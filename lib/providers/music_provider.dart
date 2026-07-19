import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/music_sources/music_source.dart';
import '../services/music_sources/jamendo_source.dart';

// Abstract source provider to make it swappable
final musicSourceProvider = Provider<MusicSource>((ref) {
  return JamendoSource();
});

// FutureProvider to fetch trending tracks from the API
final trendingTracksProvider = FutureProvider<List<Track>>((ref) async {
  final source = ref.read(musicSourceProvider);
  return source.getTrendingTracks();
});

// FutureProvider family to fetch tracks by genre
final genreTracksProvider = FutureProvider.family<List<Track>, String>((ref, genre) async {
  final source = ref.read(musicSourceProvider);
  return source.getTracksByGenre(genre);
});
