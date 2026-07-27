import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'music_source.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';

import '../recommendation/recommendation_engine.dart';

class JamendoSource implements MusicSource {
  final Dio _dio = Dio();
  static const String _baseUrl = 'https://saavn.sumit.co/api';

  @override
  Future<List<Track>> getTrendingTracks() async {
    try {
      final page = math.Random().nextInt(3) + 1;
      final response = await _dio.get('$_baseUrl/search/songs?query=trending&page=$page');
      final tracks = _parseTracks(response.data);
      return RecommendationEngine.instance.rankRecommendations(tracks);
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
      return RecommendationEngine.instance.rankRecommendations(tracks);
    } catch (e) {
      print('Error fetching tracks by genre "$genre": $e');
      return _getMockFallback();
    }
  }

  @override
  Future<List<Track>> getDynamicRecommendations() async {
    final sessionCtx = StorageService.getSessionContext();
    final activeGenre = (sessionCtx['genre'] ?? '').toUpperCase();
    final activeArtist = sessionCtx['artist'] ?? '';
    final activeLanguage = (sessionCtx['language'] ?? activeGenre).toUpperCase();

    // Build prioritized seed queries based on active listening context
    final List<String> primarySeeds = [];
    final List<String> secondarySeeds = [];

    // Primary: exact language/genre of current session
    if (activeGenre.isNotEmpty) {
      primarySeeds.add(activeGenre);
      primarySeeds.add('$activeGenre songs');
      primarySeeds.add('$activeGenre latest');
    }
    if (activeLanguage.isNotEmpty && activeLanguage != activeGenre) {
      primarySeeds.add(activeLanguage);
    }
    if (activeArtist.isNotEmpty) {
      primarySeeds.add(activeArtist);
      primarySeeds.add('$activeArtist songs');
    }

    // Secondary: user preferences and history
    final preferredLangs = StorageService.getPreferredLanguages();
    final preferredGenres = StorageService.getPreferredGenres();
    final history = StorageService.getListeningHistory();

    for (final item in history.take(3)) {
      if (item['genre'] != null && item['genre'].toString().isNotEmpty) {
        secondarySeeds.add(item['genre'].toString());
      }
      if (item['artist'] != null && item['artist'].toString().isNotEmpty) {
        secondarySeeds.add(item['artist'].toString().split(',').first);
      }
    }
    secondarySeeds.addAll(preferredLangs);
    secondarySeeds.addAll(preferredGenres);

    // Fallback pool
    final List<String> fallbackPool = [
      'trending', 'punjabi', 'bollywood', 'arijit singh', 'chillout',
      'lofi beats', 'romantic hits', 'top 50', 'taylor swift', 'pop hits',
      'acoustic guitar', 'edm party', 'retro 80s', 'kpop', 'drake', 'shreya ghoshal'
    ];

    // MULTI-QUERY STRATEGY: Fire 3 parallel API queries for a richer candidate pool
    final List<String> queryPool = [...primarySeeds, ...secondarySeeds, ...fallbackPool];
    final List<String> selectedQueries = [];

    // Pick top 3 distinct queries
    for (final q in queryPool) {
      if (selectedQueries.length >= 3) break;
      if (!selectedQueries.any((s) => s.toLowerCase() == q.toLowerCase())) {
        selectedQueries.add(q);
      }
    }

    if (selectedQueries.isEmpty) {
      selectedQueries.addAll(['trending', 'bollywood', 'punjabi']);
    }

    try {
      // Fire parallel API requests
      final futures = selectedQueries.map((query) async {
        try {
          final page = math.Random().nextInt(5) + 1;
          final response = await _dio.get(
            '$_baseUrl/search/songs?query=${Uri.encodeComponent(query)}&page=$page',
          );
          return _parseTracks(response.data);
        } catch (_) {
          return <Track>[];
        }
      }).toList();

      final results = await Future.wait(futures);

      // Merge and deduplicate all results
      final Map<String, Track> merged = {};
      for (final batch in results) {
        for (final track in batch) {
          final key = track.title.trim().toLowerCase();
          if (!merged.containsKey(key)) {
            merged[key] = track;
          }
        }
      }

      if (merged.isNotEmpty) {
        return RecommendationEngine.instance.rankRecommendations(
          merged.values.toList(),
        );
      }
    } catch (e) {
      print('Error fetching dynamic recommendations: $e');
    }

    // Single fallback attempt
    try {
      final fallbackQuery = (List.from(fallbackPool)..shuffle()).first;
      final page = math.Random().nextInt(5) + 1;
      final response = await _dio.get('$_baseUrl/search/songs?query=${Uri.encodeComponent(fallbackQuery)}&page=$page');
      final tracks = _parseTracks(response.data);
      if (tracks.isNotEmpty) {
        return RecommendationEngine.instance.rankRecommendations(tracks);
      }
    } catch (_) {}

    final fallback = List<Track>.from(Track.mockTracks)..shuffle();
    return RecommendationEngine.instance.rankRecommendations(fallback);
  }

  /// Context-specific recommendations anchored to a specific track
  Future<List<Track>> getContextualRecommendations(Track currentTrack) async {
    final genre = currentTrack.genre.trim().toUpperCase();
    final artist = currentTrack.artist.split(',').first.trim();
    final album = currentTrack.album.trim();

    final queries = <String>[];
    if (genre.isNotEmpty) {
      queries.add(genre);
      queries.add('$genre songs');
    }
    if (artist.isNotEmpty && artist != 'Unknown Artist') {
      queries.add(artist);
    }
    if (album.isNotEmpty && album != 'Single') {
      queries.add(album);
    }
    if (queries.isEmpty) queries.add('trending');

    try {
      final futures = queries.take(3).map((query) async {
        try {
          final page = math.Random().nextInt(5) + 1;
          final response = await _dio.get(
            '$_baseUrl/search/songs?query=${Uri.encodeComponent(query)}&page=$page',
          );
          return _parseTracks(response.data);
        } catch (_) {
          return <Track>[];
        }
      }).toList();

      final results = await Future.wait(futures);
      final Map<String, Track> merged = {};
      for (final batch in results) {
        for (final track in batch) {
          final key = track.title.trim().toLowerCase();
          if (!merged.containsKey(key)) {
            merged[key] = track;
          }
        }
      }

      if (merged.isNotEmpty) {
        return RecommendationEngine.instance.rankRecommendations(
          merged.values.toList(),
          currentTrack: currentTrack,
        );
      }
    } catch (_) {}

    return getDynamicRecommendations();
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

        // Fix malformed URL schemes (critical for ExoPlayer)
        if (audioUrl.startsWith('https:/') && !audioUrl.startsWith('https://')) {
          audioUrl = audioUrl.replaceFirst('https:/', 'https://');
        } else if (audioUrl.startsWith('http:/') && !audioUrl.startsWith('http://')) {
          audioUrl = audioUrl.replaceFirst('http:/', 'http://');
        }
        if (artworkUrl.startsWith('https:/') && !artworkUrl.startsWith('https://')) {
          artworkUrl = artworkUrl.replaceFirst('https:/', 'https://');
        } else if (artworkUrl.startsWith('http:/') && !artworkUrl.startsWith('http://')) {
          artworkUrl = artworkUrl.replaceFirst('http:/', 'http://');
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
