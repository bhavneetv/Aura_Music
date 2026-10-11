import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/models/track.dart';
import 'package:music_app/services/sync/playlist_cloud_sync_service.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  HttpOverrides.global = RealHttpOverrides();
  TestWidgetsFlutterBinding.ensureInitialized();
  HttpOverrides.global = RealHttpOverrides();

  group('PlaylistCloudSyncService Tests', () {
    final syncService = PlaylistCloudSyncService.instance;

    test('Create cloud sync slot successfully', () async {
      final sampleTracks = [
        const Track(
          id: 'test_t1',
          title: 'Echoes in the Rain',
          artist: 'Aura Collective',
          album: 'Lofi Chill',
          duration: '3:20',
          artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819',
          audioUrl: 'https://test.com/audio1.mp3',
          genre: 'Lofi',
          addedBy: 'Creator Bhanu',
        ),
      ];

      final syncId = await syncService.createCloudSyncSlot(
        localId: 'local_test_1',
        name: 'Test Shared Session',
        description: 'Collaborative test session',
        authorName: 'Creator Bhanu',
        tracks: sampleTracks,
        isPublic: false,
        isSyncEnabled: true,
      );

      expect(syncId, isNotNull);
      expect(syncId!.isNotEmpty, isTrue);

      // Verify slot can be fetched back
      final fetchedTracks = await syncService.fetchPlaylistTracksBySyncId(syncId);
      expect(fetchedTracks.length, 1);
      expect(fetchedTracks.first.title, 'Echoes in the Rain');
      expect(fetchedTracks.first.addedBy, 'Creator Bhanu');
    });

    test('Two-way sync merges local and remote tracks seamlessly', () async {
      // 1. Device A creates slot with Song 1
      final track1 = const Track(
        id: 'devA_song1',
        title: 'Song One',
        artist: 'Artist A',
        album: 'Album A',
        duration: '2:45',
        artworkUrl: 'https://test.com/art1.jpg',
        audioUrl: 'https://test.com/a1.mp3',
        genre: 'Pop',
        addedBy: 'Alice',
      );

      final syncId = await syncService.createCloudSyncSlot(
        localId: 'local_party_1',
        name: 'Collab Party',
        description: 'Party mix',
        authorName: 'Alice',
        tracks: [track1],
        isPublic: false,
        isSyncEnabled: true,
      );

      expect(syncId, isNotNull);

      // 2. Device B has Song 2 and syncs with that slot
      final track2 = const Track(
        id: 'devB_song2',
        title: 'Song Two',
        artist: 'Artist B',
        album: 'Album B',
        duration: '4:10',
        artworkUrl: 'https://test.com/art2.jpg',
        audioUrl: 'https://test.com/a2.mp3',
        genre: 'Electronic',
        addedBy: 'Bob',
      );

      final syncResultB = await syncService.syncPlaylist(
        syncId: syncId!,
        localTracks: [track2],
        currentAuthor: 'Bob',
        isSyncEnabled: true,
      );

      expect(syncResultB.success, isTrue);
      // Device B receives Song 1 from Alice (+1 added)
      expect(syncResultB.addedCount, 1);
      expect(syncResultB.newContributors, contains('Alice'));
      // Device B now has both songs merged
      expect(syncResultB.mergedTracks.length, 2);

      // 3. Device A syncs again and gets Song 2 from Bob
      final syncResultA = await syncService.syncPlaylist(
        syncId: syncId,
        localTracks: [track1],
        currentAuthor: 'Alice',
        isSyncEnabled: true,
      );

      expect(syncResultA.success, isTrue);
      expect(syncResultA.addedCount, 1);
      expect(syncResultA.newContributors, contains('Bob'));
      expect(syncResultA.mergedTracks.length, 2);
    });

    test('Public Global Playlists registry can publish and fetch', () async {
      final testId = 'test_global_${DateTime.now().millisecondsSinceEpoch}';
      final summary = PublicPlaylistSummary(
        id: 'local_global_test',
        syncId: testId,
        name: 'Late Night Chill Hop',
        description: 'Vibes curated by the community',
        authorName: 'Aura DJ',
        trackCount: 8,
        sampleArtwork: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819',
        isSyncEnabled: true,
        updatedAt: DateTime.now().millisecondsSinceEpoch,
      );

      await syncService.publishToGlobalRegistry(summary);

      final globalPlaylists = await syncService.fetchGlobalPublicPlaylists();
      expect(globalPlaylists.isNotEmpty, isTrue);

      final found = globalPlaylists.any((p) => p.syncId == testId || p.name == 'Late Night Chill Hop');
      expect(found, isTrue);
    });
  });
}
