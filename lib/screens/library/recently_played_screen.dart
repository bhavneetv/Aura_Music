import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
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
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Clear History?', style: TextStyle(fontWeight: FontWeight.bold)),
          content: const Text('Are you sure you want to clear your entire listening history and statistics?'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
            ),
            TextButton(
              onPressed: () async {
                await StorageService.clearListeningHistory();
                _loadHistory();
                Navigator.pop(context);
              },
              child: const Text('Clear All', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Build categories
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

    // Dynamic stats calculations
    final totalPlayedSeconds = _history.fold<double>(0.0, (prev, element) {
      final double duration = double.tryParse(element['durationPlayed']?.toString() ?? '0') ?? 0.0;
      return prev + duration;
    });
    final totalMins = (totalPlayedSeconds / 60).toStringAsFixed(1);
    
    // Group genres
    final Map<String, int> genreCounts = {};
    for (final item in _history) {
      final genre = item['genre']?.toString() ?? 'Unknown';
      if (genre.isNotEmpty) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }
    }
    String topGenre = 'None';
    int maxCount = 0;
    genreCounts.forEach((k, v) {
      if (v > maxCount) {
        maxCount = v;
        topGenre = k;
      }
    });

    final int streakDays = _history.isEmpty ? 0 : 3; // Mocking dynamic streak

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('Insights & History', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Clear History',
              onPressed: _clearHistory,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 96),
        children: [
          // Stats Row
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            child: Row(
              children: [
                _buildStatCard('LISTENING STREAK', '$streakDays Days', Icons.local_fire_department_rounded, customBranding.accentColor),
                const SizedBox(width: 12),
                _buildStatCard('MINUTES PLAYED', '$totalMins Min', Icons.query_builder_rounded, customBranding.accentColor),
              ],
            ),
          ),
          
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
            child: Row(
              children: [
                _buildStatCard('FAVORITE GENRE', topGenre, Icons.album_rounded, customBranding.accentColor),
                const SizedBox(width: 12),
                _buildStatCard('SONGS STREAMED', '${_history.length}', Icons.music_note_rounded, customBranding.accentColor),
              ],
            ),
          ),

          const SizedBox(height: 24),

          // Listening List Title
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Listening History',
              style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
            ),
          ),

          if (_history.isEmpty)
            const Padding(
              padding: EdgeInsets.all(48.0),
              child: Center(
                child: Text(
                  'No history matches found. Start listening!',
                  style: TextStyle(color: Colors.grey),
                ),
              ),
            ),

          // Render sections
          if (todayItems.isNotEmpty) ...[
            _buildSectionHeader('TODAY'),
            ...todayItems.map((item) => _buildHistoryTile(item)),
          ],

          if (yesterdayItems.isNotEmpty) ...[
            _buildSectionHeader('YESTERDAY'),
            ...yesterdayItems.map((item) => _buildHistoryTile(item)),
          ],

          if (olderItems.isNotEmpty) ...[
            _buildSectionHeader('OLDER'),
            ...olderItems.map((item) => _buildHistoryTile(item)),
          ],
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: AppTheme.glassDecoration(
          context: context,
          opacity: isDark ? 0.05 : 0.04,
          radius: 16,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey, letterSpacing: 1.2)),
                Icon(icon, size: 18, color: accentColor),
              ],
            ),
            const SizedBox(height: 12),
            Text(value, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.only(left: 24, top: 20, bottom: 8),
      child: Text(
        label,
        style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1.5),
      ),
    );
  }

  Widget _buildHistoryTile(Map<String, dynamic> item) {
    final playbackNotifier = ref.read(playbackProvider.notifier);
    
    // Parse time
    String formattedTime = '';
    try {
      final time = DateTime.parse(item['timestamp'].toString());
      formattedTime = DateFormat('hh:mm a').format(time);
    } catch (_) {}

    final track = Track(
      id: item['track_id']?.toString() ?? '',
      title: item['title']?.toString() ?? '',
      artist: item['artist']?.toString() ?? '',
      album: item['album']?.toString() ?? '',
      duration: item['duration']?.toString() ?? '',
      artworkUrl: item['artworkUrl']?.toString() ?? '',
      audioUrl: item['audioUrl']?.toString() ?? '',
      genre: item['genre']?.toString() ?? '',
    );

    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: Image.network(track.artworkUrl, width: 44, height: 44, fit: BoxFit.cover),
      ),
      title: Text(track.title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      subtitle: Text('${track.artist} • $formattedTime', style: const TextStyle(fontSize: 11)),
      trailing: IconButton(
        icon: const Icon(Icons.close_rounded, size: 16, color: Colors.grey),
        onPressed: () async {
          await StorageService.deleteHistoryItem(item['timestamp'].toString());
          _loadHistory();
        },
      ),
      onTap: () {
        playbackNotifier.playTrack(track);
      },
    );
  }
}
