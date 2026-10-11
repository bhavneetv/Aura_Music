import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/app_user.dart';
import '../models/user_stats.dart';

class UserService {
  final FirebaseFirestore _firestore;

  UserService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> get _usersCol =>
      _firestore.collection('users');

  /// Creates or updates the user profile document upon sign-in.
  /// Cost: 1 read (check existing), 1 write (set or update).
  Future<AppUser> syncUserOnLogin(User firebaseUser, {String? preferredName}) async {
    final docRef = _usersCol.doc(firebaseUser.uid);
    // Cost: 1 read
    final snapshot = await docRef.get();

    final providers = firebaseUser.providerData
        .map((p) => p.providerId.replaceAll('.com', ''))
        .toList();
    if (firebaseUser.isAnonymous && !providers.contains('anonymous')) {
      providers.add('anonymous');
    }

    final now = DateTime.now();
    final displayName = preferredName?.trim().isNotEmpty == true
        ? preferredName!.trim()
        : (firebaseUser.displayName?.trim().isNotEmpty == true
            ? firebaseUser.displayName!.trim()
            : (firebaseUser.isAnonymous ? 'Guest Listener' : 'Aura Listener'));

    if (!snapshot.exists) {
      // First login for this user! Cost: 1 write
      String? linkedGoogleEmail;
      String? linkedPasswordEmail;
      for (final p in firebaseUser.providerData) {
        if (p.providerId.contains('google') && p.email != null && p.email!.isNotEmpty) {
          linkedGoogleEmail = p.email;
        }
        if (p.providerId.contains('password') && p.email != null && p.email!.isNotEmpty) {
          linkedPasswordEmail = p.email;
        }
      }
      if (providers.contains('google') && linkedGoogleEmail == null && firebaseUser.email != null) {
        linkedGoogleEmail = firebaseUser.email;
      }
      if (providers.contains('password') && linkedPasswordEmail == null && firebaseUser.email != null) {
        linkedPasswordEmail = firebaseUser.email;
      }

      final newUser = AppUser(
        uid: firebaseUser.uid,
        displayName: displayName,
        email: firebaseUser.email,
        photoUrl: firebaseUser.photoURL,
        isGuest: firebaseUser.isAnonymous,
        providers: providers,
        createdAt: now,
        lastLoginAt: now,
        loginCount: 1,
        stats: UserStats.empty(),
        isEmailVerified: firebaseUser.emailVerified,
        linkedGoogleEmail: linkedGoogleEmail,
        linkedPasswordEmail: linkedPasswordEmail,
      );

      await docRef.set(newUser.toFirestore());
      return newUser;
    } else {
      // Existing user sign-in: increment loginCount and update lastLoginAt. Cost: 1 write
      final data = snapshot.data() ?? {};
      final existingLoginCount = (data['loginCount'] as num?)?.toInt() ?? 0;
      final existingProvidersRaw = data['providers'] as List<dynamic>? ?? [];
      final existingProviders = existingProvidersRaw.map((e) => e.toString()).toSet();
      existingProviders.addAll(providers);

      final updates = <String, dynamic>{
        'lastLoginAt': FieldValue.serverTimestamp(),
        'loginCount': existingLoginCount + 1,
        'providers': existingProviders.toList(),
      };

      for (final p in firebaseUser.providerData) {
        if (p.providerId.contains('google') && p.email != null && p.email!.isNotEmpty) {
          updates['linkedGoogleEmail'] = p.email;
        }
        if (p.providerId.contains('password') && p.email != null && p.email!.isNotEmpty) {
          updates['linkedPasswordEmail'] = p.email;
        }
      }
      if (existingProviders.contains('google') && !updates.containsKey('linkedGoogleEmail') && data['linkedGoogleEmail'] == null && firebaseUser.email != null) {
        updates['linkedGoogleEmail'] = firebaseUser.email;
      }
      if (existingProviders.contains('password') && !updates.containsKey('linkedPasswordEmail') && data['linkedPasswordEmail'] == null && firebaseUser.email != null) {
        updates['linkedPasswordEmail'] = firebaseUser.email;
      }

      if (firebaseUser.email != null) {
        updates['email'] = firebaseUser.email;
      }
      if (firebaseUser.photoURL != null) {
        updates['photoUrl'] = firebaseUser.photoURL;
      }
      if (preferredName != null && preferredName.isNotEmpty) {
        updates['displayName'] = preferredName;
      }
      if (!firebaseUser.isAnonymous && (data['isGuest'] == true)) {
        updates['isGuest'] = false;
      }

      await docRef.update(updates);

      // Re-fetch or reconstruct
      return AppUser.fromFirestore(
        await docRef.get(), // Cost: 1 read
        isEmailVerified: firebaseUser.emailVerified,
      );
    }
  }

  /// Real-time stream of the current user document.
  /// Cost: 1 initial read + 1 read per subsequent server-side update.
  Stream<AppUser?> watchUser(String uid, {bool isEmailVerified = false}) {
    return _usersCol.doc(uid).snapshots().map((doc) {
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc, isEmailVerified: isEmailVerified);
    });
  }

  /// Fetches user document once.
  /// Cost: 1 read.
  Future<AppUser?> getUser(String uid, {bool isEmailVerified = false}) async {
    try {
      final doc = await _usersCol.doc(uid).get();
      if (!doc.exists) return null;
      return AppUser.fromFirestore(doc, isEmailVerified: isEmailVerified);
    } catch (e) {
      debugPrint('Error getting user $uid: $e');
      return null;
    }
  }

  /// Updates display name across user profile.
  /// Cost: 1 write.
  Future<void> updateDisplayName(String uid, String newName) async {
    await _usersCol.doc(uid).update({
      'displayName': newName.trim(),
    });
  }

  Future<void> updateProviders(
    String uid,
    List<String> providers, {
    bool isGuest = false,
    String? linkedPasswordEmail,
    String? linkedGoogleEmail,
  }) async {
    final updates = <String, dynamic>{
      'providers': providers,
      'isGuest': isGuest,
    };
    if (linkedPasswordEmail != null && linkedPasswordEmail.isNotEmpty) {
      updates['linkedPasswordEmail'] = linkedPasswordEmail;
    }
    if (linkedGoogleEmail != null && linkedGoogleEmail.isNotEmpty) {
      updates['linkedGoogleEmail'] = linkedGoogleEmail;
    }
    await _usersCol.doc(uid).update(updates);
  }

  /// Deletes user document upon account deletion.
  /// Cost: 1 write.
  Future<void> deleteUserDoc(String uid) async {
    await _usersCol.doc(uid).delete();
  }
}
