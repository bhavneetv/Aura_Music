import 'dart:async';
import 'package:youtube_explode_dart/youtube_explode_dart.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';
import 'music_source.dart';

class _CachedStream {
  final String url;
  final DateTime expiry;
  final DateTime created;

  _CachedStream({required this.url, required this.expiry})
      : created = DateTime.now();

  bool get isExpired => DateTime.now().isAfter(expiry);

  /// Returns true if the cached URL is "stale" — older than the given duration.
  /// Even if not technically expired, stale URLs are risky for playback.
  bool isOlderThan(Duration duration) =>
      DateTime.now().difference(created) > duration;
}

class YouTubeSource implements MusicSource {
  static final YouTubeSource instance = YouTubeSource._();
  YouTubeSource._();
  factory YouTubeSource() => instance;

  static YoutubeExplode? _client;
  static YoutubeExplode get _yt => _client ??= YoutubeExplode();

  static void resetClient() {
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
  }

  // Stream URL cache with 30-minute TTL (YouTube streaming URLs expire unpredictably,
  // and stale URLs cause 403 Forbidden errors on ExoPlayer)
  final Map<String, _CachedStream> _streamCache = {};

  @override
  String get name => 'YouTube';

  // Keyword blacklist to avoid non-music videos (PRD §8.3)
  static const List<String> _blacklistedKeywords = [
    'tutorial',
    'reaction',
    'review',
    'how to',
    'unboxing',
    'vlog',
    'gameplay',
    '1 hour',
    '10 hours',
    '1 hr',
    'podcast',
    'interview',
    'talk show',
    'audiobook',
    'speed build',
    'full episode',
  ];

  @override
  Future<List<Track>> searchTracks(String query) async {
    final trimmed = query.trim();
    if (trimmed.isEmpty) return getTrendingTracks();

    print('[AURA-YT] Searching YouTube for: "$trimmed"');
    try {
      final searchResults = await _yt.search
          .search(trimmed)
          .timeout(const Duration(seconds: 8));

      final tracks = <Track>[];
      for (final video in searchResults) {
        if (_shouldSkipVideo(video, trimmed)) continue;

        final track = _videoToTrack(video);
        if (track != null) {
          tracks.add(track);
          if (tracks.length >= 25) break;
        }
      }

      print('[AURA-YT] Search found ${tracks.length} music tracks for: "$trimmed"');
      return tracks;
    } catch (e) {
      print('[AURA-YT] Search error for "$trimmed": $e');
      return [];
    }
  }

  @override
  Future<List<Track>> getTrendingTracks() async {
    try {
      final preferredLangs = StorageService.getPreferredLanguages();
      String query = 'trending music songs';
      if (preferredLangs.isNotEmpty) {
        query = 'trending ${preferredLangs.first} songs';
      }
      return await searchTracks(query);
    } catch (e) {
      print('[AURA-YT] getTrendingTracks error: $e');
      return [];
    }
  }

  @override
  Future<List<Track>> getTracksByGenre(String genre) async {
    try {
      return await searchTracks('$genre songs');
    } catch (e) {
      print('[AURA-YT] getTracksByGenre error: $e');
      return [];
    }
  }

  @override
  Future<List<Track>> getDynamicRecommendations() async {
    try {
      final history = StorageService.getListeningHistory();
      if (history.isNotEmpty) {
        final last = history.first;
        final artist = last['artist']?.toString() ?? '';
        final genre = last['genre']?.toString() ?? '';
        if (artist.isNotEmpty) {
          return await searchTracks('$artist top songs');
        } else if (genre.isNotEmpty) {
          return await searchTracks('$genre music');
        }
      }
      return await getTrendingTracks();
    } catch (e) {
      print('[AURA-YT] getDynamicRecommendations error: $e');
      return [];
    }
  }

  @override
  Future<List<Track>> getContextualRecommendations(Track currentTrack) async {
    try {
      // If we have a YouTube video ID, try related videos first
      final videoIdStr = currentTrack.youtubeVideoId ?? _extractVideoIdFromTrackId(currentTrack.id);
      if (videoIdStr != null && videoIdStr.isNotEmpty) {
        try {
          final video = await _yt.videos.get(VideoId(videoIdStr)).timeout(const Duration(seconds: 5));
          final related = await _yt.videos.getRelatedVideos(video).timeout(const Duration(seconds: 6));
          if (related != null && related.isNotEmpty) {
            final tracks = <Track>[];
            for (final rel in related) {
              if (_shouldSkipVideo(rel, '')) continue;
              final t = _videoToTrack(rel);
              if (t != null) {
                tracks.add(t);
                if (tracks.length >= 15) break;
              }
            }
            if (tracks.isNotEmpty) {
              return tracks;
            }
          }
        } catch (e) {
          print('[AURA-YT] Related videos lookup failed: $e');
        }
      }

      // Fallback: search by artist & genre
      final artist = currentTrack.artist.split(',').first.trim();
      final query = artist.isNotEmpty
          ? '$artist ${currentTrack.genre} songs'
          : '${currentTrack.title} similar songs';
      return await searchTracks(query);
    } catch (e) {
      print('[AURA-YT] getContextualRecommendations error: $e');
      return [];
    }
  }

