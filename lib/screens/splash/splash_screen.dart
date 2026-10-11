import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../themes/app_theme.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/sharing/playlist_link_share_service.dart';
import '../../services/auth/auth_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Splash screen
//
// A turntable: the record fades in and spins, the tonearm swings from its rest
// position onto the grooves, then the wordmark rises in. The light on the
// record (sheen) and the shadow under it stay still while the record turns.
// ─────────────────────────────────────────────────────────────────────────────

class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> with TickerProviderStateMixin {
  /// How long the splash stays up before moving on.
  static const Duration _splashDuration = Duration(milliseconds: 2600);

  /// Shorter wait when the app was opened from a QR code / shared link.
  static const Duration _sharedLinkDelay = Duration(milliseconds: 500);

  // Turntable layout at its design size (scaled to the screen in build()).
  static const double _stageSize = 260;
  static const double _discSize = 200;
  static const Size _armBox = Size(90, 130);
  static const Offset _armPivotOnStage = Offset(215, 40);

  static const double _needleParked = -math.pi / 4.3; // ≈ -42°, off the record
  static const double _needlePlaying = -math.pi / 24; // -7.5°, on the grooves

  late final AnimationController _rotationController;
  late final AnimationController _introController;

  late final Animation<double> _discFade;
  late final Animation<double> _discScale;
  late final Animation<double> _needleAngle;
  late final Animation<double> _titleFade;
  late final Animation<Offset> _titleSlide;
  late final Animation<double> _taglineFade;

  Timer? _navigationTimer;
  bool _listeningForImports = false;
  bool _navigated = false;

