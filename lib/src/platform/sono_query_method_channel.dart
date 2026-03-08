import 'package:flutter/services.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

class SonoQueryMethodChannel extends SonoQueryPlatform {
  final _channel = const MethodChannel('sono_query');

  @override
  Future<List<String>> getAudioFilePaths() async {
    final paths = await _channel.invokeListMethod<String>('getAudioFilePaths');
    return paths ?? [];
  }

  @override
  Future<Uint8List?> getCoverFromMediaStore(String filePath) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'getCoverFromMediaStore',
      filePath,
    );
    return bytes;
  }
}
