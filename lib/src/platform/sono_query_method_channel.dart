import 'package:flutter/services.dart';
import 'package:sono_query/src/platform/sono_query_platform.dart';

class SonoQueryMethodChannel extends SonoQueryPlatform {
  final _channel = const MethodChannel('sono_query');

  @override
  Future<List<String>> getAudioFilePaths({
    List<String> additionalPaths = const [],
    List<String> excludedPaths = const [],
    void Function(String path)? onDiscover,
  }) async {
    final paths = await _channel.invokeListMethod<String>('getAudioFilePaths');
    return paths ?? [];
  }

  @override
  Future<List<Map<String, dynamic>>?> getSongsWithMetadata({
    Duration? minDuration,
    List<String> excludedPaths = const [],
  }) async {
    final result = await _channel.invokeListMethod<Map>(
      'getSongsWithMetadata',
      <String, dynamic>{
        'minDurationMs': minDuration?.inMilliseconds,
        'excludedPaths': excludedPaths,
      },
    );
    return result?.map((m) => Map<String, dynamic>.from(m)).toList();
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
