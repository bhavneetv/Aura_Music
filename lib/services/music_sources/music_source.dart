import '../../models/track.dart';

abstract class MusicSource {
  Future<List<Track>> getTrendingTracks();
  Future<List<Track>> searchTracks(String query);
  Future<List<Track>> getTracksByGenre(String genre);
  Future<List<Track>> getDynamicRecommendations();
}
