import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'music_source.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';

class JamendoSource implements MusicSource {
  final Dio _dio = Dio();
  static const String _baseUrl = 'https://saavn.sumit.co/api';

  @override
  Future<List<Track>> getTrendingTracks() async {
    try {
      final page = math.Random().nextInt(3) + 1;
      final response = await _dio.get('$_baseUrl/search/songs?query=trending&page=$page');
      final tracks = _parseTracks(response.data);
      tracks.shuffle();
      return tracks;
    } catch (e) {
      print('Error fetching trending tracks: $e');
      return _getMockFallback();
    }
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    try {
      final response = await _dio.get('$_baseUrl/search/songs?query=$query');
      final tracks = _parseTracks(response.data);
      if (tracks.isNotEmpty) {
        return tracks;
      }
    } catch (e) {
      print('Error searching tracks: $e');
    }
    return _filterMockTracks(query);
  }

  @override
  Future<List<Track>> getTracksByGenre(String genre) async {
    try {
      final page = math.Random().nextInt(4) + 1;
      final response = await _dio.get('$_baseUrl/search/songs?query=${Uri.encodeComponent(genre)}&page=$page');
      final tracks = _parseTracks(response.data);
      tracks.shuffle();
      return tracks;
    } catch (e) {
      print('Error fetching tracks by genre "$genre": $e');
      return _getMockFallback();
    }
  }

  @override
  Future<List<Track>> getDynamicRecommendations() async {
    try {
      final preferredLangs = StorageService.getPreferredLanguages();
      final preferredGenres = StorageService.getPreferredGenres();
      final history = StorageService.getListeningHistory();

      final List<String> seedQueries = [];
      for (final item in history.take(5)) {
        if (item['genre'] != null && item['genre'].toString().isNotEmpty) {
          seedQueries.add(item['genre'].toString());
        }
        if (item['artist'] != null && item['artist'].toString().isNotEmpty) {
          seedQueries.add(item['artist'].toString().split(',').first);
        }
      }
      seedQueries.addAll(preferredLangs);
      seedQueries.addAll(preferredGenres);

      if (seedQueries.isEmpty) {
        seedQueries.addAll(['trending', 'punjabi', 'bollywood', 'chillout', 'lofi', 'romantic']);
      }

      seedQueries.shuffle();
      final selectedQuery = seedQueries.first;
      final page = math.Random().nextInt(5) + 1;

      final response = await _dio.get('$_baseUrl/search/songs?query=${Uri.encodeComponent(selectedQuery)}&page=$page');
      final tracks = _parseTracks(response.data);
      if (tracks.isNotEmpty) {
        tracks.shuffle();
        return tracks;
      }
    } catch (e) {
      print('Error fetching dynamic recommendations: $e');
    }

    final fallback = List<Track>.from(Track.mockTracks)..shuffle();
    return fallback;
  }

  // ── Parsers & Helpers ────────────────────────────────────────

  List<Track> _parseTracks(dynamic data) {
    Map<String, dynamic> parsed;
    if (data is String) {
      try {
        parsed = jsonDecode(data) as Map<String, dynamic>;
      } catch (_) {
        return [];
      }
    } else if (data is Map<String, dynamic>) {
      parsed = data;
    } else {
      return [];
    }

    final dataMap = parsed['data'];
    if (dataMap == null) return [];

    final results = dataMap['results'] as List? ?? [];
    final List<Track> tracks = [];

    for (final item in results) {
      try {
        final id = item['id']?.toString() ?? '';
        final title = item['name']?.toString() ?? 'Unknown Track';
        
        // Parse primary artists
        String artist = 'Unknown Artist';
        if (item['artists'] != null && item['artists']['primary'] != null) {
          final primary = item['artists']['primary'] as List;
          if (primary.isNotEmpty) {
            artist = primary.map((a) => a['name']?.toString() ?? '').where((name) => name.isNotEmpty).join(', ');
          }
        }

        // Parse album name
        String album = 'Single';
        if (item['album'] != null && item['album']['name'] != null) {
          album = item['album']['name'].toString();
        }

        // Parse duration in seconds and format as "MM:SS"
        final durationSec = int.tryParse(item['duration']?.toString() ?? '180') ?? 180;
        final duration = _formatDuration(durationSec);

        // Parse artwork image URL (prefer highest resolution)
        String artworkUrl = '';
        if (item['image'] != null && item['image'] is List) {
          final images = item['image'] as List;
          if (images.isNotEmpty) {
            artworkUrl = images.last['url']?.toString() ?? images.last['link']?.toString() ?? '';
          }
        }

        // Parse audio download URL (prefer 320kbps high quality)
        String audioUrl = '';
        if (item['downloadUrl'] != null && item['downloadUrl'] is List) {
          final downloads = item['downloadUrl'] as List;
          if (downloads.isNotEmpty) {
            // Find highest quality or fallback to last
            audioUrl = downloads.last['url']?.toString() ?? downloads.last['link']?.toString() ?? '';
          }
        }

        if (id.isNotEmpty && audioUrl.isNotEmpty) {
          tracks.add(
            Track(
              id: id,
              title: title,
              artist: artist,
              album: album,
              duration: duration,
              artworkUrl: artworkUrl,
              audioUrl: audioUrl,
              genre: item['language']?.toString().toUpperCase() ?? 'BOLLYWOOD',
            ),
          );
        }
      } catch (e) {
        print('Error parsing track item: $e');
      }
    }

    return tracks;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  List<Track> _getMockFallback() {
    return Track.mockTracks;
  }

  List<Track> _filterMockTracks(String query) {
    return Track.mockTracks.where((track) {
      return track.title.toLowerCase().contains(query.toLowerCase()) ||
          track.artist.toLowerCase().contains(query.toLowerCase());
    }).toList();
  }
}
