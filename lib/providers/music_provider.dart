import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../services/music_sources/music_source.dart';
import '../services/music_sources/source_manager.dart';
import 'music_source_mode_provider.dart';

// Abstract source provider swappable via SourceManager
final musicSourceProvider = Provider<MusicSource>((ref) {
  // Watch sourceModeProvider so changes trigger provider recalculation
  ref.watch(sourceModeProvider);
  return SourceManager();
});

// FutureProvider to fetch trending tracks from the active source
final trendingTracksProvider = FutureProvider<List<Track>>((ref) async {
  final source = ref.watch(musicSourceProvider);
  return source.getTrendingTracks();
});

// FutureProvider family to fetch tracks by genre
final genreTracksProvider = FutureProvider.family<List<Track>, String>((ref, genre) async {
  final source = ref.watch(musicSourceProvider);
  return source.getTracksByGenre(genre);
});

// FutureProvider to fetch fresh dynamic recommendations based on active source & user history
final dynamicRecommendationsProvider = FutureProvider<List<Track>>((ref) async {
  final source = ref.watch(musicSourceProvider);
  return source.getDynamicRecommendations();
});
