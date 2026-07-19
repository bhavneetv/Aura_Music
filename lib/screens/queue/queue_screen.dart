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
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

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

        // Up Next Label
        Padding(
          padding: const EdgeInsets.only(left: 24, top: 16, bottom: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'UP NEXT (${state.queue.length} songs • ${_formatQueueDuration(state.queueDuration)})',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: isDark ? Colors.white38 : Colors.black38,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 1.5,
                    ),
              ),
            ],
          ),
        ),

        // Reorderable Queue List
        Expanded(
          child: state.queue.isEmpty
              ? const Center(child: Text('Play queue is empty', style: TextStyle(color: Colors.grey)))
              : ReorderableListView.builder(
                  padding: const EdgeInsets.only(bottom: 96),
                  itemCount: state.queue.length,
                  onReorder: (oldIndex, newIndex) {
                    notifier.reorderQueue(oldIndex, newIndex);
                  },
                  itemBuilder: (context, index) {
                    final track = state.queue[index];
                    final isCurrent = index == state.currentIndex;

                    return KeyedSubtree(
                      key: ValueKey('${track.id}_$index'),
                      child: Opacity(
                        opacity: isCurrent ? 0.5 : 1.0,
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
                                ),
                              ),
                            ],
                          ),
                          title: Text(
                            track.title,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                          ),
                          subtitle: Text(track.artist, style: const TextStyle(fontSize: 11)),
                          trailing: isCurrent 
                              ? const SizedBox.shrink()
                              : IconButton(
                                  icon: const Icon(Icons.remove_circle_outline_rounded, size: 18),
                                  onPressed: () {
                                    notifier.removeFromQueue(index);
                                  },
                                ),
                          onTap: () {
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
