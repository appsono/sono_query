import 'dart:isolate';
import 'dart:typed_data';

import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/metadata/metadata_reader.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

export 'package:sono_query/src/models/song.dart';
export 'package:sono_query/src/metadata/metadata_reader.dart';

class SonoQuery {
  /// Returns all songs found on device with metadata
  ///
  /// On Android > metadata comes from MediaStore
  /// On desktop, iOS > files are read in background isolate (avoids blocking main thread)
  static Future<List<Song>> getSongs() async {
    final platformSongs = await SonoQueryPlatform.instance
        .getSongsWithMetadata();

    if (platformSongs != null) {
      return platformSongs.map(_songFromMap).toList();
    }

    //fallback to read metadata from files
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();
    return Isolate.run(() => _readAllMetadata(paths));
  }

  /// Stream variant: emit songs as they become available
  ///
  /// On Android > all songs are emitted at once
  /// On desktop/iOS > songs are emitted in batches
  static Stream<Song> getSongsStream() async* {
    final platformSongs = await SonoQueryPlatform.instance
        .getSongsWithMetadata();

    if (platformSongs != null) {
      for (final map in platformSongs) {
        yield _songFromMap(map);
      }
      return;
    }

    //fallback: batch-read in isolate => yield results
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();
    final songs = await Isolate.run(() => _readAllMetadata(paths));
    for (final song in songs) {
      yield song;
    }
  }

  static Future<Uint8List?> getCover(String filePath) async {
    return MetadataReader.readCover(filePath);
  }

  /// Returns map of file path > genre name
  ///
  /// On Android: genre is already included in getSong() for all API levels
  /// This method is mainly useful for desktop/iOS where it reads genre tags
  /// from files
  static Future<Map<String, String>> getGenres() async {
    //MediaStore genre tables
    final platformGenres = await SonoQueryPlatform.instance.getGenres();
    if (platformGenres != null) return platformGenres;

    //fallback: read genre from file metadata
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();
    return Isolate.run(() => _readAllGenres(paths));
  }

  /// Convert platfrom metadata map to Song
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

  /// Reads metadata for all paths synchronously
  /// in. a. background. isolate. :)
  static List<Song> _readAllMetadata(List<String> paths) {
    return paths.map((p) => MetadataReader.readSync(p)).toList();
  }

  /// Reads only genre tags from files
  /// again in a background isolate
  static Map<String, String> _readAllGenres(List<String> paths) {
    final genres = <String, String>{};
    for (final path in paths) {
      final genre = MetadataReader.readGenreSync(path);
      if (genre != null) genres[path] = genre;
    }
    return genres;
  }
}
