import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/playback_provider.dart';
import '../providers/customization_provider.dart';
import '../routes/bouncy_player_route.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../services/storage/storage_service.dart';
import 'app_artwork_image.dart';

/// A full-width desktop-grade audio player bar tailored for Web and large desktop screens.
/// Features high-fidelity glassmorphism, instant interactive playback controls,
/// volume slider with mute toggle, progress seekbar, and quick access to queue & lyrics.
class WebPlayerBar extends ConsumerStatefulWidget {
  const WebPlayerBar({super.key});

  @override
  ConsumerState<WebPlayerBar> createState() => _WebPlayerBarState();
}

class _WebPlayerBarState extends ConsumerState<WebPlayerBar> {
  double? _draggedSeekPos;
  double _lastNonZeroVolume = 1.0;

  void _openPlayer() {
    Navigator.push(
      context,
      BouncyPlayerRoute(child: const NowPlayingScreen()),
    );
  }

  void _openLyrics(Track track) {
    _openPlayer();
  }

  Future<void> _toggleFavorite(Track track) async {
    await StorageService.toggleFavoriteTrack(track);
    triggerHaptic(HapticFeedbackType.medium);
    if (mounted) setState(() {});
  }

  void _showAddToPlaylistBottomSheet(BuildContext rootContext, Track track, Color accentColor) {
    final isDark = Theme.of(rootContext).brightness == Brightness.dark;
    final playlists = StorageService.getPlaylists();

    showModalBottomSheet(
      context: rootContext,
      backgroundColor: isDark ? const Color(0xFF141418) : const Color(0xFFF7F7F9),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24)),
      ),
      builder: (sheetContext) {
        final addingIndices = <int>{};
        return StatefulBuilder(
          builder: (modalCtx, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: 420,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add to Playlist',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.add, color: accentColor, size: 18),
                        label: Text('New Playlist', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
                        onPressed: () {
                          Navigator.pop(sheetContext);
                          _showCreatePlaylistDialog(rootContext, track, accentColor);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  if (playlists.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No playlists created yet. Click "New Playlist" above!',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (ctx, index) {
                          final pl = playlists[index];
                          final tracksList = List.from(pl['tracks'] ?? []);
                          final trackIds = List<String>.from(pl['trackIds'] ?? []);
                          final alreadyContains = tracksList.any((t) => t is Map && t['id'] == track.id) || trackIds.contains(track.id);
                          final songCount = tracksList.isNotEmpty ? tracksList.length : trackIds.length;
                          final plName = pl['name']?.toString() ?? 'Playlist ${index + 1}';
                          final isAdding = addingIndices.contains(index);

                          return ListTile(
                            contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            leading: Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(Icons.music_note_rounded, color: accentColor, size: 24),
                            ),
                            title: Text(
                              plName,
                              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15),
                            ),
                            subtitle: Text('$songCount ${songCount == 1 ? "song" : "songs"}'),
                            trailing: IconButton(
                              icon: isAdding
                                  ? SizedBox(
                                      width: 22,
                                      height: 22,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                                      ),
                                    )
                                  : Icon(
                                      alreadyContains ? Icons.check_circle_rounded : Icons.add_circle_outline_rounded,
                                      color: alreadyContains ? Colors.greenAccent.shade400 : accentColor,
                                    ),
                              onPressed: (isAdding || alreadyContains)
                                  ? null
                                  : () async {
                                      setModalState(() {
                                        addingIndices.add(index);
                                      });
                                      try {
                                        final updatedPlaylists = StorageService.getPlaylists();
                                        if (index < updatedPlaylists.length) {
                                          final target = Map<String, dynamic>.from(updatedPlaylists[index]);
                                          final currentTracks = List.from(target['tracks'] ?? []);
                                          final currentIds = List<String>.from(target['trackIds'] ?? []);

                                          currentTracks.add(track.toJson());
                                          currentIds.add(track.id);

                                          target['tracks'] = currentTracks;
                                          target['trackIds'] = currentIds;
                                          updatedPlaylists[index] = target;
                                          await StorageService.savePlaylists(updatedPlaylists);

                                          if (rootContext.mounted) {
                                            ScaffoldMessenger.of(rootContext).showSnackBar(
                                              SnackBar(
                                                content: Text('Added "${track.title}" to $plName ✨'),
                                                duration: const Duration(seconds: 2),
                                                behavior: SnackBarBehavior.floating,
                                              ),
                                            );
                                          }
                                        }
                                      } finally {
                                        setModalState(() {
                                          addingIndices.remove(index);
                                        });
                                      }
                                    },
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
  }

  void _showCreatePlaylistDialog(BuildContext rootContext, Track track, Color accentColor) {
    final textController = TextEditingController();

    showDialog(
      context: rootContext,
      builder: (dialogCtx) => AlertDialog(
        title: const Text('Create New Playlist'),
        content: TextField(
          controller: textController,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Playlist Name',
            focusedBorder: UnderlineInputBorder(
              borderSide: BorderSide(color: accentColor),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogCtx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: accentColor,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              final name = textController.text.trim();
              if (name.isNotEmpty) {
                final playlists = StorageService.getPlaylists();
                final newPlaylist = {
                  'id': DateTime.now().millisecondsSinceEpoch.toString(),
                  'name': name,
                  'createdAt': DateTime.now().toIso8601String(),
                  'tracks': [track.toJson()],
                  'trackIds': [track.id],
                };
                playlists.add(newPlaylist);
                await StorageService.savePlaylists(playlists);

                if (dialogCtx.mounted) Navigator.pop(dialogCtx);
                if (rootContext.mounted) {
                  ScaffoldMessenger.of(rootContext).showSnackBar(
                    SnackBar(
                      content: Text('Created "$name" and added "${track.title}" ✨'),
                      behavior: SnackBarBehavior.floating,
                    ),
                  );
                }
              }
            },
            child: const Text('Create & Add'),
          ),
        ],
      ),
    );
  }

  String _formatTime(Duration duration) {
    final m = duration.inMinutes;
    final s = duration.inSeconds % 60;
    return '$m:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final Track? track = ref.watch(playbackProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playbackProvider.select((s) => s.isPlaying));
    final status = ref.watch(playbackProvider.select((s) => s.status));
    final isShuffle = ref.watch(playbackProvider.select((s) => s.isShuffle));
    final repeatMode = ref.watch(playbackProvider.select((s) => s.repeatMode));
    final currentPos = ref.watch(playbackProvider.select((s) => s.currentPosition));
    final totalDuration = ref.watch(playbackProvider.select((s) => s.totalDuration));
    final volume = ref.watch(playbackProvider.select((s) => s.volume));
    final accentColor = ref.watch(customizationProvider).accentColor;
    final isFav = track != null && StorageService.isFavorite('trackIds', track.id);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(playbackProvider.notifier);

    if (track == null) {
      return const SizedBox(width: double.infinity, height: 0);
    }

    final isLoading = status == PlaybackStatus.loading || status == PlaybackStatus.buffering;
    final double maxSec = totalDuration.inSeconds > 0 ? totalDuration.inSeconds.toDouble() : 1.0;
    final double currentSec = (_draggedSeekPos ?? currentPos.inSeconds.toDouble()).clamp(0.0, maxSec);

    return Container(
      width: double.infinity,
      height: 86,
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF101014) : const Color(0xFFFCFCFD)).withValues(alpha: 0.88),
        border: Border(
          top: BorderSide(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            width: 1.0,
          ),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 18,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                // ─────────────────────────────────────────────────────────────
                // LEFT: TRACK INFO & QUICK ACTIONS
                // ─────────────────────────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: Row(
                    children: [
                      // Artwork Thumbnail with hover/tap to open full player
                      MouseRegion(
                        cursor: SystemMouseCursors.click,
                        child: GestureDetector(
                          onTap: _openPlayer,
                          child: Stack(
                            alignment: Alignment.center,
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(10),
                                child: AppArtworkImage(
                                  artworkUrl: track.artworkUrl,
                                  trackId: track.id,
                                  width: 54,
                                  height: 54,
                                  fit: BoxFit.cover,
                                ),
                              ),
                              Container(
                                width: 54,
                                height: 54,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                                    width: 1,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),

                      // Title & Artist
                      Expanded(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            MouseRegion(
                              cursor: SystemMouseCursors.click,
                              child: GestureDetector(
                                onTap: _openPlayer,
                                child: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    letterSpacing: -0.2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              track.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),

                      // Favorite Button
                      IconButton(
                        tooltip: isFav ? 'Remove from Favorites' : 'Add to Favorites',
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? accentColor : (isDark ? Colors.white54 : Colors.black45),
                          size: 20,
                        ),
                        onPressed: () => _toggleFavorite(track),
                      ),

                      // Add to Playlist Button
                      IconButton(
                        tooltip: 'Add to Playlist',
                        icon: Icon(
                          Icons.playlist_add_rounded,
                          color: isDark ? Colors.white54 : Colors.black45,
                          size: 22,
                        ),
                        onPressed: () => _showAddToPlaylistBottomSheet(context, track, accentColor),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ─────────────────────────────────────────────────────────────
                // CENTER: TRANSPORT CONTROLS & TIMELINE
                // ─────────────────────────────────────────────────────────────
                Expanded(
                  flex: 5,
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      // Button controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          // Shuffle
                          IconButton(
                            tooltip: isShuffle ? 'Shuffle On' : 'Shuffle Off',
                            icon: Icon(
                              Icons.shuffle_rounded,
                              size: 19,
                              color: isShuffle ? accentColor : (isDark ? Colors.white54 : Colors.black45),
                            ),
                            onPressed: () => notifier.toggleShuffle(),
                          ),
                          const SizedBox(width: 6),
                          // Previous
                          IconButton(
                            tooltip: 'Previous Track',
                            icon: Icon(
                              Icons.skip_previous_rounded,
                              size: 26,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            onPressed: () => notifier.previousTrack(),
                          ),
                          const SizedBox(width: 6),
                          // Play/Pause Big Button
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: isDark ? Colors.white : Colors.black,
                              boxShadow: [
                                BoxShadow(
                                  color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                                  blurRadius: 8,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: isLoading
                                ? Center(
                                    child: SizedBox(
                                      width: 18,
                                      height: 18,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2.2,
                                        valueColor: AlwaysStoppedAnimation<Color>(
                                          isDark ? Colors.black : Colors.white,
                                        ),
                                      ),
                                    ),
                                  )
                                : IconButton(
                                    padding: EdgeInsets.zero,
                                    tooltip: isPlaying ? 'Pause' : 'Play',
                                    icon: Icon(
                                      isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: isDark ? Colors.black : Colors.white,
                                      size: 24,
                                    ),
                                    onPressed: () {
                                      notifier.togglePlay();
                                    },
                                  ),
                          ),
                          const SizedBox(width: 6),
                          // Next
                          IconButton(
                            tooltip: 'Next Track',
                            icon: Icon(
                              Icons.skip_next_rounded,
                              size: 26,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                            onPressed: () => notifier.nextTrack(),
                          ),
                          const SizedBox(width: 6),
                          // Repeat
                          IconButton(
                            tooltip: repeatMode == RepeatMode.one
                                ? 'Repeat One'
                                : (repeatMode == RepeatMode.all ? 'Repeat All' : 'Repeat Off'),
                            icon: Icon(
                              repeatMode == RepeatMode.one
                                  ? Icons.repeat_one_rounded
                                  : Icons.repeat_rounded,
                              size: 19,
                              color: repeatMode != RepeatMode.off
                                  ? accentColor
                                  : (isDark ? Colors.white54 : Colors.black45),
                            ),
                            onPressed: () {
                              final next = switch (repeatMode) {
                                RepeatMode.off => RepeatMode.all,
                                RepeatMode.all => RepeatMode.one,
                                RepeatMode.one => RepeatMode.off,
                              };
                              notifier.setRepeatMode(next);
                            },
                          ),
                        ],
                      ),

                      // Seek Bar Row
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        child: Row(
                          children: [
                            Text(
                              _formatTime(Duration(seconds: currentSec.toInt())),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: SliderTheme(
                                data: SliderTheme.of(context).copyWith(
                                  trackHeight: 3.5,
                                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                                  activeTrackColor: accentColor,
                                  inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.12),
                                  thumbColor: accentColor,
                                  overlayColor: accentColor.withValues(alpha: 0.2),
                                ),
                                child: Slider(
                                  value: currentSec,
                                  min: 0.0,
                                  max: maxSec,
                                  onChangeStart: (val) {
                                    setState(() => _draggedSeekPos = val);
                                  },
                                  onChanged: (val) {
                                    setState(() => _draggedSeekPos = val);
                                  },
                                  onChangeEnd: (val) {
                                    notifier.seekToDuration(Duration(seconds: val.toInt()));
                                    setState(() => _draggedSeekPos = null);
                                  },
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              _formatTime(totalDuration),
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white60 : Colors.black54,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(width: 12),

                // ─────────────────────────────────────────────────────────────
                // RIGHT: VOLUME SLIDER & FULLSCREEN / LYRICS EXPAND
                // ─────────────────────────────────────────────────────────────
                Expanded(
                  flex: 3,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      // Lyrics Quick Launcher
                      IconButton(
                        tooltip: 'Lyrics',
                        icon: Icon(
                          Icons.lyrics_rounded,
                          size: 20,
                          color: isDark ? Colors.white60 : Colors.black54,
                        ),
                        onPressed: () => _openLyrics(track),
                      ),

                      const SizedBox(width: 4),

                      // Volume Icon with Mute/Unmute Toggle
                      IconButton(
                        tooltip: volume == 0.0 ? 'Unmute' : 'Mute',
                        icon: Icon(
                          volume == 0.0
                              ? Icons.volume_off_rounded
                              : (volume < 0.5 ? Icons.volume_down_rounded : Icons.volume_up_rounded),
                          size: 21,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        onPressed: () {
                          if (volume > 0.0) {
                            _lastNonZeroVolume = volume;
                            notifier.setVolume(0.0);
                          } else {
                            notifier.setVolume(_lastNonZeroVolume > 0 ? _lastNonZeroVolume : 1.0);
                          }
                        },
                      ),

                      // Volume Slider
                      SizedBox(
                        width: 90,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 3.0,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 5),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 10),
                            activeTrackColor: accentColor,
                            inactiveTrackColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.15),
                            thumbColor: accentColor,
                          ),
                          child: Slider(
                            value: volume.clamp(0.0, 1.0),
                            min: 0.0,
                            max: 1.0,
                            onChanged: (newVolume) {
                              notifier.setVolume(newVolume);
                            },
                          ),
                        ),
                      ),

                      const SizedBox(width: 4),

                      // Expand Fullscreen / Now Playing
                      IconButton(
                        tooltip: 'Expand Full Player',
                        icon: Icon(
                          Icons.open_in_full_rounded,
                          size: 19,
                          color: isDark ? Colors.white70 : Colors.black87,
                        ),
                        onPressed: _openPlayer,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
