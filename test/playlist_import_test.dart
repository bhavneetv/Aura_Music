import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/services/sharing/playlist_link_share_service.dart';

void main() {
  group('PlaylistLinkShareService Tests', () {
    test('generateShareableLink and decodeShareableLink roundtrip', () {
      final tracks = [
        Track(
          id: 't1',
          title: 'Test Song 1',
          artist: 'Artist 1',
          album: 'Album 1',
          duration: '3:30',
          artworkUrl: 'https://example.com/art1.jpg',
          audioUrl: 'https://example.com/audio1.mp3',
          genre: 'Pop',
        ),
        Track(
          id: 't2',
          title: 'Test Song 2',
          artist: 'Artist 2',
          album: 'Album 2',
          duration: '4:00',
          artworkUrl: 'https://example.com/art2.jpg',
          audioUrl: 'https://example.com/audio2.mp3',
          genre: 'Rock',
        ),
      ];

      final link = PlaylistLinkShareService.instance.generateShareableLink('My Mix', 'Fun playlist', tracks);
      expect(link.startsWith('aura://share?p='), isTrue);

      final decoded = PlaylistLinkShareService.instance.decodeShareableLink(link);
      expect(decoded, isNotNull);
      expect(decoded!.tracks.length, equals(2));
      expect(decoded.tracks.first.id, equals('t1'));
      expect(decoded.tracks.first.title, equals('Test Song 1'));
    });

    test('importEventNotifier emits and updates correctly', () {
      PlaylistImportEvent? received;
      void listener() {
        received = PlaylistLinkShareService.importEventNotifier.value;
      }

      PlaylistLinkShareService.importEventNotifier.addListener(listener);

      final testEvent = PlaylistImportEvent(
        title: 'New Playlist',
        description: 'Test description',
        trackCount: 5,
        tracks: [],
        fromQrScan: true,
      );

      PlaylistLinkShareService.importEventNotifier.value = testEvent;
      expect(received, isNotNull);
      expect(received!.title, equals('New Playlist'));
      expect(received!.fromQrScan, isTrue);
      expect(received!.trackCount, equals(5));

      PlaylistLinkShareService.importEventNotifier.removeListener(listener);
    });
  });
}
