import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../../themes/app_theme.dart';
import '../../services/storage/storage_service.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with TickerProviderStateMixin {
  late AnimationController _rotationController;
  late AnimationController _needleController;
  late AnimationController _fadeTextController;

  late Animation<double> _needleRotationAnimation;
  late Animation<double> _textFadeAnimation;
  late Animation<double> _textSlideAnimation;

  @override
  void initState() {
    super.initState();

    // 1. Continuous smooth rotation for the vinyl record
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2500),
    )..repeat();

    // 2. Needle animation: pivots down onto the record shortly after launch
    _needleController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _needleRotationAnimation = Tween<double>(
      begin: -math.pi / 5, // -36 degrees (parked)
      end: -math.pi / 24,  // -7.5 degrees (playing on edge)
    ).animate(CurvedAnimation(
      parent: _needleController,
      curve: Curves.easeOutBack,
    ));

    // 3. Text fade & slide in animation
    _fadeTextController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );

    _textFadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _fadeTextController, curve: Curves.easeIn),
    );

    _textSlideAnimation = Tween<double>(begin: 20.0, end: 0.0).animate(
      CurvedAnimation(parent: _fadeTextController, curve: Curves.easeOutCubic),
    );

    // Start needle and text animations after a short delay
    Future.delayed(const Duration(milliseconds: 400), () {
      if (mounted) {
        _needleController.forward();
      }
    });

    Future.delayed(const Duration(milliseconds: 600), () {
      if (mounted) {
        _fadeTextController.forward();
      }
    });

    // Navigate out after 3 seconds
    Future.delayed(const Duration(milliseconds: 3200), () {
      if (mounted) {
        if (StorageService.isOnboardingComplete()) {
          context.go('/home');
        } else {
          context.go('/onboarding');
        }
      }
    });
  }

  @override
  void dispose() {
    _rotationController.dispose();
    _needleController.dispose();
    _fadeTextController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    // Background gradients matching specs
    final List<Color> bgColors = isDark
        ? [const Color(0xFF141414), const Color(0xFF070707)]
        : [const Color(0xFFFAF6F0), const Color(0xFFEFE9E0)];

    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment.center,
            radius: 1.2,
            colors: bgColors,
          ),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            // Ambient soft vignette/glow behind the disc
            Positioned(
              top: MediaQuery.of(context).size.height * 0.22,
              child: Container(
                width: 320,
                height: 320,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: AppTheme.goldAccent.withOpacity(isDark ? 0.08 : 0.15),
                      blurRadius: 100,
                      spreadRadius: 20,
                    ),
                  ],
                ),
              ),
            ),

            // Center content area
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                // Vinyl Record & Needle stack
                SizedBox(
                  width: 340,
                  height: 340,
                  child: Stack(
                    children: [
                      // Rotating Vinyl Record
                      Align(
                        alignment: Alignment.center,
                        child: Hero(
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
                            child: const VinylRecordWidget(size: 280),
                          ),
                        ),
                      ),

                      // Animated Tonearm/Needle
                      Positioned(
                        top: 20,
                        right: 20,
                        child: AnimatedBuilder(
                          animation: _needleRotationAnimation,
                          builder: (context, child) {
                            return Transform.rotate(
                              angle: _needleRotationAnimation.value,
                              origin: const Offset(45, -45), // Rotate from the tonearm pivot base
                              child: SizedBox(
                                width: 140,
                                height: 200,
                                child: CustomPaint(
                                  painter: TonearmPainter(isDark: isDark),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 40),

                // Brand text fading & sliding up
                AnimatedBuilder(
                  animation: _fadeTextController,
                  builder: (context, child) {
                    return Opacity(
                      opacity: _textFadeAnimation.value,
                      child: Transform.translate(
                        offset: Offset(0, _textSlideAnimation.value),
                        child: child,
                      ),
                    );
                  },
                  child: Column(
                    children: [
                      Text(
                        'AURA',
                        style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                              fontFamily: 'Outfit',
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 6,
                              color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                            ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Vinyl Music Player',
                        style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              fontFamily: 'Outfit',
                              fontSize: 14,
                              fontWeight: FontWeight.w300,
                              letterSpacing: 2,
                              color: (isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary)
                                  .withOpacity(0.6),
                            ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// Vinyl Record Custom Painter Container
class VinylRecordWidget extends StatelessWidget {
  final double size;

  const VinylRecordWidget({
    super.key,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.6 : 0.25),
            blurRadius: 25,
            offset: const Offset(0, 15),
          ),
        ],
      ),
      child: CustomPaint(
        painter: VinylRecordPainter(isDark: isDark),
        child: Center(
          // Center Gold Label & Album Art Placeholder
          child: Container(
            width: size * 0.32,
            height: size * 0.32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppTheme.goldAccent,
              border: Border.all(
                color: Colors.black.withOpacity(0.8),
                width: 3.5,
              ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.3),
                  blurRadius: 4,
                  spreadRadius: -1,
                ),
              ],
            ),
            child: ClipOval(
              child: Center(
                child: Container(
                  width: size * 0.12,
                  height: size * 0.12,
                  decoration: const BoxDecoration(
                    color: Color(0xFF090909), // Center spindle hole
                    shape: BoxShape.circle,
                  ),
                  child: Center(
                    child: Container(
                      width: 4,
                      height: 4,
                      decoration: const BoxDecoration(
                        color: Colors.white24,
                        shape: BoxShape.circle,
                      ),
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
}

// Painter for drawing the vinyl grooves and reflections
class VinylRecordPainter extends CustomPainter {
  final bool isDark;

  VinylRecordPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    // Draw main black disc
    final discPaint = Paint()
      ..color = const Color(0xFF0D0D0D)
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, discPaint);

    // Draw concentric groove rings
    final groovePaint = Paint()
      ..color = Colors.white.withOpacity(isDark ? 0.04 : 0.06)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.5;

    // Draw grooves from outer to inner
    double currentRadius = radius - 8.0;
    while (currentRadius > radius * 0.34) {
      canvas.drawCircle(center, currentRadius, groovePaint);
      currentRadius -= 4.0 + (math.Random().nextDouble() * 2.0); // Procedural varying grooves
    }

    final reflectionPaint = Paint()
      ..shader = SweepGradient(
        colors: [
          Colors.transparent,
          Colors.white.withOpacity(0.02),
          Colors.white.withOpacity(0.12), // Bright reflection highlight
          Colors.white.withOpacity(0.02),
          Colors.transparent,
          Colors.white.withOpacity(0.02),
          Colors.white.withOpacity(0.12), // Opposing highlight
          Colors.white.withOpacity(0.02),
          Colors.transparent,
        ],
        stops: const [0.0, 0.2, 0.25, 0.3, 0.5, 0.7, 0.75, 0.8, 1.0],
        transform: const GradientRotation(math.pi / 4),
      ).createShader(Rect.fromCircle(center: center, radius: radius));

    canvas.drawCircle(center, radius, reflectionPaint);

    // Draw outer rim highlight
    final rimPaint = Paint()
      ..color = Colors.white.withOpacity(0.08)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    canvas.drawCircle(center, radius, rimPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// Painter to draw a modern minimal Tonearm/Needle
class TonearmPainter extends CustomPainter {
  final bool isDark;

  TonearmPainter({required this.isDark});

  @override
  void paint(Canvas canvas, Size size) {
    final armPaint = Paint()
      ..color = isDark ? const Color(0xFFC0C0C0) : const Color(0xFF4A4A4A)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5
      ..strokeCap = StrokeCap.round;

    final headPaint = Paint()
      ..color = AppTheme.goldAccent
      ..style = PaintingStyle.fill;

    final shadowPaint = Paint()
      ..color = Colors.black.withOpacity(0.15)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);

    // Path representing the tonearm curve
    // Starting point is the top right pivot (Offset(size.width - 20, 20))
    // Ends at Offset(25, size.height - 30) for the stylus/cartridge
    final start = Offset(size.width - 25, 25);
    final control = Offset(size.width - 30, size.height * 0.4);
    final end = Offset(25, size.height - 30);

    final path = Path()
      ..moveTo(start.dx, start.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    // Draw Shadow first
    canvas.save();
    canvas.translate(0, 8); // Shift shadow down
    canvas.drawPath(path, shadowPaint);
    canvas.restore();

    // Draw main arm tube
    canvas.drawPath(path, armPaint);

    // Draw Pivot Base (metallic ring)
    final basePaint = Paint()
      ..color = isDark ? const Color(0xFF404040) : const Color(0xFFD0D0D0)
      ..style = PaintingStyle.fill;
    final baseRingPaint = Paint()
      ..color = isDark ? const Color(0xFF8E8E8E) : const Color(0xFF7F7F7F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    canvas.drawCircle(start, 18, basePaint);
    canvas.drawCircle(start, 18, baseRingPaint);
    canvas.drawCircle(start, 8, headPaint); // Gold center cap

    // Draw headshell (cartridge) at the end of the arm
    canvas.save();
    canvas.translate(end.dx, end.dy);
    canvas.rotate(-math.pi / 6); // Angled headshell

    // Headshell body
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
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
