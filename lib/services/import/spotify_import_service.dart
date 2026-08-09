import 'dart:convert';
import 'package:dio/dio.dart';

class SpotifyTrackPreview {
  final String title;
  final String artist;

  SpotifyTrackPreview({
    required this.title,
    required this.artist,
  });

  Map<String, dynamic> toJson() => {
        'title': title,
        'artist': artist,
      };

  factory SpotifyTrackPreview.fromJson(Map<String, dynamic> json) => SpotifyTrackPreview(
        title: json['title'] ?? '',
        artist: json['artist'] ?? '',
      );
}

class SpotifyPlaylistPreview {
  final String id;
  final String name;
  final String description;
  final String creator;
  final String coverUrl;
  final int totalTracks;
  final List<SpotifyTrackPreview> tracks;

  SpotifyPlaylistPreview({
    required this.id,
    required this.name,
    required this.description,
    required this.creator,
    required this.coverUrl,
    required this.totalTracks,
    required this.tracks,
  });
}

class SpotifyImportService {
  static final SpotifyImportService instance = SpotifyImportService._();
  SpotifyImportService._();

  final Dio _dio = Dio(BaseOptions(
    receiveTimeout: const Duration(seconds: 10),
    connectTimeout: const Duration(seconds: 8),
  ));

  /// Regular expression to match standard Spotify playlist URLs:
  /// https://open.spotify.com/playlist/3DcwVlU8cXIjtqjT3RKTaJ?si=xxxxxx
  final RegExp _playlistUrlRegExp = RegExp(
    r'spotify\.com\/playlist\/([a-zA-Z0-9]{22})',
    caseSensitive: false,
  );

  /// Validates a Spotify playlist URL and extracts its 22-character ID.
  String? validateAndExtractPlaylistId(String url) {
    final cleanUrl = url.trim();
    if (cleanUrl.isEmpty) return null;
    
    final match = _playlistUrlRegExp.firstMatch(cleanUrl);
    if (match != null && match.groupCount >= 1) {
      return match.group(1);
    }
    return null;
  }

  /// Fetches public playlist metadata keylessly by scraping Spotify's embed page widget.
  Future<SpotifyPlaylistPreview> fetchPlaylistPreview(String url) async {
    final playlistId = validateAndExtractPlaylistId(url);
    if (playlistId == null) {
      throw Exception('Invalid Spotify playlist URL. Please ensure it follows the format:\nhttps://open.spotify.com/playlist/[playlist_id]');
    }

    try {
      final embedUrl = 'https://open.spotify.com/embed/playlist/$playlistId';
      print('[SPOTIFY-IMPORT] Scraping embed URL: $embedUrl');

      final response = await _dio.get(
        embedUrl,
        options: Options(
          headers: {
            'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
            'Accept-Language': 'en-US,en;q=0.9',
          },
        ),
      );

      if (response.statusCode == 404) {
        throw Exception('Spotify playlist not found. The playlist might be private, deleted, or inaccessible.');
      } else if (response.statusCode != 200) {
        throw Exception('Failed to load playlist page. Server returned status code ${response.statusCode}.');
      }

      final html = response.data.toString();
      return parsePlaylistHtml(html, playlistId);
    } on DioException catch (dioErr) {
      if (dioErr.response?.statusCode == 404) {
        throw Exception('Spotify playlist not found. Ensure the playlist is public and accessible.');
      } else if (dioErr.response?.statusCode == 403) {
        throw Exception('Access denied. Spotify is blocking unauthenticated requests from this connection.');
      }
      throw Exception('Network connection error: ${dioErr.message ?? "failed to reach Spotify"}');
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('An unexpected error occurred: $e');
    }
  }

  /// Parses the raw HTML response to extract the playlist JSON data.
  SpotifyPlaylistPreview parsePlaylistHtml(String html, String playlistId) {
    if (html.isEmpty) {
      throw Exception('Empty response received from Spotify.');
    }

    // Locate the script containing pageProps and state
    final scriptRegex = RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true);
    final matches = scriptRegex.allMatches(html);
    
    String? jsonContent;
    for (final match in matches) {
      final scriptText = match.group(1)?.trim() ?? '';
      if (scriptText.contains('"pageProps"') && 
          scriptText.contains('"state"') && 
          scriptText.contains('"entity"')) {
        jsonContent = scriptText;
        break;
      }
    }

    if (jsonContent == null) {
      throw Exception('Spotify\'s public page format could not be parsed. The import feature isn\'t working right now (Spotify layout changed).');
    }

    try {
      final Map<String, dynamic> decoded = jsonDecode(jsonContent);
      final pageProps = decoded['props']?['pageProps'];
      final state = pageProps?['state'];
      final entity = state?['data']?['entity'];

      if (entity == null) {
        throw Exception('Playlist data not found inside the page state.');
      }

      final name = entity['name']?.toString() ?? entity['title']?.toString() ?? 'Spotify Playlist';
      final description = entity['description']?.toString() ?? 'Imported playlist';
      final creator = entity['subtitle']?.toString() ?? 'Spotify Creator';
      
      String coverUrl = '';
      final coverSources = entity['coverArt']?['sources'];
      if (coverSources is List && coverSources.isNotEmpty) {
        coverUrl = coverSources.first['url']?.toString() ?? '';
      }

      final rawTracks = entity['trackList'] as List? ?? [];
      final List<SpotifyTrackPreview> tracks = [];

      for (final item in rawTracks) {
        if (item is! Map<String, dynamic>) continue;
        final title = item['title']?.toString() ?? '';
        final artist = item['subtitle']?.toString() ?? '';
        
        // Clean subtitle/artist to replace non-breaking spaces with standard space
        final cleanArtist = artist.replaceAll('\u00a0', ' ').trim();
        
        if (title.isNotEmpty) {
          tracks.add(SpotifyTrackPreview(
            title: title.trim(),
            artist: cleanArtist,
          ));
        }
      }

      if (tracks.isEmpty) {
        throw Exception('The Spotify playlist is empty. There are no tracks to import.');
      }

      return SpotifyPlaylistPreview(
        id: playlistId,
        name: name.trim(),
        description: description.trim(),
        creator: creator.trim(),
        coverUrl: coverUrl.trim(),
        totalTracks: tracks.length,
        tracks: tracks,
      );
    } catch (e) {
      if (e is Exception) rethrow;
      throw Exception('Failed to parse Spotify metadata JSON: $e');
    }
  }
}
