import 'dart:io';
import 'package:path/path.dart' as p;
import 'audio_extensions.dart';

Future<List<String>> scanDirectories(
  List<String> paths, {
  List<String> excludedPaths = const [],
  void Function(String path)? onDiscover,
}) async {
  final results = <String>[];
  final normalized = excludedPaths
      .map((e) => e.endsWith('/') ? e : '$e/')
      .toList();

  for (final root in paths) {
    final dir = Directory(root);
    if (!await dir.exists()) continue;

    await for (final entity in dir.list(recursive: true)) {
      if (entity is! File) continue;
      if (!audioExtensions.contains(p.extension(entity.path.toLowerCase()))) {
        continue;
      }

      //check exclusions
      if (normalized.any((ex) => entity.path.startsWith(ex))) continue;

      onDiscover?.call(entity.path);
      results.add(entity.path);
    }
  }
  return results;
}

/// Legacy single-dir variant
Future<List<String>> scanDirectory(String path) => scanDirectories([path]);
