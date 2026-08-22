
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:palette_generator/palette_generator.dart';
import 'package:shimmer/shimmer.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../services/ai/song_summary_service.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../widgets/custom_slider_track_shapes.dart';
import '../../widgets/waveform_seek_bar.dart';
import '../../themes/app_theme.dart';
import '../splash/splash_screen.dart';
import '../equalizer/equalizer_screen.dart';
import 'lyrics_screen.dart';

class NowPlayingScreen extends ConsumerStatefulWidget {
  const NowPlayingScreen({super.key});

  @override
  ConsumerState<NowPlayingScreen> createState() => _NowPlayingScreenState();
}

class _NowPlayingScreenState extends ConsumerState<NowPlayingScreen> with TickerProviderStateMixin {
  late AnimationController _spinController;
  double _lastAngle = 0.0;
  
  // Deceleration angle tracker
  late AnimationController _decelController;
  late Animation<double> _decelAngleAnimation;
  Offset _albumDragOffset = Offset.zero;

  // Smooth seeking slider state
  bool _isDraggingProgress = false;
  double _dragProgressValue = 0.0;

  // Song Summary state
  SongSummary? _songSummary;
  bool _isSummaryLoading = false;
  bool _isSummaryExpanded = true;
  String? _lastSummaryTrackId;

  // Synced lyrics state
  LyricsResult? _lyricsResult;
  String? _lastLyricsTrackId;

  // Dynamic theming state
  Color? _dynamicAccentColor;
  String? _lastPaletteTrackId;

  // Karaoke lyrics state
  final ScrollController _lyricsScrollController = ScrollController();
  int _activeLyricIndex = -1;
  int? _tappedLyricIndex;

  void _fetchLyrics(Track track) {
    if (_lastLyricsTrackId == track.id) return;
    _lastLyricsTrackId = track.id;

    LyricsService.instance.fetchLyrics(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      durationStr: track.duration,
    ).then((res) {
      if (mounted && _lastLyricsTrackId == track.id) {
        setState(() {
          _lyricsResult = res;
        });
      }
    }).catchError((_) {});
  }

  void _extractPaletteColor(Track track) {
    if (_lastPaletteTrackId == track.id || track.artworkUrl.isEmpty) return;
    _lastPaletteTrackId = track.id;

    PaletteGenerator.fromImageProvider(
      NetworkImage(track.artworkUrl),
      size: const Size(100, 100),
    ).then((palette) {
      if (mounted && _lastPaletteTrackId == track.id) {
        final extracted = palette.vibrantColor?.color ??
            palette.dominantColor?.color ??
            palette.lightVibrantColor?.color ??
            palette.darkVibrantColor?.color;
        if (extracted != null) {
          setState(() {
            _dynamicAccentColor = extracted;
          });
        }
      }
    }).catchError((_) {});
  }

  // Heart pop animation state
  late AnimationController _heartController;

  // Stacked queue preview & drag shuffle state
  bool _showQueuePreview = false;
  int _queueDragIndex = -1;
  double _accumulatedDragY = 0.0;
  bool _hasDraggedQueue = false;

