import 'package:flutter_test/flutter_test.dart';
import 'package:sono_query/sono_query.dart';
import 'package:sono_query/src/helpers/artist_parser.dart';
import 'package:sono_query/src/models/scan_config.dart';
import 'package:sono_query/src/models/scan_progress.dart';

void main() {
  group('ArtistParser', () {
    const defaultConfig = ArtistParserConfig();

    group('basic splitting', () {
      test('splits on slash with spaces', () {
        final result = ArtistParser.parse('Artist1 / Artist2', defaultConfig);
        expect(result, ['Artist1', 'Artist2']);
      });

      test('splits on bare slash', () {
        final result = ArtistParser.parse('Artist1/Artist2', defaultConfig);
        expect(result, ['Artist1', 'Artist2']);
      });

      test('splits on semicolon', () {
        final result = ArtistParser.parse('Artist1; Artist2', defaultConfig);
        expect(result, ['Artist1', 'Artist2']);
      });

      test('splits on plus sign', () {
        final result = ArtistParser.parse('A + B + C', defaultConfig);
        expect(result, ['A', 'B', 'C']);
      });

      test('splits on comma-space', () {
        final result = ArtistParser.parse('A, B, C', defaultConfig);
        expect(result, ['A', 'B', 'C']);
      });

      test('single artist returns as-is', () {
        final result = ArtistParser.parse('Solo Artist', defaultConfig);
        expect(result, ['Solo Artist']);
      });

      test('trims whitespace from results', () {
        final result = ArtistParser.parse('  A  /  B  ', defaultConfig);
        expect(result, ['A', 'B']);
      });

      test('empty segments are discarded', () {
        final result = ArtistParser.parse('A / / B', defaultConfig);
        expect(result, ['A', 'B']);
      });
    });

    group('delimiter priority (longest first)', () {
      test('slash-with-spaces matches before bare slash', () {
        //" / " should be consumed first, not bare "/"
        final result = ArtistParser.parse('A / B/C', defaultConfig);
        expect(result, ['A', 'B', 'C']);
      });
    });

    group('escape handling', () {
      test('backslash before slash preserves literal slash', () {
        final result = ArtistParser.parse(r'AC\/DC', defaultConfig);
        expect(result, ['AC/DC']);
      });

      test('backslash before comma preserves literal comma', () {
        final result = ArtistParser.parse(r'A\, B, C', defaultConfig);
        expect(result, [r'A, B', 'C']);
      });

      test('backslash before plus preserves literal plus', () {
        final result = ArtistParser.parse(r'A \+ B + C', defaultConfig);
        expect(result, ['A + B', 'C']);
      });

      test('mixed escaped and unescaped', () {
        final result = ArtistParser.parse(r'AC\/DC / Artist2', defaultConfig);
        expect(result, ['AC/DC', 'Artist2']);
      });

      test('escaped slash in multi-artist', () {
        final result =
            ArtistParser.parse(r'AC\/DC / Guns N Roses', defaultConfig);
        expect(result, ['AC/DC', 'Guns N Roses']);
      });
    });

    group('excluded artists', () {
      test('artist containing comma delimiter is preserved', () {
        final config = ArtistParserConfig(
          excludedArtists: ['Tyler, The Creator'],
        );
        final result =
            ArtistParser.parse('Tyler, The Creator, Pharrell', config);
        expect(result, ['Tyler, The Creator', 'Pharrell']);
      });

      test('artist containing slash delimiter is preserved', () {
        final config = ArtistParserConfig(
          excludedArtists: ['Simon & Garfunkel'],
        );
        final result = ArtistParser.parse(
          'Simon & Garfunkel / Paul Simon',
          config,
        );
        expect(result, ['Simon & Garfunkel', 'Paul Simon']);
      });

      test('multiple excluded artists', () {
        final config = ArtistParserConfig(
          excludedArtists: ['Tyler, The Creator', 'Crosby, Stills & Nash'],
        );
        final result = ArtistParser.parse(
          'Tyler, The Creator, Crosby, Stills & Nash',
          config,
        );
        expect(result, ['Tyler, The Creator', 'Crosby, Stills & Nash']);
      });

      test('excluded artist matching is case-insensitive', () {
        final config = ArtistParserConfig(
          excludedArtists: ['tyler, the creator'],
        );
        final result =
            ArtistParser.parse('Tyler, The Creator, Pharrell', config);
        expect(result, ['Tyler, The Creator', 'Pharrell']);
      });

      test('excluded artist preserves original casing', () {
        final config = ArtistParserConfig(
          excludedArtists: ['TYLER, THE CREATOR'],
        );
        final result =
            ArtistParser.parse('Tyler, The Creator, Pharrell', config);
        //yhould keep original "Tyler, The Creator" casing
        expect(result, ['Tyler, The Creator', 'Pharrell']);
      });
    });

    group('edge cases', () {
      test('null input returns empty list', () {
        expect(ArtistParser.parse(null, defaultConfig), isEmpty);
      });

      test('empty string returns empty list', () {
        expect(ArtistParser.parse('', defaultConfig), isEmpty);
      });

      test('whitespace-only returns empty list', () {
        expect(ArtistParser.parse('   ', defaultConfig), isEmpty);
      });

      test('null config returns single-element list', () {
        expect(ArtistParser.parse('A / B', null), ['A / B']);
      });

      test('no delimiters configured returns single-element', () {
        final config = ArtistParserConfig(delimiters: []);
        expect(ArtistParser.parse('A / B', config), ['A / B']);
      });

      test('custom delimiters', () {
        final config = ArtistParserConfig(delimiters: [' & ', ' and ']);
        final result = ArtistParser.parse('A & B and C', config);
        expect(result, ['A', 'B', 'C']);
      });

      test('delimiter at start produces no empty first element', () {
        final result = ArtistParser.parse('/ Artist', defaultConfig);
        expect(result, ['Artist']);
      });

      test('delimiter at end produces no empty last element', () {
        final result = ArtistParser.parse('Artist /', defaultConfig);
        expect(result, ['Artist']);
      });
    });

    group('real-world yt-dlp tags', () {
      test('typical yt-dlp slash-separated', () {
        final result = ArtistParser.parse(
          'Daft Punk / Pharrell Williams / Nile Rodgers',
          defaultConfig,
        );
        expect(result, ['Daft Punk', 'Pharrell Williams', 'Nile Rodgers']);
      });

      test('semicolon-separated from MusicBrainz', () {
        final result = ArtistParser.parse(
          'Aphex Twin; µ-Ziq',
          defaultConfig,
        );
        expect(result, ['Aphex Twin', 'µ-Ziq']);
      });
    });
  });

  group('ArtistParserConfig', () {
    test('defaultDelimiters contains expected values', () {
      expect(ArtistParserConfig.defaultDelimiters, contains(' / '));
      expect(ArtistParserConfig.defaultDelimiters, contains('/'));
      expect(ArtistParserConfig.defaultDelimiters, contains('; '));
      expect(ArtistParserConfig.defaultDelimiters, contains(' + '));
      expect(ArtistParserConfig.defaultDelimiters, contains(', '));
    });

    test('default constructor uses defaultDelimiters', () {
      const config = ArtistParserConfig();
      expect(config.delimiters, ArtistParserConfig.defaultDelimiters);
      expect(config.excludedArtists, isEmpty);
    });
  });

  group('ScanConfig', () {
    test('none has empty defaults', () {
      expect(ScanConfig.none.excludedPaths, isEmpty);
      expect(ScanConfig.none.additionalPaths, isEmpty);
      expect(ScanConfig.none.minDuration, isNull);
      expect(ScanConfig.none.artistParser, isNull);
    });
  });

  group('ScanProgress', () {
    test('progress fraction calculation', () {
      const p = ScanProgress(total: 100, completed: 50);
      expect(p.progress, 0.5);
    });

    test('progress is 0 when total is 0', () {
      const p = ScanProgress(total: 0, completed: 0);
      expect(p.progress, 0.0);
    });

    test('toString includes fields', () {
      const p = ScanProgress(
        total: 100,
        completed: 42,
        currentPath: '/music/song.mp3',
        phase: ScanPhase.reading,
      );
      final s = p.toString();
      expect(s, contains('42'));
      expect(s, contains('100'));
      expect(s, contains('reading'));
      expect(s, contains('/music/song.mp3'));
    });
  });

  group('Song.copyWith', () {
    test('copies with new artists', () {
      final song = Song(path: '/a.mp3', title: 'A', artist: 'X / Y');
      final copy = song.copyWith(artists: ['X', 'Y']);
      expect(copy.artists, ['X', 'Y']);
      expect(copy.artist, 'X / Y'); //raw preserved
      expect(copy.path, '/a.mp3');
    });

    test('copies without changes returns equivalent', () {
      final song = Song(
        path: '/a.mp3',
        title: 'A',
        artist: 'X',
        artists: ['X'],
      );
      final copy = song.copyWith();
      expect(copy.path, song.path);
      expect(copy.title, song.title);
      expect(copy.artist, song.artist);
      expect(copy.artists, song.artists);
    });
  });
}
