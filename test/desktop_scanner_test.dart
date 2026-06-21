import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sono_query/src/helpers/desktop_scanner.dart';

void main() {
  group('scanDirectories exclusions', () {
    late Directory root;

    setUp(() async {
      root = await Directory.systemTemp.createTemp('sono_scan_test');
      await File(p.join(root.path, 'keep', 'a.mp3')).create(recursive: true);
      await File(
        p.join(root.path, 'excluded', 'b.mp3'),
      ).create(recursive: true);
      await File(
        p.join(root.path, 'excluded', 'nested', 'c.mp3'),
      ).create(recursive: true);
      await File(
        p.join(root.path, 'excludedExtra', 'd.mp3'),
      ).create(recursive: true);
    });

    tearDown(() async {
      if (await root.exists()) await root.delete(recursive: true);
    });

    Future<Set<String>> scanNames({
      List<String> excludedPaths = const [],
    }) async {
      final results = await scanDirectories([
        root.path,
      ], excludedPaths: excludedPaths);
      return results.map(p.basename).toSet();
    }

    test('returns all audio files when nothing is excluded', () async {
      expect(await scanNames(), {'a.mp3', 'b.mp3', 'c.mp3', 'd.mp3'});
    });

    test('excludes files in an excluded folder and its subfolders', () async {
      expect(await scanNames(excludedPaths: [p.join(root.path, 'excluded')]), {
        'a.mp3',
        'd.mp3',
      });
    });

    test('does not exclude sibling folders sharing a name prefix', () async {
      final names = await scanNames(
        excludedPaths: [p.join(root.path, 'excluded')],
      );
      expect(names.contains('d.mp3'), isTrue);
    });

    test('excludes when excluded path has a trailing separator', () async {
      expect(
        await scanNames(
          excludedPaths: ['${p.join(root.path, 'excluded')}${p.separator}'],
        ),
        {'a.mp3', 'd.mp3'},
      );
    });

    test('ignores empty excluded entries', () async {
      expect(await scanNames(excludedPaths: ['']), {
        'a.mp3',
        'b.mp3',
        'c.mp3',
        'd.mp3',
      });
    });
  });
}
