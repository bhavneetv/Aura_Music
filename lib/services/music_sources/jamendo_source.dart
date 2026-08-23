import 'dart:convert';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'music_source.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';
import '../recommendation/recommendation_engine.dart';
import '../audio/audio_url_resolver.dart';
import '../audio/des_cipher.dart';

class JamendoSource implements MusicSource {
  final Dio _dio = Dio();

  // Search mirrors (jiosaavn-api-beta returns accurate search results for any artist/query)
  static const List<String> _baseUrls = [
    'https://saavn.sumit.co/api',
    'https://jiosaavn-api-unofficial.vercel.app',
    'https://jiosaavn-api-beta.vercel.app',
  ];

  Future<dynamic> _fetchFromApi(String endpointPath) async {
    for (final baseUrl in _baseUrls) {
      try {
        final url = '$baseUrl$endpointPath';
        print('[AURA-DEBUG] _fetchFromApi trying: $url');
        final response = await _dio.get(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 10),
            sendTimeout: const Duration(seconds: 5),
            headers: {
              'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            },
          ),
        );
        print('[AURA-DEBUG] _fetchFromApi response status: ${response.statusCode}');
        if (response.statusCode == 200 && response.data != null) {
          final tracks = _parseTracks(response.data);
          print('[AURA-DEBUG] _fetchFromApi parsed ${tracks.length} tracks from $baseUrl');
          if (tracks.isNotEmpty) {
            return response.data;
          }
        }
      } catch (e) {
        print('[AURA-DEBUG] _fetchFromApi mirror failed ($baseUrl): $e');
      }
    }
    print('[AURA-DEBUG] _fetchFromApi ALL mirrors failed for: $endpointPath');
    return null;
  }

  @override
  Future<List<Track>> getTrendingTracks() async {
    final preferredLangs = StorageService.getPreferredLanguages();
    String query = 'trending';
    if (preferredLangs.isNotEmpty) {
      query = preferredLangs.first.toLowerCase();
    }
    try {
      final page = math.Random().nextInt(3) + 1;
      final data = await _fetchFromApi('/search/songs?query=${Uri.encodeComponent(query)}&page=$page');
      if (data != null) {
        final tracks = _parseTracks(data);
        if (tracks.isNotEmpty) {
          final resolved = await _resolveAudioUrls(tracks);
          final filtered = _filterByPreferredLanguages(resolved, preferredLangs);
          final finalTracks = filtered.isNotEmpty ? filtered : resolved;
          return RecommendationEngine.instance.rankRecommendations(finalTracks);
        }
      }
    } catch (e) {
      print('Error fetching trending tracks: $e');
    }
    return _getMockFallback();
  }

  List<Track> _filterByPreferredLanguages(List<Track> tracks, List<String> preferredLangs) {
    if (preferredLangs.isEmpty) return tracks;
    final upperLangs = preferredLangs.map((l) => l.toUpperCase()).toList();
    final filtered = tracks.where((t) {
      final g = t.genre.toUpperCase();
      return upperLangs.any((lang) {
        if (lang == 'HINDI' || lang == 'BOLLYWOOD') {
          return g.contains('HINDI') || g.contains('BOLLYWOOD');
        }
        return g.contains(lang) || lang.contains(g);
      });
    }).toList();
    return filtered.isNotEmpty ? filtered : tracks;
  }

  @override
  Future<List<Track>> searchTracks(String query) async {
    final cleanQuery = query.trim();
    if (cleanQuery.isEmpty) return [];
    print('[AURA-DEBUG] searchTracks called with: "$cleanQuery"');

    try {
      final data = await _fetchFromApi('/search/songs?query=${Uri.encodeComponent(cleanQuery)}');
      print('[AURA-DEBUG] searchTracks _fetchFromApi returned: ${data != null ? "data" : "null"}');
      if (data != null) {
        final tracks = _parseTracks(data);
        print('[AURA-DEBUG] searchTracks parsed ${tracks.length} tracks');
        if (tracks.isNotEmpty) {
          // Use AudioUrlResolver for batch resolution
          final resolved = await AudioUrlResolver.instance.resolveAll(tracks);
          print('[AURA-DEBUG] searchTracks resolved ${resolved.length} tracks');
          return resolved;
        }
      }
    } catch (e) {
      print('[AURA-DEBUG] searchTracks ERROR: $e');
    }
    print('[AURA-DEBUG] searchTracks falling back to mock');
    return _filterMockTracks(cleanQuery);
  }

  @override
  Future<List<Track>> getTracksByGenre(String genre) async {
    try {
      final page = math.Random().nextInt(4) + 1;
      final data = await _fetchFromApi('/search/songs?query=${Uri.encodeComponent(genre)}&page=$page');
      if (data != null) {
        final tracks = _parseTracks(data);
        if (tracks.isNotEmpty) {
          final resolved = await AudioUrlResolver.instance.resolveAll(tracks);
          return RecommendationEngine.instance.rankRecommendations(resolved);
        }
      }
    } catch (e) {
      print('Error fetching tracks by genre "$genre": $e');
    }
    return _getMockFallback();
  }

  @override
  Future<List<Track>> getDynamicRecommendations() async {
    final sessionCtx = StorageService.getSessionContext();
    final activeGenre = (sessionCtx['genre'] ?? '').toUpperCase();
    final activeArtist = sessionCtx['artist'] ?? '';

    final preferredLangs = StorageService.getPreferredLanguages();
    final preferredGenres = StorageService.getPreferredGenres();
    final preferredArtists = StorageService.getPreferredArtists();

    final List<String> queryPool = [];

    if (preferredLangs.isNotEmpty) {
      for (final lang in preferredLangs) {
        final l = lang.toLowerCase();
        queryPool.add(l);
        queryPool.add('$l songs');
        queryPool.add('$l hits');
      }
    }

    if (preferredGenres.isNotEmpty) {
      for (final genre in preferredGenres) {
        queryPool.add(genre.toLowerCase());
      }
    }

    if (preferredArtists.isNotEmpty) {
      for (final artist in preferredArtists) {
        queryPool.add(artist.toLowerCase());
      }
    }

    if (activeGenre.isNotEmpty) {
      queryPool.add(activeGenre.toLowerCase());
    }
    if (activeArtist.isNotEmpty) {
      queryPool.add(activeArtist.toLowerCase());
    }

    if (queryPool.isEmpty) {
      queryPool.addAll(['punjabi', 'bollywood', 'hindi songs', 'trending']);
    }

    final List<String> selectedQueries = [];
    for (final q in queryPool) {
      if (selectedQueries.length >= 3) break;
      if (!selectedQueries.any((s) => s.toLowerCase() == q.toLowerCase())) {
        selectedQueries.add(q);
      }
    }

    try {
      final futures = selectedQueries.map((query) async {
        try {
          final page = math.Random().nextInt(3) + 1;
          final data = await _fetchFromApi('/search/songs?query=${Uri.encodeComponent(query)}&page=$page');
          if (data != null) return _parseTracks(data);
        } catch (_) {}
        return <Track>[];
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
        final filtered = _filterByPreferredLanguages(merged.values.toList(), preferredLangs);
        final candidates = filtered.isNotEmpty ? filtered : merged.values.toList();
        final resolved = await AudioUrlResolver.instance.resolveAll(candidates);
        return RecommendationEngine.instance.rankRecommendations(resolved);
      }
    } catch (e) {
      print('Error fetching dynamic recommendations: $e');
    }

    return _getMockFallback();
  }

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
          final page = math.Random().nextInt(4) + 1;
          final data = await _fetchFromApi('/search/songs?query=${Uri.encodeComponent(query)}&page=$page');
          if (data != null) return _parseTracks(data);
        } catch (_) {}
        return <Track>[];
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
        final resolved = await AudioUrlResolver.instance.resolveAll(merged.values.toList());
        return RecommendationEngine.instance.rankRecommendations(
          resolved,
          currentTrack: currentTrack,
        );
      }
    } catch (_) {}

    return getDynamicRecommendations();
  }

  // ── Audio URL Resolution ─────────────────────────────────────

  Future<List<Track>> _resolveAudioUrls(List<Track> tracks) async {
    if (tracks.isEmpty) return [];
    return AudioUrlResolver.instance.resolveAll(tracks);
  }

  // ── Parsers & Helpers ────────────────────────────────────────

  List<Track> _parseTracks(dynamic data) {
    dynamic resultsRaw;
    if (data is String) {
      try {
        final decoded = jsonDecode(data);
        if (decoded is List) {
          resultsRaw = decoded;
        } else if (decoded is Map<String, dynamic>) {
          if (decoded['data'] != null) {
            if (decoded['data'] is Map && decoded['data']['results'] is List) {
              resultsRaw = decoded['data']['results'];
            } else if (decoded['data'] is List) {
              resultsRaw = decoded['data'];
            }
          } else if (decoded['results'] is List) {
            resultsRaw = decoded['results'];
          }
        }
      } catch (_) {
        return [];
      }
    } else if (data is List) {
      resultsRaw = data;
    } else if (data is Map<String, dynamic>) {
      if (data['data'] != null) {
        if (data['data'] is Map && data['data']['results'] is List) {
          resultsRaw = data['data']['results'];
        } else if (data['data'] is List) {
          resultsRaw = data['data'];
        }
      } else if (data['results'] is List) {
        resultsRaw = data['results'];
      }
    }

    final results = resultsRaw as List? ?? [];
    final List<Track> tracks = [];

    for (final item in results) {
      if (item is! Map) continue;
      try {
        final id = item['id']?.toString() ?? '';
        if (id.isEmpty) continue;

        final rawTitle = item['name']?.toString() ?? item['title']?.toString() ?? 'Unknown Track';
        final title = _cleanText(rawTitle);
        
        String artist = 'Unknown Artist';
        if (item['artists'] != null) {
          if (item['artists'] is Map && item['artists']['primary'] != null) {
            final primary = item['artists']['primary'] as List;
            if (primary.isNotEmpty) {
              artist = primary.map((a) => a is Map ? (a['name']?.toString() ?? '') : a.toString()).where((n) => n.isNotEmpty).join(', ');
            }
          } else if (item['artists'] is String) {
            artist = item['artists'].toString();
          }
        } else if (item['primaryArtists'] != null) {
          artist = item['primaryArtists'].toString();
        }
        artist = _cleanText(artist);

        String album = 'Single';
        if (item['album'] != null) {
          if (item['album'] is Map && item['album']['name'] != null) {
            album = item['album']['name'].toString();
          } else if (item['album'] is String) {
            album = item['album'].toString();
          }
        }
        album = _cleanText(album);

        final durationSec = int.tryParse(item['duration']?.toString() ?? '180') ?? 180;
        final duration = _formatDuration(durationSec);

        String artworkUrl = '';
        if (item['image'] != null && item['image'] is List) {
          final images = item['image'] as List;
          if (images.isNotEmpty) {
            final last = images.last;
            if (last is Map) {
              artworkUrl = last['url']?.toString() ?? last['link']?.toString() ?? '';
            } else {
              artworkUrl = last.toString();
            }
          }
        } else if (item['image'] != null && item['image'] is String) {
          artworkUrl = item['image'].toString();
        }

        String audioUrl = '';
        
        // Direct DES decryption if encrypted_media_url is present in item or item['more_info']
        final moreInfo = item['more_info'] is Map ? item['more_info'] as Map : null;
        final encUrl = (moreInfo != null ? moreInfo['encrypted_media_url'] : null) ?? item['encrypted_media_url'];
        if (encUrl != null && encUrl.toString().isNotEmpty) {
          final decrypted = DesCipher.decryptEcb(encUrl.toString(), '38346591');
          if (decrypted != null && decrypted.startsWith('http')) {
            audioUrl = decrypted.contains('_96.') ? decrypted.replaceAll('_96.', '_160.') : decrypted;
          }
        }

        if (audioUrl.isEmpty) {
          final possibleUrlKeys = [item['downloadUrl'], item['download_url'], item['url'], item['media_url'], item['link']];
          for (final val in possibleUrlKeys) {
            if (val == null) continue;
            if (val is List && val.isNotEmpty) {
              // 1. Prefer 160kbps link for guaranteed CDN 200 OK playback
              for (final d in val) {
                String link = '';
                String quality = '';
                if (d is Map) {
                  link = d['url']?.toString() ?? d['link']?.toString() ?? '';
                  quality = (d['quality'] ?? '').toString();
                } else if (d is String) {
                  link = d;
                }
                if (link.isNotEmpty && link.startsWith('http') && !link.contains('/song/') && (quality.contains('160') || link.contains('_160.'))) {
                  audioUrl = link;
                  break;
                }
              }
              // 2. Fallback to any valid direct audio URL
              if (audioUrl.isEmpty) {
                for (final d in val) {
                  String link = '';
                  if (d is Map) {
                    link = d['url']?.toString() ?? d['link']?.toString() ?? '';
                  } else if (d is String) {
                    link = d;
                  }
                  if (link.isNotEmpty && link.startsWith('http') && !link.contains('/song/')) {
                    audioUrl = link;
                    break;
                  }
                }
              }
              if (audioUrl.isNotEmpty) break;
            } else if (val is String && val.startsWith('http') && !val.contains('/song/')) {
              audioUrl = val;
              break;
            }
          }
        }



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

  String _cleanText(String text) {
    return text
        .replaceAll('&quot;', '"')
        .replaceAll('&amp;', '&')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ');
  }

  List<Track> _filterMockTracks(String query) {
    final lower = query.toLowerCase();
    return Track.mockTracks.where((track) {
      return track.title.toLowerCase().contains(lower) ||
          track.artist.toLowerCase().contains(lower);
    }).toList();
  }
}
