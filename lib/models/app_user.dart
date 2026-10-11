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
      stats: UserStats.fromMap(data['stats'] as Map<String, dynamic>?),
      isEmailVerified: isEmailVerified,
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
