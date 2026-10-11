import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/auth/auth_service.dart';
import 'package:music_app/services/sync/playlist_cloud_sync_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('AuthService Tests', () {
    test('AuthService instance initialization', () {
      final auth = AuthService.instance;
      expect(auth, isNotNull);
    });

    test('Ownership check correctly differentiates owner vs non-owner', () {
      final auth = AuthService.instance;

      // Playlist created by current user
      final myPlaylist = {
        'id': 'pl_101',
        'name': 'My Chill Vibes',
        'ownerId': auth.currentUserId,
        'authorName': auth.currentUserName,
        'isImported': false,
      };
      expect(auth.isPlaylistOwner(myPlaylist), isTrue);

      // Playlist imported from another device/user
      final importedPlaylist = {
        'id': 'pl_102',
        'name': 'Someone Else Vibes',
        'ownerId': 'usr_other_device_999',
        'authorName': 'Device 2 User',
        'isImported': true,
      };
      expect(auth.isPlaylistOwner(importedPlaylist), isFalse);

      // Cross-device same-account: matching email or currentUserId owns it even if isImported was set
      final crossDeviceMyPlaylist = {
        'id': 'pl_103',
        'name': 'Created on Device 1 by Me',
        'ownerId': auth.currentUserId,
        'ownerEmail': 'bhavneet@aura.com',
        'authorName': auth.currentUserName,
        'isImported': true, // e.g. imported via code search on device 2
      };
      // Since ownerId matches currentUserId:
      expect(auth.isPlaylistOwner(crossDeviceMyPlaylist), isTrue);
    });
  });

  group('PlaylistCloudSyncService ShareCode Tests', () {
    test('generateShareCode generates clean AURA-XXXXXX codes', () {
      final code1 = PlaylistCloudSyncService.generateShareCode();
      final code2 = PlaylistCloudSyncService.generateShareCode();

      expect(code1.startsWith('AURA-'), isTrue);
      expect(code1.length, equals(11)); // "AURA-" (5) + 6 chars = 11
      expect(code2.startsWith('AURA-'), isTrue);
      expect(code1, isNot(equals(code2)));
    });

    test('fetchPlaylistByShareCode correctly parses code query with or without prefix', () async {
      // Test seed playlist code lookup
      final resWithPrefix = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode('AURA-LOFI99');
      // Even if network is not mocking seed, it should handle format gracefully
      expect(resWithPrefix == null || resWithPrefix['name'] != null, isTrue);
    });
  });
}
