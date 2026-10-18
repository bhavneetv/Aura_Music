import 'dart:io';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';
import '../../../providers/customization_provider.dart';
import '../../../services/storage/storage_service.dart';
import '../../../services/download/download_service.dart';
import '../../../models/track.dart';
import '../../../widgets/app_artwork_image.dart';

// ============================================================================
// DATA MODELS
// ============================================================================

class PlaylistStorageDetail {
  final String id;
  final String name;
  final String? coverUrl;
  final int totalTracks;
  final int downloadedTracksCount;
  final int totalBytes;
  final List<String> downloadedTrackIds;

  const PlaylistStorageDetail({
    required this.id,
    required this.name,
    this.coverUrl,
    required this.totalTracks,
    required this.downloadedTracksCount,
    required this.totalBytes,
    required this.downloadedTrackIds,
  });

  String get formattedSize => StorageUsageHelper.formatBytes(totalBytes);
}

class StorageUsageBreakdown {
  final int downloadedMusicBytes;
  final int coverBytes;
  final int cacheBytes;
  final int totalAppBytes;
  final List<PlaylistStorageDetail> downloadedPlaylists;
  final int totalDownloadedTracks;

  const StorageUsageBreakdown({
    required this.downloadedMusicBytes,
    required this.coverBytes,
    required this.cacheBytes,
    required this.totalAppBytes,
    required this.downloadedPlaylists,
    required this.totalDownloadedTracks,
  });

  String get formattedTotal => StorageUsageHelper.formatBytes(totalAppBytes);
  String get formattedMusic => StorageUsageHelper.formatBytes(downloadedMusicBytes);
  String get formattedCover => StorageUsageHelper.formatBytes(coverBytes);
  String get formattedCache => StorageUsageHelper.formatBytes(cacheBytes);
}

// ============================================================================
// HELPER CALCULATOR
// ============================================================================

class StorageUsageHelper {
  static StorageUsageBreakdown? _cachedBreakdown;
  static DateTime? _lastCalculated;
  static Future<StorageUsageBreakdown>? _inFlightCalculation;

  static void invalidateCache() {
    _cachedBreakdown = null;
    _lastCalculated = null;
  }

  static String formatBytes(int bytes) {
    if (bytes <= 0) return '0 B';
    const suffixes = ['B', 'KB', 'MB', 'GB', 'TB'];
    final i = (log(bytes) / log(1024)).floor();
    final clampedIndex = i.clamp(0, suffixes.length - 1);
    final size = bytes / pow(1024, clampedIndex);
    return '${size.toStringAsFixed(size >= 100 || clampedIndex == 0 ? 0 : 1)} ${suffixes[clampedIndex]}';
  }

  static Future<StorageUsageBreakdown> getBreakdown({bool forceRefresh = false}) async {
    if (!forceRefresh &&
        _cachedBreakdown != null &&
        _lastCalculated != null &&
        DateTime.now().difference(_lastCalculated!) < const Duration(seconds: 15)) {
      return _cachedBreakdown!;
    }

    if (_inFlightCalculation != null) {
      return _inFlightCalculation!;
    }

    _inFlightCalculation = _computeBreakdown();
    try {
      final result = await _inFlightCalculation!;
      _cachedBreakdown = result;
      _lastCalculated = DateTime.now();
      return result;
    } finally {
      _inFlightCalculation = null;
    }
  }

