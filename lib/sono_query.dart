import 'package:sono_query/src/models/song.dart';
import 'package:sono_query/src/metadata/metadata_reader.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

export 'package:sono_query/src/models/song.dart';

class SonoQuery {
  /// Returns all songs found on the device with metadata
  static Future<List<Song>> getSongs() async {
    final paths = await SonoQueryPlatform.instance.getAudioFilePaths();
    final songs = <Song>[];

    for (final path in paths) {
      songs.add(await MetadataReader.read(path));
    }

    return songs;
  }
}
