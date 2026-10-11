import 'dart:convert';
import 'dart:math';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import '../../models/track.dart';

class SyncResult {
  final bool success;
  final int addedCount;
  final List<String> newContributors;
  final List<Track> mergedTracks;
  final String message;

  SyncResult({
    required this.success,
    required this.addedCount,
    required this.newContributors,
    required this.mergedTracks,
    required this.message,
  });
}

class PublicPlaylistSummary {
  final String id;
  final String syncId;
  final String shareCode;
  final String ownerId;
  final String ownerEmail;
  final String name;
  final String description;
  final String authorName;
  final int trackCount;
  final bool isSyncEnabled;
  final String sampleArtwork;
  final int updatedAt;

  PublicPlaylistSummary({
    required this.id,
    required this.syncId,
    this.shareCode = '',
    this.ownerId = '',
    this.ownerEmail = '',
    required this.name,
    required this.description,
    required this.authorName,
    required this.trackCount,
    required this.isSyncEnabled,
    required this.sampleArtwork,
    required this.updatedAt,
  });

  factory PublicPlaylistSummary.fromJson(Map<String, dynamic> json) {
    return PublicPlaylistSummary(
      id: json['id']?.toString() ?? '',
      syncId: json['syncId']?.toString() ?? '',
      shareCode: json['shareCode']?.toString() ?? '',
      ownerId: json['ownerId']?.toString() ?? '',
      ownerEmail: json['ownerEmail']?.toString() ?? '',
      name: json['name']?.toString() ?? 'Untitled Playlist',
      description: json['description']?.toString() ?? '',
      authorName: json['authorName']?.toString() ?? 'Community Member',
      trackCount: json['trackCount'] is int
          ? json['trackCount'] as int
          : int.tryParse(json['trackCount']?.toString() ?? '0') ?? 0,
      isSyncEnabled: json['isSyncEnabled'] == true,
      sampleArtwork: json['sampleArtwork']?.toString() ?? '',
      updatedAt: json['updatedAt'] is int
          ? json['updatedAt'] as int
          : int.tryParse(json['updatedAt']?.toString() ?? '0') ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'syncId': syncId,
      'shareCode': shareCode,
      'ownerId': ownerId,
      'ownerEmail': ownerEmail,
      'name': name,
      'description': description,
      'authorName': authorName,
      'trackCount': trackCount,
      'isSyncEnabled': isSyncEnabled,
      'sampleArtwork': sampleArtwork,
      'updatedAt': updatedAt,
    };
  }
}

class MasterRegistryData {
  final List<PublicPlaylistSummary> playlists;
  final Map<String, String> codeIndex;

  MasterRegistryData({
    required this.playlists,
    required this.codeIndex,
  });
}

class PlaylistCloudSyncService {
  PlaylistCloudSyncService._();
  static final PlaylistCloudSyncService instance = PlaylistCloudSyncService._();

  static const String _apiBase = 'https://extendsclass.com/api/json-storage/bin';
  // Central master registry bin ID for public playlists feed & code index
  static const String _masterRegistryId = 'ceacbde';

