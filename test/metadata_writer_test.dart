import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sono_query/sono_query.dart';
import 'package:sono_query/src/metadata/metadata_reader.dart';

void main() {
  group('canWrite', () {
    test('returns true for writable formats', () {
      expect(MetadataReader.canWrite('/x/a.mp3'), isTrue);
      expect(MetadataReader.canWrite('/x/a.m4a'), isTrue);
      expect(MetadataReader.canWrite('/x/a.flac'), isTrue);
      expect(MetadataReader.canWrite('/x/a.wav'), isTrue);
    });

    test('returns false for non-writable formats', () {
      expect(MetadataReader.canWrite('/x/a.ogg'), isFalse);
      expect(MetadataReader.canWrite('/x/a.opus'), isFalse);
      expect(MetadataReader.canWrite('/x/a.aiff'), isFalse);
      expect(MetadataReader.canWrite('/x/a.ape'), isFalse);
    });

    test('is case insensitive', () {
      expect(MetadataReader.canWrite('/x/a.MP3'), isTrue);
      expect(MetadataReader.canWrite('/x/a.Flac'), isTrue);
    });
  });

  group('writeSync', () {
    test('returns false for non-writable extension', () {
      final tmp = File(p.join(Directory.systemTemp.path, 'fake.ogg'))
        ..createSync();
      addTearDown(() => tmp.deleteSync());
      expect(MetadataReader.writeSync(tmp.path, title: 'x'), isFalse);
    });

    test('returns false when file does not exist', () {
      expect(
        MetadataReader.writeSync('/nonexistent/path.mp3', title: 'x'),
        isFalse,
      );
    });

    test('writes and reads back title', () {
      final src = File('test/fixtures/sample.mp3');
      final tmp = File(p.join(Directory.systemTemp.path, 'rt.mp3'));
      src.copySync(tmp.path);
      addTearDown(() => tmp.deleteSync());

      expect(MetadataReader.writeSync(tmp.path, title: 'Test Title'), isTrue);
      final song = MetadataReader.readSync(tmp.path);
      expect(song.title, 'Test Title');
    });
  });
}
