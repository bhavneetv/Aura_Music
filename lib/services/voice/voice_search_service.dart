import 'dart:math' as math;
import '../../models/track.dart';
import '../storage/storage_service.dart';
import '../../providers/playback_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

enum VoiceSearchResultType { track, playlist, artist, resume, noMatch }

class VoiceSearchResult {
  final VoiceSearchResultType type;
  final String query;
  final Track? matchedTrack;
  final List<Track> queue;
  final String? playlistName;
  final String? artistName;
  final String? message;

  VoiceSearchResult({
    required this.type,
    required this.query,
    this.matchedTrack,
    this.queue = const [],
    this.playlistName,
    this.artistName,
    this.message,
  });

  bool get isSuccess => type != VoiceSearchResultType.noMatch;
}

class VoiceSearchService {
  static final VoiceSearchService instance = VoiceSearchService._internal();
  VoiceSearchService._internal();

  /// Cleans and normalizes voice input text by stripping app branding and command fillers.
  String normalizeQuery(String rawQuery) {
    String q = rawQuery.trim().toLowerCase();
    
    // Remove command prefixes and app name suffixes
    final patterns = [
      RegExp(r'^hey\s+siri\s+'),
      RegExp(r'^hey\s+google\s+'),
      RegExp(r'^ok\s+google\s+'),
      RegExp(r'^play\s+me\s+'),
      RegExp(r'^play\s+the\s+song\s+'),
      RegExp(r'^play\s+the\s+playlist\s+'),
      RegExp(r'^play\s+the\s+artist\s+'),
      RegExp(r'^play\s+'),
      RegExp(r'(^|\s+)in\s+aura$'),
      RegExp(r'(^|\s+)on\s+aura$'),
      RegExp(r'(^|\s+)with\s+aura$'),
      RegExp(r'(^|\s+)using\s+aura$'),
      RegExp(r'^aura\s+play\s+'),
    ];

    for (final pattern in patterns) {
      q = q.replaceAll(pattern, '').trim();
    }

    // Strip trailing/leading punctuation
    q = q.replaceAll(RegExp(r'[^\w\s]'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    return q;
  }

  /// Calculates Levenshtein distance similarity between two strings (0.0 to 1.0)
  double _calculateSimilarity(String s1, String s2) {
    if (s1 == s2) return 1.0;
    if (s1.isEmpty || s2.isEmpty) return 0.0;

    final len1 = s1.length;
    final len2 = s2.length;
    final d = List.generate(len1 + 1, (_) => List<int>.filled(len2 + 1, 0));

    for (int i = 0; i <= len1; i++) {
      d[i][0] = i;
    }
    for (int j = 0; j <= len2; j++) {
      d[0][j] = j;
    }

    for (int i = 1; i <= len1; i++) {
      for (int j = 1; j <= len2; j++) {
        final cost = (s1[i - 1] == s2[j - 1]) ? 0 : 1;
        d[i][j] = math.min(
          math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
          d[i - 1][j - 1] + cost,
        );
      }
    }

    final maxLen = math.max(len1, len2);
    return 1.0 - (d[len1][len2] / maxLen);
  }

  /// Evaluates fuzzy match score for a given candidate target string against the search query.
  double _scoreMatch(String query, String target) {
    final q = query.toLowerCase().trim();
    final t = target.toLowerCase().trim();

    if (q.isEmpty || t.isEmpty) return 0.0;
    if (q == t) return 1.0;
    if (t.startsWith(q)) return 0.95;
    if (t.contains(q)) return 0.85;

    // Token match check (e.g. query "shape of you" vs "shape of you (cover)")
    final qTokens = q.split(' ').where((tok) => tok.length > 1).toSet();
    final tTokens = t.split(' ').where((tok) => tok.length > 1).toSet();

    if (qTokens.isNotEmpty) {
      final intersection = qTokens.intersection(tTokens);
      final tokenScore = intersection.length / qTokens.length;
      if (tokenScore >= 0.8) {
        return 0.8 + (tokenScore * 0.15);
      }
    }

    // Levenshtein similarity fallback
    return _calculateSimilarity(q, t);
  }

  /// Gathers all locally cached tracks from favorites, downloads, playlists, and history.
  List<Track> getLocalLibraryTracks() {
    final Map<String, Track> trackMap = {};

    try {
      // 1. Downloaded tracks
      final downloaded = StorageService.getFullDownloadedTracks();
      for (final t in downloaded) {
        if (t.id.isNotEmpty) trackMap[t.id] = t;
      }
    } catch (_) {}

    try {
      // 2. Favorite tracks
      final favorites = StorageService.getFavoriteTracks();
      for (final t in favorites) {
        if (t.id.isNotEmpty && !trackMap.containsKey(t.id)) {
          trackMap[t.id] = t;
        }
      }
    } catch (_) {}

    try {
      // 3. Playlists tracks
      final playlists = StorageService.getPlaylists();
      for (final pl in playlists) {
        final tracks = pl['tracks'];
        if (tracks is List) {
          for (final item in tracks) {
            if (item is Map) {
              final t = Track(
                id: item['id']?.toString() ?? '',
                title: item['title']?.toString() ?? '',
                artist: item['artist']?.toString() ?? '',
                album: item['album']?.toString() ?? '',
                duration: item['duration']?.toString() ?? '3:30',
                artworkUrl: item['artworkUrl']?.toString() ?? '',
                audioUrl: item['audioUrl']?.toString() ?? '',
                genre: item['genre']?.toString() ?? '',
              );
              if (t.id.isNotEmpty && !trackMap.containsKey(t.id)) {
                trackMap[t.id] = t;
              }
            }
          }
        }
      }
    } catch (_) {}

    try {
      // 4. Searched/played tracks
      final history = StorageService.getSearchedAndPlayedTracks();
      for (final item in history) {
        final id = item['track_id']?.toString() ?? '';
        if (id.isNotEmpty && !trackMap.containsKey(id)) {
          trackMap[id] = Track(
            id: id,
            title: item['title']?.toString() ?? '',
            artist: item['artist']?.toString() ?? '',
            album: item['album']?.toString() ?? '',
            duration: item['duration']?.toString() ?? '3:30',
            artworkUrl: item['artworkUrl']?.toString() ?? '',
            audioUrl: item['audioUrl']?.toString() ?? '',
            genre: item['genre']?.toString() ?? '',
          );
        }
      }
    } catch (_) {}

    return trackMap.values.toList();
  }

  /// Searches local library for the best matching song, artist, or playlist.
  VoiceSearchResult resolveVoiceQuery(String rawQuery) {
    final cleanQuery = normalizeQuery(rawQuery);

    // Case 1: No query or empty query ("play music on Aura")
    if (cleanQuery.isEmpty || cleanQuery == 'music' || cleanQuery == 'songs' || cleanQuery == 'library') {
      final localTracks = getLocalLibraryTracks();
      if (localTracks.isNotEmpty) {
        return VoiceSearchResult(
          type: VoiceSearchResultType.resume,
          query: rawQuery,
          queue: localTracks,
          message: 'Playing your Aura music library',
        );
      } else {
        return VoiceSearchResult(
          type: VoiceSearchResultType.resume,
          query: rawQuery,
          message: 'Resuming playback',
        );
      }
    }

    double bestScore = 0.0;
    VoiceSearchResultType bestType = VoiceSearchResultType.noMatch;
    Track? bestTrack;
    List<Track> bestQueue = [];
    String? matchedName;

    // Check Playlists
    try {
      final playlists = StorageService.getPlaylists();
      for (final pl in playlists) {
        final name = pl['name']?.toString() ?? '';
        final score = _scoreMatch(cleanQuery, name);
        if (score > bestScore && score >= 0.5) {
          bestScore = score;
          bestType = VoiceSearchResultType.playlist;
          matchedName = name;
          final rawTracks = pl['tracks'];
          if (rawTracks is List) {
            bestQueue = rawTracks.map((item) {
              final m = Map<String, dynamic>.from(item as Map);
              return Track(
                id: m['id']?.toString() ?? '',
                title: m['title']?.toString() ?? '',
                artist: m['artist']?.toString() ?? '',
                album: m['album']?.toString() ?? '',
                duration: m['duration']?.toString() ?? '3:30',
                artworkUrl: m['artworkUrl']?.toString() ?? '',
                audioUrl: m['audioUrl']?.toString() ?? '',
                genre: m['genre']?.toString() ?? '',
              );
            }).toList();
          }
        }
      }
    } catch (_) {}

    // Check Songs & Artists
    final candidates = getLocalLibraryTracks();
    
    // Group tracks by artist for artist match candidate scoring
    final Map<String, List<Track>> artistMap = {};
    for (final t in candidates) {
      if (t.artist.isNotEmpty) {
        final artistKey = t.artist.toLowerCase().trim();
        artistMap.putIfAbsent(artistKey, () => []).add(t);
      }
    }

    // Evaluate artist names
    artistMap.forEach((artistKey, tracks) {
      final score = _scoreMatch(cleanQuery, artistKey);
      if (score > bestScore && score >= 0.55) {
        bestScore = score;
        bestType = VoiceSearchResultType.artist;
        matchedName = tracks.first.artist;
        bestQueue = tracks;
        bestTrack = tracks.first;
      }
    });

    // Evaluate track titles (and title + artist combo)
    for (final t in candidates) {
      final titleScore = _scoreMatch(cleanQuery, t.title);
      final comboScore = _scoreMatch(cleanQuery, '${t.title} ${t.artist}');
      final maxTrackScore = math.max(titleScore, comboScore);

      if (maxTrackScore > bestScore && maxTrackScore >= 0.45) {
        bestScore = maxTrackScore;
        bestType = VoiceSearchResultType.track;
        bestTrack = t;
        matchedName = t.title;
        bestQueue = [t];
      }
    }

    if (bestScore >= 0.45 && bestType != VoiceSearchResultType.noMatch) {
      return VoiceSearchResult(
        type: bestType,
        query: rawQuery,
        matchedTrack: bestTrack,
        queue: bestQueue,
        playlistName: bestType == VoiceSearchResultType.playlist ? matchedName : null,
        artistName: bestType == VoiceSearchResultType.artist ? matchedName : null,
        message: 'Playing $matchedName',
      );
    }

    return VoiceSearchResult(
      type: VoiceSearchResultType.noMatch,
      query: rawQuery,
      message: 'Couldn\'t find "$rawQuery" in Aura',
    );
  }

  /// Executes playback of resolved result through Riverpod PlaybackNotifier.
  Future<bool> executeVoiceSearchResult(VoiceSearchResult result, WidgetRef ref) async {
    final notifier = ref.read(playbackProvider.notifier);

    switch (result.type) {
      case VoiceSearchResultType.resume:
        if (result.queue.isNotEmpty) {
          notifier.playCustomQueue(result.queue, initialIndex: 0);
        } else {
          final currentState = ref.read(playbackProvider);
          if (currentState.currentTrack != null) {
            notifier.playTrack(currentState.currentTrack!);
          }
        }
        return true;

      case VoiceSearchResultType.track:
        if (result.matchedTrack != null) {
          notifier.playTrack(result.matchedTrack!);
          return true;
        }
        break;

      case VoiceSearchResultType.playlist:
      case VoiceSearchResultType.artist:
        if (result.queue.isNotEmpty) {
          notifier.playCustomQueue(result.queue, initialIndex: 0);
          return true;
        }
        break;

      case VoiceSearchResultType.noMatch:
        return false;
    }

    return false;
  }
}
