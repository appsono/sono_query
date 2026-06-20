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
    try {
      final result = await _channel.invokeListMethod<Map>(
        'getSongsWithMetadata',
        <String, dynamic>{
          'minDurationMs': minDuration?.inMilliseconds,
          'excludedPaths': excludedPaths,
        },
      );
      return result?.map((m) => Map<String, dynamic>.from(m)).toList();
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<Uint8List?> getCoverFromMediaStore(String filePath) async {
    final bytes = await _channel.invokeMethod<Uint8List>(
      'getCoverFromMediaStore',
      filePath,
    );
    return bytes;
  }

  @override
  Future<Uint8List?> getCoverThumbnail(String filePath, int maxDim) {
    return _channel.invokeMethod<Uint8List>('getCoverThumbnail', {
      'path': filePath,
      'maxDim': maxDim,
    });
  }

  @override
  Future<void> rescanFile(String filePath) async {
    await _channel.invokeMethod<void>('rescanFile', filePath);
  }

  @override
  Future<String?> resolveContentUri(String path) async {
    return _channel.invokeMethod<String>('resolveContentUri', {'path': path});
  }

  @override
  Future<String> copyToAppCache(String path) async {
    final result = await _channel.invokeMethod<String>('copyToAppCache', {
      'path': path,
    });
    if (result == null) {
      throw StateError('copyToAppCache returned null for $path');
    }
    return result;
  }

  @override
  Future<bool> commitFromCache(String cachePath, String originalPath) async {
    final result = await _channel.invokeMethod<bool>('commitFromCache', {
      'cachePath': cachePath,
      'originalPath': originalPath,
    });
    return result ?? false;
  }
}
