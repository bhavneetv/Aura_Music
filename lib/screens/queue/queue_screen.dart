import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
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
              IconButton(
                icon: const Icon(Icons.clear_all_rounded, size: 24),
                tooltip: 'Clear Queue',
                onPressed: () {
                  notifier.clearQueue();
                },
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
                      ClipRRect(
                        borderRadius: BorderRadius.circular(10),
                        child: Image.network(
                          state.currentTrack!.artworkUrl,
                          width: 52,
                          height: 52,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) => Container(
                            width: 52,
                            height: 52,
                            color: Colors.grey.shade800,
                            child: const Icon(Icons.music_note_rounded, size: 24),
                          ),
                        ),
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
                  padding: const EdgeInsets.only(bottom: 96),
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
                              ClipRRect(
                                borderRadius: BorderRadius.circular(6),
                                child: Image.network(
                                  track.artworkUrl,
                                  width: 40,
                                  height: 40,
                                  fit: BoxFit.cover,
                                  errorBuilder: (context, error, stackTrace) => Container(
                                    width: 40,
                                    height: 40,
                                    color: Colors.grey.shade800,
                                    child: const Icon(Icons.music_note_rounded, size: 20),
                                  ),
                                ),
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
                              if (isUpcoming5)
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  margin: const EdgeInsets.only(left: 6),
                                  decoration: BoxDecoration(
                                    color: customBranding.accentColor.withOpacity(0.2),
                                    borderRadius: BorderRadius.circular(4),
                                  ),
                                  child: Text(
                                    '#${index + 1}',
                                    style: TextStyle(fontSize: 9, color: customBranding.accentColor, fontWeight: FontWeight.bold),
                                  ),
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
}
