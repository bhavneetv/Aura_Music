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
import '../../services/sharing/playlist_link_share_service.dart';
import '../sharing/remote_link_share_modal.dart';

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
    _tabController = TabController(length: 4, vsync: this);
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
        'description': desc.isNotEmpty ? desc : 'A custom playlist',
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
    final accentColor = ref.read(customizationProvider).accentColor;

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
            color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
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
              const SizedBox(height: 20),
              const Text('Create Custom Playlist 🎵', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
              const SizedBox(height: 16),
              TextField(
                controller: _playlistNameController,
                decoration: InputDecoration(
                  labelText: 'Playlist Title',
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor, width: 1.5)),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _playlistDescController,
                decoration: InputDecoration(
                  labelText: 'Description (Optional)',
                  filled: true,
                  fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor, width: 1.5)),
                ),
              ),
              const SizedBox(height: 24),
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
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text('Create Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
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
                color: isDark ? const Color(0xFF1B1B1E) : Colors.white,
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
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
                  const SizedBox(height: 20),
                  const Text(
                    'Import Playlist Link / Code 🎧', 
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Paste an Aura shared link/code or Spotify playlist link below to import.',
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: _spotifyUrlController,
                    enabled: !isLoading,
                    decoration: InputDecoration(
                      labelText: 'Aura Shared Link or Spotify URL',
                      errorText: inlineError,
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor, width: 1.5)),
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
                  const SizedBox(height: 24),
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
                              
                              // Check if stateless Aura link or ultra-short relay code
                              final decodedAura = await PlaylistLinkShareService.instance.decodeShareableLinkAsync(url);
                              if (decodedAura != null) {
                                final newPl = {
                                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                  'name': decodedAura.title,
                                  'description': decodedAura.description.isNotEmpty ? decodedAura.description : 'Imported via Link',
                                  'trackIds': decodedAura.tracks.map((t) => t.id).toList(),
                                  'tracks': decodedAura.tracks.map((t) => {
                                    'id': t.id,
                                    'title': t.title,
                                    'artist': t.artist,
                                    'album': t.album,
                                    'duration': t.duration,
                                    'artworkUrl': t.artworkUrl,
                                    'audioUrl': t.audioUrl,
                                    'genre': t.genre,
                                  }).toList(),
                                };
                                final playlists = StorageService.getPlaylists();
                                playlists.insert(0, newPl);
                                await StorageService.savePlaylists(playlists);

                                Navigator.pop(context);
                                _spotifyUrlController.clear();
                                _loadPlaylists();

                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text('Imported "${decodedAura.title}" with ${decodedAura.tracks.length} tracks! 🎵'),
                                    backgroundColor: accentColor,
                                  ),
                                );
                                return;
                              }

                              final playlistId = SpotifyImportService.instance.validateAndExtractPlaylistId(url);
                              
                              if (playlistId == null) {
                                setModalState(() {
                                  inlineError = 'Please enter a valid Aura shared link or Spotify playlist URL.';
                                });
                                return;
                              }

                              setModalState(() {
                                isLoading = true;
                                inlineError = null;
                              });

                              try {
                                final preview = await SpotifyImportService.instance.fetchPlaylistPreview(url);
                                Navigator.pop(context);
                                _spotifyUrlController.clear();
                                
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
                          disabledBackgroundColor: accentColor.withValues(alpha: 0.3),
                          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
    final accentColor = customBranding.accentColor;

    final favTracks = StorageService.getFavoriteTracks();
    final downloadedTracks = DownloadService.instance.getDownloadedTracksList();
    final historyList = StorageService.getListeningHistory();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Header & Title Bar
        Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: MediaQuery.of(context).padding.top + 8, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Your Library 📚',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${_playlists.length} Playlists • ${favTracks.length} Liked • ${downloadedTracks.length} Offline',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.add_rounded, color: accentColor, size: 20),
                    ),
                    tooltip: 'Create Playlist',
                    onPressed: _showCreatePlaylistBottomSheet,
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.import_export_rounded, color: accentColor, size: 20),
                    ),
                    tooltip: 'Import Spotify Playlist',
                    onPressed: _showImportPlaylistBottomSheet,
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Quick Action Cards Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            children: [
              _buildLibraryShortcutCard(
                context,
                'Favorites',
                '${favTracks.length} Tracks',
                Icons.favorite_rounded,
                accentColor,
                () => _tabController.animateTo(1),
              ),
              _buildLibraryShortcutCard(
                context,
                'Offline',
                '${downloadedTracks.length} Saved',
                Icons.download_done_rounded,
                accentColor,
                () => _tabController.animateTo(3),
              ),
              _buildLibraryShortcutCard(
                context,
                'History',
                '${historyList.length} Played',
                Icons.history_rounded,
                accentColor,
                () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const RecentlyPlayedScreen()),
                  ).then((_) => _loadPlaylists());
                },
              ),
            ],
          ),
        ),

        // 3. Floating Segmented Tab Selector
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 6),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(18),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.black,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Playlists'),
              Tab(text: 'Liked Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Downloaded'),
            ],
          ),
        ),

        // 4. Main Tab Content Area
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildPlaylistsTab(accentColor),
              _buildLikedSongsTab(favTracks, accentColor),
              _buildAlbumsTab(favTracks, accentColor),
              _buildDownloadedTab(downloadedTracks, accentColor),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildLibraryShortcutCard(
    BuildContext context,
    String title,
    String subtitle,
    IconData icon,
    Color accentColor,
    VoidCallback onTap,
  ) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 4),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 10),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: accentColor.withValues(alpha: 0.2)),
          ),
          child: Column(
            children: [
              Icon(icon, color: accentColor, size: 22),
              const SizedBox(height: 6),
              Text(title, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 10, color: Colors.grey)),
            ],
          ),
        ),
      ),
    );
  }

  // Playlists Tab
  Widget _buildPlaylistsTab(Color accentColor) {
    if (_playlists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.playlist_add_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No custom playlists created yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Tap "+" in top right or import from Spotify!', style: TextStyle(color: Colors.grey, fontSize: 13)),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: _showCreatePlaylistBottomSheet,
              icon: const Icon(Icons.add_rounded, color: Colors.black, size: 18),
              label: const Text('Create Playlist', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(backgroundColor: accentColor),
            ),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 150, top: 10, left: 20, right: 20),
      itemCount: _playlists.length,
      itemBuilder: (context, index) {
        final playlist = _playlists[index];
        final List rawTracks = playlist['tracks'] as List? ?? [];
        final List trackIds = playlist['trackIds'] as List? ?? [];
        final int songCount = rawTracks.isNotEmpty ? rawTracks.length : trackIds.length;

        return Card(
          margin: const EdgeInsets.only(bottom: 10),
          color: isDark ? const Color(0xFF1E1E22) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          child: ListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            leading: Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                color: accentColor.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(Icons.playlist_play_rounded, color: accentColor, size: 30),
            ),
            title: Text(playlist['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            subtitle: Text('$songCount songs • ${playlist['description'] ?? 'Custom playlist'}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  icon: Icon(Icons.share_rounded, color: accentColor, size: 20),
                  tooltip: 'Share Playlist via Nearby Share',
                  onPressed: () {
                    final List rawTracks = playlist['tracks'] ?? [];
                    final List<Track> playlistTracks = [];
                    if (rawTracks.isNotEmpty) {
                      for (final item in rawTracks) {
                        if (item is Map) {
                          playlistTracks.add(Track(
                            id: item['id']?.toString() ?? '',
                            title: item['title']?.toString() ?? 'Track',
                            artist: item['artist']?.toString() ?? 'Unknown Artist',
                            album: item['album']?.toString() ?? 'Album',
                            duration: item['duration']?.toString() ?? '3:30',
                            artworkUrl: item['artworkUrl']?.toString() ?? '',
                            audioUrl: item['audioUrl']?.toString() ?? '',
                            genre: item['genre']?.toString() ?? '',
                          ));
                        }
                      }
                    }
                    ShareOptionsModal.show(
                      context,
                      tracks: playlistTracks,
                      title: playlist['name']?.toString() ?? 'Custom Playlist',
                      description: playlist['description']?.toString() ?? '',
                    );
                  },
                ),
                const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              ],
            ),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => PlaylistDetailScreen(playlistIndex: index),
                ),
              ).then((_) => _loadPlaylists());
            },
          ),
        );
      },
    );
  }

  // Liked Songs Tab
  Widget _buildLikedSongsTab(List<Track> tracks, Color accentColor) {
    if (tracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.favorite_border_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No favorited songs yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Heart any playing song to save it here!', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 8),
          itemCount: tracks.length,
          itemBuilder: (context, index) {
            final track = tracks[index];
            final isFav = StorageService.isFavorite('trackIds', track.id);
            
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
              leading: AppArtworkImage(
                artworkUrl: track.artworkUrl,
                trackId: track.id,
                width: 48,
                height: 48,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(10),
              ),
              title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text('${track.artist} • ${track.album}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
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
                  IconButton(
                    icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                    onPressed: () => notifier.playTrack(track),
                  ),
                ],
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

  // Albums Tab
  Widget _buildAlbumsTab(List<Track> tracks, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<String, List<Track>> albumsMap = {};
    for (final track in tracks) {
      final albumName = track.album.trim().isNotEmpty ? track.album.trim() : 'Singles';
      albumsMap.putIfAbsent(albumName, () => []).add(track);
    }

    if (albumsMap.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.album_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No saved albums found', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.grey)),
          ],
        ),
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.only(left: 20, right: 20, top: 14, bottom: 150),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
        childAspectRatio: 0.82,
      ),
      itemCount: albumsMap.keys.length,
      itemBuilder: (context, index) {
        final albumName = albumsMap.keys.elementAt(index);
        final albumTracks = albumsMap[albumName]!;
        final firstTrack = albumTracks.first;

        return Consumer(
          builder: (context, ref, child) {
            return GestureDetector(
              onTap: () {
                ref.read(playbackProvider.notifier).playCustomQueue(albumTracks, initialIndex: 0);
              },
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1F) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AppArtworkImage(
                          artworkUrl: firstTrack.artworkUrl,
                          trackId: firstTrack.id,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(albumName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${firstTrack.artist} • ${albumTracks.length} tracks', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // Downloaded Offline Tab
  Widget _buildDownloadedTab(List<Track> downloadedTracks, Color accentColor) {
    final downloadedPlaylists = StorageService.getDownloadedPlaylists();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (downloadedTracks.isEmpty && downloadedPlaylists.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
            const SizedBox(height: 12),
            const Text('No offline downloads yet', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
            const SizedBox(height: 6),
            const Text('Download songs to listen offline anytime!', style: TextStyle(color: Colors.grey, fontSize: 13)),
          ],
        ),
      );
    }

    return ListView(
      padding: const EdgeInsets.only(bottom: 150, top: 12, left: 20, right: 20),
      children: [
        if (downloadedPlaylists.isNotEmpty) ...[
          const Text('Downloaded Playlists', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit')),
          const SizedBox(height: 10),
          ...downloadedPlaylists.map((pl) {
            final List rawTracks = pl['tracks'] ?? [];
            return Card(
              margin: const EdgeInsets.only(bottom: 10),
              color: isDark ? const Color(0xFF1E1E22) : Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              child: ListTile(
                leading: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.download_done_rounded, color: accentColor, size: 24),
                ),
                title: Text(pl['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: Text('${rawTracks.length} songs saved offline'),
                trailing: IconButton(
                  icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                  onPressed: () async {
                    await StorageService.deleteDownloadedPlaylist(pl['name']);
                    setState(() {});
                  },
                ),
              ),
            );
          }),
          const SizedBox(height: 16),
        ],

        if (downloadedTracks.isNotEmpty) ...[
          Text('Downloaded Tracks (${downloadedTracks.length})', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit')),
          const SizedBox(height: 10),
          ...downloadedTracks.map((track) {
            return Consumer(
              builder: (context, ref, child) {
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: AppArtworkImage(
                    artworkUrl: track.artworkUrl,
                    trackId: track.id,
                    width: 44,
                    height: 44,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                        onPressed: () {
                          ref.read(playbackProvider.notifier).playTrack(track);
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 20),
                        onPressed: () async {
                          await DownloadService.instance.deleteDownload(track.id);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                  onTap: () {
                    ref.read(playbackProvider.notifier).playTrack(track);
                  },
                );
              },
            );
          }),
        ],
      ],
    );
  }
}
