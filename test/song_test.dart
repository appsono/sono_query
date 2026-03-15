import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:sono_query/sono_query.dart';
import 'package:sono_query/src/helpers/audio_extensions.dart';

void main() {
  group('Song', () {
    test('fromPath extracts filename as title', () {
      final song = Song.fromPath('/home/user/Music/Some Track.mp3');
      expect(song.title, 'Some Track');
      expect(song.path, '/home/user/Music/Some Track.mp3');
    });

    test('fromPath handles nested paths', () {
      final song = Song.fromPath('/home/user/Music/Artist/Album/Track.flac');
      expect(song.title, 'Track');
    });

    test('fromPath leaves optional fields null', () {
      final song = Song.fromPath('/music/track.mp3');
      expect(song.artist, isNull);
      expect(song.album, isNull);
      expect(song.duration, isNull);
      expect(song.cover, isNull);
      expect(song.genre, isNull);
      expect(song.releaseDate, isNull);
    });

    test('equality is based on path', () {
      final a = Song(path: '/music/track.mp3', title: 'Track');
      final b = Song(path: '/music/track.mp3', title: 'Different Title');
      expect(a, equals(b));
    });

    test('different paths are not equal', () {
      final a = Song(path: '/music/track1.mp3', title: 'Track');
      final b = Song(path: '/music/track2.mp3', title: 'Track');
      expect(a, isNot(equals(b)));
    });

    test('toString includes key fields', () {
      final song = Song(
        path: '/music/track.mp3',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(minutes: 2, seconds: 41),
        genre: 'Genre',
      );
      final str = song.toString();
      expect(str, contains('Title'));
      expect(str, contains('Artist'));
      expect(str, contains('Album'));
      expect(str, contains('2:41'));
      expect(str, contains('Genre'));
    });

    test('consructor stores all fields', () {
      final cover = Uint8List.fromList([0xFF, 0xD8, 0xFF, 0xE0]);
      final song = Song(
        path: '/music/track.flac',
        title: 'Title',
        artist: 'Artist',
        album: 'Album',
        duration: const Duration(seconds: 4141),
        cover: cover,
        genre: 'Genre',
        releaseDate: DateTime(2026),
      );

      expect(song.path, '/music/track.flac');
      expect(song.title, 'Title');
      expect(song.artist, 'Artist');
      expect(song.album, 'Album');
      expect(song.duration, const Duration(seconds: 4141));
      expect(song.cover, cover);
      expect(song.genre, 'Genre');
      expect(song.releaseDate, DateTime(2026));
    });

    group('audio extensions', () {
      test('contains expected formats', () {
        expect(audioExtensions, contains('.mp3'));
        expect(audioExtensions, contains('.flac'));
        expect(audioExtensions, contains('.m4a'));
        expect(audioExtensions, contains('.ogg'));
        expect(audioExtensions, contains('.opus'));
        expect(audioExtensions, contains('.wav'));
      });

      test('does not contain video formats', () {
        expect(audioExtensions, isNot(contains('.mp4')));
        expect(audioExtensions, isNot(contains('.avi')));
        expect(audioExtensions, isNot(contains('.mkv')));
      });
    });
  });
}
