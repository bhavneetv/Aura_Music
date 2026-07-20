import 'dart:math' as math;
import 'package:flutter/material.dart' hide RepeatMode;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/download/download_service.dart';
import '../../widgets/custom_slider_track_shapes.dart';
import '../../themes/app_theme.dart';
import '../splash/splash_screen.dart';
import '../equalizer/equalizer_screen.dart';

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
    super.dispose();
  }

  void _syncAnimations(bool isPlaying) {
    if (isPlaying) {
      if (_decelController.isAnimating) _decelController.stop();
      _spinController.repeat();
    } else {
      if (_spinController.isAnimating) {
        _lastAngle = _spinController.value * 2 * math.pi;
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

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        height: double.infinity,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: bgColors,
          ),
          borderRadius: const BorderRadius.only(topLeft: Radius.circular(32), topRight: Radius.circular(32)),
        ),
        child: SafeArea(
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

                // Header Top Row
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
                        onPressed: () => Navigator.pop(context),
                      ),
                      Text(
                        'NOW PLAYING',
                        style: Theme.of(context).textTheme.labelLarge?.copyWith(
                              letterSpacing: 2,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
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
                                return const SizedBox(
                                  width: 24,
                                  height: 24,
                                  child: CircularProgressIndicator(strokeWidth: 2.5),
                                );
                              }
                              if (isDownloaded) {
                                return IconButton(
                                  icon: Icon(Icons.download_done_rounded, color: customBranding.accentColor, size: 22),
                                  onPressed: () {},
                                );
                              }
                              return IconButton(
                                icon: const Icon(Icons.download_rounded, color: Colors.grey, size: 22),
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
                            icon: Icon(
                              isFav ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                              color: isFav ? Colors.redAccent : Colors.grey,
                              size: 24,
                            ),
                            onPressed: () async {
                              triggerHaptic(HapticFeedbackType.selection);
                              await StorageService.toggleFavorite('trackIds', track.id);
                              setState(() {});
                            },
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 12),

                // Dynamic Skin Stages with Physics Swipe Gestures
                GestureDetector(
                  onPanUpdate: (details) {
                    setState(() {
                      _albumDragOffset += details.delta;
                    });
                  },
                  onPanEnd: (details) async {
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
                        await StorageService.toggleFavorite('trackIds', track.id);
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
                    child: _buildSkinStage(state.playerSkin, track, angle, isDark, customBranding.accentColor),
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
                        Text('👈 Prev', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('Next 👉', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('👆 Fav', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
                        Text(' • ', style: TextStyle(fontSize: 10, color: Colors.grey)),
                        Text('Playlist 👇', style: TextStyle(fontSize: 10, color: Colors.grey, fontWeight: FontWeight.bold)),
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
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    children: [
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
                          value: state.progress,
                          onChanged: (val) {
                            notifier.seek(val);
                          },
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_formatDuration(state.currentPosition), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(_formatDuration(state.totalDuration), style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          ],
                        ),
                      ),
                    ],
                  ),
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
                          child: Icon(
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

                // Bottom row: Sleep timer, Equalizer, Speed adjust, Queue drawer
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 40),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      // Sleep Timer Option
                      IconButton(
                        icon: Icon(
                          Icons.timer_rounded, 
                          color: state.sleepTimerMinutes != null ? customBranding.accentColor : Colors.grey,
                          size: 20,
                        ),
                        onPressed: () => _showSleepTimerDialog(notifier),
                      ),
                      
                      // Equalizer Option
                      IconButton(
                        icon: const Icon(Icons.graphic_eq_rounded, color: Colors.grey, size: 20),
                        onPressed: () {
                          Navigator.push(context, MaterialPageRoute(builder: (context) => const EqualizerScreen()));
                        },
                      ),
                      
                      // Playback Speed
                      IconButton(
                        icon: const Icon(Icons.speed_rounded, color: Colors.grey, size: 20),
                        onPressed: () => _showPlaybackSpeedDialog(notifier),
                      ),

                      // Add to Playlist Option
                      IconButton(
                        icon: const Icon(Icons.playlist_add_rounded, color: Colors.grey, size: 22),
                        tooltip: 'Add to Playlist',
                        onPressed: () => _showAddToPlaylistBottomSheet(track),
                      ),
                      
                      // Active Queue Info list
                      IconButton(
                        icon: const Icon(Icons.queue_music_rounded, color: Colors.grey, size: 20),
                        onPressed: () => _showQueueBottomSheet(state, notifier),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 24),
              ],
            ),
          ),
        ),
      ),
    );
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

  void _showSleepTimerDialog(PlaybackNotifier notifier) {
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Theme.of(context).cardColor,
          title: const Text('Sleep Timer Settings', style: TextStyle(fontWeight: FontWeight.bold)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('5 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(5);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('15 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(15);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('30 Minutes'),
                onTap: () {
                  notifier.startSleepTimer(30);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('Turn Timer Off', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  notifier.cancelSleepTimer();
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        );
      },
    );
  }

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
                          final trackIds = List<String>.from(pl['trackIds'] ?? []);
                          final alreadyContains = trackIds.contains(track.id);

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
                            subtitle: Text('${trackIds.length} songs'),
                            trailing: alreadyContains
                                ? Icon(Icons.check_circle_rounded, color: customBranding.accentColor)
                                : const Icon(Icons.add_circle_outline_rounded, color: Colors.grey),
                            onTap: () async {
                              if (!alreadyContains) {
                                trackIds.add(track.id);
                                playlists[index]['trackIds'] = trackIds;
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
          }
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
