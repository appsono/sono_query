import 'dart:io';
import 'dart:typed_data';
import 'package:path/path.dart' as p;
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/helpers/audio_extensions.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

class MetadataReader {
  static Song readSync(String filePath) {
    try {
      final file = File(filePath);
      final stat = file.statSync();
      final metadata = readMetadata(file, getImage: false);

      return Song(
        path: filePath,
        title: metadata.title ?? Song.fromPath(filePath).title,
        artist: metadata.artist,
        album: metadata.album,
        duration: metadata.duration,
        trackNumber: metadata.trackNumber,
        cover: null,
        genre: metadata.genres.isNotEmpty ? metadata.genres.first : null,
        releaseDate: metadata.year is DateTime
            ? metadata.year as DateTime
            : metadata.year is int
            ? DateTime(metadata.year as int)
            : null,
        mtimeMs: stat.modified.millisecondsSinceEpoch,
        fileSize: stat.size,
      );
    } catch (e) {
      return Song.fromPath(filePath);
    }
  }

  /// Async one (for backwards compatibility aka dont use!)
  static Future<Song> read(String filePath) async {
    return readSync(filePath);
  }

  /// Reads only the genre tag from a file
  /// Used on desktop/iOS genre backfill
  static String? readGenreSync(String filePath) {
    try {
      final file = File(filePath);
      final metadata = readMetadata(file, getImage: false);
      return metadata.genres.isNotEmpty ? metadata.genres.first : null;
    } catch (_) {
      return null;
    }
  }

  static Future<Uint8List?> readCover(String filePath) async {
    try {
      final file = File(filePath);
      final metadata = readMetadata(file, getImage: true);

      if (metadata.pictures.isNotEmpty) {
        final bytes = Uint8List.fromList(metadata.pictures.first.bytes);
        if (bytes.length >= 4) {
          //check for JPEG or PNG magic bytes
          final isJpeg = bytes[0] == 0xFF && bytes[1] == 0xD8;
          final isPng = bytes[0] == 0x89 && bytes[1] == 0x50;
          final isWebp =
              bytes.length > 11 &&
              bytes[0] == 0x52 &&
              bytes[1] == 0x49 &&
              bytes[2] == 0x46 &&
              bytes[3] == 0x46; // RIFF
          if (isJpeg || isPng || isWebp) return bytes;
        }
      }

      //fallback to MediaStore on Android
      return await SonoQueryPlatform.instance.getCoverFromMediaStore(filePath);
    } catch (_) {
      return null;
    }
  }

  static bool canWrite(String filePath) =>
      writeableExtensions.contains(p.extension(filePath).toLowerCase());

  /// Update tags. Returns false if format is non-writeable or write throws
  /// Pass null to leave a field empty. Rewrites file in place
  static bool writeSync(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    DateTime? year,
    List<String>? genres,
    List<Picture>? pictures,
  }) {
    if (!canWrite(filePath)) return false;
    try {
      updateMetadata(File(filePath), (m) {
        if (title != null) m.setTitle(title);
        if (artist != null) m.setArtist(artist);
        if (album != null) m.setAlbum(album);
        if (trackNumber != null) m.setTrackNumber(trackNumber);
        if (year != null) m.setYear(year);
        if (genres != null) m.setGenres(genres);
        if (pictures != null) m.setPictures(pictures);
      });
      return true;
    } catch (e, st) {
      print('sono_query writeSync failed for $filePath: $e\n$st');
      return false;
    }
  }

  /// Updated tags asynchronously, handling android scoped storage
  ///
  /// retunrs false if format is unsupported, permission is denied, or
  /// an IO operation fails
  ///
  /// pass null to leave a field unchanged
  static Future<bool> writeAsync(
    String filePath, {
    String? title,
    String? artist,
    String? album,
    int? trackNumber,
    DateTime? year,
    List<String>? genres,
    List<Picture>? pictures,
  }) async {
    if (!canWrite(filePath)) return false;

    //non-android platforms: writeSync writes directly with no permission gate
    if (!Platform.isAndroid) {
      return writeSync(
        filePath,
        title: title,
        artist: artist,
        album: album,
        trackNumber: trackNumber,
        year: year,
        genres: genres,
        pictures: pictures,
      );
    }

    //android: copy > writeSync(scratch) > commit
    String? cachePath;
    try {
      cachePath = await SonoQueryPlatform.instance.copyToAppCache(filePath);

      final wroteScratch = writeSync(
        cachePath,
        title: title,
        artist: artist,
        album: album,
        trackNumber: trackNumber,
        year: year,
        genres: genres,
        pictures: pictures,
      );
      if (!wroteScratch) {
        print('writeAsync: writeSync on cache copy failed for $filePath');
        return false;
      }

      final committed = await SonoQueryPlatform.instance.commitFromCache(
        cachePath,
        filePath,
      );
      return committed;
    } catch (e, st) {
      print('writeAsync failed for $filePath: $e\n$st');
      return false;
    } finally {
      if (cachePath != null) {
        try {
          File(cachePath).deleteSync();
        } catch (_) {
          //best effort cleanup, ignore errors
        }
      }
    }
  }
}
