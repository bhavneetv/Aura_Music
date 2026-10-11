import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:google_sign_in/google_sign_in.dart';
import '../../models/app_user.dart';
import '../../models/user_model.dart';
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
        });
      } else {
        _currentAppUser = null;
      }
    });
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

  // --- Backward Compatibility Placeholders for Old Backup/Restore ---
  Future<String> backupUserPlaylists() async {
    return 'Playlists are now automatically synced live via Firestore!';
  }

  Future<int> restoreUserPlaylists() async {
    return 0;
  }

  bool isPlaylistOwner(Map<String, dynamic> playlist) {
    final ownerId = playlist['ownerId']?.toString() ?? playlist['ownerUid']?.toString();
    if (ownerId != null && ownerId.isNotEmpty && ownerId == currentUserId) {
      return true;
    }
    final ownerEmail = (playlist['ownerEmail'] ?? '').toString().trim().toLowerCase();
    if (currentUserEmail != null && ownerEmail.isNotEmpty && ownerEmail == currentUserEmail!.toLowerCase()) {
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
