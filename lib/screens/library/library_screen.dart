import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../services/import/spotify_import_service.dart';
import '../../themes/app_theme.dart';
import '../../widgets/app_artwork_image.dart';
import 'playlist_detail_screen.dart';
import 'recently_played_screen.dart';
import 'spotify_import_preview_screen.dart';

class LibraryScreen extends ConsumerStatefulWidget {
  const LibraryScreen({super.key});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _playlistNameController = TextEditingController();
  final TextEditingController _playlistDescController = TextEditingController();
  final TextEditingController _spotifyUrlController = TextEditingController();
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
    _spotifyUrlController.dispose();
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

  void _showImportPlaylistBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.read(customizationProvider).accentColor;
    
    String? inlineError;
    bool isLoading = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
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
                  const Text(
                    'Import Spotify Playlist', 
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paste a public Spotify playlist link below to fetch its tracks. Due to public scraping constraints, only the first 100 tracks can be imported.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _spotifyUrlController,
                    enabled: !isLoading,
                    decoration: InputDecoration(
                      labelText: 'Spotify Playlist Link',
                      errorText: inlineError,
                      border: const OutlineInputBorder(),
                      suffixIcon: _spotifyUrlController.text.isNotEmpty 
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded),
                            onPressed: () {
                              _spotifyUrlController.clear();
                              setModalState(() {
                                inlineError = null;
                              });
                            },
                          )
                        : null,
                    ),
                    onChanged: (_) {
                      if (inlineError != null) {
                        setModalState(() {
                          inlineError = null;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TextButton(
                        onPressed: isLoading ? null : () => Navigator.pop(context),
                        child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        onPressed: isLoading 
                          ? null 
                          : () async {
                              final url = _spotifyUrlController.text.trim();
                              final playlistId = SpotifyImportService.instance.validateAndExtractPlaylistId(url);
                              
                              if (playlistId == null) {
                                setModalState(() {
                                  inlineError = 'Please enter a valid Spotify playlist URL.';
                                });
                                return;
                              }

                              setModalState(() {
                                isLoading = true;
                                inlineError = null;
                              });

                              try {
                                final preview = await SpotifyImportService.instance.fetchPlaylistPreview(url);
                                Navigator.pop(context); // Close bottom sheet
                                _spotifyUrlController.clear();
                                
                                // Navigate to the preview screen
                                if (context.mounted) {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) => SpotifyImportPreviewScreen(preview: preview),
                                    ),
                                  ).then((_) => _loadPlaylists());
                                }
                              } catch (e) {
                                setModalState(() {
                                  isLoading = false;
                                  inlineError = e.toString().replaceFirst('Exception: ', '');
                                });
                              }
                            },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: accentColor,
                          disabledBackgroundColor: accentColor.withOpacity(0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: isLoading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Text('Load Preview', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ],
              ),
            );
          }
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
    final tracks = StorageService.getFavoriteTracks();

    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'No favorited songs yet',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            const Text(
              'Double-tap any playing song to add it here!',
              style: TextStyle(color: Colors.grey, fontSize: 13),
            ),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 12),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isFav = StorageService.isFavorite('trackIds', track.id);
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              leading: AppArtworkImage(
                artworkUrl: track.artworkUrl,
                trackId: track.id,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${track.artist} • ${track.album}'),
              trailing: IconButton(
                icon: Icon(
                  isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                  color: isFav ? Colors.redAccent : Colors.grey,
                  size: 20,
                ),
                onPressed: () async {
                  await StorageService.toggleFavoriteTrack(track);
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
    final tracks = StorageService.getFavoriteTracks();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.album_rounded, size: 56, color: Colors.grey.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text(
              'No albums saved',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 150),
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
                child: AppArtworkImage(
                  artworkUrl: track.artworkUrl,
                  trackId: track.id,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(AppTheme.cardRadius),
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
              Row(
                children: [
                  TextButton.icon(
                    onPressed: _showImportPlaylistBottomSheet,
                    icon: Icon(Icons.import_export_rounded, size: 16, color: accentColor),
                    label: Text('Import', style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                  const SizedBox(width: 4),
                  TextButton.icon(
                    onPressed: _showCreatePlaylistBottomSheet,
                    icon: Icon(Icons.add_rounded, size: 16, color: accentColor),
                    label: Text('Create', style: TextStyle(color: accentColor, fontSize: 12, fontWeight: FontWeight.bold)),
                  ),
                ],
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
                  padding: const EdgeInsets.only(bottom: 150),
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
    final downloadedTracks = DownloadService.instance.getDownloadedTracksList();
    final downloadedPlaylists = StorageService.getDownloadedPlaylists();
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.read(customizationProvider).accentColor;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      builder: (context) {
        return DefaultTabController(
          length: 2,
          child: Container(
            height: MediaQuery.of(context).size.height * 0.75,
            padding: const EdgeInsets.only(top: 16, left: 16, right: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Downloads (Offline)',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit'),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                TabBar(
                  indicatorColor: accentColor,
                  labelColor: accentColor,
                  unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
                  labelStyle: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  tabs: [
                    Tab(text: 'Tracks (${downloadedTracks.length})'),
                    Tab(text: 'Playlists (${downloadedPlaylists.length})'),
                  ],
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: TabBarView(
                    children: [
                      // ── Tab 1: Offline Tracks ──
                      downloadedTracks.isEmpty
                          ? const Center(child: Text('No downloaded tracks yet.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: downloadedTracks.length,
                              itemBuilder: (context, index) {
                                final track = downloadedTracks[index];
                                return ListTile(
                                  leading: AppArtworkImage(
                                    artworkUrl: track.artworkUrl,
                                    trackId: track.id,
                                    width: 40,
                                    height: 40,
                                    fit: BoxFit.cover,
                                    borderRadius: BorderRadius.circular(6),
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

                      // ── Tab 2: Offline Playlists ──
                      downloadedPlaylists.isEmpty
                          ? const Center(child: Text('No downloaded playlists yet.', style: TextStyle(color: Colors.grey)))
                          : ListView.builder(
                              itemCount: downloadedPlaylists.length,
                              itemBuilder: (context, index) {
                                final playlist = downloadedPlaylists[index];
                                final List rawTracks = playlist['tracks'] ?? [];
                                final List<Track> playlistTracks = rawTracks.map((item) {
                                  final m = Map<String, dynamic>.from(item as Map);
                                  return Track(
                                    id: m['id']?.toString() ?? '',
                                    title: m['title']?.toString() ?? 'Track',
                                    artist: m['artist']?.toString() ?? 'Unknown Artist',
                                    album: m['album']?.toString() ?? 'Offline',
                                    duration: m['duration']?.toString() ?? '3:30',
                                    artworkUrl: m['artworkUrl']?.toString() ?? '',
                                    audioUrl: m['audioUrl']?.toString() ?? '',
                                    genre: m['genre']?.toString() ?? '',
                                  );
                                }).toList();

                                return ListTile(
                                  leading: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: accentColor.withOpacity(0.15),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Icon(Icons.download_done_rounded, color: accentColor, size: 24),
                                  ),
                                  title: Text(playlist['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                                  subtitle: Text('${playlistTracks.length} songs downloaded offline'),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 30),
                                        onPressed: () {
                                          if (playlistTracks.isNotEmpty) {
                                            ref.read(playbackProvider.notifier).playCustomQueue(playlistTracks, initialIndex: 0);
                                            Navigator.pop(context);
                                          }
                                        },
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                                        onPressed: () async {
                                          await StorageService.deleteDownloadedPlaylist(playlist['name']);
                                          Navigator.pop(context);
                                          _showDownloadsDialog();
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
