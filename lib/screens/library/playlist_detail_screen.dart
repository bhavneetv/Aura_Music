import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
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
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../services/playlist/playlist_repository.dart';
import '../../services/network/app_connectivity.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Playlist page
//
//   App bar     back · name · sync · settings · more
//   Header      cover, name, owner, share code and status chips
//   Actions     Play all · Shuffle · add songs
//   Songs       search + reorderable cards
//
// Everything below the app bar scrolls together, so the header no longer
// takes a fixed half of small screens. On wide screens the header becomes a
// side panel next to the songs.
//
// Loading, saving, syncing, downloading and deleting are the original
// methods, unchanged. Only the interface was rebuilt.
// ─────────────────────────────────────────────────────────────────────────────

enum PlaylistSortOption {
  custom('Custom Order', Icons.drag_handle_rounded),
  newest('Recently Added', Icons.fiber_new_rounded),
  oldest('First Added', Icons.history_rounded),
  titleAZ('Title (A to Z)', Icons.sort_by_alpha_rounded),
  titleZA('Title (Z to A)', Icons.sort_by_alpha_rounded),
  artistAZ('Artist (A to Z)', Icons.person_outline_rounded),
  duration('Duration (Longest)', Icons.timer_outlined);

  final String label;
  final IconData icon;
  const PlaylistSortOption(this.label, this.icon);
}

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
  /// From this width up, the header sits beside the song list.
  static const double _wideBreakpoint = 720;

  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 1040;

  /// Vertical gap between two song cards.
  static const double _rowGap = 8;

  Map<String, dynamic> _playlist = {};
  List<Track> _playlistTracks = [];
  String _searchQuery = '';
  PlaylistSortOption _sortOption = PlaylistSortOption.custom;
  bool _isDownloadingPlaylist = false;
  double _downloadProgress = 0.0;
  bool _isPlaylistDownloaded = false;
  bool _isSyncing = false;
  String? _loadingTrackId;
  Timer? _loadingTimeoutTimer;

  final TextEditingController _searchController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  // Drag tracking, used only to time the haptic ticks.
  bool _dragging = false;
  int _dragSlot = -1;
  double _pointerY = 0;

  // Layout values from the latest build, read by the drag callbacks.
  double _rowExtent = 76;
  double _listSidePadding = 20;
  int _rowCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_tickIfSlotChanged);
    _loadPlaylistData();
  }

  @override
  void dispose() {
    _loadingTimeoutTimer?.cancel();
    _searchController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _setLoadingTrack(String trackId) {
    _loadingTimeoutTimer?.cancel();
    setState(() {
      _loadingTrackId = trackId;
    });
    _loadingTimeoutTimer = Timer(const Duration(seconds: 15), () {
      if (mounted && _loadingTrackId != null) {
        setState(() => _loadingTrackId = null);
      }
    });
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // DATA (original, unchanged)
  // ═══════════════════════════════════════════════════════════════════════════

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
        if (code != null && code.isNotEmpty && mounted && _playlist['shareCode'] != code) {
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

    _isPlaylistDownloaded = _playlistTracks.isNotEmpty &&
        _playlistTracks.every((t) => DownloadService.instance.isDownloaded(t.id));
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

  Future<void> _addSongToPlaylist(Track track) async {
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

      // Sync to Firestore if collab sync is active (guests can contribute too)
      if (_playlist['isSyncEnabled'] == true) {
        if (!AuthService.instance.isLoggedIn) {
          AuthService.instance.ensureAnonymousSession();
        }
        final pid = _playlist['id']?.toString() ?? '';
        final syncUid = callerUid.isNotEmpty
            ? callerUid
            : (AuthService.instance.currentUserId.isNotEmpty
                ? AuthService.instance.currentUserId
                : StorageService.getDeviceId());
        if (pid.isNotEmpty) {
          PlaylistRepository().syncPlaylistTracks(
            playlistId: pid,
            callerUid: syncUid,
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

      // Remove from Firestore if collaborative sync is active (guests can contribute too)
      if (_playlist['isSyncEnabled'] == true) {
        () async {
          if (!AuthService.instance.isLoggedIn) {
            await AuthService.instance.ensureAnonymousSession();
          }
          final pid = _playlist['id']?.toString() ?? '';
          final uid = AuthService.instance.currentUserId.isNotEmpty
              ? AuthService.instance.currentUserId
              : StorageService.getDeviceId();
          if (pid.isNotEmpty && uid.isNotEmpty && removedTrackId.isNotEmpty) {
            PlaylistRepository().removeTrack(pid, removedTrackId, uid).catchError((e) {
              debugPrint('Firestore removeTrack notice: $e');
            });
          }
        }();
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
    final isOffline = await AppConnectivity.isOffline();
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

    // 1. Auth check: ensure an active Firebase session exists.
    // Guests CAN sync songs to collaborative playlists without saving to an account.
    if (!AuthService.instance.isLoggedIn) {
      await AuthService.instance.ensureAnonymousSession();
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

      // Sync watch history count (number only, when logged in)
      if (AuthService.instance.isLoggedIn && !AuthService.instance.isGuest) {
        AuthService.instance.syncWatchHistoryCount().catchError((e) => debugPrint('Watch history count sync: $e'));
      }

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

  Future<void> _openPlaylistSettings() async {
    final isOffline = await AppConnectivity.isOffline();
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
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // REORDER HAPTICS
  //
  // A light tap on pick-up, a tick each time the song passes another
  // position, and a firmer tap when it is dropped.
  // ═══════════════════════════════════════════════════════════════════════════

  void _onReorderStart(int index) {
    _dragging = true;
    _dragSlot = index;
    triggerHaptic(HapticFeedbackType.light);
  }

  void _onReorderEnd(int index) {
    _dragging = false;
  }

  void _onPointerMove(PointerEvent event) {
    _pointerY = event.localPosition.dy;
    _tickIfSlotChanged();
  }

  /// Works out which position the finger is over and ticks when it changes.
  /// Runs on finger movement and on scrolling, so it also ticks while the
  /// list auto-scrolls under a held song.
  void _tickIfSlotChanged() {
    if (!_dragging || _rowCount <= 0 || !_scrollController.hasClients) return;

    final renderObject = _listKey.currentContext?.findRenderObject();
    if (renderObject is! RenderSliver) return;

    // Finger position measured from the top of the first song card.
    final listStart = renderObject.constraints.precedingScrollExtent;
    final y = _pointerY + _scrollController.offset - listStart;
    final slot = (y / _rowExtent).floor().clamp(0, _rowCount - 1).toInt();

    if (slot != _dragSlot) {
      _dragSlot = slot;
      triggerHaptic(HapticFeedbackType.selection);
    }
  }

  /// How a card looks while it is being carried: lifted, solid, outlined.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    final accentColor = ref.read(customizationProvider).accentColor;
    final solid = Color.alphaBlend(_tint(context, 0.08), Theme.of(context).scaffoldBackgroundColor);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final lift = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0).toDouble());
        return Transform.scale(
          scale: 1 + 0.025 * lift,
          child: Stack(
            children: [
              Positioned(
                left: _listSidePadding,
                right: _listSidePadding,
                top: _rowGap / 2,
                bottom: _rowGap / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: solid,
                    borderRadius: BorderRadius.circular(_PlaylistTrackRow.radius),
                    border: Border.all(color: accentColor.withValues(alpha: 0.7 * lift), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30 * lift),
                        blurRadius: 24 * lift,
                        offset: Offset(0, 10 * lift),
                      ),
                    ],
                  ),
                ),
              ),
              Material(type: MaterialType.transparency, child: child),
            ],
          ),
        );
      },
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHEETS & SMALL ACTIONS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showAddSongsBottomSheet() {
    final accentColor = ref.read(customizationProvider).accentColor;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
        final addingTrackIds = <String>{};

        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              height: MediaQuery.of(sheetContext).size.height * 0.7,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const SizedBox(height: 10),
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _tint(sheetContext, 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 14, 12, 6),
                    child: Row(
                      children: [
                        const Expanded(
                          child: Text(
                            'Add songs',
                            style: TextStyle(fontSize: 21, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                          ),
                        ),
                        IconButton(
                          tooltip: 'Close',
                          icon: const Icon(Icons.close_rounded),
                          onPressed: () => Navigator.pop(sheetContext),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      physics: const BouncingScrollPhysics(),
                      padding: EdgeInsets.fromLTRB(8, 4, 8, MediaQuery.of(sheetContext).padding.bottom + 16),
                      itemCount: Track.mockTracks.length,
                      itemBuilder: (context, index) {
                        final track = Track.mockTracks[index];
                        final isAlreadyIn = _playlistTracks.any((t) => t.id == track.id);
                        final isAdding = addingTrackIds.contains(track.id);

                        return ListTile(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          leading: AppArtworkImage(
                            artworkUrl: track.artworkUrl,
                            trackId: track.id,
                            width: 50,
                            height: 50,
                            fit: BoxFit.cover,
                            borderRadius: BorderRadius.circular(13),
                          ),
                          title: Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                          subtitle: Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 12.5, color: _muted(context)),
                          ),
                          trailing: isAdding
                              ? SizedBox(
                                  width: 22,
                                  height: 22,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.2,
                                    valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                  ),
                                )
                              : Icon(
                                  isAlreadyIn ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                  color: isAlreadyIn ? Colors.greenAccent.shade400 : _tint(context, 0.5),
                                ),
                          onTap: (isAdding || isAlreadyIn)
                              ? null
                              : () async {
                                  setModalState(() {
                                    addingTrackIds.add(track.id);
                                  });
                                  try {
                                    await _addSongToPlaylist(track);
                                  } finally {
                                    if (modalCtx.mounted) {
                                      setModalState(() {
                                        addingTrackIds.remove(track.id);
                                      });
                                    }
                                  }
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
      },
    );
  }

  void _copyShareCode() {
    final code = _playlist['shareCode']?.toString() ?? '';
    if (code.isEmpty) return;
    Clipboard.setData(ClipboardData(text: code));
    triggerHaptic(HapticFeedbackType.light);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Copied playlist code "$code"'),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _sharePlaylist() {
    ShareOptionsModal.show(
      context,
      tracks: _playlistTracks,
      title: _playlist['name']?.toString() ?? 'Custom Playlist',
      description: _playlist['description']?.toString() ?? '',
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;
    final playbackState = ref.watch(playbackProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);

    ref.listen<PlaybackState>(playbackProvider, (previous, next) {
      if (_loadingTrackId != null) {
        if (next.currentTrack?.id == _loadingTrackId) {
          if (next.status == PlaybackStatus.playing ||
              next.status == PlaybackStatus.ready ||
              next.status == PlaybackStatus.paused ||
              next.status == PlaybackStatus.error) {
            _loadingTimeoutTimer?.cancel();
            setState(() {
              _loadingTrackId = null;
            });
          }
        } else if (next.status == PlaybackStatus.error) {
          _loadingTimeoutTimer?.cancel();
          setState(() {
            _loadingTrackId = null;
          });
        }
      }
    });

    final query = _searchQuery.trim().toLowerCase();
    final isFiltering = query.isNotEmpty;
    final filteredTracks = !isFiltering
        ? _playlistTracks
        : _playlistTracks.where((track) {
            return track.title.toLowerCase().contains(query) || track.artist.toLowerCase().contains(query);
          }).toList();

    List<Track> displayedTracks = List<Track>.from(filteredTracks);
    switch (_sortOption) {
      case PlaylistSortOption.custom:
        break;
      case PlaylistSortOption.newest:
        displayedTracks = displayedTracks.reversed.toList();
        break;
      case PlaylistSortOption.oldest:
        break;
      case PlaylistSortOption.titleAZ:
        displayedTracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
        break;
      case PlaylistSortOption.titleZA:
        displayedTracks.sort((a, b) => b.title.toLowerCase().compareTo(a.title.toLowerCase()));
        break;
      case PlaylistSortOption.artistAZ:
        displayedTracks.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
        break;
      case PlaylistSortOption.duration:
        displayedTracks.sort((a, b) {
          final da = _parseTrackDuration(a.duration);
          final db = _parseTrackDuration(b.duration);
          return db.compareTo(da);
        });
        break;
    }

    // A song can be in a playlist twice, so a key is the id plus which
    // occurrence it is. It stays with the song when other rows move.
    final seen = <String, int>{};
    final rowKeys = <Key>[];
    for (final track in displayedTracks) {
      final id = track.id.toString();
      final occurrence = seen[id] = (seen[id] ?? 0) + 1;
      rowKeys.add(ValueKey('pl_track_${id}_$occurrence'));
    }

    // Rows have one fixed height that follows the system font size.
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final rowHeight = math.max(48.0, 40.0 * textScale) + 20;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        titleSpacing: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          _playlist['name']?.toString() ?? 'Playlist',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'Outfit'),
        ),
        actions: [
          IconButton(
            icon: _isSyncing
                ? SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                  )
                : const Icon(Icons.sync_rounded),
            tooltip: 'Sync Playlist Songs',
            onPressed: _isSyncing ? null : () => _performPlaylistSync(accentColor),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Playlist Settings',
            onPressed: _openPlaylistSettings,
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert_rounded),
            tooltip: 'More',
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
            onSelected: (val) {
              if (val == 'add') {
                _showAddSongsBottomSheet();
              } else if (val == 'download') {
                _downloadPlaylist(accentColor);
              } else if (val == 'share') {
                _sharePlaylist();
              } else if (val == 'delete') {
                _showDeletePlaylistDialog(accentColor);
              }
            },
            itemBuilder: (context) => [
              const PopupMenuItem(
                value: 'add',
                child: Row(
                  children: [
                    Icon(Icons.add_circle_outline_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Add Songs'),
                  ],
                ),
              ),
              PopupMenuItem(
                value: 'download',
                child: Row(
                  children: [
                    Icon(
                      _isPlaylistDownloaded ? Icons.check_circle_rounded : Icons.download_for_offline_rounded,
                      size: 20,
                      color: _isPlaylistDownloaded ? Colors.green : null,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _isDownloadingPlaylist
                          ? 'Downloading (${(_downloadProgress * 100).toInt()}%)...'
                          : (_isPlaylistDownloaded ? 'Downloaded' : 'Download All'),
                    ),
                  ],
                ),
              ),
              const PopupMenuItem(
                value: 'share',
                child: Row(
                  children: [
                    Icon(Icons.share_rounded, size: 20),
                    SizedBox(width: 10),
                    Text('Share Playlist'),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem(
                value: 'delete',
                child: Row(
                  children: [
                    Icon(Icons.delete_outline_rounded, size: 20, color: Colors.redAccent),
                    SizedBox(width: 10),
                    Text('Delete Playlist', style: TextStyle(color: Colors.redAccent)),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= _wideBreakpoint;
          final side = math.max(20.0, (constraints.maxWidth - _maxContentWidth) / 2);

          _rowExtent = rowHeight + _rowGap;
          _rowCount = displayedTracks.length;
          _listSidePadding = isWide ? 0 : side;

          Widget header({required bool large}) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _PlaylistHero(
                  large: large,
                  name: _playlist['name']?.toString() ?? 'Custom Playlist',
                  byline: _byline(),
                  accent: accentColor,
                  coverBuilder: (size, radius) => _cover(size, radius, accentColor),
                  chips: _buildChips(accentColor),
                ),
                const SizedBox(height: 14),
                _buildActions(accentColor, playbackNotifier, displayedTracks),
                if (_isDownloadingPlaylist) ...[
                  const SizedBox(height: 14),
                  _DownloadProgress(progress: _downloadProgress, accent: accentColor),
                ],
              ],
            );
          }

          Widget songScroller({required double sidePadding, required bool withHeader}) {
            return Listener(
              onPointerDown: _onPointerMove,
              onPointerMove: _onPointerMove,
              child: CustomScrollView(
                controller: _scrollController,
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                slivers: [
                  if (withHeader)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(sidePadding, 6, sidePadding, 0),
                        child: header(large: false),
                      ),
                    ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(sidePadding, withHeader ? 16 : 6, sidePadding, 8),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Expanded(child: _buildSearchField(accentColor)),
                              const SizedBox(width: 8),
                              _buildSortButton(accentColor),
                            ],
                          ),
                          if (_sortOption != PlaylistSortOption.custom) ...[
                            const SizedBox(height: 8),
                            _buildActiveSortChip(accentColor, displayedTracks),
                          ],
                        ],
                      ),
                    ),
                  ),
                  if (displayedTracks.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(sidePadding, 16, sidePadding, 120),
                        child: _buildEmptySongs(accentColor, isFiltering),
                      ),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.only(bottom: 120),
                      sliver: SliverReorderableList(
                        key: _listKey,
                        itemCount: displayedTracks.length,
                        itemExtent: _rowExtent,
                        proxyDecorator: _proxyDecorator,
                        onReorderStart: _onReorderStart,
                        onReorderEnd: _onReorderEnd,
                        onReorder: (oldIndex, newIndex) {
                          triggerHaptic(HapticFeedbackType.medium);
                          _reorderPlaylistSongs(oldIndex, newIndex);
                        },
                        itemBuilder: (context, index) {
                          final track = displayedTracks[index];

                          final isTrackPlayingOrReady = playbackState.currentTrack?.id == track.id &&
                              (playbackState.status == PlaybackStatus.playing ||
                               playbackState.status == PlaybackStatus.ready ||
                               playbackState.status == PlaybackStatus.paused ||
                               playbackState.status == PlaybackStatus.error);

                          final isTrackLoading = (!isTrackPlayingOrReady && _loadingTrackId == track.id) ||
                              (playbackState.currentTrack?.id == track.id &&
                               (playbackState.status == PlaybackStatus.loading || playbackState.status == PlaybackStatus.buffering));

                          return Padding(
                            key: rowKeys[index],
                            padding: EdgeInsets.fromLTRB(sidePadding, _rowGap / 2, sidePadding, _rowGap / 2),
                            child: _PlaylistTrackRow(
                              index: index,
                              title: track.title,
                              artist: track.artist,
                              isYouTube: track.isYouTube,
                              addedBy: track.addedBy,
                              // Positions only mean something on the full
                              // list, so dragging is off while searching or sorted.
                              canReorder: !isFiltering && _sortOption == PlaylistSortOption.custom,
                              artwork: isTrackLoading
                                  ? Container(
                                      width: 48,
                                      height: 48,
                                      decoration: BoxDecoration(
                                        color: accentColor.withValues(alpha: 0.15),
                                        borderRadius: BorderRadius.circular(13),
                                        border: Border.all(
                                          color: accentColor.withValues(alpha: 0.35),
                                          width: 1.5,
                                        ),
                                      ),
                                      child: Center(
                                        child: SizedBox(
                                          width: 20,
                                          height: 20,
                                          child: CircularProgressIndicator(
                                            strokeWidth: 2.2,
                                            valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                          ),
                                        ),
                                      ),
                                    )
                                  : AppArtworkImage(
                                      artworkUrl: track.artworkUrl,
                                      trackId: track.id,
                                      width: 48,
                                      height: 48,
                                      fit: BoxFit.cover,
                                      borderRadius: BorderRadius.circular(13),
                                    ),
                              onPlay: () {
                                triggerHaptic(HapticFeedbackType.selection);
                                _setLoadingTrack(track.id);
                                playbackNotifier.playTrack(track);
                              },
                              onRemove: () {
                                triggerHaptic(HapticFeedbackType.light);
                                // Remove by the song's place in the whole
                                // playlist, not its place in search results.
                                _removeSongFromPlaylist(
                                  _playlistTracks.indexWhere((t) => identical(t, track)),
                                );
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

          if (isWide) {
            final panelWidth = (constraints.maxWidth * 0.36).clamp(280.0, 380.0).toDouble();
            return Padding(
              padding: EdgeInsets.symmetric(horizontal: side),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: panelWidth,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(top: 6, bottom: 120),
                      child: header(large: true),
                    ),
                  ),
                  const SizedBox(width: 24),
                  Expanded(child: songScroller(sidePadding: 0, withHeader: false)),
                ],
              ),
            );
          }

          return songScroller(sidePadding: side, withHeader: true);
        },
      ),
    );
  }

  String _byline() {
    final author = _playlist['authorName']?.toString() ?? '';
    final description = _playlist['description']?.toString() ?? '';
    final by = 'By ${author.isNotEmpty ? author : 'Me'}';
    return description.isNotEmpty ? '$by · $description' : by;
  }

  Widget _cover(double size, double radius, Color accentColor) {
    final firstTrack = _playlistTracks.isNotEmpty ? _playlistTracks.first : null;

    if (firstTrack != null && firstTrack.artworkUrl.isNotEmpty) {
      return AppArtworkImage(
        artworkUrl: firstTrack.artworkUrl,
        trackId: firstTrack.id,
        width: size,
        height: size,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(radius),
      );
    }

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withValues(alpha: 0.4), accentColor.withValues(alpha: 0.14)],
        ),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Icon(Icons.queue_music_rounded, color: accentColor, size: size * 0.45),
    );
  }

  List<Widget> _buildChips(Color accentColor) {
    final code = _playlist['shareCode']?.toString() ?? '';
    final isOwner = AuthService.instance.isPlaylistOwner(_playlist);
    final ownerName = _playlist['authorName']?.toString() ?? 'Creator';
    final count = _playlistTracks.length;

    return [
      // Share code: tap to copy
      if (code.isNotEmpty)
        _InfoChip(
          icon: Icons.tag_rounded,
          label: code,
          trailingIcon: Icons.copy_rounded,
          color: accentColor,
          tooltip: 'Copy playlist code',
          onTap: _copyShareCode,
        ),
      _InfoChip(
        icon: isOwner ? Icons.workspace_premium_rounded : Icons.person_outline_rounded,
        label: isOwner ? 'You · Owner' : ownerName,
      ),
      _InfoChip(icon: Icons.music_note_rounded, label: '$count ${count == 1 ? 'song' : 'songs'}'),
      if (_playlist['isPublic'] == true) const _InfoChip(icon: Icons.public_rounded, label: 'Public'),
      if (_playlist['isSyncEnabled'] == true) const _InfoChip(icon: Icons.sync_rounded, label: 'Sync on'),
    ];
  }

  Widget _buildActions(Color accentColor, PlaybackNotifier playbackNotifier, List<Track> currentTracks) {
    final hasSongs = currentTracks.isNotEmpty;

    return Row(
      children: [
        Expanded(
          child: FilledButton.icon(
            onPressed: !hasSongs
                ? null
                : () {
                    triggerHaptic(HapticFeedbackType.selection);
                    playbackNotifier.playCustomQueue(currentTracks, initialIndex: 0);
                  },
            icon: const Icon(Icons.play_arrow_rounded, size: 22),
            label: const Text('Play all', maxLines: 1),
            style: FilledButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: _onColor(accentColor),
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: FilledButton.icon(
            onPressed: !hasSongs
                ? null
                : () {
                    triggerHaptic(HapticFeedbackType.selection);
                    final shuffled = List<Track>.from(currentTracks)..shuffle();
                    playbackNotifier.playCustomQueue(shuffled, initialIndex: 0);
                  },
            icon: const Icon(Icons.shuffle_rounded, size: 20),
            label: const Text('Shuffle', maxLines: 1),
            style: FilledButton.styleFrom(
              backgroundColor: _tint(context, 0.09),
              foregroundColor: Theme.of(context).colorScheme.onSurface,
              minimumSize: const Size(0, 50),
              padding: const EdgeInsets.symmetric(horizontal: 12),
              shape: const StadiumBorder(),
              textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Material(
          color: _tint(context, 0.09),
          shape: const CircleBorder(),
          clipBehavior: Clip.antiAlias,
          child: IconButton(
            tooltip: 'Add Songs',
            constraints: const BoxConstraints.tightFor(width: 50, height: 50),
            padding: EdgeInsets.zero,
            icon: const Icon(Icons.add_rounded, size: 24),
            onPressed: _showAddSongsBottomSheet,
          ),
        ),
      ],
    );
  }

  Widget _buildSortButton(Color accentColor) {
    final isCustom = _sortOption == PlaylistSortOption.custom;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return PopupMenuButton<PlaylistSortOption>(
      tooltip: 'Sort Playlist',
      offset: const Offset(0, 52),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      color: isDark ? const Color(0xFF1E1E24) : Colors.white,
      onSelected: (option) {
        triggerHaptic(HapticFeedbackType.selection);
        setState(() {
          _sortOption = option;
        });
      },
      itemBuilder: (context) {
        return PlaylistSortOption.values.map((opt) {
          final isSelected = _sortOption == opt;
          return PopupMenuItem<PlaylistSortOption>(
            value: opt,
            child: Row(
              children: [
                Icon(
                  opt.icon,
                  size: 19,
                  color: isSelected ? accentColor : (isDark ? Colors.white70 : Colors.black87),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    opt.label,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.w800 : FontWeight.w500,
                      color: isSelected ? accentColor : null,
                    ),
                  ),
                ),
                if (isSelected)
                  Icon(Icons.check_rounded, size: 18, color: accentColor),
              ],
            ),
          );
        }).toList();
      },
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: !isCustom ? accentColor.withValues(alpha: 0.18) : _tint(context, 0.055),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: !isCustom ? accentColor.withValues(alpha: 0.6) : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.swap_vert_rounded,
              size: 20,
              color: !isCustom ? accentColor : _muted(context),
            ),
            const SizedBox(width: 6),
            Text(
              'Sort',
              style: TextStyle(
                fontWeight: !isCustom ? FontWeight.w800 : FontWeight.w600,
                fontSize: 13.5,
                color: !isCustom ? accentColor : _muted(context),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActiveSortChip(Color accentColor, List<Track> currentTracks) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: accentColor.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(_sortOption.icon, size: 14, color: accentColor),
              const SizedBox(width: 6),
              Text(
                'Sorted: ${_sortOption.label}',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: accentColor,
                ),
              ),
              const SizedBox(width: 6),
              GestureDetector(
                onTap: () {
                  triggerHaptic(HapticFeedbackType.light);
                  setState(() => _sortOption = PlaylistSortOption.custom);
                },
                child: Icon(Icons.close_rounded, size: 14, color: accentColor),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        TextButton(
          onPressed: () => _saveCurrentSortAsPlaylistOrder(currentTracks),
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text(
            'Save Order',
            style: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w600,
              color: accentColor,
            ),
          ),
        ),
      ],
    );
  }

  Future<void> _saveCurrentSortAsPlaylistOrder(List<Track> currentTracks) async {
    if (_sortOption == PlaylistSortOption.custom) return;
    final sorted = List<Track>.from(currentTracks);
    _playlistTracks = sorted;
    _playlist['tracks'] = sorted.map((t) => t.toJson()).toList();
    _playlist['trackIds'] = sorted.map((t) => t.id).toList();
    _sortOption = PlaylistSortOption.custom;
    await _persistPlaylist(_playlist);
    if (mounted) {
      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Saved order as playlist default ✨'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Duration _parseTrackDuration(String durationStr) {
    try {
      final parts = durationStr.split(':');
      if (parts.length == 2) {
        return Duration(minutes: int.parse(parts[0]), seconds: int.parse(parts[1]));
      }
    } catch (_) {}
    return const Duration(minutes: 3);
  }

  Widget _buildSearchField(Color accentColor) {
    OutlineInputBorder outline(Color color, [double width = 1]) {
      return OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: color, width: width),
      );
    }

    return TextField(
      controller: _searchController,
      textInputAction: TextInputAction.search,
      onChanged: (val) {
        setState(() {
          _searchQuery = val;
        });
      },
      decoration: InputDecoration(
        hintText: 'Search in this playlist',
        hintStyle: TextStyle(fontSize: 14, color: _muted(context)),
        prefixIcon: Icon(Icons.search_rounded, size: 21, color: _muted(context)),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                tooltip: 'Clear search',
                icon: Icon(Icons.close_rounded, size: 19, color: _muted(context)),
                onPressed: () {
                  _searchController.clear();
                  setState(() {
                    _searchQuery = '';
                  });
                },
              ),
        filled: true,
        fillColor: _tint(context, 0.055),
        contentPadding: const EdgeInsets.symmetric(vertical: 13),
        border: outline(Colors.transparent),
        enabledBorder: outline(Colors.transparent),
        focusedBorder: outline(accentColor, 1.5),
      ),
    );
  }

  Widget _buildEmptySongs(Color accentColor, bool isFiltering) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(
              isFiltering ? Icons.search_off_rounded : Icons.library_music_rounded,
              size: 34,
              color: accentColor,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isFiltering ? 'No matching songs' : 'No songs in this playlist yet',
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            isFiltering ? 'Nothing here matches "${_searchQuery.trim()}".' : 'Add a few to get started.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, color: _muted(context)),
          ),
          if (!isFiltering) ...[
            const SizedBox(height: 18),
            FilledButton.icon(
              onPressed: _showAddSongsBottomSheet,
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text('Add songs'),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: _onColor(accentColor),
                minimumSize: const Size(0, 46),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

/// White in dark mode, black in light mode, at the given opacity.
Color _tint(BuildContext context, double alpha) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

Color _muted(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
}

/// Readable text/icon color on top of [background] (any accent the user picks).
Color _onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// Cover, name, owner line and chips. Compact (cover on the left) on phones,
/// [large] (cover on top) when it is the side panel on wide screens.
class _PlaylistHero extends StatelessWidget {
  const _PlaylistHero({
    required this.name,
    required this.byline,
    required this.accent,
    required this.coverBuilder,
    required this.chips,
    this.large = false,
  });

  final String name;
  final String byline;
  final Color accent;
  final bool large;

  /// Builds the cover at the given square size and corner radius.
  final Widget Function(double size, double radius) coverBuilder;
  final List<Widget> chips;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget shadowed(Widget cover, double radius) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 18,
              offset: const Offset(0, 9),
            ),
          ],
        ),
        child: cover,
      );
    }

    final title = Text(
      name,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontFamily: 'Outfit',
        fontSize: large ? 25 : 21,
        fontWeight: FontWeight.w900,
        letterSpacing: -0.3,
        height: 1.15,
      ),
    );
    final sub = Text(
      byline,
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(fontSize: 13, height: 1.35, color: _muted(context)),
    );
    final chipWrap = Wrap(spacing: 6, runSpacing: 6, children: chips);

    final Widget content;
    if (large) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              shadowed(coverBuilder(constraints.maxWidth, 22), 22),
              const SizedBox(height: 18),
              title,
              const SizedBox(height: 5),
              sub,
              const SizedBox(height: 14),
              chipWrap,
            ],
          );
        },
      );
    } else {
      content = Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              shadowed(coverBuilder(92, 20), 20),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [title, const SizedBox(height: 5), sub],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          chipWrap,
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [accent.withValues(alpha: 0.30), const Color(0xFF1C1C20)]
              : [accent.withValues(alpha: 0.20), Colors.white],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.12 : 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }
}

