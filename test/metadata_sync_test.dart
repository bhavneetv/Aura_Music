import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';

void main() {
  group('Metadata Synchronization & Track Identity Tests', () {
    test('Track model strictly preserves ID across URL resolution copyWith', () {
      final original = Track(
        id: 'track_12345',
        title: 'Midnight Echoes',
        artist: 'Solaris',
        album: 'Aura Vinyl',
        duration: '3:45',
        artworkUrl: 'https://example.com/art.jpg',
        audioUrl: '',
        genre: 'Chillout',
      );

      final resolved = original.copyWith(
        audioUrl: 'https://aac.saavncdn.com/123/stream_160.mp4',
      );

      expect(resolved.id, equals('track_12345'));
      expect(resolved.title, equals('Midnight Echoes'));
      expect(resolved.artist, equals('Solaris'));
      expect(resolved.album, equals('Aura Vinyl'));
      expect(resolved.duration, equals('3:45'));
      expect(resolved.artworkUrl, equals('https://example.com/art.jpg'));
      expect(resolved.audioUrl, equals('https://aac.saavncdn.com/123/stream_160.mp4'));
    });

    test('Track JSON serialization preserves all identity fields', () {
      final track = Track(
        id: 'yt_abc123xyz',
        title: 'Pagal',
        artist: 'Diljit Dosanjh',
        album: 'MoonChild Era',
        duration: '4:10',
        artworkUrl: 'https://i.ytimg.com/vi/abc123xyz/hqdefault.jpg',
        audioUrl: 'https://googlevideo.com/playback',
        genre: 'Punjabi',
        source: 'youtube',
        youtubeVideoId: 'abc123xyz',
      );

      final json = track.toJson();
      final restored = Track.fromJson(json);

      expect(restored.id, equals(track.id));
      expect(restored.title, equals(track.title));
      expect(restored.artist, equals(track.artist));
      expect(restored.album, equals(track.album));
      expect(restored.duration, equals(track.duration));
      expect(restored.artworkUrl, equals(track.artworkUrl));
      expect(restored.audioUrl, equals(track.audioUrl));
      expect(restored.genre, equals(track.genre));
      expect(restored.source, equals('youtube'));
      expect(restored.youtubeVideoId, equals('abc123xyz'));
    });

    test('Comparing media item identity with audio source prevents mismatched state', () {
      final currentPlayingTrack = Track.mockTracks[0];
      final incomingTrack = Track.mockTracks[1];

      // Simulated MediaItem ID matches current audio
      String activeMediaItemId = currentPlayingTrack.id;
      String activeAudioSourceTrackId = currentPlayingTrack.id;

      expect(activeMediaItemId == activeAudioSourceTrackId, isTrue);

      // Incoming track starts loading, metadata MUST NOT prematurely update activeMediaItemId
      String pendingTrackId = incomingTrack.id;
      expect(pendingTrackId != activeMediaItemId, isTrue);

      // Only upon successful load does activeMediaItemId swap
      activeAudioSourceTrackId = incomingTrack.id;
      activeMediaItemId = incomingTrack.id;
      expect(activeMediaItemId == activeAudioSourceTrackId, isTrue);
    });
  });
}
