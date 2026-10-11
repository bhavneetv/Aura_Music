import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../config/admin_config.dart';
import '../models/app_user.dart';
import '../services/auth/auth_service.dart';
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

/// True if the current user matches the verified Admin Email.
final isAdminProvider = Provider<bool>((ref) {
  final authUser = ref.watch(authStateStreamProvider).value;
  if (authUser == null || authUser.email == null) return false;
  
  final isMatchingEmail = authUser.email!.trim().toLowerCase() == kAdminEmail.trim().toLowerCase();
  final isVerified = authUser.emailVerified;
  return isMatchingEmail && isVerified;
});
