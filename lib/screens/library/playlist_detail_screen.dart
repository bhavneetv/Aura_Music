import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';

class PlaylistDetailScreen extends ConsumerStatefulWidget {
  final int playlistIndex;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistIndex,
  });

  @override
  ConsumerState<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends ConsumerState<PlaylistDetailScreen> {
  late Map<String, dynamic> _playlist;
  List<Track> _playlistTracks = [];
  String _searchQuery = '';
  bool _isDownloadingPlaylist = false;
  double _downloadProgress = 0.0;
  bool _isPlaylistDownloaded = false;

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

  @override
  void initState() {
    super.initState();
    _loadPlaylistData();
  }

  void _loadPlaylistData() {
    final playlists = StorageService.getPlaylists();
    if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      _playlist = playlists[widget.playlistIndex];
      final List rawTracks = _playlist['tracks'] ?? [];
      
      _playlistTracks = [];
      if (rawTracks.isNotEmpty) {
        for (final item in rawTracks) {
          if (item is Map) {
            _playlistTracks.add(Track(
              id: item['id']?.toString() ?? '',
              title: item['title']?.toString() ?? 'Unknown Track',
              artist: item['artist']?.toString() ?? 'Unknown Artist',
              album: item['album']?.toString() ?? 'Single',
              duration: item['duration']?.toString() ?? '3:30',
              artworkUrl: item['artworkUrl']?.toString() ?? item['coverUrl']?.toString() ?? '',
              audioUrl: item['audioUrl']?.toString() ?? item['streamUrl']?.toString() ?? '',
              genre: item['genre']?.toString() ?? '',
            ));
          }
        }
      } else {
        // Fallback for old playlists using trackIds
        final List rawIds = _playlist['trackIds'] ?? [];
        for (final id in rawIds) {
          final track = Track.mockTracks.firstWhere(
            (t) => t.id == id.toString(),
            orElse: () => Track(
              id: id.toString(),
              title: 'Track $id',
              artist: 'Unknown Artist',
              album: 'Unknown Album',
              duration: '3:00',
              artworkUrl: 'https://images.unsplash.com/photo-1514525253161-7a46d19cd819?w=150',
              audioUrl: '',
              genre: '',
            ),
          );
          _playlistTracks.add(track);
        }
      }
    }
  }

  void _addSongToPlaylist(Track track) async {
    final playlists = StorageService.getPlaylists();
    if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      final List rawTracks = List.from(playlists[widget.playlistIndex]['tracks'] ?? []);
      final trackMap = {
        'id': track.id,
        'title': track.title,
        'artist': track.artist,
        'album': track.album,
        'duration': track.duration,
        'artworkUrl': track.artworkUrl,
        'audioUrl': track.audioUrl,
        'genre': track.genre,
      };
      
      // Prevent duplicates by track ID
      if (!rawTracks.any((t) => t is Map && t['id'] == track.id)) {
        rawTracks.add(trackMap);
        playlists[widget.playlistIndex]['tracks'] = rawTracks;
        await StorageService.savePlaylists(playlists);
        setState(() {
          _loadPlaylistData();
        });
      }
    }
  }

  void _removeSongFromPlaylist(int index) async {
    final playlists = StorageService.getPlaylists();
    if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      final List rawTracks = List.from(playlists[widget.playlistIndex]['tracks'] ?? []);
      if (index >= 0 && index < rawTracks.length) {
        rawTracks.removeAt(index);
        playlists[widget.playlistIndex]['tracks'] = rawTracks;
        await StorageService.savePlaylists(playlists);
        setState(() {
          _loadPlaylistData();
        });
      }
    }
  }

  void _reorderPlaylistSongs(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex -= 1;
    final playlists = StorageService.getPlaylists();
    if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
      final List rawTracks = List.from(playlists[widget.playlistIndex]['tracks'] ?? []);
      if (oldIndex >= 0 && oldIndex < rawTracks.length) {
        final item = rawTracks.removeAt(oldIndex);
        rawTracks.insert(newIndex, item);
        playlists[widget.playlistIndex]['tracks'] = rawTracks;
        await StorageService.savePlaylists(playlists);
        setState(() {
          _loadPlaylistData();
        });
      }
    }
  }

  void _showAddSongsBottomSheet() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      builder: (context) {
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: Track.mockTracks.length,
          itemBuilder: (context, index) {
            final track = Track.mockTracks[index];
            return ListTile(
              leading: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.network(track.artworkUrl, width: 40, height: 40, fit: BoxFit.cover),
              ),
              title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
              subtitle: Text(track.artist, style: const TextStyle(fontSize: 12)),
              trailing: const Icon(Icons.add_circle_outline_rounded, color: Colors.grey),
              onTap: () {
                _addSongToPlaylist(track);
                Navigator.pop(context);
              },
            );
          },
        );
      },
    );
  }

  void _showDeletePlaylistDialog(Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161616) : const Color(0xFFFAF8F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Playlist', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          content: Text('Are you sure you want to delete "${_playlist['name']}"? This action cannot be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                final playlists = StorageService.getPlaylists();
                if (widget.playlistIndex >= 0 && widget.playlistIndex < playlists.length) {
                  playlists.removeAt(widget.playlistIndex);
                  await StorageService.savePlaylists(playlists);
                }
                if (mounted) {
                  Navigator.pop(context); // Close dialog
                  Navigator.pop(context); // Pop detail screen back to library
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Delete', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);
    final playbackNotifier = ref.read(playbackProvider.notifier);

    // Apply search filter if active
    final filteredTracks = _playlistTracks.where((track) {
      final query = _searchQuery.toLowerCase();
      return track.title.toLowerCase().contains(query) ||
             track.artist.toLowerCase().contains(query);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_playlist['name'] ?? 'Playlist Detail', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          if (_isPlaylistDownloaded)
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12),
              child: Icon(Icons.check_circle_rounded, color: Colors.greenAccent, size: 24),
            )
          else if (_isDownloadingPlaylist)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    value: _downloadProgress > 0 ? _downloadProgress : null,
                    strokeWidth: 2.5,
                    color: customBranding.accentColor,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded),
              tooltip: 'Download Playlist',
              onPressed: () => _downloadPlaylist(customBranding.accentColor),
            ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: 'Delete Playlist',
            onPressed: () => _showDeletePlaylistDialog(customBranding.accentColor),
          ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add Songs',
            onPressed: _showAddSongsBottomSheet,
          ),
        ],
      ),
      body: Column(
        children: [
          // Cover Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                // Playlist Cover
                Container(
                  width: 100,
                  height: 100,
                  decoration: BoxDecoration(
                    color: customBranding.accentColor.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Icon(Icons.playlist_play_rounded, color: customBranding.accentColor, size: 48),
                ),
                const SizedBox(width: 20),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _playlist['name'] ?? 'Custom Playlist',
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 20),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _playlist['description'] ?? 'No description provided.',
                        style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.4),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '${_playlistTracks.length} Songs',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: customBranding.accentColor),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Search Field inside playlist
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: TextField(
              onChanged: (val) {
                setState(() {
                  _searchQuery = val;
                });
              },
              decoration: InputDecoration(
                hintText: 'Search songs in playlist...',
                hintStyle: const TextStyle(fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded, size: 20, color: Colors.grey),
                filled: true,
                fillColor: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.04),
                contentPadding: const EdgeInsets.symmetric(vertical: 8),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
            ),
          ),

          // Actions: Play & Shuffle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: () {
                      if (_playlistTracks.isNotEmpty) {
                        playbackNotifier.playCustomQueue(_playlistTracks, initialIndex: 0);
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customBranding.accentColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
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
                      side: BorderSide(color: customBranding.accentColor),
                      foregroundColor: customBranding.accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Songs List (Reorderable)
          Expanded(
            child: filteredTracks.isEmpty
                ? Center(
                    child: Text(
                      _searchQuery.isEmpty ? 'No songs in this playlist.' : 'No matching songs found.',
                      style: const TextStyle(color: Colors.grey),
                    ),
                  )
                : ReorderableListView.builder(
                    itemCount: filteredTracks.length,
                    onReorder: _reorderPlaylistSongs,
                    itemBuilder: (context, index) {
                      final track = filteredTracks[index];
                      return KeyedSubtree(
                        key: ValueKey(track.id),
                        child: ListTile(
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle_rounded, color: Colors.grey, size: 18),
                              const SizedBox(width: 8),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(track.artworkUrl, width: 40, height: 40, fit: BoxFit.cover),
                              ),
                            ],
                          ),
                          title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          subtitle: Text(track.artist, style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.grey),
                            onPressed: () => _removeSongFromPlaylist(index),
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
