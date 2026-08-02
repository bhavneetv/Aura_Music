import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';

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

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const goldColor = Color(0xFFFFC72C);

    final selectedTracks = widget.tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();

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
            margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
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
                        '${selectedTracks.length} / ${widget.tracks.length} Tracks Selected',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: goldColor),
                      ),
                    ),
                    const Spacer(),
                    TextButton.icon(
                      onPressed: () {
                        setState(() {
                          if (_selectedTrackIds.length == widget.tracks.length) {
                            _selectedTrackIds.clear();
                          } else {
                            _selectedTrackIds = widget.tracks.map((t) => t.id).toSet();
                          }
                        });
                      },
                      icon: Icon(
                        _selectedTrackIds.length == widget.tracks.length ? Icons.deselect_rounded : Icons.select_all_rounded,
                        size: 16,
                        color: goldColor,
                      ),
                      label: Text(
                        _selectedTrackIds.length == widget.tracks.length ? 'Deselect All' : 'Select All',
                        style: const TextStyle(fontSize: 12, color: goldColor, fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Songs Checklist
          Expanded(
            child: widget.tracks.isEmpty
                ? const Center(child: Text('No tracks found for query', style: TextStyle(color: Colors.grey)))
                : ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: widget.tracks.length,
                    itemBuilder: (context, index) {
                      final track = widget.tracks[index];
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
                        secondary: ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.network(
                            track.artworkUrl,
                            width: 44,
                            height: 44,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Container(width: 44, height: 44, color: Colors.grey),
                          ),
                        ),
                        title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        subtitle: Text(track.artist, style: const TextStyle(fontSize: 12)),
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
                              'tracks': selectedTracks.map((t) => {
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
