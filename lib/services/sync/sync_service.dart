import 'package:flutter/foundation.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../stats/stats_service.dart';
import '../migration/migration_service.dart';
import '../auth/auth_service.dart';

class SyncService {
  static final SyncService instance = SyncService._();
  SyncService._();

  static const String _kAutoSyncKey = 'sync_auto_enabled_v1';
  static const String _kSyncWifiOnlyKey = 'sync_wifi_only_v1';
  static const String _kLastSyncedTimeKey = 'sync_last_synced_timestamp';

  final ValueNotifier<bool> autoSync = ValueNotifier<bool>(true);
  final ValueNotifier<bool> syncWifiOnly = ValueNotifier<bool>(false);
  final ValueNotifier<DateTime?> lastSyncedAt = ValueNotifier<DateTime?>(null);
  final ValueNotifier<bool> isSyncing = ValueNotifier<bool>(false);

  bool _initialized = false;

  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    final prefs = await SharedPreferences.getInstance();
    autoSync.value = prefs.getBool(_kAutoSyncKey) ?? true;
    syncWifiOnly.value = prefs.getBool(_kSyncWifiOnlyKey) ?? false;

    final lastMs = prefs.getInt(_kLastSyncedTimeKey);
    if (lastMs != null) {
      lastSyncedAt.value = DateTime.fromMillisecondsSinceEpoch(lastMs);
    }
  }

  Future<void> setAutoSync(bool enabled) async {
    autoSync.value = enabled;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kAutoSyncKey, enabled);
  }

  Future<void> setSyncWifiOnly(bool wifiOnly) async {
    syncWifiOnly.value = wifiOnly;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kSyncWifiOnlyKey, wifiOnly);
  }

  /// Performs an immediate sync.
  /// Returns a user-friendly status message.
  Future<String> syncNow() async {
    if (isSyncing.value) return 'Sync already in progress...';
    isSyncing.value = true;

    try {
      final connectivity = await Connectivity().checkConnectivity();
      final hasWifi = connectivity.contains(ConnectivityResult.wifi);
      final hasCellular = connectivity.contains(ConnectivityResult.mobile);
      final hasEthernet = connectivity.contains(ConnectivityResult.ethernet);
      final isOnline = hasWifi || hasCellular || hasEthernet;

      if (!isOnline) {
        return 'Account & database sync is disabled in offline mode.';
      }

      if (syncWifiOnly.value && !hasWifi && !hasEthernet) {
        return 'Sync skipped: "Sync on Wi-Fi only" is enabled.';
      }

      // Flush batched stats
      await StatsService.instance.flushPendingStats();

      // Ensure local migration is completed
      final user = AuthService.instance.currentFirebaseUser;
      if (user != null) {
        final userName = AuthService.instance.currentUserName;
        await MigrationService().migrateLocalDataIfNeeded(
          uid: user.uid,
          userName: userName,
        );
      }

      final now = DateTime.now();
      lastSyncedAt.value = now;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kLastSyncedTimeKey, now.millisecondsSinceEpoch);

      return 'Sync complete!';
    } catch (e) {
      return 'Sync error: $e';
    } finally {
      isSyncing.value = false;
    }
  }
}
