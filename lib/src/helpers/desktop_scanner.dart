import 'dart:io';
import 'package:path/path.dart' as p;
import 'audio_extensions.dart';

Future<List<String>> scanDirectory(String path) async {
  final dir = Directory(path);
  if (!dir.existsSync()) return [];

  return dir
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => audioExtensions.contains(p.extension(f.path).toLowerCase()))
      .map((f) => f.path)
      .toList();
}
