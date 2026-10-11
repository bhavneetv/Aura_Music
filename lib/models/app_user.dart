import 'package:cloud_firestore/cloud_firestore.dart';
import 'user_stats.dart';

class AppUser {
  final String uid;
  final String displayName;
  final String? email;
  final String? photoUrl;
  final bool isGuest;
  final List<String> providers;
  final DateTime createdAt;
  final DateTime lastLoginAt;
  final int loginCount;
  final UserStats stats;
  final bool isEmailVerified;

  const AppUser({
    required this.uid,
    required this.displayName,
    this.email,
    this.photoUrl,
    required this.isGuest,
    required this.providers,
    required this.createdAt,
    required this.lastLoginAt,
    required this.loginCount,
    required this.stats,
    this.isEmailVerified = false,
  });

  factory AppUser.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc, {bool isEmailVerified = false}) {
    final data = doc.data() ?? {};
    
    DateTime parseTimestamp(dynamic val) {
      if (val is Timestamp) return val.toDate();
      if (val is int) return DateTime.fromMillisecondsSinceEpoch(val);
      if (val is String) return DateTime.tryParse(val) ?? DateTime.now();
      return DateTime.now();
    }

    final providersRaw = data['providers'] as List<dynamic>? ?? [];
    final providers = providersRaw.map((e) => e.toString()).toList();

    final baseStats = UserStats.fromMap(data['stats'] as Map<String, dynamic>?);
    final historyCount = (data['watchHistoryCount'] as num?)?.toInt() ?? 0;
    final effectiveStats = baseStats.totalSongsPlayed == 0 && historyCount > 0
        ? baseStats.copyWith(totalSongsPlayed: historyCount)
        : baseStats;

    return AppUser(
      uid: doc.id,
      displayName: (data['displayName'] as String?)?.isNotEmpty == true 
          ? data['displayName'] as String 
          : 'Guest Listener',
      email: data['email'] as String?,
      photoUrl: data['photoUrl'] as String?,
      isGuest: (data['isGuest'] as bool?) ?? false,
      providers: providers,
      createdAt: parseTimestamp(data['createdAt']),
      lastLoginAt: parseTimestamp(data['lastLoginAt']),
      loginCount: (data['loginCount'] as num?)?.toInt() ?? 1,
      stats: effectiveStats,
      isEmailVerified: isEmailVerified,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'uid': uid,
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'isGuest': isGuest,
      'providers': providers,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'lastLoginAt': lastLoginAt.millisecondsSinceEpoch,
      'loginCount': loginCount,
      'stats': stats.toMap(),
      'isEmailVerified': isEmailVerified,
    };
  }

  factory AppUser.fromMap(Map<String, dynamic> map) {
    return AppUser(
      uid: map['uid'] as String? ?? '',
      displayName: map['displayName'] as String? ?? 'Aura Listener',
      email: map['email'] as String?,
      photoUrl: map['photoUrl'] as String?,
      isGuest: map['isGuest'] as bool? ?? false,
      providers: List<String>.from(map['providers'] ?? []),
      createdAt: map['createdAt'] is int ? DateTime.fromMillisecondsSinceEpoch(map['createdAt']) : DateTime.now(),
      lastLoginAt: map['lastLoginAt'] is int ? DateTime.fromMillisecondsSinceEpoch(map['lastLoginAt']) : DateTime.now(),
      loginCount: (map['loginCount'] as num?)?.toInt() ?? 1,
      stats: UserStats.fromMap(map['stats'] as Map<String, dynamic>?),
      isEmailVerified: map['isEmailVerified'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'displayName': displayName,
      'email': email,
      'photoUrl': photoUrl,
      'isGuest': isGuest,
      'providers': providers,
      'createdAt': Timestamp.fromDate(createdAt),
      'lastLoginAt': Timestamp.fromDate(lastLoginAt),
      'loginCount': loginCount,
      'stats': stats.toMap(),
    };
  }

  AppUser copyWith({
    String? displayName,
    String? email,
    String? photoUrl,
    bool? isGuest,
    List<String>? providers,
    DateTime? createdAt,
    DateTime? lastLoginAt,
    int? loginCount,
    UserStats? stats,
    bool? isEmailVerified,
  }) {
    return AppUser(
      uid: uid,
      displayName: displayName ?? this.displayName,
      email: email ?? this.email,
      photoUrl: photoUrl ?? this.photoUrl,
      isGuest: isGuest ?? this.isGuest,
      providers: providers ?? this.providers,
      createdAt: createdAt ?? this.createdAt,
      lastLoginAt: lastLoginAt ?? this.lastLoginAt,
      loginCount: loginCount ?? this.loginCount,
      stats: stats ?? this.stats,
      isEmailVerified: isEmailVerified ?? this.isEmailVerified,
    );
  }
}
