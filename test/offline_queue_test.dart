import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';

void main() {
  group('Offline Queue & Auto-Advance Tests', () {
    test('Track mapping preserves local path when downloaded', () {
      const track = Track(
        id: 'offline_55',
        title: 'Downloaded Punjabi Song',
        artist: 'Singer',
        album: 'Album',
        duration: '3:00',
        artworkUrl: '/app/downloads/offline_55_cover.jpg',
        audioUrl: '/app/downloads/offline_55.mp4',
        genre: 'OFFLINE',
      );

      expect(track.audioUrl.startsWith('http'), isFalse);
      expect(track.audioUrl, equals('/app/downloads/offline_55.mp4'));
    });

    test('Filtering downloaded tracks retains only local audio tracks', () {
      final tracks = [
        const Track(
          id: 'dl_1',
          title: 'Song 1',
          artist: 'Artist 1',
          album: 'Album',
          duration: '3:00',
          artworkUrl: '',
          audioUrl: '/downloads/1.mp4',
          genre: '',
        ),
        const Track(
          id: 'online_2',
          title: 'Song 2',
          artist: 'Artist 2',
          album: 'Album',
          duration: '3:00',
          artworkUrl: '',
          audioUrl: 'https://cdn.example.com/2.mp4',
          genre: '',
        ),
      ];

      final downloadedOnly = tracks.where((t) => t.audioUrl.isNotEmpty && !t.audioUrl.startsWith('http')).toList();
      expect(downloadedOnly.length, equals(1));
      expect(downloadedOnly.first.id, equals('dl_1'));
    });
  });
}