/// A small rounded fact about the playlist. Neutral unless given a [color].
class _InfoChip extends StatelessWidget {
  const _InfoChip({
    required this.icon,
    required this.label,
    this.trailingIcon,
    this.color,
    this.tooltip,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final IconData? trailingIcon;
  final Color? color;
  final String? tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final foreground = color ?? Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8);

    Widget chip = Material(
      color: color != null ? color!.withValues(alpha: 0.16) : _tint(context, 0.08),
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(
        side: BorderSide(color: color != null ? color!.withValues(alpha: 0.4) : Colors.transparent),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 13, color: foreground),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: foreground),
                ),
              ),
              if (trailingIcon != null) ...[
                const SizedBox(width: 6),
                Icon(trailingIcon, size: 12, color: foreground),
              ],
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      chip = Tooltip(message: tooltip!, child: chip);
    }
    return chip;
  }
}

class _DownloadProgress extends StatelessWidget {
  const _DownloadProgress({required this.progress, required this.accent});

  final double progress;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(Icons.download_rounded, size: 17, color: accent),
        const SizedBox(width: 10),
        Expanded(
          child: ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 5,
              color: accent,
              backgroundColor: _tint(context, 0.1),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '${(progress * 100).toInt()}%',
          style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

/// One song in the playlist. Tap to play. Press and hold the row, or drag the
/// grip on the right, to move it.
class _PlaylistTrackRow extends StatelessWidget {
  const _PlaylistTrackRow({
    required this.index,
    required this.title,
    required this.artist,
    required this.isYouTube,
    required this.addedBy,
    required this.canReorder,
    required this.artwork,
    required this.onPlay,
    required this.onRemove,
  });

  static const double radius = 18;

  final int index;
  final String title;
  final String artist;
  final bool isYouTube;
  final String? addedBy;
  final bool canReorder;
  final Widget artwork;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sourceColor = isYouTube
        ? (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD32F2F))
        : (isDark ? const Color(0xFF00D1B2) : const Color(0xFF00897B));
    final contributor = addedBy?.trim() ?? '';

    final Widget tappable = InkWell(
      onTap: onPlay,
      child: Row(
        children: [
          const SizedBox(width: 10),
          artwork,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.25),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    // Where the song streams from
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                      margin: const EdgeInsets.only(right: 6),
                      decoration: BoxDecoration(
                        color: sourceColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        isYouTube ? 'YT' : 'Saavn',
                        style: TextStyle(
                          color: sourceColor,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.4,
                          height: 1.3,
                        ),
                      ),
                    ),
                    Flexible(
                      child: Text(
                        artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, height: 1.25, color: _muted(context)),
                      ),
                    ),
                    // Who added it (collaborative playlists)
                    if (contributor.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                        decoration: BoxDecoration(
                          color: _tint(context, 0.08),
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.person_rounded, size: 10, color: _muted(context)),
                            const SizedBox(width: 3),
                            ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 80),
                              child: Text(
                                contributor,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                  color: _muted(context),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          IconButton(
            tooltip: 'Remove from playlist',
            visualDensity: VisualDensity.compact,
            onPressed: onRemove,
            icon: Icon(Icons.close_rounded, size: 18, color: _tint(context, 0.45)),
          ),
        ],
      ),
    );

    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Everything except the grip: tap plays, press-and-hold drags.
          Expanded(
            child: canReorder
                ? ReorderableDelayedDragStartListener(index: index, child: tappable)
                : tappable,
          ),
          // The grip: drags straight away, no hold needed.
          if (canReorder)
            ReorderableDragStartListener(
              index: index,
              child: Semantics(
                label: 'Reorder',
                child: Container(
                  width: 42,
                  color: Colors.transparent,
                  alignment: Alignment.center,
                  child: Icon(Icons.drag_indicator_rounded, size: 22, color: _tint(context, 0.38)),
                ),
              ),
            )
          else
            const SizedBox(width: 4),
        ],
      ),
    );
  }
}