  @override
  void initState() {
    super.initState();
    _spinController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    );
    _decelController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _heartController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(playbackProvider).isPlaying) {
        _spinController.repeat();
      }
      if (!StorageService.hasSeenPlayerTutorial()) {
        _showPlayerTutorialModal();
      }
    });
  }

  @override
  void dispose() {
    _spinController.dispose();
    _decelController.dispose();
    _heartController.dispose();
    _lyricsScrollController.dispose();
    super.dispose();
  }

  void _syncAnimations(bool isPlaying) {
    if (isPlaying) {
      if (_decelController.isAnimating) {
        _lastAngle = _decelAngleAnimation.value % (2 * math.pi);
        _decelController.stop();
      }
      if (!_spinController.isAnimating) {
        _spinController.repeat();
      }
    } else {
      if (_spinController.isAnimating) {
        _lastAngle = (_spinController.value * 2 * math.pi) % (2 * math.pi);
        _spinController.stop();
        _decelAngleAnimation = Tween<double>(begin: _lastAngle, end: _lastAngle + (math.pi / 8)).animate(
          CurvedAnimation(parent: _decelController, curve: Curves.decelerate)
        );
        _decelController.forward(from: 0.0);
      }
    }
  }

  String _formatDuration(Duration duration) {
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final minutes = duration.inMinutes;
    final seconds = duration.inSeconds.remainder(60);
    return '$minutes:${twoDigits(seconds)}';
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final customBranding = ref.watch(customizationProvider);
    
    _syncAnimations(state.isPlaying);

    if (state.currentTrack == null) {
      return const Scaffold(body: Center(child: Text('No song playing')));
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = state.currentTrack!;

    _fetchLyrics(track);
    _extractPaletteColor(track);

    final targetAccent = _dynamicAccentColor ?? customBranding.accentColor;

    final List<Color> bgColors = isDark
        ? [const Color(0xFF1B1B1D), const Color(0xFF0C0C0E)]
        : [const Color(0xFFFAF7F2), const Color(0xFFE8E2D7)];

    double angle = 0.0;
    if (_decelController.isAnimating) {
      angle = _decelAngleAnimation.value;
    } else if (state.isPlaying) {
      angle = _spinController.value * 2 * math.pi;
    } else {
      angle = _lastAngle;
    }

    final isFav = StorageService.isFavorite('trackIds', track.id);

    // ── Screen Theme Layout Routing ─────────────────────────────
    if (state.playerScreenTheme == 'android_11_theme') {
      return _buildAndroid11ThemeScreen(state, notifier, track, targetAccent, isDark, isFav);
    } else if (state.playerScreenTheme == 'android_16_theme') {
      return _buildAndroid16ThemeScreen(state, notifier, track, targetAccent, isDark, isFav);
    } else if (state.playerScreenTheme == 'apple_music_theme') {
      return _buildAppleMusicThemeScreen(state, notifier, track, targetAccent, isDark, isFav);
    } else if (state.playerScreenTheme == 'minimal_theme') {
      return _buildMinimalThemeScreen(state, notifier, track, targetAccent, isDark, isFav);
    }

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: TweenAnimationBuilder<Color?>(
        duration: const Duration(milliseconds: 400),
        tween: ColorTween(begin: targetAccent, end: targetAccent),
        builder: (context, currentAccentColor, child) {
          final activeAccent = currentAccentColor ?? targetAccent;

          return Container(
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: bgColors,
              ),
              borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
            ),
            child: Stack(
              children: [
                // Dynamic cover art blur glow layer
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: const Alignment(0, -0.4),
                          radius: 0.85,
                          colors: [
                            activeAccent.withValues(alpha: isDark ? 0.28 : 0.20),
                            Colors.transparent,
                          ],
                        ),
                      ),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                        child: Container(color: Colors.transparent),
                      ),
                    ),
                  ),
                ),

                // Main player content
                SafeArea(
                  bottom: false,
                  child: SingleChildScrollView(
                    physics: const ClampingScrollPhysics(),
            child: Column(
              children: [
                const SizedBox(height: 12),
                Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: (isDark ? Colors.white : Colors.black).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 12),

                // Header Top Row (Top Middle Title)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, size: 28, color: isDark ? Colors.white.withValues(alpha: 0.95) : Colors.black87),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              track.title.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                letterSpacing: 1.5,
                                fontSize: 13,
                                fontWeight: FontWeight.w900,
                                color: isDark ? Colors.white : Colors.black87,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              track.artist.toUpperCase(),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                letterSpacing: 1.0,
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          ListenableBuilder(
                            listenable: DownloadService.instance,
                            builder: (context, _) {
                              final isDownloaded = DownloadService.instance.isDownloaded(track.id);
                              final task = DownloadService.instance.tasks[track.id];
                              final isDownloading = task?.status == 'downloading';

                              if (isDownloading) {
                                return SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5, color: customBranding.accentColor),
                                );
                              }
                              if (isDownloaded) {
                                return IconButton(
                                  icon: Icon(Icons.download_done_rounded, color: customBranding.accentColor, size: 22),
                                  onPressed: () {},
                                );
                              }
                              return IconButton(
                                icon: Icon(Icons.download_rounded, color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black54, size: 22),
                                onPressed: () {
                                  DownloadService.instance.startDownload(track);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Downloading "${track.title}" for offline playback...'),
                                      duration: const Duration(seconds: 2),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                },
                              );
                            },
                          ),
                          IconButton(
                            icon: Icon(Icons.playlist_add_rounded, color: isDark ? Colors.white.withValues(alpha: 0.8) : Colors.black54, size: 24),
                            tooltip: 'Add to Playlist',
                            onPressed: () {
                              triggerHaptic(HapticFeedbackType.selection);
                              _showAddToPlaylistBottomSheet(track);
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Dynamic Skin Stages with Physics Swipe Gestures & H.2 Press-and-Drag Queue Interaction
                GestureDetector(
                  onDoubleTap: () async {
                    triggerHaptic(HapticFeedbackType.medium);
                    await StorageService.toggleFavoriteTrack(track);
                    if (StorageService.isFavorite('trackIds', track.id)) {
                      ref.read(playbackProvider.notifier).onTrackLiked(track);
                    }
                    _heartController.forward(from: 0.0);
                    setState(() {});
                  },
                  onLongPressStart: (details) {
                    triggerHaptic(HapticFeedbackType.medium);
                    setState(() {
                      _showQueuePreview = true;
                      _queueDragIndex = state.currentIndex >= 0 ? state.currentIndex : 0;
                      _accumulatedDragY = 0.0;
                      _hasDraggedQueue = false;
                    });
                  },
                  onLongPressMoveUpdate: (details) {
                    final dy = details.offsetFromOrigin.dy;
                    final deltaY = dy - _accumulatedDragY;
                    const stepThreshold = 45.0;

                    if (deltaY.abs() > stepThreshold) {
                      _accumulatedDragY = dy;
                      _hasDraggedQueue = true;

                      final queue = state.queue;
                      if (queue.isNotEmpty) {
                        if (deltaY < 0) {
                          // Drag UP -> Shuffle to next card in queue
                          if (_queueDragIndex + 1 < queue.length) {
                            setState(() {
                              _queueDragIndex++;
                            });
                            triggerHaptic(HapticFeedbackType.light);
                          } else {
                            // Boundary signal (Double light haptic)
                            triggerHaptic(HapticFeedbackType.light);
                            Future.delayed(const Duration(milliseconds: 60), () => triggerHaptic(HapticFeedbackType.light));
                          }
                        } else {
                          // Drag DOWN -> Shuffle to previous card in queue
                          if (_queueDragIndex - 1 >= 0) {
                            setState(() {
                              _queueDragIndex--;
                            });
                            triggerHaptic(HapticFeedbackType.light);
                          } else {
                            // Boundary signal (Double light haptic)
                            triggerHaptic(HapticFeedbackType.light);
                            Future.delayed(const Duration(milliseconds: 60), () => triggerHaptic(HapticFeedbackType.light));
                          }
                        }
                      }
                    }
                  },
                  onLongPressEnd: (details) {
                    final queue = state.queue;
                    if (_hasDraggedQueue && _queueDragIndex >= 0 && _queueDragIndex < queue.length && _queueDragIndex != state.currentIndex) {
                      // Release after drag plays selected track without changing queue order
                      triggerHaptic(HapticFeedbackType.medium);
                      notifier.jumpToQueueIndex(_queueDragIndex);
                    }
                    // Clean reset on release
                    setState(() {
                      _showQueuePreview = false;
                      _hasDraggedQueue = false;
                      _queueDragIndex = -1;
                      _accumulatedDragY = 0.0;
                    });
                  },
                  onPanUpdate: (details) {
                    if (!_showQueuePreview) {
                      setState(() {
                        _albumDragOffset += details.delta;
                      });
                    }
                  },
                  onPanEnd: (details) async {
                    if (_showQueuePreview) return;
                    final dx = _albumDragOffset.dx;
                    final dy = _albumDragOffset.dy;

                    if (dx.abs() > dy.abs()) {
                      if (dx < -80) {
                        // Swipe Left -> Next Track
                        triggerHaptic(HapticFeedbackType.medium);
                        notifier.nextTrack();
                      } else if (dx > 80) {
                        // Swipe Right -> Previous Track
                        triggerHaptic(HapticFeedbackType.medium);
                        notifier.previousTrack();
                      }
                    } else {
                      if (dy < -80) {
                        // Swipe Up -> Toggle Favorite
                        triggerHaptic(HapticFeedbackType.medium);
                        await StorageService.toggleFavoriteTrack(track);
                        if (StorageService.isFavorite('trackIds', track.id)) {
                          ref.read(playbackProvider.notifier).onTrackLiked(track);
                        }
                        _heartController.forward(from: 0.0);
                        setState(() {});
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(StorageService.isFavorite('trackIds', track.id) ? 'Added to Favorites ❤️' : 'Removed from Favorites'),
                              duration: const Duration(seconds: 1),
                              behavior: SnackBarBehavior.floating,
                            ),
                          );
                        }
                      } else if (dy > 80) {
                        // Swipe Down -> Add to Playlist
                        triggerHaptic(HapticFeedbackType.medium);
                        _showAddToPlaylistBottomSheet(track);
                      }
                    }

                    // Physics spring back bounce
                    setState(() {
                      _albumDragOffset = Offset.zero;
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    curve: Curves.easeOutBack,
                    transform: Matrix4.translationValues(_albumDragOffset.dx, _albumDragOffset.dy, 0),
                    width: MediaQuery.of(context).size.width,
                    height: MediaQuery.of(context).size.width * 0.82,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Interactive 3D Deck of Cards Stack Queue Preview
                        if (_showQueuePreview) ...[
                          Builder(
                            builder: (context) {
                              final queue = state.queue;
                              if (queue.isEmpty) {
                                return Center(
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                    decoration: BoxDecoration(
                                      color: Colors.black87,
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: const Text('Queue is empty', style: TextStyle(color: Colors.white, fontSize: 12)),
                                  ),
                                );
                              }

                              final focusedIdx = (_queueDragIndex >= 0 && _queueDragIndex < queue.length)
                                  ? _queueDragIndex
                                  : (state.currentIndex >= 0 ? state.currentIndex : 0);

                              // Pre-cache nearby artwork for smooth 60 FPS transitions
                              for (int i = math.max(0, focusedIdx - 2); i <= math.min(queue.length - 1, focusedIdx + 2); i++) {
                                if (queue[i].artworkUrl.isNotEmpty) {
                                  precacheImage(NetworkImage(queue[i].artworkUrl), context);
                                }
                              }

                              final visibleIndices = <int>[];
                              for (int offset = -2; offset <= 2; offset++) {
                                final idx = focusedIdx + offset;
                                if (idx >= 0 && idx < queue.length) {
                                  visibleIndices.add(idx);
                                }
                              }

                              return Stack(
                                alignment: Alignment.center,
                                children: [
                                  // Instructions Legend Banner
                                  Positioned(
                                    top: 8,
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withOpacity(0.85),
                                        borderRadius: BorderRadius.circular(16),
                                        border: Border.all(color: customBranding.accentColor.withOpacity(0.6), width: 1.0),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.touch_app_rounded, size: 14, color: customBranding.accentColor),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'Drag up/down to shuffle • Release to play track',
                                            style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  ...visibleIndices.map((idx) {
                                  final itemTrack = queue[idx];
                                  final dist = idx - focusedIdx;
                                  final isFocused = (idx == focusedIdx);

                                  final double offsetY = dist * 52.0;
                                  final double scale = (1.0 - (dist.abs() * 0.10)).clamp(0.72, 1.05);
                                  final double opacity = (1.0 - (dist.abs() * 0.25)).clamp(0.35, 1.0);
                                  final double tiltAngle = dist * 0.07;

                                  final Matrix4 transform = Matrix4.identity()
                                    ..setEntry(3, 2, 0.001)
                                    ..rotateX(tiltAngle)
                                    ..translate(0.0, offsetY, 0.0);

                                  return Transform(
                                    transform: transform,
                                    alignment: Alignment.center,
                                    child: Transform.scale(
                                      scale: scale,
                                      child: Opacity(
                                        opacity: opacity,
                                        child: GestureDetector(
                                          onTap: () {
                                            triggerHaptic(HapticFeedbackType.medium);
                                            notifier.jumpToQueueIndex(idx);
                                            setState(() => _showQueuePreview = false);
                                          },
                                          child: AnimatedContainer(
                                            duration: const Duration(milliseconds: 180),
                                            curve: Curves.easeOutCubic,
                                            width: MediaQuery.of(context).size.width * 0.78,
                                            height: 78,
                                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: isFocused
                                                  ? (isDark ? const Color(0xFF28282E) : Colors.white)
                                                  : (isDark ? const Color(0xFF1E1E22) : const Color(0xFFF0EAE1)),
                                              borderRadius: BorderRadius.circular(20),
                                              border: isFocused
                                                  ? Border.all(color: customBranding.accentColor, width: 2.0)
                                                  : Border.all(color: Colors.grey.withOpacity(0.2), width: 1.0),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: isFocused
                                                      ? customBranding.accentColor.withOpacity(0.35)
                                                      : Colors.black.withOpacity(0.20),
                                                  blurRadius: isFocused ? 18 : 8,
                                                  offset: Offset(0, isFocused ? 6 : 3),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              children: [
                                                ClipRRect(
                                                  borderRadius: BorderRadius.circular(12),
                                                  child: Image.network(
                                                    itemTrack.artworkUrl,
                                                    width: 52,
                                                    height: 52,
                                                    fit: BoxFit.cover,
                                                    errorBuilder: (_, __, ___) => Container(width: 52, height: 52, color: Colors.grey.shade800, child: const Icon(Icons.music_note_rounded)),
                                                  ),
                                                ),
                                                const SizedBox(width: 12),
                                                Expanded(
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        isFocused
                                                            ? (idx == state.currentIndex ? 'NOW PLAYING 🎵' : 'RELEASE TO PLAY ⚡')
                                                            : 'UP NEXT #${idx + 1}',
                                                        style: TextStyle(
                                                          fontSize: 10,
                                                          fontWeight: FontWeight.bold,
                                                          color: isFocused ? customBranding.accentColor : Colors.grey,
                                                          letterSpacing: 0.8,
                                                        ),
                                                      ),
                                                      const SizedBox(height: 2),
                                                      Text(
                                                        itemTrack.title,
                                                        style: TextStyle(
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: isFocused ? 14 : 13,
                                                        ),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                      Text(
                                                        itemTrack.artist,
                                                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                                                        maxLines: 1,
                                                        overflow: TextOverflow.ellipsis,
                                                      ),
                                                    ],
                                                  ),
                                                ),
                                                Icon(
                                                  isFocused ? Icons.play_circle_fill_rounded : Icons.music_note_rounded,
                                                  size: isFocused ? 30 : 22,
                                                  color: isFocused ? customBranding.accentColor : Colors.grey,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                                ],
                              );
                            },
                          ),
                        ],

                        // Main Skin Stage (Vinyl / CD / Cassette / Minimal)
                        if (!_showQueuePreview)
                          _buildSkinStage(state.playerSkin, track, angle, isDark, customBranding.accentColor),

                        // Double-tap Animated Heart Pop Overlay
                        AnimatedBuilder(
                          animation: _heartController,
                          builder: (context, child) {
                            if (!_heartController.isAnimating) return const SizedBox.shrink();
                            final scale = 0.5 + (_heartController.value * 0.9);
                            final opacity = 1.0 - _heartController.value;
                            return Opacity(
                              opacity: opacity.clamp(0.0, 1.0),
                              child: Transform.scale(
                                scale: scale,
                                child: Icon(
                                  Icons.favorite_rounded,
                                  color: customBranding.accentColor,
                                  size: 110,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),

                // Mini Gesture Legend
                Padding(
                  padding: const EdgeInsets.only(top: 8, bottom: 4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                    decoration: BoxDecoration(
                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.06),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: const [
                        Text('↔️ Swipe Track', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('👆 Favorite', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('👇 Queue', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Title & Artist Metadata
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Column(
                    children: [
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontSize: 22,
                              fontWeight: FontWeight.w900,
                              letterSpacing: -0.5,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        track.artist,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w500,
                              color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary).withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Progress Slider
                Builder(
                  builder: (context) {
                    final sliderValue = _isDraggingProgress
                        ? _dragProgressValue.clamp(0.0, 1.0)
                        : state.progress.clamp(0.0, 1.0);
                    final currentDisplayPosition = _isDraggingProgress
                        ? Duration(milliseconds: (_dragProgressValue * state.totalDuration.inMilliseconds).round())
                        : state.currentPosition;

                    final isWaveformStyle = StorageService.getProgressBarStyle() == 'waveform';

                    return Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Column(
                        children: [
                          if (isWaveformStyle)
                            WaveformSeekBar(
                              track: track,
                              progress: sliderValue,
                              currentPosition: currentDisplayPosition,
                              totalDuration: state.totalDuration,
                              activeColor: customBranding.accentColor,
                              isDark: isDark,
                              onChangeStart: (val) {
                                triggerHaptic(HapticFeedbackType.selection);
                                setState(() {
                                  _isDraggingProgress = true;
                                  _dragProgressValue = val;
                                });
                              },
                              onChanged: (val) {
                                setState(() {
                                  _dragProgressValue = val;
                                });
                              },
                              onChangeEnd: (val) {
                                notifier.seek(val);
                                setState(() {
                                  _isDraggingProgress = false;
                                });
                              },
                            )
                          else
                            SliderTheme(
                              data: SliderTheme.of(context).copyWith(
                                trackHeight: 3.5,
                                activeTrackColor: customBranding.accentColor,
                                thumbColor: customBranding.accentColor,
                                trackShape: resolveSliderTrackShape(StorageService.getProgressBarStyle()),
                                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                                overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                              ),
                              child: Slider(
                                value: sliderValue,
                                onChangeStart: (val) {
                                  triggerHaptic(HapticFeedbackType.selection);
                                  setState(() {
                                    _isDraggingProgress = true;
                                    _dragProgressValue = val;
                                  });
                                },
                                onChanged: (val) {
                                  setState(() {
                                    _dragProgressValue = val;
                                  });
                                },
                                onChangeEnd: (val) {
                                  notifier.seek(val);
                                  setState(() {
                                    _isDraggingProgress = false;
                                  });
                                },
                              ),
                            ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(_formatDuration(currentDisplayPosition), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                                Text(_formatDuration(state.totalDuration), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                              ],
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),

                const SizedBox(height: 16),

                // Controls: Shuffle, Previous, Play/Pause, Next, Repeat
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shuffle_rounded, 
                          color: state.isShuffle ? customBranding.accentColor : Colors.grey, 
                          size: 22
                        ),
                        onPressed: () {
                          notifier.toggleShuffle();
                        },
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 36),
                        onPressed: () => notifier.previousTrack(),
                      ),
                      GestureDetector(
                        onTap: () => notifier.togglePlay(),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: customBranding.accentColor,
                            shape: BoxShape.circle,
                            boxShadow: const [
                              BoxShadow(color: Colors.black26, blurRadius: 10, offset: Offset(0, 5))
                            ],
                          ),
                          child: (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.buffering)
                              ? Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                                    ),
                                  ),
                                )
                              : Icon(
                                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: isDark ? Colors.black : Colors.white,
                                  size: 36,
                                ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 36),
                        onPressed: () => notifier.nextTrack(),
                      ),
                      IconButton(
                        icon: Icon(
                          state.repeatMode == RepeatMode.one 
                              ? Icons.repeat_one_rounded 
                              : Icons.repeat_rounded,
                          color: state.repeatMode != RepeatMode.off ? customBranding.accentColor : Colors.grey,
                          size: 22,
                        ),
                        onPressed: () {
                          final nextMode = {
                            RepeatMode.off: RepeatMode.all,
                            RepeatMode.all: RepeatMode.one,
                            RepeatMode.one: RepeatMode.off,
                          }[state.repeatMode]!;
                          notifier.setRepeatMode(nextMode);
                        },
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Bottom row: Sleep timer, Lyrics, Equalizer, Speed, Queue (G.3 Redesigned)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      // Sleep Timer Option
                      _buildActionButton(
                        icon: Icons.timer_rounded,
                        label: 'Timer',
                        isActive: state.sleepTimerMinutes != null || state.isSleepTimerEndOfTrack,
                        accentColor: customBranding.accentColor,
                        onTap: () => _showSleepTimerDialog(notifier),
                      ),

                      // Synced Lyrics Option
                      _buildActionButton(
                        icon: Icons.lyrics_rounded,
                        label: 'Lyrics',
                        isActive: _lyricsResult != null && _lyricsResult!.hasLyrics,
                        accentColor: customBranding.accentColor,
                        onTap: (_lyricsResult != null && _lyricsResult!.hasLyrics)
                            ? () {
                                Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => LyricsScreen(
                                      track: track,
                                      lyricsResult: _lyricsResult!,
                                    ),
                                  ),
                                );
                              }
                            : () {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Fetching lyrics for this track...'), duration: Duration(seconds: 1)),
                                );
                              },
                      ),

                      // Equalizer Option
                      _buildActionButton(
                        icon: Icons.graphic_eq_rounded,
                        label: 'EQ',
                        isActive: false,
                        accentColor: customBranding.accentColor,
                        onTap: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const EqualizerScreen()));
                        },
                      ),

                      // Playback Speed Option
                      _buildActionButton(
                        icon: Icons.speed_rounded,
                        label: '${state.playbackSpeed}x',
                        isActive: state.playbackSpeed != 1.0,
                        accentColor: customBranding.accentColor,
                        onTap: () => _showPlaybackSpeedDialog(notifier),
                      ),

                      // Active Queue Option
                      _buildActionButton(
                        icon: Icons.queue_music_rounded,
                        label: 'Queue',
                        isActive: false,
                        accentColor: customBranding.accentColor,
                        onTap: () => _showQueueBottomSheet(state, notifier),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // ── Song Summary Section ──────────────────────
                _buildSongSummarySection(track, isDark, customBranding.accentColor),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ],
    ),
  );
},
),
);
}

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required bool isActive,
    required Color accentColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return InkWell(
      onTap: () {
        triggerHaptic(HapticFeedbackType.selection);
        onTap();
      },
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 22,
              color: isActive ? accentColor : (isDark ? Colors.white60 : Colors.black54),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: isActive ? FontWeight.bold : FontWeight.w500,
                color: isActive ? accentColor : (isDark ? Colors.white54 : Colors.black54),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Skin Stage Switcher ────────────────────────────────────────

  void _fetchSongSummary(Track track, {bool forceRefresh = false}) {
    if (WidgetsBinding.instance.lifecycleState != null && 
        WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }

    final activeTrackId = track.id;

    if (forceRefresh || _lastSummaryTrackId != activeTrackId) {
      setState(() {
        _songSummary = null;
        _isSummaryLoading = true;
        _lastSummaryTrackId = activeTrackId;
      });
    } else if (_isSummaryLoading && !forceRefresh) {
      return;
    }

    String? lyricsText;
    if (_lyricsResult != null) {
      if (_lyricsResult!.synced != null && _lyricsResult!.synced!.isNotEmpty) {
        lyricsText = _lyricsResult!.synced!.map((l) => l.text).join('\n');
      } else if (_lyricsResult!.plain != null && _lyricsResult!.plain!.isNotEmpty) {
        lyricsText = _lyricsResult!.plain;
      }
    }

    SongSummaryService.instance.getSummary(
      trackId: track.id,
      title: track.title,
      artist: track.artist,
      album: track.album,
      genre: track.genre,
      lyricsText: lyricsText,
      forceRefresh: forceRefresh,
    ).then((summary) {
      final currentTrackId = ref.read(playbackProvider).currentTrack?.id;
      if (mounted && _lastSummaryTrackId == activeTrackId && currentTrackId == activeTrackId) {
        setState(() {
          _songSummary = summary;
          _isSummaryLoading = false;
        });
      }
    }).catchError((_) {
      final currentTrackId = ref.read(playbackProvider).currentTrack?.id;
      if (mounted && _lastSummaryTrackId == activeTrackId && currentTrackId == activeTrackId) {
        setState(() => _isSummaryLoading = false);
      }
    });
  }

  Widget _buildSongSummarySection(Track track, bool isDark, Color accentColor) {
    if (_lastSummaryTrackId != track.id) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _fetchSongSummary(track, forceRefresh: false));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        decoration: BoxDecoration(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
            width: 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header row (always visible)
            InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                setState(() => _isSummaryExpanded = !_isSummaryExpanded);
                if (_isSummaryExpanded && _songSummary == null && !_isSummaryLoading) {
                  _fetchSongSummary(track);
                }
              },
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(Icons.auto_awesome_rounded, color: accentColor, size: 20),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Song Summary',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: isDark ? Colors.white : Colors.black87,
                            ),
                          ),
                          if (!_isSummaryExpanded && _songSummary != null)
                            Text(
                              _songSummary!.theme.length > 60 
                                ? '${_songSummary!.theme.substring(0, 60)}...' 
                                : _songSummary!.theme,
                              style: TextStyle(
                                fontSize: 11,
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    if (_isSummaryLoading)
                      SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2, color: accentColor),
                      )
                    else
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_isSummaryExpanded)
                            IconButton(
                              icon: Icon(Icons.refresh_rounded, color: Colors.grey, size: 18),
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
                              onPressed: () => _fetchSongSummary(track, forceRefresh: true),
                            ),
                          Icon(
                            _isSummaryExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                            color: Colors.grey,
                            size: 22,
                          ),
                        ],
                      ),
                  ],
                ),
              ),
            ),

            // Expanded content
            if (_isSummaryExpanded)
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                child: _isSummaryLoading
                    ? _buildSummaryShimmer(isDark)
                    : _songSummary != null
                        ? _buildSummaryContent(_songSummary!, isDark, accentColor)
                        : Padding(
                            padding: const EdgeInsets.all(16),
                            child: Text(
                              'Tap refresh to generate a summary for this song.',
                              style: TextStyle(
                                fontSize: 12,
                                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.5),
                              ),
                            ),
                          ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildSummaryContent(SongSummary summary, bool isDark, Color accentColor) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtleColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.6);
    final state = ref.watch(playbackProvider);

    // Calculate active lyric index based on playback progress
    if (summary.lineByLineExplanations.isNotEmpty) {
      final lineCount = summary.lineByLineExplanations.length;
      final newIndex = (state.progress * lineCount).floor().clamp(0, lineCount - 1);
      if (newIndex != _activeLyricIndex) {
        _activeLyricIndex = newIndex;
        _scrollToActiveLyric();
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Divider(height: 1),
          const SizedBox(height: 12),
          // Theme & info pills row
          if (summary.theme.isNotEmpty || summary.emotions.isNotEmpty)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                if (summary.theme.isNotEmpty)
                  _buildInfoPill('🎵', summary.theme, isDark, accentColor),
                if (summary.emotions.isNotEmpty)
                  _buildInfoPill('💫', summary.emotions, isDark, accentColor),
              ],
            ),
          if (summary.theme.isNotEmpty || summary.emotions.isNotEmpty)
            const SizedBox(height: 16),

          // Karaoke Lyrics View
          if (summary.lineByLineExplanations.isNotEmpty) ...[
            // Header
            Row(
              children: [
                Icon(Icons.lyrics_rounded, size: 18, color: accentColor),
                const SizedBox(width: 8),
                Text(
                  'LYRICS & MEANING',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.5,
                    color: accentColor,
                  ),
                ),
                const Spacer(),
                // Spotify-style "Synced" badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.sync_rounded, size: 10, color: accentColor),
                      const SizedBox(width: 4),
                      Text(
                        'Synced',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: accentColor,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Karaoke lyrics list
            ...List.generate(summary.lineByLineExplanations.length, (index) {
              final item = summary.lineByLineExplanations[index];
              final isActive = index == _activeLyricIndex;
              final isPast = index < _activeLyricIndex;
              final isTapped = _tappedLyricIndex == index;
              final showMeaning = isActive || isTapped;

              return GestureDetector(
                onTap: () {
                  setState(() {
                    _tappedLyricIndex = _tappedLyricIndex == index ? null : index;
                  });
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 400),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: EdgeInsets.symmetric(
                    horizontal: isActive ? 16 : 12,
                    vertical: isActive ? 14 : 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? accentColor.withValues(alpha: 0.12)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: isActive
                        ? Border.all(color: accentColor.withValues(alpha: 0.25), width: 1)
                        : null,
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Lyric line
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 350),
                        style: TextStyle(
                          fontSize: isActive ? 17 : 14,
                          fontWeight: isActive ? FontWeight.w800 : FontWeight.w500,
                          color: isActive
                              ? accentColor
                              : isPast
                                  ? textColor.withValues(alpha: 0.35)
                                  : textColor.withValues(alpha: 0.55),
                          height: 1.4,
                          fontFamily: 'Outfit',
                        ),
                        child: Text(item.line),
                      ),

                      // Meaning (shown for active line or tapped line)
                      AnimatedCrossFade(
                        duration: const Duration(milliseconds: 300),
                        crossFadeState: showMeaning
                            ? CrossFadeState.showFirst
                            : CrossFadeState.showSecond,
                        firstChild: Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            decoration: BoxDecoration(
                              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border(
                                left: BorderSide(
                                  color: accentColor.withValues(alpha: 0.5),
                                  width: 2.5,
                                ),
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text('💡 ', style: TextStyle(fontSize: 11, color: subtleColor)),
                                Expanded(
                                  child: Text(
                                    item.explanation,
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: textColor.withValues(alpha: 0.8),
                                      height: 1.4,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        secondChild: const SizedBox.shrink(),
                      ),
                    ],
                  ),
                ),
              );
            }),
          ] else ...[
            // Fallback: show message and cultural notes
            if (summary.message.isNotEmpty) ...[
              _buildSummaryRow('📝', 'Message', summary.message, textColor, subtleColor),
              const SizedBox(height: 10),
            ],
            if (summary.culturalNotes.isNotEmpty) ...[
              _buildSummaryRow('🌍', 'Cultural Notes', summary.culturalNotes, textColor, subtleColor),
            ],
          ],
        ],
      ),
    );
  }

  Widget _buildInfoPill(String emoji, String text, bool isDark, Color accentColor) {
    final displayText = text.length > 50 ? '${text.substring(0, 50)}...' : text;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 11,
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.7),
                fontWeight: FontWeight.w600,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  void _scrollToActiveLyric() {
    if (!_lyricsScrollController.hasClients) return;
    // Each lyric item is approximately 70px tall (with padding)
    // We don't directly control the parent scroll, but the summary section
    // is inside the main ListView. We'll use post-frame callback for smooth UX.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_lyricsScrollController.hasClients) return;
      // Not applicable for inner scroll - the lyrics are part of the outer ListView
    });
  }

  Widget _buildSummaryRow(String emoji, String label, String content, Color textColor, Color subtleColor) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 16)),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12, color: subtleColor)),
              const SizedBox(height: 2),
              Text(content, style: TextStyle(fontSize: 13, color: textColor, height: 1.4)),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSummaryShimmer(bool isDark) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Shimmer.fromColors(
        baseColor: isDark ? Colors.grey[800]! : Colors.grey[300]!,
        highlightColor: isDark ? Colors.grey[600]! : Colors.grey[100]!,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(height: 1),
            const SizedBox(height: 12),
            Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(width: 200, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 12),
            Container(width: double.infinity, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
            const SizedBox(height: 8),
            Container(width: 150, height: 14, decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(4))),
          ],
        ),
      ),
    );
  }

  // ── Android 11 Theme Full-Screen Layout ───────────────────────

  Widget _buildAndroid11ThemeScreen(
    PlaybackState state,
    PlaybackNotifier notifier,
    Track track,
    Color accentColor,
    bool isDark,
    bool isFav,
  ) {
    final screenW = MediaQuery.of(context).size.width;
    final progress = state.progress.clamp(0.0, 1.0);
    final bgDark = HSLColor.fromColor(accentColor).withLightness(isDark ? 0.07 : 0.92).withSaturation(0.35).toColor();
    final cardBg = isDark ? Colors.white.withValues(alpha: 0.08) : Colors.white.withValues(alpha: 0.85);
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top Bar Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            track.artist.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              color: textColor.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.queue_music_rounded, color: textColor, size: 24),
                      onPressed: () => _showQueueBottomSheet(state, notifier),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              // Android 11 Media Notification Card Container
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Container(
                  width: screenW,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: cardBg,
                    borderRadius: BorderRadius.circular(28),
                    border: Border.all(
                      color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.1),
                      width: 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.2),
                        blurRadius: 25,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      // Album Cover Art
                      ClipRRect(
                        borderRadius: BorderRadius.circular(20),
                        child: Image.network(
                          track.artworkUrl,
                          width: screenW * 0.65,
                          height: screenW * 0.65,
                          fit: BoxFit.cover,
                          errorBuilder: (_, __, ___) => Container(
                            width: screenW * 0.65,
                            height: screenW * 0.65,
                            color: accentColor.withValues(alpha: 0.2),
                            child: Icon(Icons.music_note_rounded, size: 64, color: accentColor),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Title & Artist
                      Text(
                        track.title.toUpperCase(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.3,
                          color: textColor,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: textColor.withValues(alpha: 0.6),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 20),

                      // Android 11 Wave / Progress Bar with Circle Knob
                      if (StorageService.getProgressBarStyle() == 'waveform')
                        WaveformSeekBar(
                          track: track,
                          progress: progress,
                          currentPosition: state.currentPosition,
                          totalDuration: state.totalDuration,
                          activeColor: accentColor,
                          isDark: isDark,
                          onChangeEnd: (val) => notifier.seek(val),
                        )
                      else
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.0,
                            activeTrackColor: accentColor,
                            inactiveTrackColor: textColor.withValues(alpha: 0.15),
                            thumbColor: accentColor,
                            trackShape: resolveSliderTrackShape(StorageService.getProgressBarStyle()),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.0, disabledThumbRadius: 8.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (val) {
                              notifier.seek(val);
                            },
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(state.currentPosition), style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5))),
                            Text(_formatDuration(state.totalDuration), style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5))),
                          ],
                        ),
                      ),
                      const SizedBox(height: 16),

                      // Controls
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                        children: [
                          IconButton(
                            icon: Icon(
                              Icons.shuffle_rounded,
                              color: state.isShuffle ? accentColor : textColor.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            onPressed: () => notifier.toggleShuffle(),
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_previous_rounded, size: 36, color: textColor),
                            onPressed: () => notifier.previousTrack(),
                          ),
                          GestureDetector(
                            onTap: () => notifier.togglePlay(),
                            child: Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: accentColor,
                                shape: BoxShape.circle,
                                boxShadow: [
                                  BoxShadow(color: accentColor.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4)),
                                ],
                              ),
                              child: (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.buffering)
                                  ? Center(
                                      child: SizedBox(
                                        width: 24,
                                        height: 24,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                                        ),
                                      ),
                                    )
                                  : Icon(
                                      state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                      color: isDark ? Colors.black : Colors.white,
                                      size: 32,
                                    ),
                            ),
                          ),
                          IconButton(
                            icon: Icon(Icons.skip_next_rounded, size: 36, color: textColor),
                            onPressed: () => notifier.nextTrack(),
                          ),
                          IconButton(
                            icon: Icon(
                              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: isFav ? Colors.redAccent : textColor.withValues(alpha: 0.5),
                              size: 22,
                            ),
                            onPressed: () async {
                              triggerHaptic(HapticFeedbackType.selection);
                              await StorageService.toggleFavoriteTrack(track);
                              if (StorageService.isFavorite('trackIds', track.id)) {
                                ref.read(playbackProvider.notifier).onTrackLiked(track);
                              }
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 20),
              _buildSongSummarySection(track, isDark, accentColor),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Android 16 Theme Full-Screen Layout ───────────────────────

  Widget _buildAndroid16ThemeScreen(
    PlaybackState state,
    PlaybackNotifier notifier,
    Track track,
    Color accentColor,
    bool isDark,
    bool isFav,
  ) {
    final screenW = MediaQuery.of(context).size.width;
    final progress = state.progress.clamp(0.0, 1.0);
    final bgDark = HSLColor.fromColor(accentColor).withLightness(isDark ? 0.05 : 0.95).withSaturation(0.3).toColor();
    final textColor = isDark ? Colors.white : Colors.black87;

    return Scaffold(
      backgroundColor: bgDark,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Top Bar Header with Centered Song Title at Top Middle
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor, size: 28),
                      onPressed: () => Navigator.pop(context),
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            track.title.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.5,
                              color: textColor,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          Text(
                            track.artist.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.0,
                              color: textColor.withValues(alpha: 0.6),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.tune_rounded, color: textColor, size: 22),
                      onPressed: () => Navigator.push(context, MaterialPageRoute(builder: (context) => const EqualizerScreen())),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Square Album Art
              Center(
                child: Container(
                  width: screenW * 0.72,
                  height: screenW * 0.72,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: [
                      BoxShadow(
                        color: accentColor.withValues(alpha: 0.3),
                        blurRadius: 35,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      track.artworkUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: accentColor.withValues(alpha: 0.2),
                        child: Icon(Icons.music_note_rounded, size: 72, color: accentColor),
                      ),
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 28),

              // Metadata
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    Text(
                      track.title.toUpperCase(),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w900,
                        letterSpacing: -0.5,
                        color: textColor,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      track.artist,
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                        color: textColor.withValues(alpha: 0.6),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),

              // Android 16 Progress Bar with Circle Knob
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    if (StorageService.getProgressBarStyle() == 'waveform')
                      WaveformSeekBar(
                        track: track,
                        progress: progress,
                        currentPosition: state.currentPosition,
                        totalDuration: state.totalDuration,
                        activeColor: accentColor,
                        isDark: isDark,
                        onChangeEnd: (val) => notifier.seek(val),
                      )
                    else
                      SliderTheme(
                        data: SliderTheme.of(context).copyWith(
                          trackHeight: 4.5,
                          activeTrackColor: accentColor,
                          inactiveTrackColor: textColor.withValues(alpha: 0.15),
                          thumbColor: accentColor,
                          trackShape: resolveSliderTrackShape(StorageService.getProgressBarStyle()),
                          thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8.5, disabledThumbRadius: 8.5),
                          overlayShape: const RoundSliderOverlayShape(overlayRadius: 16.0),
                        ),
                        child: Slider(
                          value: progress,
                          onChanged: (val) => notifier.seek(val),
                        ),
                      ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(_formatDuration(state.currentPosition), style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5))),
                          Text(_formatDuration(state.totalDuration), style: TextStyle(fontSize: 11, color: textColor.withValues(alpha: 0.5))),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Minimal Controls Row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    IconButton(
                      icon: Icon(Icons.shuffle_rounded, color: state.isShuffle ? accentColor : textColor.withValues(alpha: 0.5), size: 22),
                      onPressed: () => notifier.toggleShuffle(),
                    ),
                    IconButton(
                      icon: Icon(Icons.skip_previous_rounded, size: 40, color: textColor),
                      onPressed: () => notifier.previousTrack(),
                    ),
                    GestureDetector(
                      onTap: () => notifier.togglePlay(),
                      child: Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          color: accentColor,
                          shape: BoxShape.circle,
                        ),
                        child: (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.buffering)
                            ? Center(
                                child: SizedBox(
                                  width: 26,
                                  height: 26,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2.5,
                                    valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                                  ),
                                ),
                              )
                            : Icon(
                                state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                color: isDark ? Colors.black : Colors.white,
                                size: 36,
                              ),
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.skip_next_rounded, size: 40, color: textColor),
                      onPressed: () => notifier.nextTrack(),
                    ),
                    IconButton(
                      icon: Icon(
                        isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                        color: isFav ? Colors.redAccent : textColor.withValues(alpha: 0.5),
                        size: 22,
                      ),
                      onPressed: () async {
                        triggerHaptic(HapticFeedbackType.selection);
                        await StorageService.toggleFavoriteTrack(track);
                        if (StorageService.isFavorite('trackIds', track.id)) {
                          ref.read(playbackProvider.notifier).onTrackLiked(track);
                        }
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 24),
              _buildSongSummarySection(track, isDark, accentColor),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  // ── Apple Music Theme Full-Screen Layout ──────────────────────

  Widget _buildAppleMusicThemeScreen(
    PlaybackState state,
    PlaybackNotifier notifier,
    Track track,
    Color accentColor,
    bool isDark,
    bool isFav,
  ) {
    final screenW = MediaQuery.of(context).size.width;
    final progress = state.progress.clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Fullscreen Blurred Background Artwork
          Positioned.fill(
            child: Image.network(
              track.artworkUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, __, ___) => Container(color: const Color(0xFF1C1C1E)),
            ),
          ),
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 55, sigmaY: 55),
              child: Container(
                color: Colors.black.withValues(alpha: isDark ? 0.65 : 0.45),
              ),
            ),
          ),

          // Main Content
          SafeArea(
            child: Column(
              children: [
                // Top Header Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Expanded(
                        child: Text(
                          'NOW PLAYING',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.5,
                          ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.more_horiz_rounded, color: Colors.white, size: 24),
                        onPressed: () => _showQueueBottomSheet(state, notifier),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),

                // Squercular Hero Artwork
                Container(
                  width: screenW * 0.78,
                  height: screenW * 0.78,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black45,
                        blurRadius: 30,
                        offset: Offset(0, 12),
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(24),
                    child: Image.network(
                      track.artworkUrl,
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: Colors.grey.shade900,
                        child: const Icon(Icons.music_note_rounded, size: 64, color: Colors.white38),
                      ),
                    ),
                  ),
                ),

                const Spacer(flex: 1),

                // Track Title & Artist
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 36),
                  child: Column(
                    children: [
                      Text(
                        track.title,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.bold,
                          letterSpacing: -0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        track.artist,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.7),
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),

                // Apple Progress Slider with Circle Knob
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: Column(
                    children: [
                      if (StorageService.getProgressBarStyle() == 'waveform')
                        WaveformSeekBar(
                          track: track,
                          progress: progress,
                          currentPosition: state.currentPosition,
                          totalDuration: state.totalDuration,
                          activeColor: Colors.white,
                          isDark: true,
                          onChangeEnd: (val) => notifier.seek(val),
                        )
                      else
                        SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 4.0,
                            activeTrackColor: Colors.white,
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.2),
                            thumbColor: Colors.white,
                            trackShape: resolveSliderTrackShape(StorageService.getProgressBarStyle()),
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7.0, disabledThumbRadius: 7.0),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14.0),
                          ),
                          child: Slider(
                            value: progress,
                            onChanged: (val) => notifier.seek(val),
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(state.currentPosition), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                            Text(_formatDuration(state.totalDuration), style: TextStyle(color: Colors.white.withValues(alpha: 0.6), fontSize: 11)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 20),

                // Controls
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(Icons.shuffle_rounded, color: state.isShuffle ? accentColor : Colors.white60, size: 22),
                        onPressed: () => notifier.toggleShuffle(),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_previous_rounded, size: 40, color: Colors.white),
                        onPressed: () => notifier.previousTrack(),
                      ),
                      GestureDetector(
                        onTap: () => notifier.togglePlay(),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                          ),
                          child: (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.buffering)
                              ? Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                                    ),
                                  ),
                                )
                              : Icon(
                                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: isDark ? Colors.black : Colors.white,
                                  size: 36,
                                ),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.skip_next_rounded, size: 40, color: Colors.white),
                        onPressed: () => notifier.nextTrack(),
                      ),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.redAccent : Colors.white60,
                          size: 22,
                        ),
                        onPressed: () async {
                          triggerHaptic(HapticFeedbackType.selection);
                          await StorageService.toggleFavoriteTrack(track);
                          if (StorageService.isFavorite('trackIds', track.id)) {
                            ref.read(playbackProvider.notifier).onTrackLiked(track);
                          }
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Minimal Theme Full-Screen Layout ──────────────────────────

  Widget _buildMinimalThemeScreen(
    PlaybackState state,
    PlaybackNotifier notifier,
    Track track,
    Color accentColor,
    bool isDark,
    bool isFav,
  ) {
    final screenW = MediaQuery.of(context).size.width;
    final artSize = screenW * 0.65;
    final ringSize = artSize + 28;
    final progress = state.progress.clamp(0.0, 1.0);

    final textColor = isDark ? Colors.white : Colors.black87;
    final subTextColor = isDark ? Colors.white.withValues(alpha: 0.65) : Colors.black.withValues(alpha: 0.65);
    final iconSubColor = isDark ? Colors.white54 : Colors.black45;

    // Gradient derived from album accent color with light/dark theme adaptation
    final bgDark = HSLColor.fromColor(accentColor).withLightness(isDark ? 0.08 : 0.94).withSaturation(0.38).toColor();
    final bgMid = HSLColor.fromColor(accentColor).withLightness(isDark ? 0.18 : 0.86).withSaturation(0.42).toColor();

    return Scaffold(
      backgroundColor: bgDark,
      body: Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [bgMid, bgDark, bgDark],
            stops: const [0.0, 0.55, 1.0],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: Column(
              children: [
                // ── Top Bar Header (Back & Options) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: Icon(Icons.keyboard_arrow_down_rounded, color: textColor.withValues(alpha: 0.8), size: 28),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                      IconButton(
                        icon: Icon(Icons.more_horiz_rounded, color: textColor.withValues(alpha: 0.8), size: 24),
                        onPressed: () => _showQueueBottomSheet(state, notifier),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // ── 1. Song Title (Large Bold Centered at Top) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    track.title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: textColor,
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.3,
                    ),
                  ),
                ),

                const SizedBox(height: 6),

                // ── 2. Artist (Centered Below Title) ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    track.artist,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: subTextColor,
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // ── 3. Time Indicator (Centered Above Artwork: 01:23  |  02:35) ──
                Text(
                  '${_formatDuration(state.currentPosition)}   |   ${_formatDuration(state.totalDuration)}',
                  style: TextStyle(
                    color: subTextColor,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 1.2,
                  ),
                ),

                const SizedBox(height: 16),

                // ── 4. Circular Artwork with Interactive Circular Arc Progress Ring ──
                GestureDetector(
                  onPanStart: (details) {
                    triggerHaptic(HapticFeedbackType.selection);
                    final double seekVal = _calculateArcProgress(details.localPosition, ringSize);
                    setState(() {
                      _isDraggingProgress = true;
                      _dragProgressValue = seekVal;
                    });
                  },
                  onPanUpdate: (details) {
                    final double seekVal = _calculateArcProgress(details.localPosition, ringSize);
                    setState(() {
                      _dragProgressValue = seekVal;
                    });
                  },
                  onPanEnd: (_) {
                    notifier.seek(_dragProgressValue);
                    setState(() {
                      _isDraggingProgress = false;
                    });
                  },
                  onTapDown: (details) {
                    triggerHaptic(HapticFeedbackType.selection);
                    final double seekVal = _calculateArcProgress(details.localPosition, ringSize);
                    notifier.seek(seekVal);
                  },
                  child: SizedBox(
                    width: ringSize,
                    height: ringSize,
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        // Arc Ring & Dot Knob Painter
                        CustomPaint(
                          size: Size(ringSize, ringSize),
                          painter: _ArcProgressPainter(
                            progress: _isDraggingProgress ? _dragProgressValue.clamp(0.0, 1.0) : progress,
                            activeColor: accentColor.withValues(alpha: 0.95),
                            inactiveColor: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.2),
                          ),
                        ),
                        // Circular Album Artwork
                        Container(
                          width: artSize,
                          height: artSize,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.35),
                                blurRadius: 35,
                                spreadRadius: 4,
                              ),
                              BoxShadow(
                                color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.2),
                                blurRadius: 20,
                                offset: const Offset(0, 10),
                              ),
                            ],
                          ),
                          child: ClipOval(
                            child: Image.network(
                              track.artworkUrl,
                              width: artSize,
                              height: artSize,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Container(
                                color: accentColor.withValues(alpha: 0.3),
                                child: Icon(Icons.music_note_rounded, color: textColor.withValues(alpha: 0.4), size: artSize * 0.4),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 28),

                // ── 6. Primary Playback Controls ──
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      IconButton(
                        icon: Icon(
                          state.isShuffle ? Icons.shuffle_rounded : Icons.shuffle_rounded,
                          color: state.isShuffle ? accentColor : iconSubColor,
                          size: 22,
                        ),
                        onPressed: () => notifier.toggleShuffle(),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_previous_rounded, color: textColor, size: 38),
                        onPressed: () => notifier.previousTrack(),
                      ),
                      GestureDetector(
                        onTap: () => notifier.togglePlay(),
                        child: Container(
                          width: 64,
                          height: 64,
                          decoration: BoxDecoration(
                            color: accentColor,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.4),
                                blurRadius: 15,
                                offset: const Offset(0, 5),
                              ),
                            ],
                          ),
                          child: (state.status == PlaybackStatus.loading || state.status == PlaybackStatus.buffering)
                              ? Center(
                                  child: SizedBox(
                                    width: 26,
                                    height: 26,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(isDark ? Colors.black : Colors.white),
                                    ),
                                  ),
                                )
                              : Icon(
                                  state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                                  color: isDark ? Colors.black : Colors.white,
                                  size: 36,
                                ),
                        ),
                      ),
                      IconButton(
                        icon: Icon(Icons.skip_next_rounded, color: textColor, size: 38),
                        onPressed: () => notifier.nextTrack(),
                      ),
                      IconButton(
                        icon: Icon(
                          isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                          color: isFav ? Colors.redAccent : iconSubColor,
                          size: 24,
                        ),
                        onPressed: () async {
                          triggerHaptic(HapticFeedbackType.selection);
                          await StorageService.toggleFavoriteTrack(track);
                          if (StorageService.isFavorite('trackIds', track.id)) {
                            ref.read(playbackProvider.notifier).onTrackLiked(track);
                          }
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),

              const SizedBox(height: 20),

              // ── Quick Action Buttons Row: Timer, Lyrics, Playlist, EQ, Queue ──
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildActionButton(
                      icon: Icons.timer_rounded,
                      label: 'Timer',
                      isActive: state.sleepTimerMinutes != null || state.isSleepTimerEndOfTrack,
                      accentColor: accentColor,
                      onTap: () => _showSleepTimerDialog(notifier),
                    ),
                    _buildActionButton(
                      icon: Icons.lyrics_rounded,
                      label: 'Lyrics',
                      isActive: _lyricsResult != null && _lyricsResult!.hasLyrics,
                      accentColor: accentColor,
                      onTap: (_lyricsResult != null && _lyricsResult!.hasLyrics)
                          ? () {
                              Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => LyricsScreen(
                                    track: track,
                                    lyricsResult: _lyricsResult!,
                                  ),
                                ),
                              );
                            }
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Fetching lyrics for this track...'), duration: Duration(seconds: 1)),
                              );
                            },
                    ),
                    _buildActionButton(
                      icon: Icons.playlist_add_rounded,
                      label: 'Playlist',
                      isActive: false,
                      accentColor: accentColor,
                      onTap: () {
                        triggerHaptic(HapticFeedbackType.selection);
                        _showAddToPlaylistBottomSheet(track);
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.graphic_eq_rounded,
                      label: 'EQ',
                      isActive: false,
                      accentColor: accentColor,
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => const EqualizerScreen()));
                      },
                    ),
                    _buildActionButton(
                      icon: Icons.queue_music_rounded,
                      label: 'Queue',
                      isActive: false,
                      accentColor: accentColor,
                      onTap: () => _showQueueBottomSheet(state, notifier),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // ── Song Summary & Karaoke Insights Section ──
              _buildSongSummarySection(track, isDark, accentColor),

            ],
          ),
        ),
      ),
    ),
    );
  }

  double _calculateArcProgress(Offset localPosition, double ringSize) {
    final center = Offset(ringSize / 2, ringSize / 2);
    final dx = localPosition.dx - center.dx;
    final dy = localPosition.dy - center.dy;
    double angle = math.atan2(dy, dx);
    double normalized = angle + (math.pi / 2);
    if (normalized < 0) {
      normalized += 2 * math.pi;
    }
    return (normalized / (2 * math.pi)).clamp(0.0, 1.0);
  }

  // ── Skins Layout Rendering ───────────────────────────────────

  Widget _buildSkinStage(String skin, Track track, double angle, bool isDark, Color accentColor) {

    switch (skin) {
      case 'cd':
        return Center(
          child: Transform.rotate(
            angle: angle,
            child: _buildCDDisc(track, isDark),
          ),
        );
      case 'cassette':
        return Center(
          child: _buildCassetteTape(track, angle, isDark),
        );
      case 'neon':
        return Center(
          child: Transform.rotate(
            angle: angle,
            child: _buildNeonDisc(track, accentColor, isDark),
          ),
        );
      case 'amber':
        return Center(
          child: _buildAmberGlowStage(track, accentColor, isDark),
        );
      case 'minimal':
        return Center(
          child: Container(
            width: MediaQuery.of(context).size.width * 0.68,
            height: MediaQuery.of(context).size.width * 0.68,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              image: DecorationImage(image: NetworkImage(track.artworkUrl), fit: BoxFit.cover),
              boxShadow: [
                BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 15, offset: const Offset(0, 8))
              ],
            ),
          ),
        );
      case 'vinyl':
      default:
        return Stack(
          clipBehavior: Clip.none,
          children: [
            Align(
              alignment: Alignment.center,
              child: Transform.rotate(
                angle: angle,
                child: VinylRecordWidget(size: MediaQuery.of(context).size.width * 0.72),
              ),
            ),
            Positioned(
              top: -10,
              right: 25,
              child: SizedBox(
                width: 120,
                height: 180,
                child: CustomPaint(
                  painter: TonearmPainter(isDark: isDark),
                ),
              ),
            ),
          ],
        );
    }
  }

  Widget _buildNeonDisc(Track track, Color accentColor, bool isDark) {
    final size = MediaQuery.of(context).size.width * 0.70;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: isDark ? const Color(0xFF0D0D11) : const Color(0xFF1E1E24),
        border: Border.all(color: accentColor, width: 3),
        boxShadow: [
          BoxShadow(color: accentColor.withOpacity(0.5), blurRadius: 25, spreadRadius: 2),
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.55,
          height: size * 0.55,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(image: NetworkImage(track.artworkUrl), fit: BoxFit.cover),
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Center(
            child: Container(
              width: size * 0.12,
              height: size * 0.12,
              decoration: BoxDecoration(
                color: accentColor,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: accentColor, blurRadius: 10),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAmberGlowStage(Track track, Color accentColor, bool isDark) {
    final size = MediaQuery.of(context).size.width * 0.70;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(32),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF382A15), const Color(0xFF1B160E)]
              : [const Color(0xFFFFECC8), const Color(0xFFF7E2B3)],
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFB300).withOpacity(0.35),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
        border: Border.all(color: const Color(0xFFFFC72C).withOpacity(0.6), width: 1.5),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Image.network(
            track.artworkUrl,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(color: Colors.amber),
          ),
        ),
      ),
    );
  }

  // ── Custom Skins Painters ────────────────────────────────────

  Widget _buildCDDisc(Track track, bool isDark) {
    final size = MediaQuery.of(context).size.width * 0.70;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [
            const Color(0xFFE0E0E0),
            Colors.grey[400]!,
            const Color(0xFFC0C0C0),
            Colors.grey[600]!,
          ],
          stops: const [0.0, 0.4, 0.7, 1.0],
        ),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.3), blurRadius: 15, offset: const Offset(0, 6))
        ],
      ),
      child: Center(
        child: Container(
          width: size * 0.4,
          height: size * 0.4,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            image: DecorationImage(image: NetworkImage(track.artworkUrl), fit: BoxFit.cover),
            border: Border.all(color: Colors.white, width: 3),
          ),
          child: Center(
            child: Container(
              width: size * 0.1,
              height: size * 0.1,
              decoration: const BoxDecoration(color: Colors.black, shape: BoxShape.circle),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildCassetteTape(Track track, double angle, bool isDark) {
    final size = MediaQuery.of(context).size.width * 0.8;
    return Container(
      width: size,
      height: size * 0.6,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E1E) : const Color(0xFFE2DDD5),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.withOpacity(0.5), width: 3),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.25), blurRadius: 12, offset: const Offset(0, 6))
        ],
      ),
      child: Stack(
        children: [
          // Tape windows
          Align(
            alignment: Alignment.center,
            child: Container(
              width: size * 0.7,
              height: size * 0.32,
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F0F0F) : Colors.white,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.grey.withOpacity(0.4), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  // Gear 1
                  Transform.rotate(
                    angle: angle,
                    child: const Icon(Icons.brightness_5_rounded, color: Colors.grey, size: 36),
                  ),
                  // Cover Image small in center
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(track.artworkUrl, width: 36, height: 36, fit: BoxFit.cover),
                  ),
                  // Gear 2
                  Transform.rotate(
                    angle: angle,
                    child: const Icon(Icons.brightness_5_rounded, color: Colors.grey, size: 36),
                  ),
                ],
              ),
            ),
          ),
          // Tape text brand
          Positioned(
            top: 10,
            left: 20,
            child: Text(
              'AURA TAPE',
              style: TextStyle(
                fontWeight: FontWeight.w900, 
                fontSize: 12, 
                color: isDark ? Colors.white30 : Colors.black26, 
                letterSpacing: 2
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Dialog Selectors & Queue Sheet ───────────────────────────

  void _showPlaybackSpeedDialog(PlaybackNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Playback Speed', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [0.75, 1.0, 1.25, 1.5, 2.0].map((speed) {
              return ListTile(
                title: Text('${speed}x'),
                onTap: () {
                  notifier.setPlaybackSpeed(speed);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  void _showQueueBottomSheet(PlaybackState state, PlaybackNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Active Queue', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 12),
              Expanded(
                child: ListView.builder(
                  itemCount: state.queue.length,
                  itemBuilder: (context, index) {
                    final track = state.queue[index];
                    final isCurrent = index == state.currentIndex;
                    return ListTile(
                      leading: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: Image.network(track.artworkUrl, width: 40, height: 40, fit: BoxFit.cover),
                      ),
                      title: Text(track.title, style: TextStyle(fontWeight: isCurrent ? FontWeight.bold : FontWeight.normal, fontSize: 14)),
                      subtitle: Text(track.artist, style: const TextStyle(fontSize: 12)),
                      trailing: isCurrent ? const Icon(Icons.volume_up_rounded, color: AppTheme.goldAccent, size: 20) : null,
                      onTap: () {
                        notifier.playTrack(track);
                        Navigator.pop(context);
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _showAddToPlaylistBottomSheet(Track track) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final customBranding = ref.watch(customizationProvider);
    final playlists = StorageService.getPlaylists();

    showModalBottomSheet(
      context: context,
      backgroundColor: isDark ? const Color(0xFF141414) : const Color(0xFFFAF8F5),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topLeft: Radius.circular(24), topRight: Radius.circular(24))
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              height: 400,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Add to Playlist',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                      ),
                      TextButton.icon(
                        icon: Icon(Icons.add, color: customBranding.accentColor, size: 16),
                        label: Text('New', style: TextStyle(color: customBranding.accentColor)),
                        onPressed: () {
                          Navigator.pop(context);
                          _showCreatePlaylistDialog(track);
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  if (playlists.isEmpty)
                    const Expanded(
                      child: Center(
                        child: Text(
                          'No playlists yet. Create one above!',
                          style: TextStyle(color: Colors.grey),
                        ),
                      ),
                    )
                  else
                    Expanded(
                      child: ListView.builder(
                        itemCount: playlists.length,
                        itemBuilder: (context, index) {
                          final pl = playlists[index];
                          final tracksList = List.from(pl['tracks'] ?? []);
                          final trackIds = List<String>.from(pl['trackIds'] ?? []);
                          final alreadyContains = tracksList.any((t) => t is Map && t['id'] == track.id) || trackIds.contains(track.id);
                          final songCount = tracksList.isNotEmpty ? tracksList.length : trackIds.length;

                          return ListTile(
                            leading: Container(
                              width: 40,
                              height: 40,
                              decoration: BoxDecoration(
                                color: customBranding.accentColor.withOpacity(0.1),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Icon(Icons.playlist_play_rounded, color: customBranding.accentColor),
                            ),
                            title: Text(
                              pl['name'] ?? 'Playlist',
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text('$songCount songs'),
                            trailing: alreadyContains
                                ? Icon(Icons.check_circle_rounded, color: customBranding.accentColor)
                                : const Icon(Icons.add_circle_outline_rounded, color: Colors.grey),
                            onTap: () async {
                              if (!alreadyContains) {
                                trackIds.add(track.id);
                                tracksList.add({
                                  'id': track.id,
                                  'title': track.title,
                                  'artist': track.artist,
                                  'album': track.album,
                                  'duration': track.duration,
                                  'artworkUrl': track.artworkUrl,
                                  'audioUrl': track.audioUrl,
                                  'genre': track.genre,
                                });
                                playlists[index]['trackIds'] = trackIds;
                                playlists[index]['tracks'] = tracksList;
                                await StorageService.savePlaylists(playlists);
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('Added "${track.title}" to ${pl['name']}'),
                                      backgroundColor: customBranding.accentColor,
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              } else {
                                if (mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text('"${track.title}" is already in ${pl['name']}'),
                                      behavior: SnackBarBehavior.floating,
                                    ),
                                  );
                                }
                              }
                              Navigator.pop(context);
                            },
                          );
                        },
                      ),
                    ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showSleepTimerDialog(PlaybackNotifier notifier) {
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final state = ref.read(playbackProvider);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF1B1B1F) : Colors.white,
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
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  Icon(Icons.timer_rounded, color: customBranding.accentColor, size: 22),
                  const SizedBox(width: 10),
                  const Text('Sleep Timer', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                ],
              ),
              const SizedBox(height: 16),

              // Option: Till this song ends
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: CircleAvatar(
                  radius: 18,
                  backgroundColor: state.isSleepTimerEndOfTrack ? customBranding.accentColor : Colors.grey.withOpacity(0.12),
                  child: Icon(Icons.music_off_rounded, size: 18, color: state.isSleepTimerEndOfTrack ? Colors.white : customBranding.accentColor),
                ),
                title: const Text('Till this song ends ⌛', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                subtitle: const Text('Stop playback automatically when current track finishes', style: TextStyle(fontSize: 11, color: Colors.grey)),
                trailing: state.isSleepTimerEndOfTrack
                    ? Icon(Icons.check_circle_rounded, color: customBranding.accentColor)
                    : null,
                onTap: () {
                  triggerHaptic(HapticFeedbackType.medium);
                  notifier.startSleepTimerTillEndOfTrack();
                  Navigator.pop(context);
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Sleep timer set: Playback will stop when this song ends ⌛'),
                      behavior: SnackBarBehavior.floating,
                      duration: Duration(seconds: 2),
                    ),
                  );
                },
              ),
              const Divider(height: 16),

              // Preset minute options: 5, 15, 30, 45, 60
              Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [5, 15, 30, 45, 60].map((mins) {
                  final isSelected = !state.isSleepTimerEndOfTrack && state.sleepTimerMinutes == mins;
                  return ChoiceChip(
                    label: Text('$mins mins'),
                    selected: isSelected,
                    onSelected: (val) {
                      triggerHaptic(HapticFeedbackType.medium);
                      if (val) {
                        notifier.startSleepTimer(mins);
                        Navigator.pop(context);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Sleep timer set for $mins minutes ⏳'),
                            behavior: SnackBarBehavior.floating,
                            duration: const Duration(seconds: 2),
                          ),
                        );
                      }
                    },
                    selectedColor: customBranding.accentColor.withOpacity(0.15),
                    checkmarkColor: customBranding.accentColor,
                    labelStyle: TextStyle(
                      color: isSelected ? customBranding.accentColor : (isDark ? Colors.white70 : Colors.black87),
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  );
                }).toList(),
              ),

              if (state.sleepTimerMinutes != null || state.isSleepTimerEndOfTrack) ...[
                const SizedBox(height: 16),
                Center(
                  child: TextButton.icon(
                    onPressed: () {
                      triggerHaptic(HapticFeedbackType.medium);
                      notifier.cancelSleepTimer();
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Sleep timer cancelled ⏹️'),
                          behavior: SnackBarBehavior.floating,
                          duration: Duration(seconds: 1),
                        ),
                      );
                    },
                    icon: const Icon(Icons.stop_circle_rounded, color: Colors.redAccent, size: 20),
                    label: const Text('Turn Off Sleep Timer', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _showCreatePlaylistDialog(Track track) {
    final nameController = TextEditingController();
    final customBranding = ref.watch(customizationProvider);

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('Create New Playlist'),
          content: TextField(
            controller: nameController,
            decoration: const InputDecoration(
              hintText: 'Playlist name...',
              border: OutlineInputBorder(),
            ),
            autofocus: true,
          ),
          actions: [
            TextButton(
              child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
              onPressed: () => Navigator.pop(context),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: customBranding.accentColor,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Create & Add', style: TextStyle(color: Colors.white)),
              onPressed: () async {
                final name = nameController.text.trim();
                if (name.isNotEmpty) {
                  final playlists = StorageService.getPlaylists();
                  final newPl = {
                    'id': DateTime.now().millisecondsSinceEpoch.toString(),
                    'name': name,
                    'description': 'A premium custom playlist',
                    'trackIds': <String>[track.id],
                    'tracks': <Map<String, dynamic>>[
                      {
                        'id': track.id,
                        'title': track.title,
                        'artist': track.artist,
                        'album': track.album,
                        'duration': track.duration,
                        'artworkUrl': track.artworkUrl,
                        'audioUrl': track.audioUrl,
                        'genre': track.genre,
                      }
                    ],
                  };
                  playlists.add(newPl);
                  await StorageService.savePlaylists(playlists);
                  
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Created playlist "$name" and added "${track.title}"'),
                        backgroundColor: customBranding.accentColor,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  }
                  Navigator.pop(context);
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showPlayerTutorialModal() {
    int currentStep = 0;
    final customBranding = ref.watch(customizationProvider);

    final steps = [
      {
        'title': '🎵 Interactive Vinyl & Skins',
        'desc': 'Tap the bottom skin icon to cycle between Vinyl record, CD, Cassette tape, and Minimal artwork skins!'
      },
      {
        'title': '👆 Swipe Gestures',
        'desc': 'Swipe Left/Right to skip tracks. Swipe Up to Favorite. Swipe Down to add to any playlist instantly!'
      },
      {
        'title': '🎛️ Equalizer & Sleep Timer',
        'desc': 'Fine-tune 5-band EQ, bass boost, and set automatic sleep timers directly from the bottom controls.'
      },
      {
        'title': '🎨 Dynamic RGB Branding',
        'desc': 'Customize app name, icon, and accent color with live RGB gradient preview in Settings.'
      },
    ];

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setTutorialState) {
            final step = steps[currentStep];
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
              title: Text(step['title']!, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(step['desc']!, style: const TextStyle(fontSize: 14, height: 1.4)),
                  const SizedBox(height: 16),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      steps.length,
                      (idx) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        width: idx == currentStep ? 16 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: idx == currentStep ? customBranding.accentColor : Colors.grey.withOpacity(0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  child: const Text('Skip', style: TextStyle(color: Colors.grey)),
                  onPressed: () async {
                    await StorageService.setSeenPlayerTutorial();
                    if (mounted) Navigator.pop(context);
                  },
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: customBranding.accentColor,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: Text(
                    currentStep < steps.length - 1 ? 'Next' : 'Got It!',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                  ),
                  onPressed: () async {
                    if (currentStep < steps.length - 1) {
                      setTutorialState(() {
                        currentStep++;
                      });
                    } else {
                      await StorageService.setSeenPlayerTutorial();
                      if (mounted) Navigator.pop(context);
                    }
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }
}

class _ArcProgressPainter extends CustomPainter {
  final double progress;
  final Color activeColor;
  final Color inactiveColor;

  _ArcProgressPainter({
    required this.progress,
    required this.activeColor,
    required this.inactiveColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width / 2) - 4;

    final inactivePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    final activePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    // Draw background track ring
    canvas.drawCircle(center, radius, inactivePaint);

    // Draw active arc starting from top (-pi / 2)
    final sweepAngle = 2 * math.pi * progress;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      sweepAngle,
      false,
      activePaint,
    );

    // Draw Circular Dot Knob at progress position angle
    final knobAngle = -math.pi / 2 + sweepAngle;
    final knobX = center.dx + radius * math.cos(knobAngle);
    final knobY = center.dy + radius * math.sin(knobAngle);

    final knobPaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final knobBorderPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;

    // White outer ring, active inner dot knob
    canvas.drawCircle(Offset(knobX, knobY), 6.5, knobBorderPaint);
    canvas.drawCircle(Offset(knobX, knobY), 4.5, knobPaint);
  }

  @override
  bool shouldRepaint(covariant _ArcProgressPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
