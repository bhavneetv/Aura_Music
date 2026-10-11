import 'dart:async';
import 'dart:math';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';
import '../auth/auth_service.dart';

class PlaylistRepository {
  final FirebaseFirestore _firestore;

  PlaylistRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _playlistsCol =>
      _firestore.collection('playlists');

  CollectionReference<Map<String, dynamic>> get _inviteCodesCol =>
      _firestore.collection('inviteCodes');

  // Debounce timers for reordering
  final Map<String, Timer> _reorderDebouncers = {};

  // -------------------------------------------------------------
  // 1. Creation & Favorites
  // -------------------------------------------------------------

  /// Creates a new playlist document.
  /// Cost: 1 write.
  Future<Playlist> createPlaylist({
    String? id,
    required String name,
    String description = '',
    required String ownerUid,
    required String ownerName,
    String visibility = 'private',
    bool collabEnabled = false,
    String type = 'custom',
    List<PlaylistTrack> initialTracks = const [],
  }) async {
    final docRef = (id != null && id.isNotEmpty) ? _playlistsCol.doc(id) : _playlistsCol.doc();
    final now = DateTime.now();

    final playlist = Playlist(
      id: docRef.id,
      name: name.trim().isEmpty ? 'My Playlist' : name.trim(),
      description: description.trim(),
      ownerUid: ownerUid,
      ownerName: ownerName,
      memberUids: [ownerUid],
      visibility: visibility,
      collabEnabled: collabEnabled,
      type: type,
      createdAt: now,
      updatedAt: now,
      trackCount: initialTracks.length,
      tracks: initialTracks,
    );

    // Cost: 1 write
    await docRef.set(playlist.toFirestore());
    return playlist;
  }

  /// Sets or merges playlist document in Firestore.
  /// Cost: 1 write.
  Future<void> saveOrUpdatePlaylist(Playlist playlist) async {
    final docRef = _playlistsCol.doc(playlist.id);
    await docRef.set(playlist.toFirestore(), SetOptions(merge: true));
  }

  /// Gets or creates the user's special "Liked songs" Favorites playlist.
  /// Cost: 1 read (if exists) or 1 read + 1 write (first time creation).
  Future<Playlist> getOrCreateFavorites(String uid, String userName) async {
    // Cost: 1 query read (limited to 1 doc)
    final query = await _playlistsCol
        .where('ownerUid', isEqualTo: uid)
        .where('type', isEqualTo: 'favorites')
        .limit(1)
        .get();

    if (query.docs.isNotEmpty) {
      return Playlist.fromFirestore(query.docs.first);
    }

    // Create favorites playlist if not exists. Cost: 1 write
    return createPlaylist(
      name: 'Liked Songs',
      description: 'Your favorite tracks',
      ownerUid: uid,
      ownerName: userName,
      type: 'favorites',
      visibility: 'private',
    );
  }

  // -------------------------------------------------------------
  // 2. Streams & Queries (Cost Effective)
  // -------------------------------------------------------------

