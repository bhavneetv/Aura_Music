import 'dart:convert';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/track.dart';
import '../handoff/nearby_handoff_service.dart';

class DecodedPlaylistLink {
  final String title;
  final String description;
  final List<Track> tracks;

  DecodedPlaylistLink({
    required this.title,
    required this.description,
    required this.tracks,
  });
}

class PlaylistImportEvent {
  final String title;
  final String description;
  final int trackCount;
  final List<Track> tracks;
  final bool fromQrScan;

  PlaylistImportEvent({
    required this.title,
    required this.description,
    required this.trackCount,
    required this.tracks,
    this.fromQrScan = false,
  });
}

class PlaylistLinkShareService {
  PlaylistLinkShareService._();
  static final PlaylistLinkShareService instance = PlaylistLinkShareService._();

  static PlaylistImportEvent? pendingImportEvent;
  static final ValueNotifier<PlaylistImportEvent?> importEventNotifier =
      ValueNotifier<PlaylistImportEvent?>(null);

  static void notifyImport(PlaylistImportEvent event) {
    pendingImportEvent = event;
    importEventNotifier.value = event;
  }

  static PlaylistImportEvent? consumePendingEvent() {
    final event = pendingImportEvent ?? importEventNotifier.value;
    pendingImportEvent = null;
    importEventNotifier.value = null;
    return event;
  }

