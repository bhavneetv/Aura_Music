import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../models/track.dart';
import '../../providers/customization_provider.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../../themes/app_theme.dart';
import '../handoff/nearby_share_screen.dart';

class ShareOptionsModal extends ConsumerWidget {
  final List<Track> tracks;
  final String title;
  final String description;

  const ShareOptionsModal({
    super.key,
    required this.tracks,
    required this.title,
    this.description = '',
  });

  static Future<void> show(
    BuildContext context, {
    required List<Track> tracks,
    required String title,
    String description = '',
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) => ShareOptionsModal(
        tracks: tracks,
        title: title,
        description: description,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF18181C) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
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
                color: isDark ? Colors.white24 : Colors.black12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Icon(Icons.share_rounded, color: accentColor, size: 26),
              const SizedBox(width: 12),
              Text(
                'Share Playlist 🎵',
                style: TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            '"$title" • ${tracks.length} Tracks',
            style: TextStyle(fontSize: 13, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7)),
          ),
          const SizedBox(height: 24),

          // Option 1: Remote Link & QR (0 Database)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pop(context);
                RemoteLinkShareModal.show(
                  context,
                  tracks: tracks,
                  title: title,
                  description: description,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: accentColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: accentColor,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.link_rounded, color: Colors.black, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Stateless Remote Link & QR',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Share link/QR with anyone far away (0 Database required)',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white70 : Colors.black.withValues(alpha: 0.7)),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.arrow_forward_ios_rounded, size: 16, color: accentColor),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 14),

          // Option 2: Nearby Share (P2P Wi-Fi)
          Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () {
                Navigator.pop(context);
                NearbyShareScreen.showHandoffModal(
                  context,
                  tracks: tracks,
                  title: title,
                );
              },
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white12 : Colors.black12,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.wifi_tethering_rounded, color: isDark ? Colors.white : Colors.black, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Nearby Share (Local Wi-Fi P2P)',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Transfer directly to nearby devices on the same Wi-Fi',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white60 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    const Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
        ],
      ),
    );
  }
}

class RemoteLinkShareModal extends ConsumerWidget {
  final List<Track> tracks;
  final String title;
  final String description;

  const RemoteLinkShareModal({
    super.key,
    required this.tracks,
    required this.title,
    this.description = '',
  });

  static Future<void> show(
    BuildContext context, {
    required List<Track> tracks,
    required String title,
    String description = '',
  }) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => RemoteLinkShareModal(
        tracks: tracks,
        title: title,
        description: description,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return FutureBuilder<String>(
      future: PlaylistLinkShareService.instance.generateShareableLinkAsync(title, description, tracks),
      builder: (context, snapshot) {
        final shareableLink = snapshot.data ?? PlaylistLinkShareService.instance.generateShareableLink(title, description, tracks);
        final isLoading = snapshot.connectionState == ConnectionState.waiting;

        return Container(
          height: MediaQuery.of(context).size.height * 0.85,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF16161A) : Colors.white,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            children: [
              const SizedBox(height: 12),
              Container(
                width: 42,
                height: 5,
                decoration: BoxDecoration(
                  color: isDark ? Colors.white24 : Colors.black12,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.qr_code_2_rounded, color: accentColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Stateless Remote Playlist Link',
                            style: TextStyle(
                              fontFamily: 'Outfit',
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text(
                            'Zero database required • Microscopic QR Code',
                            style: TextStyle(fontSize: 11.5, color: Colors.grey),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Expanded(
                child: isLoading
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(
                              width: 32,
                              height: 32,
                              child: CircularProgressIndicator(color: accentColor, strokeWidth: 3),
                            ),
                            const SizedBox(height: 16),
                            const Text(
                              'Generating Microscopic QR Code...',
                              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.grey),
                            ),
                          ],
                        ),
                      )
                    : ListView(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                        children: [
                          // QR Code Container
                          Center(
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: accentColor.withValues(alpha: 0.2),
                                    blurRadius: 20,
                                    offset: const Offset(0, 8),
                                  ),
                                ],
                              ),
                              child: QrImageView(
                                data: shareableLink,
                                version: QrVersions.auto,
                                errorCorrectionLevel: QrErrorCorrectLevel.L,
                                size: 220.0,
                                backgroundColor: Colors.white,
                              ),
                            ),
                          ),

                          const SizedBox(height: 14),
                          Center(
                            child: Text(
                              'Scan with any phone camera or Aura importer',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w500,
                                color: isDark ? Colors.white54 : Colors.black54,
                              ),
                            ),
                          ),

                          const SizedBox(height: 20),

                          // Shareable Link Box
                          Container(
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
                              borderRadius: BorderRadius.circular(18),
                              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Ultra-Short Playlist Code / Link',
                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  shareableLink,
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    fontFamily: 'monospace',
                                    color: accentColor,
                                  ),
                                ),
                              ],
                            ),
                          ),

                          const SizedBox(height: 16),

                          // Copy Link Button
                          ElevatedButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: shareableLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Copied short link for "$title"! Share it anywhere.'),
                                  backgroundColor: accentColor,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy_rounded, color: Colors.black, size: 20),
                            label: const Text(
                              'Copy Playlist Link',
                              style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 14),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: accentColor,
                              minimumSize: const Size(double.infinity, 48),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            ),
                          ),

                          const SizedBox(height: 24),

                          // Preview Content
                          Text(
                            'Playlist Summary (${tracks.length} Tracks)',
                            style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 15),
                          ),
                          const SizedBox(height: 8),

                          ...tracks.take(4).map((tr) => ListTile(
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                                title: Text(tr.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
                                subtitle: Text(tr.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              )),

                          if (tracks.length > 4)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                '+ ${tracks.length - 4} more tracks embedded',
                                style: TextStyle(fontSize: 12, fontStyle: FontStyle.italic, color: accentColor),
                              ),
                            ),
                        ],
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}
