import 'package:dio/dio.dart';
import '../../models/track.dart';

/// Multi-strategy audio URL resolver with URL validation.
/// Re-searches by title+artist across multiple API mirrors,
/// validates CDN URLs with HEAD requests, and tries multiple
/// quality levels to find a working stream.
class AudioUrlResolver {
  static final AudioUrlResolver instance = AudioUrlResolver._();
  AudioUrlResolver._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 6),
    receiveTimeout: const Duration(seconds: 6),
    sendTimeout: const Duration(seconds: 3),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  // Search API mirrors — saavn-api.vercel.app returns valid 200 OK CDN URLs
  static const List<String> _searchMirrors = [
    'https://saavn-api.vercel.app',
    'https://jiosaavn-api-beta.vercel.app',
    'https://jiosaavn-api-unofficial.vercel.app',
  ];

  /// Resolves a working audio URL for the given track.
  Future<String?> resolveAudioUrl(Track track, {bool forceFresh = false}) async {
    print('[AURA-RESOLVER] resolveAudioUrl for: "${track.title}" (id: ${track.id}) forceFresh=$forceFresh');

    // Strategy 1: Original URL if it's a valid CDN link and we're not retrying
    if (!forceFresh && _isDirectCdnLink(track.audioUrl)) {
      print('[AURA-RESOLVER] Strategy 1: Using existing CDN link');
      return track.audioUrl;
    }

    // Strategy 2: Re-search across all mirrors, collect ALL candidate URLs,
    // then validate them with HEAD requests
    final candidates = await _collectCandidateUrls(track);
    if (candidates.isNotEmpty) {
      print('[AURA-RESOLVER] Collected ${candidates.length} candidate URLs, validating...');
      final validUrl = await _findFirstPlayableUrl(candidates);
      if (validUrl != null) {
        print('[AURA-RESOLVER] Strategy 2 SUCCESS: Validated working URL');
        return validUrl;
      }
    }

    // Strategy 3: Return original URL as last resort if not forceFresh
    if (!forceFresh && track.audioUrl.startsWith('http')) {
      print('[AURA-RESOLVER] Returning original URL as last resort');
      return track.audioUrl;
    }

    print('[AURA-RESOLVER] ALL strategies FAILED for: "${track.title}"');
    return null;
  }

  /// Resolves audio URLs for a list of tracks (batch).
  Future<List<Track>> resolveAll(List<Track> tracks) async {
    if (tracks.isEmpty) return [];
    final List<Track> resolved = [];
    for (final track in tracks) {
      if (_isDirectCdnLink(track.audioUrl)) {
        resolved.add(track);
      } else {
        final url = await resolveAudioUrl(track);
        if (url != null) {
          resolved.add(track.copyWith(audioUrl: url));
        } else {
          resolved.add(track);
        }
      }
    }
    return resolved;
  }

  // ── Collect candidate URLs from all mirrors ────────────────────

  Future<List<String>> _collectCandidateUrls(Track track) async {
    final List<String> candidates = [];
    final query = '${track.title} ${track.artist}'.trim();
    if (query.isEmpty) return candidates;

    // Also try title-only as a fallback query
    final queries = [query];
    if (track.artist.isNotEmpty) {
      queries.add(track.title.trim());
    }

    for (final mirror in _searchMirrors) {
      for (final q in queries) {
        try {
          print('[AURA-RESOLVER] Searching $mirror for "$q"');
          final response = await _dio.get(
            '$mirror/search/songs?query=${Uri.encodeComponent(q)}',
          );
          if (response.statusCode == 200 && response.data != null) {
            final urls = _extractMatchingUrls(response.data, track);
            for (final url in urls) {
              if (!candidates.contains(url)) {
                candidates.add(url);
              }
            }
            // Also generate quality variants for each CDN URL
            final variants = <String>[];
            for (final url in urls) {
              variants.addAll(_generateQualityVariants(url));
            }
            for (final v in variants) {
              if (!candidates.contains(v)) {
                candidates.add(v);
              }
            }
          }
          // If we already have enough candidates from this mirror, move on
          if (candidates.length >= 6) break;
        } catch (_) {}
      }
      if (candidates.length >= 6) break;
    }

    return candidates;
  }

  /// Given a CDN URL like .../hash_320.mp4, generate 160, 96, 48 variants
  List<String> _generateQualityVariants(String url) {
    final variants = <String>[];
    if (!url.contains('aac.saavncdn.com')) return variants;

    // Pattern: anything_320.mp4 → try _160.mp4, _96.mp4, _48.mp4
    final qualities = ['160', '96', '48', '320'];
    for (final q in qualities) {
      final variant = url.replaceFirst(RegExp(r'_\d+\.mp4$'), '_$q.mp4');
      if (variant != url && !variants.contains(variant)) {
        variants.add(variant);
      }
    }
    return variants;
  }

  // ── Validate URLs with HEAD request ────────────────────────────

  Future<String?> _findFirstPlayableUrl(List<String> urls) async {
    for (final url in urls) {
      if (await _isUrlPlayable(url)) {
        print('[AURA-RESOLVER] ✓ URL validated: ${url.length > 80 ? '${url.substring(0, 80)}...' : url}');
        return url;
      }
    }
    print('[AURA-RESOLVER] ✗ None of ${urls.length} candidate URLs passed HEAD check');
    return null;
  }

  Future<bool> _isUrlPlayable(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          followRedirects: true,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      return response.statusCode != null && response.statusCode! < 400;
    } catch (_) {
      // HEAD might not be supported, try a range GET instead
      try {
        final response = await _dio.get(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            headers: {'Range': 'bytes=0-512'},
            responseType: ResponseType.bytes,
            followRedirects: true,
            validateStatus: (status) => status != null && status < 400,
          ),
        );
        return response.statusCode != null && response.statusCode! < 400;
      } catch (_) {
        return false;
      }
    }
  }

  // ── URL Extraction with title matching ─────────────────────────

  /// Extract all CDN URLs from search results that match the track.
  List<String> _extractMatchingUrls(dynamic data, Track originalTrack) {
    final results = _extractResultsList(data);
    if (results == null || results.isEmpty) return [];

    final targetTitle = originalTrack.title.trim().toLowerCase();
    final targetArtist = originalTrack.artist.trim().toLowerCase();
    final targetWords = _extractWords(targetTitle);
    final urls = <String>[];

    // Pass 1: Title + artist match (highest confidence)
    for (final item in results) {
      if (item is! Map) continue;
      final name = (item['name']?.toString() ?? item['title']?.toString() ?? '').toLowerCase();
      final artist = (item['artists']?.toString() ??
              item['primaryArtists']?.toString() ??
              item['artist']?.toString() ??
              '')
          .toLowerCase();

      if (_titlesMatch(targetTitle, targetWords, name)) {
        if (targetArtist.isEmpty || _fuzzyContains(artist, targetArtist)) {
          final itemUrls = _extractAllCdnUrlsFromItem(item);
          print('[AURA-RESOLVER] Matched: "$name" by "$artist" → ${itemUrls.length} URLs');
          urls.addAll(itemUrls);
        }
      }
    }

    // Pass 2: Title match only (no artist requirement)
    if (urls.isEmpty) {
      for (final item in results) {
        if (item is! Map) continue;
        final name = (item['name']?.toString() ?? item['title']?.toString() ?? '').toLowerCase();
        if (_titlesMatch(targetTitle, targetWords, name)) {
          final itemUrls = _extractAllCdnUrlsFromItem(item);
          print('[AURA-RESOLVER] Title-only match: "$name" → ${itemUrls.length} URLs');
          urls.addAll(itemUrls);
        }
      }
    }

    if (urls.isEmpty) {
      print('[AURA-RESOLVER] No confident match found in ${results.length} results');
    }
    return urls;
  }

  // ── Extract ALL quality CDN URLs from a single result item ─────

  List<String> _extractAllCdnUrlsFromItem(Map item) {
    final urls = <String>[];

    // Check 'downloadUrl' / 'download_url' arrays (multiple quality levels)
    for (final key in ['downloadUrl', 'download_url']) {
      final val = item[key];
      if (val is List) {
        // Iterate all quality levels (reversed = highest first)
        for (final d in val.reversed) {
          if (d is Map) {
            final link = d['url']?.toString() ?? d['link']?.toString() ?? '';
            if (link.isNotEmpty && _isDirectCdnLink(link) && !urls.contains(link)) {
              urls.add(link);
            }
          } else if (d is String && _isDirectCdnLink(d) && !urls.contains(d)) {
            urls.add(d);
          }
        }
      } else if (val is String && _isDirectCdnLink(val) && !urls.contains(val)) {
        urls.add(val);
      }
    }

    // Check direct 'url' field
    if (item['url'] != null) {
      final url = item['url'].toString();
      if (_isDirectCdnLink(url) && !urls.contains(url)) {
        urls.add(url);
      }
    }

    // Check 'media_url'
    if (item['media_url'] != null) {
      final url = item['media_url'].toString();
      if (_isDirectCdnLink(url) && !urls.contains(url)) {
        urls.add(url);
      }
    }

    return urls;
  }

  // ── Results list extraction ────────────────────────────────────

  List? _extractResultsList(dynamic data) {
    if (data is List) return data;
    if (data is Map) {
      if (data['data'] is Map && data['data']['results'] is List) {
        return data['data']['results'];
      } else if (data['data'] is List) {
        return data['data'];
      } else if (data['results'] is List) {
        return data['results'];
      }
    }
    return null;
  }

  // ── Title matching helpers ─────────────────────────────────────

  bool _titlesMatch(String target, Set<String> targetWords, String candidate) {
    if (target == candidate) return true;
    if (target.isNotEmpty && candidate.isNotEmpty) {
      if (candidate.contains(target) || target.contains(candidate)) return true;
      if (targetWords.length >= 2) {
        final candidateWords = _extractWords(candidate);
        final overlap = targetWords.intersection(candidateWords).length;
        final ratio = overlap / targetWords.length;
        if (ratio >= 0.6) return true;
      }
    }
    return false;
  }

  bool _fuzzyContains(String haystack, String needle) {
    if (haystack.contains(needle) || needle.contains(haystack)) return true;
    final needleWords = _extractWords(needle);
    final haystackWords = _extractWords(haystack);
    if (needleWords.isEmpty) return true;
    final overlap = needleWords.intersection(haystackWords).length;
    return overlap / needleWords.length >= 0.5;
  }

  Set<String> _extractWords(String text) {
    return text
        .replaceAll(RegExp(r'[^a-z0-9\s]'), ' ')
        .split(RegExp(r'\s+'))
        .where((w) => w.length > 1)
        .toSet();
  }

  // ── CDN link detection ─────────────────────────────────────────

  bool _isDirectCdnLink(String url) {
    if (url.isEmpty) return false;
    if (url.contains('saavn-api.vercel.app') ||
        url.contains('jiosaavn-api') ||
        url.contains('jiosaavn.com') ||
        url.contains('saavn.dev/api') ||
        url.contains('vercel.app')) {
      return false;
    }
    return url.contains('aac.saavncdn.com') ||
        url.contains('sndsaavn.com') ||
        url.contains('soundhelix.com') ||
        (url.startsWith('http') && (url.endsWith('.mp3') || url.endsWith('.mp4') || url.endsWith('.m4a')));
  }
}
