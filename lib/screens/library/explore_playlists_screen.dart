import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/playlist.dart';
import '../../services/playlist/playlist_repository.dart';
import '../../services/auth/auth_service.dart';
import '../../providers/customization_provider.dart';

class ExplorePlaylistsScreen extends ConsumerStatefulWidget {
  const ExplorePlaylistsScreen({super.key});

  @override
  ConsumerState<ExplorePlaylistsScreen> createState() => _ExplorePlaylistsScreenState();
}

class _ExplorePlaylistsScreenState extends ConsumerState<ExplorePlaylistsScreen> {
  final PlaylistRepository _repository = PlaylistRepository();
  final List<Playlist> _playlists = [];
  bool _isLoading = true;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadInitialPlaylists();
  }

  Future<void> _loadInitialPlaylists() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    // 1. Auto-upload any local public playlists so they appear immediately in Explore
    try {
      await _repository.syncLocalPublicPlaylists();
    } catch (e) {
      debugPrint('Sync local public playlists note: $e');
    }

    // 2. Fetch public playlists from Firestore
    try {
      final results = await _repository.getPublicPlaylists(limit: 20);
      if (mounted) {
        setState(() {
          _playlists.clear();
          _playlists.addAll(results);
          _isLoading = false;
          _hasMore = results.length == 20;
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

  Future<void> _importAsCopy(Playlist p) async {
    final uid = AuthService.instance.currentUserId;
    final name = AuthService.instance.currentUserName;
    if (uid.isEmpty) return;

    try {
      await _repository.duplicateAsPrivateCopy(
        sourcePlaylistId: p.id,
        newOwnerUid: uid,
        newOwnerName: name,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('Imported "${p.name}" as your private copy!'),
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

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141414) : Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) {
        return DraggableScrollableSheet(
          initialChildSize: 0.65,
          minChildSize: 0.4,
          maxChildSize: 0.9,
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
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(p.name, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                            Text('Created by ${p.ownerName} • ${p.trackCount} tracks', style: const TextStyle(fontSize: 13, color: Colors.grey)),
                          ],
                        ),
                      ),
                      FilledButton.icon(
                        style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _importAsCopy(p);
                        },
                        icon: const Icon(Icons.copy_rounded, size: 16),
                        label: const Text('Import Copy', style: TextStyle(fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                  const Divider(height: 24),
                  Expanded(
                    child: p.tracks.isEmpty
                        ? const Center(child: Text('No tracks in this playlist'))
                        : ListView.separated(
                            controller: scrollController,
                            itemCount: p.tracks.length,
                            separatorBuilder: (_, __) => const Divider(height: 1, indent: 56),
                            itemBuilder: (context, idx) {
                              final t = p.tracks[idx];
                              return ListTile(
                                leading: Container(
                                  width: 40,
                                  height: 40,
                                  decoration: BoxDecoration(
                                    color: Colors.grey.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(8),
                                    image: t.artworkUrl.isNotEmpty
                                        ? DecorationImage(image: NetworkImage(t.artworkUrl), fit: BoxFit.cover)
                                        : null,
                                  ),
                                  child: t.artworkUrl.isEmpty ? const Icon(Icons.music_note, size: 20) : null,
                                ),
                                title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                                subtitle: Text('${t.artist} • Added by ${t.addedByName}', maxLines: 1, style: const TextStyle(fontSize: 12)),
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

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Explore Public Playlists', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadInitialPlaylists,
          ),
        ],
      ),
      body: _isLoading
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
              : _playlists.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.public_off_rounded, size: 64, color: Colors.grey.withOpacity(0.5)),
                            const SizedBox(height: 16),
                            const Text('No public playlists found yet', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                            const SizedBox(height: 6),
                            const Text('Publish a playlist in your library to share with the community!', textAlign: TextAlign.center, style: TextStyle(color: Colors.grey, fontSize: 13)),
                            const SizedBox(height: 18),
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
                          mainAxisExtent: 110,
                          crossAxisSpacing: 12,
                          mainAxisSpacing: 12,
                        ),
                        itemCount: _playlists.length,
                        itemBuilder: (context, index) {
                          final pl = _playlists[index];
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
                                      width: 80,
                                      height: 80,
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
                                          Row(
                                            children: [
                                              Container(
                                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                decoration: BoxDecoration(
                                                  color: Colors.teal.withOpacity(0.15),
                                                  borderRadius: BorderRadius.circular(6),
                                                ),
                                                child: const Text('PUBLIC', style: TextStyle(fontSize: 10, color: Colors.teal, fontWeight: FontWeight.bold)),
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
    );
  }
}
