import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';
import '../../themes/app_theme.dart';

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackProvider.notifier).ensureUpcomingRecommendations();
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final upcomingStart = (state.currentIndex >= 0 && state.currentIndex < state.queue.length)
        ? state.currentIndex + 1
        : 0;
    final upcomingTracks = state.queue.skip(upcomingStart).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 1. Page Title & Header Actions
        Padding(
          padding: const EdgeInsets.only(left: 20, right: 12, top: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Play Queue 🎵',
                    style: TextStyle(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '${state.queue.length} Songs • Drag handles to reorder',
                    style: TextStyle(fontSize: 12, color: Colors.grey.shade500, fontWeight: FontWeight.w500),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.playlist_add_check_rounded, color: accentColor, size: 20),
                    ),
                    tooltip: 'Save Queue as Playlist',
                    onPressed: () => _showSaveQueueAsPlaylistSheet(context),
                  ),
                  IconButton(
                    icon: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.clear_all_rounded, size: 20),
                    ),
                    tooltip: 'Clear Queue',
                    onPressed: () {
                      notifier.clearQueue();
                    },
                  ),
                ],
              ),
            ],
          ),
        ),

        // 2. Pinned Now Playing Card
        if (state.currentTrack != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.graphic_eq_rounded, color: accentColor, size: 14),
                    const SizedBox(width: 6),
                    Text(
                      'NOW PLAYING',
                      style: TextStyle(
                        color: accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isDark
                          ? [accentColor.withValues(alpha: 0.25), const Color(0xFF1E1E22)]
                          : [accentColor.withValues(alpha: 0.15), Colors.white],
                    ),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.08), blurRadius: 10, offset: const Offset(0, 4))
                    ],
                  ),
                  child: Row(
                    children: [
                      AppArtworkImage(
                        artworkUrl: state.currentTrack!.artworkUrl,
                        trackId: state.currentTrack!.id,
                        width: 56,
                        height: 56,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.currentTrack!.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, fontFamily: 'Outfit'),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              state.currentTrack!.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(color: Colors.grey, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.2),
                          shape: BoxShape.circle,
                        ),
                        child: Icon(Icons.volume_up_rounded, color: accentColor, size: 20),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // 3. Up Next Header Bar
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UP NEXT (${upcomingTracks.length} SONGS)',
                style: TextStyle(
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1.2,
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 12, color: accentColor),
                    const SizedBox(width: 4),
                    Text(
                      'Smart Recommendations Active',
                      style: TextStyle(color: accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 4. Reorderable Queue List
        Expanded(
          child: upcomingTracks.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.queue_music_rounded, size: 56, color: accentColor.withValues(alpha: 0.4)),
                      const SizedBox(height: 12),
                      const Text('No upcoming songs in queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                      const SizedBox(height: 6),
                      const Text('Search or play songs to populate your queue!', style: TextStyle(color: Colors.grey, fontSize: 13)),
                    ],
                  ),
                )
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 150, top: 4),
                  itemCount: upcomingTracks.length,
                  onReorder: (oldIndex, newIndex) {
                    triggerHaptic(HapticFeedbackType.medium);
                    notifier.reorderQueue(upcomingStart + oldIndex, upcomingStart + newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = upcomingTracks[index];
                    final isUpcoming5 = index < 5;
                    final isRec = state.queueSources[track.id] == QueueSource.recommendation;

                    return KeyedSubtree(
                      key: ValueKey('queue_up_${track.id}_$index'),
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 3),
                        decoration: BoxDecoration(
                          color: isUpcoming5
                              ? accentColor.withValues(alpha: isDark ? 0.08 : 0.04)
                              : (isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02)),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: isUpcoming5 ? accentColor.withValues(alpha: 0.25) : Colors.transparent,
                          ),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle_rounded, color: Colors.grey, size: 20),
                              const SizedBox(width: 10),
                              AppArtworkImage(
                                artworkUrl: track.artworkUrl,
                                trackId: track.id,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: isUpcoming5 ? FontWeight.bold : FontWeight.w500,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                margin: const EdgeInsets.only(left: 6),
                                decoration: BoxDecoration(
                                  color: isRec 
                                      ? accentColor.withValues(alpha: 0.2) 
                                      : Colors.blueAccent.withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  isRec ? 'AI Rec' : 'User',
                                  style: TextStyle(
                                    fontSize: 9, 
                                    color: isRec ? accentColor : Colors.blueAccent, 
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Text(track.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 28),
                                onPressed: () {
                                  triggerHaptic(HapticFeedbackType.selection);
                                  notifier.playTrack(track);
                                },
                              ),
                              IconButton(
                                icon: const Icon(Icons.remove_circle_outline_rounded, size: 18, color: Colors.grey),
                                onPressed: () {
                                  triggerHaptic(HapticFeedbackType.light);
                                  notifier.removeFromQueue(upcomingStart + index);
                                },
                              ),
                            ],
                          ),
                          onTap: () {
                            triggerHaptic(HapticFeedbackType.selection);
                            notifier.playTrack(track);
                          },
                        ),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  void _showSaveQueueAsPlaylistSheet(BuildContext context) {
    final state = ref.read(playbackProvider);
    final customBranding = ref.read(customizationProvider);
    final accentColor = customBranding.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final nameController = TextEditingController(
      text: 'Queue Playlist (${DateTime.now().day}/${DateTime.now().month})',
    );
    String selectedFilter = 'all';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            final userTracks = state.queue.where((t) => state.queueSources[t.id] == QueueSource.user || state.queueSources[t.id] == null).toList();
            final recTracks = state.queue.where((t) => state.queueSources[t.id] == QueueSource.recommendation).toList();

            return Container(
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 24,
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
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.grey.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    'Save Queue as Playlist 🎵',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 16),
                  
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Playlist Name',
                      filled: true,
                      fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                      focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: accentColor, width: 1.5)),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Select Songs Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),

                  RadioListTile<String>(
                    title: Text('All Queue Songs (${state.queue.length} tracks)'),
                    value: 'all',
                    groupValue: selectedFilter,
                    activeColor: accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('User-Queued Only (${userTracks.length} tracks)'),
                    value: 'user',
                    groupValue: selectedFilter,
                    activeColor: accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('Recommended Only (${recTracks.length} tracks)'),
                    value: 'recommendation',
                    groupValue: selectedFilter,
                    activeColor: accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  const SizedBox(height: 24),

                  ElevatedButton(
                    onPressed: () async {
                      final name = nameController.text.trim();
                      if (name.isEmpty) return;

                      List targetTracks = [];
                      if (selectedFilter == 'user') {
                        targetTracks = userTracks;
                      } else if (selectedFilter == 'recommendation') {
                        targetTracks = recTracks;
                      } else {
                        targetTracks = state.queue;
                      }

                      if (targetTracks.isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('No tracks match selected filter.')),
                        );
                        return;
                      }

                      final playlists = StorageService.getPlaylists();
                      final newPl = {
                        'id': DateTime.now().millisecondsSinceEpoch.toString(),
                        'name': name,
                        'description': 'Created from active queue (${targetTracks.length} tracks)',
                        'trackIds': targetTracks.map((t) => t.id).toList(),
                        'tracks': targetTracks.map((t) => {
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
                      playlists.add(newPl);
                      await StorageService.savePlaylists(playlists);

                      if (mounted) {
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Saved "$name" with ${targetTracks.length} tracks! 🎵'),
                            backgroundColor: accentColor,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: Colors.black,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 0,
                    ),
                    child: const Text('Save Playlist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
