import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

class MetadataReader {
  static Future<Song> read(String filePath) async {
    try {
      final file = File(filePath);
      final metadata = readMetadata(file, getImage: false);

      return Song(
        path: filePath,
        title: metadata.title ?? Song.fromPath(filePath).title,
        artist: metadata.artist,
        album: metadata.artist,
        duration: metadata.duration,
        cover: null,
        genre: metadata.genres.isNotEmpty ? metadata.genres.first : null,
        releaseDate: metadata.year is DateTime
            ? metadata.year as DateTime
            : metadata.year is int
            ? DateTime(metadata.year as int)
            : null,
      );
    } catch (e) {
      print('metadata read failed for $filePath: $e');
      return Song.fromPath(filePath);
    }
  }

  static Future<Uint8List?> readCover(String filePath) async {
    try {
      final file = File(filePath);
      final metadata = readMetadata(file, getImage: true);
      if (metadata.pictures.isEmpty) return null;

      final bytes = Uint8List.fromList(metadata.pictures.first.bytes);
      if (bytes.length < 4) return null;

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

      //fallback to MediaStore on Android
      return await SonoQueryPlatform.instance.getCoverFromMediaStore(filePath);
    } catch (_) {
      return null;
    }
  }
}
