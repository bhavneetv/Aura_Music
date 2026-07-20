import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers/playback_provider.dart';
import '../themes/app_theme.dart';
import '../routes/bouncy_player_route.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../providers/customization_provider.dart';

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  @override
  void initState() {
    super.initState();
    _bounceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 100),
    );
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.94).animate(
      CurvedAnimation(parent: _bounceController, curve: Curves.easeOutCubic),
    );
  }

  @override
  void dispose() {
    _bounceController.dispose();
    super.dispose();
  }

  double _miniPlayerDragX = 0.0;

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);

    if (state.currentTrack == null) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final track = state.currentTrack!;

    return GestureDetector(
      onTapDown: (_) {
        _bounceController.forward();
      },
      onTapUp: (_) {
        _bounceController.reverse();
        // Trigger springy custom bouncy slide route
        Navigator.push(
          context,
          BouncyPlayerRoute(child: const NowPlayingScreen()),
        );
      },
      onTapCancel: () {
        _bounceController.reverse();
      },
      onHorizontalDragUpdate: (details) {
        setState(() {
          _miniPlayerDragX += details.delta.dx;
        });
      },
      onHorizontalDragEnd: (details) {
        if (_miniPlayerDragX < -60) {
          triggerHaptic(HapticFeedbackType.medium);
          notifier.nextTrack();
        } else if (_miniPlayerDragX > 60) {
          triggerHaptic(HapticFeedbackType.medium);
          notifier.previousTrack();
        }
        setState(() {
          _miniPlayerDragX = 0.0;
        });
      },
      child: AnimatedBuilder(
        animation: _scaleAnimation,
        builder: (context, child) {
          return Transform.scale(
            scale: _scaleAnimation.value,
            child: child,
          );
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          transform: Matrix4.translationValues(_miniPlayerDragX, 0, 0),
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          height: 66,
          decoration: BoxDecoration(
            color: isDark 
                ? Colors.black.withOpacity(0.85) 
                : Colors.white.withOpacity(0.92),
            borderRadius: BorderRadius.circular(AppTheme.cardRadius),
            border: Border.all(
              color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
              width: 1.0,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(isDark ? 0.4 : 0.12),
                blurRadius: 20,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: Stack(
            children: [
              // Thin progress line along the top edge
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: ClipRRect(
                  borderRadius: const BorderRadius.only(
                    topLeft: Radius.circular(AppTheme.cardRadius),
                    topRight: Radius.circular(AppTheme.cardRadius),
                  ),
                  child: LinearProgressIndicator(
                    value: state.progress,
                    minHeight: 2.5,
                    backgroundColor: Colors.transparent,
                    valueColor: AlwaysStoppedAnimation<Color>(ref.watch(customizationProvider).accentColor),
                  ),
                ),
              ),

              // Content
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Row(
                  children: [
                    // Track Artwork (Hero Transition Target)
                    Hero(
                      tag: 'mini_player_artwork',
                      child: Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.15),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: Image.network(
                            track.artworkUrl,
                            fit: BoxFit.cover,
                            errorBuilder: (context, error, stackTrace) => Container(
                              color: AppTheme.goldAccent,
                              child: const Icon(Icons.music_note_rounded, color: Colors.white),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),

                    // Track Title & Artist
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            track.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                                  fontSize: 12,
                                ),
                          ),
                        ],
                      ),
                    ),

                    // Play/Pause button
                    IconButton(
                      icon: Icon(
                        state.isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                        color: ref.watch(customizationProvider).accentColor,
                        size: 28,
                      ),
                      onPressed: () {
                        notifier.togglePlay();
                      },
                    ),

                    // Next Track button
                    IconButton(
                      icon: Icon(
                        Icons.skip_next_rounded,
                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                        size: 28,
                      ),
                      onPressed: () {
                        notifier.nextTrack();
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
