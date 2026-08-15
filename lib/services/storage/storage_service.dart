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
  static const String _affinityBox = 'affinity_box';
  static const String _lyricsBox = 'lyrics_box';

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
    await Hive.openBox(_affinityBox);
    await Hive.openBox(_summaryBox);
    await Hive.openBox(_lyricsBox);
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

  static String getUserName() {
    return getSetting('user_name', defaultValue: '') as String;
  }

  static Future<void> setUserName(String name) async {
    await saveSetting('user_name', name.trim());
  }

  static bool hasCompletedOnboarding() {
    return getSetting('completed_onboarding', defaultValue: false) as bool;
  }

  static Future<void> setCompletedOnboarding(bool completed) async {
    await saveSetting('completed_onboarding', completed);
  }

  static bool isCrossfadeEnabled() {
    return getSetting('crossfade_enabled', defaultValue: false) as bool;
  }

  static Future<void> setCrossfadeEnabled(bool enabled) async {
    await saveSetting('crossfade_enabled', enabled);
  }

  static int getCrossfadeDuration() {
    return getSetting('crossfade_duration', defaultValue: 5) as int;
  }

  static Future<void> setCrossfadeDuration(int seconds) async {
    await saveSetting('crossfade_duration', seconds);
  }

  static bool isHapticsEnabled() {
    return getSetting('haptics_enabled', defaultValue: true) as bool;
  }

  static Future<void> setHapticsEnabled(bool enabled) async {
    await saveSetting('haptics_enabled', enabled);
  }

  static bool hasSeenPlayerTutorial() {
    final box = Hive.box(_profileBox);
    return box.get('seen_player_tutorial', defaultValue: false) as bool;
  }

  static Future<void> setSeenPlayerTutorial() async {
    final box = Hive.box(_profileBox);
    await box.put('seen_player_tutorial', true);
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

  static List<Track> getFavoriteTracks() {
    final box = Hive.box(_favoritesBox);
    final raw = box.get('favorite_tracks_objects');
    if (raw == null) return [];
    try {
      final List decoded = jsonDecode(raw.toString());
      return decoded.map((e) {
        final map = Map<String, dynamic>.from(e as Map);
        return Track(
          id: map['id']?.toString() ?? '',
          title: map['title']?.toString() ?? 'Unknown Track',
          artist: map['artist']?.toString() ?? 'Unknown Artist',
          album: map['album']?.toString() ?? 'Single',
          duration: map['duration']?.toString() ?? '3:30',
          artworkUrl: map['artworkUrl']?.toString() ?? '',
          audioUrl: map['audioUrl']?.toString() ?? '',
          genre: map['genre']?.toString() ?? 'Pop',
        );
      }).where((t) => t.id.isNotEmpty).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> toggleFavoriteTrack(Track track) async {
    final box = Hive.box(_favoritesBox);
    final ids = getFavoriteIds('trackIds');
    final tracks = getFavoriteTracks();

    final isFav = ids.contains(track.id);
    if (isFav) {
      ids.remove(track.id);
      tracks.removeWhere((t) => t.id == track.id);
    } else {
      ids.add(track.id);
      tracks.insert(0, track);
    }

    await box.put('trackIds', ids);
    final jsonList = tracks.map((t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration': t.duration,
      'artworkUrl': t.artworkUrl,
      'audioUrl': t.audioUrl,
      'genre': t.genre,
    }).toList();
    await box.put('favorite_tracks_objects', jsonEncode(jsonList));
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

  // ── AI Search History ───────────────────────────────────────

  static List<String> getAiRecentSearches() {
    final box = Hive.box(_historyBox);
    return List<String>.from(box.get('ai_searches', defaultValue: <String>[]));
  }

  static Future<void> addAiSearchQuery(String query) async {
    final box = Hive.box(_historyBox);
    final list = getAiRecentSearches();
    list.remove(query);
    list.insert(0, query);
    if (list.length > 20) list.removeLast();
    await box.put('ai_searches', list);
  }

  static Future<void> clearAiSearchHistory() async {
    final box = Hive.box(_historyBox);
    await box.put('ai_searches', <String>[]);
  }

  // ── AI Grouped Session History ─────────────────────────────

  static Future<void> saveGroupedAiSession(String sessionTitle, List<Track> tracks) async {
    final box = Hive.box(_historyBox);
    final Map<String, dynamic> allSessions = getGroupedAiSessionsMap();
    final List<Map<String, dynamic>> trackMaps = tracks.map((t) => {
      'id': t.id,
      'title': t.title,
      'artist': t.artist,
      'album': t.album,
      'duration': t.duration,
      'artworkUrl': t.artworkUrl,
      'audioUrl': t.audioUrl,
      'genre': t.genre,
    }).toList();
    allSessions[sessionTitle.trim().toLowerCase()] = trackMaps;
    await box.put('ai_session_tracks', jsonEncode(allSessions));
  }

  static Map<String, dynamic> getGroupedAiSessionsMap() {
    final box = Hive.box(_historyBox);
    final raw = box.get('ai_session_tracks');
    if (raw == null) return {};
    try {
      return Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return {};
    }
  }

  static List<Track> getGroupedSessionTracks(String sessionTitle) {
    final allSessions = getGroupedAiSessionsMap();
    final rawList = allSessions[sessionTitle.trim().toLowerCase()];
    if (rawList == null || rawList is! List) return [];
    return rawList.map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      return Track(
        id: map['id']?.toString() ?? '',
        title: map['title']?.toString() ?? 'Track',
        artist: map['artist']?.toString() ?? 'Unknown Artist',
        album: map['album']?.toString() ?? 'Single',
        duration: map['duration']?.toString() ?? '3:30',
        artworkUrl: map['artworkUrl']?.toString() ?? '',
        audioUrl: map['audioUrl']?.toString() ?? '',
        genre: map['genre']?.toString() ?? '',
      );
    }).toList();
  }

  // ── AI Tutorial Flag ───────────────────────────────────────

  static bool hasSeenAiTutorial() {
    final box = Hive.box(_profileBox);
    return box.get('has_seen_ai_tutorial', defaultValue: false) as bool;
  }

  static Future<void> setHasSeenAiTutorial(bool value) async {
    final box = Hive.box(_profileBox);
    await box.put('has_seen_ai_tutorial', value);
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

  // ── Searched & Played Tracks Tracker ────────────────────────

  static List<Map<String, dynamic>> getSearchedAndPlayedTracks() {
    final box = Hive.box(_historyBox);
    final raw = box.get('searched_played_tracks');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addSearchedAndPlayedTrack(Track track) async {
    final box = Hive.box(_historyBox);
    final list = getSearchedAndPlayedTracks();
    
    // Prevent duplicates by track_id
    list.removeWhere((item) => item['track_id'] == track.id);
    
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
    };
    
    list.insert(0, item);
    if (list.length > 100) list.removeLast();
    await box.put('searched_played_tracks', jsonEncode(list));
  }

  // ── Progress Bar Visual Style ────────────────────────────────

  static String getProgressBarStyle() {
    return getSetting('progress_bar_style', defaultValue: 'normal') as String;
  }

  static Future<void> setProgressBarStyle(String style) async {
    await saveSetting('progress_bar_style', style);
  }

  // ── Downloads Tracker ───────────────────────────────────────

  static Map<String, String> getDownloadedTracks() {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return {};
    try {
      final Map decoded = jsonDecode(raw.toString()) as Map;
      final Map<String, String> result = {};
      decoded.forEach((key, value) {
        if (value is Map) {
          result[key.toString()] = value['localPath']?.toString() ?? '';
        } else {
          result[key.toString()] = value.toString();
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static List<Track> getFullDownloadedTracks() {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return [];
    try {
      final Map decoded = jsonDecode(raw.toString()) as Map;
      final List<Track> tracks = [];
      decoded.forEach((key, val) {
        if (val is Map) {
          final localPath = val['localPath']?.toString() ?? '';
          if (localPath.isNotEmpty) {
            tracks.add(
              Track(
                id: val['id']?.toString() ?? key.toString(),
                title: val['title']?.toString() ?? 'Downloaded Song',
                artist: val['artist']?.toString() ?? 'Unknown Artist',
                album: val['album']?.toString() ?? 'Offline',
                duration: val['duration']?.toString() ?? '3:30',
                artworkUrl: val['artworkUrl']?.toString() ?? '',
                audioUrl: localPath,
                genre: val['genre']?.toString() ?? 'OFFLINE',
              ),
            );
          }
        }
      });
      return tracks;
    } catch (_) {
      return [];
    }
  }

  static String? getDownloadedTrackPath(String trackId) {
    final downloads = getDownloadedTracks();
    return downloads[trackId];
  }

  static Future<void> registerDownloadTrack(Track track, String localPath) async {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    Map<String, dynamic> downloads = {};
    if (raw != null) {
      try {
        downloads = Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      } catch (_) {}
    }
    downloads[track.id] = {
      'id': track.id,
      'title': track.title,
      'artist': track.artist,
      'album': track.album,
      'duration': track.duration,
      'artworkUrl': track.artworkUrl,
      'genre': track.genre,
      'localPath': localPath,
      'downloadedAt': DateTime.now().toIso8601String(),
    };
    await box.put('downloaded_tracks', jsonEncode(downloads));
  }

  static Future<void> deleteDownloadRecord(String trackId) async {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw != null) {
      try {
        final Map downloads = jsonDecode(raw.toString()) as Map;
        downloads.remove(trackId);
        await box.put('downloaded_tracks', jsonEncode(downloads));
      } catch (_) {}
    }
  }

  // ── Downloaded Playlists ────────────────────────────────────

  static List<Map<String, dynamic>> getDownloadedPlaylists() {
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_playlists');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> registerDownloadedPlaylist(String name, String description, List<Track> tracks) async {
    final box = Hive.box(_downloadsBox);
    final playlists = getDownloadedPlaylists();
    playlists.removeWhere((p) => p['name'] == name);
    playlists.insert(0, {
      'name': name,
      'description': description,
      'downloadedAt': DateTime.now().toIso8601String(),
      'tracks': tracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'artworkUrl': t.artworkUrl,
        'genre': t.genre,
        'audioUrl': StorageService.getDownloadedTrackPath(t.id) ?? t.audioUrl,
      }).toList(),
    });
    await box.put('downloaded_playlists', jsonEncode(playlists));
  }

  static Future<void> deleteDownloadedPlaylist(String name) async {
    final box = Hive.box(_downloadsBox);
    final playlists = getDownloadedPlaylists();
    playlists.removeWhere((p) => p['name'] == name);
    await box.put('downloaded_playlists', jsonEncode(playlists));
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

  // ── Affinity Vectors & Session Persistence ─────────────────

  static Map<String, double> getArtistAffinityMap() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('artist_affinity');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw.toString()) as Map;
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> updateArtistAffinity(String artist, double delta) async {
    if (artist.isEmpty || artist == 'Unknown Artist') return;
    final box = Hive.box(_affinityBox);
    final map = getArtistAffinityMap();
    final cleanArtist = artist.split(',').first.trim();
    map[cleanArtist] = ((map[cleanArtist] ?? 0.0) + delta).clamp(0.0, 100.0);
    await box.put('artist_affinity', jsonEncode(map));
  }

  static Map<String, double> getGenreAffinityMap() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('genre_affinity');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw.toString()) as Map;
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> updateGenreAffinity(String genre, double delta) async {
    if (genre.isEmpty) return;
    final box = Hive.box(_affinityBox);
    final map = getGenreAffinityMap();
    final cleanGenre = genre.trim().toUpperCase();
    map[cleanGenre] = ((map[cleanGenre] ?? 0.0) + delta).clamp(0.0, 100.0);
    await box.put('genre_affinity', jsonEncode(map));
  }

  static List<String> getCooldownHistoryTitles() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('cooldown_history');
    if (raw == null) return [];
    try {
      return List<String>.from(jsonDecode(raw.toString()) as List);
    } catch (_) {
      return [];
    }
  }

  static Future<void> addCooldownTrackTitle(String title) async {
    final cleanTitle = title.trim().toLowerCase();
    if (cleanTitle.isEmpty) return;
    final box = Hive.box(_affinityBox);
    final list = getCooldownHistoryTitles();
    list.remove(cleanTitle);
    list.add(cleanTitle);
    if (list.length > 50) list.removeAt(0); // Cap at 50 tracks
    await box.put('cooldown_history', jsonEncode(list));
  }

  static Map<String, String> getSessionContext() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('session_context');
    if (raw == null) return {};
    try {
      return Map<String, String>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return {};
    }
  }

  static Future<void> setSessionContext({String? genre, String? artist, String? language}) async {
    final box = Hive.box(_affinityBox);
    final ctx = getSessionContext();
    if (genre != null && genre.isNotEmpty) ctx['genre'] = genre.trim().toUpperCase();
    if (artist != null && artist.isNotEmpty) ctx['artist'] = artist.trim();
    if (language != null && language.isNotEmpty) ctx['language'] = language.trim().toUpperCase();
    await box.put('session_context', jsonEncode(ctx));
  }

  // ── Language Affinity ──────────────────────────────────────────

  static Map<String, double> getLanguageAffinityMap() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('language_affinity');
    if (raw == null) return {};
    try {
      final decoded = jsonDecode(raw.toString()) as Map;
      return decoded.map((k, v) => MapEntry(k.toString(), (v as num).toDouble()));
    } catch (_) {
      return {};
    }
  }

  static Future<void> updateLanguageAffinity(String language, double delta) async {
    if (language.isEmpty) return;
    final box = Hive.box(_affinityBox);
    final map = getLanguageAffinityMap();
    final cleanLang = language.trim().toUpperCase();
    map[cleanLang] = ((map[cleanLang] ?? 0.0) + delta).clamp(0.0, 100.0);
    await box.put('language_affinity', jsonEncode(map));
  }

  // ── Skip History ───────────────────────────────────────────────

  static List<Map<String, String>> getSkipHistory() {
    final box = Hive.box(_affinityBox);
    final raw = box.get('skip_history');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      return decoded.map((e) => Map<String, String>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> addSkipRecord(String artist, String genre, String language) async {
    final box = Hive.box(_affinityBox);
    final history = getSkipHistory();
    history.insert(0, {
      'artist': artist,
      'genre': genre.toUpperCase(),
      'language': language.toUpperCase(),
      'timestamp': DateTime.now().toIso8601String(),
    });
    if (history.length > 30) history.removeLast();
    await box.put('skip_history', jsonEncode(history));
  }

  // ── Replay Count ───────────────────────────────────────────────

  static int getReplayCount(String trackId) {
    final box = Hive.box(_affinityBox);
    final raw = box.get('replay_counts');
    if (raw == null) return 0;
    try {
      final decoded = jsonDecode(raw.toString()) as Map;
      return (decoded[trackId] as num?)?.toInt() ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> incrementReplayCount(String trackId) async {
    final box = Hive.box(_affinityBox);
    final raw = box.get('replay_counts');
    Map<String, dynamic> counts = {};
    if (raw != null) {
      try {
        counts = Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
      } catch (_) {}
    }
    counts[trackId] = ((counts[trackId] as num?)?.toInt() ?? 0) + 1;
    await box.put('replay_counts', jsonEncode(counts));
  }

  // ── Song Summary Cache ─────────────────────────────────────────

  static const String _summaryBox = 'song_summaries_box';

  static Map<String, dynamic>? getSongSummary(String trackId) {
    final box = Hive.box(_summaryBox);
    final raw = box.get(trackId);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveSongSummary(String trackId, Map<String, dynamic> summary) async {
    final box = Hive.box(_summaryBox);
    await box.put(trackId, jsonEncode(summary));
  }

  static Future<void> clearSongSummary(String trackId) async {
    final box = Hive.box(_summaryBox);
    await box.delete(trackId);
  }

  // ── Lyrics Cache ───────────────────────────────────────────────

  static Map<String, dynamic>? getLyrics(String trackId) {
    final box = Hive.box(_lyricsBox);
    final raw = box.get(trackId);
    if (raw == null) return null;
    try {
      return Map<String, dynamic>.from(jsonDecode(raw.toString()) as Map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveLyrics(String trackId, Map<String, dynamic> data) async {
    final box = Hive.box(_lyricsBox);
    await box.put(trackId, jsonEncode(data));
  }
}
