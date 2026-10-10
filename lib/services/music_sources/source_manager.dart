import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import '../../models/track.dart';
import '../../models/source_mode.dart';
import '../storage/storage_service.dart';
import 'music_source.dart';
import 'jamendo_source.dart';
import 'youtube_source.dart';

class FallbackEvent {
  final Track originalTrack;
  final String fallbackSource;
  final String message;
  final DateTime timestamp;

  FallbackEvent({
    required this.originalTrack,
    required this.fallbackSource,
    required this.message,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Top-level helper to search across all music sources simultaneously
Future<List<Track>> searchAllMusicSources(String query) async {
  return await SourceManager.instance.searchAllSources(query);
}

class SourceManager implements MusicSource {
  static final SourceManager instance = SourceManager._();
  SourceManager._();
  factory SourceManager() => instance;

  final JamendoSource _jioSaavn = JamendoSource();
  final YouTubeSource _youTube = YouTubeSource();

  JamendoSource get jioSaavn => _jioSaavn;
  YouTubeSource get youTube => _youTube;

  /// Searches both JioSaavn & YouTube in parallel, interleave & deduplicate
  Future<List<Track>> searchAllSources(String query) async {
    print('[AURA-SM] searchAllSources: query="$query"');
    try {
      final futures = await Future.wait([
        _jioSaavn.searchTracks(query).timeout(const Duration(seconds: 8)).catchError((e) {
          print('[AURA-SM] Filter All - JioSaavn error: $e');
          return <Track>[];
        }),
        _youTube.searchTracks(query).timeout(const Duration(seconds: 8)).catchError((e) {
          print('[AURA-SM] Filter All - YouTube error: $e');
          return <Track>[];
        }),
      ]);

      final jioResults = futures[0];
      final ytResults = futures[1];

      final results = <Track>[];
      final seen = <String>{};

      final maxLen = math.max(jioResults.length, ytResults.length);
      for (int i = 0; i < maxLen; i++) {
        if (i < jioResults.length) {
          final t = jioResults[i];
          final key = t.id.isNotEmpty ? t.id : '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(t);
          }
        }
        if (i < ytResults.length) {
          final t = ytResults[i];
          final key = t.id.isNotEmpty ? t.id : '${t.title.toLowerCase().trim()}_${t.artist.toLowerCase().trim()}';
          if (!seen.contains(key)) {
            seen.add(key);
            results.add(t);
          }
        }
      }
      return results;
    } catch (e) {
      print('[AURA-SM] searchAllSources All failed: $e, falling back to standard search');
      return await searchTracks(query);
    }
  }

  /// Searches tracks filtered specifically by source ('All', 'Saavn'/'JioSaavn', 'YT'/'YouTube')
  Future<List<Track>> searchByFilter(String query, String filter) async {
    print('[AURA-SM] searchByFilter: query="$query", filter="$filter"');
    if (filter == 'Saavn' || filter == 'JioSaavn') {
      return await _jioSaavn.searchTracks(query);
    } else if (filter == 'YT' || filter == 'YouTube') {
      return await _youTube.searchTracks(query);
    } else {
      return await searchAllSources(query);
    }
  }

  // Notification stream/notifier for UI snackbar when fallback occurs
  static final ValueNotifier<FallbackEvent?> fallbackNotifier = ValueNotifier<FallbackEvent?>(null);

  @override
  String get name => 'SourceManager';

  SourceMode get currentMode => StorageService.getSourceMode();

  @override
  Future<List<Track>> searchTracks(String query) async {
    final mode = currentMode;
    print('[AURA-SM] searchTracks: query="$query", mode=${mode.name}');

    switch (mode) {
      case SourceMode.jiosaavn:
        return await _jioSaavn.searchTracks(query);

      case SourceMode.youtube:
        return await _youTube.searchTracks(query);

      case SourceMode.hybrid:
        // Try JioSaavn first with a 6-second timeout
        try {
          final jioResults = await _jioSaavn
              .searchTracks(query)
              .timeout(const Duration(seconds: 6));
          if (jioResults.isNotEmpty) {
            print('[AURA-SM] Hybrid search: JioSaavn returned ${jioResults.length} tracks');
            return jioResults;
          }
          print('[AURA-SM] Hybrid search: JioSaavn returned 0 tracks, falling back to YouTube');
        } catch (e) {
          print('[AURA-SM] Hybrid search: JioSaavn failed/timed out ($e), falling back to YouTube');
        }

        // Fallback to YouTube
        try {
          final ytResults = await _youTube
              .searchTracks(query)
              .timeout(const Duration(seconds: 8));
          print('[AURA-SM] Hybrid search: YouTube fallback returned ${ytResults.length} tracks');
          return ytResults;
        } catch (e) {
          print('[AURA-SM] Hybrid search: YouTube fallback also failed: $e');
          return [];
        }
    }
  }

  @override
  Future<List<Track>> getTrendingTracks() async {
    final mode = currentMode;
    switch (mode) {
      case SourceMode.jiosaavn:
        return await _jioSaavn.getTrendingTracks();

      case SourceMode.youtube:
        return await _youTube.getTrendingTracks();

      case SourceMode.hybrid:
        try {
          final tracks = await _jioSaavn
              .getTrendingTracks()
              .timeout(const Duration(seconds: 6));
          if (tracks.isNotEmpty) return tracks;
        } catch (e) {
          print('[AURA-SM] Hybrid trending: JioSaavn failed ($e), trying YouTube');
        }
        return await _youTube.getTrendingTracks();
    }
  }

  @override
  Future<List<Track>> getTracksByGenre(String genre) async {
    final mode = currentMode;
    switch (mode) {
      case SourceMode.jiosaavn:
        return await _jioSaavn.getTracksByGenre(genre);

      case SourceMode.youtube:
        return await _youTube.getTracksByGenre(genre);

      case SourceMode.hybrid:
        try {
          final tracks = await _jioSaavn
              .getTracksByGenre(genre)
              .timeout(const Duration(seconds: 6));
          if (tracks.isNotEmpty) return tracks;
        } catch (e) {
          print('[AURA-SM] Hybrid genre: JioSaavn failed ($e), trying YouTube');
        }
        return await _youTube.getTracksByGenre(genre);
    }
  }

  @override
  Future<List<Track>> getDynamicRecommendations() async {
    final mode = currentMode;
    switch (mode) {
      case SourceMode.jiosaavn:
        return await _jioSaavn.getDynamicRecommendations();

      case SourceMode.youtube:
        return await _youTube.getDynamicRecommendations();

      case SourceMode.hybrid:
        try {
          final tracks = await _jioSaavn
              .getDynamicRecommendations()
              .timeout(const Duration(seconds: 6));
          if (tracks.isNotEmpty) return tracks;
        } catch (e) {
          print('[AURA-SM] Hybrid dynamic recs: JioSaavn failed ($e), trying YouTube');
        }
        return await _youTube.getDynamicRecommendations();
    }
  }

  @override
  Future<List<Track>> getContextualRecommendations(Track currentTrack) async {
    final mode = currentMode;

    if (mode == SourceMode.youtube || currentTrack.isYouTube) {
      final recs = await _youTube.getContextualRecommendations(currentTrack);
      if (recs.isNotEmpty) return recs;
      if (mode == SourceMode.hybrid) {
        return await _jioSaavn.getContextualRecommendations(currentTrack);
      }
      return [];
    }

    if (mode == SourceMode.jiosaavn) {
      return await _jioSaavn.getContextualRecommendations(currentTrack);
    }

    // Hybrid with JioSaavn track
    try {
      final recs = await _jioSaavn
          .getContextualRecommendations(currentTrack)
          .timeout(const Duration(seconds: 6));
      if (recs.isNotEmpty) return recs;
    } catch (e) {
      print('[AURA-SM] Hybrid contextual recs: JioSaavn failed ($e), trying YouTube');
    }
    return await _youTube.getContextualRecommendations(currentTrack);
  }

  @override
  Future<String?> getStreamUrl(Track track) async {
    final mode = currentMode;
    print('[AURA-SM] getStreamUrl for "${track.title}" (source: ${track.source}, mode: ${mode.name})');

    // If track is explicitly from YouTube, always resolve via YouTube
    if (track.isYouTube) {
      return await _youTube.getStreamUrl(track);
    }

    // If mode is YouTube-only (even if track metadata came from elsewhere)
    if (mode == SourceMode.youtube) {
      final ytUrl = await _resolveViaYouTubeFallback(track);
      return ytUrl;
    }

    // If mode is JioSaavn only
    if (mode == SourceMode.jiosaavn) {
      return await _jioSaavn.getStreamUrl(track);
    }

    // Hybrid mode: Try JioSaavn first
    try {
      final jioUrl = await _jioSaavn
          .getStreamUrl(track)
          .timeout(const Duration(seconds: 6));
      if (jioUrl != null && jioUrl.isNotEmpty) {
        return jioUrl;
      }
      print('[AURA-SM] JioSaavn returned null stream URL for "${track.title}", triggering YouTube fallback');
    } catch (e) {
      print('[AURA-SM] JioSaavn stream resolution failed/timed out for "${track.title}": $e');
    }

    // Fallback to YouTube in Hybrid mode
    final fallbackUrl = await _resolveViaYouTubeFallback(track);
    if (fallbackUrl != null) {
      fallbackNotifier.value = FallbackEvent(
        originalTrack: track,
        fallbackSource: 'YouTube',
        message: 'Playing "${track.title}" via YouTube fallback',
      );
    }
    return fallbackUrl;
  }

  void invalidateStreamCache(Track track) {
    final videoId = track.youtubeVideoId ?? (track.id.startsWith('yt_') ? track.id.substring(3) : null);
    if (videoId != null) {
      _youTube.invalidateCache(videoId);
    }
  }

  /// Always resolves a fresh stream URL (bypasses cache).
  /// Critical for YouTube tracks where cached URLs expire and cause 403 errors.
  Future<String?> getFreshStreamUrl(Track track) async {
    if (track.isYouTube) {
      return await _youTube.getFreshStreamUrl(track);
    }

    final mode = currentMode;
    if (mode == SourceMode.youtube) {
      // For non-YouTube tracks in YT-only mode, search YouTube fresh
      return await _resolveViaYouTubeFallbackFresh(track);
    }

    // For JioSaavn/hybrid with non-YT tracks, use normal resolution
    return await getStreamUrl(track);
  }

  /// Like _resolveViaYouTubeFallback but always fetches fresh stream URLs
  Future<String?> _resolveViaYouTubeFallbackFresh(Track track) async {
    print('[AURA-SM] Searching YouTube fallback (FRESH) for: "${track.title}" - "${track.artist}"');
    try {
      if (track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty) {
        final directUrl = await _youTube.getFreshStreamUrl(track);
        if (directUrl != null) return directUrl;
      }

      final cleanTitle = track.title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ').trim();
      final cleanArtist = track.artist.split(',').first.trim();
      final query = '$cleanArtist $cleanTitle audio';

      final candidates = await _youTube
          .searchTracks(query)
          .timeout(const Duration(seconds: 7));

      if (candidates.isEmpty) {
        final titleCandidates = await _youTube
            .searchTracks('$cleanTitle audio')
            .timeout(const Duration(seconds: 5));
        candidates.addAll(titleCandidates);
      }

      if (candidates.isEmpty) return null;

      final bestMatch = _findBestMatch(track, candidates);
      final target = bestMatch ?? candidates.first;
      return await _youTube.getFreshStreamUrl(target);
    } catch (e) {
      print('[AURA-SM] YouTube fallback (FRESH) error for "${track.title}": $e');
      return null;
    }
  }

  /// Searches YouTube for a matching track and resolves its stream URL
  Future<String?> _resolveViaYouTubeFallback(Track track) async {
    print('[AURA-SM] Searching YouTube fallback for: "${track.title}" - "${track.artist}"');
    try {
      // 1. If track already has a youtubeVideoId, fetch stream directly
      if (track.youtubeVideoId != null && track.youtubeVideoId!.isNotEmpty) {
        final directUrl = await _youTube.getStreamUrl(track);
        if (directUrl != null) return directUrl;
      }

      // 2. Query YouTube with "Artist Track audio"
      final cleanTitle = track.title.replaceAll(RegExp(r'\s*\(.*?\)\s*'), ' ').trim();
      final cleanArtist = track.artist.split(',').first.trim();
      final query = '$cleanArtist $cleanTitle audio';

      final candidates = await _youTube
          .searchTracks(query)
          .timeout(const Duration(seconds: 7));

      if (candidates.isEmpty) {
        // Fallback search with title only
        final titleCandidates = await _youTube
            .searchTracks('$cleanTitle audio')
            .timeout(const Duration(seconds: 5));
        candidates.addAll(titleCandidates);
      }

      if (candidates.isEmpty) {
        print('[AURA-SM] No YouTube fallback candidates found for: "${track.title}"');
        return null;
      }

      // 3. Find best match using match scoring
      final bestMatch = _findBestMatch(track, candidates);
      if (bestMatch != null) {
        print('[AURA-SM] Best YouTube match: "${bestMatch.title}" (${bestMatch.youtubeVideoId})');
        final streamUrl = await _youTube.getStreamUrl(bestMatch);
        return streamUrl;
      }

      // If scoring didn't pick, take first candidate
      final first = candidates.first;
      print('[AURA-SM] Taking first YouTube candidate: "${first.title}"');
      return await _youTube.getStreamUrl(first);
    } catch (e) {
      print('[AURA-SM] YouTube fallback error for "${track.title}": $e');
      return null;
    }
  }

  /// Match scoring algorithm to pick the most accurate YouTube candidate
  Track? _findBestMatch(Track target, List<Track> candidates) {
    if (candidates.isEmpty) return null;

    final targetTitleTokens = _tokenize(target.title);
    final targetArtistTokens = _tokenize(target.artist);
    final targetDurationSec = _parseDurationSeconds(target.duration);

    Track? bestTrack;
    double highestScore = -1.0;

    for (final candidate in candidates) {
      double score = 0.0;
      final candTitleTokens = _tokenize(candidate.title);
      final candArtistTokens = _tokenize(candidate.artist);

      // Title match overlap (0.0 to 0.5)
      int titleOverlap = 0;
      for (final token in targetTitleTokens) {
        if (candTitleTokens.contains(token)) titleOverlap++;
      }
      if (targetTitleTokens.isNotEmpty) {
        score += (titleOverlap / targetTitleTokens.length) * 0.5;
      }

      // Artist match overlap (0.0 to 0.3)
      int artistOverlap = 0;
      for (final token in targetArtistTokens) {
        if (candArtistTokens.contains(token) || candTitleTokens.contains(token)) {
          artistOverlap++;
        }
      }
      if (targetArtistTokens.isNotEmpty) {
        score += (artistOverlap / targetArtistTokens.length) * 0.3;
      }

      // Duration proximity (0.0 to 0.2)
      if (targetDurationSec > 0) {
        final candDurationSec = _parseDurationSeconds(candidate.duration);
        final diff = (targetDurationSec - candDurationSec).abs();
        if (diff <= 15) {
          score += 0.2;
        } else if (diff <= 45) {
          score += 0.1;
        } else if (diff > 120) {
          score -= 0.2; // penalty for big duration mismatch (e.g. podcast/compilation)
        }
      }

      if (score > highestScore) {
        highestScore = score;
        bestTrack = candidate;
      }
    }

    // Only accept match if minimum confidence met
    if (highestScore >= 0.35) {
      return bestTrack;
    }

    return candidates.first;
  }

  Set<String> _tokenize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((s) => s.length > 1)
        .toSet();
  }

  int _parseDurationSeconds(String duration) {
    try {
      final parts = duration.split(':');
      if (parts.length == 2) {
        return (int.parse(parts[0]) * 60) + int.parse(parts[1]);
      } else if (parts.length == 3) {
        return (int.parse(parts[0]) * 3600) + (int.parse(parts[1]) * 60) + int.parse(parts[2]);
      }
    } catch (_) {}
    return 0;
  }
}
