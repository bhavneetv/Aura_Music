import 'package:dio/dio.dart';
import '../../models/track.dart';

/// Multi-strategy audio URL resolver.
/// Primary strategy: Song ID lookup on saavn-api.vercel.app/song/[id]
/// which decrypts and returns fresh 200 OK playable CDN URLs.
class AudioUrlResolver {
  static final AudioUrlResolver instance = AudioUrlResolver._();
  AudioUrlResolver._();

  final Dio _dio = Dio(BaseOptions(
    connectTimeout: const Duration(seconds: 3),
    receiveTimeout: const Duration(seconds: 3),
    sendTimeout: const Duration(seconds: 2),
    headers: {
      'User-Agent':
          'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    },
  ));

  // Search API mirrors for re-search fallback (excludes saavn-api search which returns static Hindi songs)
  static const List<String> _searchMirrors = [
    'https://saavn.sumit.co/api',
    'https://jiosaavn-api-beta.vercel.app',
    'https://jiosaavn-api-unofficial.vercel.app',
  ];

  /// Resolves a working audio URL for the given track.
  Future<String?> resolveAudioUrl(Track track, {bool forceFresh = false}) async {
    print('[AURA-RESOLVER] resolveAudioUrl for: "${track.title}" (id: ${track.id}) forceFresh=$forceFresh');

    // Strategy 1: Original URL if it's already a direct CDN link
    if (!forceFresh && _isDirectCdnLink(track.audioUrl)) {
      print('[AURA-RESOLVER] Strategy 1: Using existing CDN link');
      String url = track.audioUrl;
      if (url.contains('saavncdn.com') && url.contains('_320.')) {
        url = url.replaceAll('_320.', '_160.');
      }
      return url;
    }

    // Strategy 2: Direct Song ID lookup on working JioSaavn API mirrors
    if (track.id.isNotEmpty) {
      final songByIdUrl = await _tryGetSongById(track.id);
      if (songByIdUrl != null) {
        print('[AURA-RESOLVER] Strategy 2 SUCCESS: Got live URL from song ID lookup');
        return songByIdUrl;
      }
    }

    // Strategy 3: Re-search by title+artist on working search mirrors
    final candidates = await _collectCandidateUrls(track);
    if (candidates.isNotEmpty) {
      final validUrl = await _findFirstPlayableUrl(candidates);
      if (validUrl != null) {
        print('[AURA-RESOLVER] Strategy 3 SUCCESS: Got validated URL from re-search');
        return validUrl;
      }
    }

    // Strategy 4: Return original URL as last resort if not forceFresh
    if (!forceFresh && track.audioUrl.startsWith('http')) {
      print('[AURA-RESOLVER] Returning original URL as last resort');
      String url = track.audioUrl;
      if (url.contains('saavncdn.com') && url.contains('_320.')) {
        url = url.replaceAll('_320.', '_160.');
      }
      return url;
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

  // ── Strategy 2: Song ID Lookup ──────────────────────────────────

  Future<String?> _tryGetSongById(String trackId) async {
    final endpoints = [
      'https://saavn.sumit.co/api/songs?ids=$trackId',
      'https://jiosaavn-api-beta.vercel.app/songs?id=$trackId',
      'https://jiosaavn-api-unofficial.vercel.app/songs?id=$trackId',
    ];

    for (final url in endpoints) {
      try {
        print('[AURA-RESOLVER] Trying song ID lookup: $url');
        final response = await _dio.get(url);
        if (response.statusCode == 200 && response.data != null) {
          final cdnUrl = _extractCdnUrlFromData(response.data);
          if (cdnUrl != null && _isDirectCdnLink(cdnUrl)) {
            if (await _isUrlPlayable(cdnUrl)) {
              return cdnUrl;
            } else {
              print('[AURA-RESOLVER] Strategy 2 CDN link expired (404/403): $cdnUrl');
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  // ── Strategy 3: Collect & validate candidate URLs ───────────────

  Future<List<String>> _collectCandidateUrls(Track track) async {
    final List<String> candidates = [];
    final query = '${track.title} ${track.artist}'.trim();
    if (query.isEmpty) return candidates;

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
              if (!candidates.contains(url)) candidates.add(url);
            }
          }
          if (candidates.length >= 6) break;
        } catch (_) {}
      }
      if (candidates.length >= 6) break;
    }

    return candidates;
  }

  // ── URL Validation Helpers ─────────────────────────────────────

  Future<String?> _findFirstPlayableUrl(List<String> urls) async {
    for (final url in urls) {
      if (await _isUrlPlayable(url)) {
        print('[AURA-RESOLVER] ✓ URL validated: ${url.length > 80 ? '${url.substring(0, 80)}...' : url}');
        return url;
      }
    }
    return null;
  }

  static const Map<String, String> _cdnHeaders = {
    'User-Agent': 'Mozilla/5.0 (Linux; Android 13) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36',
    'Referer': 'https://www.jiosaavn.com/',
  };

  Future<bool> _isUrlPlayable(String url) async {
    try {
      final response = await _dio.head(
        url,
        options: Options(
          receiveTimeout: const Duration(seconds: 3),
          followRedirects: true,
          headers: _cdnHeaders,
          validateStatus: (status) => status != null && status < 400,
        ),
      );
      return response.statusCode != null && response.statusCode! < 400;
    } catch (_) {
      try {
        final response = await _dio.get(
          url,
          options: Options(
            receiveTimeout: const Duration(seconds: 3),
            headers: {..._cdnHeaders, 'Range': 'bytes=0-512'},
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

  // ── Data Extraction Helpers ────────────────────────────────────

  String? _extractCdnUrlFromData(dynamic data) {
    if (data is Map) {
      // Check direct 'url' field (saavn-api.vercel.app returns direct CDN URL here)
      if (data['url'] != null) {
        final url = data['url'].toString();
        if (_isDirectCdnLink(url)) return url;
      }
      // Check nested under 'data'
      if (data['data'] != null) {
        final nested = _extractCdnUrlFromData(data['data']);
        if (nested != null) return nested;
      }
      return _extractCdnUrlFromItem(data);
    } else if (data is List && data.isNotEmpty) {
      for (final item in data) {
        final url = _extractCdnUrlFromData(item);
        if (url != null) return url;
      }
    }
    return null;
  }

  List<String> _extractMatchingUrls(dynamic data, Track originalTrack) {
    final results = _extractResultsList(data);
    if (results == null || results.isEmpty) return [];

    final targetTitle = originalTrack.title.trim().toLowerCase();
    final targetArtist = originalTrack.artist.trim().toLowerCase();
    final targetWords = _extractWords(targetTitle);
    final urls = <String>[];

    for (final item in results) {
      if (item is! Map) continue;
      final name = (item['name']?.toString() ?? item['title']?.toString() ?? '').toLowerCase();
      final artist = (item['artists']?.toString() ?? item['primaryArtists']?.toString() ?? '').toLowerCase();

      if (_titlesMatch(targetTitle, targetWords, name)) {
        if (targetArtist.isEmpty || _fuzzyContains(artist, targetArtist)) {
          final itemUrl = _extractCdnUrlFromItem(item);
          if (itemUrl != null && !urls.contains(itemUrl)) {
            urls.add(itemUrl);
          }
        }
      }
    }
    return urls;
  }

  String? _extractCdnUrlFromItem(Map item) {
    for (final key in ['downloadUrl', 'download_url']) {
      final val = item[key];
      if (val is List && val.isNotEmpty) {
        // 1. Prefer 160kbps link for 100% CDN reliability (prevents 404 errors)
        for (final d in val) {
          String link = '';
          String quality = '';
          if (d is Map) {
            link = d['url']?.toString() ?? d['link']?.toString() ?? '';
            quality = (d['quality'] ?? '').toString();
          } else if (d is String) {
            link = d;
          }
          if (link.isNotEmpty && _isDirectCdnLink(link) && (quality.contains('160') || link.contains('_160.'))) {
            return link;
          }
        }
        // 2. Fallback to any valid direct audio link
        for (final d in val) {
          String link = '';
          if (d is Map) {
            link = d['url']?.toString() ?? d['link']?.toString() ?? '';
          } else if (d is String) {
            link = d;
          }
          if (link.isNotEmpty && _isDirectCdnLink(link)) {
            return link;
          }
        }
      } else if (val is String && _isDirectCdnLink(val)) {
        return val;
      }
    }
    if (item['url'] != null) {
      final url = item['url'].toString();
      if (_isDirectCdnLink(url)) return url;
    }
    return null;
  }

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

  bool _isDirectCdnLink(String url) {
    if (url.isEmpty) return false;
    if (url.contains('saavn-api.vercel.app/song') ||
        url.contains('jiosaavn-api-beta.vercel.app/search')) {
      return false;
    }
    return url.contains('saavncdn.com') ||
        url.contains('sndsaavn.com') ||
        url.contains('jamendo.com') ||
        url.contains('soundhelix.com') ||
        url.contains('googlevideo.com') ||
        (url.startsWith('http') && (url.contains('.mp3') || url.contains('.mp4') || url.contains('.m4a') || url.contains('cdn')));
  }
}