  final Dio _dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'User-Agent': 'AuraMusic/4.0',
      },
    ),
  );

  /// Generates a human-friendly unique short code (e.g. AURA-7K9X2B)
  static String generateShareCode() {
    const chars = '23456789ABCDEFGHJKLMNPQRSTUVWXYZ';
    final rand = Random();
    final code = List.generate(6, (_) => chars[rand.nextInt(chars.length)]).join();
    return 'AURA-$code';
  }

  /// Creates a cloud sync slot for a collaborative or public playlist
  Future<String?> createCloudSyncSlot({
    required String localId,
    required String name,
    required String description,
    required String authorName,
    required bool isPublic,
    required bool isSyncEnabled,
    required List<Track> tracks,
    String? shareCode,
    String? ownerId,
    String? ownerEmail,
  }) async {
    try {
      final code = (shareCode != null && shareCode.isNotEmpty) ? shareCode : generateShareCode();
      final sampleArt = tracks.isNotEmpty ? tracks.first.artworkUrl : '';
      final payload = {
        'localId': localId,
        'name': name,
        'shareCode': code,
        'ownerId': ownerId ?? '',
        if (ownerEmail != null && ownerEmail.isNotEmpty) 'ownerEmail': ownerEmail,
        'description': description,
        'authorName': authorName,
        'isPublic': isPublic,
        'isSyncEnabled': isSyncEnabled,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

      final response = await _dio.post(
        _apiBase,
        data: jsonEncode(payload),
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if ((response.statusCode == 200 || response.statusCode == 201) && response.data != null) {
        final data = response.data is Map ? response.data : jsonDecode(response.data.toString());
        final syncId = data['id']?.toString();
        if (syncId != null && syncId.isNotEmpty) {
          debugPrint('[CloudSync] Created sync slot with ID: $syncId, code: $code');

          if (isPublic) {
            await publishToGlobalRegistry(
              PublicPlaylistSummary(
                id: localId,
                syncId: syncId,
                shareCode: code,
                ownerId: ownerId ?? '',
                ownerEmail: ownerEmail ?? '',
                name: name,
                description: description,
                authorName: authorName,
                trackCount: tracks.length,
                isSyncEnabled: isSyncEnabled,
                sampleArtwork: sampleArt,
                updatedAt: DateTime.now().millisecondsSinceEpoch,
              ),
            );
          }

          return syncId;
        }
      }
    } catch (e) {
      debugPrint('[CloudSync] Error creating sync slot: $e');
    }
    return null;
  }

  /// Updates an existing cloud slot with updated metadata and current tracks
  Future<bool> updateCloudSlot({
    required String syncId,
    required String name,
    required String description,
    required String authorName,
    required bool isPublic,
    required bool isSyncEnabled,
    required List<Track> tracks,
    String? shareCode,
    String? ownerId,
    String? ownerEmail,
  }) async {
    if (syncId.isEmpty) return false;
    try {
      final sampleArt = tracks.isNotEmpty ? tracks.first.artworkUrl : '';
      final payload = {
        'name': name,
        'description': description,
        'authorName': authorName,
        'isPublic': isPublic,
        'isSyncEnabled': isSyncEnabled,
        if (shareCode != null && shareCode.isNotEmpty) 'shareCode': shareCode,
        if (ownerId != null && ownerId.isNotEmpty) 'ownerId': ownerId,
        if (ownerEmail != null && ownerEmail.isNotEmpty) 'ownerEmail': ownerEmail,
        'updatedAt': DateTime.now().millisecondsSinceEpoch,
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

      final resp = await _dio.put(
        '$_apiBase/$syncId',
        data: jsonEncode(payload),
        options: Options(validateStatus: (s) => s != null && s < 500),
      );

      if (isPublic) {
        await publishToGlobalRegistry(
          PublicPlaylistSummary(
            id: syncId,
            syncId: syncId,
            shareCode: shareCode ?? '',
            ownerId: ownerId ?? '',
            ownerEmail: ownerEmail ?? '',
            name: name,
            description: description,
            authorName: authorName,
            trackCount: tracks.length,
            isSyncEnabled: isSyncEnabled,
            sampleArtwork: sampleArt,
            updatedAt: DateTime.now().millisecondsSinceEpoch,
          ),
        );
      } else {
        await removeFromGlobalRegistry(syncId);
      }

      return resp.statusCode == 200 || resp.statusCode == 201;
    } catch (e) {
      debugPrint('[CloudSync] Error updating cloud slot $syncId: $e');
      return false;
    }
  }

  /// Two-way sync: Pulls remote updates, merges with local tracks, and pushes merged results
  Future<SyncResult> syncPlaylist({
    required String syncId,
    required String currentAuthor,
    required List<Track> localTracks,
    required bool isSyncEnabled,
    String? playlistName,
    String? playlistDescription,
    String? shareCode,
    String? ownerId,
    String? ownerEmail,
  }) async {
    if (syncId.trim().isEmpty) {
      return SyncResult(
        success: false,
        addedCount: 0,
        newContributors: [],
        mergedTracks: localTracks,
        message: 'No cloud sync key attached to this playlist.',
      );
    }

    try {
      // 1. PULL remote version
      final getResp = await _dio.get(
        '$_apiBase/$syncId?t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );

      if (getResp.statusCode != 200 || getResp.data == null) {
        return SyncResult(
          success: false,
          addedCount: 0,
          newContributors: [],
          mergedTracks: localTracks,
          message: 'Could not connect to cloud playlist slot (${getResp.statusCode}).',
        );
      }

      final dynamic rawObj = getResp.data is Map ? getResp.data : jsonDecode(getResp.data.toString());
      final Map<String, dynamic> remoteData = rawObj is Map
          ? (rawObj.containsKey('data') && rawObj['data'] is Map
              ? Map<String, dynamic>.from(rawObj['data'] as Map)
              : Map<String, dynamic>.from(rawObj))
          : {};
      final List rawRemoteTracks = remoteData['tracks'] as List? ?? [];

      final List<Track> remoteTracks = [];
      for (final item in rawRemoteTracks) {
        if (item is Map) {
          remoteTracks.add(Track.fromJson(Map<String, dynamic>.from(item)));
        }
      }

      // 2. MERGE logic (deduplicate by track id)
      final Set<String> localTrackIds = localTracks.map((t) => t.id).toSet();
      final List<Track> merged = List<Track>.from(localTracks);
      final List<String> contributors = [];
      int newlyAddedFromRemote = 0;

      for (final rTrack in remoteTracks) {
        if (!localTrackIds.contains(rTrack.id)) {
          merged.add(rTrack);
          localTrackIds.add(rTrack.id);
          newlyAddedFromRemote++;

          final author = rTrack.addedBy ?? remoteData['authorName']?.toString();
          if (author != null && author.isNotEmpty && !contributors.contains(author)) {
            contributors.add(author);
          }
        }
      }

      // Check if local has new songs to push up to remote
      final Set<String> remoteTrackIds = remoteTracks.map((t) => t.id).toSet();
      bool hasLocalAdditions = false;
      for (final lTrack in localTracks) {
        if (!remoteTrackIds.contains(lTrack.id)) {
          hasLocalAdditions = true;
          break;
        }
      }

      // 3. PUSH merged state back to cloud if collaboration is enabled or local additions exist
      if (isSyncEnabled || hasLocalAdditions) {
        final sampleArt = merged.isNotEmpty ? merged.first.artworkUrl : '';
        final resolvedCode = (shareCode != null && shareCode.isNotEmpty)
            ? shareCode
            : remoteData['shareCode']?.toString() ?? '';
        final resolvedOwner = (ownerId != null && ownerId.isNotEmpty)
            ? ownerId
            : remoteData['ownerId']?.toString() ?? '';
        final resolvedOwnerEmail = (ownerEmail != null && ownerEmail.isNotEmpty)
            ? ownerEmail
            : remoteData['ownerEmail']?.toString() ?? '';

        final updatePayload = {
          'name': playlistName ?? remoteData['name'] ?? 'Collaborative Playlist',
          'description': playlistDescription ?? remoteData['description'] ?? '',
          'authorName': remoteData['authorName'] ?? currentAuthor,
          'isPublic': remoteData['isPublic'] ?? false,
          'isSyncEnabled': isSyncEnabled,
          'updatedAt': DateTime.now().millisecondsSinceEpoch,
          if (resolvedCode.isNotEmpty) 'shareCode': resolvedCode,
          if (resolvedOwner.isNotEmpty) 'ownerId': resolvedOwner,
          if (resolvedOwnerEmail.isNotEmpty) 'ownerEmail': resolvedOwnerEmail,
          'tracks': merged.map((t) {
            final json = t.toJson();
            if (json['extras'] == null) json['extras'] = {};
            final extras = json['extras'] as Map;
            if (extras['addedBy'] == null || extras['addedBy'].toString().isEmpty) {
              extras['addedBy'] = currentAuthor;
            }
            return json;
          }).toList(),
        };

        await _dio.put(
          '$_apiBase/$syncId',
          data: jsonEncode(updatePayload),
          options: Options(validateStatus: (s) => s != null && s < 600),
        );

        // Also update Master Registry if public
        if (remoteData['isPublic'] == true) {
          await publishToGlobalRegistry(
            PublicPlaylistSummary(
              id: remoteData['localId']?.toString() ?? syncId,
              syncId: syncId,
              shareCode: resolvedCode,
              ownerId: resolvedOwner,
              ownerEmail: resolvedOwnerEmail,
              name: playlistName ?? remoteData['name']?.toString() ?? 'Playlist',
              description: playlistDescription ?? remoteData['description']?.toString() ?? '',
              authorName: remoteData['authorName']?.toString() ?? currentAuthor,
              trackCount: merged.length,
              isSyncEnabled: isSyncEnabled,
              sampleArtwork: sampleArt,
              updatedAt: DateTime.now().millisecondsSinceEpoch,
            ),
          );
        }
      }

      String message;
      if (newlyAddedFromRemote > 0) {
        final contribText = contributors.isNotEmpty ? ' from ${contributors.join(', ')}' : '';
        message = 'Synced! +$newlyAddedFromRemote songs added$contribText.';
      } else if (hasLocalAdditions) {
        message = 'Synced! Your songs were pushed to the cloud.';
      } else {
        message = 'Playlist is fully up to date with cloud!';
      }

      return SyncResult(
        success: true,
        addedCount: newlyAddedFromRemote,
        newContributors: contributors,
        mergedTracks: merged,
        message: message,
      );
    } catch (e) {
      debugPrint('[CloudSync] Sync failed with error: $e');
      return SyncResult(
        success: false,
        addedCount: 0,
        newContributors: [],
        mergedTracks: localTracks,
        message: 'Sync error: $e',
      );
    }
  }

  /// Fetches the full track list of a cloud playlist by its syncId
  Future<List<Track>> fetchPlaylistTracksBySyncId(String syncId) async {
    try {
      final response = await _dio.get(
        '$_apiBase/$syncId?t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final dynamic rawObj = response.data is Map ? response.data : jsonDecode(response.data.toString());
        final Map<String, dynamic> data = rawObj is Map
            ? (rawObj.containsKey('data') && rawObj['data'] is Map
                ? Map<String, dynamic>.from(rawObj['data'] as Map)
                : Map<String, dynamic>.from(rawObj))
            : {};
        final List rawTracks = data['tracks'] as List? ?? [];

        final List<Track> tracks = [];
        for (final item in rawTracks) {
          if (item is Map) {
            tracks.add(Track.fromJson(Map<String, dynamic>.from(item)));
          }
        }
        return tracks;
      }
    } catch (e) {
      debugPrint('[CloudSync] Error fetching playlist tracks: $e');
    }
    return [];
  }

  /// Publishes or updates a playlist summary in the Master Global Registry
  Future<void> publishToGlobalRegistry(PublicPlaylistSummary summary) async {
    try {
      final masterData = await _fetchRawMasterData();
      final currentList = masterData.playlists;
      final codeIndex = Map<String, String>.from(masterData.codeIndex);

      final updatedList = currentList.where((p) => p.syncId != summary.syncId && p.id != summary.id).toList();
      updatedList.insert(0, summary);

      if (summary.shareCode.isNotEmpty) {
        codeIndex[summary.shareCode.toUpperCase()] = summary.syncId;
        // Also register without 'AURA-' prefix for easy searching
        final shortPart = summary.shareCode.toUpperCase().replaceAll('AURA-', '').trim();
        if (shortPart.isNotEmpty) {
          codeIndex[shortPart] = summary.syncId;
        }
      }

      // Keep most recent 50 public playlists
      if (updatedList.length > 50) {
        updatedList.removeRange(50, updatedList.length);
      }

      int retries = 0;
      while (retries < 3) {
        try {
          final res = await _dio.put(
            '$_apiBase/$_masterRegistryId',
            data: jsonEncode({
              'service': 'AURA_GLOBAL_PLAYLISTS_MASTER',
              'playlists': updatedList.map((p) => p.toJson()).toList(),
              'codeIndex': codeIndex,
              'lastUpdated': DateTime.now().millisecondsSinceEpoch,
            }),
            options: Options(validateStatus: (s) => s != null && s < 600),
          );
          if (res.statusCode == 200 || res.statusCode == 201) {
            debugPrint('[CloudSync] Published "${summary.name}" (Code: ${summary.shareCode}) to Global Registry');
            break;
          } else {
            debugPrint('[CloudSync] Put returned status: ${res.statusCode}, body: ${res.data}');
          }
        } catch (err) {
          debugPrint('[CloudSync] Put exception: $err');
        }
        retries++;
        await Future.delayed(const Duration(milliseconds: 300));
      }
    } catch (e) {
      debugPrint('[CloudSync] Error publishing to Global Registry: $e');
    }
  }

  /// Removes a playlist summary from the Master Global Registry (when made Private)
  Future<void> removeFromGlobalRegistry(String syncId) async {
    try {
      final masterData = await _fetchRawMasterData();
      final filteredList = masterData.playlists.where((p) => p.syncId != syncId).toList();

      await _dio.put(
        '$_apiBase/$_masterRegistryId',
        data: jsonEncode({
          'service': 'AURA_GLOBAL_PLAYLISTS_MASTER',
          'playlists': filteredList.map((p) => p.toJson()).toList(),
          'codeIndex': masterData.codeIndex,
          'lastUpdated': DateTime.now().millisecondsSinceEpoch,
        }),
        options: Options(validateStatus: (s) => s != null && s < 500),
      );
      debugPrint('[CloudSync] Removed playlist $syncId from Global Registry');
    } catch (e) {
      debugPrint('[CloudSync] Error removing from Global Registry: $e');
    }
  }

  /// Fetches playlist details and tracks directly by its unique shareCode (e.g. AURA-7K9X2B)
  Future<Map<String, dynamic>?> fetchPlaylistByShareCode(String inputCode) async {
    final cleanCode = inputCode.trim().toUpperCase();
    if (cleanCode.isEmpty) return null;

    final normalizedCode = cleanCode.startsWith('AURA-') ? cleanCode : 'AURA-$cleanCode';
    final bareCode = cleanCode.replaceAll('AURA-', '').trim();

    try {
      MasterRegistryData masterData = await _fetchRawMasterData();

      // 1. Direct index lookup
      String? syncId = masterData.codeIndex[normalizedCode] ??
          masterData.codeIndex[cleanCode] ??
          masterData.codeIndex[bareCode];

      // If not found immediately, retry once with short delay to account for edge propagation
      if (syncId == null || syncId.isEmpty) {
        await Future.delayed(const Duration(milliseconds: 400));
        masterData = await _fetchRawMasterData();
        syncId = masterData.codeIndex[normalizedCode] ??
            masterData.codeIndex[cleanCode] ??
            masterData.codeIndex[bareCode];
      }

      debugPrint('[CloudSync] Looked up code "$normalizedCode", resolved syncId: $syncId, known index size: ${masterData.codeIndex.length}');

      // 2. Fallback search through master playlists list
      if (syncId == null || syncId.isEmpty) {
        for (final p in masterData.playlists) {
          final pCode = p.shareCode.toUpperCase();
          if (pCode == normalizedCode || pCode == cleanCode || pCode.replaceAll('AURA-', '') == bareCode) {
            syncId = p.syncId;
            break;
          }
        }
      }

      // 3. Fallback: check if the user entered the direct cloud syncId (hex or UUID)
      if (syncId == null || syncId.isEmpty) {
        if (cleanCode.length >= 6 && !cleanCode.startsWith('AURA-')) {
          syncId = inputCode.trim();
        }
      }

      if (syncId != null && syncId.isNotEmpty) {
        final resp = await _dio.get(
          '$_apiBase/$syncId?t=${DateTime.now().millisecondsSinceEpoch}',
          options: Options(
            validateStatus: (s) => s != null && s < 500,
            headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
          ),
        );

        if (resp.statusCode == 200 && resp.data != null) {
          final dynamic rawObj = resp.data is Map ? resp.data : jsonDecode(resp.data.toString());
          final Map<String, dynamic> data = rawObj is Map
              ? (rawObj.containsKey('data') && rawObj['data'] is Map
                  ? Map<String, dynamic>.from(rawObj['data'] as Map)
                  : Map<String, dynamic>.from(rawObj))
              : {};
          final List rawTracks = data['tracks'] as List? ?? [];

          final List<Track> tracks = [];
          for (final item in rawTracks) {
            if (item is Map) {
              tracks.add(Track.fromJson(Map<String, dynamic>.from(item)));
            }
          }

          return {
            'syncId': syncId,
            'shareCode': data['shareCode']?.toString().isNotEmpty == true
                ? data['shareCode'].toString()
                : normalizedCode,
            'ownerId': data['ownerId']?.toString() ?? '',
            'ownerEmail': data['ownerEmail']?.toString() ?? '',
            'name': data['name']?.toString() ?? 'Shared Playlist',
            'description': data['description']?.toString() ?? '',
            'authorName': data['authorName']?.toString() ?? 'Community Member',
            'isPublic': data['isPublic'] == true,
            'isSyncEnabled': data['isSyncEnabled'] == true,
            'tracks': tracks,
          };
        }
      }
    } catch (e) {
      debugPrint('[CloudSync] Error fetching by shareCode $inputCode: $e');
    }
    return null;
  }

  /// Fetches all public playlists for the Global Playlists screen
  Future<List<PublicPlaylistSummary>> fetchGlobalPublicPlaylists() async {
    final masterData = await _fetchRawMasterData();
    final cloudList = masterData.playlists;
    final curatedList = _getCuratedSeedPlaylists();

    final Map<String, PublicPlaylistSummary> combined = {};
    // Key by syncId/id so playlists with the same name never overwrite each other!
    for (final p in cloudList) {
      final key = p.syncId.isNotEmpty ? p.syncId : p.id;
      if (key.isNotEmpty) {
        combined[key] = p;
      }
    }
    for (final p in curatedList) {
      final key = p.syncId.isNotEmpty ? p.syncId : p.id;
      if (!combined.containsKey(key)) {
        combined[key] = p;
      }
    }

    final result = combined.values.toList();
    result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return result;
  }

  Future<MasterRegistryData> _fetchRawMasterData() async {
    try {
      final response = await _dio.get(
        '$_apiBase/$_masterRegistryId?t=${DateTime.now().millisecondsSinceEpoch}',
        options: Options(
          validateStatus: (s) => s != null && s < 500,
          headers: {'Cache-Control': 'no-cache', 'Pragma': 'no-cache'},
        ),
      );

      if (response.statusCode == 200 && response.data != null) {
        final dynamic raw = response.data is Map ? response.data : jsonDecode(response.data.toString());
        final Map<String, dynamic> data = raw is Map
            ? (raw.containsKey('data') && raw['data'] is Map
                ? Map<String, dynamic>.from(raw['data'] as Map)
                : Map<String, dynamic>.from(raw))
            : {};
        final List rawPlaylists = data['playlists'] as List? ?? [];
        final Map<String, dynamic> rawCodeIndex = Map<String, dynamic>.from((data['codeIndex'] as Map?) ?? {});

        final playlists = rawPlaylists
            .whereType<Map>()
            .map((item) => PublicPlaylistSummary.fromJson(Map<String, dynamic>.from(item)))
            .toList();

        final codeIndex = rawCodeIndex.map((k, v) => MapEntry(k.toString().toUpperCase(), v.toString()));

        return MasterRegistryData(playlists: playlists, codeIndex: codeIndex);
      }
    } catch (e) {
      debugPrint('[CloudSync] Error fetching raw registry: $e');
    }
    return MasterRegistryData(playlists: [], codeIndex: {});
  }


  List<PublicPlaylistSummary> _getCuratedSeedPlaylists() {
    return [
      PublicPlaylistSummary(
        id: 'curated_1',
        syncId: 'seed_lofi',
        shareCode: 'AURA-LOFI99',
        ownerId: 'system_aura',
        ownerEmail: 'system@auramusic.app',
        name: 'Midnight Lo-Fi & Chill',
        description: 'Atmospheric lo-fi beats, warm vinyl crackles, and calming night vibes.',
        authorName: 'Aura Curation',
        trackCount: 16,
        isSyncEnabled: true,
        sampleArtwork: 'https://images.unsplash.com/photo-1518709268805-4e9042af9f23?w=500&q=80',
        updatedAt: DateTime.now().millisecondsSinceEpoch - 100000,
      ),
      PublicPlaylistSummary(
        id: 'curated_2',
        syncId: 'seed_workout',
        shareCode: 'AURA-GYM100',
        ownerId: 'system_aura',
        ownerEmail: 'system@auramusic.app',
        name: 'High Octane Gym Boost',
        description: 'Hard-hitting EDM, Phonk, and rap tracks built for intense lifting sessions.',
        authorName: 'Fitness Club',
        trackCount: 24,
        isSyncEnabled: false,
        sampleArtwork: 'https://images.unsplash.com/photo-1517838277536-f5f99be501cd?w=500&q=80',
        updatedAt: DateTime.now().millisecondsSinceEpoch - 250000,
      ),
      PublicPlaylistSummary(
        id: 'curated_3',
        syncId: 'seed_bollywood',
        shareCode: 'AURA-DESI55',
        ownerId: 'system_aura',
        ownerEmail: 'system@auramusic.app',
        name: 'Bollywood Trending Hits',
        description: 'The biggest chart-topping romantic and dance tracks straight from Mumbai.',
        authorName: 'Desi Beats',
        trackCount: 30,
        isSyncEnabled: true,
        sampleArtwork: 'https://images.unsplash.com/photo-1470225620780-dba8ba36b745?w=500&q=80',
        updatedAt: DateTime.now().millisecondsSinceEpoch - 400000,
      ),
      PublicPlaylistSummary(
        id: 'curated_4',
        syncId: 'seed_acoustic',
        shareCode: 'AURA-ACOUST',
        ownerId: 'system_aura',
        ownerEmail: 'system@auramusic.app',
        name: 'Acoustic Coffeehouse',
        description: 'Intimate fingerstyle guitars, stripped-down vocals, and cozy afternoon melodies.',
        authorName: 'Aura Acoustic',
        trackCount: 18,
        isSyncEnabled: false,
        sampleArtwork: 'https://images.unsplash.com/photo-1511671782779-c97d3d27a1d4?w=500&q=80',
        updatedAt: DateTime.now().millisecondsSinceEpoch - 600000,
      ),
    ];
  }
}
