import 'dart:io';
import 'package:dio/dio.dart';

void main() async {
  final dio = Dio();
  dio.options.headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36',
    'Accept-Language': 'en-US,en;q=0.9',
  };
  
  try {
    print('Fetching Spotify Playlist Embed HTML...');
    final response = await dio.get('https://open.spotify.com/embed/playlist/3DcwVlU8cXIjtqjT3RKTaJ');
    final html = response.data.toString();
    print('HTML Length: ${html.length}');
    
    // Write HTML to file for inspection
    final file = File('test/scratch_spotify.html');
    file.writeAsStringSync(html);
    print('HTML saved to test/scratch_spotify.html');
    
    // Look for script tags
    final regex = RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true);
    final matches = regex.allMatches(html);
    print('Found ${matches.length} script tags.');
    
    for (int i = 0; i < matches.length; i++) {
      final scriptContent = matches.elementAt(i).group(1) ?? '';
      if (scriptContent.contains('initial-state') || 
          scriptContent.contains('__NEXT_DATA__') || 
          scriptContent.contains('resource') || 
          scriptContent.contains('track') || 
          scriptContent.contains('playlist') || 
          scriptContent.contains('props')) {
        print('--- Script Tag $i (Length: ${scriptContent.length}) ---');
        print(scriptContent.substring(0, scriptContent.length > 300 ? 300 : scriptContent.length));
        print('----------------------------------------------------');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
