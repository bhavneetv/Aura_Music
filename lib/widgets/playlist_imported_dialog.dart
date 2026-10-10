import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/customization_provider.dart';
import '../providers/playback_provider.dart';
import '../services/sharing/playlist_link_share_service.dart';
import '../themes/app_theme.dart';
import '../widgets/app_artwork_image.dart';

class PlaylistImportSuccessDialog extends ConsumerWidget {
  final PlaylistImportEvent event;

  const PlaylistImportSuccessDialog({
    super.key,
    required this.event,
  });

  static Future<void> show(
    BuildContext context,
    PlaylistImportEvent event,
    WidgetRef ref,
  ) {
    return showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => PlaylistImportSuccessDialog(event: event),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF1E1E24) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      elevation: 16,
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Top celebratory icon
            Center(
              child: Container(
                width: 64,
                height: 64,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      accentColor,
                      accentColor.withValues(alpha: 0.7),
                    ],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.35),
                      blurRadius: 18,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.playlist_add_check_rounded,
                  color: Colors.black,
                  size: 34,
                ),
              ),
            ),
            const SizedBox(height: 16),

            // Title
            Center(
              child: Text(
                'Playlist Added! 🎉',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ),
            const SizedBox(height: 6),
            Center(
              child: Text(
                event.fromQrScan
                    ? 'Scanned & imported from QR code'
                    : 'Saved successfully to your library',
                style: TextStyle(
                  fontSize: 12.5,
                  color: isDark ? Colors.white60 : Colors.black54,
                ),
              ),
            ),
            const SizedBox(height: 20),

            // Playlist Info Card
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: accentColor.withValues(alpha: 0.25),
                  width: 1.2,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Icon(Icons.queue_music_rounded, color: accentColor, size: 20),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              event.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                            ),
                            if (event.description.isNotEmpty) ...[
                              const SizedBox(height: 2),
                              Text(
                                event.description,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ],
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: accentColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          '${event.trackCount} ${event.trackCount == 1 ? 'Song' : 'Songs'}',
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.bold,
                            color: accentColor,
                          ),
                        ),
                      ),
                    ],
                  ),

                  // Mini preview of tracks (up to 3)
                  if (event.tracks.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    const Divider(height: 1, color: Colors.white10),
                    const SizedBox(height: 8),
                    ...event.tracks.take(3).map((track) => Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            children: [
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: AppArtworkImage(
                                    artworkUrl: track.artworkUrl,
                                    width: 26,
                                    height: 26,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  '${track.title} • ${track.artist}',
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    color: isDark ? Colors.white70 : Colors.black87,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        )),
                    if (event.tracks.length > 3)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          '+ ${event.tracks.length - 3} more songs in playlist',
                          style: const TextStyle(
                            fontSize: 10.5,
                            fontStyle: FontStyle.italic,
                            color: Colors.grey,
                          ),
                        ),
                      ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 22),

            // Buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      side: BorderSide(color: isDark ? Colors.white24 : Colors.black12),
                    ),
                    child: Text(
                      'Done',
                      style: TextStyle(
                        fontWeight: FontWeight.w600,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      if (event.tracks.isNotEmpty) {
                        ref.read(playbackProvider.notifier).playCustomQueue(event.tracks, initialIndex: 0);
                      }
                    },
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black, size: 22),
                    label: const Text(
                      'Play Now',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      padding: const EdgeInsets.symmetric(vertical: 13),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                      elevation: 2,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
