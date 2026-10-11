import 'dart:async';
import 'dart:math' as math;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../models/app_user.dart';
import '../../models/user_model.dart';
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../models/track.dart';
import '../storage/storage_service.dart';
import '../playlist/playlist_repository.dart';
import '../user_service.dart';

class AuthResult {
  final bool success;
  final String? message;
  final AppUser? user;

  const AuthResult({required this.success, this.message, this.user});

  factory AuthResult.ok([AppUser? user]) => AuthResult(success: true, user: user);
  factory AuthResult.fail(String msg) => AuthResult(success: false, message: msg);
}

class AuthService {
  AuthService._();
  static final AuthService instance = AuthService._();

  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final UserService _userService = UserService();

  // Backward compatibility notifier for existing UI listeners
  final ValueNotifier<bool> authState = ValueNotifier<bool>(false);
  
  // Notifier to trigger playlist refresh across UI when push/pull or sync occurs
  final ValueNotifier<int> playlistsChangedNotifier = ValueNotifier<int>(0);
  
  // Real-time app user cache
  AppUser? _currentAppUser;
  StreamSubscription<User?>? _authSub;
  StreamSubscription<AppUser?>? _userDocSub;

  bool _initialized = false;

  void init() {
    if (_initialized) return;
    _initialized = true;

    _authSub = _auth.authStateChanges().listen((firebaseUser) {
      final isLoggedIn = firebaseUser != null;
      authState.value = isLoggedIn;

      _userDocSub?.cancel();
      if (firebaseUser != null) {
        _userDocSub = _userService.watchUser(firebaseUser.uid, isEmailVerified: firebaseUser.emailVerified).listen((appUser) {
          _currentAppUser = appUser;
          if (appUser != null) {
            _syncLocalProfile(appUser);
          }
        });
      } else {
        _currentAppUser = null;
      }
    });
  }

  Future<void> _syncLocalProfile(AppUser appUser) async {
    final name = appUser.displayName.trim();
    if (name.isNotEmpty) {
      await StorageService.setUserAuthorName(name);
      await StorageService.setUserName(name);
      await StorageService.saveCurrentUser(UserModel(
        id: appUser.uid,
        name: name,
        email: appUser.email ?? '',
        passwordHash: '',
        cloudSlotId: '',
        createdAt: appUser.createdAt.millisecondsSinceEpoch,
      ));
    }
  }

  void dispose() {
    _authSub?.cancel();
    _userDocSub?.cancel();
  }

  // --- Getters & Status ---
  User? get currentFirebaseUser => _auth.currentUser;
  AppUser? get currentAppUser => _currentAppUser;
  bool get isLoggedIn => _auth.currentUser != null;
  bool get isGuest => _auth.currentUser?.isAnonymous ?? false;
  bool get canSyncAccountPlaylists => isLoggedIn && !isGuest;
  String get currentUserId => _auth.currentUser?.uid ?? '';
  String? get currentUserEmail => _auth.currentUser?.email;
  String get currentUserName => 
      _currentAppUser?.displayName ??
      _auth.currentUser?.displayName ?? 
      (isGuest ? 'Guest Listener' : 'Aura Listener');

  // Compatibility getter with legacy UserModel
  UserModel? get currentUser {
    final user = _auth.currentUser;
    if (user == null) return null;
    return UserModel(
      id: user.uid,
      name: currentUserName,
      email: user.email ?? '',
      passwordHash: '',
      cloudSlotId: '',
      createdAt: _currentAppUser?.createdAt.millisecondsSinceEpoch ?? DateTime.now().millisecondsSinceEpoch,
    );
  }

  Stream<User?> get authStateChanges => _auth.authStateChanges();

  // --- 1. Google Sign-In ---
  Future<AuthResult> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User cancelled the Google sign-in flow
        return AuthResult.fail('Google sign-in was cancelled.');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final UserCredential userCredential = await _auth.signInWithCredential(credential);
      final user = userCredential.user;
      if (user == null) return AuthResult.fail('Failed to obtain user info.');

