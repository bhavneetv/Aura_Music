import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/admin_config.dart';
import '../models/app_user.dart';
import '../services/auth/auth_service.dart';
import '../services/storage/storage_service.dart';
import '../services/user_service.dart';

final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService.instance;
});

final userServiceProvider = Provider<UserService>((ref) {
  return UserService();
});

/// Emits the current Firebase User or null on auth state transitions.
final authStateStreamProvider = StreamProvider<User?>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
});

/// Emits the live [AppUser] Firestore document for the signed-in user.
final currentAppUserStreamProvider = StreamProvider<AppUser?>((ref) {
  final authUserAsync = ref.watch(authStateStreamProvider);
  final user = authUserAsync.value;
  if (user == null) {
    return Stream.value(null);
  }
  final userService = ref.watch(userServiceProvider);
  return userService.watchUser(user.uid, isEmailVerified: user.emailVerified);
});

/// True if the current user is signed in as a guest/anonymous user.
final isGuestProvider = Provider<bool>((ref) {
  final authUser = ref.watch(authStateStreamProvider).value;
  return authUser?.isAnonymous ?? false;
});

/// True if the current user matches the configured Admin Email.
final isAdminProvider = Provider<bool>((ref) {
  final streamUser = ref.watch(authStateStreamProvider).value;
  final authUser = streamUser ??
      AuthService.instance.currentFirebaseUser ??
      FirebaseAuth.instance.currentUser;

  // 1. Direct email on Firebase User object
  if (isConfiguredAdminEmail(authUser?.email)) {
    return true;
  }

  // 2. Any provider email (e.g. Google Sign-In)
  if (authUser != null) {
    for (final p in authUser.providerData) {
      if (isConfiguredAdminEmail(p.email)) {
        return true;
      }
    }
  }

  // 3. Live AppUser document from Firestore
  final appUser = ref.watch(currentAppUserStreamProvider).value ??
      AuthService.instance.currentAppUser;
  if (isConfiguredAdminEmail(appUser?.email)) {
    return true;
  }

  // 4. AuthService cached email getter
  if (isConfiguredAdminEmail(AuthService.instance.currentUserEmail)) {
    return true;
  }

  // 5. Saved local user model in storage
  final localEmail = StorageService.getCurrentUser()?.email;
  if (isConfiguredAdminEmail(localEmail)) {
    return true;
  }

  return false;
});

