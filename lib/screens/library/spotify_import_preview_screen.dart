import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/music_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/import/spotify_import_service.dart';
import '../../services/storage/storage_service.dart';
import '../../themes/app_theme.dart';

class SpotifyImportPreviewScreen extends ConsumerStatefulWidget {
  final SpotifyPlaylistPreview preview;

  const SpotifyImportPreviewScreen({
    super.key,
    required this.preview,
  });

  @override
  ConsumerState<SpotifyImportPreviewScreen> createState() => _SpotifyImportPreviewScreenState();
}

class _SpotifyImportPreviewScreenState extends ConsumerState<SpotifyImportPreviewScreen> {
  bool _isResolving = false;
  int _currentResolvingIndex = 0;
  String _currentTrackTitle = '';
  String _currentTrackArtist = '';
  double _progress = 0.0;

  Future<void> _startImportFlow() async {
    setState(() {
      _isResolving = true;
      _currentResolvingIndex = 0;
      _progress = 0.0;
    });

    final total = widget.preview.tracks.length;
    final List<Track> resolvedTracks = [];
    final List<SpotifyTrackPreview> unresolvedTracks = [];

    final musicSource = ref.read(musicSourceProvider);

    for (int i = 0; i < total; i++) {
      final spotifyTrack = widget.preview.tracks[i];
      
      setState(() {
        _currentResolvingIndex = i + 1;
        _currentTrackTitle = spotifyTrack.title;
        _currentTrackArtist = spotifyTrack.artist;
        _progress = (i + 1) / total;
      });

      // Query format: "Track Name Artist Name"
      final query = "${spotifyTrack.title} ${spotifyTrack.artist}";
      try {
        final results = await musicSource.searchTracks(query);
        
        if (results.isNotEmpty) {
          // Take the first result as the closest match
          resolvedTracks.add(results.first);
        } else {
          // Try a fallback search with just the track title if it didn't match with artist name
          final fallbackResults = await musicSource.searchTracks(spotifyTrack.title);
          if (fallbackResults.isNotEmpty) {
            resolvedTracks.add(fallbackResults.first);
          } else {
            unresolvedTracks.add(spotifyTrack);
          }
        }
      } catch (e) {
        print('Error resolving track "$query": $e');
        unresolvedTracks.add(spotifyTrack);
      }
    }

    // Save the resolved tracks as a native playlist
    final playlistId = 'spotify_${widget.preview.id}_${DateTime.now().millisecondsSinceEpoch}';
    final playlist = {
      'id': playlistId,
      'name': widget.preview.name,
      'description': widget.preview.description.isNotEmpty 
          ? widget.preview.description 
          : 'Imported from Spotify (Playlist ID: ${widget.preview.id})',
      'trackIds': resolvedTracks.map((t) => t.id).toList(),
      'tracks': resolvedTracks.map((t) => {
        'id': t.id,
        'title': t.title,
        'artist': t.artist,
        'album': t.album,
        'duration': t.duration,
        'artworkUrl': t.artworkUrl,
        'audioUrl': t.audioUrl,
        'genre': t.genre,
      }).toList(),
      'source': 'spotify',
      'spotifyId': widget.preview.id,
      'matchStats': {
        'total': total,
        'resolved': resolvedTracks.length,
        'unresolved': unresolvedTracks.length,
      },
      'unresolvedTracks': unresolvedTracks.map((t) => t.toJson()).toList(),
    };

    final savedPlaylists = StorageService.getPlaylists();
    
    // Find index of existing playlist with the same Spotify ID or same name & source
    final existingIndex = savedPlaylists.indexWhere((p) =>
        p['spotifyId'] == widget.preview.id ||
        (p['name'] == widget.preview.name && p['source'] == 'spotify'));

    if (existingIndex != -1) {
      // Overwrite/update the existing one
      savedPlaylists[existingIndex] = playlist;
      print('[SPOTIFY-IMPORT] Overwriting existing playlist at index $existingIndex');
    } else {
      // Append if it is a new playlist
      savedPlaylists.add(playlist);
      print('[SPOTIFY-IMPORT] Creating new playlist');
    }

    await StorageService.savePlaylists(savedPlaylists);

    setState(() {
      _isResolving = false;
    });

    if (context.mounted) {
      if (unresolvedTracks.isEmpty) {
        // Show 100% success snackbar and go back
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Successfully imported all ${resolvedTracks.length} tracks!'),
            backgroundColor: Colors.green.shade800,
          ),
        );
        Navigator.pop(context);
      } else {
        // Show summary dialog listing unresolved tracks
        _showImportSummaryDialog(resolvedTracks.length, unresolvedTracks);
      }
    }
  }

  void _showImportSummaryDialog(int resolvedCount, List<SpotifyTrackPreview> unresolved) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF161616) : const Color(0xFFFAF8F5),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Text(
            'Import Summary',
            style: const TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Imported $resolvedCount tracks successfully.',
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '${unresolved.length} tracks could not be resolved against the music library source:',
                  style: const TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: Container(
                    constraints: const BoxConstraints(maxHeight: 200),
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white.withOpacity(0.04) : Colors.black.withOpacity(0.03),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      padding: const EdgeInsets.all(8),
                      itemCount: unresolved.length,
                      itemBuilder: (context, index) {
                        final item = unresolved[index];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Text(
                            '• ${item.title} - ${item.artist}',
                            style: const TextStyle(fontSize: 12, color: Colors.redAccent),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context); // Close dialog
                Navigator.pop(context); // Pop preview screen back to library
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: ref.read(customizationProvider).accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              child: const Text('Done', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customization = ref.watch(customizationProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Spotify Import Preview', style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18)),
        elevation: 0,
        backgroundColor: Colors.transparent,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: _isResolving ? null : () => Navigator.pop(context),
        ),
      ),
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // Background Gradient
          Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: isDark
                    ? [const Color(0xFF1E3A1E).withOpacity(0.4), const Color(0xFF121212)]
                    : [const Color(0xFFE8F5E9), const Color(0xFFFAF8F5)],
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Header Details card
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Row(
                    children: [
                      // Playlist Artwork
                      ClipRRect(
                        borderRadius: BorderRadius.circular(16),
                        child: widget.preview.coverUrl.isNotEmpty
                            ? Image.network(
                                widget.preview.coverUrl,
                                width: 110,
                                height: 110,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => _buildPlaceholderArtwork(customization.accentColor),
                              )
                            : _buildPlaceholderArtwork(customization.accentColor),
                      ),
                      const SizedBox(width: 20),
                      // Meta details
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.preview.name,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'Outfit',
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'By ${widget.preview.creator}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              decoration: BoxDecoration(
                                color: customization.accentColor.withOpacity(0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(
                                '${widget.preview.totalTracks} Tracks Available',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: customization.accentColor,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const Divider(height: 1, indent: 24, endIndent: 24),

                // Tracks list title
                Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8),
                  child: Row(
                    children: [
                      const Text(
                        'TRACKS TO IMPORT',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey,
                          letterSpacing: 1.2,
                        ),
                      ),
                      const Spacer(),
                      if (widget.preview.totalTracks > 100)
                        const Text(
                          '(Capped at 100)',
                          style: TextStyle(fontSize: 11, color: Colors.redAccent, fontWeight: FontWeight.bold),
                        ),
                    ],
                  ),
                ),

                // Tracklist scrollable view
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.only(left: 12, right: 12, bottom: 100),
                    itemCount: widget.preview.tracks.length,
                    itemBuilder: (context, index) {
                      final track = widget.preview.tracks[index];
                      return ListTile(
                        leading: SizedBox(
                          width: 32,
                          child: Center(
                            child: Text(
                              '${index + 1}',
                              style: const TextStyle(
                                color: Colors.grey,
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        ),
                        title: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          track.artist,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
          ),

          // Sticky Bottom Import Button
          if (!_isResolving)
            Align(
              alignment: Alignment.bottomCenter,
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      isDark ? const Color(0xFF121212) : const Color(0xFFFAF8F5),
                      isDark ? const Color(0xFF121212).withOpacity(0.0) : const Color(0xFFFAF8F5).withOpacity(0.0),
                    ],
                  ),
                ),
                child: SafeArea(
                  top: false,
                  child: ElevatedButton.icon(
                    onPressed: _startImportFlow,
                    icon: const Icon(Icons.import_export_rounded, color: Colors.black),
                    label: const Text(
                      'Import Playlist',
                      style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit'),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customization.accentColor,
                      minimumSize: const Size(double.infinity, 52),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 4,
                      shadowColor: customization.accentColor.withOpacity(0.4),
                    ),
                  ),
                ),
              ),
            ),

          // Resolution Progress Overlay
          if (_isResolving)
            Container(
              color: Colors.black87,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Container(
                    padding: const EdgeInsets.all(24),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1A1A1A) : const Color(0xFFFAF8F5),
                      borderRadius: BorderRadius.circular(24),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.4),
                          blurRadius: 20,
                        ),
                      ],
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Resolving Playlist Tracks',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'Outfit',
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Matching songs against the audio source library.',
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 24),
                        // Linear progress indicator
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: _progress,
                            minHeight: 8,
                            backgroundColor: Colors.grey.withOpacity(0.2),
                            valueColor: AlwaysStoppedAnimation<Color>(customization.accentColor),
                          ),
                        ),
                        const SizedBox(height: 16),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'Track $_currentResolvingIndex of ${widget.preview.tracks.length}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                            ),
                            Text(
                              '${(_progress * 100).round()}%',
                              style: TextStyle(fontWeight: FontWeight.bold, color: customization.accentColor, fontSize: 13),
                            ),
                          ],
                        ),
                        const SizedBox(height: 16),
                        const Divider(),
                        const SizedBox(height: 12),
                        Text(
                          'Current song:',
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          _currentTrackTitle,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        Text(
                          _currentTrackArtist,
                          textAlign: TextAlign.center,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPlaceholderArtwork(Color accentColor) {
    return Container(
      width: 110,
      height: 110,
      color: accentColor.withOpacity(0.12),
      child: Icon(Icons.music_note_rounded, size: 40, color: accentColor),
    );
  }
}
