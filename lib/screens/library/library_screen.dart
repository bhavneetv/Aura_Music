import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../themes/app_theme.dart';
import 'playlist_detail_screen.dart';
import 'recently_played_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _playlistNameController = TextEditingController();
  final TextEditingController _playlistDescController = TextEditingController();
  List<Map<String, dynamic>> _playlists = [];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadPlaylists();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _playlistNameController.dispose();
    _playlistDescController.dispose();
    super.dispose();
  }

  void _loadPlaylists() {
    setState(() {
      _playlists = StorageService.getPlaylists();
    });
  }

  void _createPlaylist() async {
    final name = _playlistNameController.text.trim();
    final desc = _playlistDescController.text.trim();
    if (name.isNotEmpty) {
      final playlists = StorageService.getPlaylists();
      final newPl = {
        'id': DateTime.now().millisecondsSinceEpoch.toString(),
        'name': name,
        'description': desc.isNotEmpty ? desc : 'A premium custom playlist',
        'trackIds': <String>[],
      };
      playlists.add(newPl);
      await StorageService.savePlaylists(playlists);
      
      _playlistNameController.clear();
      _playlistDescController.clear();
      _loadPlaylists();
      Navigator.pop(context);
    }
  }

  void _showCreatePlaylistBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: EdgeInsets.only(
            left: 24, 
            right: 24, 
            top: 24, 
            bottom: MediaQuery.of(context).viewInsets.bottom + 24
          ),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Create Playlist', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              TextField(
                controller: _playlistNameController,
                decoration: const InputDecoration(
                  labelText: 'Playlist Name',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _playlistDescController,
                decoration: const InputDecoration(
                  labelText: 'Description (Optional)',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: () => Navigator.pop(context),
                    child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: _createPlaylist,
                    style: ElevatedButton.styleFrom(backgroundColor: ref.watch(customizationProvider).accentColor),
                    child: const Text('Create', style: TextStyle(color: Colors.black)),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Title
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 16, bottom: 8),
          child: Text(
            'Your Library',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                ),
          ),
        ),

        // Shortcuts Row
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildShortcutButton(context, 'Favorites', Icons.favorite_rounded, () {
                // Instantly navigate or select favorites filter
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Songs favorited can be viewed below. Enjoy!'))
                );
              }),
              _buildShortcutButton(context, 'Downloads', Icons.download_done_rounded, () {
                // Open downloaded lists modal/screen
                _showDownloadsDialog();
              }),
              _buildShortcutButton(context, 'History', Icons.history_rounded, () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const RecentlyPlayedScreen()),
                ).then((_) => _loadPlaylists());
              }),
            ],
          ),
        ),

        // Library Section Tabs
        TabBar(
          controller: _tabController,
          indicatorColor: customBranding.accentColor,
          labelColor: customBranding.accentColor,
          unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Playlists'),
          ],
        ),

        // Library List View
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSongsList(customBranding.accentColor),
              _buildAlbumsGrid(),
              _buildPlaylistsList(customBranding.accentColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildShortcutButton(BuildContext context, String label, IconData icon, VoidCallback onTap) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 14),
          decoration: AppTheme.glassDecoration(
            context: context,
            opacity: isDark ? 0.05 : 0.04,
            radius: 16,
          ),
          child: Column(
            children: [
              Icon(icon, color: customBranding.accentColor, size: 24),
              const SizedBox(height: 6),
              Text(
                label,
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSongsList(Color accentColor) {
    final tracks = Track.mockTracks;

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96, top: 12),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isFav = StorageService.isFavorite('trackIds', track.id);
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Image.network(
                  track.artworkUrl,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                ),
              ),
              title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text(track.artist),
              trailing: IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? Colors.redAccent : Colors.grey,
                  size: 20,
                ),
                onPressed: () async {
                  await StorageService.toggleFavorite('trackIds', track.id);
                  setState(() {});
                },
              ),
              onTap: () {
                notifier.playTrack(track);
              },
            );
          },
        );
      },
    );
  }

  Widget _buildAlbumsGrid() {
    final tracks = Track.mockTracks;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GridView.builder(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 96),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 16,
        mainAxisSpacing: 16,
        childAspectRatio: 0.8,
      ),
      itemCount: 4,
      itemBuilder: (context, index) {
        final track = tracks[index % tracks.length];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(isDark ? 0.3 : 0.1),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
                  child: Image.network(
                    track.artworkUrl,
                    width: double.infinity,
                    fit: BoxFit.cover,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              track.album,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
            ),
            Text(
              track.artist,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(fontSize: 11),
            ),
          ],
        );
      },
    );
  }

  Widget _buildPlaylistsList(Color accentColor) {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Your Playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14, color: Colors.grey)),
              TextButton.icon(
                onPressed: _showCreatePlaylistBottomSheet,
                icon: Icon(Icons.add_rounded, size: 16, color: accentColor),
                label: Text('Create', style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        ),
        Expanded(
          child: _playlists.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.playlist_add_rounded, size: 48, color: accentColor.withOpacity(0.4)),
                      const SizedBox(height: 8),
                      const Text('No custom playlists yet.', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: _playlists.length,
                  itemBuilder: (context, index) {
                    final playlist = _playlists[index];
                    final List trackIds = playlist['trackIds'] ?? [];
                    return ListTile(
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                      leading: Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: accentColor.withOpacity(0.12),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 28),
                      ),
                      title: Text(playlist['name'] ?? '', style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text('${trackIds.length} songs'),
                      trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => PlaylistDetailScreen(playlistIndex: index),
                          ),
                        ).then((_) => _loadPlaylists());
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showDownloadsDialog() {
    final downloaded = DownloadService.instance.getDownloadedTracksList();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Downloaded Tracks (Offline)', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 12),
              Expanded(
                child: downloaded.isEmpty
                    ? const Center(child: Text('No downloaded tracks yet.', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: downloaded.length,
                        itemBuilder: (context, index) {
                          final track = downloaded[index];
                          return ListTile(
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(6),
                              child: Image.network(track.artworkUrl, width: 40, height: 40, fit: BoxFit.cover),
                            ),
                            title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                            subtitle: Text(track.artist, style: const TextStyle(fontSize: 12)),
                            trailing: IconButton(
                              icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                              onPressed: () async {
                                await DownloadService.instance.deleteDownload(track.id);
                                Navigator.pop(context);
                                _showDownloadsDialog();
                              },
                            ),
                            onTap: () {
                              ref.read(playbackProvider.notifier).playTrack(track);
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
}
