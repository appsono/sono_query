import 'dart:typed_data';
import 'package:path/path.dart' as p;

class Song {
  final String path;
  final String title;
  final String? artist;
  final Duration? duration;
  final Uint8List? cover;
  final String? genre;
  final DateTime? releaseDate;

  const Song({
    required this.path,
    required this.title,
    this.artist,
    this.duration,
    this.cover,
    this.genre,
    this.releaseDate,
  });

  /// Fallback constructor from just a file path when metadata cant be read
  factory Song.fromPath(String filePath) {
    final filename = p.basenameWithoutExtension(filePath);
    return Song(path: filePath, title: filename);
  }

  @override
  String toString() => 'Song(title: $title, artist: $artist, path: $path)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Song && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
