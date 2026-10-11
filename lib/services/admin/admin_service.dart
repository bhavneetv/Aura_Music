import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../../models/app_user.dart';
import '../../models/playlist.dart';
import '../storage/storage_service.dart';

class AdminStatsData {
  final int registeredUsers;
  final int guestUsers;
  final int totalLogins;
  final int totalPlaylists;
  final int publicPlaylists;
  final int collabPlaylists;
  final int totalSongsListened;
  final Map<String, int> usersJoinedLast7Days;
  final DateTime? syncedAt;

  const AdminStatsData({
    required this.registeredUsers,
    required this.guestUsers,
    required this.totalLogins,
    required this.totalPlaylists,
    required this.publicPlaylists,
    required this.collabPlaylists,
    required this.totalSongsListened,
    required this.usersJoinedLast7Days,
    this.syncedAt,
  });

  // Free Tier quota: 1 GiB = 1073741824 bytes
  static const int totalQuotaBytes = 1073741824;

  int get estimatedStorageUsedBytes {
    final userBytes = (registeredUsers + guestUsers) * 1250;
    final playlistBytes = totalPlaylists * 5200;
    const systemBytes = 10240;
    return userBytes + playlistBytes + systemBytes;
  }

  int get storageLeftBytes => (totalQuotaBytes - estimatedStorageUsedBytes).clamp(0, totalQuotaBytes);

  double get storageUsedMB => estimatedStorageUsedBytes / (1024 * 1024);
  double get storageLeftMB => storageLeftBytes / (1024 * 1024);
  double get percentStorageUsed => ((estimatedStorageUsedBytes / totalQuotaBytes) * 100).clamp(0.001, 100.0);

  // Remaining playlists we can store at ~5.2 KB each
  int get estimatedPlaylistsRemaining => (storageLeftBytes ~/ 5200);

  Map<String, dynamic> toJson() => {
    'registeredUsers': registeredUsers,
    'guestUsers': guestUsers,
    'totalLogins': totalLogins,
    'totalPlaylists': totalPlaylists,
    'publicPlaylists': publicPlaylists,
    'collabPlaylists': collabPlaylists,
    'totalSongsListened': totalSongsListened,
    'usersJoinedLast7Days': usersJoinedLast7Days,
    'syncedAt': syncedAt?.toIso8601String(),
  };

  factory AdminStatsData.fromJson(Map<String, dynamic> json) {
    return AdminStatsData(
      registeredUsers: (json['registeredUsers'] as num?)?.toInt() ?? 0,
      guestUsers: (json['guestUsers'] as num?)?.toInt() ?? 0,
      totalLogins: (json['totalLogins'] as num?)?.toInt() ?? 0,
      totalPlaylists: (json['totalPlaylists'] as num?)?.toInt() ?? 0,
      publicPlaylists: (json['publicPlaylists'] as num?)?.toInt() ?? 0,
      collabPlaylists: (json['collabPlaylists'] as num?)?.toInt() ?? 0,
      totalSongsListened: (json['totalSongsListened'] as num?)?.toInt() ?? 0,
      usersJoinedLast7Days: Map<String, int>.from(json['usersJoinedLast7Days'] ?? {}),
      syncedAt: json['syncedAt'] != null ? DateTime.tryParse(json['syncedAt']) : null,
    );
  }
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

    int totalUsersCount = 0;
    try {
      final totalQuery = await _usersCol.count().get();
      totalUsersCount = totalQuery.count ?? 0;
    } catch (e) {
      debugPrint('Admin total users count notice: $e');
    }

    int regCount = 0;
    try {
      final regUsersQuery = await _usersCol.where('isGuest', isEqualTo: false).count().get();
      regCount = regUsersQuery.count ?? 0;
    } catch (e) {
      debugPrint('Admin reg users query notice: $e');
    }

    int guestCount = 0;
    try {
      final guestUsersQuery = await _usersCol.where('isGuest', isEqualTo: true).count().get();
      guestCount = guestUsersQuery.count ?? 0;
    } catch (e) {
      debugPrint('Admin guest users query notice: $e');
    }

    if (totalUsersCount > 0 && regCount == 0 && guestCount == 0) {
      regCount = totalUsersCount;
    } else if (totalUsersCount > (regCount + guestCount)) {
      regCount = totalUsersCount - guestCount;
    }

    int plCount = 0;
    try {
      final playlistsQuery = await _playlistsCol.count().get();
      plCount = playlistsQuery.count ?? 0;
    } catch (e) {
      debugPrint('Admin total playlists query notice: $e');
    }

    int pubCount = 0;
    try {
      final publicPlQuery = await _playlistsCol.where('visibility', isEqualTo: 'public').count().get();
      pubCount = publicPlQuery.count ?? 0;
    } catch (e) {
      try {
        final publicPlQuery2 = await _playlistsCol.where('isPublic', isEqualTo: true).count().get();
        pubCount = publicPlQuery2.count ?? 0;
      } catch (_) {}
    }

