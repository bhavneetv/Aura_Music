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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final upcomingStart = (state.currentIndex >= 0 && state.currentIndex < state.queue.length)
        ? state.currentIndex + 1
        : 0;
    final upcomingTracks = state.queue.skip(upcomingStart).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Page Title & Header Actions
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 12, top: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'Play Queue',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Outfit',
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: Icon(Icons.playlist_add_check_rounded, color: customBranding.accentColor, size: 24),
                    tooltip: 'Save Queue as Playlist',
                    onPressed: () => _showSaveQueueAsPlaylistSheet(context),
                  ),
                  IconButton(
                    icon: const Icon(Icons.clear_all_rounded, size: 24),
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

        // Pinned Now Playing Card
        if (state.currentTrack != null) ...[
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'NOW PLAYING',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        color: customBranding.accentColor,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.5,
                      ),
                ),
                const SizedBox(height: 8),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: AppTheme.glassDecoration(
                    context: context,
                    opacity: isDark ? 0.08 : 0.06,
                    radius: 16,
                  ),
                  child: Row(
                    children: [
                      AppArtworkImage(
                        artworkUrl: state.currentTrack!.artworkUrl,
                        trackId: state.currentTrack!.id,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              state.currentTrack!.title,
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              state.currentTrack!.artist,
                              style: TextStyle(color: isDark ? Colors.white54 : Colors.black54, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                      Icon(Icons.volume_up_rounded, color: customBranding.accentColor, size: 20),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // Up Next Label & Upcoming 5 Badge
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UP NEXT (${upcomingTracks.length} songs)',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: customBranding.accentColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  'Upcoming Recommended',
                  style: TextStyle(color: customBranding.accentColor, fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),

        // Reorderable Queue List
        Expanded(
          child: upcomingTracks.isEmpty
              ? const Center(child: Text('No upcoming songs in queue', style: TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 150),
                  itemCount: upcomingTracks.length,
                  onReorder: (oldIndex, newIndex) {
                    triggerHaptic(HapticFeedbackType.medium);
                    notifier.reorderQueue(upcomingStart + oldIndex, upcomingStart + newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = upcomingTracks[index];
                    final isUpcoming5 = index < 5;

                    return KeyedSubtree(
                      key: ValueKey('queue_up_${track.id}_$index'),
                      child: Container(
                        color: isUpcoming5
                            ? customBranding.accentColor.withOpacity(isDark ? 0.05 : 0.03)
                            : Colors.transparent,
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                          leading: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.drag_handle_rounded, color: Colors.grey, size: 20),
                              const SizedBox(width: 8),
                              AppArtworkImage(
                                artworkUrl: track.artworkUrl,
                                trackId: track.id,
                                width: 40,
                                height: 40,
                                fit: BoxFit.cover,
                                borderRadius: BorderRadius.circular(6),
                              ),
                            ],
                          ),
                          title: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  track.title,
                                  style: TextStyle(
                                    fontWeight: isUpcoming5 ? FontWeight.bold : FontWeight.normal,
                                    fontSize: 14,
                                  ),
                                ),
                              ),
                              Builder(
                                builder: (context) {
                                  final isRec = state.queueSources[track.id] == QueueSource.recommendation;
                                  return Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    margin: const EdgeInsets.only(left: 6),
                                    decoration: BoxDecoration(
                                      color: isRec 
                                          ? customBranding.accentColor.withOpacity(0.18) 
                                          : Colors.blueAccent.withOpacity(0.18),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      isRec ? 'AI Rec' : 'User',
                                      style: TextStyle(
                                        fontSize: 9, 
                                        color: isRec ? customBranding.accentColor : Colors.blueAccent, 
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  );
                                },
                              ),
                            ],
                          ),
                          subtitle: Text(track.artist, style: const TextStyle(fontSize: 11)),
                          trailing: IconButton(
                            icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                            onPressed: () {
                              triggerHaptic(HapticFeedbackType.light);
                              notifier.removeFromQueue(upcomingStart + index);
                            },
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

  String _formatQueueDuration(Duration duration) {
    final m = duration.inMinutes;
    return '$m Min';
  }

  void _showSaveQueueAsPlaylistSheet(BuildContext context) {
    final state = ref.read(playbackProvider);
    final customBranding = ref.read(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final nameController = TextEditingController(
      text: 'Queue Playlist (${DateTime.now().day}/${DateTime.now().month})',
    );
    String selectedFilter = 'all'; // 'all', 'user', 'recommendation'

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
                color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
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
                    'Save Queue as Playlist',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  const SizedBox(height: 16),
                  
                  // Playlist Name Input
                  TextField(
                    controller: nameController,
                    decoration: InputDecoration(
                      labelText: 'Playlist Name',
                      filled: true,
                      fillColor: isDark ? Colors.white12 : Colors.black.withValues(alpha: 0.04),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                  const SizedBox(height: 16),

                  const Text('Select Songs Source', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),

                  // Source Filters
                  RadioListTile<String>(
                    title: Text('All Queue Songs (${state.queue.length} tracks)'),
                    value: 'all',
                    groupValue: selectedFilter,
                    activeColor: customBranding.accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('User-Queued Only (${userTracks.length} tracks)'),
                    value: 'user',
                    groupValue: selectedFilter,
                    activeColor: customBranding.accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  RadioListTile<String>(
                    title: Text('Recommended Only (${recTracks.length} tracks)'),
                    value: 'recommendation',
                    groupValue: selectedFilter,
                    activeColor: customBranding.accentColor,
                    contentPadding: EdgeInsets.zero,
                    onChanged: (val) => setSheetState(() => selectedFilter = val!),
                  ),
                  const SizedBox(height: 20),

                  // Save Button
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
                            content: Text('Saved "${name}" with ${targetTracks.length} tracks! 🎵'),
                            backgroundColor: customBranding.accentColor,
                            behavior: SnackBarBehavior.floating,
                          ),
                        );
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: customBranding.accentColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      minimumSize: const Size(double.infinity, 50),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
