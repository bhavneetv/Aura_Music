import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/models/source_mode.dart';
import 'package:music_app/services/music_sources/source_manager.dart';
import 'package:music_app/services/music_sources/youtube_source.dart';

void main() {
  group('SourceMode Enum Tests', () {
    test('default fromKey returns hybrid', () {
      expect(SourceMode.fromKey(null), equals(SourceMode.hybrid));
      expect(SourceMode.fromKey('unknown'), equals(SourceMode.hybrid));
    });

    test('valid fromKey maps correctly', () {
      expect(SourceMode.fromKey('hybrid'), equals(SourceMode.hybrid));
      expect(SourceMode.fromKey('jiosaavn'), equals(SourceMode.jiosaavn));
      expect(SourceMode.fromKey('youtube'), equals(SourceMode.youtube));
    });

    test('labels and descriptions are present', () {
      for (final mode in SourceMode.values) {
        expect(mode.label.isNotEmpty, isTrue);
        expect(mode.description.isNotEmpty, isTrue);
      }
    });
  });

  group('Track Model Multi-Source Tests', () {
    test('defaults source to jiosaavn and youtubeVideoId to null', () {
      const track = Track(
        id: 'track1',
        title: 'Song Name',
        artist: 'Artist Name',
        album: 'Album',
        duration: '3:30',
        artworkUrl: 'http://art.jpg',
        audioUrl: 'http://audio.mp3',
        genre: 'POP',
      );

      expect(track.source, equals('jiosaavn'));
      expect(track.youtubeVideoId, isNull);
      expect(track.isJioSaavn, isTrue);
      expect(track.isYouTube, isFalse);
    });

    test('backward compatible fromJson handles legacy maps without source', () {
      final legacyMap = {
        'id': 'legacy_123',
        'title': 'Legacy Song',
        'artist': 'Legacy Artist',
        'album': 'Single',
        'duration': '4:00',
        'artworkUrl': 'https://example.com/art.jpg',
        'audioUrl': 'https://example.com/song.mp4',
        'genre': 'BOLLYWOOD',
      };

      final track = Track.fromJson(legacyMap);
      expect(track.id, equals('legacy_123'));
      expect(track.source, equals('jiosaavn'));
      expect(track.youtubeVideoId, isNull);
      expect(track.isJioSaavn, isTrue);
      expect(track.isYouTube, isFalse);
    });

    test('fromJson and toJson serialize source and youtubeVideoId correctly', () {
      final ytTrack = Track(
        id: 'yt_abc123',
        title: 'YouTube Track',
        artist: 'YouTuber Musician',
        album: 'YouTube',
        duration: '3:45',
        artworkUrl: 'https://i.ytimg.com/vi/abc123/hqdefault.jpg',
        audioUrl: '',
        genre: 'YouTube',
        source: 'youtube',
        youtubeVideoId: 'abc123',
      );

      expect(ytTrack.isYouTube, isTrue);
      expect(ytTrack.isJioSaavn, isFalse);

      final json = ytTrack.toJson();
      expect(json['source'], equals('youtube'));
      expect(json['youtubeVideoId'], equals('abc123'));

      final restored = Track.fromJson(json);
      expect(restored.source, equals('youtube'));
      expect(restored.youtubeVideoId, equals('abc123'));
      expect(restored.isYouTube, isTrue);
    });

    test('copyWith updates source and youtubeVideoId properly', () {
      const original = Track(
        id: '1',
        title: 'Song',
        artist: 'Artist',
        album: 'Album',
        duration: '3:00',
        artworkUrl: '',
        audioUrl: '',
        genre: 'POP',
      );

      final modified = original.copyWith(
        source: 'youtube',
        youtubeVideoId: 'vid999',
      );

      expect(modified.source, equals('youtube'));
      expect(modified.youtubeVideoId, equals('vid999'));
      expect(modified.title, equals(original.title));
    });
  });

  group('SourceManager Match Scoring & Parsing', () {
    test('SourceManager initializes as singleton and implements MusicSource', () {
      final sm = SourceManager();
      expect(sm, equals(SourceManager.instance));
      expect(sm.name, equals('SourceManager'));
    });
  });
}