  @override
  Future<String?> getStreamUrl(Track track) async {
    final videoIdStr = track.youtubeVideoId ?? _extractVideoIdFromTrackId(track.id);
    if (videoIdStr == null || videoIdStr.isEmpty) {
      print('[AURA-YT] getStreamUrl: No YouTube video ID found for track "${track.title}"');
      return null;
    }

    // Check cache — only use if fresh (< 20 minutes old)
    final cached = _streamCache[videoIdStr];
    if (cached != null && !cached.isExpired && !cached.isOlderThan(const Duration(minutes: 20))) {
      print('[AURA-YT] getStreamUrl: Cache HIT for video $videoIdStr (age: ${DateTime.now().difference(cached.created).inMinutes}m)');
      return cached.url;
    }

    // Cache is stale or missing — resolve fresh
    if (cached != null) {
      print('[AURA-YT] getStreamUrl: Cache STALE for video $videoIdStr (age: ${DateTime.now().difference(cached.created).inMinutes}m), refreshing...');
      _streamCache.remove(videoIdStr);
    }

    print('[AURA-YT] Resolving fresh audio stream for video: $videoIdStr ("${track.title}")');
    try {
      return await _fetchStreamWithRetry(videoIdStr);
    } catch (e) {
      print('[AURA-YT] Failed to resolve stream for $videoIdStr: $e');
      // Reset client in case of corrupted connection
      resetClient();
      return null;
    }
  }

  /// Always resolves a fresh stream URL, bypassing any cache.
  /// Use this for immediate playback to avoid 403 errors from stale URLs.
  Future<String?> getFreshStreamUrl(Track track) async {
    final videoIdStr = track.youtubeVideoId ?? _extractVideoIdFromTrackId(track.id);
    if (videoIdStr == null || videoIdStr.isEmpty) return null;

    // Invalidate any existing cache entry
    _streamCache.remove(videoIdStr);

    print('[AURA-YT] getFreshStreamUrl: Force-resolving stream for $videoIdStr ("${track.title}")');
    try {
      return await _fetchStreamWithRetry(videoIdStr);
    } catch (e) {
      print('[AURA-YT] getFreshStreamUrl failed for $videoIdStr: $e');
      resetClient();
      return null;
    }
  }

  void invalidateCache(String videoId) {
    _streamCache.remove(videoId);
  }

  void clearAllCache() {
    _streamCache.clear();
  }

  Future<String?> _fetchStreamWithRetry(String videoIdStr, {int retryCount = 1}) async {
    for (int attempt = 0; attempt <= retryCount; attempt++) {
      try {
        final videoId = VideoId(videoIdStr);
        final manifest = await _yt.videos.streamsClient
            .getManifest(videoId)
            .timeout(const Duration(seconds: 8));

        final audioStreams = manifest.audioOnly;
        if (audioStreams.isNotEmpty) {
          // Prefer MP4/AAC (e.g. itag 140) for universal hardware decoding in Android ExoPlayer
          final mp4Streams = audioStreams.where((s) => s.container.name.toLowerCase() == 'mp4').toList();
          final bestAudio = mp4Streams.isNotEmpty
              ? mp4Streams.withHighestBitrate()
              : audioStreams.withHighestBitrate();
          final streamUrl = bestAudio.url.toString();

          // Cache for 30 minutes (YouTube URLs expire unpredictably)
          _streamCache[videoIdStr] = _CachedStream(
            url: streamUrl,
            expiry: DateTime.now().add(const Duration(minutes: 30)),
          );

          print('[AURA-YT] Successfully resolved stream (${bestAudio.container.name}, ${bestAudio.bitrate}) for $videoIdStr');
          return streamUrl;
        }

        // Fallback to muxed stream if no audio-only
        if (manifest.muxed.isNotEmpty) {
          final bestMuxed = manifest.muxed.withHighestBitrate();
          final streamUrl = bestMuxed.url.toString();
          _streamCache[videoIdStr] = _CachedStream(
            url: streamUrl,
            expiry: DateTime.now().add(const Duration(minutes: 30)),
          );
          return streamUrl;
        }

        return null;
      } catch (e) {
        print('[AURA-YT] Stream attempt $attempt failed for $videoIdStr: $e');
        if (attempt < retryCount) {
          resetClient();
          await Future.delayed(const Duration(milliseconds: 500));
        } else {
          rethrow;
        }
      }
    }
    return null;
  }

