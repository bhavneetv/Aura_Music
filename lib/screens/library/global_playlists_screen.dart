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
  int _selectedFilterIndex = 0; // 0: All, 1: Collaborative, 2: Recent
  final Set<String> _importingIds = {};
  final Set<String> _importedSyncIds = {};

  static const List<String> _filters = [
    'All',
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

      final isMyOwnPlaylist = AuthService.instance.isLoggedIn &&
          ((summary.ownerId.isNotEmpty && summary.ownerId == currentUserId) ||
              (summary.ownerEmail.isNotEmpty && summary.ownerEmail.trim().toLowerCase() == currentUserEmail) ||
              (summary.authorName.isNotEmpty &&
                  summary.authorName.trim().toLowerCase() == currentUserName &&
                  (summary.ownerId.isEmpty || summary.ownerId == currentUserId)));

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
    final accentColor = ref.read(customizationProvider).accentColor;
    bool isSearchingCode = false;
    String? codeError;

    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;

        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1B1B1F) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
              titlePadding: const EdgeInsets.fromLTRB(20, 18, 20, 0),
              contentPadding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
              actionsPadding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
              title: Row(
                children: [
                  Icon(Icons.tag_rounded, color: accentColor, size: 20),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Search by Playlist Code',
                      style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Enter the 6-character code (e.g. AURA-7K9X2B) shared by another user:',
                      style: TextStyle(fontSize: 12.5),
                    ),
                    const SizedBox(height: 10),
                    TextField(
                      controller: codeController,
                      textCapitalization: TextCapitalization.characters,
                      style: const TextStyle(fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'AURA-XXXXXX',
                        isDense: true,
                        prefixIcon: const Icon(Icons.vpn_key_rounded, size: 18),
                        filled: true,
                        fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                        contentPadding: const EdgeInsets.symmetric(vertical: 11),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                      ),
                    ),
                    if (codeError != null) ...[
                      const SizedBox(height: 6),
                      Text(codeError!, style: const TextStyle(color: Colors.redAccent, fontSize: 11.5)),
                    ],
                  ],
                ),
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
                          if (!ctx.mounted) return;

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
                    visualDensity: VisualDensity.compact,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: isSearchingCode
                      ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                      : const Text('Find & Import 🚀', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  List<PublicPlaylistSummary> _applyFilters() {
    final q = _searchQuery.toLowerCase().trim();

    var result = _playlists.where((p) {
      if (_selectedFilterIndex == 1 && !p.isSyncEnabled) return false;
      if (q.isEmpty) return true;

      return p.name.toLowerCase().contains(q) ||
          p.authorName.toLowerCase().contains(q) ||
          p.description.toLowerCase().contains(q) ||
          p.shareCode.toLowerCase().contains(q) ||
          p.shareCode.toLowerCase().replaceAll('aura-', '').contains(q);
    }).toList();

    if (_selectedFilterIndex == 2) {
      result.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    }
    return result;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;
    final filtered = _applyFilters();

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF101014) : const Color(0xFFF8F8FC),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 52,
        titleSpacing: 0,
        leading: IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.public_rounded, color: accentColor, size: 17),
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(
                'Global Playlists',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.refresh_rounded, size: 22),
            tooltip: 'Refresh Feed',
            onPressed: _fetchGlobalPlaylists,
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1100),
          child: Column(
            children: [
              _buildSearchRow(isDark, accentColor),
              _buildFilterPills(isDark, accentColor),
              const SizedBox(height: 8),
              Expanded(child: _buildBody(filtered, isDark, accentColor)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSearchRow(bool isDark, Color accentColor) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
      child: Row(
        children: [
          Expanded(
            child: SizedBox(
              height: 40,
              child: TextField(
                onChanged: (val) => setState(() => _searchQuery = val),
                style: const TextStyle(fontSize: 13.5),
                decoration: InputDecoration(
                  hintText: 'Search title, creator or code…',
                  hintStyle: TextStyle(fontSize: 12.5, color: isDark ? Colors.white38 : Colors.black38),
                  prefixIcon: Icon(Icons.search_rounded, size: 18, color: accentColor),
                  isDense: true,
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 40,
            height: 40,
            child: IconButton.filled(
              padding: EdgeInsets.zero,
              style: IconButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.tag_rounded, size: 18),
              tooltip: 'Enter Playlist Code',
              onPressed: _showEnterCodeDialog,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterPills(bool isDark, Color accentColor) {
    return SizedBox(
      height: 32,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        itemCount: _filters.length,
        separatorBuilder: (_, __) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final isSelected = _selectedFilterIndex == index;
          return ChoiceChip(
            label: Text(_filters[index]),
            selected: isSelected,
            showCheckmark: false,
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 4),
            labelStyle: TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.bold,
              color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
            ),
            backgroundColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            selectedColor: accentColor,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            side: BorderSide.none,
            onSelected: (_) => setState(() => _selectedFilterIndex = index),
          );
        },
      ),
    );
  }

  Widget _buildBody(List<PublicPlaylistSummary> filtered, bool isDark, Color accentColor) {
    if (_isLoading) {
      return Center(
        child: CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
      );
    }

    if (filtered.isEmpty) {
      return RefreshIndicator(
        color: accentColor,
        onRefresh: _fetchGlobalPlaylists,
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.public_off_rounded, size: 44, color: accentColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 10),
                      const Text('No public playlists found',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                      const SizedBox(height: 3),
                      const Text(
                        'Be the first to publish one, or search by code!',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey, fontSize: 12),
                      ),
                      const SizedBox(height: 12),
                      ElevatedButton.icon(
                        onPressed: _showEnterCodeDialog,
                        icon: const Icon(Icons.tag_rounded, size: 15),
                        label: const Text('Enter Playlist Code', style: TextStyle(fontSize: 12.5)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          foregroundColor: Colors.black,
                          visualDensity: VisualDensity.compact,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }

    // One column on phones, 2–3 columns on tablets/desktop.
    return RefreshIndicator(
      color: accentColor,
      onRefresh: _fetchGlobalPlaylists,
      child: GridView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(14, 2, 14, 96),
        gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
          maxCrossAxisExtent: 480,
          mainAxisExtent: 82,
          crossAxisSpacing: 10,
          mainAxisSpacing: 8,
        ),
        itemCount: filtered.length,
        itemBuilder: (context, index) {
          final item = filtered[index];
          return _PlaylistCard(
            item: item,
            isDark: isDark,
            accentColor: accentColor,
            isImported: _importedSyncIds.contains(item.syncId),
            isImporting: _importingIds.contains(item.syncId),
            onImport: () => _importPlaylist(item, accentColor),
          );
        },
      ),
    );
  }
}

class _PlaylistCard extends StatelessWidget {
  final PublicPlaylistSummary item;
  final bool isDark;
  final Color accentColor;
  final bool isImported;
  final bool isImporting;
  final VoidCallback onImport;

  const _PlaylistCard({
    required this.item,
    required this.isDark,
    required this.accentColor,
    required this.isImported,
    required this.isImporting,
    required this.onImport,
  });

  static const double _art = 58;

  Widget _chip({required Widget child, required Color color, Color? border}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(6),
        border: border != null ? Border.all(color: border) : null,
      ),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final muted = isDark ? Colors.white60 : Colors.black54;

    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: item.isSyncEnabled ? accentColor.withValues(alpha: 0.28) : (isDark ? Colors.white10 : Colors.black12),
        ),
      ),
      child: Row(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: item.sampleArtwork.isNotEmpty
                ? AppArtworkImage(
                    artworkUrl: item.sampleArtwork,
                    trackId: item.id,
                    width: _art,
                    height: _art,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: _art,
                    height: _art,
                    color: accentColor.withValues(alpha: 0.15),
                    child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 28),
                  ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14, fontFamily: 'Outfit', height: 1.15),
                ),
                const SizedBox(height: 1),
                Text(
                  'By ${item.authorName} • ${item.trackCount} songs',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: muted, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 5),
                Row(
                  children: [
                    if (item.isSyncEnabled)
                      _chip(
                        color: Colors.greenAccent.withValues(alpha: 0.15),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.sync_rounded, size: 10, color: Colors.greenAccent),
                            SizedBox(width: 3),
                            Text('Collab',
                                style: TextStyle(fontSize: 9.5, color: Colors.greenAccent, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      )
                    else
                      _chip(
                        color: isDark ? Colors.white10 : Colors.black12,
                        child: const Text('Read-only',
                            style: TextStyle(fontSize: 9.5, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ),
                    if (item.shareCode.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Flexible(
                        child: GestureDetector(
                          onTap: () {
                            Clipboard.setData(ClipboardData(text: item.shareCode));
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text('Copied code "${item.shareCode}" 📋'),
                                behavior: SnackBarBehavior.floating,
                                duration: const Duration(seconds: 2),
                              ),
                            );
                          },
                          child: _chip(
                            color: accentColor.withValues(alpha: 0.15),
                            border: accentColor.withValues(alpha: 0.3),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.tag_rounded, size: 10, color: accentColor),
                                const SizedBox(width: 2),
                                Flexible(
                                  child: Text(
                                    item.shareCode,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 9.5, color: accentColor, fontWeight: FontWeight.bold),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            height: 34,
            child: ElevatedButton(
              onPressed: isImported || isImporting ? null : onImport,
              style: ElevatedButton.styleFrom(
                backgroundColor: isImported ? Colors.grey.withValues(alpha: 0.2) : accentColor,
                foregroundColor: isImported ? Colors.grey : Colors.black,
                disabledBackgroundColor: isImported ? Colors.grey.withValues(alpha: 0.2) : accentColor.withValues(alpha: 0.6),
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 34),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: isImporting
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                    )
                  : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(isImported ? Icons.check_rounded : Icons.download_rounded,
                            size: 15, color: isImported ? Colors.grey : Colors.black),
                        const SizedBox(width: 4),
                        Text(
                          isImported ? 'Added' : 'Import',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: isImported ? Colors.grey : Colors.black,
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ],
      ),
    );
  }
}