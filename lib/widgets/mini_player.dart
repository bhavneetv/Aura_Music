import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/track.dart';
import '../providers/playback_provider.dart';
import '../themes/app_theme.dart';
import '../routes/bouncy_player_route.dart';
import '../screens/now_playing/now_playing_screen.dart';
import '../providers/customization_provider.dart';
import 'app_artwork_image.dart';

// ═════════════════════════════════════════════════════════════════════════════
// MINI PLAYER
//
// A floating glass capsule that matches the glass navigation bar:
//
//   [artwork]  Title            (play/pause inside a progress ring)  (next)
//              Artist
//
//   Tap the song          open the full player
//   Swipe left / right    next / previous song
// ═════════════════════════════════════════════════════════════════════════════

class MiniPlayer extends ConsumerStatefulWidget {
  const MiniPlayer({super.key});

  @override
  ConsumerState<MiniPlayer> createState() => _MiniPlayerState();
}

class _MiniPlayerState extends ConsumerState<MiniPlayer> with SingleTickerProviderStateMixin {
  late AnimationController _bounceController;
  late Animation<double> _scaleAnimation;

  static const double _barHeight = 58;

  /// How far you have to swipe before letting go skips the song.
  static const double _swipeThreshold = 60;

  double _miniPlayerDragX = 0.0;
  bool _dragging = false;
  bool _pastThreshold = false;

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

  // ── Actions ────────────────────────────────────────────────────────────────

  void _openPlayer() {
    // Trigger springy custom bouncy slide route
    Navigator.push(
      context,
      BouncyPlayerRoute(child: const NowPlayingScreen()),
    );
  }

  void _onDragUpdate(DragUpdateDetails details) {
    final next = (_miniPlayerDragX + details.delta.dx).clamp(-140.0, 140.0).toDouble();
    final past = next.abs() > _swipeThreshold;
    // A tick the moment the swipe is far enough to count
    if (past && !_pastThreshold) triggerHaptic(HapticFeedbackType.selection);

    setState(() {
      _dragging = true;
      _miniPlayerDragX = next;
      _pastThreshold = past;
    });
  }

  void _onDragEnd(DragEndDetails details) {
    final notifier = ref.read(playbackProvider.notifier);
    final velocity = details.primaryVelocity ?? 0;

    // Far enough, or a quick flick in that direction
    if (_miniPlayerDragX < -_swipeThreshold || (velocity < -700 && _miniPlayerDragX < -16)) {
      triggerHaptic(HapticFeedbackType.medium);
      notifier.nextTrack();
    } else if (_miniPlayerDragX > _swipeThreshold || (velocity > 700 && _miniPlayerDragX > 16)) {
      triggerHaptic(HapticFeedbackType.medium);
      notifier.previousTrack();
    }
    _resetDrag();
  }

