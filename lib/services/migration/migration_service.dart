import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../storage/storage_service.dart';
import '../playlist/playlist_repository.dart';
import '../../models/playlist_track.dart';
import '../../models/track.dart';

class MigrationService {
  final PlaylistRepository _repository;
  static const String _kMigrationKey = 'has_migrated_hive_to_firestore_v1';

  MigrationService({PlaylistRepository? repository})
      : _repository = repository ?? PlaylistRepository();

  /// Performs a one-time migration of local Hive playlists and favorites to Firestore.
  /// Skips if already completed. Keeps the local database completely intact.
  Future<void> migrateLocalDataIfNeeded({
    required String uid,
    required String userName,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final hasMigrated = prefs.getBool(_kMigrationKey) ?? false;
      if (hasMigrated) {
        debugPrint('Migration: Local data has already been migrated.');
        return;
      }

      debugPrint('Migration: Starting one-time Hive -> Firestore migration for $uid');

      // 1. Migrate Favorites / Liked Songs
      final localFavTracks = StorageService.getFavoriteTracks();
      if (localFavTracks.isNotEmpty) {
        final favPlaylist = await _repository.getOrCreateFavorites(uid, userName);
        for (final track in localFavTracks) {
          final playlistTrack = PlaylistTrack.fromTrack(
            track,
            addedByUid: uid,
            addedByName: userName,
          );
          try {
            await _repository.addTrack(favPlaylist.id, playlistTrack, uid);
          } catch (e) {
            debugPrint('Migration: Error adding fav track ${track.title}: $e');
          }
        }
      }

      // 2. Migrate Custom Playlists
      final localPlaylists = StorageService.getPlaylists();
      for (final rawPl in localPlaylists) {
        final plName = rawPl['name']?.toString() ?? 'My Playlist';
        final desc = rawPl['description']?.toString() ?? '';
        final rawTracks = rawPl['tracks'] as List<dynamic>? ?? [];

        final playlistTracks = <PlaylistTrack>[];
        for (final item in rawTracks) {
          if (item is Map) {
            try {
              final track = Track.fromJson(Map<String, dynamic>.from(item));
              playlistTracks.add(
                PlaylistTrack.fromTrack(
                  track,
                  addedByUid: uid,
                  addedByName: userName,
                ),
              );
            } catch (e) {
              debugPrint('Migration: Error parsing track item: $e');
            }
          }
        }

        final isPublic = rawPl['isPublic'] == true;
        final isCollab = rawPl['isSyncEnabled'] == true;
        final plId = rawPl['id']?.toString();

        await _repository.createPlaylist(
          id: plId,
          name: plName,
          description: desc,
          ownerUid: uid,
          ownerName: userName,
          visibility: isPublic ? 'public' : 'private',
          collabEnabled: isCollab,
          initialTracks: playlistTracks,
        );
      }

      // 3. Mark migration as complete
      await prefs.setBool(_kMigrationKey, true);
      debugPrint('Migration: Successfully migrated local playlists to Firestore.');
    } catch (e) {
      debugPrint('Migration error: $e');
      // Do not mark as complete if there was an error so it can retry safely
    }
  }
}
