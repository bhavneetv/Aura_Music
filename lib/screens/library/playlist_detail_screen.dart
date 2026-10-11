import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../widgets/app_artwork_image.dart';
import '../sharing/remote_link_share_modal.dart';
import 'package:flutter/services.dart';
import '../../services/auth/auth_service.dart';
import '../../widgets/playlist_settings_dialog.dart';
import '../../widgets/auth_dialog.dart';
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../services/playlist/playlist_repository.dart';
import 'package:connectivity_plus/connectivity_plus.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistIndex;
  final Map<String, dynamic>? initialPlaylist;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistIndex,
    this.initialPlaylist,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  Map<String, dynamic> _playlist = {};
  List<Track> _playlistTracks = [];
  String _searchQuery = '';
  bool _isDownloadingPlaylist = false;
  double _downloadProgress = 0.0;
  bool _isPlaylistDownloaded = false;
  bool _isSyncing = false;

  @override
  void initState() {
    super.initState();
    _loadPlaylistData();
  }

  void _loadPlaylistData() {
    final playlists = StorageService.getPlaylists();
    Map<String, dynamic>? target;

    final targetId = _playlist['id']?.toString() ?? widget.initialPlaylist?['id']?.toString();
    if (targetId != null && targetId.isNotEmpty) {
      for (final p in playlists) {
        if (p['id']?.toString() == targetId) {
          target = p;
          break;
        }
      }
    }

    if (target == null && widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      target = playlists[widget.playlistIndex];
    }

    target ??= widget.initialPlaylist;

    if (target != null) {
      _playlist = Map<String, dynamic>.from(target);
    } else if (playlists.isNotEmpty) {
      _playlist = Map<String, dynamic>.from(playlists.first);
    } else {
      _playlist = {
        'id': 'temp_${DateTime.now().millisecondsSinceEpoch}',
        'name': 'Custom Playlist',
        'description': '',
        'tracks': [],
        'trackIds': [],
      };
    }

    final bool isImported = _playlist['isImported'] == true;

    // Only update ownership info if this is NOT an imported/collaborative playlist
    if (AuthService.instance.isLoggedIn && !isImported) {
      final currentUserId = AuthService.instance.currentUserId;
      final currentUserEmail = (AuthService.instance.currentUserEmail ?? '').trim().toLowerCase();
      final pOwnerId = _playlist['ownerId']?.toString();
      final pOwnerEmail = (_playlist['ownerEmail']?.toString() ?? '').trim().toLowerCase();
      if ((pOwnerId != null && pOwnerId == currentUserId) ||
          (pOwnerEmail.isNotEmpty && pOwnerEmail == currentUserEmail)) {
        _playlist['ownerId'] = currentUserId;
        _playlist['ownerEmail'] = AuthService.instance.currentUserEmail;
      }
    }

    if (_playlist['ownerId'] == null || _playlist['ownerId'].toString().isEmpty) {
      if (!isImported) {
        _playlist['ownerId'] = AuthService.instance.currentUserId;
        _playlist['ownerName'] = AuthService.instance.currentUserName;
        if (AuthService.instance.isLoggedIn) {
          _playlist['ownerEmail'] = AuthService.instance.currentUserEmail;
        }
      }
    }

    // Ensure syncedTrackIds baseline exists if this playlist has already been synced or imported
    if (_playlist['syncedTrackIds'] == null && _playlist['trackIds'] != null) {
      if (_playlist['isSyncEnabled'] == true || _playlist['isImported'] == true) {
        _playlist['syncedTrackIds'] = List<String>.from(_playlist['trackIds'] as List);
      }
    }

    // Lazily resolve share code from Firestore if missing
    final pid = _playlist['id']?.toString() ?? '';
    if ((_playlist['shareCode'] == null || _playlist['shareCode'].toString().isEmpty) && pid.isNotEmpty) {
      PlaylistRepository().getInviteCodeForPlaylist(pid).then((code) {
        if (code != null && code.isNotEmpty && mounted) {
          setState(() {
            _playlist['shareCode'] = code;
          });
        }
      }).catchError((_) {});
    }

    final List rawTracks = _playlist['tracks'] as List? ?? [];
    _playlistTracks = [];
    if (rawTracks.isNotEmpty) {
      for (final item in rawTracks) {
        if (item is Map) {
          _playlistTracks.add(Track.fromJson(Map<String, dynamic>.from(item)));
        }
      }
    } else {
      final List rawIds = _playlist['trackIds'] as List? ?? [];
      for (final id in rawIds) {
        final track = Track.mockTracks.firstWhere(
          (t) => t.id == id.toString(),
          orElse: () => Track(
            id: id.toString(),
            title: 'Track $id',
            artist: 'Unknown Artist',
            album: 'Unknown Album',
            duration: '3:00',
            artworkUrl: '',
            audioUrl: '',
            genre: '',
          ),
        );
        _playlistTracks.add(track);
      }
    }
  }

  Future<void> _persistPlaylist(Map<String, dynamic> updated) async {
    final playlists = StorageService.getPlaylists();
    final targetId = updated['id']?.toString();
    bool replaced = false;

    if (targetId != null && targetId.isNotEmpty) {
      for (int i = 0; i < playlists.length; i++) {
        if (playlists[i]['id']?.toString() == targetId) {
          playlists[i] = updated;
          replaced = true;
          break;
        }
      }
    }

    if (!replaced && widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      playlists[widget.playlistIndex] = updated;
      replaced = true;
    }

    if (!replaced) {
      playlists.add(updated);
    }

    await StorageService.savePlaylists(playlists);

    // Sync to Cloud Firestore if authenticated
    if (AuthService.instance.isLoggedIn && targetId != null && targetId.isNotEmpty) {
      try {
        final repo = PlaylistRepository();
        final isOwner = AuthService.instance.isPlaylistOwner(updated);
        final isPublic = updated['isPublic'] == true;
        final isCollab = updated['isSyncEnabled'] == true;
        final ownerId = updated['ownerId']?.toString() ?? AuthService.instance.currentUserId;
        final authorName = updated['authorName']?.toString() ?? updated['ownerName']?.toString() ?? AuthService.instance.currentUserName;

        final playlistTracks = _playlistTracks.map((t) => PlaylistTrack.fromTrack(
          t,
          addedByUid: (t.addedBy != null && t.addedBy!.isNotEmpty && t.addedBy != authorName)
              ? ''
              : (ownerId.isNotEmpty ? ownerId : AuthService.instance.currentUserId),
          addedByName: (t.addedBy != null && t.addedBy!.isNotEmpty) ? t.addedBy! : authorName,
        )).toList();

        // Only owner should overwrite full playlist metadata doc
        if (isOwner) {
          final existing = await repo.getPlaylist(targetId);
          final pl = Playlist(
            id: targetId,
            name: updated['name']?.toString() ?? 'My Playlist',
            description: updated['description']?.toString() ?? '',
            ownerUid: ownerId.isNotEmpty ? ownerId : AuthService.instance.currentUserId,
            ownerName: authorName,
            memberUids: existing?.memberUids.isNotEmpty == true ? existing!.memberUids : [ownerId.isNotEmpty ? ownerId : AuthService.instance.currentUserId],
            visibility: isPublic ? 'public' : 'private',
            collabEnabled: isCollab,
            createdAt: existing?.createdAt ?? DateTime.now(),
            updatedAt: DateTime.now(),
            trackCount: playlistTracks.length,
            tracks: playlistTracks,
            shareCode: updated['shareCode']?.toString() ?? existing?.shareCode,
          );

          await repo.saveOrUpdatePlaylist(pl);
        }
      } catch (e) {
        debugPrint('Firestore _persistPlaylist error: $e');
      }
    }
  }

  void _downloadPlaylist(Color accentColor) async {
    if (_playlistTracks.isEmpty || _isDownloadingPlaylist) return;
    setState(() {
      _isDownloadingPlaylist = true;
      _downloadProgress = 0.0;
    });

    await DownloadService.instance.downloadPlaylist(
      _playlistTracks,
      onProgress: (completed, total) {
        if (mounted) {
          setState(() {
            _downloadProgress = total > 0 ? (completed / total).clamp(0.0, 1.0) : 0.0;
          });
        }
      },
    );

    await StorageService.registerDownloadedPlaylist(
      _playlist['name'] ?? 'Custom Playlist',
      _playlist['description'] ?? '',
      _playlistTracks,
    );

    if (mounted) {
      setState(() {
        _isDownloadingPlaylist = false;
        _isPlaylistDownloaded = true;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Downloaded all ${_playlistTracks.length} songs for offline listening! ⚡'),
          backgroundColor: accentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _addSongToPlaylist(Track track) async {
    final callerName = AuthService.instance.currentUserName.isNotEmpty
        ? AuthService.instance.currentUserName
        : StorageService.getUserAuthorName();
    final callerUid = AuthService.instance.currentUserId;

    // Stamp the track with whoever added it so it reflects the collaborator or owner!
    final stampedTrack = track.copyWith(
      addedBy: (track.addedBy != null && track.addedBy!.trim().isNotEmpty)
          ? track.addedBy!.trim()
          : callerName,
    );

    final List rawTracks = List.from(_playlist['tracks'] as List? ?? []);
    final trackMap = stampedTrack.toJson();
    trackMap['addedBy'] = stampedTrack.addedBy;
    trackMap['addedByUid'] = callerUid;

    if (!rawTracks.any((t) => t is Map && t['id'] == stampedTrack.id)) {
      rawTracks.add(trackMap);
      _playlist['tracks'] = rawTracks;
      _playlist['trackIds'] = rawTracks.map((t) => t['id']?.toString()).whereType<String>().toList();
      await _persistPlaylist(_playlist);
      setState(() {
        _loadPlaylistData();
      });

      // Sync to Firestore if collab sync is active
      if (_playlist['isSyncEnabled'] == true && AuthService.instance.isLoggedIn) {
        final pid = _playlist['id']?.toString() ?? '';
        if (pid.isNotEmpty && callerUid.isNotEmpty) {
          PlaylistRepository().syncPlaylistTracks(
            playlistId: pid,
            callerUid: callerUid,
            callerName: callerName,
            localTracks: _playlistTracks,
            deletedTrackIds: List<String>.from(_playlist['deletedTrackIds'] as List? ?? []),
            baseTrackIds: List<String>.from(_playlist['syncedTrackIds'] as List? ?? []),
          ).then((syncedTracks) {
            if (syncedTracks.isNotEmpty && mounted) {
              setState(() {
                _playlistTracks = syncedTracks;
                _playlist['tracks'] = syncedTracks.map((t) => t.toJson()).toList();
                _playlist['trackIds'] = syncedTracks.map((t) => t.id).toList();
                _playlist['syncedTrackIds'] = syncedTracks.map((t) => t.id).toList();
              });
              _persistPlaylist(_playlist);
            }
          }).catchError((e) {
            debugPrint('Firestore auto sync notice: $e');
          });
        }
      }
    }
  }

  void _removeSongFromPlaylist(int index) async {
    final List rawTracks = List.from(_playlist['tracks'] as List? ?? []);
    if (index >= 0 && index < rawTracks.length) {
      final removedItem = rawTracks.removeAt(index);
      final removedTrackId = (removedItem is Map ? removedItem['id'] : null)?.toString() ??
          (index < _playlistTracks.length ? _playlistTracks[index].id : '');

      _playlist['tracks'] = rawTracks;
      _playlist['trackIds'] = rawTracks.map((t) => t['id']?.toString()).whereType<String>().toList();

      // Track deleted ID so sync does not resurrect it
      final deletedIds = List<String>.from(_playlist['deletedTrackIds'] as List? ?? []);
      if (removedTrackId.isNotEmpty && !deletedIds.contains(removedTrackId)) {
        deletedIds.add(removedTrackId);
        _playlist['deletedTrackIds'] = deletedIds;
      }

      await _persistPlaylist(_playlist);
      setState(() {
        _loadPlaylistData();
      });

      // Remove from Firestore if authenticated
      if (AuthService.instance.isLoggedIn) {
        final pid = _playlist['id']?.toString() ?? '';
        final uid = AuthService.instance.currentUserId;
        if (pid.isNotEmpty && uid.isNotEmpty && removedTrackId.isNotEmpty) {
          PlaylistRepository().removeTrack(pid, removedTrackId, uid).catchError((e) {
            debugPrint('Firestore removeTrack notice: $e');
          });
        }
      }
    }
  }

  void _reorderPlaylistSongs(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final List rawTracks = List.from(_playlist['tracks'] as List? ?? []);
    if (oldIndex >= 0 && oldIndex < rawTracks.length) {
      final item = rawTracks.removeAt(oldIndex);
      rawTracks.insert(newIndex, item);
      _playlist['tracks'] = rawTracks;
      _playlist['trackIds'] = rawTracks.map((t) => t['id']?.toString()).whereType<String>().toList();
      await _persistPlaylist(_playlist);
      setState(() {
        _loadPlaylistData();
      });
    }
  }

  void _showAddSongsBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(28))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text('Add Songs to Playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: Track.mockTracks.length,
                  itemBuilder: (context, index) {
                    final track = Track.mockTracks[index];
                    return ListTile(
                      leading: AppArtworkImage(
                        artworkUrl: track.artworkUrl,
                        trackId: track.id,
                        width: 44,
                        height: 44,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      subtitle: Text(track.artist, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      trailing: const Icon(Icons.add_circle_outline_rounded, color: Colors.grey),
                      onTap: () {
                        _addSongToPlaylist(track);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showDeletePlaylistDialog(Color accentColor) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Playlist?', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          content: Text('Are you sure you want to delete "${_playlist['name']}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx, false),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () => Navigator.pop(dialogCtx, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed == true && mounted) {
      final pId = _playlist['id']?.toString();
      final playlists = StorageService.getPlaylists();
      if (pId != null && pId.isNotEmpty) {
        playlists.removeWhere((p) => p['id']?.toString() == pId);
        await StorageService.savePlaylists(playlists);
      } else if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
        playlists.removeAt(widget.playlistIndex);
        await StorageService.savePlaylists(playlists);
      }

      AuthService.instance.playlistsChangedNotifier.value++;

      if (pId != null && pId.isNotEmpty && AuthService.instance.isLoggedIn) {
        try {
          if (AuthService.instance.isPlaylistOwner(_playlist)) {
            await PlaylistRepository().deletePlaylist(pId, AuthService.instance.currentUserId);
          } else {
            await PlaylistRepository().leavePlaylist(pId, AuthService.instance.currentUserId);
          }
        } catch (e) {
          debugPrint('Remote delete/leave playlist error: $e');
        }
      }

      if (mounted && Navigator.canPop(context)) {
        Navigator.pop(context);
      }
    }
  }

  Future<void> _performPlaylistSync(Color accentColor) async {
    // 0. Connectivity check: verify internet access
    final connResults = await Connectivity().checkConnectivity();
    final isOffline = connResults.contains(ConnectivityResult.none) || connResults.isEmpty;
    if (isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Row(
              children: [
                Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'You are offline. Please connect to the internet to sync songs.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
      return;
    }

    // 1. Auth check: user needs to be logged in to participate in cloud sync
    if (!AuthService.instance.isLoggedIn) {
      final loggedIn = await AuthModalDialog.show(
        context,
        featurePrompt: 'Please sign in or create an account to sync songs with other devices!',
      );
      if (!loggedIn) return;
    }

    final currentUserId = AuthService.instance.currentUserId;
    final currentAuthor = AuthService.instance.currentUserName.isNotEmpty
        ? AuthService.instance.currentUserName
        : StorageService.getUserAuthorName();
    final playlistId = _playlist['id']?.toString() ?? '';
    final isOwner = AuthService.instance.isPlaylistOwner(_playlist);

    if (playlistId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid playlist ID.'), behavior: SnackBarBehavior.floating),
      );
      return;
    }

    setState(() => _isSyncing = true);

    try {
      final repo = PlaylistRepository();

      // 1. Fetch remote playlist document to check live cloud collaboration state
      final remotePl = await repo.getPlaylist(playlistId);

      // If owner and not yet created on cloud, initialize in Firestore
      if (isOwner && remotePl == null) {
        final ptTracks = _playlistTracks
            .map((t) => PlaylistTrack.fromTrack(
                  t,
                  addedByUid: currentUserId,
                  addedByName: (t.addedBy != null && t.addedBy!.isNotEmpty) ? t.addedBy! : currentAuthor,
                ))
            .toList();
        final created = await repo.createPlaylist(
          id: playlistId,
          name: _playlist['name']?.toString() ?? 'Playlist',
          description: _playlist['description']?.toString() ?? '',
          ownerUid: currentUserId,
          ownerName: currentAuthor,
          visibility: _playlist['isPublic'] == true ? 'public' : 'private',
          collabEnabled: _playlist['isSyncEnabled'] == true,
          initialTracks: ptTracks,
          shareCode: _playlist['shareCode']?.toString(),
        );
        _playlist['shareCode'] = created.shareCode ?? await repo.enableCollaboration(playlistId, currentUserId);
      }

      // Check remote permission status
      if (remotePl != null) {
        // Sync shareCode if missing locally
        if ((_playlist['shareCode'] == null || _playlist['shareCode'].toString().isEmpty) &&
            remotePl.shareCode != null && remotePl.shareCode!.isNotEmpty) {
          _playlist['shareCode'] = remotePl.shareCode;
        }

        // If collaborator device and collaboration is disabled on the remote playlist
        if (!isOwner && !remotePl.collabEnabled) {
          _playlist['isSyncEnabled'] = false;
          await StorageService.updatePlaylist(playlistId, _playlist);
          if (mounted) {
            setState(() => _isSyncing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Row(
                  children: [
                    Icon(Icons.lock_outline_rounded, color: Colors.white, size: 20),
                    SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Sync not allowed: The owner has disabled collaboration for this playlist (Read-Only Mode).',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                      ),
                    ),
                  ],
                ),
                backgroundColor: Colors.orangeAccent.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
              ),
            );
          }
          return;
        }

        // If owner has collab turned off and tries to sync, warn owner
        if (isOwner && !remotePl.collabEnabled && _playlist['isSyncEnabled'] != true) {
          if (mounted) {
            setState(() => _isSyncing = false);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  'Collaborative sync is disabled for this playlist. Turn on "Allow Collaboration & Sync" in Settings (⚙️) to sync songs.',
                ),
                backgroundColor: Colors.orangeAccent.shade700,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 4),
                action: SnackBarAction(
                  label: 'SETTINGS',
                  textColor: Colors.white,
                  onPressed: () {
                    PlaylistSettingsModal.show(
                      context,
                      playlist: _playlist,
                      tracks: _playlistTracks,
                      onUpdated: (updated) {
                        setState(() {
                          _playlist = updated;
                          _loadPlaylistData();
                        });
                      },
                    );
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      // 2. Perform atomic two-way sync with Firestore
      final deletedIds = List<String>.from(_playlist['deletedTrackIds'] as List? ?? []);
      final baseIds = List<String>.from(_playlist['syncedTrackIds'] as List? ?? []);
      final mergedTracks = await repo.syncPlaylistTracks(
        playlistId: playlistId,
        callerUid: currentUserId,
        callerName: currentAuthor,
        localTracks: _playlistTracks,
        deletedTrackIds: deletedIds,
        baseTrackIds: baseIds,
      );

      _playlistTracks = mergedTracks;
      _playlist['tracks'] = mergedTracks.map((t) => t.toJson()).toList();
      _playlist['trackIds'] = mergedTracks.map((t) => t.id).toList();
      _playlist['syncedTrackIds'] = mergedTracks.map((t) => t.id).toList();
      _playlist['deletedTrackIds'] = <String>[];
      if (remotePl != null) {
        _playlist['isSyncEnabled'] = remotePl.collabEnabled;
      }

      await StorageService.updatePlaylist(playlistId, _playlist);

      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.cloud_done_rounded, color: Colors.black, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Playlist synced with cloud! (${mergedTracks.length} songs total) ☁️',
                    style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ),
              ],
            ),
            backgroundColor: accentColor,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSyncing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Sync notice: $e'), behavior: SnackBarBehavior.floating),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;
    final playbackNotifier = ref.read(playbackProvider.notifier);

    final filteredTracks = _playlistTracks.where((track) {
      final query = _searchQuery.toLowerCase();
      return track.title.toLowerCase().contains(query) ||
             track.artist.toLowerCase().contains(query);
    }).toList();

    final firstTrack = _playlistTracks.isNotEmpty ? _playlistTracks.first : null;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _playlist['name'] ?? 'Playlist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit'),
        ),
        actions: [
          // 1. Dedicated Playlist Collaborative Sync Button (🔄) - Always enabled / clickable
          IconButton(
            icon: _isSyncing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                  )
                : Icon(
                    Icons.sync_rounded,
                    color: accentColor,
                  ),
            tooltip: 'Sync Playlist Songs 🔄',
            onPressed: _isSyncing ? null : () => _performPlaylistSync(accentColor),
          ),

          // 2. Add Songs Button
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add Songs',
            onPressed: _showAddSongsBottomSheet,
          ),

          // 3. Playlist Settings Button (⚙️)
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Playlist Settings',
            onPressed: () async {
              final connResults = await Connectivity().checkConnectivity();
              final isOffline = connResults.contains(ConnectivityResult.none) || connResults.isEmpty;
              if (isOffline) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: const Row(
                        children: [
                          Icon(Icons.wifi_off_rounded, color: Colors.white, size: 20),
                          SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'You are offline. Playlist cloud settings require an internet connection.',
                              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                            ),
                          ),
                        ],
                      ),
                      backgroundColor: Colors.redAccent.shade700,
                      behavior: SnackBarBehavior.floating,
                      duration: const Duration(seconds: 3),
                    ),
                  );
                }
                return;
              }

              if (!mounted) return;
              PlaylistSettingsModal.show(
                context,
                playlist: _playlist,
                tracks: _playlistTracks,
                onUpdated: (updated) {
                  setState(() {
                    _playlist = updated;
                    _loadPlaylistData();
                  });
                },
              );
            },
          ),

          // 4. Overflow Safe More Options Menu (Download, Share, Delete)
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            onSelected: (val) {
              if (val == 'download') {
                _downloadPlaylist(accentColor);
              } else if (val == 'share') {
                ShareOptionsModal.show(
                  context,
                  tracks: _playlistTracks,
                  title: _playlist['name']?.toString() ?? 'Custom Playlist',
                  description: _playlist['description']?.toString() ?? '',
                );
              } else if (val == 'delete') {
                _showDeletePlaylistDialog(accentColor);
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(
                      _isPlaylistDownloaded ? Icons.check_circle_rounded : Icons.download_for_offline_rounded,
                      size: 20,
                      color: _isPlaylistDownloaded ? Colors.greenAccent : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isDownloadingPlaylist
                          ? 'Downloading (${(_downloadProgress * 100).toInt()}%)...'
                          : (_isPlaylistDownloaded ? 'Downloaded ✓' : 'Download All'),
                    ),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'share',
                child: Row(
                  children: const [
                    Icon(Icons.share_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Share Playlist'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: const [
                    Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Delete Playlist', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          // Dynamic Hero Header Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: isDark
                    ? [accentColor.withValues(alpha: 0.25), const Color(0xFF1E1E22)]
                    : [accentColor.withValues(alpha: 0.15), Colors.white],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 12, offset: const Offset(0, 4))
              ],
            ),
            child: Row(
              children: [
                firstTrack != null && firstTrack.artworkUrl.isNotEmpty
                    ? AppArtworkImage(
                        artworkUrl: firstTrack.artworkUrl,
                        trackId: firstTrack.id,
                        width: 90,
                        height: 90,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(18),
                      )
                    : Container(
                        width: 90,
                        height: 90,
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 48),
                      ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playlist['name'] ?? 'Custom Playlist',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Created by ${_playlist['authorName'] ?? 'Me'} • ${_playlist['description'] ?? 'Personalized collection'}',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          // Unique Share Code Pill
                          GestureDetector(
                            onTap: () {
                              final code = _playlist['shareCode']?.toString() ?? '';
                              if (code.isNotEmpty) {
                                Clipboard.setData(ClipboardData(text: code));
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Copied Playlist Code "$code" to clipboard! 📋'),
                                    behavior: SnackBarBehavior.floating,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                            },
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.tag_rounded, size: 11, color: accentColor),
                                  const SizedBox(width: 3),
                                  Text(
                                    _playlist['shareCode']?.toString() ?? 'CODE',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: accentColor),
                                  ),
                                  const SizedBox(width: 4),
                                  Icon(Icons.copy_rounded, size: 9, color: accentColor),
                                ],
                              ),
                            ),
                          ),

                          // Owner Status Pill
                          Builder(
                            builder: (context) {
                              final isOwner = AuthService.instance.isPlaylistOwner(_playlist);
                              final ownerName = _playlist['authorName']?.toString() ?? 'Creator';
                              return Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                decoration: BoxDecoration(
                                  color: isOwner
                                      ? Colors.purpleAccent.withValues(alpha: 0.15)
                                      : Colors.amber.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: isOwner
                                        ? Colors.purpleAccent.withValues(alpha: 0.3)
                                        : Colors.amber.withValues(alpha: 0.3),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      isOwner ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
                                      size: 11,
                                      color: isOwner ? Colors.purpleAccent : Colors.amber,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      isOwner ? '👑 You (Owner)' : '👤 $ownerName',
                                      style: TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 10.5,
                                        color: isOwner ? Colors.purpleAccent : Colors.amber,
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            },
                          ),

                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
                            decoration: BoxDecoration(
                              color: accentColor.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              '${_playlistTracks.length} Songs',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: accentColor),
                            ),
                          ),
                          if (_playlist['isPublic'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.blueAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.blueAccent.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.public_rounded, size: 11, color: Colors.blueAccent),
                                  SizedBox(width: 4),
                                  Text(
                                    'Public',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.blueAccent),
                                  ),
                                ],
                              ),
                            ),
                          if (_playlist['isSyncEnabled'] == true)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.greenAccent.withValues(alpha: 0.3)),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.sync_rounded, size: 11, color: Colors.greenAccent),
                                  SizedBox(width: 4),
                                  Text(
                                    'Sync Ready',
                                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 10.5, color: Colors.greenAccent),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // In-playlist Search Box
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Filter songs in playlist...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
                filled: true,
                fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Action Buttons: Play All & Shuffle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_playlistTracks.isNotEmpty) {
                        playbackNotifier.playCustomQueue(_playlistTracks, initialIndex: 0);
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                    label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      if (_playlistTracks.isNotEmpty) {
                        final shuffled = List<Track>.from(_playlistTracks)..shuffle();
                        playbackNotifier.playCustomQueue(shuffled, initialIndex: 0);
                      }
                    },
                    icon: const Icon(Icons.shuffle_rounded),
                    label: const Text('Shuffle'),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(color: accentColor),
                      foregroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Reorderable Track List
          Expanded(
            child: filteredTracks.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No songs in this playlist yet.' : 'No matching songs found.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    padding: const EdgeInsets.only(bottom: 120),
                    itemCount: filteredTracks.length,
                    onReorder: _reorderPlaylistSongs,
                    itemBuilder: (context, index) {
                      final track = filteredTracks[index];
                      return KeyedSubtree(
                        key: ValueKey('pl_track_${track.id}_$index'),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle_rounded, color: Colors.grey, size: 18),
                              const SizedBox(width: 8),
                              AppArtworkImage(
                                artworkUrl: track.artworkUrl,
                                trackId: track.id,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(8),
                              ),
                            ],
                          ),
                          title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                margin: const EdgeInsets.only(right: 6),
                                decoration: BoxDecoration(
                                  color: track.isYouTube
                                      ? Colors.red.withValues(alpha: 0.15)
                                      : const Color(0xFF00D1B2).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(
                                    color: track.isYouTube
                                        ? Colors.red.withValues(alpha: 0.5)
                                        : const Color(0xFF00D1B2).withValues(alpha: 0.5),
                                    width: 0.5,
                                  ),
                                ),
                                child: Text(
                                  track.isYouTube ? 'YT' : 'Saavn',
                                  style: TextStyle(
                                    color: track.isYouTube ? Colors.redAccent : const Color(0xFF00D1B2),
                                    fontSize: 9.5,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                              ),
                              if (track.addedBy != null && track.addedBy!.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1.5),
                                  decoration: BoxDecoration(
                                    color: accentColor.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: ConstrainedBox(
                                    constraints: const BoxConstraints(maxWidth: 90),
                                    child: Text(
                                      '👤 ${track.addedBy}',
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(fontSize: 9.5, color: accentColor, fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 28),
                                onPressed: () => playbackNotifier.playTrack(track),
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.grey),
                                onPressed: () => _removeSongFromPlaylist(index),
                              ),
                            ],
                          ),
                          onTap: () {
                            playbackNotifier.playTrack(track);
                          },
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
