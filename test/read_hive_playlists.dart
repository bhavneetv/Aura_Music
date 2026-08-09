import 'dart:convert';
import 'dart:io';
import 'package:hive/hive.dart';

void main() async {
  // Set path to current dir or standard path
  final path = Directory.current.path;
  Hive.init(path);
  
  try {
    final box = await Hive.openBox('playlists_box');
    final raw = box.get('all_playlists');
    if (raw == null) {
      print('No playlists found in box.');
      return;
    }
    
    final List decoded = jsonDecode(raw.toString());
    print('Total playlists in Hive: ${decoded.length}');
    for (int i = 0; i < decoded.length; i++) {
      final pl = decoded[i];
      print('Playlist $i:');
      print('  ID: ${pl['id']}');
      print('  Name: ${pl['name']}');
      print('  Source: ${pl['source']}');
      print('  Tracks Count: ${pl['tracks']?.length}');
      print('  TrackIds Count: ${pl['trackIds']?.length}');
      if (pl['tracks'] != null && (pl['tracks'] as List).isNotEmpty) {
        print('  First track in tracks: ${pl['tracks'].first}');
      }
    }
  } catch (e) {
    print('Error: $e');
  }
}
