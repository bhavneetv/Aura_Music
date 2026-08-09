import 'dart:io';
import 'dart:convert';

void main() {
  try {
    final html = File('test/scratch_spotify.html').readAsStringSync();
    
    // Find the script tag containing the JSON data
    // We can use a regex that matches `<script id="__NEXT_DATA__" type="application/json">...</script>` 
    // or just look for the script containing target JSON keys
    final regex = RegExp(r'<script[^>]*>(.*?)</script>', dotAll: true);
    final matches = regex.allMatches(html);
    
    String? jsonStr;
    for (final match in matches) {
      final content = match.group(1) ?? '';
      if (content.contains('"pageProps"') && content.contains('"state"') && content.contains('"entity"')) {
        jsonStr = content.trim();
        break;
      }
    }
    
    if (jsonStr == null) {
      print('Could not find script tag containing JSON data.');
      return;
    }
    
    final Map<String, dynamic> data = jsonDecode(jsonStr);
    final encoder = JsonEncoder.withIndent('  ');
    final formatted = encoder.convert(data);
    
    File('test/scratch_spotify.json').writeAsStringSync(formatted);
    print('Formatted JSON saved to test/scratch_spotify.json');
    
    // Print top level keys and playlist summary
    final pageProps = data['props']?['pageProps'];
    final state = pageProps?['state'];
    final entity = state?['data']?['entity'];
    
    if (entity != null) {
      print('Playlist Name: ${entity['name']}');
      print('Owner: ${entity['subtitle']}');
      final coverUrl = entity['coverArt']?['sources']?[0]?['url'];
      print('Cover URL: $coverUrl');
      
      final tracksList = entity['trackList'] as List?;
      print('Tracks count in embed trackList: ${tracksList?.length}');
      if (tracksList != null && tracksList.isNotEmpty) {
        print('First Track Structure:');
        print(encoder.convert(tracksList.first));
      }
    } else {
      print('Entity was null inside data.');
    }
  } catch (e) {
    print('Error parsing: $e');
  }
}
