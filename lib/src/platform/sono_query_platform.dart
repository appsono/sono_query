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
  Future<List<String>> getAudioFilePaths();
}