  @override
  void initState() {
    super.initState();

    // One full turn every 1.8s = 33⅓ rpm, the speed of a real LP.
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat();

    // One timeline drives the whole entrance; each piece gets its own window.
    _introController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1700),
    )..forward();

    Animation<double> window(double begin, double end, Curve curve) {
      return CurvedAnimation(
        parent: _introController,
        curve: Interval(begin, end, curve: curve),
      );
    }

    _discFade = window(0.0, 0.30, Curves.easeOut);
    _discScale = Tween<double>(begin: 0.86, end: 1.0).animate(window(0.0, 0.40, Curves.easeOutCubic));
    _needleAngle = Tween<double>(begin: _needleParked, end: _needlePlaying)
        .animate(window(0.24, 0.72, Curves.easeOutBack));
    _titleFade = window(0.40, 0.80, Curves.easeOut);
    _titleSlide = Tween<Offset>(begin: const Offset(0, 0.45), end: Offset.zero)
        .animate(window(0.40, 0.85, Curves.easeOutCubic));
    _taglineFade = window(0.58, 1.0, Curves.easeOut);

    // If opened via QR code or shared link, go to /home right away so the
    // user isn't stuck on the splash.
    final openedFromSharedLink = PlaylistLinkShareService.pendingImportEvent != null ||
        PlaylistLinkShareService.importEventNotifier.value != null;

    if (openedFromSharedLink) {
      _navigationTimer = Timer(_sharedLinkDelay, () => _goTo('/home'));
    } else {
      PlaylistLinkShareService.importEventNotifier.addListener(_onSplashImportEvent);
      _listeningForImports = true;
      _navigationTimer = Timer(_splashDuration, () => _goTo(_nextRoute()));
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Respect the system "remove animations" setting: show the finished frame.
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotationController.stop();
      _introController.value = 1.0;
    }
  }

  String _nextRoute() {
    if (!StorageService.isOnboardingComplete()) return '/onboarding';
    if (!AuthService.instance.isLoggedIn) return '/login';
    return '/home';
  }

  /// Leaves the splash exactly once, whichever trigger fires first.
  void _goTo(String route) {
    if (_navigated || !mounted) return;
    _navigated = true;
    _navigationTimer?.cancel();
    context.go(route);
  }

  void _onSplashImportEvent() {
    if (PlaylistLinkShareService.importEventNotifier.value != null) {
      _goTo('/home');
    }
  }

  @override
  void dispose() {
    _navigationTimer?.cancel();
    if (_listeningForImports) {
      PlaylistLinkShareService.importEventNotifier.removeListener(_onSplashImportEvent);
    }
    _rotationController.dispose();
    _introController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final textColor = isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary;

    final List<Color> bgColors = isDark
        ? [const Color(0xFF17171A), const Color(0xFF070707)]
        : [const Color(0xFFFDFAF5), const Color(0xFFEFE9E0)];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      // Keep the status bar icons readable on the splash background.
      value: isDark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF0C0C0C) : const Color(0xFFFAF6F0),
        body: Container(
          width: double.infinity,
          height: double.infinity,
          decoration: BoxDecoration(
            gradient: RadialGradient(
              center: Alignment.center,
              radius: 1.2,
              colors: bgColors,
            ),
          ),
          child: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                // Scale the turntable with the screen instead of a fixed size.
                final scale = (constraints.biggest.shortestSide / 360).clamp(0.85, 1.5).toDouble();

                return Stack(
                  children: [
                    Center(
                      child: Transform.scale(
                        scale: scale,
                        child: _buildTurntable(isDark, accent),
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 48,
                      child: _buildWordmark(textColor),
                    ),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTurntable(bool isDark, Color accent) {
    final armPivotInBox = TonearmPainter.pivotFor(_armBox);
    final armCenter = _armBox.center(Offset.zero);

    return SizedBox(
      width: _stageSize,
      height: _stageSize,
      child: Stack(
        clipBehavior: Clip.none,
        alignment: Alignment.center,
        children: [
          // Record: glow, shadow, spinning disc, fixed light
          FadeTransition(
            opacity: _discFade,
            child: ScaleTransition(
              scale: _discScale,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  // Ambient glow in the accent color
                  Container(
                    width: _discSize,
                    height: _discSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: accent.withValues(alpha: isDark ? 0.16 : 0.24),
                          blurRadius: 80,
                          spreadRadius: 18,
                        ),
                      ],
                    ),
                  ),

                  // Drop shadow. It lives outside the spinning widget so it
                  // stays below the record instead of orbiting around it.
                  Container(
                    width: _discSize,
                    height: _discSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.28),
                          blurRadius: 28,
                          offset: const Offset(0, 16),
                        ),
                      ],
                    ),
                  ),

                  // Spinning record
                  Hero(
                    tag: 'now_playing_vinyl',
                    flightShuttleBuilder: (
                      BuildContext flightContext,
                      Animation<double> animation,
                      HeroFlightDirection flightDirection,
                      BuildContext fromHeroContext,
                      BuildContext toHeroContext,
                    ) {
                      return RotationTransition(
                        turns: _rotationController,
                        child: toHeroContext.widget,
                      );
                    },
                    child: RotationTransition(
                      turns: _rotationController,
                      child: RepaintBoundary(
                        child: VinylRecordWidget(
                          size: _discSize,
                          labelColor: accent,
                          showShadow: false,
                          showSheen: false,
                        ),
                      ),
                    ),
                  ),

                  // Light reflection, fixed in place while the record turns
                  const IgnorePointer(
                    child: CustomPaint(
                      size: Size.square(_discSize),
                      painter: VinylSheenPainter(innerFraction: VinylRecordWidget.labelFraction),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tonearm, rotating around its own pivot
          Positioned(
            left: _armPivotOnStage.dx - armPivotInBox.dx,
            top: _armPivotOnStage.dy - armPivotInBox.dy,
            child: FadeTransition(
              opacity: _discFade,
              child: AnimatedBuilder(
                animation: _needleAngle,
                builder: (context, child) {
                  return Transform.rotate(
                    angle: _needleAngle.value,
                    // `origin` is measured from the box center.
                    origin: armPivotInBox - armCenter,
                    child: child,
                  );
                },
                child: CustomPaint(
                  size: _armBox,
                  painter: TonearmPainter(isDark: isDark, accentColor: accent),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWordmark(Color textColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        FadeTransition(
          opacity: _titleFade,
          child: SlideTransition(
            position: _titleSlide,
            child: Padding(
              // Letter spacing adds a gap after the last letter; this
              // balances it so the word sits truly centered.
              padding: const EdgeInsets.only(left: 8),
              child: Text(
                'AURA',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontFamily: 'Outfit',
                      fontSize: 34,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 8,
                      color: textColor,
                    ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 8),
        FadeTransition(
          opacity: _taglineFade,
          child: Padding(
            padding: const EdgeInsets.only(left: 2.5),
            child: Text(
              'VINYL MUSIC PLAYER',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontFamily: 'Outfit',
                    fontSize: 11.5,
                    fontWeight: FontWeight.w500,
                    letterSpacing: 2.5,
                    color: textColor.withValues(alpha: 0.55),
                  ),
            ),
          ),
        ),
      ],
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// VINYL RECORD
// ═════════════════════════════════════════════════════════════════════════════

/// The vinyl record. Same constructor as before (`size`), plus three optional
/// switches used by the splash screen.
class VinylRecordWidget extends StatelessWidget {
  /// Label diameter as a share of the record diameter.
  static const double labelFraction = 0.32;

  final double size;

  /// Color of the center label. Defaults to the app's gold accent.
  final Color? labelColor;

  /// Draw the drop shadow. Turn off when the record is rotated by a parent
  /// (the shadow would rotate with it) and draw a fixed shadow behind instead.
  final bool showShadow;

  /// Draw the light reflection. Turn off to layer a fixed [VinylSheenPainter]
  /// on top of a spinning record.
  final bool showSheen;

  const VinylRecordWidget({
    super.key,
    required this.size,
    this.labelColor,
    this.showShadow = true,
    this.showSheen = true,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: showShadow
            ? [
                BoxShadow(
                  color: Colors.black.withValues(alpha: isDark ? 0.6 : 0.25),
                  blurRadius: 25,
                  offset: const Offset(0, 15),
                ),
              ]
            : null,
      ),
      child: CustomPaint(
        painter: VinylRecordPainter(isDark: isDark, showSheen: showSheen),
        child: Center(
          child: CustomPaint(
            size: Size.square(size * labelFraction),
            painter: _VinylLabelPainter(color: labelColor ?? AppTheme.goldAccent),
          ),
        ),
      ),
    );
  }
}

/// Paints the black disc and its grooves.
class VinylRecordPainter extends CustomPainter {
  final bool isDark;
  final bool showSheen;

  VinylRecordPainter({required this.isDark, this.showSheen = true});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final unit = radius / 100; // the design was drawn for a 200px record

    // Disc body, slightly lighter toward the middle for depth
    final discPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0xFF191919), Color(0xFF0D0D0D), Color(0xFF080808)],
        stops: [0.0, 0.7, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, discPaint);

    // Grooves. The spacing is irregular like a real pressing, but the seed is
    // fixed so every repaint draws the same record.
    final groovePaint = Paint()
      ..color = Colors.white.withValues(alpha: isDark ? 0.045 : 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    final random = math.Random(33);
    double currentRadius = radius - 8.0 * unit;
    while (currentRadius > radius * 0.34) {
      canvas.drawCircle(center, currentRadius, groovePaint);
      currentRadius -= (4.0 + random.nextDouble() * 2.0) * unit;
    }

    // Silent gaps between tracks
    final gapPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.2 * unit;
    for (final fraction in const [0.79, 0.63, 0.49]) {
      canvas.drawCircle(center, radius * fraction, gapPaint);
    }

    if (showSheen) {
      VinylSheenPainter.paintSheen(canvas, center, radius);
    }

    // Outer rim highlight
    final rimPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius - 0.5, rimPaint);
  }

  @override
  bool shouldRepaint(covariant VinylRecordPainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.showSheen != showSheen;
  }
}

/// The two soft light reflections across the record. Painted on its own so it
/// can sit still above a spinning record.
class VinylSheenPainter extends CustomPainter {
  /// Leaves a hole of this share of the diameter (the label) unlit.
  final double innerFraction;

  const VinylSheenPainter({this.innerFraction = 0.0});

  static void paintSheen(Canvas canvas, Offset center, double radius, {double innerRadius = 0}) {
    final bounds = Rect.fromCircle(center: center, radius: radius);
    final paint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.white.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.13), // Bright reflection highlight
          Colors.white.withValues(alpha: 0.02),
          Colors.transparent,
          Colors.white.withValues(alpha: 0.02),
          Colors.white.withValues(alpha: 0.13), // Opposing highlight
          Colors.white.withValues(alpha: 0.02),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.25, 0.3, 0.5, 0.7, 0.75, 0.8, 1.0],
        transform: const GradientRotation(math.pi / 4),
      ).createShader(bounds);

    if (innerRadius <= 0) {
      canvas.drawCircle(center, radius, paint);
      return;
    }

    final ring = Path()
      ..fillType = PathFillType.evenOdd
      ..addOval(bounds)
      ..addOval(Rect.fromCircle(center: center, radius: innerRadius));
    canvas.drawPath(ring, paint);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final radius = size.width / 2;
    paintSheen(
      canvas,
      Offset(size.width / 2, size.height / 2),
      radius,
      innerRadius: radius * innerFraction,
    );
  }

  @override
  bool shouldRepaint(covariant VinylSheenPainter oldDelegate) {
    return oldDelegate.innerFraction != innerFraction;
  }
}

/// The center label. Its printed marks are off-center on purpose: they are
/// what makes the spin visible.
class _VinylLabelPainter extends CustomPainter {
  final Color color;

  const _VinylLabelPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Paper label with a dark pressed edge
    canvas.drawCircle(center, radius, Paint()..color = color);
    final edgeWidth = radius * 0.11;
    canvas.drawCircle(
      center,
      radius - edgeWidth / 2,
      Paint()
        ..color = Colors.black.withValues(alpha: 0.8)
        ..style = PaintingStyle.stroke
        ..strokeWidth = edgeWidth,
    );

    // Printed marks
    final ink = ThemeData.estimateBrightnessForColor(color) == Brightness.dark
        ? Colors.white
        : Colors.black;

    canvas.drawCircle(
      center,
      radius * 0.76,
      Paint()
        ..color = ink.withValues(alpha: 0.22)
        ..style = PaintingStyle.stroke
        ..strokeWidth = math.max(0.6, radius * 0.025),
    );

    final textPaint = Paint()
      ..color = ink.withValues(alpha: 0.5)
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeWidth = radius * 0.065;
    final textBand = Rect.fromCircle(center: center, radius: radius * 0.58);
    canvas.drawArc(textBand, -math.pi * 0.86, math.pi * 0.62, false, textPaint);
    canvas.drawArc(textBand, math.pi * 0.2, math.pi * 0.3, false, textPaint);

    const dotAngle = math.pi * 0.72;
    canvas.drawCircle(
      center + Offset(math.cos(dotAngle), math.sin(dotAngle)) * (radius * 0.58),
      radius * 0.06,
      Paint()..color = ink.withValues(alpha: 0.5),
    );

    // Spindle hole
    canvas.drawCircle(center, radius * 0.375, Paint()..color = const Color(0xFF090909));
    canvas.drawCircle(center, math.max(1.2, radius * 0.0625), Paint()..color = Colors.white24);
  }

  @override
  bool shouldRepaint(covariant _VinylLabelPainter oldDelegate) => oldDelegate.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// TONEARM
// ═════════════════════════════════════════════════════════════════════════════

/// Paints a minimal tonearm. Drawing is unchanged from before; the accent
/// color is now optional and [pivotFor] tells callers where to rotate it.
class TonearmPainter extends CustomPainter {
  final bool isDark;

  /// Color of the pivot cap and headshell. Defaults to the app's gold accent.
  final Color? accentColor;

  TonearmPainter({required this.isDark, this.accentColor});

  /// Where the arm's pivot is drawn inside a box of [size]. Rotate the arm
  /// around this point so the base stays put while the needle swings.
  static Offset pivotFor(Size size) => Offset(size.width - 25, 25);

  @override
  void paint(Canvas canvas, Size size) {
    final armPaint = Paint()
      ..color = isDark ? const Color(0xFFC0C0C0) : const Color(0xFF4A4A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final headPaint = Paint()
      ..color = accentColor ?? AppTheme.goldAccent
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withValues(alpha: 0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // The arm curves from the pivot (top right) to the cartridge (bottom left).
    final start = pivotFor(size);
    final control = Offset(size.width - 30, size.height * 0.4);
    final end = Offset(25, size.height - 30);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    // Shadow first, shifted down
    canvas.save();
    canvas.translate(0, 8);
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Arm tube
    canvas.drawPath(path, armPaint);

    // Pivot base (metallic ring) with an accent cap
    final basePaint = Paint()
      ..color = isDark ? const Color(0xFF404040) : const Color(0xFFD0D0D0)
      ..style = PaintingStyle.fill;
    final baseRingPaint = Paint()
      ..color = isDark ? const Color(0xFF8E8E8E) : const Color(0xFF7F7F7F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(start, 18, basePaint);
    canvas.drawCircle(start, 18, baseRingPaint);
    canvas.drawCircle(start, 8, headPaint);

    // Headshell (cartridge) at the end of the arm
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-math.pi / 6);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        const Rect.fromLTWH(-10, -5, 20, 32),
        const Radius.circular(3),
      ),
      headPaint,
    );

    // Stylus detail
    final stylusPaint = Paint()
      ..color = isDark ? Colors.white30 : Colors.black26
      ..style = PaintingStyle.fill;
    canvas.drawRect(const Rect.fromLTWH(-4, 25, 8, 4), stylusPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant TonearmPainter oldDelegate) {
    return oldDelegate.isDark != isDark || oldDelegate.accentColor != accentColor;
  }
}