  static Future<StorageUsageBreakdown> _computeBreakdown() async {
    int downloadedMusicBytes = 0;
    int coverBytes = 0;
    int cacheBytes = 0;
    final Map<String, int> trackSizeBytes = {};
    final Set<String> seenCoverPaths = {};
    String? docDirPath;

    // 1. Calculate physical files in downloads directory asynchronously (non-blocking)
    try {
      final docDir = await getApplicationDocumentsDirectory();
      docDirPath = docDir.path;
      final downloadsDir = Directory('${docDir.path}/downloads');
      if (await downloadsDir.exists()) {
        await for (final entity in downloadsDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              final len = await entity.length();
              final name = entity.uri.pathSegments.last.toLowerCase();
              if (name.endsWith('_cover.jpg') ||
                  name.endsWith('_art.jpg') ||
                  name.endsWith('.jpg') ||
                  name.endsWith('.jpeg') ||
                  name.endsWith('.png') ||
                  name.endsWith('.webp')) {
                coverBytes += len;
                seenCoverPaths.add(entity.path);
              } else {
                downloadedMusicBytes += len;
                final dotIdx = name.lastIndexOf('.');
                final trackId = dotIdx > 0 ? name.substring(0, dotIdx) : name;
                trackSizeBytes[trackId] = (trackSizeBytes[trackId] ?? 0) + len;
              }
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 2. Artwork files registered in StorageService
    try {
      final downloadedTracksMap = StorageService.getDownloadedTracks();
      for (final entry in downloadedTracksMap.entries) {
        final trackId = entry.key;
        final artPath = StorageService.getDownloadedArtworkPath(trackId);
        if (artPath != null && !seenCoverPaths.contains(artPath)) {
          final artFile = File(artPath);
          if (await artFile.exists()) {
            try {
              final artLen = await artFile.length();
              coverBytes += artLen;
              seenCoverPaths.add(artPath);
              trackSizeBytes[trackId] = (trackSizeBytes[trackId] ?? 0) + artLen;
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 3. Cache and temporary directory asynchronously
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: true, followLinks: false)) {
          if (entity is File) {
            try {
              cacheBytes += await entity.length();
            } catch (_) {}
          }
        }
      }
    } catch (_) {}

    // 5. Build per-playlist breakdown
    final List<PlaylistStorageDetail> playlistDetails = [];
    final Set<String> countedTrackIds = {};

    // A. User Library Playlists
    try {
      final rawPlaylists = StorageService.getPlaylists();
      for (final pl in rawPlaylists) {
        final plId = pl['id']?.toString() ?? pl['name']?.toString() ?? '';
        final plName = pl['name']?.toString() ?? 'Custom Playlist';
        final coverUrl = pl['coverUrl']?.toString();
        final tracksRaw = pl['tracks'] as List<dynamic>? ?? [];

        int plBytes = 0;
        final List<String> plDownloadedIds = [];

        for (final t in tracksRaw) {
          String? tId;
          if (t is Map) {
            tId = t['id']?.toString();
          } else if (t is Track) {
            tId = t.id;
          }
          if (tId != null) {
            final isDown = DownloadService.instance.isDownloaded(tId) || trackSizeBytes.containsKey(tId);
            if (isDown) {
              plDownloadedIds.add(tId);
              countedTrackIds.add(tId);
              plBytes += trackSizeBytes[tId] ?? (trackSizeBytes['yt_$tId'] ?? _safeTrackSize(tId, docDirPath));
            }
          }
        }

        if (plDownloadedIds.isNotEmpty) {
          playlistDetails.add(PlaylistStorageDetail(
            id: plId,
            name: plName,
            coverUrl: coverUrl,
            totalTracks: tracksRaw.length,
            downloadedTracksCount: plDownloadedIds.length,
            totalBytes: plBytes,
            downloadedTrackIds: plDownloadedIds,
          ));
        }
      }
    } catch (_) {}

    // B. Explicit Downloaded Playlists
    try {
      final downloadedPls = StorageService.getDownloadedPlaylists();
      for (final pl in downloadedPls) {
        final plName = pl['name']?.toString() ?? 'Downloaded Playlist';
        if (playlistDetails.any((p) => p.name.trim().toLowerCase() == plName.trim().toLowerCase())) {
          continue;
        }
        final tracksRaw = pl['tracks'] as List<dynamic>? ?? [];
        int plBytes = 0;
        final List<String> plDownloadedIds = [];

        for (final t in tracksRaw) {
          String? tId;
          if (t is Map) {
            tId = t['id']?.toString();
          }
          if (tId != null) {
            plDownloadedIds.add(tId);
            countedTrackIds.add(tId);
            plBytes += trackSizeBytes[tId] ?? (trackSizeBytes['yt_$tId'] ?? _safeTrackSize(tId, docDirPath));
          }
        }

        if (plDownloadedIds.isNotEmpty) {
          playlistDetails.add(PlaylistStorageDetail(
            id: 'dl_${plName.hashCode}',
            name: plName,
            totalTracks: tracksRaw.length,
            downloadedTracksCount: plDownloadedIds.length,
            totalBytes: plBytes,
            downloadedTrackIds: plDownloadedIds,
          ));
        }
      }
    } catch (_) {}

    // C. Liked Songs (Favorites)
    try {
      final favTracks = StorageService.getFavoriteTracks();
      int favBytes = 0;
      final List<String> favDownloadedIds = [];
      for (final t in favTracks) {
        if (DownloadService.instance.isDownloaded(t.id) || trackSizeBytes.containsKey(t.id)) {
          favDownloadedIds.add(t.id);
          countedTrackIds.add(t.id);
          favBytes += trackSizeBytes[t.id] ?? (trackSizeBytes['yt_${t.id}'] ?? _safeTrackSize(t.id, docDirPath));
        }
      }
      if (favDownloadedIds.isNotEmpty) {
        playlistDetails.insert(0, PlaylistStorageDetail(
          id: 'favorites',
          name: 'Liked Songs (Favorites)',
          totalTracks: favTracks.length,
          downloadedTracksCount: favDownloadedIds.length,
          totalBytes: favBytes,
          downloadedTrackIds: favDownloadedIds,
        ));
      }
    } catch (_) {}

    // D. Individual / Standalone Downloaded Tracks
    int totalDownloadedTracks = 0;
    try {
      final allRegistered = StorageService.getFullDownloadedTracks();
      totalDownloadedTracks = allRegistered.length;
      final remainingTracks = allRegistered.where((t) => !countedTrackIds.contains(t.id)).toList();
      if (remainingTracks.isNotEmpty) {
        int otherBytes = 0;
        final otherIds = <String>[];
        for (final t in remainingTracks) {
          otherIds.add(t.id);
          otherBytes += trackSizeBytes[t.id] ?? (trackSizeBytes['yt_${t.id}'] ?? _safeTrackSize(t.id, docDirPath));
        }
        if (otherBytes > 0) {
          playlistDetails.add(PlaylistStorageDetail(
            id: 'other_tracks',
            name: 'Single Downloaded Tracks',
            totalTracks: remainingTracks.length,
            downloadedTracksCount: remainingTracks.length,
            totalBytes: otherBytes,
            downloadedTrackIds: otherIds,
          ));
        }
      }
    } catch (_) {}

    // Sort by largest space used
    playlistDetails.sort((a, b) => b.totalBytes.compareTo(a.totalBytes));

    final totalAppBytes = downloadedMusicBytes + coverBytes + cacheBytes;

    return StorageUsageBreakdown(
      downloadedMusicBytes: downloadedMusicBytes,
      coverBytes: coverBytes,
      cacheBytes: cacheBytes,
      totalAppBytes: totalAppBytes,
      downloadedPlaylists: playlistDetails,
      totalDownloadedTracks: totalDownloadedTracks,
    );
  }

  static int _safeTrackSize(String trackId, [String? docPath]) {
    try {
      final p = StorageService.getDownloadedTrackPath(trackId);
      if (p != null) {
        final f = File(p);
        if (f.existsSync()) return f.lengthSync();
      }
      if (docPath != null) {
        final m4a = File('$docPath/downloads/$trackId.m4a');
        if (m4a.existsSync()) return m4a.lengthSync();
        final mp4 = File('$docPath/downloads/$trackId.mp4');
        if (mp4.existsSync()) return mp4.lengthSync();
      }
    } catch (_) {}
    return 0;
  }

  static Future<void> clearTemporaryCache() async {
    try {
      final tempDir = await getTemporaryDirectory();
      if (await tempDir.exists()) {
        await for (final entity in tempDir.list(recursive: false, followLinks: false)) {
          try {
            if (entity is File) {
              await entity.delete();
            } else if (entity is Directory) {
              await entity.delete(recursive: true);
            }
          } catch (_) {}
        }
      }
    } catch (_) {}
    invalidateCache();
  }
}

// ============================================================================
// MAIN STORAGE USAGE CARD WIDGET
// ============================================================================

class AuraStorageUsageCard extends ConsumerStatefulWidget {
  const AuraStorageUsageCard({super.key});

  @override
  ConsumerState<AuraStorageUsageCard> createState() => _AuraStorageUsageCardState();
}

class _AuraStorageUsageCardState extends ConsumerState<AuraStorageUsageCard> {
  StorageUsageBreakdown? _breakdown;
  bool _isLoading = true;
  bool _isClearingCache = false;
  DateTime? _lastDownloadNotification;

  @override
  void initState() {
    super.initState();
    _loadStorageUsage();
    DownloadService.instance.addListener(_onDownloadChange);
  }

  @override
  void dispose() {
    DownloadService.instance.removeListener(_onDownloadChange);
    super.dispose();
  }

  void _onDownloadChange() {
    if (!mounted) return;
    final now = DateTime.now();
    // Throttle during active file downloads
    if (_lastDownloadNotification != null &&
        now.difference(_lastDownloadNotification!) < const Duration(seconds: 4)) {
      return;
    }
    _lastDownloadNotification = now;
    _loadStorageUsage(forceRefresh: true);
  }

  Future<void> _loadStorageUsage({bool forceRefresh = false}) async {
    try {
      final data = await StorageUsageHelper.getBreakdown(forceRefresh: forceRefresh);
      if (mounted) {
        setState(() {
          _breakdown = data;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _breakdown = const StorageUsageBreakdown(
            downloadedMusicBytes: 0,
            coverBytes: 0,
            cacheBytes: 0,
            totalAppBytes: 0,
            downloadedPlaylists: [],
            totalDownloadedTracks: 0,
          );
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _handleClearCache() async {
    setState(() => _isClearingCache = true);
    await StorageUsageHelper.clearTemporaryCache();
    await _loadStorageUsage(forceRefresh: true);
    if (mounted) {
      setState(() => _isClearingCache = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          backgroundColor: const Color(0xFF2E7D32),
          content: const Row(
            children: [
              Icon(Icons.check_circle_rounded, color: Colors.white, size: 20),
              SizedBox(width: 10),
              Text('Temporary cache cleared successfully!'),
            ],
          ),
        ),
      );
    }
  }

  void _openDetailsModal() {
    if (_breakdown == null) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => DownloadedPlaylistsStorageModal(
        breakdown: _breakdown!,
        onStorageChanged: _loadStorageUsage,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;

    if (_isLoading) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161616) : Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: const Center(
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 24),
            child: CircularProgressIndicator(),
          ),
        ),
      );
    }

    final data = _breakdown!;
    final total = max(1, data.totalAppBytes);
    final musicRatio = (data.downloadedMusicBytes / total).clamp(0.0, 1.0);
    final coverRatio = (data.coverBytes / total).clamp(0.0, 1.0);
    final cacheRatio = (data.cacheBytes / total).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151515) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.05),
            blurRadius: 14,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Top Header Row
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.storage_rounded, color: accent, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Aura Storage Usage',
                      style: TextStyle(
                        fontFamily: 'Outfit',
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Offline songs, album covers & app cache',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.black54,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh_rounded, size: 20),
                tooltip: 'Refresh Storage',
                onPressed: _loadStorageUsage,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Big Storage Number Callout
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                data.formattedTotal,
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  fontFamily: 'Outfit',
                  color: isDark ? Colors.white : Colors.black87,
                  letterSpacing: -0.5,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                'used by Aura',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: accent.withValues(alpha: 0.25)),
                ),
                child: Text(
                  '${data.totalDownloadedTracks} tracks saved',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: accent,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 14),

          // Multi-segment Visual Progress Bar (Songs, Cover, Cache)
          ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: Container(
              height: 12,
              width: double.infinity,
              color: isDark ? const Color(0xFF242424) : const Color(0xFFE5E5E5),
              child: data.totalAppBytes == 0
                  ? const SizedBox.shrink()
                  : Row(
                      children: [
                        if (musicRatio > 0)
                          Expanded(
                            flex: max(1, (musicRatio * 1000).round()),
                            child: Container(
                              color: accent,
                            ),
                          ),
                        if (coverRatio > 0)
                          Expanded(
                            flex: max(1, (coverRatio * 1000).round()),
                            child: Container(
                              color: const Color(0xFF38BDF8),
                            ),
                          ),
                        if (cacheRatio > 0)
                          Expanded(
                            flex: max(1, (cacheRatio * 1000).round()),
                            child: Container(
                              color: const Color(0xFFF59E0B),
                            ),
                          ),
                      ],
                    ),
            ),
          ),

          const SizedBox(height: 12),

          // Category Legend Chips (Songs, Cover, Cache)
          Wrap(
            spacing: 14,
            runSpacing: 8,
            children: [
              _buildLegendItem(
                color: accent,
                label: 'Songs',
                size: data.formattedMusic,
                isDark: isDark,
              ),
              _buildLegendItem(
                color: const Color(0xFF38BDF8),
                label: 'Cover',
                size: data.formattedCover,
                isDark: isDark,
              ),
              _buildLegendItem(
                color: const Color(0xFFF59E0B),
                label: 'Cache',
                size: data.formattedCache,
                isDark: isDark,
              ),
            ],
          ),

          const SizedBox(height: 16),
          const Divider(height: 1),
          const SizedBox(height: 14),

          // Actions Row: "View Details" & "Clear Cache"
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: accent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  icon: const Icon(Icons.analytics_outlined, size: 18),
                  label: const Text(
                    'View Details',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                  ),
                  onPressed: _openDetailsModal,
                ),
              ),
              const SizedBox(width: 10),
              OutlinedButton.icon(
                style: OutlinedButton.styleFrom(
                  foregroundColor: isDark ? Colors.white70 : Colors.black87,
                  side: BorderSide(
                    color: isDark ? Colors.white24 : Colors.black12,
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                icon: _isClearingCache
                    ? const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.cleaning_services_rounded, size: 16),
                label: const Text(
                  'Clean Cache',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                ),
                onPressed: _isClearingCache ? null : _handleClearCache,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem({
    required Color color,
    required String label,
    required String size,
    required bool isDark,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        Text(
          '$label ',
          style: TextStyle(
            fontSize: 11,
            color: isDark ? Colors.white70 : Colors.black87,
          ),
        ),
        Text(
          size,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.bold,
            color: isDark ? Colors.white : Colors.black,
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// POPUP DETAILS MODAL: PER-PLAYLIST BREAKDOWN
// ============================================================================

class DownloadedPlaylistsStorageModal extends ConsumerStatefulWidget {
  final StorageUsageBreakdown breakdown;
  final VoidCallback onStorageChanged;

  const DownloadedPlaylistsStorageModal({
    super.key,
    required this.breakdown,
    required this.onStorageChanged,
  });

  @override
  ConsumerState<DownloadedPlaylistsStorageModal> createState() =>
      _DownloadedPlaylistsStorageModalState();
}

class _DownloadedPlaylistsStorageModalState
    extends ConsumerState<DownloadedPlaylistsStorageModal> {
  late StorageUsageBreakdown _currentBreakdown;
  bool _isDeleting = false;

  @override
  void initState() {
    super.initState();
    _currentBreakdown = widget.breakdown;
  }

  Future<void> _refreshData() async {
    final updated = await StorageUsageHelper.getBreakdown(forceRefresh: true);
    if (mounted) {
      setState(() => _currentBreakdown = updated);
      widget.onStorageChanged();
    }
  }

  Future<void> _confirmDeletePlaylistDownloads(PlaylistStorageDetail playlist) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${playlist.name}" Downloads?'),
        content: Text(
          'This will remove ${playlist.downloadedTracksCount} offline downloaded songs (${playlist.formattedSize}) from device storage.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Downloads'),
          ),
        ],
      ),
    );

    if (confirm == true && mounted) {
      setState(() => _isDeleting = true);
      for (final trackId in playlist.downloadedTrackIds) {
        await DownloadService.instance.deleteDownload(trackId);
      }
      if (playlist.id.startsWith('dl_')) {
        await StorageService.deleteDownloadedPlaylist(playlist.name);
      }
      await _refreshData();
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: const Color(0xFF2E7D32),
            content: Text('Removed ${playlist.formattedSize} from "${playlist.name}".'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final playlists = _currentBreakdown.downloadedPlaylists;
    final totalMusicBytes = max(1, _currentBreakdown.downloadedMusicBytes);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.85,
        maxWidth: 580,
      ),
      margin: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 20,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141414) : const Color(0xFFFBFBFB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        border: Border.all(
          color: isDark ? Colors.white10 : Colors.black12,
        ),
      ),
      child: Column(
        children: [
          // Drag handle
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 44,
            height: 4.5,
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black26,
              borderRadius: BorderRadius.circular(3),
            ),
          ),

          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 12, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: accent.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.folder_special_rounded, color: accent, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Downloaded Playlists Storage',
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontWeight: FontWeight.bold,
                          fontSize: 17,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Storage space utilized by offline tracks',
                        style: TextStyle(
                          fontSize: 12,
                          color: isDark ? Colors.white54 : Colors.black54,
                        ),
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

          const Divider(height: 1),

          // Summary Overview Banner
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: accent.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.download_done_rounded, color: accent, size: 24),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${_currentBreakdown.formattedMusic} offline audio saved',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                            color: isDark ? Colors.white : Colors.black87,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${playlists.length} playlists · ${_currentBreakdown.totalDownloadedTracks} total songs stored on device',
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Playlists List
          Expanded(
            child: _isDeleting
                ? const Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text('Removing offline files...'),
                      ],
                    ),
                  )
                : playlists.isEmpty
                    ? _buildEmptyState(isDark, accent)
                    : ListView.separated(
                        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                        itemCount: playlists.length,
                        separatorBuilder: (_, __) => const SizedBox(height: 8),
                        itemBuilder: (context, index) {
                          final pl = playlists[index];
                          final percentOfMusic =
                              ((pl.totalBytes / totalMusicBytes) * 100).clamp(0.0, 100.0);

                          return Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: isDark ? const Color(0xFF1C1C1C) : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: Border.all(
                                color: isDark ? Colors.white10 : Colors.black12,
                              ),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    // Thumbnail / Icon
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(10),
                                      child: Container(
                                        width: 44,
                                        height: 44,
                                        color: accent.withValues(alpha: 0.15),
                                        child: pl.coverUrl != null && pl.coverUrl!.isNotEmpty
                                            ? AppArtworkImage(
                                                artworkUrl: pl.coverUrl!,
                                                width: 44,
                                                height: 44,
                                              )
                                            : Icon(
                                                pl.id == 'favorites'
                                                    ? Icons.favorite_rounded
                                                    : Icons.queue_music_rounded,
                                                color: accent,
                                                size: 22,
                                              ),
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    // Title & Track Count
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            pl.name,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            '${pl.downloadedTracksCount} songs offline (${percentOfMusic.toStringAsFixed(0)}% of downloads)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark ? Colors.white54 : Colors.black54,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    // Size Tag
                                    Container(
                                      padding: const EdgeInsets.symmetric(
                                          horizontal: 10, vertical: 5),
                                      decoration: BoxDecoration(
                                        color: accent.withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        pl.formattedSize,
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          fontSize: 12,
                                          color: accent,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 4),
                                    // Delete downloads icon button
                                    IconButton(
                                      icon: const Icon(Icons.delete_outline_rounded,
                                          size: 20, color: Colors.redAccent),
                                      tooltip: 'Delete offline songs',
                                      onPressed: () => _confirmDeletePlaylistDownloads(pl),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // Mini proportion bar
                                ClipRRect(
                                  borderRadius: BorderRadius.circular(4),
                                  child: LinearProgressIndicator(
                                    value: (percentOfMusic / 100).clamp(0.0, 1.0),
                                    minHeight: 4,
                                    backgroundColor:
                                        isDark ? Colors.white10 : Colors.black12,
                                    valueColor: AlwaysStoppedAnimation<Color>(accent),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState(bool isDark, Color accent) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_download_outlined, size: 40, color: accent),
            ),
            const SizedBox(height: 16),
            const Text(
              'No Offline Playlists Found',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            const SizedBox(height: 6),
            Text(
              'Download individual tracks or playlists from your Library to listen without internet. Storage used by each playlist will appear here.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                color: isDark ? Colors.white54 : Colors.black54,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
