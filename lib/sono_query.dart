import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:sono_query/src/helpers/artist_parser.dart';
import 'package:sono_query/src/models/scan_config.dart';
import 'package:sono_query/src/models/scan_progress.dart';
import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/metadata/metadata_reader.dart';
import 'package:audio_metadata_reader/audio_metadata_reader.dart' show Picture;
import 'package:sono_query/src/platform/sono_query_platform.dart';

export 'package:sono_query/src/models/song.dart';
export 'package:sono_query/src/metadata/metadata_reader.dart';
export 'package:sono_query/src/platform/sono_query_desktop.dart';
export 'package:sono_query/src/models/scan_config.dart';
export 'package:sono_query/src/models/scan_progress.dart';
export 'package:sono_query/src/helpers/artist_parser.dart';
export 'package:audio_metadata_reader/audio_metadata_reader.dart'
    show Picture, PictureType;
export 'package:sono_query/src/platform/sono_query_platform.dart';

/// Callback for files that failed metadata reading
/// Receives file path and the error that occurred
typedef ScanErrorCallback = void Function(String path, Object error);

class SonoQuery {
  /// Canoncal file fingerprint (used by scan skip)
  /// App stores this per song and passes the path => fingerprint map
  /// back via [getSongsStream]s knownFingerprints paramter
  static String fingerprint(int mtimeMs, int size) => '$mtimeMs:$size';

  /// Default batch size for streaming metadata reads
  static const _defaultBatchSize = 50;

  /// Returns all songs found on device with metadata
  ///
  ///
  /// [config] controls filtering (excluded/additional paths, min duration)
  /// and artist tag parsing
  ///
  /// [onProgress] is called periodically with a [ScanProgress] snapshot
  ///
  /// [onError] is called for each file that fails metadata reading
  /// File is skipped and scanning continues
  ///
  /// On Android: metadata comes from MediaStore in one query
  /// On desktop/iOS: files are discovered, then read in background
  /// isolate (avoids blocking main thread)
  static Future<List<Song>> getSongs({
    ScanConfig config = ScanConfig.none,
    ScanProgressCallback? onProgress,
    ScanErrorCallback? onError,
  }) async {
    final platformSongs = await SonoQueryPlatform.instance.getSongsWithMetadata(
      minDuration: config.minDuration,
      excludedPaths: config.excludedPaths,
    );

    if (platformSongs != null) {
      onProgress?.call(
        ScanProgress(
          total: platformSongs.length,
          completed: 0,
          phase: ScanPhase.reading,
        ),
      );

      final songs = <Song>[];
      for (var i = 0; i < platformSongs.length; i++) {
        songs.add(_songFromMap(platformSongs[i], config.artistParser));
        if (onProgress != null &&
            (i % 100 == 0 || i == platformSongs.length - 1)) {
          onProgress(
            ScanProgress(
              total: platformSongs.length,
              completed: i + 1,
              phase: i == platformSongs.length - 1
                  ? ScanPhase.done
                  : ScanPhase.reading,
            ),
          );
        }
      }
      return songs;
    }

    //fallback: discover files then read metadata in isolate
    onProgress?.call(
      const ScanProgress(total: 0, completed: 0, phase: ScanPhase.discovering),
    );

    final paths = await SonoQueryPlatform.instance.getAudioFilePaths(
      additionalPaths: config.additionalPaths,
      excludedPaths: config.excludedPaths,
    );

    onProgress?.call(
      ScanProgress(total: paths.length, completed: 0, phase: ScanPhase.reading),
    );

    final results = await Isolate.run(() => _readAllMetadata(paths));

    final songs = <Song>[];
    for (var i = 0; i < results.length; i++) {
      final result = results[i];
      if (result.error != null) {
        onError?.call(result.path, result.error!);
      } else {
        var song = result.song!;

        //apply min dur filter (desktop/iOS)
        if (config.minDuration != null &&
            song.duration != null &&
            song.duration! < config.minDuration!) {
          continue;
        }

        //apply artist parsing
        if (config.artistParser != null) {
          song = song.copyWith(
            artists: ArtistParser.parse(song.artist, config.artistParser),
          );
        }
        songs.add(song);
      }

      if (onProgress != null && (i % 50 == 0 || i == results.length - 1)) {
        onProgress(
          ScanProgress(
            total: results.length,
            completed: i + 1,
            currentPath: result.path,
            phase: i == results.length - 1 ? ScanPhase.done : ScanPhase.reading,
          ),
        );
      }
    }
    return songs;
  }

