import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../widgets/app_artwork_image.dart';
import '../../themes/app_theme.dart';

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
              artworkUrl: '',
              audioUrl: '',
              genre: '',
            ),
          );
          _playlistTracks.add(track);
        }
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

  void _showDeletePlaylistDialog(Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Delete Playlist?', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
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
                  Navigator.pop(context);
                  Navigator.pop(context);
                }
              },
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
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(_playlist['name'] ?? 'Playlist', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit')),
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
                    color: accentColor,
                  ),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.download_for_offline_rounded),
              tooltip: 'Download Playlist',
              onPressed: () => _downloadPlaylist(accentColor),
            ),
          IconButton(
            icon: const Icon(Icons.add_circle_outline_rounded),
            tooltip: 'Add Songs',
            onPressed: _showAddSongsBottomSheet,
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent),
            tooltip: 'Delete Playlist',
            onPressed: () => _showDeletePlaylistDialog(accentColor),
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
                      const SizedBox(height: 4),
                      Text(
                        _playlist['description'] ?? 'Personalized collection',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12, color: Colors.grey, height: 1.3),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${_playlistTracks.length} Songs',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: accentColor),
                        ),
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
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
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
