import 'package:sono_query/src/models/scan_config.dart';

/// Splits raw artist tag strings into individual artist names
class ArtistParser {
  ArtistParser._();

  /// Parse a raw artist string into a list of individual artist names
  ///
  /// Returns a single element list with trimmed input, when:
  /// - [raw] is null or blank
  /// - no delimiters match
  /// - [config] is null
  static List<String> parse(String? raw, [ArtistParserConfig? config]) {
    if (raw == null || raw.trim().isEmpty) return [];
    if (config == null) return [raw.trim()];

    //1. protect excluded artist names by replacing them with
    //placeholder tokens before doing any splitting
    final placeholders = <String, String>{};
    var working = raw;

    for (var i = 0; i < config.excludedArtists.length; i++) {
      final excluded = config.excludedArtists[i];
      if (excluded.isEmpty) continue;

      final token = '\x00EXCL$i\x00';
      //case insensitive find and replace, preserving original casing
      var searchForm = 0;
      while (true) {
        final idx = working.toLowerCase().indexOf(
          excluded.toLowerCase(),
          searchForm,
        );
        if (idx == -1) break;

        //dont match if preceded by an escape backlash
        if (idx > 0 && working[idx - 1] == r'\') {
          searchForm = idx + excluded.length;
          continue;
        }

        final original = working.substring(idx, idx + excluded.length);
        placeholders[token] = original;
        working =
            working.substring(0, idx) +
            token +
            working.substring(idx + excluded.length);
        searchForm = idx + token.length;
      }
    }

    //2. process escapes sequences: \x > literal x
    final buffer = StringBuffer();
    final escapePositions = <int>[];
    var i = 0;
    while (i < working.length) {
      if (working[i] == r'\' && i + 1 < working.length) {
        //only process when outside of a placeholder token
        if (!_insidePlaceholder(working, i)) {
          escapePositions.add(buffer.length);
          buffer.write(working[i + 1]);
          i += 2;
          continue;
        }
      }
      buffer.write(working[i]);
      i++;
    }

    var processed = buffer.toString();

    //3. build a mask of protected character positions
    //so that delimiter matches overlapping those positions are skipped
    final protectedPositions = Set<int>.from(escapePositions);

    //4. split on delimiters => longest first to avoid partial matches
    final sorted = List<String>.from(config.delimiters)
      ..sort((a, b) => b.length.compareTo(a.length));

    final parts = _splitWithProtection(processed, sorted, protectedPositions);

    //5. restore placeholder and trim
    final results = <String>[];
    for (final part in parts) {
      var restored = part;
      for (final entry in placeholders.entries) {
        restored = restored.replaceAll(entry.key, entry.value);
      }
      final trimmed = restored.trim();
      if (trimmed.isNotEmpty) results.add(trimmed);
    }

    return results.isEmpty ? [raw.trim()] : results;
  }

  /// Splits [input] on any of [delimiters], skipping matches that
  /// overlap [protectedPositions]
  static List<String> _splitWithProtection(
    String input,
    List<String> delimiters,
    Set<int> protectedPositions,
  ) {
    if (delimiters.isEmpty) return [input];

    final parts = <String>[];
    var lastSplit = 0;
    var i = 0;

    while (i < input.length) {
      //check if any delimiter matches at pos 1
      String? matched;
      for (final delim in delimiters) {
        if (i + delim.length > input.length) continue;
        if (input.substring(i, i + delim.length) == delim) {
          //check none of the positions in this match are protected
          var isProtected = false;
          for (var j = i; j < i + delim.length; j++) {
            if (protectedPositions.contains(j)) {
              isProtected = true;
              break;
            }
          }
          if (!isProtected) {
            matched = delim;
            break;
          }
        }
      }

      if (matched != null) {
        parts.add(input.substring(lastSplit, i));
        i += matched.length;
        lastSplit = i;
      } else {
        i++;
      }
    }
    parts.add(input.substring(lastSplit, i));
    return parts;
  }

  /// Returns true if position [i] falls inside a placeholder token
  static bool _insidePlaceholder(String s, int i) {
    //quick check: is there a \x00 before and after this position?
    final before = s.lastIndexOf('\x00', i);
    if (before == -1) return false;
    final after = s.indexOf('\x00', i);
    if (after == -1) return false;
    //verify it looks like placeholder pattern
    return before < i && after > i;
  }
}
