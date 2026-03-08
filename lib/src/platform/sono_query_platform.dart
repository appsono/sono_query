import 'package:plugin_platform_interface/plugin_platform_interface.dart';

abstract class SonoQueryPlatform extends PlatformInterface {
  SonoQueryPlatform() : super(token: _token);

  static final Object _token = Object();

  static SonoQueryPlatform? _instance;

  static SonoQueryPlatform get instance {
    if (_instance == null) {
      throw UnimplementedError('SonoQueryPlatform has not been set');
    }
    return _instance!;
  }

  static set instance(SonoQueryPlatform instance) {
    PlatformInterface.verify(instance, _token);
    _instance = instance;
  }

  /// Returns a list of audio file paths on device
  Future<List<String>> getAudioFilePaths();
}
