import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sono_query/src/platform/sono_query_platform.dart';
import 'package:sono_query/src/helpers/desktop_scanner.dart';

class SonoQueryDesktop extends SonoQueryPlatform {
  static void registerWith() {
    SonoQueryPlatform.instance = SonoQueryDesktop();
  }

  @override
  Future<List<String>> getAudioFilePaths() async {
    final home = Platform.isLinux
        ? Platform.environment['HOME']
        : Platform.environment['USERPROFILE'];
    if (home == null) return [];
    return scanDirectory(p.join(home, 'Music'));
  }
}
