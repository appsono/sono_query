import 'dart:io';
import 'package:path/path.dart' as p;
import 'audio_extensions.dart';

Future<List<String>> scanDirectory(String path) async {
  final dir = Directory(path);
  if (!await dir.exists()) return [];

  final paths = <String>[];
  await for (final entity in dir.list(recursive: true)) {
    if (entity is File &&
        audioExtensions.contains(p.extension(entity.path.toLowerCase()))) {
      paths.add(entity.path);
    }
  }
  return paths;
}
