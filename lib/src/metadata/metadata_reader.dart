import 'dart:io';
import 'dart:typed_data';
import 'package:audio_metadata_reader/audio_metadata_reader.dart';
import 'package:sono_query/src/models/song.dart';

class MetadataReader {
  static Future<Song> read(String filePath) async {
    try {
      final file = File(filePath);
      final metadata = readMetadata(file, getImage: true);

      return Song(
        path: filePath,
        title: metadata.title ?? Song.fromPath(filePath).title,
        artist: metadata.artist,
        duration: metadata.duration,
        cover: metadata.pictures.isNotEmpty
            ? Uint8List.fromList(metadata.pictures.first.bytes)
            : null,
        genre: metadata.genres.isNotEmpty ? metadata.genres.first : null,
        releaseDate: metadata.year != null
            ? DateTime(metadata.year! as int)
            : null,
      );
    } catch (_) {
      return Song.fromPath(filePath);
    }
  }
}