  void _resetDrag() {
    if (!mounted) return;
    setState(() {
      _dragging = false;
      _miniPlayerDragX = 0.0;
      _pastThreshold = false;
    });
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    // Only the pieces this bar shows are watched. The playback position
    // changes many times a second; it is watched by the progress ring alone,
    // so the rest of the bar no longer rebuilds with every tick.
    final Track? track = ref.watch(playbackProvider.select((s) => s.currentTrack));
    final isPlaying = ref.watch(playbackProvider.select((s) => s.isPlaying));
    final status = ref.watch(playbackProvider.select((s) => s.status));
    final accentColor = ref.watch(customizationProvider).accentColor;

    // Slides open when the first song starts, and closed when there is none.
    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.bottomCenter,
      child: track == null
          ? const SizedBox(width: double.infinity, height: 0)
          : _buildBar(
              context,
              track: track,
              isPlaying: isPlaying,
              isLoading: status == PlaybackStatus.loading || status == PlaybackStatus.buffering,
              accentColor: accentColor,
            ),
    );
  }

  Widget _buildBar(
    BuildContext context, {
    required Track track,
    required bool isPlaying,
    required bool isLoading,
    required Color accentColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final notifier = ref.read(playbackProvider.notifier);

    return MediaQuery.withClampedTextScaling(
      // The bar has a fixed height, so its text grows only a little.
      maxScaleFactor: 1.15,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 2),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            // Same width as the glass navigation bar on tablets / landscape
            constraints: const BoxConstraints(maxWidth: 560),
            child: GestureDetector(
              onHorizontalDragUpdate: _onDragUpdate,
              onHorizontalDragEnd: _onDragEnd,
              onHorizontalDragCancel: _resetDrag,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: SizedBox(
                  height: _barHeight,
                  child: _Glass(
                    radius: _barHeight / 2,
                    child: Row(
                      children: [
                        const SizedBox(width: 8),

                        // Artwork, title and artist: tap to open the player
                        Expanded(
                          child: Semantics(
                            button: true,
                            hint: 'Opens the player',
                            child: GestureDetector(
                              behavior: HitTestBehavior.opaque,
                              onTapDown: (_) => _bounceController.forward(),
                              onTapUp: (_) => _bounceController.reverse(),
                              onTapCancel: () => _bounceController.reverse(),
                              onTap: _openPlayer,
                              child: SizedBox(
                                height: _barHeight,
                                child: _buildTrackInfo(context, track, accentColor),
                              ),
                            ),
                          ),
                        ),

                        // Play/Pause button
                        _buildPlayButton(context, isPlaying, isLoading, accentColor),

                        // Next Track button
                        IconButton(
                          tooltip: 'Next',
                          icon: Icon(
                            Icons.skip_next_rounded,
                            color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            size: 28,
                          ),
                          onPressed: () {
                            notifier.nextTrack();
                          },
                        ),
                        const SizedBox(width: 4),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Artwork + title + artist. While you swipe it follows your finger and a
  /// skip arrow appears on the side it is leaving; let go and it springs back.
  Widget _buildTrackInfo(BuildContext context, Track track, Color accentColor) {
    final muted = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
    final dragFraction = (_miniPlayerDragX.abs() / _swipeThreshold).clamp(0.0, 1.0).toDouble();
    final swipingToNext = _miniPlayerDragX < 0;

    final info = Row(
      children: [
        // Track Artwork (Hero Transition Target)
        Hero(
          tag: 'mini_player_artwork',
          child: Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(21),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.18),
                  blurRadius: 5,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            // The new cover fades in over the old one when the song changes
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 280),
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: KeyedSubtree(
                key: ValueKey(track.id),
                child: AppArtworkImage(
                  artworkUrl: track.artworkUrl,
                  trackId: track.id,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(21),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 12),

        // Track Title & Artist
        Expanded(
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 260),
            switchInCurve: Curves.easeOutCubic,
            switchOutCurve: Curves.easeIn,
            transitionBuilder: (child, animation) {
              return FadeTransition(
                opacity: animation,
                child: SlideTransition(
                  position: Tween<Offset>(begin: const Offset(0, 0.3), end: Offset.zero).animate(animation),
                  child: child,
                ),
              );
            },
            layoutBuilder: (currentChild, previousChildren) {
              return Stack(
                alignment: AlignmentDirectional.centerStart,
                children: [
                  ...previousChildren,
                  if (currentChild != null) currentChild,
                ],
              );
            },
            child: Column(
              key: ValueKey(track.id),
              mainAxisSize: MainAxisSize.min,
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
                Row(
                  children: [
                    if (track.isYouTube) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 0.5),
                        margin: const EdgeInsets.only(right: 5),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'YT',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    Expanded(
                      child: Text(
                        track.artist,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontSize: 12,
                            ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    return Stack(
      fit: StackFit.expand,
      children: [
        // Skip arrow, on the side the song is sliding away from
        if (_miniPlayerDragX != 0)
          Align(
            alignment: swipingToNext ? Alignment.centerRight : Alignment.centerLeft,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Opacity(
                opacity: dragFraction,
                child: Icon(
                  swipingToNext ? Icons.skip_next_rounded : Icons.skip_previous_rounded,
                  size: 24,
                  // Turns to the accent color once letting go will skip
                  color: _pastThreshold ? accentColor : muted,
                ),
              ),
            ),
          ),

        TweenAnimationBuilder<double>(
          // Follows the finger exactly while dragging, springs back after
          tween: Tween<double>(end: _miniPlayerDragX),
          duration: _dragging ? Duration.zero : const Duration(milliseconds: 320),
          curve: Curves.easeOutBack,
          child: info,
          builder: (context, dx, child) {
            return Transform.translate(
              offset: Offset(dx * 0.75, 0),
              child: Opacity(
                opacity: (1 - dx.abs() / 170).clamp(0.25, 1.0).toDouble(),
                child: child,
              ),
            );
          },
        ),
      ],
    );
  }

  /// Play / pause, with the song's progress drawn as a ring around it.
  Widget _buildPlayButton(BuildContext context, bool isPlaying, bool isLoading, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final trackColor = (isDark ? Colors.white : Colors.black).withValues(alpha: 0.13);

    return SizedBox(
      width: 44,
      height: 44,
      child: Stack(
        alignment: Alignment.center,
        children: [
          Positioned.fill(
            child: Padding(
              padding: const EdgeInsets.all(2.5),
              child: isLoading
                  // Loading or buffering: the ring spins instead
                  ? CircularProgressIndicator(
                      strokeWidth: 2.6,
                      valueColor: AlwaysStoppedAnimation<Color>(accentColor),
                    )
                  : Consumer(
                      builder: (context, ref, _) {
                        final double? raw = ref.watch(playbackProvider.select((s) => s.progress));
                        final value = (raw != null && raw.isFinite) ? raw.clamp(0.0, 1.0).toDouble() : 0.0;

                        return TweenAnimationBuilder<double>(
                          tween: Tween<double>(end: value),
                          duration: const Duration(milliseconds: 300),
                          builder: (context, progress, _) {
                            return CustomPaint(
                              painter: _ProgressRingPainter(
                                progress: progress,
                                color: accentColor,
                                trackColor: trackColor,
                              ),
                            );
                          },
                        );
                      },
                    ),
            ),
          ),
          IconButton(
            tooltip: isPlaying ? 'Pause' : 'Play',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints.tightFor(width: 44, height: 44),
            icon: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              transitionBuilder: (child, animation) {
                return ScaleTransition(
                  scale: Tween<double>(begin: 0.6, end: 1.0).animate(animation),
                  child: FadeTransition(opacity: animation, child: child),
                );
              },
              child: Icon(
                isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
                key: ValueKey(isPlaying),
                color: accentColor,
                size: 26,
              ),
            ),
            onPressed: () {
              ref.read(playbackProvider.notifier).togglePlay();
            },
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// A faint full circle with the played part drawn over it, from the top.
class _ProgressRingPainter extends CustomPainter {
  const _ProgressRingPainter({
    required this.progress,
    required this.color,
    required this.trackColor,
  });

  final double progress;
  final Color color;
  final Color trackColor;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 2.6;
    final center = size.center(Offset.zero);
    final radius = (size.shortestSide - stroke) / 2;

    canvas.drawCircle(
      center,
      radius,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = trackColor,
    );

    if (progress <= 0) return;
    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      -math.pi / 2,
      math.pi * 2 * progress,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ProgressRingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.color != color || oldDelegate.trackColor != trackColor;
  }
}

/// A see-through surface (same look as the glass navigation bar): blurs what
/// is behind it, adds a light tint and a soft sheen across the top, then a
/// bright rim and a shadow around it.
class _Glass extends StatelessWidget {
  const _Glass({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1B1B1F).withValues(alpha: 0.62) : Colors.white.withValues(alpha: 0.68);

    return CustomPaint(
      painter: _GlassShadowPainter(radius: radius, isDark: isDark),
      foregroundPainter: _GlassRimPainter(radius: radius, isDark: isDark),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.10 : 0.45),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shadow drawn only outside the shape, so it never darkens the glass itself.
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({required this.radius, required this.isDark});

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const blur = 14.0;
    const offset = Offset(0, 6);
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(blur * 3 + offset.dy))
        ..addRRect(shape),
    );
    canvas.drawRRect(
      shape.shift(offset),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.40 : 0.14)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassShadowPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.isDark != isDark;
  }
}

/// The edge of the glass: brightest at the top-left, where light would catch
/// it, fading around the shape and picking up again at the bottom-right.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.isDark});

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));

    // In light mode a faint dark line keeps the edge visible on white pages.
    if (!isDark) {
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.black.withValues(alpha: 0.07),
      );
    }

    final bright = isDark ? 0.36 : 0.95;
    final dim = isDark ? 0.07 : 0.30;
    final mid = isDark ? 0.18 : 0.60;

    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: bright),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: mid),
          ],
          stops: const [0.0, 0.38, 0.7, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.isDark != isDark;
  }
}