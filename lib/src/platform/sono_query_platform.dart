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

  /// Downscaled cover from native thumbnail source, or null when
  /// platform has none. Android Q+ only
  Future<Uint8List?> getCoverThumbnail(String filePath, int maxDim) async =>
      null;

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

  Future<void> rescanFile(String filePath) async {}

  /// Returns MediaStore content URI for [path], or null if file is
  /// not indexed (e.g, just downloadd, not yet scanned)
  ///
  /// Android only. Returns null on other platforms
  Future<String?> resolveContentUri(String path) async => null;

  /// Copies file at [path] into apps private cache dir and
  /// returns cached files absolute path. Caller is responsible for
  /// deleting cache file when done
  ///
  /// On Android: prefers direc file read when file is in apps own scope
  /// otherwise falls bac to ContentResolver
  ///
  /// Android only. Throws UnsupporedError on other platforms
  Future<String> copyToAppCache(String path) async {
    throw UnsupportedError('copyToAppCache is Android-only');
  }

  /// Wites bytes at [cachePath] back to [originalPath]
  ///
  /// On Android (11+): triggers system "Allow Sono to modify this audio file"
  /// dialog. returns true on success (user granted + write completed),
  /// false if user denied. throws IO errors
  ///
  /// also notifies MediaScanner on success so other apps see new tags
  ///
  /// Android only. Throw UnsupportedError on other platforms
  Future<bool> commitFromCache(String cachePath, String originalPath) async {
    throw UnsupportedError('commitFromCache is Android-only');
  }

  /// Maps MediaStore _ID to a file path
  ///
  /// Old Sono stored song references as MediaStore ids, so migrating
  /// data needs this pass first. Ids that are no longer indexed are
  /// absent from result rather than mapped to null
  ///
  /// Android only, returns an empty map elsewhere
  Future<Map<int, String>> resolveMediaStoreIds(List<int> ids) async => {};

  /// Maps MediaStore ALBUM_ID to path of one member song
  ///
  /// Picks lowest track number, so repeated calls agree with each other
  /// Android only, return an empty map elsewhere
  Future<Map<int, String>> resolveMediaStoreAlbumIds(
    List<int> albumIds,
  ) async => {};
}
