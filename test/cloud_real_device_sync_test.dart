import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/services/sync/playlist_cloud_sync_service.dart';
import 'package:music_app/models/track.dart';

class RealHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context);
  }
}

void main() {
  HttpOverrides.global = RealHttpOverrides();

  test('Real cloud slot creation, publish, code lookup, and track retrieval', () async {
    final code = PlaylistCloudSyncService.generateShareCode();
    final testTracks = [
      Track(
        id: 'real_test_track_1',
        title: 'Cyberpunk Odyssey',
        artist: 'Synthwave Master',
        album: 'Neon Horizon',
        duration: '3:45',
        artworkUrl: 'https://images.unsplash.com/photo-1508700115892-45ecd05ae2ad',
        audioUrl: 'https://example.com/audio1.mp3',
        genre: 'Synthwave',
      ),
    ];

    // 1. Device 1 creates cloud slot
    final syncId = await PlaylistCloudSyncService.instance.createCloudSyncSlot(
      localId: 'local_device_1_${DateTime.now().millisecondsSinceEpoch}',
      name: 'Synthwave Galaxy',
      description: 'Tested across real devices',
      authorName: 'Device 1 Creator',
      isPublic: true,
      isSyncEnabled: true,
      tracks: testTracks,
      shareCode: code,
      ownerId: 'usr_device_1',
    );

    expect(syncId, isNotNull);
    expect(syncId!.isNotEmpty, isTrue);

    // 2. Device 2 finds playlist by unique share code
    final retrievedByCode = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode(code);
    expect(retrievedByCode, isNotNull);
    expect(retrievedByCode!['name'], equals('Synthwave Galaxy'));
    expect(retrievedByCode['shareCode'], equals(code));
    expect(retrievedByCode['tracks'], isNotEmpty);

    // 3. Device 2 performs sync with a new track
    final device2Tracks = List<Track>.from(testTracks)..add(
      Track(
        id: 'real_test_track_2',
        title: 'Retro Highway',
        artist: 'Outrun Legend',
        album: 'Neon Horizon',
        duration: '4:10',
        artworkUrl: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4',
        audioUrl: 'https://example.com/audio2.mp3',
        genre: 'Synthwave',
        addedBy: 'Device 2 Friend',
      ),
    );

    final syncResult = await PlaylistCloudSyncService.instance.syncPlaylist(
      syncId: syncId,
      currentAuthor: 'Device 2 Friend',
      localTracks: device2Tracks,
      isSyncEnabled: true,
      playlistName: 'Synthwave Galaxy',
      playlistDescription: 'Updated by Device 2',
      shareCode: code,
      ownerId: 'usr_device_1',
    );

    expect(syncResult.success, isTrue);

    // 4. Verify remote has updated merged tracks
    final updatedTracks = await PlaylistCloudSyncService.instance.fetchPlaylistTracksBySyncId(syncId);
    expect(updatedTracks.length, equals(2));
  }, timeout: const Timeout(Duration(seconds: 40)));
}
