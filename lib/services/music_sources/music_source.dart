import '../../models/track.dart';

abstract class MusicSource {
  String get name;
  Future<List<Track>> getTrendingTracks();
  Future<List<Track>> searchTracks(String query);
  Future<List<Track>> getTracksByGenre(String genre);
  Future<List<Track>> getDynamicRecommendations();
  Future<List<Track>> getContextualRecommendations(Track currentTrack);
  Future<String?> getStreamUrl(Track track);
}