  /// Streams all playlists that the user is a member of (owned + joined).
  /// Cost: 1 query with N reads on initial listen, then 1 read per modified playlist.
  Stream<List<Playlist>> watchUserPlaylists(String uid) {
    return _playlistsCol
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snapshot) {
      final list = snapshot.docs.map((doc) => Playlist.fromFirestore(doc)).toList();
      // Sort locally by updatedAt descending
      list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
      return list;
    });
  }

  /// Streams a single open playlist document in real-time.
  /// Cost: 1 read initially, plus 1 read whenever collaborators update it.
  Stream<Playlist?> watchPlaylist(String playlistId) {
    return _playlistsCol.doc(playlistId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return Playlist.fromFirestore(doc);
    });
  }

  /// Fetches a playlist document once.
  /// Cost: 1 read.
  Future<Playlist?> getPlaylist(String playlistId) async {
    try {
      final doc = await _playlistsCol.doc(playlistId).get();
      if (!doc.exists) return null;
      return Playlist.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting playlist $playlistId: $e');
      return null;
    }
  }

  // -------------------------------------------------------------
  // 3. Track Operations (Atomic Transactions)
  // -------------------------------------------------------------

  /// Atomically adds a track to the playlist array.
  /// Enforces the 500-track limit and checks authorization.
  /// Cost: 1 read + 1 write (Transaction).
  Future<void> addTrack(String playlistId, PlaylistTrack track, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);

    await _firestore.runTransaction((transaction) async {
      // Cost: 1 read
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) {
        throw Exception('Playlist does not exist.');
      }

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      // Verify permission
      if (!playlist.canEditTracks(callerUid)) {
        throw Exception('You do not have permission to add tracks to this playlist.');
      }

      // Enforce 500 tracks cap
      if (playlist.tracks.length >= 500) {
        throw Exception('Playlist is full (maximum 500 tracks reached).');
      }

      // Check if duplicate track exists (optional skip or allow)
      final existingIndex = playlist.tracks.indexWhere((t) => t.trackId == track.trackId && t.source == track.source);
      if (existingIndex != -1) {
        // Track already in playlist; do not duplicate
        return;
      }

      final updatedTracks = List<PlaylistTrack>.from(playlist.tracks)..add(track);

      // Cost: 1 write
      transaction.update(docRef, {
        'tracks': updatedTracks.map((t) => t.toMap()).toList(),
        'trackCount': updatedTracks.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Atomically removes a track from the playlist.
  /// Owner can remove any track; Collaborator can only remove tracks they added.
  /// Cost: 1 read + 1 write (Transaction).
  Future<void> removeTrack(String playlistId, String trackEntryId, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);

    await _firestore.runTransaction((transaction) async {
      // Cost: 1 read
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception('Playlist not found.');

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      final trackIndex = playlist.tracks.indexWhere((t) => t.id == trackEntryId);
      if (trackIndex == -1) return; // Already removed

      final targetTrack = playlist.tracks[trackIndex];

      // Authorization check
      final isOwner = playlist.isOwner(callerUid);
      final isAddedByCaller = targetTrack.addedByUid == callerUid;
      if (!isOwner && !isAddedByCaller) {
        throw Exception('You can only remove tracks that you added.');
      }

      final updatedTracks = List<PlaylistTrack>.from(playlist.tracks)..removeAt(trackIndex);

      // Cost: 1 write
      transaction.update(docRef, {
        'tracks': updatedTracks.map((t) => t.toMap()).toList(),
        'trackCount': updatedTracks.length,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Debounced reordering of tracks in playlist.
  /// Cost: 1 read + 1 write (Transaction).
  Future<void> reorderTracks(String playlistId, int oldIndex, int newIndex, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);

    await _firestore.runTransaction((transaction) async {
      // Cost: 1 read
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception('Playlist not found.');

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      if (!playlist.canEditTracks(callerUid)) {
        throw Exception('You do not have permission to edit this playlist.');
      }

      final updatedTracks = List<PlaylistTrack>.from(playlist.tracks);
      if (oldIndex < 0 || oldIndex >= updatedTracks.length) return;
      if (newIndex < 0 || newIndex > updatedTracks.length) return;

      int targetIndex = newIndex;
      if (oldIndex < newIndex) {
        targetIndex -= 1;
      }
      final item = updatedTracks.removeAt(oldIndex);
      updatedTracks.insert(targetIndex, item);

      // Cost: 1 write
      transaction.update(docRef, {
        'tracks': updatedTracks.map((t) => t.toMap()).toList(),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // -------------------------------------------------------------
  // 4. Playlist Metadata & Deletion
  // -------------------------------------------------------------

  /// Renames or changes description of a playlist (owner only).
  /// Cost: 1 write.
  Future<void> updatePlaylistDetails({
    required String playlistId,
    required String name,
    required String description,
    required String callerUid,
  }) async {
    final docRef = _playlistsCol.doc(playlistId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Playlist not found.');
    if (doc.data()?['ownerUid'] != callerUid) {
      throw Exception('Only the owner can update playlist details.');
    }

    // Cost: 1 write
    await docRef.update({
      'name': name.trim(),
      'description': description.trim(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Toggles visibility between "private" and "public".
  /// Cost: 1 write.
  Future<void> updateVisibility(String playlistId, String visibility, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Playlist not found.');
    if (doc.data()?['ownerUid'] != callerUid) {
      throw Exception('Only the owner can change visibility.');
    }

    // Cost: 1 write
    await docRef.update({
      'visibility': visibility,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Deletes a playlist document and any associated invite code.
  /// Cost: 1 or 2 writes.
  Future<void> deletePlaylist(String playlistId, String callerUid, {bool isAdmin = false}) async {
    final docRef = _playlistsCol.doc(playlistId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    if (!isAdmin && doc.data()?['ownerUid'] != callerUid) {
      throw Exception('Only the owner or admin can delete this playlist.');
    }

    // Remove any active invite codes for this playlist
    final inviteQuery = await _inviteCodesCol.where('playlistId', isEqualTo: playlistId).get();
    for (final inviteDoc in inviteQuery.docs) {
      await inviteDoc.reference.delete();
    }

    // Delete playlist doc
    await docRef.delete();
  }

  // -------------------------------------------------------------
  // 5. Collaboration & Invite Codes
  // -------------------------------------------------------------

  /// Enables collaboration and generates an 8-character join code.
  /// Cost: 1 read + 2 writes (invite code doc + playlist doc update).
  Future<String> enableCollaboration(String playlistId, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Playlist not found.');
    if (doc.data()?['ownerUid'] != callerUid) {
      throw Exception('Only the playlist owner can enable collaboration.');
    }

    // Check if an invite code already exists
    final existingCodes = await _inviteCodesCol.where('playlistId', isEqualTo: playlistId).limit(1).get();
    if (existingCodes.docs.isNotEmpty) {
      final code = existingCodes.docs.first.id;
      await docRef.update({'collabEnabled': true, 'updatedAt': FieldValue.serverTimestamp()});
      return code;
    }

    // Generate clean 8-character uppercase code (no 0/O/1/I)
    final code = _generateInviteCode();

    // Create inviteCodes doc. Cost: 1 write
    await _inviteCodesCol.doc(code).set({
      'playlistId': playlistId,
      'createdBy': callerUid,
      'createdAt': FieldValue.serverTimestamp(),
    });

    // Update playlist doc. Cost: 1 write
    await docRef.update({
      'collabEnabled': true,
      'updatedAt': FieldValue.serverTimestamp(),
    });

    return code;
  }

  /// Disables collaboration and removes the invite code.
  /// Cost: 1 read + 2 writes.
  Future<void> disableCollaboration(String playlistId, String callerUid) async {
    final docRef = _playlistsCol.doc(playlistId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Playlist not found.');
    if (doc.data()?['ownerUid'] != callerUid) {
      throw Exception('Only the owner can disable collaboration.');
    }

    // Delete invite codes. Cost: query + delete
    final existingCodes = await _inviteCodesCol.where('playlistId', isEqualTo: playlistId).get();
    for (final c in existingCodes.docs) {
      await c.reference.delete();
    }

    // Update playlist doc
    await docRef.update({
      'collabEnabled': false,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches existing invite code if collaboration is active.
  /// Cost: 1 read.
  Future<String?> getInviteCodeForPlaylist(String playlistId) async {
    final query = await _inviteCodesCol.where('playlistId', isEqualTo: playlistId).limit(1).get();
    if (query.docs.isNotEmpty) {
      return query.docs.first.id;
    }
    return null;
  }

  /// Joins a collaborative playlist using an 8-character invite code.
  /// Cost: 1 read (invite code) + 1 transaction (playlist read + write).
  Future<Playlist> joinByInviteCode(String rawCode, String userUid, String userName) async {
    final cleanCode = rawCode.trim().toUpperCase();

    // 1. Read invite code. Cost: 1 read
    final inviteDoc = await _inviteCodesCol.doc(cleanCode).get();
    if (!inviteDoc.exists) {
      throw Exception('Invalid or expired invite code.');
    }

    final targetPlaylistId = inviteDoc.data()?['playlistId'] as String?;
    if (targetPlaylistId == null) {
      throw Exception('Playlist associated with this code was not found.');
    }

    final docRef = _playlistsCol.doc(targetPlaylistId);

    // 2. Transaction: Add userUid to memberUids. Cost: 1 read + 1 write
    return await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) throw Exception('Playlist no longer exists.');

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      if (!playlist.collabEnabled) {
        throw Exception('Collaboration is currently disabled for this playlist.');
      }

      if (playlist.memberUids.contains(userUid)) {
        return playlist; // Already a member!
      }

      final updatedMembers = List<String>.from(playlist.memberUids)..add(userUid);

      transaction.update(docRef, {
        'memberUids': updatedMembers,
        'joinedWith': cleanCode,
        'updatedAt': FieldValue.serverTimestamp(),
      });

      return playlist.copyWith(memberUids: updatedMembers);
    });
  }

  /// Allows a member to leave a collaborative playlist.
  /// Cost: 1 read + 1 write (Transaction).
  Future<void> leavePlaylist(String playlistId, String userUid) async {
    final docRef = _playlistsCol.doc(playlistId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      if (playlist.isOwner(userUid)) {
        throw Exception('The owner cannot leave their own playlist. You can delete it instead.');
      }

      final updatedMembers = List<String>.from(playlist.memberUids)..remove(userUid);

      transaction.update(docRef, {
        'memberUids': updatedMembers,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  /// Owner removes a collaborator from the playlist.
  /// Cost: 1 read + 1 write (Transaction).
  Future<void> removeMember(String playlistId, String memberUid, String ownerUid) async {
    final docRef = _playlistsCol.doc(playlistId);

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(docRef);
      if (!snapshot.exists) return;

      final data = snapshot.data() ?? {};
      final playlist = Playlist.fromMap(data, id: snapshot.id);

      if (!playlist.isOwner(ownerUid)) {
        throw Exception('Only the playlist owner can remove members.');
      }

      final updatedMembers = List<String>.from(playlist.memberUids)..remove(memberUid);

      transaction.update(docRef, {
        'memberUids': updatedMembers,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  // -------------------------------------------------------------
  // 6. Public Playlists & Duplication
  // -------------------------------------------------------------

  /// Fetches paginated public playlists for explore screen.
  /// Scans local Hive storage and ensures all playlists marked as public
  /// are pushed and live on Cloud Firestore.
  Future<int> syncLocalPublicPlaylists() async {
    final uid = AuthService.instance.currentUserId;
    if (uid.isEmpty) return 0;
    final userName = AuthService.instance.currentUserName;

    final localPlaylists = StorageService.getPlaylists();
    int syncedCount = 0;

    for (final raw in localPlaylists) {
      if (raw['isPublic'] == true) {
        final id = raw['id']?.toString();
        if (id == null || id.isEmpty) continue;

        final rawTracks = raw['tracks'] as List? ?? [];
        final tracks = <PlaylistTrack>[];
        for (final t in rawTracks) {
          if (t is Map) {
            try {
              final track = Track.fromJson(Map<String, dynamic>.from(t));
              tracks.add(PlaylistTrack.fromTrack(
                track,
                addedByUid: uid,
                addedByName: userName,
              ));
            } catch (e) {
              debugPrint('Error parsing track for public sync: $e');
            }
          }
        }

        final pl = Playlist(
          id: id,
          name: raw['name']?.toString() ?? 'My Playlist',
          description: raw['description']?.toString() ?? '',
          ownerUid: uid,
          ownerName: raw['authorName']?.toString() ?? userName,
          memberUids: [uid],
          visibility: 'public',
          collabEnabled: raw['isSyncEnabled'] == true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          trackCount: tracks.length,
          tracks: tracks,
        );

        try {
          await saveOrUpdatePlaylist(pl);
          syncedCount++;
        } catch (e) {
          debugPrint('Error uploading local public playlist $id to Firestore: $e');
        }
      }
    }
    return syncedCount;
  }

  /// Fetches paginated public playlists for explore screen.
  /// Cost: at most [limit] reads.
  Future<List<Playlist>> getPublicPlaylists({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _playlistsCol
          .where('visibility', isEqualTo: 'public')
          .orderBy('updatedAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snapshot = await query.get();
      return snapshot.docs.map((doc) => Playlist.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('getPublicPlaylists index fallback: $e');
      try {
        final fallback = await _playlistsCol
            .where('visibility', isEqualTo: 'public')
            .limit(limit)
            .get();
        final list = fallback.docs.map((doc) => Playlist.fromFirestore(doc)).toList();
        list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
        return list;
      } catch (err) {
        debugPrint('getPublicPlaylists fallback error: $err');
        rethrow;
      }
    }
  }

  /// Imports a public playlist as a private copy for the current user.
  /// Cost: 1 read (source) + 1 write (new playlist doc).
  Future<Playlist> duplicateAsPrivateCopy({
    required String sourcePlaylistId,
    required String newOwnerUid,
    required String newOwnerName,
  }) async {
    final source = await getPlaylist(sourcePlaylistId);
    if (source == null) throw Exception('Source playlist not found.');

    final newTracks = source.tracks.map((t) {
      return PlaylistTrack(
        id: '${DateTime.now().millisecondsSinceEpoch}_${t.trackId.hashCode.abs()}',
        source: t.source,
        trackId: t.trackId,
        title: t.title,
        artist: t.artist,
        artworkUrl: t.artworkUrl,
        durationMs: t.durationMs,
        addedByUid: newOwnerUid,
        addedByName: newOwnerName,
        addedAt: DateTime.now(),
      );
    }).toList();

    return createPlaylist(
      name: '${source.name} (Copy)',
      description: source.description,
      ownerUid: newOwnerUid,
      ownerName: newOwnerName,
      visibility: 'private',
      collabEnabled: false,
      initialTracks: newTracks,
    );
  }

  // -------------------------------------------------------------
  // Helpers
  // -------------------------------------------------------------

  String _generateInviteCode() {
    // 8-character uppercase code without confusing characters (0, O, 1, I)
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }
}
