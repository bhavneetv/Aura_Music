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

class PlaylistLinkShareService {
  PlaylistLinkShareService._();
  static final PlaylistLinkShareService instance = PlaylistLinkShareService._();

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
      String cleanCode = rawInput.trim();

      // Check if P2P local Wi-Fi IP/port address embedded in URL
      if (cleanCode.contains('ip=') && cleanCode.contains('port=')) {
        try {
          final uri = Uri.parse(cleanCode);
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
        } catch (e) {
          debugPrint('[PlaylistLinkShare] Local P2P fetch failed, falling back to URL payload: $e');
        }
      }

      // Check if short code dpc= (dpaste.com)
      if (cleanCode.contains('dpc=') || cleanCode.contains('dpaste.com/')) {
        String shortId = cleanCode;
        if (cleanCode.contains('dpc=')) {
          shortId = cleanCode.substring(cleanCode.indexOf('dpc=') + 4);
          if (shortId.contains('&')) shortId = shortId.split('&').first;
        } else if (cleanCode.contains('dpaste.com/')) {
          shortId = cleanCode.split('dpaste.com/').last.replaceAll('.txt', '').replaceAll('/', '');
        }

        shortId = shortId.trim();
        if (shortId.isNotEmpty) {
          final rawUrl = 'https://dpaste.com/$shortId.txt';
          final response = await _dio.get(rawUrl, options: Options(responseType: ResponseType.plain));
          if (response.statusCode == 200 && response.data != null) {
            final Map<String, dynamic> parsedMap = jsonDecode(response.data.toString()) as Map<String, dynamic>;
            return _parsePlaylistMap(parsedMap);
          }
        }
      }

      // Check if short code dp= (dpaste.org)
      if (cleanCode.contains('dp=') || cleanCode.contains('dpaste.org/')) {
        String shortId = cleanCode;
        if (cleanCode.contains('dp=')) {
          shortId = cleanCode.substring(cleanCode.indexOf('dp=') + 3);
          if (shortId.contains('&')) shortId = shortId.split('&').first;
        } else if (cleanCode.contains('dpaste.org/')) {
          shortId = cleanCode.split('dpaste.org/').last.replaceAll('.raw', '').replaceAll('/', '');
        }

        shortId = shortId.trim();
        if (shortId.isNotEmpty) {
          final rawUrl = 'https://dpaste.org/$shortId.raw';
          final response = await _dio.get(rawUrl, options: Options(responseType: ResponseType.plain));
          if (response.statusCode == 200 && response.data != null) {
            final Map<String, dynamic> parsedMap = jsonDecode(response.data.toString()) as Map<String, dynamic>;
            return _parsePlaylistMap(parsedMap);
          }
        }
      }

      // Check if ids=
      if (cleanCode.contains('ids=')) {
        final idsStr = cleanCode.substring(cleanCode.indexOf('ids=') + 4).split('&').first;
        final idsList = idsStr.split(',').where((id) => id.trim().isNotEmpty).toList();
        final List<Track> tracks = [];
        for (final id in idsList) {
          final match = Track.mockTracks.firstWhere(
            (t) => t.id == id.trim(),
            orElse: () => Track(
              id: id.trim(),
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

      // Synchronous decode fallback
      return decodeShareableLink(cleanCode);
    } catch (e) {
      debugPrint('[PlaylistLinkShare] Async decode error, falling back to sync decode: $e');
      return decodeShareableLink(rawInput);
    }
  }

  /// Decode compressed Base64 URL string
  DecodedPlaylistLink? decodeShareableLink(String rawInput) {
    if (rawInput.trim().isEmpty) return null;

    try {
      String cleanCode = rawInput.trim();

      if (cleanCode.contains('p=')) {
        cleanCode = cleanCode.substring(cleanCode.indexOf('p=') + 2);
        if (cleanCode.contains('&')) {
          cleanCode = cleanCode.split('&').first;
        }
      } else if (cleanCode.startsWith('aura://') || cleanCode.startsWith('https://')) {
        final uri = Uri.parse(cleanCode);
        cleanCode = uri.queryParameters['p'] ?? uri.pathSegments.last;
      }

      int padLen = (4 - (cleanCode.length % 4)) % 4;
      cleanCode = cleanCode + ('=' * padLen);

      final compressedBytes = base64Url.decode(cleanCode);
      final jsonBytes = gzip.decode(compressedBytes);
      final jsonStr = utf8.decode(jsonBytes);

      final dynamic parsed = jsonDecode(jsonStr);
      if (parsed is Map<String, dynamic>) {
        return _parsePlaylistMap(parsed);
      } else if (parsed is List) {
        return _parseTrackList(parsed);
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
