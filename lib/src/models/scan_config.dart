/// Conf for song scanning and artist parsing
///
/// Sorry for the long explanatory comments, but
/// since this is a public repo that will may be given away to others to work on
/// those are neccesary to ensure everyone understands everything directly.
class ScanConfig {
  /// Directories to exclude from scanning
  /// Songs whose path starts with any of these preifxes are skipped
  /// Android: MediaSTore filtering
  /// Desktop: directory walk
  final List<String> excludedPaths;

  /// Additional dir to scan (desktop only)
  /// By default only ~/Music is scanned; these are scanned too
  final List<String> additionalPaths;

  /// Minimum song duration == songs that are shorter than this are skipped
  /// Android: pushed into MediaStore WHERE clause
  /// Desktop: Applied after metadata reading
  final Duration? minDuration;

  /// Artist tag parsing conf. When non-null [Song.artists] will be
  /// populated by splitting the artist tag on given delimiters
  final ArtistParserConfig? artistParser;

  const ScanConfig({
    this.excludedPaths = const [],
    this.additionalPaths = const [],
    this.minDuration,
    this.artistParser,
  });

  /// Defalt config: no filtering, no artist parsing
  static const none = ScanConfig();
}

/// Controls how raw artist tags are split into individual artist names
class ArtistParserConfig {
  /// Delimiter strings to split on
  ///
  /// Order matters: longer/more specific delimiters should come first
  /// so that e.g. ' / ' is matched before '/'
  ///
  /// Defaults covber the most common
  final List<String> delimiters;

  /// Artist names that must never be split
  /// Example: "Tyler, The Creator"
  final List<String> excludedArtists;

  const ArtistParserConfig({
    this.delimiters = defaultDelimiters,
    this.excludedArtists = const [],
  });

  static const defaultDelimiters = [' / ', '; ', ';', ' + ', ', ', '/'];
}
