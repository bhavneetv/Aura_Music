import 'dart:convert';
import 'dart:io';
import 'package:hive_flutter/hive_flutter.dart';
import '../../models/track.dart';
import '../../models/source_mode.dart';
import '../../models/user_model.dart';
import '../sync/playlist_cloud_sync_service.dart';

class StorageService {
  static const String _settingsBox = 'settings_box';
  static const String _profileBox = 'profile_box';
  static const String _playlistsBox = 'playlists_box';
  static const String _favoritesBox = 'favorites_box';
  static const String _historyBox = 'history_box';
  static const String _downloadsBox = 'downloads_box';
  static const String _queueBox = 'queue_box';
  static const String _affinityBox = 'affinity_box';
  static const String _summaryBox = 'song_summaries_box';
  static const String _lyricsBox = 'lyrics_box';
  static const String _waveformBox = 'waveform_box';

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
    await Hive.openBox(_waveformBox);
  }

  // ── Settings ────────────────────────────────────────────────
  
  static dynamic getSetting(String key, {dynamic defaultValue}) {
    if (!Hive.isBoxOpen(_settingsBox)) return defaultValue;
    final box = Hive.box(_settingsBox);
    return box.get(key, defaultValue: defaultValue);
  }

  static Future<void> saveSetting(String key, dynamic value) async {
    if (!Hive.isBoxOpen(_settingsBox)) return;
    final box = Hive.box(_settingsBox);
    await box.put(key, value);
  }

  static String getUserName() {
    return getSetting('user_name', defaultValue: '') as String;
  }

  static Future<void> setUserName(String name) async {
    await saveSetting('user_name', name.trim());
  }

  // ── Admin Cache ─────────────────────────────────────────────
  static String? getAdminCachedStatsJson() {
    return getSetting('admin_cached_stats') as String?;
  }

  static Future<void> saveAdminCachedStatsJson(String jsonStr) async {
    await saveSetting('admin_cached_stats', jsonStr);
  }

  static String? getAdminLastSyncedAt() {
    return getSetting('admin_last_synced_at') as String?;
  }

  static Future<void> setAdminLastSyncedAt(String dtIso) async {
    await saveSetting('admin_last_synced_at', dtIso);
  }

  static String? getAdminCachedUsersJson() {
    return getSetting('admin_cached_users') as String?;
  }

  static Future<void> saveAdminCachedUsersJson(String jsonStr) async {
    await saveSetting('admin_cached_users', jsonStr);
  }

  static String? getAdminCachedPlaylistsJson() {
    return getSetting('admin_cached_playlists') as String?;
  }

  static Future<void> saveAdminCachedPlaylistsJson(String jsonStr) async {
    await saveSetting('admin_cached_playlists', jsonStr);
  }

  static bool hasCompletedOnboarding() {
    final fromSettings = getSetting('completed_onboarding', defaultValue: false) as bool;
    try {
      final box = Hive.box(_profileBox);
      final fromProfile = box.get('completed', defaultValue: false) as bool;
      return fromSettings || fromProfile;
    } catch (_) {
      return fromSettings;
    }
  }

  static Future<void> setCompletedOnboarding(bool completed) async {
    await saveSetting('completed_onboarding', completed);
    try {
      final box = Hive.box(_profileBox);
      await box.put('completed', completed);
    } catch (_) {}
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

  // ── Music Source Mode ─────────────────────────────────────────

  static const String _sourceModeKey = 'music_source_mode';

  static SourceMode getSourceMode() {
    final val = getSetting(_sourceModeKey, defaultValue: 'hybrid') as String?;
    return SourceMode.fromKey(val);
  }

  static Future<void> setSourceMode(SourceMode mode) async {
    await saveSetting(_sourceModeKey, mode.key);
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
    return hasCompletedOnboarding();
  }

  static Future<void> completeOnboarding() async {
    await setCompletedOnboarding(true);
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

  static String getLastSelectedHomeLanguage() {
    final box = Hive.box(_profileBox);
    final saved = box.get('last_home_language')?.toString();
    if (saved != null && saved.isNotEmpty) return saved;
    final langs = List<String>.from(box.get('languages', defaultValue: <String>[]));
    if (langs.isNotEmpty) return langs.first;
    return 'Punjabi';
  }

  static Future<void> saveLastSelectedHomeLanguage(String language) async {
    final box = Hive.box(_profileBox);
    await box.put('last_home_language', language);
    if (language != 'All') {
      await box.put('languages', [language]);
    }
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
        return Track.fromJson(map);
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
    final jsonList = tracks.map((t) => t.toJson()).toList();
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

  // ── User Accounts & Device ID ──────────────────────────────

  static String getDeviceId() {
    if (!Hive.isBoxOpen(_profileBox)) return 'dev_guest_device';
    final box = Hive.box(_profileBox);
    var id = box.get('device_unique_id')?.toString();
    if (id == null || id.isEmpty) {
      id = 'dev_${DateTime.now().millisecondsSinceEpoch}_${(1000 + (DateTime.now().microsecond % 9000))}';
      box.put('device_unique_id', id);
    }
    return id;
  }

  static UserModel? getCurrentUser() {
    if (!Hive.isBoxOpen(_profileBox)) return null;
    final box = Hive.box(_profileBox);
    final raw = box.get('current_user_profile');
    if (raw == null) return null;
    try {
      final map = jsonDecode(raw.toString()) as Map<String, dynamic>;
      return UserModel.fromJson(map);
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveCurrentUser(UserModel? user) async {
    if (!Hive.isBoxOpen(_profileBox)) return;
    final box = Hive.box(_profileBox);
    if (user == null) {
      await box.delete('current_user_profile');
    } else {
      await box.put('current_user_profile', jsonEncode(user.toJson()));
    }
  }

  // ── Playlists CRUD ─────────────────────────────────────────

  static List<Map<String, dynamic>> getPlaylists() {
    if (!Hive.isBoxOpen(_playlistsBox)) return [];
    final box = Hive.box(_playlistsBox);
    final raw = box.get('all_playlists');
    if (raw == null) return [];
    try {
      final decoded = jsonDecode(raw.toString()) as List;
      final list = decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();

      bool needsResave = false;
      final currentUser = getCurrentUser();

      for (final pl in list) {
        final isImported = pl['isImported'] == true;

        // If user is logged in, normalize playlists created by this user
        // NEVER hijack ownership if pl is imported or collaborative member
        if (currentUser != null && !isImported) {
          final isOwnerById = pl['ownerId'] != null && pl['ownerId'] == currentUser.id;
          final isOwnerByEmail = pl['ownerEmail'] != null &&
              pl['ownerEmail'].toString().trim().isNotEmpty &&
              pl['ownerEmail'].toString().trim().toLowerCase() == currentUser.email.trim().toLowerCase();

          if (isOwnerById || isOwnerByEmail) {
            if (pl['ownerEmail'] != currentUser.email) {
              pl['ownerEmail'] = currentUser.email;
              needsResave = true;
            }
            if (pl['ownerId'] != currentUser.id) {
              pl['ownerId'] = currentUser.id;
              needsResave = true;
            }
          }
        }

        if (pl['ownerId'] == null || pl['ownerId'].toString().isEmpty) {
          if (!isImported) {
            pl['ownerId'] = currentUser?.id ?? getDeviceId();
            pl['ownerName'] = currentUser?.name ?? getUserAuthorName();
            if (currentUser != null) pl['ownerEmail'] = currentUser.email;
            needsResave = true;
          }
        }
      }

      if (needsResave) {
        box.put('all_playlists', jsonEncode(list));
      }
      return list;
    } catch (_) {
      return [];
    }
  }

  static String getUserAuthorName() {
    final user = getCurrentUser();
    if (user != null && user.name.isNotEmpty) return user.name;
    final name = getUserName().trim();
    if (name.isNotEmpty) return name;
    return getSetting('user_author_name', defaultValue: 'Aura Member')?.toString() ?? 'Aura Member';
  }

  static Future<void> setUserAuthorName(String name) async {
    final clean = name.trim();
    await saveSetting('user_author_name', clean.isEmpty ? 'Aura Member' : clean);
    if (clean.isNotEmpty) {
      await setUserName(clean);
    }
  }

  static Future<void> updatePlaylist(String playlistId, Map<String, dynamic> updatedData) async {
    final playlists = getPlaylists();
    final index = playlists.indexWhere((p) => p['id']?.toString() == playlistId);
    if (index != -1) {
      playlists[index] = {
        ...playlists[index],
        ...updatedData,
      };
      await savePlaylists(playlists);
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
    final List<Map<String, dynamic>> trackMaps = tracks.map((t) => t.toJson()).toList();
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
      return Track.fromJson(map);
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
      'source': track.source,
      'youtubeVideoId': track.youtubeVideoId,
      'timestamp': DateTime.now().toIso8601String(),
      'durationPlayed': durationPlayedSeconds,
    };
    
    history.insert(0, item);
    // Unlimited dynamic history by default
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

  static int getSyncedWatchHistoryCount() {
    final box = Hive.box(_historyBox);
    return (box.get('synced_watch_history_count', defaultValue: 0) as num).toInt();
  }

  static Future<void> setSyncedWatchHistoryCount(int count) async {
    final box = Hive.box(_historyBox);
    await box.put('synced_watch_history_count', count);
  }

  // ── 3D Virtual Sound / Spatial Audio ─────────────────────────

  static bool is3dSoundEnabled() {
    return getSetting('virtual_3d_sound_enabled', defaultValue: false) as bool;
  }

  static Future<void> set3dSoundEnabled(bool enabled) async {
    await saveSetting('virtual_3d_sound_enabled', enabled);
  }

  static String get3dSoundMode() {
    return getSetting('virtual_3d_sound_mode', defaultValue: 'Wide Room') as String;
  }

  static Future<void> set3dSoundMode(String mode) async {
    await saveSetting('virtual_3d_sound_mode', mode);
  }

  static double get3dSoundIntensity() {
    final val = getSetting('virtual_3d_sound_intensity', defaultValue: 0.65);
    if (val is num) return val.toDouble();
    return 0.65;
  }

  static Future<void> set3dSoundIntensity(double intensity) async {
    await saveSetting('virtual_3d_sound_intensity', intensity);
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
      'source': track.source,
      'youtubeVideoId': track.youtubeVideoId,
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

  // ── Navigation Bar Visual Style ──────────────────────────────

  static String getNavigationBarStyle() {
    return getSetting('nav_bar_style', defaultValue: 'default') as String;
  }

  static Future<void> setNavigationBarStyle(String style) async {
    await saveSetting('nav_bar_style', style);
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
        String? path;
        String? trackId;
        if (value is Map) {
          path = value['localPath']?.toString() ?? '';
          trackId = value['id']?.toString();
        } else {
          path = value.toString();
        }
        if (path.isNotEmpty && File(path).existsSync() && File(path).lengthSync() > 0) {
          result[key.toString()] = path;
          if (trackId != null && trackId.isNotEmpty) {
            result[trackId] = path;
          }
        }
      });
      return result;
    } catch (_) {
      return {};
    }
  }

  static List<Track> getFullDownloadedTracks() {
    if (!Hive.isBoxOpen(_downloadsBox)) return [];
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return [];
    try {
      final Map decoded = jsonDecode(raw.toString()) as Map;
      final List<Track> tracks = [];
      decoded.forEach((key, val) {
        if (val is Map) {
          final localPath = val['localPath']?.toString() ?? '';
          if (localPath.isNotEmpty && File(localPath).existsSync() && File(localPath).lengthSync() > 0) {
            final localArt = val['localArtworkPath']?.toString() ?? '';
            final remoteArt = val['artworkUrl']?.toString() ?? '';

            // Prioritize valid local artwork file for offline reliability
            String finalArt = (localArt.isNotEmpty && File(localArt).existsSync() && File(localArt).lengthSync() > 0)
                ? localArt
                : remoteArt;

            tracks.add(
              Track(
                id: val['id']?.toString() ?? key.toString(),
                title: val['title']?.toString() ?? 'Downloaded Song',
                artist: val['artist']?.toString() ?? 'Unknown Artist',
                album: val['album']?.toString() ?? 'Offline',
                duration: val['duration']?.toString() ?? '3:30',
                artworkUrl: finalArt,
                audioUrl: localPath,
                genre: val['genre']?.toString() ?? 'OFFLINE',
                source: val['source']?.toString() ?? 'jiosaavn',
                youtubeVideoId: val['youtubeVideoId']?.toString(),
              ),
            );
          }
        }
      });
      final Map<String, Track> uniqueTracks = {};
      for (final t in tracks) {
        if (!uniqueTracks.containsKey(t.id)) {
          uniqueTracks[t.id] = t;
        }
      }
      return uniqueTracks.values.toList();
    } catch (_) {
      return [];
    }
  }

  static String? getDownloadedTrackPath(String trackId, {String? title, String? artist}) {
    final downloads = getDownloadedTracks();
    if (downloads.containsKey(trackId)) {
      return downloads[trackId];
    }
    // Tolerance for yt_ prefix differences
    if (trackId.startsWith('yt_')) {
      final rawId = trackId.substring(3);
      if (downloads.containsKey(rawId)) return downloads[rawId];
    } else {
      final withYt = 'yt_$trackId';
      if (downloads.containsKey(withYt)) return downloads[withYt];
    }

    // Fallback: search downloaded metadata by matching title and artist
    if (title != null && title.trim().isNotEmpty && Hive.isBoxOpen(_downloadsBox)) {
      try {
        final box = Hive.box(_downloadsBox);
        final raw = box.get('downloaded_tracks');
        if (raw != null) {
          final Map decoded = jsonDecode(raw.toString()) as Map;
          final cleanTitle = title.trim().toLowerCase();
          final cleanArtist = artist?.trim().toLowerCase() ?? '';
          for (final val in decoded.values) {
            if (val is Map) {
              final tTitle = val['title']?.toString().trim().toLowerCase() ?? '';
              final tArtist = val['artist']?.toString().trim().toLowerCase() ?? '';
              if (tTitle == cleanTitle) {
                if (cleanArtist.isEmpty || tArtist.isEmpty || tArtist == cleanArtist || tArtist.contains(cleanArtist) || cleanArtist.contains(tArtist)) {
                  final localPath = val['localPath']?.toString() ?? '';
                  if (localPath.isNotEmpty && File(localPath).existsSync() && File(localPath).lengthSync() > 0) {
                    return localPath;
                  }
                }
              }
            }
          }
        }
      } catch (_) {}
    }
    return null;
  }

  static String? getRemoteArtworkUrl(String trackId) {
    if (!Hive.isBoxOpen(_downloadsBox)) return null;
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return null;
    try {
      final Map decoded = jsonDecode(raw.toString()) as Map;
      final val = decoded[trackId];
      if (val is Map) {
        final remote = val['artworkUrl']?.toString() ?? '';
        if (remote.startsWith('http://') || remote.startsWith('https://')) {
          return remote;
        }
      }
    } catch (_) {}
    return null;
  }

  static String? getDownloadedArtworkPath(String trackId, {String? title}) {
    if (!Hive.isBoxOpen(_downloadsBox)) return null;
    final box = Hive.box(_downloadsBox);
    final raw = box.get('downloaded_tracks');
    if (raw == null) return null;
    try {
      final Map decoded = jsonDecode(raw.toString()) as Map;
      var val = decoded[trackId];
      if (val == null && trackId.startsWith('yt_')) {
        val = decoded[trackId.substring(3)];
      } else if (val == null) {
        val = decoded['yt_$trackId'];
      }
      if (val is Map) {
        final localArt = val['localArtworkPath']?.toString() ?? '';
        if (localArt.isNotEmpty && File(localArt).existsSync() && File(localArt).lengthSync() > 0) {
          return localArt;
        }
      }

      // Fallback matching by title
      if (title != null && title.trim().isNotEmpty) {
        final cleanTitle = title.trim().toLowerCase();
        for (final item in decoded.values) {
          if (item is Map && (item['title']?.toString().trim().toLowerCase() == cleanTitle)) {
            final localArt = item['localArtworkPath']?.toString() ?? '';
            if (localArt.isNotEmpty && File(localArt).existsSync() && File(localArt).lengthSync() > 0) {
              return localArt;
            }
          }
        }
      }
    } catch (_) {}
    return null;
  }

  static Future<void> registerDownloadTrack(Track track, String localPath, {String? artworkLocalPath}) async {
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
      'localArtworkPath': artworkLocalPath ?? '',
      'genre': track.genre,
      'localPath': localPath,
      'source': track.source,
      'youtubeVideoId': track.youtubeVideoId,
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
      'tracks': tracks.map((t) {
        final m = t.toJson();
        m['audioUrl'] = StorageService.getDownloadedTrackPath(t.id) ?? t.audioUrl;
        return m;
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
      'tracks': tracks.map((t) => t.toJson()).toList(),
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

  // ── Waveform Cache ──────────────────────────────────────────────

  static List<double>? getWaveformData(String trackId) {
    final box = Hive.box(_waveformBox);
    final raw = box.get(trackId);
    if (raw == null) return null;
    try {
      final List decoded = jsonDecode(raw.toString());
      return decoded.map((e) => (e as num).toDouble()).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> saveWaveformData(String trackId, List<double> data) async {
    final box = Hive.box(_waveformBox);
    await box.put(trackId, jsonEncode(data));
  }
}
