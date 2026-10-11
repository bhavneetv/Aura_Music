import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/customization_provider.dart';
import '../../services/auth/auth_service.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../../services/storage/storage_service.dart';
import '../../services/sync/playlist_cloud_sync_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/app_artwork_image.dart';
import '../../widgets/playlist_imported_dialog.dart';

class GlobalPlaylistsScreen extends ConsumerStatefulWidget {
  const GlobalPlaylistsScreen({super.key});

  @override
  ConsumerState<GlobalPlaylistsScreen> createState() => _GlobalPlaylistsScreenState();
}

class _GlobalPlaylistsScreenState extends ConsumerState<GlobalPlaylistsScreen> {
  List<PublicPlaylistSummary> _playlists = [];
  bool _isLoading = true;
  String _searchQuery = '';
  int _selectedFilterIndex = 0; // 0: All, 1: Sync Enabled, 2: Recent
  final Set<String> _importingIds = {};
  final Set<String> _importedSyncIds = {};

  final List<String> _filters = [
    'All Playlists',
    '🔄 Collaborative',
    '🔥 Recent',
  ];

  @override
  void initState() {
    super.initState();
    _loadExistingImportedIds();
    _fetchGlobalPlaylists();
  }

  void _loadExistingImportedIds() {
    final local = StorageService.getPlaylists();
    for (final pl in local) {
      final syncId = pl['syncId']?.toString();
      if (syncId != null && syncId.isNotEmpty) {
        _importedSyncIds.add(syncId);
      }
    }
  }