  bool _shouldSkipVideo(Video video, String searchQuery) {
    // Skip live streams
    if (video.isLive) return true;

    // Video duration filter (PRD §8.3): 45s to 900s (15 mins)
    final dur = video.duration;
    if (dur != null) {
      if (dur.inSeconds < 45 || dur.inSeconds > 900) {
        return true;
      }
    }

    final titleLower = video.title.toLowerCase();
    final queryLower = searchQuery.toLowerCase();

    // Blacklist filter (skip if query doesn't explicitly look for it)
    for (final keyword in _blacklistedKeywords) {
      if (titleLower.contains(keyword) && !queryLower.contains(keyword)) {
        return true;
      }
    }

    return false;
  }

  Track? _videoToTrack(Video video) {
    final videoId = video.id.value;
    if (videoId.isEmpty) return null;

    final parsed = _parseTitleAndArtist(video.title, video.author);

    // Thumbnail selection
    String artwork = '';
    try {
      final thumbs = video.thumbnails;
      artwork = thumbs.highResUrl.isNotEmpty
          ? thumbs.highResUrl
          : (thumbs.mediumResUrl.isNotEmpty
              ? thumbs.mediumResUrl
              : thumbs.lowResUrl);
    } catch (_) {}
    if (artwork.isEmpty) {
      artwork = 'https://i.ytimg.com/vi/$videoId/hqdefault.jpg';
    }

    final durationSeconds = video.duration?.inSeconds ?? 210;
    final durationStr = _formatDuration(durationSeconds);

    return Track(
      id: 'yt_$videoId',
      title: parsed.title,
      artist: parsed.artist,
      album: 'YouTube',
      duration: durationStr,
      artworkUrl: artwork,
      audioUrl: '', // lazily resolved on stream
      genre: 'YouTube',
      source: 'youtube',
      youtubeVideoId: videoId,
    );
  }

  _TitleArtist _parseTitleAndArtist(String rawTitle, String channelName) {
    String cleanTitle = _cleanVideoTitle(rawTitle);
    String artist = channelName;

    // Check if title is formatted as "Artist - Title" or "Artist – Title"
    final hyphenDelimiters = [' - ', ' – ', ' — ', ' // '];
    for (final delimiter in hyphenDelimiters) {
      if (cleanTitle.contains(delimiter)) {
        final parts = cleanTitle.split(delimiter);
        if (parts.length >= 2) {
          final possibleArtist = parts[0].trim();
          final possibleTitle = parts.sublist(1).join(delimiter).trim();
          if (possibleArtist.isNotEmpty && possibleTitle.isNotEmpty) {
            artist = possibleArtist;
            cleanTitle = possibleTitle;
            break;
          }
        }
      }
    }

    // Clean channel name clutter (e.g. " - Topic", "VEVO")
    artist = artist
        .replaceAll(RegExp(r'\s*-\s*Topic$', caseSensitive: false), '')
        .replaceAll(RegExp(r'VEVO$', caseSensitive: false), '')
        .trim();

    if (artist.isEmpty) artist = channelName;
    if (cleanTitle.isEmpty) cleanTitle = rawTitle;

    return _TitleArtist(title: cleanTitle, artist: artist);
  }

  String _cleanVideoTitle(String title) {
    String cleaned = title;

    // Remove bracketed/parenthesized noise (Official Video, Lyrics, etc.)
    final noisePatterns = [
      RegExp(
        r'\s*[\(\[]\s*(official\s*(music\s*)?video|official\s*audio|music\s*video|lyric\s*video|lyrics|audio|visualizer|4k|hd|hq|extended|clean|explicit|prod\.[^\)\]]*)\s*[\)\]]',
        caseSensitive: false,
      ),
      RegExp(
        r'\s*\|\s*(official\s*(music\s*)?video|full\s*song|official\s*audio|audio\s*song).*$',
        caseSensitive: false,
      ),
      RegExp(r'^\s*official\s*audio\s*:\s*', caseSensitive: false),
    ];

    for (final pattern in noisePatterns) {
      cleaned = cleaned.replaceAll(pattern, '');
    }

    return cleaned.trim();
  }

  String? _extractVideoIdFromTrackId(String trackId) {
    if (trackId.startsWith('yt_')) {
      return trackId.substring(3);
    }
    return null;
  }

  String _formatDuration(int seconds) {
    final minutes = seconds ~/ 60;
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }
}

class _TitleArtist {
  final String title;
  final String artist;
  _TitleArtist({required this.title, required this.artist});
}
