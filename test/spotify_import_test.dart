import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/import/spotify_import_service.dart';

void main() {
  group('SpotifyImportService Tests', () {
    final service = SpotifyImportService.instance;

    test('validateAndExtractPlaylistId extracts ID for valid links', () {
      final validUrls = [
        'https://open.spotify.com/playlist/3DcwVlU8cXIjtqjT3RKTaJ',
        'https://open.spotify.com/playlist/3DcwVlU8cXIjtqjT3RKTaJ?si=a54a3f6796b84db8',
        'open.spotify.com/playlist/3DcwVlU8cXIjtqjT3RKTaJ',
        'http://open.spotify.com/playlist/3DcwVlU8cXIjtqjT3RKTaJ',
      ];

      for (final url in validUrls) {
        expect(service.validateAndExtractPlaylistId(url), '3DcwVlU8cXIjtqjT3RKTaJ');
      }
    });

    test('validateAndExtractPlaylistId returns null for invalid links', () {
      final invalidUrls = [
        'https://open.spotify.com/track/2sqsNXfN0HtgDEgaHXiUTa',
        'https://spotify.com/3DcwVlU8cXIjtqjT3RKTaJ',
        'open.spotify.com/playlist/',
        'https://open.spotify.com/playlist/shortId',
        '',
      ];

      for (final url in invalidUrls) {
        expect(service.validateAndExtractPlaylistId(url), isNull);
      }
    });

    test('parsePlaylistHtml successfully parses correct HTML structure', () {
      const sampleHtml = '''
<!DOCTYPE html>
<html>
<head>
  <script id="initial-state" type="application/json">
    {
      "props": {
        "pageProps": {
          "state": {
            "data": {
              "entity": {
                "name": "My Sample Playlist",
                "description": "Scraping test playlist description",
                "subtitle": "Zeke",
                "coverArt": {
                  "sources": [{"url": "https://sample-image-cdn.com/123"}]
                },
                "trackList": [
                  {
                    "title": "Won't Be Late",
                    "subtitle": "Swae Lee, Drake",
                    "uri": "spotify:track:2sqsNXfN0HtgDEgaHXiUTa"
                  },
                  {
                    "title": "One Dance",
                    "subtitle": "Drake, Wizkid, Kyla",
                    "uri": "spotify:track:12345"
                  }
                ]
              }
            }
          }
        }
      }
    }
  </script>
</head>
<body></body>
</html>
''';

      final preview = service.parsePlaylistHtml(sampleHtml, '3DcwVlU8cXIjtqjT3RKTaJ');
      expect(preview.id, '3DcwVlU8cXIjtqjT3RKTaJ');
      expect(preview.name, 'My Sample Playlist');
      expect(preview.description, 'Scraping test playlist description');
      expect(preview.creator, 'Zeke');
      expect(preview.coverUrl, 'https://sample-image-cdn.com/123');
      expect(preview.totalTracks, 2);
      
      expect(preview.tracks[0].title, "Won't Be Late");
      expect(preview.tracks[0].artist, "Swae Lee, Drake");
      expect(preview.tracks[1].title, "One Dance");
      expect(preview.tracks[1].artist, "Drake, Wizkid, Kyla");
    });

    test('parsePlaylistHtml throws exception for invalid HTML/JSON structure', () {
      const badHtml = '<html><body>No Script Tag Here</body></html>';
      expect(
        () => service.parsePlaylistHtml(badHtml, '3DcwVlU8cXIjtqjT3RKTaJ'),
        throwsA(isA<Exception>()),
      );
    });
  });
}
