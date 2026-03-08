import 'package:flutter_test/flutter_test.dart';
import 'package:sono_query/sono_query.dart';

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
  });
}
