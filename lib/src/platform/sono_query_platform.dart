import 'dart:typed_data';

import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:sono_query/src/platform/sono_query_method_channel.dart';

abstract class SonoQueryPlatform extends PlatformInterface {
  SonoQueryPlatform() : super(token: _token);

  static final Object _token = Object();

  static SonoQueryPlatform? _instance;

  static SonoQueryPlatform get instance {
    _instance ??= SonoQueryMethodChannel();
    return _instance!;
  }

  static set instance(SonoQueryPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  Future<Uint8List?> getCoverFromMediaStore(String filePath) {
    throw UnimplementedError();
  }

  /// Returns a list of audio file paths on device
  ///
  /// [additionalPaths] > extra dirs to scan (desktop only)
  /// [onDiscover] > called once per found file => for progress reporting
  Future<List<String>> getAudioFilePaths({
    List<String> additionalPaths = const [],
    List<String> excludedPaths = const [],
    void Function(String path)? onDiscover,
  });

  /// Returns song with metadata from MediaStore
  /// Return null if not supported == dart-based reading
  ///
  /// [minDuration] > skip songs shorter than this
  /// [excludedPaths] > skip songs whose path starts with any prefix
  Future<List<Map<String, dynamic>>?> getSongsWithMetadata({
    Duration? minDuration,
    List<String> excludedPaths = const [],
  }) async => null;

  /// Returns map of file path => genre from MediaStore
  /// Returns null if not supported
  Future<Map<String, String>?> getGenres() async => null;
}