  /// Stream variant: emits songs as they become available
  ///
  /// On Android: all songs are emitted at once
  /// On desktop/iOS: songs are emitted in batches of [batchSize]
  ///
  /// [config] controls filtering and artist parsing
  /// [onProgress] is called periodically with scan progress
  /// [onError] is called for each file that fails metadata reading
  static Stream<Song> getSongsStream({
    int batchSize = _defaultBatchSize,
    ScanConfig config = ScanConfig.none,
    Map<String, String>? knownFingerprints,
    void Function(List<String> paths)? onUnchanged,
    ScanProgressCallback? onProgress,
    ScanErrorCallback? onError,
  }) async* {
    final platformSongs = await SonoQueryPlatform.instance.getSongsWithMetadata(
      minDuration: config.minDuration,
      excludedPaths: config.excludedPaths,
    );

    if (platformSongs != null) {
      //MediaStore has no year for Vorbis-comment files, read tag instead
      final needYear = <String>[
        for (final m in platformSongs)
          if (m['year'] == null && _needsYearFallback(m['path'] as String))
            m['path'] as String,
      ];
      final fallbackYears = needYear.isEmpty
          ? const <String, DateTime>{}
          : await Isolate.run(() => _readReleaseDates(needYear));
      for (var i = 0; i < platformSongs.length; i++) {
        final song = _songFromMap(platformSongs[i], config.artistParser);
        final fallback = fallbackYears[song.path];
        yield fallback == null ? song : song.copyWith(releaseDate: fallback);
        if (onProgress != null &&
            (i % 100 == 0 || i == platformSongs.length - 1)) {
          onProgress(
            ScanProgress(
              total: platformSongs.length,
              completed: i + 1,
              phase: i == platformSongs.length - 1
                  ? ScanPhase.done
                  : ScanPhase.reading,
            ),
          );
        }
      }
      return;
    }

    //fallback: discover files then batch-read in isolate
    onProgress?.call(
      const ScanProgress(total: 0, completed: 0, phase: ScanPhase.discovering),
    );

    final paths = await SonoQueryPlatform.instance.getAudioFilePaths(
      additionalPaths: config.additionalPaths,
      excludedPaths: config.excludedPaths,
    );

    //skip unchanged files by mtime+size fingerprint; stat work runs in an isolate
    var toRead = paths;
    var processed = 0;
    if (knownFingerprints != null && knownFingerprints.isNotEmpty) {
      final known = knownFingerprints;
      final parts = await Isolate.run(
        () => _partitionByFingerprint(paths, known),
      );
      toRead = parts.changed;
      processed = parts.unchanged.length;
      if (parts.unchanged.isNotEmpty) onUnchanged?.call(parts.unchanged);
    }

    onProgress?.call(
      ScanProgress(
        total: paths.length,
        completed: processed,
        phase: toRead.isEmpty ? ScanPhase.done : ScanPhase.reading,
      ),
    );

    for (var i = 0; i < toRead.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, toRead.length);
      final batch = paths.sublist(i, end);
      final results = await Isolate.run(() => _readAllMetadata(batch));

      for (final result in results) {
        processed++;
        if (result.error != null) {
          onError?.call(result.path, result.error!);
        } else {
          var song = result.song!;

          //apply min duration filter
          if (config.minDuration != null &&
              song.duration != null &&
              song.duration! < config.minDuration!) {
            continue;
          }

          //apply artist parsing
          if (config.artistParser != null) {
            song = song.copyWith(
              artists: ArtistParser.parse(song.artist, config.artistParser),
            );
          }
          yield song;
        }

        if (onProgress != null &&
            (processed % 50 == 0 || processed == paths.length)) {
          onProgress(
            ScanProgress(
              total: paths.length,
              completed: processed,
              currentPath: result.path,
              phase: processed == paths.length
                  ? ScanPhase.done
                  : ScanPhase.reading,
            ),
          );
        }
      }
    }
  }

  /// Read cover art for single file
  ///
  /// Tries embedded metadata first, validates magic bytes,
  /// then falls back to MediaStore on Android
  static Future<Uint8List?> getCover(String filePath) async {
    return MetadataReader.readCover(filePath);
  }

  /// Downscale cover art for thumbnails
  ///
  /// On Android tries MediaStore thumbnails first (Q+), then a
  /// subsampled native decode of embedded tag picture (all API
  /// levels, including files MediaStore does not index)
  /// Returns null on other platforms so callers can fall back to [getCover]
  static Future<Uint8List?> getCoverThumbnail(
    String filePath, {
    int maxDim = 512,
  }) {
    return SonoQueryPlatform.instance.getCoverThumbnail(filePath, maxDim);
  }

  /// Update tags on a song file. Returns false if format is non-writeable
  /// (OGG, Opus, AIFF, APE) or write failed. Trigger MediaStore rescan
  /// on Android
  static Future<bool> updateTags(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    DateTime? year,
    List<String>? genres,
    List<Picture>? pictures,
  }) async {
    final ok = MetadataReader.writeSync(
      filePath,
      title: title,
      artist: artist,
      album: album,
      trackNumber: trackNumber,
      year: year,
      genres: genres,
      pictures: pictures,
    );
    if (ok) {
      await SonoQueryPlatform.instance.rescanFile(filePath);
    }
    return ok;
  }

  /// Maps MediaStore _ID to file path, for migrating old Sono data
  static Future<Map<int, String>> resolveMediaStoreIds(List<int> ids) =>
      SonoQueryPlatform.instance.resolveMediaStoreIds(ids);

  /// Maps MediaStore ALBUM_ID to one member song path
  static Future<Map<int, String>> resolveMediaStoreAlbumIds(
    List<int> albumIds,
  ) => SonoQueryPlatform.instance.resolveMediaStoreAlbumIds(albumIds);

  /// Convert platform metadata map to Song, optionally parsing artists
  static Song _songFromMap(
    Map<String, dynamic> map, [
    ArtistParserConfig? artistParser,
  ]) {
    final path = map['path'] as String;
    final durationMs = map['duration'] as int?;
    final year = map['year'] as int?;
    final rawArtist = map['artist'] as String?;

    return Song(
      path: path,
      title: (map['title'] as String?) ?? Song.fromPath(path).title,
      artist: map['artist'] as String?,
      artists: artistParser != null
          ? ArtistParser.parse(rawArtist, artistParser)
          : const [],
      album: map['album'] as String?,
      duration: durationMs != null && durationMs > 0
          ? Duration(milliseconds: durationMs)
          : null,
      trackNumber: map['track'] as int?,
      cover: null,
      genre: map['genre'] as String?,
      releaseDate: year != null && year > 0 ? DateTime(year) : null,
      mtimeMs: map['mtimeMs'] as int?,
      fileSize: map['size'] as int?,
    );
  }

  /// Reads metadata for all paths, returning results with error info
  /// Runs synchronously inside background isolate
  static List<_ScanResult> _readAllMetadata(List<String> paths) {
    return paths.map((p) {
      try {
        return _ScanResult(path: p, song: MetadataReader.readSync(p));
      } catch (e) {
        return _ScanResult(path: p, error: e);
      }
    }).toList();
  }

  /// Formats MediaStore does not index a year for
  static const _yearFallbackExtensions = {'.flac', '.ogg', '.oppus', '.ape'};

  static bool _needsYearFallback(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return false;
    return _yearFallbackExtensions.contains(path.substring(dot).toLowerCase());
  }

  /// Runs synchronously inside background isolate
  static Map<String, DateTime> _readReleaseDates(List<String> paths) {
    final out = <String, DateTime>{};
    for (final path in paths) {
      final date = MetadataReader.readReleaseDateSync(path);
      if (date != null) out[path] = date;
    }
    return out;
  }

  /// Splits paths into changed (need metadata read) and unchanged
  /// (fingerprint matches stored one). Runs in background isolate
  static ({List<String> changed, List<String> unchanged})
  _partitionByFingerprint(List<String> paths, Map<String, String> known) {
    final changed = <String>[];
    final unchanged = <String>[];
    for (final path in paths) {
      final expected = known[path];
      if (expected == null) {
        changed.add(path);
        continue;
      }
      try {
        final stat = File(path).statSync();
        final fp = fingerprint(stat.modified.millisecondsSinceEpoch, stat.size);
        (fp == expected ? unchanged : changed).add(path);
      } catch (_) {
        changed.add(path);
      }
    }
    return (changed: changed, unchanged: unchanged);
  }
}

class _ScanResult {
  final String path;
  final Song? song;
  final Object? error;

  const _ScanResult({required this.path, this.song, this.error});
}