  Future<void> _fetchGlobalPlaylists() async {
    setState(() => _isLoading = true);
    try {
      final list = await PlaylistCloudSyncService.instance.fetchGlobalPublicPlaylists();
      if (mounted) {
        setState(() {
          _playlists = list;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  Future<void> _importPlaylist(PublicPlaylistSummary summary, Color accentColor) async {
    if (_importingIds.contains(summary.syncId)) return;

    setState(() => _importingIds.add(summary.syncId));

    try {
      List<Track> tracks = [];
      if (summary.syncId.isNotEmpty) {
        tracks = await PlaylistCloudSyncService.instance.fetchPlaylistTracksBySyncId(summary.syncId);
      }

      // Only system demonstration seed playlists get mock seed songs if empty
      if (tracks.isEmpty && summary.syncId.startsWith('seed_')) {
        tracks = List.generate(summary.trackCount > 0 ? summary.trackCount : 12, (i) {
          final mock = Track.mockTracks[i % Track.mockTracks.length];
          return Track(
            id: 'global_${summary.syncId}_$i',
            title: mock.title,
            artist: mock.artist,
            album: summary.name,
            duration: mock.duration,
            artworkUrl: summary.sampleArtwork.isNotEmpty ? summary.sampleArtwork : mock.artworkUrl,
            audioUrl: mock.audioUrl,
            genre: mock.genre,
          );
        });
      }

      final currentUserId = AuthService.instance.currentUserId;
      final currentUserEmail = (AuthService.instance.currentUserEmail ?? '').trim().toLowerCase();
      final currentUserName = AuthService.instance.currentUserName.trim().toLowerCase();

      final isMyOwnPlaylist = AuthService.instance.isLoggedIn && (
        (summary.ownerId.isNotEmpty && summary.ownerId == currentUserId) ||
        (summary.ownerEmail.isNotEmpty && summary.ownerEmail.trim().toLowerCase() == currentUserEmail) ||
        (summary.authorName.isNotEmpty && summary.authorName.trim().toLowerCase() == currentUserName &&
            (summary.ownerId.isEmpty || summary.ownerId == currentUserId))
      );

      final newPlaylist = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': summary.name,
        'description': summary.description.isNotEmpty ? summary.description : 'Imported from Global Playlists',
        'authorName': summary.authorName,
        'ownerId': isMyOwnPlaylist ? currentUserId : summary.ownerId,
        'ownerEmail': isMyOwnPlaylist ? (AuthService.instance.currentUserEmail ?? summary.ownerEmail) : summary.ownerEmail,
        'ownerName': summary.authorName,
        'isImported': !isMyOwnPlaylist,
        'isPublic': true,
        'isSyncEnabled': summary.isSyncEnabled,
        'shareCode': summary.shareCode,
        'syncId': summary.syncId,
        'trackIds': tracks.map((t) => t.id).toList(),
        'tracks': tracks.map((t) => t.toJson()).toList(),
      };

      final playlists = StorageService.getPlaylists();
      playlists.insert(0, newPlaylist);
      await StorageService.savePlaylists(playlists);

      if (mounted) {
        setState(() {
          _importingIds.remove(summary.syncId);
          _importedSyncIds.add(summary.syncId);
        });

        final importEvent = PlaylistImportEvent(
          title: summary.name,
          description: summary.description,
          trackCount: tracks.length,
          tracks: tracks,
          fromQrScan: false,
        );

        PlaylistImportSuccessDialog.show(context, importEvent, ref);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _importingIds.remove(summary.syncId));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to import: $e')),
        );
      }
    }
  }

  void _showEnterCodeDialog() {
    final codeController = TextEditingController();
    bool isSearchingCode = false;
    String? codeError;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final accentColor = ref.watch(customizationProvider).accentColor;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1B1B1F) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Row(
                children: [
                  Icon(Icons.tag_rounded, color: accentColor),
                  const SizedBox(width: 8),
                  const Text('Search by Playlist Code', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18)),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('Enter the unique 6-character code (e.g. AURA-7K9X2B) shared by another user:'),
                  const SizedBox(height: 14),
                  TextField(
                    controller: codeController,
                    textCapitalization: TextCapitalization.characters,
                    decoration: InputDecoration(
                      hintText: 'AURA-XXXXXX',
                      prefixIcon: const Icon(Icons.vpn_key_rounded),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    ),
                  ),
                  if (codeError != null) ...[
                    const SizedBox(height: 8),
                    Text(codeError!, style: const TextStyle(color: Colors.redAccent, fontSize: 12)),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed: isSearchingCode
                      ? null
                      : () async {
                          final code = codeController.text.trim();
                          if (code.isEmpty) return;

                          setDialogState(() {
                            isSearchingCode = true;
                            codeError = null;
                          });

                          final playlistData = await PlaylistCloudSyncService.instance.fetchPlaylistByShareCode(code);

                          if (playlistData != null) {
                            Navigator.pop(ctx);
                            final List<Track> tracks = List<Track>.from(playlistData['tracks'] as List? ?? []);
                            final summary = PublicPlaylistSummary(
                              id: playlistData['syncId']?.toString() ?? '',
                              syncId: playlistData['syncId']?.toString() ?? '',
                              shareCode: playlistData['shareCode']?.toString() ?? code,
                              ownerId: playlistData['ownerId']?.toString() ?? '',
                              ownerEmail: playlistData['ownerEmail']?.toString() ?? '',
                              name: playlistData['name']?.toString() ?? 'Shared Playlist',
                              description: playlistData['description']?.toString() ?? '',
                              authorName: playlistData['authorName']?.toString() ?? 'Community Member',
                              trackCount: tracks.length,
                              isSyncEnabled: playlistData['isSyncEnabled'] == true,
                              sampleArtwork: tracks.isNotEmpty ? tracks.first.artworkUrl : '',
                              updatedAt: DateTime.now().millisecondsSinceEpoch,
                            );

                            await _importPlaylist(summary, accentColor);
                          } else {
                            setDialogState(() {
                              isSearchingCode = false;
                              codeError = 'Playlist not found. Verify the code and try again.';
                            });
                          }
                        },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  child: isSearchingCode
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Find & Import 🚀', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    final filtered = _playlists.where((p) {
      final q = _searchQuery.toLowerCase().trim();
      if (q.isEmpty) {
        if (_selectedFilterIndex == 1) return p.isSyncEnabled;
        return true;
      }

      final matchesSearch = p.name.toLowerCase().contains(q) ||
          p.authorName.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.shareCode.toLowerCase().contains(q) ||
          p.shareCode.toLowerCase().replaceAll('aura-', '').contains(q);

      if (!matchesSearch) return false;

      if (_selectedFilterIndex == 1) {
        return p.isSyncEnabled;
      }
      return true;
    }).toList();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101014) : const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(7),
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.public_rounded, color: accentColor, size: 20),
            ),
            const SizedBox(width: 10),
            Text(
              'Global Playlists 🌐',
              style: TextStyle(
                fontFamily: 'Outfit',
                fontSize: 19,
                fontWeight: FontWeight.bold,
                color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.tag_rounded),
            tooltip: 'Search by Code',
            onPressed: _showEnterCodeDialog,
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Feed',
            onPressed: _fetchGlobalPlaylists,
          ),
        ],
      ),
      body: Column(
        children: [
          // 1. Search Bar with Direct Code Entry Button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    onChanged: (val) {
                      setState(() => _searchQuery = val);
                    },
                    decoration: InputDecoration(
                      hintText: 'Search title, creator, or code (e.g. AURA-7K9)...',
                      hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.black38),
                      prefixIcon: Icon(Icons.search_rounded, size: 20, color: accentColor),
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                IconButton.filled(
                  style: IconButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: Colors.black,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                  icon: const Icon(Icons.tag_rounded, size: 20),
                  tooltip: 'Enter Playlist Code',
                  onPressed: _showEnterCodeDialog,
                ),
              ],
            ),
          ),

          // 2. Filter Pills
          SizedBox(
            height: 38,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              itemCount: _filters.length,
              itemBuilder: (context, index) {
                final isSelected = _selectedFilterIndex == index;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(_filters[index]),
                    selected: isSelected,
                    showCheckmark: false,
                    labelStyle: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
                    ),
                    backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                    selectedColor: accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    side: BorderSide.none,
                    onSelected: (val) {
                      setState(() => _selectedFilterIndex = index);
                    },
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),

          // 3. Playlists List
          Expanded(
            child: _isLoading
                ? Center(
                    child: CircularProgressIndicator(
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    ),
                  )
                : filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.public_off_rounded, size: 54, color: accentColor.withValues(alpha: 0.4)),
                            const SizedBox(height: 12),
                            const Text('No public playlists found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                            const SizedBox(height: 4),
                            const Text('Be the first to publish a public playlist or search by code!', style: TextStyle(color: Colors.grey, fontSize: 12)),
                            const SizedBox(height: 14),
                            ElevatedButton.icon(
                              onPressed: _showEnterCodeDialog,
                              icon: const Icon(Icons.tag_rounded, size: 16),
                              label: const Text('Enter Playlist Code'),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: accentColor,
                                foregroundColor: Colors.black,
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.only(left: 20, right: 20, top: 6, bottom: 120),
                        itemCount: filtered.length,
                        itemBuilder: (context, index) {
                          final item = filtered[index];
                          final isAlreadyImported = _importedSyncIds.contains(item.syncId);
                          final isImporting = _importingIds.contains(item.syncId);

                          return Container(
                            margin: const EdgeInsets.only(bottom: 14),
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: item.isSyncEnabled ? accentColor.withValues(alpha: 0.25) : (isDark ? Colors.white10 : Colors.black12),
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: isDark ? 0.2 : 0.04),
                                  blurRadius: 10,
                                  offset: const Offset(0, 4),
                                ),
                              ],
                            ),
                            child: Row(
                              children: [
                                // Sample Artwork
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: item.sampleArtwork.isNotEmpty
                                      ? AppArtworkImage(
                                          artworkUrl: item.sampleArtwork,
                                          trackId: item.id,
                                          width: 72,
                                          height: 72,
                                          fit: BoxFit.cover,
                                        )
                                      : Container(
                                          width: 72,
                                          height: 72,
                                          decoration: BoxDecoration(
                                            color: accentColor.withValues(alpha: 0.15),
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                          child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 36),
                                        ),
                                ),
                                const SizedBox(width: 14),

                                // Details
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit'),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        'By ${item.authorName} • ${item.trackCount} Songs',
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          color: isDark ? Colors.white60 : Colors.black54,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (item.description.isNotEmpty) ...[
                                        const SizedBox(height: 3),
                                        Text(
                                          item.description,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 11, color: Colors.grey),
                                        ),
                                      ],
                                      const SizedBox(height: 6),
                                      Wrap(
                                        spacing: 6,
                                        runSpacing: 4,
                                        children: [
                                          if (item.isSyncEnabled)
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: Colors.greenAccent.withValues(alpha: 0.15),
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(Icons.sync_rounded, size: 10, color: Colors.greenAccent),
                                                  SizedBox(width: 3),
                                                  Text('Collaborative', style: TextStyle(fontSize: 9.5, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                                                ],
                                              ),
                                            )
                                          else
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: isDark ? Colors.white10 : Colors.black12,
                                                borderRadius: BorderRadius.circular(6),
                                              ),
                                              child: const Text('Read-Only', style: TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                                            ),

                                          if (item.shareCode.isNotEmpty)
                                            GestureDetector(
                                              onTap: () {
                                                Clipboard.setData(ClipboardData(text: item.shareCode));
                                                ScaffoldMessenger.of(context).showSnackBar(
                                                  SnackBar(
                                                    content: Text('Copied code "${item.shareCode}" to clipboard! 📋'),
                                                    behavior: SnackBarBehavior.floating,
                                                    duration: const Duration(seconds: 2),
                                                  ),
                                                );
                                              },
                                              child: Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: accentColor.withValues(alpha: 0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                                                ),
                                                child: Row(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    Icon(Icons.tag_rounded, size: 10, color: accentColor),
                                                    const SizedBox(width: 2),
                                                    Text(
                                                      item.shareCode,
                                                      style: TextStyle(fontSize: 9.5, color: accentColor, fontWeight: FontWeight.bold),
                                                    ),
                                                  ],
                                                ),
                                              ),
                                            ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 8),

                                // 1-Tap Add to Library Button
                                ElevatedButton(
                                  onPressed: isAlreadyImported || isImporting
                                      ? null
                                      : () => _importPlaylist(item, accentColor),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: isAlreadyImported ? Colors.grey.withValues(alpha: 0.2) : accentColor,
                                    foregroundColor: isAlreadyImported ? Colors.grey : Colors.black,
                                    elevation: isAlreadyImported ? 0 : 2,
                                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                    minimumSize: const Size(60, 36),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                  child: isImporting
                                      ? const SizedBox(
                                          width: 14,
                                          height: 14,
                                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                                        )
                                      : Text(
                                          isAlreadyImported ? 'Imported' : 'Import',
                                          style: TextStyle(
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold,
                                            color: isAlreadyImported ? Colors.grey : Colors.black,
                                          ),
                                        ),
                                ),
                              ],
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
