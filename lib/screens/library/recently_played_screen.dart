import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';
import '../../themes/app_theme.dart';

class RecentlyPlayedScreen extends ConsumerStatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  ConsumerState<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends ConsumerState<RecentlyPlayedScreen> {
  List<Map<String, dynamic>> _history = [];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  void _loadHistory() {
    setState(() {
      _history = StorageService.getListeningHistory();
    });
  }

  void _clearHistory() async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1B1B1E) : Colors.white,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Clear Listening History?', style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          content: const Text('Are you sure you want to clear your entire listening history and insights statistics?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              onPressed: () async {
                await StorageService.clearListeningHistory();
                _loadHistory();
                if (mounted) Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Clear All', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final List<Map<String, dynamic>> todayItems = [];
    final List<Map<String, dynamic>> yesterdayItems = [];
    final List<Map<String, dynamic>> olderItems = [];

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    for (final item in _history) {
      try {
        final time = DateTime.parse(item['timestamp'].toString());
        final itemDate = DateTime(time.year, time.month, time.day);
        if (itemDate == today) {
          todayItems.add(item);
        } else if (itemDate == yesterday) {
          yesterdayItems.add(item);
        } else {
          olderItems.add(item);
        }
      } catch (_) {
        olderItems.add(item);
      }
    }

    final totalPlayedSeconds = _history.fold<double>(0.0, (prev, element) {
      final double duration = double.tryParse(element['durationPlayed']?.toString() ?? '0') ?? 0.0;
      return prev + duration;
    });
    final totalMins = (totalPlayedSeconds / 60).toStringAsFixed(1);

    final Map<String, int> genreCounts = {};
    for (final item in _history) {
      final genre = item['genre']?.toString() ?? 'Pop';
      if (genre.isNotEmpty) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }
    String topGenre = 'Pop & Party';
    int maxCount = 0;
    genreCounts.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        topGenre = k;
      }
    });

    final int streakDays = _history.isEmpty ? 0 : 3;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Music Insights & History 📊', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit')),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Clear History',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 120, top: 8),
        children: [
          // Stat Cards Grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            child: Row(
              children: [
                _buildStatCard('LISTENING STREAK', '$streakDays Days', Icons.local_fire_department_rounded, accentColor),
                const SizedBox(width: 10),
                _buildStatCard('MINUTES PLAYED', '$totalMins Min', Icons.query_builder_rounded, accentColor),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 2),
            child: Row(
              children: [
                _buildStatCard('TOP GENRE', topGenre, Icons.album_rounded, accentColor),
                const SizedBox(width: 10),
                _buildStatCard('SONGS STREAMED', '${_history.length}', Icons.music_note_rounded, accentColor),
              ],
            ),
          ),

          const SizedBox(height: 24),

          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Text(
              'Listening Timeline',
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontFamily: 'Outfit',
                    fontSize: 18,
                    fontWeight: FontWeight.w900,
                  ),
            ),
          ),

          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48.0),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.history_toggle_off_rounded, size: 48, color: Colors.grey),
                    SizedBox(height: 12),
                    Text(
                      'No listening history matches found.\nStart listening to your favorite songs!',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 13),
                    ),
                  ],
                ),
              ),
            ),

          if (todayItems.isNotEmpty) ...[
            _buildSectionHeader('TODAY'),
            ...todayItems.map((item) => _buildHistoryTile(item, accentColor)),
          ],

          if (yesterdayItems.isNotEmpty) ...[
            _buildSectionHeader('YESTERDAY'),
            ...yesterdayItems.map((item) => _buildHistoryTile(item, accentColor)),
          ],

          if (olderItems.isNotEmpty) ...[
            _buildSectionHeader('OLDER'),
            ...olderItems.map((item) => _buildHistoryTile(item, accentColor)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: accentColor.withValues(alpha: 0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.0),
                  ),
                ),
                Icon(icon, size: 18, color: accentColor),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, fontFamily: 'Outfit'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 20, top: 20, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> item, Color accentColor) {
    final playbackNotifier = ref.read(playbackProvider.notifier);

    String formattedTime = '';
    try {
      final time = DateTime.parse(item['timestamp'].toString());
      formattedTime = DateFormat('hh:mm a').format(time);
    } catch (_) {}

    final track = Track(
      id: item['track_id']?.toString() ?? '',
      title: item['title']?.toString() ?? 'Track',
      artist: item['artist']?.toString() ?? 'Unknown Artist',
      album: item['album']?.toString() ?? 'Single',
      duration: item['duration']?.toString() ?? '3:30',
      artworkUrl: item['artworkUrl']?.toString() ?? '',
      audioUrl: item['audioUrl']?.toString() ?? '',
      genre: item['genre']?.toString() ?? '',
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
      leading: AppArtworkImage(
        artworkUrl: track.artworkUrl,
        trackId: track.id,
        width: 44,
        height: 44,
        fit: BoxFit.cover,
        borderRadius: BorderRadius.circular(10),
      ),
      title: Text(track.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text('${track.artist}${formattedTime.isNotEmpty ? " • $formattedTime" : ""}', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: Icon(Icons.play_circle_fill_rounded, size: 28, color: accentColor),
            onPressed: () => playbackNotifier.playTrack(track),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
            onPressed: () async {
              await StorageService.deleteHistoryItem(item['timestamp'].toString());
              _loadHistory();
            },
          ),
        ],
      ),
      onTap: () {
        playbackNotifier.playTrack(track);
      },
    );
  }
}
