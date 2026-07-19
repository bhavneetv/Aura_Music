import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/track.dart';

class StorageService {
  static const String _settingsBox = 'settings_box';
  static const String _profileBox = 'profile_box';
  static const String _playlistsBox = 'playlists_box';
  static const String _favoritesBox = 'favorites_box';
  static const String _historyBox = 'history_box';
  static const String _downloadsBox = 'downloads_box';
  static const String _queueBox = 'queue_box';

  static Future<void> init() async {
    await Hive.initFlutter();
    
    // Open all boxes
    await Hive.openBox(_settingsBox);
    await Hive.openBox(_profileBox);
    await Hive.openBox(_playlistsBox);
    await Hive.openBox(_favoritesBox);
    await Hive.openBox(_historyBox);
    await Hive.openBox(_downloadsBox);
    await Hive.openBox(_queueBox);
  }

  // ── Settings ────────────────────────────────────────────────
  
  static dynamic getSetting(String key, {dynamic defaultValue}) {
    final box = Hive.box(_settingsBox);
    return box.get(key, defaultValue: defaultValue);
  }

  static Future<void> saveSetting(String key, dynamic value) async {
    final box = Hive.box(_settingsBox);
    await box.put(key, value);
  }

  // ── Onboarding Profile ──────────────────────────────────────
  
  static bool isOnboardingComplete() {
    final box = Hive.box(_profileBox);
    return box.get('completed', defaultValue: false) as bool;
  }

  static Future<void> completeOnboarding() async {
    final box = Hive.box(_profileBox);
    await box.put('completed', true);
  }

  static List<String> getPreferredLanguages() {
    final box = Hive.box(_profileBox);
    return List<String>.from(box.get('languages', defaultValue: <String>['English', 'Hindi']));
  }

  static Future<void> savePreferredLanguages(List<String> langs) async {
    final box = Hive.box(_profileBox);
    await box.put('languages', langs);
  }

  static List<String> getPreferredGenres() {
    final box = Hive.box(_profileBox);
    return List<String>.from(box.get('genres', defaultValue: <String>[]));
  }

  static Future<void> savePreferredGenres(List<String> genres) async {
    final box = Hive.box(_profileBox);
    await box.put('genres', genres);
  }

  static List<String> getPreferredArtists() {
    final box = Hive.box(_profileBox);
    return List<String>.from(box.get('artists', defaultValue: <String>[]));
  }

  static Future<void> savePreferredArtists(List<String> artists) async {
    final box = Hive.box(_profileBox);
    await box.put('artists', artists);
  }

  // ── Favorites ───────────────────────────────────────────────
  
  static List<String> getFavoriteIds(String type) {
    final box = Hive.box(_favoritesBox);
    return List<String>.from(box.get(type, defaultValue: <String>[]));
  }

  static Future<void> toggleFavorite(String type, String id) async {
    final box = Hive.box(_favoritesBox);
    final list = getFavoriteIds(type);
    if (list.contains(id)) {
      list.remove(id);
    } else {
      list.add(id);
    }
    await box.put(type, list);
  }

  static bool isFavorite(String type, String id) {
    return getFavoriteIds(type).contains(id);
  }

  // ── Playlists CRUD ─────────────────────────────────────────

  static List<Map<String, dynamic>> getPlaylists() {
    final box = Hive.box(_playlistsBox);
    final raw = box.get('all_playlists');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> savePlaylists(List<Map<String, dynamic>> playlists) async {
    final box = Hive.box(_playlistsBox);
    await box.put('all_playlists', jsonEncode(playlists));
  }

  // ── History Tracker ─────────────────────────────────────────

  static List<String> getRecentSearches() {
    final box = Hive.box(_historyBox);
    return List<String>.from(box.get('searches', defaultValue: <String>[]));
  }

  static Future<void> addSearchQuery(String query) async {
    final box = Hive.box(_historyBox);
    final list = getRecentSearches();
    list.remove(query); // Prevent duplicates
    list.insert(0, query);
    if (list.length > 20) list.removeLast(); // Cap size
    await box.put('searches', list);
  }

  static Future<void> clearSearchHistory() async {
    final box = Hive.box(_historyBox);
    await box.put('searches', <String>[]);
  }

  static List<Map<String, dynamic>> getListeningHistory() {
    final box = Hive.box(_historyBox);
    final raw = box.get('listening_history');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addListeningHistory(Track track, double durationPlayedSeconds) async {
    final box = Hive.box(_historyBox);
    final history = getListeningHistory();
    
    // Construct history item
    final item = {
      'track_id': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'duration': track.duration,
      'artworkUrl': track.artworkUrl,
      'audioUrl': track.audioUrl,
      'genre': track.genre,
      'timestamp': DateTime.now().toIso8601String(),
      'durationPlayed': durationPlayedSeconds,
    };
    
    history.insert(0, item);
    if (history.length > 200) history.removeLast(); // Cap size
    await box.put('listening_history', jsonEncode(history));
  }

  static Future<void> deleteHistoryItem(String timestamp) async {
    final box = Hive.box(_historyBox);
    final history = getListeningHistory();
    history.removeWhere((item) => item['timestamp'] == timestamp);
    await box.put('listening_history', jsonEncode(history));
  }

  static Future<void> clearListeningHistory() async {
    final box = Hive.box(_historyBox);
    await box.put('listening_history', jsonEncode([]));
  }

  // ── Downloads Tracker ───────────────────────────────────────

  static Map<String, String> getDownloadedTracks() {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> registerDownload(String trackId, String localPath) async {
    final box = Hive.box(_downloadsBox);
    final downloads = getDownloadedTracks();
    downloads[trackId] = localPath;
    await box.put('downloaded_tracks', jsonEncode(downloads));
  }

  static Future<void> deleteDownloadRecord(String trackId) async {
    final box = Hive.box(_downloadsBox);
    final downloads = getDownloadedTracks();
    downloads.remove(trackId);
    await box.put('downloaded_tracks', jsonEncode(downloads));
  }

  // ── Playback Queue Box ──────────────────────────────────────

  static Map<String, dynamic>? getSavedQueueState() {
    final box = Hive.box(_queueBox);
    final raw = box.get('state');
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveQueueState({
    required List<Track> tracks,
    required int currentIndex,
    required bool isShuffle,
    required int repeatMode,
  }) async {
    final box = Hive.box(_queueBox);
    final state = {
      'tracks': tracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'artworkUrl': t.artworkUrl,
        'audioUrl': t.audioUrl,
        'genre': t.genre,
      }).toList(),
      'currentIndex': currentIndex,
      'isShuffle': isShuffle,
      'repeatMode': repeatMode,
    };
    await box.put('state', jsonEncode(state));
  }
}
