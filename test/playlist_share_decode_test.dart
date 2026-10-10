import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/services/sharing/playlist_link_share_service.dart';

class _RealHttpOverrides extends HttpOverrides {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = _RealHttpOverrides();

  final sampleTracks = [
    Track(
      id: 'song1',
      title: 'First Song',
      artist: 'Artist One',
      album: 'Album One',
      duration: '3:30',
      artworkUrl: 'https://example.com/art1.jpg',
      audioUrl: 'https://example.com/audio1.mp3',
      genre: 'Pop',
    ),
    Track(
      id: 'song2',
      title: 'Second Song',
      artist: 'Artist Two',
      album: 'Album Two',
      duration: '4:15',
      artworkUrl: 'https://example.com/art2.jpg',
      audioUrl: 'https://example.com/audio2.mp3',
      genre: 'Rock',
    ),
  ];

  group('PlaylistLinkShareService Tests', () {
    test('Pasting 5-character string (e.g. uqPhU) never crashes Base64 decoder with uqPhU===', () {
      // Must not throw FormatException
      final result = PlaylistLinkShareService.instance.decodeShareableLink('uqPhU');
      expect(result, isNull);
    });

    test('Pasting invalid short codes returns null without throwing FormatException', () {
      expect(PlaylistLinkShareService.instance.decodeShareableLink('abcde'), isNull);
      expect(PlaylistLinkShareService.instance.decodeShareableLink('aura://share?dp=uqPhU'), isNull);
      expect(PlaylistLinkShareService.instance.decodeShareableLink('   '), isNull);
    });

    test('Synchronous Base64 encode and decode works correctly', () {
      final link = PlaylistLinkShareService.instance.generateShareableLink(
        'My Cool Mix',
        'Test Description',
        sampleTracks,
      );

      expect(link, startsWith('aura://share?p='));

      // Decode with full URL
      final decodedFull = PlaylistLinkShareService.instance.decodeShareableLink(link);
      expect(decodedFull, isNotNull);
      expect(decodedFull!.tracks.length, equals(2));
      expect(decodedFull.tracks[0].title, equals('First Song'));
      expect(decodedFull.tracks[1].artist, equals('Artist Two'));

      // Decode with just the raw base64 payload
      final rawPayload = link.split('p=').last;
      final decodedRaw = PlaylistLinkShareService.instance.decodeShareableLink(rawPayload);
      expect(decodedRaw, isNotNull);
      expect(decodedRaw!.tracks.length, equals(2));
    });

    test('Pasting aura://share?dp=... never triggers p= parameter matching in decodeShareableLink', () {
      // Because dp= contains 'p=', it must NOT be extracted as p= parameter!
      final result = PlaylistLinkShareService.instance.decodeShareableLink('aura://share?dp=invalidcode');
      expect(result, isNull);
    });

    test('Async share link generation and decoding with both full URL and raw code', () async {
      final link = await PlaylistLinkShareService.instance.generateShareableLinkAsync(
        'Cloud Test Mix',
        'Shared across devices',
        sampleTracks,
      );

      expect(link, isNotEmpty);
      print('Generated async link: $link');

      // 1. Decode with full link
      final decodedFull = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(link);
      expect(decodedFull, isNotNull);
      expect(decodedFull!.title, equals('Cloud Test Mix'));
      expect(decodedFull.tracks.length, equals(2));

      // 2. Extract code from link and test decoding with just the raw short code!
      String rawCode = link;
      if (link.contains('dp=')) {
        rawCode = link.split('dp=').last.split('&').first;
      } else if (link.contains('dpc=')) {
        rawCode = link.split('dpc=').last.split('&').first;
      }

      print('Extracted raw code: $rawCode');
      final decodedRaw = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(rawCode);
      expect(decodedRaw, isNotNull);
      expect(decodedRaw!.tracks.length, equals(2));
    });
  });
}
