import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';

class AiPlaylistReviewScreen extends ConsumerStatefulWidget {
  final String suggestedName;
  final List<Track> tracks;

  const AiPlaylistReviewScreen({
    super.key,
    required this.suggestedName,
    required this.tracks,
  });

  @override
  ConsumerState<AiPlaylistReviewScreen> createState() => _AiPlaylistReviewScreenState();
}

class _AiPlaylistReviewScreenState extends ConsumerState<AiPlaylistReviewScreen> {
  late TextEditingController _nameController;
  late Set<String> _selectedTrackIds;
  String _sourceFilter = 'All'; // 'All', 'Saavn', 'YT'

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _selectedTrackIds = widget.tracks.map((t) => t.id).toSet();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  List<Track> get _visibleTracks {
    if (_sourceFilter == 'Saavn') {
      return widget.tracks.where((t) => t.isJioSaavn).toList();
    } else if (_sourceFilter == 'YT') {
      return widget.tracks.where((t) => t.isYouTube).toList();
    }
    return widget.tracks;
  }

  int get _allCount => widget.tracks.length;
  int get _saavnCount => widget.tracks.where((t) => t.isJioSaavn).length;
  int get _ytCount => widget.tracks.where((t) => t.isYouTube).length;

  Widget _buildSourceSliderBar({
    required BuildContext context,
    required Color accentColor,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(3.5),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF1C1C22) : const Color(0xFFE8E8EE),
          borderRadius: BorderRadius.circular(22),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Row(
          children: [
            _buildSliderSegment(
              label: 'All',
              filterKey: 'All',
              count: _allCount,
              icon: Icons.all_inclusive_rounded,
              activeColor: accentColor,
              activeTextColor: Colors.black,
              isDark: isDark,
            ),
            const SizedBox(width: 4),
            _buildSliderSegment(
              label: 'Saavn',
              filterKey: 'Saavn',
              count: _saavnCount,
              icon: Icons.graphic_eq_rounded,
              activeColor: const Color(0xFF00D1B2),
              activeTextColor: Colors.black,
              isDark: isDark,
            ),
            const SizedBox(width: 4),
            _buildSliderSegment(
              label: 'YT',
              filterKey: 'YT',
              count: _ytCount,
              icon: Icons.smart_display_rounded,
              activeColor: const Color(0xFFFF0033),
              activeTextColor: Colors.white,
              isDark: isDark,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSliderSegment({
    required String label,
    required String filterKey,
    required int count,
    required IconData icon,
    required Color activeColor,
    required Color activeTextColor,
    required bool isDark,
  }) {
    final isSelected = _sourceFilter == filterKey;

    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          if (_sourceFilter != filterKey) {
            triggerHaptic(HapticFeedbackType.selection);
            setState(() {
              _sourceFilter = filterKey;
            });
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: isSelected ? activeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(18),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: activeColor.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 14,
                color: isSelected ? activeTextColor : (isDark ? Colors.white60 : Colors.black54),
              ),
              const SizedBox(width: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.w900 : FontWeight.w600,
                  fontFamily: 'Outfit',
                  color: isSelected ? activeTextColor : (isDark ? Colors.white70 : Colors.black87),
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (activeTextColor == Colors.black ? Colors.black.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.25))
                      : (isDark ? Colors.white.withValues(alpha: 0.1) : Colors.black.withValues(alpha: 0.08)),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    color: isSelected ? activeTextColor : (isDark ? Colors.white60 : Colors.black54),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = customBranding.accentColor;
    const goldColor = Color(0xFFFFC72C);

    final selectedTracks = widget.tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
    final visibleTracks = _visibleTracks;
    final allVisibleSelected = visibleTracks.isNotEmpty && visibleTracks.every((t) => _selectedTrackIds.contains(t.id));

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F11) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.auto_awesome_rounded, color: goldColor, size: 20),
            SizedBox(width: 8),
            Text('AI Curated Playlist', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17, fontFamily: 'Outfit')),
          ],
        ),
      ),
      body: Column(
        children: [
          // Header Card
          Container(
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: isDark
                    ? [const Color(0xFF24221A), const Color(0xFF18181A)]
                    : [const Color(0xFFFFF9E6), const Color(0xFFF3EFE9)],
              ),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: goldColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Playlist Name',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit'),
                  decoration: InputDecoration(
                    suffixIcon: const Icon(Icons.edit_rounded, color: goldColor, size: 18),
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.white70,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: goldColor.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        '${selectedTracks.length} / ${widget.tracks.length} Selected',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: goldColor),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (allVisibleSelected) {
                            for (final t in visibleTracks) {
                              _selectedTrackIds.remove(t.id);
                            }
                          } else {
                            for (final t in visibleTracks) {
                              _selectedTrackIds.add(t.id);
                            }
                          }
                        });
                      },
                      icon: Icon(
                        allVisibleSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                        size: 16,
                        color: goldColor,
                      ),
                      label: Text(
                        allVisibleSelected ? 'Deselect (${visibleTracks.length})' : 'Select All (${visibleTracks.length})',
                        style: const TextStyle(fontSize: 12, color: goldColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // 3 Source Filter Slider Bar: All, Saavn, YT
          _buildSourceSliderBar(
            context: context,
            accentColor: accentColor,
            isDark: isDark,
          ),
          const SizedBox(height: 4),

          // Songs Checklist
          Expanded(
            child: visibleTracks.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _sourceFilter == 'YT' ? Icons.smart_display_outlined : Icons.graphic_eq_rounded,
                            size: 48,
                            color: Colors.grey.withValues(alpha: 0.5),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'No $_sourceFilter tracks in this curated playlist',
                            style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold, fontSize: 14),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: () => setState(() => _sourceFilter = 'All'),
                            child: const Text('Show All Tracks', style: TextStyle(color: goldColor, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: visibleTracks.length,
                    itemBuilder: (context, index) {
                      final track = visibleTracks[index];
                      final isSelected = _selectedTrackIds.contains(track.id);

                      return CheckboxListTile(
                        value: isSelected,
                        activeColor: goldColor,
                        checkColor: Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                        onChanged: (val) {
                          setState(() {
                            if (val == true) {
                              _selectedTrackIds.add(track.id);
                            } else {
                              _selectedTrackIds.remove(track.id);
                            }
                          });
                        },
                        secondary: AppArtworkImage(
                          artworkUrl: track.artworkUrl,
                          trackId: track.id,
                          width: 44,
                          height: 44,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                              margin: const EdgeInsets.only(right: 6),
                              decoration: BoxDecoration(
                                color: track.isYouTube
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : const Color(0xFF00D1B2).withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(
                                  color: track.isYouTube
                                      ? Colors.red.withValues(alpha: 0.5)
                                      : const Color(0xFF00D1B2).withValues(alpha: 0.5),
                                  width: 0.5,
                                ),
                              ),
                              child: Text(
                                track.isYouTube ? 'YT' : 'Saavn',
                                style: TextStyle(
                                  color: track.isYouTube ? Colors.redAccent : const Color(0xFF00D1B2),
                                  fontSize: 9.5,
                                  fontWeight: FontWeight.bold,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            Expanded(
                              child: Text(track.artist, style: const TextStyle(fontSize: 12), maxLines: 1, overflow: TextOverflow.ellipsis),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),

          // Bottom Action Bar (Save & Play)
          Container(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 14,
              bottom: MediaQuery.of(context).padding.bottom + 14,
            ),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF141416) : Colors.white,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.1), blurRadius: 10, offset: const Offset(0, -4)),
              ],
            ),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: selectedTracks.isEmpty
                        ? null
                        : () async {
                            final name = _nameController.text.trim().isEmpty ? 'AI Curated Playlist' : _nameController.text.trim();
                            final playlists = StorageService.getPlaylists();
                            final newPl = {
                              'id': DateTime.now().millisecondsSinceEpoch.toString(),
                              'name': name,
                              'description': 'AI generated playlist from prompt',
                              'trackIds': selectedTracks.map((t) => t.id).toList(),
                              'tracks': selectedTracks.map((t) => t.toJson()).toList(),
                            };
                            playlists.add(newPl);
                            await StorageService.savePlaylists(playlists);

                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Saved AI Playlist "$name" with ${selectedTracks.length} tracks! ⚡'),
                                  backgroundColor: customBranding.accentColor,
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                              Navigator.pop(context);
                            }
                          },
                    icon: const Icon(Icons.bookmark_add_rounded),
                    label: const Text('Save Playlist'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: selectedTracks.isEmpty
                        ? null
                        : () async {
                            final sessionName = widget.suggestedName.trim();
                            final chipTag = '✨ $sessionName (${selectedTracks.length} songs)';
                            await StorageService.saveGroupedAiSession(chipTag, selectedTracks);
                            await StorageService.saveGroupedAiSession(sessionName, selectedTracks);
                            await StorageService.addAiSearchQuery(chipTag);

                            final notifier = ref.read(playbackProvider.notifier);
                            notifier.playCustomQueue(selectedTracks, initialIndex: 0);
                            if (context.mounted) {
                              Navigator.pop(context);
                            }
                          },
                    icon: const Icon(Icons.play_arrow_rounded),
                    label: const Text('Play Now'),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: goldColor),
                      foregroundColor: goldColor,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
