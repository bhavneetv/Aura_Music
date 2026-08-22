import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/screens/now_playing/now_playing_screen.dart';

void main() {
  group('Offline Cover Art Tests', () {
    test('getArtworkImageProvider resolves network URL when online', () {
      const track = Track(
        id: 'test_101',
        title: 'Online Song',
        artist: 'Online Artist',
        album: 'Online Album',
        duration: '3:30',
        artworkUrl: 'https://c.saavncdn.com/123/cover.jpg',
        audioUrl: 'https://audio.com/song.mp4',
        genre: 'Pop',
      );

      final provider = getArtworkImageProvider(track);
      expect(provider, isNotNull);
    });

    test('Track model retains local artworkUrl path when set', () {
      const localArtPath = '/data/user/0/com.example.music_app/app_flutter/downloads/test_101_cover.jpg';
      const track = Track(
        id: 'test_101',
        title: 'Downloaded Song',
        artist: 'Offline Artist',
        album: 'Offline Album',
        duration: '3:30',
        artworkUrl: localArtPath,
        audioUrl: '/data/user/0/com.example.music_app/app_flutter/downloads/test_101.mp4',
        genre: 'OFFLINE',
      );

      expect(track.artworkUrl, equals(localArtPath));
      expect(track.artworkUrl.startsWith('http'), isFalse);
    });
  });
}