    int collabCount = 0;
    try {
      final collabPlQuery = await _playlistsCol.where('collabEnabled', isEqualTo: true).count().get();
      collabCount = collabPlQuery.count ?? 0;
    } catch (e) {
      debugPrint('Admin collab query notice: $e');
    }

    int totalLoginsSum = 0;
    try {
      final loginsAgg = await _usersCol.aggregate(sum('loginCount')).get();
      totalLoginsSum = (loginsAgg.getSum('loginCount') ?? 0).toInt();
    } catch (e) {
      debugPrint('Admin logins sum notice: $e');
    }

    int totalSongsSum = 0;
    try {
      final songsAgg = await _usersCol.aggregate(sum('stats.totalSongsPlayed')).get();
      totalSongsSum = (songsAgg.getSum('stats.totalSongsPlayed') ?? 0).toInt();
    } catch (e) {
      debugPrint('Admin songs sum notice: $e');
    }

    if (totalSongsSum == 0) {
      try {
        final historyAgg = await _usersCol.aggregate(sum('watchHistoryCount')).get();
        final historySum = (historyAgg.getSum('watchHistoryCount') ?? 0).toInt();
        if (historySum > 0) {
          totalSongsSum = historySum;
        }
      } catch (e) {
        debugPrint('Admin history count sum notice: $e');
      }
    }

    if (totalSongsSum == 0) {
      final localHistoryCount = StorageService.getListeningHistory().length;
      if (localHistoryCount > 0) {
        totalSongsSum = localHistoryCount;
      }
    }

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
      syncedAt: DateTime.now(),
    );

    return _cachedStats!;
  }

  // -------------------------------------------------------------
  // User Management
  // -------------------------------------------------------------

  /// Fetches paginated user list (20 per page).
  Future<List<AppUser>> getPaginatedUsers({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _usersCol
          .orderBy('createdAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snap = await query.get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.map((d) => AppUser.fromFirestore(d)).toList();
      }
    } catch (e) {
      debugPrint('getPaginatedUsers ordered query notice: $e');
    }

    // Fallback: un-ordered query
    try {
      Query<Map<String, dynamic>> fallbackQuery = _usersCol.limit(limit);
      if (startAfter != null) {
        fallbackQuery = fallbackQuery.startAfterDocument(startAfter);
      }
      final snap = await fallbackQuery.get();
      return snap.docs.map((d) => AppUser.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('getPaginatedUsers fallback notice: $e');
      return [];
    }
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
  Future<List<Playlist>> getPaginatedPlaylists({
    DocumentSnapshot? startAfter,
    int limit = 20,
  }) async {
    try {
      Query<Map<String, dynamic>> query = _playlistsCol
          .orderBy('updatedAt', descending: true)
          .limit(limit);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final snap = await query.get();
      if (snap.docs.isNotEmpty) {
        return snap.docs.map((d) => Playlist.fromFirestore(d)).toList();
      }
    } catch (e) {
      debugPrint('getPaginatedPlaylists ordered query notice: $e');
    }

    // Fallback: un-ordered query
    try {
      Query<Map<String, dynamic>> fallbackQuery = _playlistsCol.limit(limit);
      if (startAfter != null) {
        fallbackQuery = fallbackQuery.startAfterDocument(startAfter);
      }
      final snap = await fallbackQuery.get();
      return snap.docs.map((d) => Playlist.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('getPaginatedPlaylists fallback notice: $e');
      return [];
    }
  }

  /// Forcefully deletes any playlist (admin only).
  /// Cost: 1 write.
  Future<void> forceDeletePlaylist(String playlistId) async {
    await _playlistsCol.doc(playlistId).delete();
  }

  /// Forces a playlist to private or public visibility.
  /// Cost: 1 write.
  Future<void> forceSetVisibility(String playlistId, bool isPublic) async {
    await _playlistsCol.doc(playlistId).update({
      'visibility': isPublic ? 'public' : 'private',
      'isPublic': isPublic,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Forces a playlist to private visibility.
  /// Cost: 1 write.
  Future<void> forceMakePrivate(String playlistId) => forceSetVisibility(playlistId, false);

  /// Toggles collaboration on any playlist.
  /// Cost: 1 write.
  Future<void> forceSetCollab(String playlistId, bool collabEnabled) async {
    await _playlistsCol.doc(playlistId).update({
      'collabEnabled': collabEnabled,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Fetches all playlists owned by a specific user UID.
  Future<List<Playlist>> getPlaylistsByOwner(String ownerUid) async {
    try {
      final snap = await _playlistsCol.where('ownerUid', isEqualTo: ownerUid).get();
      return snap.docs.map((d) => Playlist.fromFirestore(d)).toList();
    } catch (e) {
      debugPrint('getPlaylistsByOwner notice: $e');
      return [];
    }
  }

  /// Fetches all blocked user UIDs in a single query.
  Future<Set<String>> getBlockedUserIds() async {
    try {
      final snap = await _blockedCol.get();
      return snap.docs.map((d) => d.id).toSet();
    } catch (e) {
      debugPrint('getBlockedUserIds notice: $e');
      return {};
    }
  }
}
