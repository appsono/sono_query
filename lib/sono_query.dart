import 'dart:isolate';
import 'dart:typed_data';

import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/metadata/metadata_reader.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

export 'package:sono_query/src/models/song.dart';
export 'package:sono_query/src/metadata/metadata_reader.dart';
export 'package:sono_query/src/platform/sono_query_desktop.dart';

/// Callback for files that failed metadta reading
/// Receives file path and the error that occured
typedef ScanErrorCallback = void Function(String path, Object error);

class SonoQuery {
  /// Default batch size for streaming metadata reads
  static const _defaultBatchSize = 50;

  /// Returns all songs foud on device with metadata
  ///
  /// On Android: metadata comes from MediaStore in one query
  /// On desktop/iOS: files are discovered, then read in background
  /// isolate (avoids blocking main thread)
  ///
  /// [onError] is called for each file that fails metadata reading
  /// File is skipped and scanning continues
  static Future<List<Song>> getSongs({ScanErrorCallback? onError}) async {
    final platformSongs = await SonoQueryPlatform.instance
        .getSongsWithMetadata();

    if (platformSongs != null) {
      return platformSongs.map(_songFromMap).toList();
    }

    //fallback: read metadata from files
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();
    final results = await Isolate.run(() => _readAllMetadata(paths));

    final songs = <Song>[];
    for (final result in results) {
      if (result.error != null) {
        onError?.call(result.path, result.error!);
      } else {
        songs.add(result.song!);
      }
    }
    return songs;
  }

  /// Stream variant: emits songs as they become available
  ///
  /// On Android: all songs are emitted at once
  /// On desktop/iOS: songs are emitted in batches of [batchSize]
  ///
  /// [OnError] is called for each file that fails metadata reading
  static Stream<Song> getSongsStream({
    int batchSize = _defaultBatchSize,
    ScanErrorCallback? onError,
  }) async* {
    final platformSongs = await SonoQueryPlatform.instance
        .getSongsWithMetadata();

    if (platformSongs != null) {
      for (final map in platformSongs) {
        yield _songFromMap(map);
      }
      return;
    }

    //fallback: batch-read in isolate, yield per batch
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();

    for (var i = 0; i < paths.length; i += batchSize) {
      final end = (i + batchSize).clamp(0, paths.length);
      final batch = paths.sublist(i, end);
      final results = await Isolate.run(() => _readAllMetadata(batch));

      for (final result in results) {
        if (result.error != null) {
          onError?.call(result.path, result.error!);
        } else {
          yield result.song!;
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

  /// Convert platform metadata map to Song
  static Song _songFromMap(Map<String, dynamic> map) {
    final path = map['path'] as String;
    final durationMs = map['duration'] as int?;
    final year = map['year'] as int?;

    return Song(
      path: path,
      title: (map['title'] as String?) ?? Song.fromPath(path).title,
      artist: map['artist'] as String?,
      album: map['album'] as String?,
      duration: durationMs != null && durationMs > 0
          ? Duration(milliseconds: durationMs)
          : null,
      cover: null,
      genre: map['genre'] as String?,
      releaseDate: year != null && year > 0 ? DateTime(year) : null,
    );
  }

  /// Reads metadata for all paths, returniong results with error info
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
}

class _ScanResult {
  final String path;
  final Song? song;
  final Object? error;

  const _ScanResult({required this.path, this.song, this.error});
}