      final appUser = await _userService.syncUserOnLogin(user, preferredName: googleUser.displayName);
      _currentAppUser = appUser;
      await _syncLocalProfile(appUser);
      authState.value = true;
      return AuthResult.ok(appUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } on PlatformException catch (e) {
      if (e.message?.contains('10') == true || e.code == 'sign_in_failed') {
        return AuthResult.fail(
          'Google Sign-In needs SHA-1 fingerprint: Add your debug SHA-1 in Firebase Console (Project Settings -> Your apps -> Android) and enable Google in Authentication -> Sign-in method.',
        );
      }
      return AuthResult.fail('Google sign-in error: ${e.message ?? e.code}');
    } catch (e) {
      debugPrint('Google Sign-In Error: $e');
      if (e.toString().contains('10') || e.toString().contains('sign_in_failed')) {
        return AuthResult.fail(
          'Google Sign-In needs SHA-1 fingerprint: Add your debug SHA-1 in Firebase Console (Project Settings -> Your apps -> Android) and enable Google in Authentication -> Sign-in method.',
        );
      }
      return AuthResult.fail('Google sign-in error: $e');
    }
  }

  // --- 2. Email + Password Sign In ---
  Future<AuthResult> signInWithEmail(String email, String password) async {
    try {
      final credential = await _auth.signInWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) return AuthResult.fail('Failed to sign in.');

      final appUser = await _userService.syncUserOnLogin(user);
      _currentAppUser = appUser;
      await _syncLocalProfile(appUser);
      authState.value = true;
      return AuthResult.ok(appUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Sign-in failed: $e');
    }
  }

  // Compatibility alias for existing login calls
  Future<AuthResult> login({required String email, required String password}) =>
      signInWithEmail(email, password);

  // --- 3. Email + Password Sign Up ---
  Future<AuthResult> signUpWithEmail(String name, String email, String password) async {
    try {
      final credential = await _auth.createUserWithEmailAndPassword(
        email: email.trim(),
        password: password,
      );
      final user = credential.user;
      if (user == null) return AuthResult.fail('Failed to create account.');

      // Update Firebase Auth profile
      await user.updateDisplayName(name.trim());

      // Send email verification
      try {
        await user.sendEmailVerification();
      } catch (e) {
        debugPrint('Verification email warning: $e');
      }

      final appUser = await _userService.syncUserOnLogin(user, preferredName: name.trim());
      _currentAppUser = appUser;
      await _syncLocalProfile(appUser);
      authState.value = true;
      return AuthResult.ok(appUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Sign-up failed: $e');
    }
  }

  // Compatibility alias for existing register calls
  Future<AuthResult> register({required String name, required String email, required String password}) =>
      signUpWithEmail(name, email, password);

  // --- 4. Guest / Anonymous Sign In ---
  Future<AuthResult> signInAsGuest(String displayName) async {
    final name = displayName.trim();
    if (name.length < 2 || name.length > 24) {
      return AuthResult.fail('Display name must be between 2 and 24 characters.');
    }

    try {
      final credential = await _auth.signInAnonymously();
      final user = credential.user;
      if (user == null) return AuthResult.fail('Failed to start guest session.');

      await user.updateDisplayName(name);

      final appUser = await _userService.syncUserOnLogin(user, preferredName: name);
      _currentAppUser = appUser;
      await _syncLocalProfile(appUser);
      authState.value = true;
      return AuthResult.ok(appUser);
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Guest login failed: $e');
    }
  }

  // --- 5. Account Linking: Add Google to Email/Password or Guest ---
  Future<AuthResult> linkGoogleAccount() async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.fail('No active session.');

    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return AuthResult.fail('Google sign-in was cancelled.');
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      final userCred = await user.linkWithCredential(credential);
      final updatedUser = userCred.user ?? user;

      final providers = updatedUser.providerData
          .map((p) => p.providerId.replaceAll('.com', ''))
          .toList();
      await _userService.updateProviders(updatedUser.uid, providers, isGuest: false);

      return AuthResult.ok();
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Linking Google failed: $e');
    }
  }

  // --- 6. Account Linking: Add Email & Password to Google or Guest ---
  Future<AuthResult> linkEmailPassword(String email, String password) async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.fail('No active session.');

    try {
      final credential = EmailAuthProvider.credential(
        email: email.trim(),
        password: password,
      );

      final userCred = await user.linkWithCredential(credential);
      final updatedUser = userCred.user ?? user;

      try {
        await updatedUser.sendEmailVerification();
      } catch (_) {}

      final providers = updatedUser.providerData
          .map((p) => p.providerId.replaceAll('.com', ''))
          .toList();
      await _userService.updateProviders(updatedUser.uid, providers, isGuest: false);

      return AuthResult.ok();
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Linking email failed: $e');
    }
  }

  // --- 7. Upgrade Guest User ---
  Future<AuthResult> upgradeGuestWithGoogle() => linkGoogleAccount();

  Future<AuthResult> upgradeGuestWithEmail(String email, String password) =>
      linkEmailPassword(email, password);

  // --- 8. Password Reset ---
  Future<AuthResult> sendPasswordReset(String email) async {
    try {
      await _auth.sendPasswordResetEmail(email: email.trim());
      return AuthResult.ok();
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Password reset error: $e');
    }
  }

  // --- 9. Email Verification ---
  Future<AuthResult> sendEmailVerification() async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.fail('No active user.');
    try {
      await user.sendEmailVerification();
      return AuthResult.ok();
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Email verification failed: $e');
    }
  }

  // --- 10. Update Profile ---
  Future<AuthResult> updateDisplayName(String newName) async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.fail('Not signed in.');
    final trimmed = newName.trim();
    if (trimmed.length < 2 || trimmed.length > 24) {
      return AuthResult.fail('Name must be between 2 and 24 characters.');
    }

    try {
      await user.updateDisplayName(trimmed);
      await _userService.updateDisplayName(user.uid, trimmed);
      return AuthResult.ok();
    } catch (e) {
      return AuthResult.fail('Failed to update name: $e');
    }
  }

  // --- 11. Sign Out ---
  Future<void> signOut() async {
    try {
      await _googleSignIn.signOut();
    } catch (_) {}
    await _auth.signOut();
    _currentAppUser = null;
    authState.value = false;
  }

  // Compatibility alias for existing logout calls
  Future<void> logout() => signOut();

  // --- 12. Delete Account ---
  Future<AuthResult> deleteAccount() async {
    final user = _auth.currentUser;
    if (user == null) return AuthResult.fail('Not signed in.');

    try {
      final uid = user.uid;
      // Delete user document in Firestore
      await _userService.deleteUserDoc(uid);
      // Delete Firebase Auth user
      await user.delete();
      await signOut();
      return AuthResult.ok();
    } on FirebaseAuthException catch (e) {
      return AuthResult.fail(_mapAuthError(e));
    } catch (e) {
      return AuthResult.fail('Delete account failed: $e');
    }
  }

  // --- Push & Pull Cloud Playlists Backup / Restore ---

  /// Push all local playlists and favorites to Cloud Firestore under current user's UID.
  Future<String> backupUserPlaylists() async {
    if (isGuest) {
      return 'Guest accounts cannot sync playlists to cloud. Please sign in or link your account.';
    }
    final uid = currentUserId;
    if (uid.isEmpty) {
      return 'Please sign in first to back up your playlists.';
    }

    try {
      final repo = PlaylistRepository();
      final localPlaylists = StorageService.getPlaylists();
      final localIds = <String>{};
      int pushedCount = 0;

      for (final raw in localPlaylists) {
        String id = raw['id']?.toString() ?? '';
        if (id.isEmpty) {
          id = DateTime.now().millisecondsSinceEpoch.toString();
          raw['id'] = id;
        }

        // If this playlist is imported or joined as a collaborator, do NOT hijack ownership
        final isImported = raw['isImported'] == true;
        final rawOwnerId = raw['ownerId']?.toString() ?? '';
        final isOwner = !isImported && (rawOwnerId.isEmpty || rawOwnerId == uid);

        if (!isOwner) {
          // If collaborative sync is enabled, sync the tracks to remote without modifying ownership
          if (raw['isSyncEnabled'] == true && id.isNotEmpty) {
            try {
              final rawTracks = raw['tracks'] as List? ?? [];
              final localTracks = <Track>[];
              for (final t in rawTracks) {
                if (t is Map) {
                  try {
                    localTracks.add(Track.fromJson(Map<String, dynamic>.from(t)));
                  } catch (_) {}
                }
              }
              final synced = await repo.syncPlaylistTracks(
                playlistId: id,
                callerUid: uid,
                callerName: currentUserName,
                localTracks: localTracks,
                deletedTrackIds: List<String>.from(raw['deletedTrackIds'] as List? ?? []),
                baseTrackIds: List<String>.from(raw['syncedTrackIds'] as List? ?? []),
              );
              raw['syncedTrackIds'] = synced.map((t) => t.id).toList();
              raw['tracks'] = synced.map((t) => t.toJson()).toList();
              raw['trackIds'] = synced.map((t) => t.id).toList();
              raw['deletedTrackIds'] = <String>[];
            } catch (se) {
              debugPrint('Failed to sync collaborative tracks for $id: $se');
            }
          }
          continue;
        }

        localIds.add(id);

        final rawTracks = raw['tracks'] as List? ?? [];
        final tracks = <PlaylistTrack>[];
        for (final t in rawTracks) {
          if (t is Map) {
            try {
              final track = Track.fromJson(Map<String, dynamic>.from(t));
              tracks.add(PlaylistTrack.fromTrack(
                track,
                addedByUid: uid,
                addedByName: currentUserName,
              ));
            } catch (_) {}
          }
        }

        final pl = Playlist(
          id: id,
          name: raw['name']?.toString() ?? 'My Playlist',
          description: raw['description']?.toString() ?? '',
          ownerUid: uid,
          ownerName: currentUserName.isNotEmpty ? currentUserName : (raw['authorName']?.toString() ?? 'Aura User'),
          memberUids: [uid],
          visibility: raw['isPublic'] == true ? 'public' : 'private',
          collabEnabled: raw['isSyncEnabled'] == true,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
          trackCount: tracks.length,
          tracks: tracks,
          shareCode: raw['shareCode']?.toString(),
        );

        await repo.saveOrUpdatePlaylist(pl);
        pushedCount++;
      }

      if (localPlaylists.isNotEmpty) {
        await StorageService.savePlaylists(localPlaylists);
      }

      // --- PRUNE DELETED PLAYLISTS FROM CLOUD ---
      // Any remote playlist owned by this user that is NOT in localIds was deleted locally,
      // so delete it from cloud backup as well!
      try {
        final remoteOwnedSnap = await FirebaseFirestore.instance
            .collection('playlists')
            .where('ownerUid', isEqualTo: uid)
            .get();

        for (final doc in remoteOwnedSnap.docs) {
          final data = doc.data();
          final type = data['type']?.toString() ?? 'custom';
          if (type == 'favorites') continue;

          if (!localIds.contains(doc.id)) {
            try {
              await repo.deletePlaylist(doc.id, uid);
            } catch (de) {
              debugPrint('Failed to prune deleted remote playlist ${doc.id}: $de');
            }
          }
        }
      } catch (pe) {
        debugPrint('Failed to query remote playlists for pruning: $pe');
      }

      // Also backup favorites
      final favTracks = StorageService.getFavoriteTracks();
      if (favTracks.isNotEmpty) {
        final favPl = await repo.getOrCreateFavorites(uid, currentUserName);
        for (final t in favTracks) {
          try {
            await repo.addTrack(
              favPl.id,
              PlaylistTrack.fromTrack(t, addedByUid: uid, addedByName: currentUserName),
              uid,
            );
          } catch (_) {}
        }
      }

      playlistsChangedNotifier.value++;

      // Sync watch history count (number only) to user profile in Firestore
      if (!isGuest && uid.isNotEmpty) {
        try {
          final historyCount = StorageService.getListeningHistory().length;
          await FirebaseFirestore.instance.collection('users').doc(uid).set({
            'watchHistoryCount': historyCount,
            'lastHistorySyncedAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));
          await StorageService.setSyncedWatchHistoryCount(historyCount);
        } catch (he) {
          debugPrint('backupUserPlaylists watch history count sync error: $he');
        }
      }

      return 'Successfully pushed and backed up $pushedCount playlist(s) to cloud! ☁️';
    } catch (e) {
      debugPrint('backupUserPlaylists error: $e');
      return 'Backup error: $e';
    }
  }

  /// Pull all playlists owned or joined by the current user from Cloud Firestore,
  /// and merge/restore them into local Hive storage.
  Future<int> restoreUserPlaylists() async {
    if (isGuest) return 0;
    final uid = currentUserId;
    if (uid.isEmpty) return 0;

    try {
      final docMap = <String, DocumentSnapshot<Map<String, dynamic>>>{};

      // 1. Query playlists where current user is in memberUids
      try {
        final querySnapshot = await FirebaseFirestore.instance
            .collection('playlists')
            .where('memberUids', arrayContains: uid)
            .get();
        for (final doc in querySnapshot.docs) {
          docMap[doc.id] = doc;
        }
      } catch (e) {
        debugPrint('restoreUserPlaylists memberUids query error: $e');
      }

      // 2. Query playlists where current user is ownerUid
      try {
        final ownerSnapshot = await FirebaseFirestore.instance
            .collection('playlists')
            .where('ownerUid', isEqualTo: uid)
            .get();
        for (final doc in ownerSnapshot.docs) {
          docMap[doc.id] = doc;
        }
      } catch (e) {
        debugPrint('restoreUserPlaylists ownerUid query error: $e');
      }

      if (docMap.isEmpty) {
        return 0;
      }

      final existingLocal = StorageService.getPlaylists();
      // Keep local playlists that are NOT owned by the current user (e.g. joined or other author),
      // or that ARE present in docMap. Any playlist owned by the current user that is no longer
      // in docMap was pruned/deleted from cloud, so it should not linger locally.
      final localMap = <String, Map<String, dynamic>>{};
      for (final p in existingLocal) {
        final pid = p['id']?.toString() ?? '';
        if (pid.isEmpty) continue;
        final ownerId = p['ownerId']?.toString() ?? p['ownerUid']?.toString() ?? '';
        final isOwnedByCurrentUser = ownerId.isNotEmpty && ownerId == uid;
        if (isOwnedByCurrentUser) {
          if (docMap.containsKey(pid)) {
            localMap[pid] = p;
          }
        } else {
          localMap[pid] = p;
        }
      }

      int restoredCount = 0;

      for (final doc in docMap.values) {
        final data = doc.data() ?? {};
        final pl = Playlist.fromMap(data, id: doc.id);

        if (pl.type == 'favorites') {
          final favTracks = pl.tracks.map((pt) => pt.toTrack()).toList();
          for (final ft in favTracks) {
            await StorageService.toggleFavoriteTrack(ft);
          }
          continue;
        }

        final convertedTracks = pl.tracks.map((pt) {
          final t = pt.toTrack();
          return t.toJson();
        }).toList();

        final isOwner = pl.isOwner(uid);
        final playlistMap = <String, dynamic>{
          'id': pl.id,
          'name': pl.name,
          'description': pl.description,
          'authorName': pl.ownerName,
          'ownerId': pl.ownerUid,
          'ownerEmail': isOwner ? (currentUserEmail ?? '') : (data['ownerEmail']?.toString() ?? ''),
          'ownerName': pl.ownerName,
          'isImported': !isOwner,
          'isPublic': pl.isPublic,
          'isSyncEnabled': pl.collabEnabled,
          'shareCode': pl.shareCode ?? (data['shareCode']?.toString() ?? ''),
          'trackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
          'syncedTrackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
          'tracks': convertedTracks,
        };

        if (!localMap.containsKey(pl.id)) {
          restoredCount++;
        }
        localMap[pl.id] = playlistMap;
      }

      final updatedPlaylists = <Map<String, dynamic>>[];
      for (final p in existingLocal) {
        final pid = p['id']?.toString() ?? '';
        if (pid.isEmpty) {
          updatedPlaylists.add(p);
        }
      }
      updatedPlaylists.addAll(localMap.values);

      await StorageService.savePlaylists(updatedPlaylists);

      // Trigger instant UI refresh across the app
      playlistsChangedNotifier.value++;

      // Pull and sync watch history count (number only) from cloud
      if (!isGuest && uid.isNotEmpty) {
        try {
          final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
          if (userDoc.exists && userDoc.data() != null) {
            final cloudCount = userDoc.data()!['watchHistoryCount'];
            if (cloudCount is num) {
              final localCount = StorageService.getListeningHistory().length;
              final finalCount = math.max(localCount, cloudCount.toInt());
              await StorageService.setSyncedWatchHistoryCount(finalCount);
            }
          }
        } catch (he) {
          debugPrint('restoreUserPlaylists watch history count pull error: $he');
        }
      }

      return restoredCount > 0 ? restoredCount : docMap.length;
    } catch (e) {
      debugPrint('restoreUserPlaylists error: $e');
      return 0;
    }
  }

  /// Sync watch history count (integer number only) to cloud Firestore under users/{uid}
  Future<void> syncWatchHistoryCount() async {
    if (isGuest || !isLoggedIn) return;
    final uid = currentUserId;
    if (uid.isEmpty) return;
    try {
      final historyCount = StorageService.getListeningHistory().length;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'watchHistoryCount': historyCount,
        'lastHistorySyncedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      await StorageService.setSyncedWatchHistoryCount(historyCount);
    } catch (e) {
      debugPrint('syncWatchHistoryCount error: $e');
    }
  }

  bool isPlaylistOwner(Map<String, dynamic> playlist) {
    if (playlist['isImported'] == true) {
      return false;
    }
    final ownerId = playlist['ownerId']?.toString() ?? playlist['ownerUid']?.toString();
    if (ownerId != null && ownerId.isNotEmpty && ownerId == currentUserId) {
      return true;
    }
    final ownerEmail = (playlist['ownerEmail'] ?? '').toString().trim().toLowerCase();
    if (currentUserEmail != null &&
        currentUserEmail!.isNotEmpty &&
        ownerEmail.isNotEmpty &&
        ownerEmail == currentUserEmail!.toLowerCase()) {
      return true;
    }
    return false;
  }

  // --- Friendly User-Facing Error Messages ---
  String _mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'credential-already-in-use':
        return 'This account is already linked to another user profile.';
      case 'email-already-in-use':
        return 'An account already exists with this email address. Please sign in with your existing password or Google account, then link the other provider in Settings.';
      case 'account-exists-with-different-credential':
        return 'An account already exists with this email using a different sign-in method. Please sign in with that method first, then link from Settings.';
      case 'provider-already-linked':
        return 'This sign-in provider is already linked to your account.';
      case 'requires-recent-login':
        return 'This operation is sensitive and requires a recent login. Please sign out and sign in again.';
      case 'network-request-failed':
        return 'Network connection error. Please check your internet connection and try again.';
      case 'invalid-email':
        return 'The provided email address is not valid.';
      case 'user-disabled':
        return 'This user account has been disabled.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return 'Invalid email or password. Please verify your credentials.';
      case 'weak-password':
        return 'The password is too weak. Please use at least 6 characters.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a few moments and try again.';
      case 'operation-not-allowed':
      case 'admin-restricted-operation':
      case 'configuration-not-found':
        return 'This sign-in provider is not enabled in Firebase Console. Please go to Firebase Console -> Authentication -> Sign-in method and enable it (Anonymous, Google, or Email/Password).';
      default:
        return e.message ?? 'An unexpected authentication error occurred.';
    }
  }
}