  static const String linkPrefix = 'aura://share?p=';
  static const String shortLinkPrefix = 'aura://share?dp=';
  static const String idsLinkPrefix = 'aura://share?ids=';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 5),
      receiveTimeout: const Duration(seconds: 5),
      headers: {
        'User-Agent': 'AuraMusic/4.0 (Mobile)',
      },
    ),
  );

  /// Generate ultra-short 14-character link & low-density QR code via zero-config anonymous paste APIs for 5-500 songs
  Future<String> generateShareableLinkAsync(
    String title,
    String description,
    List<Track> tracks,
  ) async {
    try {
      final compactMap = {
        't': title.trim().isEmpty ? 'Aura Playlist' : title.trim(),
        'd': description.trim(),
        'k': tracks.map((tr) {
          final cleanArt = _stripQuery(tr.artworkUrl);
          return [
            tr.id,
            tr.title,
            tr.artist,
            cleanArt,
            tr.genre,
          ];
        }).toList(),
      };

      final jsonStr = jsonEncode(compactMap);

      // Method 1: dpaste.org API
      try {
        final response = await _dio.post(
          'https://dpaste.org/api/',
          data: {
            'content': jsonStr,
            'expiry_days': '365',
            'format': 'url',
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200 && response.data != null) {
          final respStr = response.data.toString().trim();
          if (respStr.contains('dpaste.org/')) {
            final shortId = respStr.split('dpaste.org/').last.replaceAll('/', '').trim();
            if (shortId.isNotEmpty) {
              debugPrint('[PlaylistLinkShare] Successfully created dpaste.org short code: $shortId');
              return '$shortLinkPrefix$shortId';
            }
          }
        }
      } catch (e) {
        debugPrint('[PlaylistLinkShare] dpaste.org API attempt failed: $e');
      }

      // Method 2: dpaste.com API (Secondary anonymous relay)
      try {
        final response = await _dio.post(
          'https://dpaste.com/api/v2/',
          data: {
            'content': jsonStr,
            'expiry_days': '365',
          },
          options: Options(
            contentType: Headers.formUrlEncodedContentType,
            responseType: ResponseType.plain,
            validateStatus: (status) => status != null && status < 500,
          ),
        );

        if (response.statusCode == 200 || response.statusCode == 201) {
          final respStr = response.data.toString().trim();
          if (respStr.contains('dpaste.com/')) {
            final shortId = respStr.split('dpaste.com/').last.replaceAll('/', '').replaceAll('.txt', '').trim();
            if (shortId.isNotEmpty) {
              debugPrint('[PlaylistLinkShare] Successfully created dpaste.com short code: $shortId');
              return 'aura://share?dpc=$shortId';
            }
          }
        }
      } catch (e) {
        debugPrint('[PlaylistLinkShare] dpaste.com API attempt failed: $e');
      }

      // Method 3: Ultra-short IDs link if tracks have valid short IDs
      final trackIds = tracks.map((t) => t.id).where((id) => id.isNotEmpty).toList();
      if (trackIds.length == tracks.length && trackIds.join(',').length < 120) {
        return '$idsLinkPrefix${trackIds.join(',')}';
      }

      // Method 4: Fallback to ultra-compact ID-only string
      return generateShareableLink(title, description, tracks);
    } catch (e) {
      debugPrint('[PlaylistLinkShare] Error generating share link: $e');
      return generateShareableLink(title, description, tracks);
    }
  }

  /// Synchronous local compression fallback
  String generateShareableLink(
    String title,
    String description,
    List<Track> tracks,
  ) {
    try {
      final compactList = tracks.map((tr) {
        final cleanArt = _stripQuery(tr.artworkUrl);
        return [
          tr.id,
          tr.title,
          tr.artist,
          cleanArt,
        ];
      }).toList();

      final jsonStr = jsonEncode(compactList);
      final jsonBytes = utf8.encode(jsonStr);
      final compressedBytes = gzip.encode(jsonBytes);
      final base64String = base64Url.encode(compressedBytes);

      return '$linkPrefix$base64String';
    } catch (e) {
      debugPrint('[PlaylistLinkShare] Error generating compressed share link: $e');
      return '';
    }
  }

  /// Decode compressed Base64 URL or short relay link back into a full Playlist object with zero server/database calls
  Future<DecodedPlaylistLink?> decodeShareableLinkAsync(String rawInput) async {
    if (rawInput.trim().isEmpty) return null;

    try {
      String cleanInput = rawInput.trim();
      // Strip outer quotes or markdown backticks
      cleanInput = cleanInput.replaceAll(RegExp(r'^["`\x27]+|["`\x27]+$'), '').trim();

      // Handle URL-encoded links (e.g., aura%3A%2F%2Fshare)
      if (cleanInput.contains('%3A') || cleanInput.contains('%2F') || cleanInput.contains('%3F')) {
        try {
          cleanInput = Uri.decodeFull(cleanInput);
        } catch (_) {}
      }

      // 1. Check if P2P local Wi-Fi IP/port address embedded in URL
      if (cleanInput.contains('ip=') && cleanInput.contains('port=')) {
        try {
          final uri = Uri.tryParse(cleanInput);
          if (uri != null) {
            final ip = uri.queryParameters['ip'];
            final port = int.tryParse(uri.queryParameters['port'] ?? '8899');
            if (ip != null && port != null) {
              final payload = await NearbyHandoffService.instance.fetchPayloadFromAddress(ip, port);
              if (payload != null && payload.tracks.isNotEmpty) {
                return DecodedPlaylistLink(
                  title: payload.title,
                  description: 'Received via Local P2P Wi-Fi from ${payload.senderName}',
                  tracks: payload.tracks,
                );
              }
            }
          }
        } catch (e) {
          debugPrint('[PlaylistLinkShare] Local P2P fetch failed: $e');
        }
      }

      // 2. Extract potential query parameters
      String? dpCode; // dpaste.org
      String? dpcCode; // dpaste.com
      String? pCode; // compressed base64
      String? idsCode; // track IDs

      try {
        final uri = Uri.tryParse(cleanInput);
        if (uri != null && uri.queryParameters.isNotEmpty) {
          dpCode = uri.queryParameters['dp'];
          dpcCode = uri.queryParameters['dpc'];
          pCode = uri.queryParameters['p'];
          idsCode = uri.queryParameters['ids'];
        }
      } catch (_) {}

      // Regex fallbacks for custom schemes or unparsed query parameters
      if (dpCode == null) {
        final m = RegExp(r'[?&]dp=([^&\s]+)').firstMatch(cleanInput);
        if (m != null) dpCode = m.group(1);
      }
      if (dpcCode == null) {
        final m = RegExp(r'[?&]dpc=([^&\s]+)').firstMatch(cleanInput);
        if (m != null) dpcCode = m.group(1);
      }
      if (pCode == null) {
        // Specifically match p= preceded by ? or & or start-of-string (never dp=)
        final m = RegExp(r'(?:[?&]|^)p=([^&\s]+)').firstMatch(cleanInput);
        if (m != null) pCode = m.group(1);
      }
      if (idsCode == null) {
        final m = RegExp(r'[?&]ids=([^&\s]+)').firstMatch(cleanInput);
        if (m != null) idsCode = m.group(1);
      }

      // Direct dpaste.org URL (e.g., https://dpaste.org/uqPhU or https://dpaste.org/uqPhU/raw)
      if (cleanInput.contains('dpaste.org/')) {
        final afterHost = cleanInput.split('dpaste.org/').last;
        final cleanSegment = afterHost.split('?').first.split('#').first.replaceAll('/raw', '').replaceAll('.raw', '').replaceAll('/', '').trim();
        if (cleanSegment.isNotEmpty) dpCode = cleanSegment;
      }

      // Direct dpaste.com URL (e.g., https://dpaste.com/EJ76BFXSW or https://dpaste.com/EJ76BFXSW.txt)
      if (cleanInput.contains('dpaste.com/')) {
        final afterHost = cleanInput.split('dpaste.com/').last;
        final cleanSegment = afterHost.split('?').first.split('#').first.replaceAll('.txt', '').replaceAll('/', '').trim();
        if (cleanSegment.isNotEmpty) dpcCode = cleanSegment;
      }

      // 3. Resolve dpaste.org code if present
      if (dpCode != null && dpCode.isNotEmpty) {
        final result = await _fetchFromDpasteOrg(dpCode);
        if (result != null) return result;
      }

      // 4. Resolve dpaste.com code if present
      if (dpcCode != null && dpcCode.isNotEmpty) {
        final result = await _fetchFromDpasteCom(dpcCode);
        if (result != null) return result;
      }

      // 5. Resolve track IDs list if present
      if (idsCode != null && idsCode.isNotEmpty) {
        final result = _parseTrackIds(idsCode);
        if (result != null) return result;
      }

      // 6. Resolve compressed base64 payload if present
      if (pCode != null && pCode.isNotEmpty) {
        final result = decodeShareableLink(pCode);
        if (result != null) return result;
      }

      // 7. Check if user pasted a raw alphanumeric short code without any URL prefix
      // (e.g. "uqPhU" or "EJ76BFXSW")
      final alphanumericOnly = cleanInput.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '').trim();
      if (!cleanInput.contains('://') &&
          !cleanInput.contains('&') &&
          !cleanInput.contains('=') &&
          alphanumericOnly.length >= 3 &&
          alphanumericOnly.length <= 35) {
        // dpaste.org IDs are usually 5-7 chars; dpaste.com IDs are usually 8-12 chars
        if (alphanumericOnly.length <= 7) {
          final resOrg = await _fetchFromDpasteOrg(alphanumericOnly);
          if (resOrg != null) return resOrg;
          final resCom = await _fetchFromDpasteCom(alphanumericOnly);
          if (resCom != null) return resCom;
        } else {
          final resCom = await _fetchFromDpasteCom(alphanumericOnly);
          if (resCom != null) return resCom;
          final resOrg = await _fetchFromDpasteOrg(alphanumericOnly);
          if (resOrg != null) return resOrg;
        }
      }

      // 8. Fallback to synchronous decode
      return decodeShareableLink(cleanInput);
    } catch (e) {
      debugPrint('[PlaylistLinkShare] Async decode error: $e');
      return decodeShareableLink(rawInput);
    }
  }

  /// Fetches playlist payload from dpaste.org via the /raw endpoint
  Future<DecodedPlaylistLink?> _fetchFromDpasteOrg(String code) async {
    final cleanCode = code.replaceAll('/', '').replaceAll('.raw', '').trim();
    if (cleanCode.isEmpty) return null;

    // Try https://dpaste.org/$cleanCode/raw
    try {
      final response = await _dio.get(
        'https://dpaste.org/$cleanCode/raw',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final dataStr = response.data.toString().trim();
        if (dataStr.startsWith('{') && dataStr.endsWith('}')) {
          final parsedMap = jsonDecode(dataStr) as Map<String, dynamic>;
          return _parsePlaylistMap(parsedMap);
        }
      }
    } catch (e) {
      debugPrint('[PlaylistLinkShare] dpaste.org /raw error: $e');
    }

    // Secondary attempt with text/plain Accept header
    try {
      final response = await _dio.get(
        'https://dpaste.org/$cleanCode',
        options: Options(
          headers: {'Accept': 'text/plain'},
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final dataStr = response.data.toString().trim();
        if (dataStr.startsWith('{') && dataStr.endsWith('}')) {
          final parsedMap = jsonDecode(dataStr) as Map<String, dynamic>;
          return _parsePlaylistMap(parsedMap);
        }
      }
    } catch (e) {
      debugPrint('[PlaylistLinkShare] dpaste.org text/plain error: $e');
    }

    return null;
  }

  /// Fetches playlist payload from dpaste.com via the .txt endpoint
  Future<DecodedPlaylistLink?> _fetchFromDpasteCom(String code) async {
    final cleanCode = code.replaceAll('/', '').replaceAll('.txt', '').trim();
    if (cleanCode.isEmpty) return null;

    try {
      final response = await _dio.get(
        'https://dpaste.com/$cleanCode.txt',
        options: Options(
          responseType: ResponseType.plain,
          validateStatus: (status) => status != null && status < 500,
        ),
      );
      if (response.statusCode == 200 && response.data != null) {
        final dataStr = response.data.toString().trim();
        if (dataStr.startsWith('{') && dataStr.endsWith('}')) {
          final parsedMap = jsonDecode(dataStr) as Map<String, dynamic>;
          return _parsePlaylistMap(parsedMap);
        }
      }
    } catch (e) {
      debugPrint('[PlaylistLinkShare] dpaste.com fetch error: $e');
    }

    return null;
  }

  /// Parses comma-separated track IDs list into playlist tracks
  DecodedPlaylistLink? _parseTrackIds(String idsStr) {
    final idsList = idsStr.split(',').map((id) => id.trim()).where((id) => id.isNotEmpty).toList();
    if (idsList.isEmpty) return null;

    final List<Track> tracks = [];
    for (final id in idsList) {
      final match = Track.mockTracks.firstWhere(
        (t) => t.id == id,
        orElse: () => Track(
          id: id,
          title: 'Track $id',
          artist: 'Shared Artist',
          album: 'Single',
          duration: '3:30',
          artworkUrl: '',
          audioUrl: '',
          genre: 'POP',
        ),
      );
      tracks.add(match);
    }
    return DecodedPlaylistLink(
      title: 'Shared Mix',
      description: 'Imported via Track IDs',
      tracks: tracks,
    );
  }

  /// Decode compressed Base64 URL string safely
  DecodedPlaylistLink? decodeShareableLink(String rawInput) {
    if (rawInput.trim().isEmpty) return null;

    try {
      String cleanCode = rawInput.trim();

      // If query string has p=, isolate ONLY the p parameter (never dp=)
      final pMatch = RegExp(r'(?:[?&]|^)p=([^&\s]+)').firstMatch(cleanCode);
      if (pMatch != null) {
        cleanCode = pMatch.group(1)!;
      } else if (cleanCode.startsWith('aura://') || cleanCode.startsWith('https://')) {
        try {
          final uri = Uri.parse(cleanCode);
          cleanCode = uri.queryParameters['p'] ?? (uri.pathSegments.isNotEmpty ? uri.pathSegments.last : '');
        } catch (_) {}
      }

      cleanCode = cleanCode.trim();
      if (cleanCode.isEmpty) return null;

      // Base64 mathematical rule: length % 4 can NEVER be 1
      // (1 character = 6 bits, cannot encode any whole byte = 8 bits)
      if (cleanCode.length % 4 == 1) {
        return null;
      }

      // Verify that cleanCode consists strictly of valid Base64 / Base64Url characters
      if (!RegExp(r'^[A-Za-z0-9_-]+={0,2}$').hasMatch(cleanCode)) {
        return null;
      }

      // Minimum meaningful compressed JSON payload is >= 8 characters
      if (cleanCode.replaceAll('=', '').length < 8) {
        return null;
      }

      // Pad missing Base64 characters (only 0, 1, or 2 '=' characters allowed)
      int padLen = (4 - (cleanCode.length % 4)) % 4;
      if (padLen > 2) return null;
      cleanCode = cleanCode + ('=' * padLen);

      final compressedBytes = base64Url.decode(cleanCode);

      // Verify Gzip magic bytes header (0x1F, 0x8B)
      if (compressedBytes.length >= 2 && compressedBytes[0] == 0x1F && compressedBytes[1] == 0x8B) {
        final jsonBytes = gzip.decode(compressedBytes);
        final jsonStr = utf8.decode(jsonBytes);

        final dynamic parsed = jsonDecode(jsonStr);
        if (parsed is Map<String, dynamic>) {
          return _parsePlaylistMap(parsed);
        } else if (parsed is List) {
          return _parseTrackList(parsed);
        }
      } else {
        // Fallback: check if raw uncompressed UTF8 JSON bytes
        try {
          final jsonStr = utf8.decode(compressedBytes);
          final dynamic parsed = jsonDecode(jsonStr);
          if (parsed is Map<String, dynamic>) {
            return _parsePlaylistMap(parsed);
          } else if (parsed is List) {
            return _parseTrackList(parsed);
          }
        } catch (_) {}
      }

      return null;
    } catch (e) {
      debugPrint('[PlaylistLinkShare] Error decoding share link: $e');
      return null;
    }
  }

  DecodedPlaylistLink _parsePlaylistMap(Map<String, dynamic> parsedMap) {
    final title = parsedMap['t']?.toString() ?? 'Imported Playlist';
    final description = parsedMap['d']?.toString() ?? 'Imported via Short Link';
    final List rawTracksList = parsedMap['k'] as List? ?? [];

    final List<Track> tracks = [];
    for (final item in rawTracksList) {
      if (item is List && item.isNotEmpty) {
        final id = item[0]?.toString() ?? '';
        final tTitle = item.length > 1 ? item[1]?.toString() ?? 'Track' : 'Track';
        final artist = item.length > 2 ? item[2]?.toString() ?? 'Unknown Artist' : 'Unknown Artist';
        final art = item.length > 3 ? item[3]?.toString() ?? '' : '';
        final genre = item.length > 4 ? item[4]?.toString() ?? '' : '';

        tracks.add(
          Track(
            id: id,
            title: tTitle,
            artist: artist,
            album: 'Single',
            duration: '3:30',
            artworkUrl: art,
            audioUrl: '',
            genre: genre,
          ),
        );
      }
    }

    return DecodedPlaylistLink(
      title: title,
      description: description,
      tracks: tracks,
    );
  }

  DecodedPlaylistLink _parseTrackList(List rawTracksList) {
    final List<Track> tracks = [];
    for (final item in rawTracksList) {
      if (item is List && item.isNotEmpty) {
        final id = item[0]?.toString() ?? '';
        final tTitle = item.length > 1 ? item[1]?.toString() ?? 'Track' : 'Track';
        final artist = item.length > 2 ? item[2]?.toString() ?? 'Unknown Artist' : 'Unknown Artist';
        final art = item.length > 3 ? item[3]?.toString() ?? '' : '';

        tracks.add(
          Track(
            id: id,
            title: tTitle,
            artist: artist,
            album: 'Single',
            duration: '3:30',
            artworkUrl: art,
            audioUrl: '',
            genre: 'POP',
          ),
        );
      }
    }

    final title = tracks.isNotEmpty ? '${tracks.first.title} & Mix' : 'Imported Playlist';
    return DecodedPlaylistLink(
      title: title,
      description: 'Imported via Stateless Link',
      tracks: tracks,
    );
  }

  String _stripQuery(String url) {
    if (url.isEmpty || !url.startsWith('http')) return url;
    final idx = url.indexOf('?');
    if (idx != -1) return url.substring(0, idx);
    return url;
  }
}
