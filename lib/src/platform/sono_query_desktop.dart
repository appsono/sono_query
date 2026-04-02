import 'dart:io';
import 'package:path/path.dart' as p;
import 'package:sono_query/src/platform/sono_query_platform.dart';
import 'package:sono_query/src/helpers/desktop_scanner.dart';

class SonoQueryDesktop extends SonoQueryPlatform {
  static void registerWith() {
    SonoQueryPlatform.instance = SonoQueryDesktop();
  }

  @override
  Future<List<String>> getAudioFilePaths({
    List<String> additionalPaths = const [],
    List<String> excludedPaths = const [],
    void Function(String path)? onDiscover,
  }) async {
    final home = Platform.isLinux
        ? Platform.environment['HOME']
        : Platform.environment['USERPROFILE'];
    if (home == null) return [];
    final roots = [p.join(home, 'Music'), ...additionalPaths];
    return scanDirectories(
      roots,
      excludedPaths: excludedPaths,
      onDiscover: onDiscover,
    );
  }
}
