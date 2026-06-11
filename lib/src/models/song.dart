import 'dart:typed_data';
import 'package:path/path.dart' as p;

class Song {
  final String path;
  final String title;

  /// Raw artist tag as stored in metadata (may contain delimiters)
  final String? artist;

  /// Individual artist names parsed from [artist]
  ///
  /// Populated when [ScanConfig.artistParser] is set
  /// Empty list when artist parsing is disabled or [artist] is null
  final List<String> artists;

  final Duration? duration;
  final int? trackNumber;
  final Uint8List? cover;
  final String? genre;
  final DateTime? releaseDate;

  final String? album;

  /// File mtime in ms since epoch
  final int? mtimeMs;

  /// File sitz bytes
  final int? fileSize;

  const Song({
    required this.path,
    required this.title,
    this.artist,
    this.artists = const [],
    this.album,
    this.duration,
    this.trackNumber,
    this.cover,
    this.genre,
    this.releaseDate,
    this.mtimeMs,
    this.fileSize,
  });

  /// Fallback constructor from just a file path when metadata cant be read
  factory Song.fromPath(String filePath) {
    final filename = p.basenameWithoutExtension(filePath);
    return Song(path: filePath, title: filename);
  }

  /// Returns a copy with selected fields replaced
  Song copyWith({
    String? path,
    String? title,
    String? artist,
    List<String>? artists,
    String? album,
    Duration? duration,
    int? trackNumber,
    Uint8List? cover,
    String? genre,
    DateTime? releaseDate,
    int? mtimeMs,
    int? fileSize,
  }) {
    return Song(
      path: path ?? this.path,
      title: title ?? this.title,
      artist: artist ?? this.artist,
      artists: artists ?? this.artists,
      album: album ?? this.album,
      duration: duration ?? this.duration,
      trackNumber: trackNumber ?? this.trackNumber,
      cover: cover ?? this.cover,
      genre: genre ?? this.genre,
      releaseDate: releaseDate ?? this.releaseDate,
      mtimeMs: mtimeMs ?? this.mtimeMs,
      fileSize: fileSize ?? this.fileSize,
    );
  }

  @override
  String toString() =>
      'Song(title: $title, artist: $artist'
      '${artists.isNotEmpty ? ', artists: $artists' : ''}'
      ',  album: $album, duration: $duration, genre, $genre, path: $path';

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is Song && other.path == path;

  @override
  int get hashCode => path.hashCode;
}
