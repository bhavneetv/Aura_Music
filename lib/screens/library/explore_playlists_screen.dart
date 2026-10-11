import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../models/playlist.dart';
import '../../models/playlist_track.dart';
import '../../models/track.dart';
import '../../services/sync/playlist_cloud_sync_service.dart';
import '../../services/playlist/playlist_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../services/storage/storage_service.dart';
import '../../providers/customization_provider.dart';
import '../../services/network/app_connectivity.dart';
import 'playlist_detail_screen.dart';

class ExplorePlaylistsScreen extends ConsumerStatefulWidget {
  const ExplorePlaylistsScreen({super.key});

  @override
  ConsumerState<ExplorePlaylistsScreen> createState() => _ExplorePlaylistsScreenState();
}

class _ExplorePlaylistsScreenState extends ConsumerState<ExplorePlaylistsScreen> {
  final PlaylistRepository _repository = PlaylistRepository();
  final List<Playlist> _playlists = [];
  bool _isLoading = true;
  String? _errorMessage;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  List<String> _recentSearches = [];
  bool _isSearchingCode = false;

  @override
  void initState() {
    super.initState();
    _loadRecentSearches();
    _loadInitialPlaylists();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _loadRecentSearches() {
    try {
      final raw = StorageService.getSetting('explore_recent_searches', defaultValue: <dynamic>[]);
      if (raw is List) {
        setState(() {
          _recentSearches = raw.map((e) => e.toString()).where((e) => e.trim().isNotEmpty).toList();
        });
      }
    } catch (_) {}
  }

  Future<void> _addRecentSearch(String term) async {
    final clean = term.trim();
    if (clean.isEmpty) return;
    setState(() {
      _recentSearches.remove(clean);
      _recentSearches.insert(0, clean);
      if (_recentSearches.length > 8) {
        _recentSearches = _recentSearches.sublist(0, 8);
      }
    });
    try {
      await StorageService.saveSetting('explore_recent_searches', _recentSearches);
    } catch (_) {}
  }

  Future<void> _removeRecentSearch(String term) async {
    setState(() {
      _recentSearches.remove(term);
    });
    try {
      await StorageService.saveSetting('explore_recent_searches', _recentSearches);
    } catch (_) {}
  }

  Future<void> _clearAllRecentSearches() async {
    setState(() {
      _recentSearches.clear();
    });
    try {
      await StorageService.saveSetting('explore_recent_searches', <String>[]);
    } catch (_) {}
  }

  Future<void> _loadInitialPlaylists() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = 'You are offline. Please connect to the internet to explore global playlists.';
        });
      }
      return;
    }

    // 1. Auto-upload any local public playlists so they appear immediately in Explore
    try {
      await _repository.syncLocalPublicPlaylists();
    } catch (e) {
      debugPrint('Sync local public playlists note: $e');
    }

    // 2. Fetch public playlists from Firestore
    try {
      final results = await _repository.getPublicPlaylists(limit: 50);
      if (mounted) {
        setState(() {
          _playlists.clear();
          _playlists.addAll(results);
          _isLoading = false;
          _errorMessage = null;
        });
      }
    } catch (e) {
      debugPrint('Explore fetch error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _errorMessage = e.toString();
        });
      }
    }
  }

  Future<void> _handleSearchByCode([String? inputCode]) async {
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
                    'You are offline. Searching global playlists requires an active internet connection.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    final code = (inputCode ?? _searchController.text).trim().toUpperCase();
    if (code.isEmpty) {
      _showEnterCodeDialog();
      return;
    }

    setState(() => _isSearchingCode = true);
    try {
      // 1. Check if matches an invite code in Firestore
      final playlistFromInvite = await _repository.getPlaylistByInviteCode(code);
      if (playlistFromInvite != null) {
        await _addRecentSearch(code);
        if (mounted) {
          setState(() => _isSearchingCode = false);
          _previewPlaylist(playlistFromInvite);
        }
        return;
      }

      // 2. Check direct playlist ID or shareCode match
      final directDoc = await _repository.getPlaylist(code);
      if (directDoc != null) {
        await _addRecentSearch(code);
        if (mounted) {
          setState(() => _isSearchingCode = false);
          _previewPlaylist(directDoc);
        }
        return;
      }

      // 3. Check locally loaded playlists (by ID, shareCode, or stripped code)
      final localMatch = _playlists.cast<Playlist?>().firstWhere(
        (p) => p != null && (
          p.id.toUpperCase() == code ||
          (p.shareCode != null && p.shareCode!.toUpperCase() == code) ||
          (p.shareCode != null && p.shareCode!.replaceAll('AURA-', '').toUpperCase() == code) ||
          (p.tracks.any((t) => t.id.toUpperCase() == code))
        ),
        orElse: () => null,
      );

      if (localMatch != null) {
        await _addRecentSearch(code);
        if (mounted) {
          setState(() => _isSearchingCode = false);
          _previewPlaylist(localMatch);
        }
        return;
      }

      // 4. Fallback: check legacy cloud sync service if exists
      try {
        final legacyData = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode(code);
        if (legacyData != null) {
          final legacyOwnerId = legacyData['ownerId']?.toString() ?? '';
          final legacyAuthor = legacyData['authorName']?.toString() ?? 'Community Member';
          final List rawTracks = legacyData['tracks'] as List? ?? [];
          final tracks = <PlaylistTrack>[];
          for (final t in rawTracks) {
            if (t is Track) {
              tracks.add(PlaylistTrack.fromTrack(
                t,
                addedByUid: legacyOwnerId,
                addedByName: t.addedBy ?? legacyAuthor,
              ));
            } else if (t is Map) {
              try {
                final trk = Track.fromJson(Map<String, dynamic>.from(t));
                tracks.add(PlaylistTrack.fromTrack(
                  trk,
                  addedByUid: legacyOwnerId,
                  addedByName: trk.addedBy ?? legacyAuthor,
                ));
              } catch (_) {}
            }
          }

          final legacyPl = Playlist(
            id: legacyData['id']?.toString() ?? code,
            name: legacyData['name']?.toString() ?? 'Shared Playlist',
            description: legacyData['description']?.toString() ?? '',
            ownerUid: legacyData['ownerId']?.toString() ?? '',
            ownerName: legacyData['authorName']?.toString() ?? 'Community Member',
            memberUids: [legacyData['ownerId']?.toString() ?? ''],
            visibility: legacyData['isPublic'] == true ? 'public' : 'private',
            collabEnabled: legacyData['isSyncEnabled'] == true,
            createdAt: DateTime.now(),
            updatedAt: DateTime.now(),
            trackCount: tracks.length,
            tracks: tracks,
            shareCode: legacyData['shareCode']?.toString() ?? code,
          );

          await _addRecentSearch(code);
          if (mounted) {
            setState(() => _isSearchingCode = false);
            _previewPlaylist(legacyPl);
          }
          return;
        }
      } catch (_) {}

      if (mounted) {
        setState(() => _isSearchingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('No playlist found with code "$code". Please check the code.'),
            backgroundColor: Colors.orangeAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSearchingCode = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error finding code: $e'),
            backgroundColor: Colors.redAccent,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showEnterCodeDialog() {
    final codeController = TextEditingController();
    final accent = ref.read(customizationProvider).accentColor;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.tag_rounded, color: accent, size: 24),
            const SizedBox(width: 8),
            const Text('Search by Code', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Enter an 8-character invite code or share code to instantly access and join a collaborative playlist:',
              style: TextStyle(fontSize: 12.5, color: Colors.grey),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: codeController,
              autofocus: true,
              textCapitalization: TextCapitalization.characters,
              decoration: InputDecoration(
                hintText: 'e.g. 7KX9Y2A1',
                prefixIcon: Icon(Icons.vpn_key_rounded, color: accent),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
            onPressed: () {
              final c = codeController.text.trim();
              Navigator.pop(ctx);
              if (c.isNotEmpty) {
                _searchController.text = c;
                setState(() => _searchQuery = c);
                _handleSearchByCode(c);
              }
            },
            child: const Text('Search Code', style: TextStyle(fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );
  }

  Future<void> _joinCollaborator(Playlist p) async {
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
                    'You are offline. Please connect to the internet to join playlists.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    // Ensure an active session exists (anonymous if user is a guest)
    if (!AuthService.instance.isLoggedIn) {
      await AuthService.instance.ensureAnonymousSession();
    }

    try {
      final currentUid = AuthService.instance.currentUserId;
      final currentName = AuthService.instance.currentUserName.isNotEmpty
          ? AuthService.instance.currentUserName
          : StorageService.getUserAuthorName();

      Playlist target = p;

      // 1. Join on Firestore if session exists
      if (currentUid.isNotEmpty) {
        try {
          final code = await _repository.getInviteCodeForPlaylist(p.id);
          if (code != null) {
            target = await _repository.joinByInviteCode(code, currentUid, currentName);
          } else {
            await FirebaseFirestore.instance.collection('playlists').doc(p.id).update({
              'memberUids': FieldValue.arrayUnion([currentUid]),
              'updatedAt': FieldValue.serverTimestamp(),
            });
          }
        } catch (fe) {
          debugPrint('Firestore join notice: $fe');
        }
      }

      // If tracks are missing from summary, fetch full playlist
      if (target.tracks.isEmpty) {
        try {
          final fullPl = await _repository.getPlaylist(target.id);
          if (fullPl != null) {
            target = fullPl;
          }
        } catch (_) {}
      }

      // 2. ALWAYS add immediately to local StorageService!
      final convertedTracks = target.tracks.map((pt) {
        final t = pt.toTrack();
        return t.toJson();
      }).toList();

      final joinedMap = <String, dynamic>{
        'id': target.id,
        'name': target.name,
        'description': target.description,
        'authorName': target.ownerName,
        'ownerId': target.ownerUid,
        'ownerEmail': '',
        'ownerName': target.ownerName,
        'isImported': true,
        'isPublic': target.isPublic,
        'isSyncEnabled': target.collabEnabled,
        'shareCode': target.shareCode ?? '',
        'trackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
        'syncedTrackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
        'tracks': convertedTracks,
      };

      final localPlaylists = StorageService.getPlaylists();
      localPlaylists.removeWhere((item) => item['id']?.toString() == target.id);
      localPlaylists.insert(0, joinedMap);
      await StorageService.savePlaylists(localPlaylists);

      // Trigger instant UI refresh across the app
      AuthService.instance.playlistsChangedNotifier.value++;

      // Background cloud restore if logged in
      if (AuthService.instance.isLoggedIn && !AuthService.instance.isGuest) {
        AuthService.instance.restoreUserPlaylists().catchError((e) {
          debugPrint('Background restoreUserPlaylists notice: $e');
          return 0;
        });
      }

      if (mounted) {
        Navigator.pop(context);
        final wasRejoined = p.memberUids.contains(currentUid);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Row(
              children: [
                const Icon(Icons.handshake_rounded, color: Colors.white, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    wasRejoined
                        ? 'Re-joined "${target.name}" as a Collaborator! 🤝 Added to your Library.'
                        : 'Joined "${target.name}" as a Collaborator! 🤝 Added to your Library.',
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
          ),
        );
        _loadInitialPlaylists();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text('Failed to join: $e'),
          ),
        );
      }
    }
  }

  Future<void> _importAsCopy(Playlist p) async {
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
                    'You are offline. Please connect to the internet to import playlists.',
                    style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                ),
              ],
            ),
            backgroundColor: Colors.redAccent.shade700,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    try {
      final currentUid = AuthService.instance.currentUserId;
      final currentAuthor = AuthService.instance.currentUserName.isNotEmpty
          ? AuthService.instance.currentUserName
          : StorageService.getUserAuthorName();

      Playlist source = p;
      if (source.tracks.isEmpty) {
        try {
          final full = await _repository.getPlaylist(p.id);
          if (full != null) source = full;
        } catch (_) {}
      }

      String newId = 'copy_${DateTime.now().millisecondsSinceEpoch}';

      // If user is authenticated and not a guest, duplicate on Firestore as well
      if (AuthService.instance.isLoggedIn && !AuthService.instance.isGuest && currentUid.isNotEmpty) {
        try {
          final remoteCopy = await _repository.duplicateAsPrivateCopy(
            sourcePlaylistId: source.id,
            newOwnerUid: currentUid,
            newOwnerName: currentAuthor,
          );
          newId = remoteCopy.id;
        } catch (cloudErr) {
          debugPrint('Firestore copy creation notice: $cloudErr');
        }
      }

      final convertedTracks = source.tracks.map((pt) {
        final t = pt.toTrack();
        return t.toJson();
      }).toList();

      final copyPlaylist = <String, dynamic>{
        'id': newId,
        'name': '${source.name} (Copy)',
        'description': source.description.isNotEmpty ? source.description : 'Copied from ${source.ownerName}',
        'authorName': currentAuthor,
        'ownerId': currentUid.isNotEmpty ? currentUid : StorageService.getDeviceId(),
        'ownerEmail': AuthService.instance.currentUserEmail ?? '',
        'ownerName': currentAuthor,
        'isImported': false,
        'isPublic': false,
        'isSyncEnabled': false,
        'shareCode': '',
        'trackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
        'syncedTrackIds': convertedTracks.map((t) => t['id']?.toString() ?? '').toList(),
        'tracks': convertedTracks,
      };

      // IMMEDIATELY save to local storage
      final localPlaylists = StorageService.getPlaylists();
      localPlaylists.removeWhere((item) => item['id']?.toString() == newId);
      localPlaylists.insert(0, copyPlaylist);
      await StorageService.savePlaylists(localPlaylists);

      // Trigger instant UI refresh across the app
      AuthService.instance.playlistsChangedNotifier.value++;

      // Trigger cloud restore in background if appropriate
      if (AuthService.instance.isLoggedIn && !AuthService.instance.isGuest) {
        AuthService.instance.restoreUserPlaylists().catchError((e) {
          debugPrint('Background restoreUserPlaylists error: $e');
          return 0;
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('Imported "${source.name}" as your private copy! 📥 Added to your Library.'),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFFC62828),
            content: Text('Failed to import: $e'),
          ),
        );
      }
    }
  }

  void _previewPlaylist(Playlist p) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final currentUid = AuthService.instance.currentUserId;
    final isOwner = p.isOwner(currentUid);
    final hasInLocalLibrary = StorageService.getPlaylists().any((item) => item['id']?.toString() == p.id);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        bool isJoining = false;
        bool isImporting = false;
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.72,
              minChildSize: 0.45,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(color: Colors.grey.withOpacity(0.4), borderRadius: BorderRadius.circular(2)),
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Header Info
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: accent.withOpacity(0.18),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Icon(Icons.album_rounded, color: accent, size: 30),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(p.name, style: const TextStyle(fontSize: 19, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                                const SizedBox(height: 2),
                                Text('Created by ${p.ownerName} • ${p.trackCount} tracks', style: const TextStyle(fontSize: 12.5, color: Colors.grey)),
                                const SizedBox(height: 4),
                                // Collaborator count indicator
                                Row(
                                  children: [
                                    Icon(
                                      p.collabEnabled ? Icons.groups_rounded : Icons.public_rounded,
                                      size: 14,
                                      color: p.collabEnabled ? Colors.amberAccent : Colors.teal,
                                    ),
                                    const SizedBox(width: 5),
                                    Text(
                                      p.collabEnabled
                                          ? 'Collaborative • ${p.memberUids.length} Collaborator(s)'
                                          : 'Public (Read-Only)',
                                      style: TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.bold,
                                        color: p.collabEnabled ? Colors.amberAccent : Colors.teal,
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),

                      const SizedBox(height: 14),

                      // Action Buttons Row: Join Collaborator & Import Copy
                      Row(
                        children: [
                          if (p.collabEnabled) ...[
                            Expanded(
                              child: FilledButton.icon(
                                style: FilledButton.styleFrom(
                                  backgroundColor: hasInLocalLibrary ? Colors.grey.withOpacity(0.3) : accent,
                                  foregroundColor: hasInLocalLibrary ? (isDark ? Colors.white70 : Colors.black87) : Colors.black,
                                  padding: const EdgeInsets.symmetric(vertical: 12),
                                ),
                                onPressed: isJoining || isImporting
                                    ? null
                                    : () async {
                                        if (hasInLocalLibrary) {
                                          Navigator.pop(ctx);
                                          final playlists = StorageService.getPlaylists();
                                          final idx = playlists.indexWhere((item) => item['id']?.toString() == p.id);
                                          if (idx != -1 && context.mounted) {
                                            Navigator.push(
                                              context,
                                              MaterialPageRoute(
                                                builder: (_) => PlaylistDetailScreen(
                                                  playlistIndex: idx,
                                                  initialPlaylist: playlists[idx],
                                                ),
                                              ),
                                            );
                                          }
                                          return;
                                        }

                                        setModalState(() => isJoining = true);
                                        try {
                                          await _joinCollaborator(p);
                                        } finally {
                                          if (modalCtx.mounted) {
                                            setModalState(() => isJoining = false);
                                          }
                                        }
                                      },
                                icon: isJoining
                                    ? const SizedBox(
                                        width: 16,
                                        height: 16,
                                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                      )
                                    : Icon(hasInLocalLibrary ? Icons.check_circle_rounded : Icons.group_add_rounded, size: 17),
                                label: FittedBox(
                                  fit: BoxFit.scaleDown,
                                  child: Text(
                                    isJoining
                                        ? 'Joining...'
                                        : (hasInLocalLibrary
                                            ? (isOwner ? 'Owner (In Library) 👑' : 'In Library ✅')
                                            : (isOwner
                                                ? 'Add to Library 👑'
                                                : (p.memberUids.contains(currentUid) ? 'Re-join Collab 🤝' : 'Join Collab 🤝'))),
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                          ],
                          Expanded(
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: BorderSide(color: accent.withOpacity(0.6)),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              onPressed: (isJoining || isImporting) ? null : () async {
                                setModalState(() => isImporting = true);
                                try {
                                  await _importAsCopy(p);
                                } finally {
                                  if (modalCtx.mounted) {
                                    setModalState(() => isImporting = false);
                                    Navigator.pop(modalCtx);
                                  }
                                }
                              },
                              icon: isImporting
                                  ? SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2, color: accent),
                                    )
                                  : const Icon(Icons.copy_rounded, size: 16),
                              label: FittedBox(
                                fit: BoxFit.scaleDown,
                                child: Text(
                                  isImporting ? 'Importing...' : 'Import Copy 📥',
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      const Divider(height: 24),

                      // Track Listing Header
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('TRACK LIST', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1, color: Colors.grey)),
                          Text('${p.tracks.length} songs', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        ],
                      ),
                      const SizedBox(height: 8),

                      Expanded(
                        child: p.tracks.isEmpty
                            ? const Center(child: Text('No tracks in this playlist yet', style: TextStyle(color: Colors.grey)))
                            : ListView.separated(
                                controller: scrollController,
                                itemCount: p.tracks.length,
                                separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                                itemBuilder: (context, idx) {
                                  final t = p.tracks[idx];
                                  return ListTile(
                                    leading: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: Colors.grey.withOpacity(0.2),
                                        borderRadius: BorderRadius.circular(8),
                                        image: t.artworkUrl.isNotEmpty
                                            ? DecorationImage(image: NetworkImage(t.artworkUrl), fit: BoxFit.cover)
                                            : null,
                                      ),
                                      child: t.artworkUrl.isEmpty ? const Icon(Icons.music_note, size: 20) : null,
                                    ),
                                    title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                    subtitle: Text(
                                      '${t.artist} • Added by ${t.addedByName.isNotEmpty ? t.addedByName : p.ownerName}',
                                      maxLines: 1,
                                      style: const TextStyle(fontSize: 11.5, color: Colors.grey),
                                    ),
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
      },
    );
  }

  List<Playlist> get _filteredPlaylists {
    if (_searchQuery.isEmpty) return _playlists;
    final q = _searchQuery.toLowerCase().trim();
    return _playlists.where((p) {
      final matchesName = p.name.toLowerCase().contains(q);
      final matchesOwner = p.ownerName.toLowerCase().contains(q);
      final matchesDesc = p.description.toLowerCase().contains(q);
      final matchesCode = p.id.toLowerCase() == q ||
          (p.shareCode != null && p.shareCode!.toLowerCase() == q) ||
          (p.shareCode != null && p.shareCode!.replaceAll('AURA-', '').toLowerCase() == q);
      final matchesTrack = p.tracks.any((t) =>
          t.title.toLowerCase().contains(q) || t.artist.toLowerCase().contains(q));
      return matchesName || matchesOwner || matchesDesc || matchesCode || matchesTrack;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final filtered = _filteredPlaylists;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Public Playlists', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            tooltip: 'Search by Code',
            icon: const Icon(Icons.tag_rounded),
            onPressed: _showEnterCodeDialog,
          ),
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadInitialPlaylists,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Search Bar Section ─────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: 'Search playlists, creators, or enter code...',
                hintStyle: TextStyle(fontSize: 13, color: isDark ? Colors.white38 : Colors.black38),
                prefixIcon: const Icon(Icons.search_rounded, size: 22),
                suffixIcon: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_searchQuery.isNotEmpty)
                      IconButton(
                        icon: const Icon(Icons.clear_rounded, size: 18),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                    IconButton(
                      tooltip: 'Search by Code',
                      icon: Icon(Icons.tag_rounded, color: accent, size: 20),
                      onPressed: () => _handleSearchByCode(),
                    ),
                  ],
                ),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              ),
              onChanged: (val) {
                setState(() => _searchQuery = val);
              },
              onSubmitted: (val) {
                if (val.trim().isNotEmpty) {
                  _addRecentSearch(val.trim());
                  // If it looks like an invite code, check code directly
                  if (val.trim().length >= 6 && val.trim().length <= 12 && !val.contains(' ')) {
                    _handleSearchByCode(val.trim());
                  }
                }
              },
            ),
          ),

          // ── Recent Searches Chips Row ──────────────────────────────
          if (_recentSearches.isNotEmpty && _searchQuery.isEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 8),
              child: SizedBox(
                height: 34,
                child: Row(
                  children: [
                    const Icon(Icons.history_rounded, size: 16, color: Colors.grey),
                    const SizedBox(width: 6),
                    Expanded(
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: _recentSearches.length,
                        separatorBuilder: (_, __) => const SizedBox(width: 6),
                        itemBuilder: (context, idx) {
                          final term = _recentSearches[idx];
                          return InputChip(
                            label: Text(term, style: const TextStyle(fontSize: 11.5)),
                            backgroundColor: isDark ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.06),
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            onPressed: () {
                              _searchController.text = term;
                              setState(() => _searchQuery = term);
                            },
                            onDeleted: () => _removeRecentSearch(term),
                            deleteIconColor: Colors.grey,
                            deleteIcon: const Icon(Icons.close_rounded, size: 13),
                          );
                        },
                      ),
                    ),
                    TextButton(
                      style: TextButton.styleFrom(padding: EdgeInsets.zero, visualDensity: VisualDensity.compact),
                      onPressed: _clearAllRecentSearches,
                      child: const Text('Clear', style: TextStyle(fontSize: 11, color: Colors.grey)),
                    ),
                  ],
                ),
              ),
            ),

          // ── Main Content Area ──────────────────────────────────────
          Expanded(
            child: _isLoading || _isSearchingCode
                ? const Center(child: CircularProgressIndicator())
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.cloud_off_rounded, size: 64, color: Colors.orange.withOpacity(0.8)),
                              const SizedBox(height: 16),
                              const Text('Unable to load public playlists', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                              const SizedBox(height: 8),
                              Text(
                                _errorMessage!.contains('permission-denied')
                                    ? 'Firestore access denied. Please ensure your Firebase rules are deployed.'
                                    : _errorMessage!,
                                textAlign: TextAlign.center,
                                style: const TextStyle(color: Colors.grey, fontSize: 13),
                              ),
                              const SizedBox(height: 18),
                              FilledButton.icon(
                                style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                                onPressed: _loadInitialPlaylists,
                                icon: const Icon(Icons.refresh_rounded, size: 18),
                                label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : filtered.isEmpty
                        ? Center(
                            child: Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 24),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    _searchQuery.isNotEmpty ? Icons.search_off_rounded : Icons.public_off_rounded,
                                    size: 64,
                                    color: Colors.grey.withOpacity(0.5),
                                  ),
                                  const SizedBox(height: 16),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'No playlists match "$_searchQuery"'
                                        : 'No public playlists found yet',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    _searchQuery.isNotEmpty
                                        ? 'Try searching by an 8-character invite code or another title'
                                        : 'Publish a playlist in your library to share with the community!',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                                  ),
                                  const SizedBox(height: 18),
                                  if (_searchQuery.isNotEmpty) ...[
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                                      onPressed: () => _handleSearchByCode(_searchQuery),
                                      icon: const Icon(Icons.vpn_key_rounded, size: 18),
                                      label: Text('Search Code "$_searchQuery"', style: const TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                    const SizedBox(height: 8),
                                    TextButton(
                                      onPressed: () {
                                        _searchController.clear();
                                        setState(() => _searchQuery = '');
                                      },
                                      child: const Text('Clear Search Filter'),
                                    ),
                                  ] else ...[
                                    FilledButton.icon(
                                      style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                                      onPressed: () async {
                                        final count = await _repository.syncLocalPublicPlaylists();
                                        if (mounted) {
                                          ScaffoldMessenger.of(context).showSnackBar(
                                            SnackBar(content: Text('Uploaded $count public playlist(s) to cloud!')),
                                          );
                                          _loadInitialPlaylists();
                                        }
                                      },
                                      icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                                      label: const Text('Sync & Publish My Playlists', style: TextStyle(fontWeight: FontWeight.bold)),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          )
                        : RefreshIndicator(
                            onRefresh: _loadInitialPlaylists,
                            child: LayoutBuilder(
                              builder: (context, constraints) {
                                final isTabletOrDesktop = constraints.maxWidth > 650;

                                return GridView.builder(
                                  padding: const EdgeInsets.all(16),
                                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                                    crossAxisCount: isTabletOrDesktop ? 2 : 1,
                                    mainAxisExtent: 142,
                                    crossAxisSpacing: 12,
                                    mainAxisSpacing: 12,
                                  ),
                                  itemCount: filtered.length,
                                  itemBuilder: (context, index) {
                                    final pl = filtered[index];
                                    final isUserInLibrary = StorageService.getPlaylists().any((item) => item['id']?.toString() == pl.id);

                                    return Card(
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                                      elevation: 0,
                                      color: isDark ? const Color(0xFF161616) : Colors.white,
                                      child: InkWell(
                                        borderRadius: BorderRadius.circular(20),
                                        onTap: () => _previewPlaylist(pl),
                                        child: Padding(
                                          padding: const EdgeInsets.all(12),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 82,
                                                height: 82,
                                                decoration: BoxDecoration(
                                                  color: accent.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(14),
                                                ),
                                                child: Icon(Icons.album_rounded, color: accent, size: 38),
                                              ),
                                              const SizedBox(width: 14),
                                              Expanded(
                                                child: Column(
                                                  crossAxisAlignment: CrossAxisAlignment.start,
                                                  mainAxisAlignment: MainAxisAlignment.center,
                                                  children: [
                                                    Text(
                                                      pl.name,
                                                      maxLines: 1,
                                                      overflow: TextOverflow.ellipsis,
                                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Outfit'),
                                                    ),
                                                    const SizedBox(height: 4),
                                                    Text(
                                                      'By ${pl.ownerName} • ${pl.trackCount} songs',
                                                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                                                    ),
                                                    const SizedBox(height: 6),
                                                    Wrap(
                                                      spacing: 6,
                                                      runSpacing: 4,
                                                      children: [
                                                        if (pl.collabEnabled)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                                            decoration: BoxDecoration(
                                                              color: Colors.amber.withOpacity(0.18),
                                                              borderRadius: BorderRadius.circular(6),
                                                              border: Border.all(color: Colors.amber.withOpacity(0.4), width: 0.8),
                                                            ),
                                                            child: Row(
                                                              mainAxisSize: MainAxisSize.min,
                                                              children: [
                                                                const Icon(Icons.groups_rounded, size: 12, color: Colors.amberAccent),
                                                                const SizedBox(width: 4),
                                                                Text(
                                                                  'COLLABORATIVE (${pl.memberUids.length})',
                                                                  style: const TextStyle(fontSize: 10, color: Colors.amberAccent, fontWeight: FontWeight.bold),
                                                                ),
                                                              ],
                                                            ),
                                                          )
                                                        else
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                                            decoration: BoxDecoration(
                                                              color: Colors.teal.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: const Text('PUBLIC', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
                                                          ),
                                                        if (isUserInLibrary)
                                                          Container(
                                                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                                                            decoration: BoxDecoration(
                                                              color: Colors.green.withOpacity(0.15),
                                                              borderRadius: BorderRadius.circular(6),
                                                            ),
                                                            child: const Text('IN LIBRARY ✅', style: TextStyle(fontSize: 10, color: Colors.green, fontWeight: FontWeight.bold)),
                                                          ),
                                                      ],
                                                    ),
                                                  ],
                                                ),
                                              ),
                                              IconButton(
                                                icon: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                                                onPressed: () => _previewPlaylist(pl),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    );
                                  },
                                );
                              },
                            ),
                          ),
          ),
        ],
      ),
    );
  }
}
