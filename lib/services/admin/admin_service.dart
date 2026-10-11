import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/app_user.dart';
import '../../models/playlist.dart';

class AdminStatsData {
  final int registeredUsers;
  final int guestUsers;
  final int totalLogins;
  final int totalPlaylists;
  final int publicPlaylists;
  final int collabPlaylists;
  final int totalSongsListened;
  final Map<String, int> usersJoinedLast7Days;

  const AdminStatsData({
    required this.registeredUsers,
    required this.guestUsers,
    required this.totalLogins,
    required this.totalPlaylists,
    required this.publicPlaylists,
    required this.collabPlaylists,
    required this.totalSongsListened,
    required this.usersJoinedLast7Days,
  });
}

class AdminService {
  final FirebaseFirestore _firestore;

  AdminService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersCol => _firestore.collection('users');
  CollectionReference<Map<String, dynamic>> get _playlistsCol => _firestore.collection('playlists');
  CollectionReference<Map<String, dynamic>> get _blockedCol => _firestore.collection('blocked');

  // Cached aggregate data for session
  AdminStatsData? _cachedStats;

  /// Fetches aggregate counts & sums using cost-effective Firestore Aggregate Queries.
  /// Cost: ~1 read per aggregate query.
  Future<AdminStatsData> getDashboardStats({bool forceRefresh = false}) async {
    if (_cachedStats != null && !forceRefresh) {
      return _cachedStats!;
    }

    try {
      // 1. Registered users count (Cost: 1 read)
      final regUsersQuery = await _usersCol.where('isGuest', isEqualTo: false).count().get();
      final regCount = regUsersQuery.count ?? 0;

      // 2. Guest users count (Cost: 1 read)
      final guestUsersQuery = await _usersCol.where('isGuest', isEqualTo: true).count().get();
      final guestCount = guestUsersQuery.count ?? 0;

      // 3. Total playlists count (Cost: 1 read)
      final playlistsQuery = await _playlistsCol.count().get();
      final plCount = playlistsQuery.count ?? 0;

      // 4. Public playlists count (Cost: 1 read)
      final publicPlQuery = await _playlistsCol.where('visibility', isEqualTo: 'public').count().get();
      final pubCount = publicPlQuery.count ?? 0;

      // 5. Collaborative playlists count (Cost: 1 read)
      final collabPlQuery = await _playlistsCol.where('collabEnabled', isEqualTo: true).count().get();
      final collabCount = collabPlQuery.count ?? 0;

      // 6. Aggregate sums: total logins & total songs listened (Cost: 1 read each)
      int totalLoginsSum = 0;
      int totalSongsSum = 0;
      try {
        final loginsAgg = await _usersCol.aggregate(sum('loginCount')).get();
        totalLoginsSum = (loginsAgg.getSum('loginCount') ?? 0).toInt();

        final songsAgg = await _usersCol.aggregate(sum('stats.totalSongsPlayed')).get();
        totalSongsSum = (songsAgg.getSum('stats.totalSongsPlayed') ?? 0).toInt();
      } catch (e) {
        debugPrint('Admin aggregate sum notice: $e');
      }

      // 7. Users joined last 7 days (Cost: 7 aggregate count queries = 7 reads)
      final now = DateTime.now();
      final last7DaysMap = <String, int>{};
      for (int i = 6; i >= 0; i--) {
        final dayStart = DateTime(now.year, now.month, now.day).subtract(Duration(days: i));
        final dayEnd = dayStart.add(const Duration(days: 1));
        final label = '${dayStart.month}/${dayStart.day}';

        try {
          final countRes = await _usersCol
              .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(dayStart))
              .where('createdAt', isLessThan: Timestamp.fromDate(dayEnd))
              .count()
              .get();
          last7DaysMap[label] = countRes.count ?? 0;
        } catch (_) {
          last7DaysMap[label] = 0;
        }
      }

      _cachedStats = AdminStatsData(
        registeredUsers: regCount,
        guestUsers: guestCount,
        totalLogins: totalLoginsSum,
        totalPlaylists: plCount,
        publicPlaylists: pubCount,
        collabPlaylists: collabCount,
        totalSongsListened: totalSongsSum,
        usersJoinedLast7Days: last7DaysMap,
      );

      return _cachedStats!;
    } catch (e) {
      debugPrint('Admin stats fetch error: $e');
      return _cachedStats ?? const AdminStatsData(
        registeredUsers: 0,
        guestUsers: 0,
        totalLogins: 0,
        totalPlaylists: 0,
        publicPlaylists: 0,
        collabPlaylists: 0,
        totalSongsListened: 0,
        usersJoinedLast7Days: {},
      );
    }
  }

  // -------------------------------------------------------------
  // User Management
  // -------------------------------------------------------------

  /// Fetches paginated user list (20 per page).
  /// Cost: up to 20 reads.
  Future<List<AppUser>> getPaginatedUsers({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _usersCol
        .orderBy('createdAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    return snap.docs.map((d) => AppUser.fromFirestore(d)).toList();
  }

  /// Checks if a user UID is blocked.
  /// Cost: 1 read.
  Future<bool> isUserBlocked(String uid) async {
    final doc = await _blockedCol.doc(uid).get();
    return doc.exists;
  }

  /// Blocks a user by creating a `blocked/{uid}` doc.
  /// Cost: 1 write.
  Future<void> blockUser(String uid, String reason) async {
    await _blockedCol.doc(uid).set({
      'blockedAt': FieldValue.serverTimestamp(),
      'reason': reason.trim(),
    });
  }

  /// Unblocks a user by removing the `blocked/{uid}` doc.
  /// Cost: 1 write.
  Future<void> unblockUser(String uid) async {
    await _blockedCol.doc(uid).delete();
  }

  /// Deletes a user's Firestore document.
  /// Cost: 1 write.
  Future<void> deleteUserFirestoreData(String uid) async {
    await _usersCol.doc(uid).delete();
  }

  // -------------------------------------------------------------
  // Playlist Management
  // -------------------------------------------------------------

  /// Fetches paginated list of all playlists (20 per page).
  /// Cost: up to 20 reads.
  Future<List<Playlist>> getPaginatedPlaylists({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    Query<Map<String, dynamic>> query = _playlistsCol
        .orderBy('updatedAt', descending: true)
        .limit(limit);

    if (startAfter != null) {
      query = query.startAfterDocument(startAfter);
    }

    final snap = await query.get();
    return snap.docs.map((d) => Playlist.fromFirestore(d)).toList();
  }

  /// Forcefully deletes any playlist (admin only).
  /// Cost: 1 write.
  Future<void> forceDeletePlaylist(String playlistId) async {
    await _playlistsCol.doc(playlistId).delete();
  }

  /// Forces a playlist to private visibility.
  /// Cost: 1 write.
  Future<void> forceMakePrivate(String playlistId) async {
    await _playlistsCol.doc(playlistId).update({
      'visibility': 'private',
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }
}
