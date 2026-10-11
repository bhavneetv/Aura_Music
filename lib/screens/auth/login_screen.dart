import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../themes/app_theme.dart';
import '../../providers/customization_provider.dart';
import '../../services/auth/auth_service.dart';
import '../splash/splash_screen.dart';

// ═════════════════════════════════════════════════════════════════════════════
// LOGIN
//
//   Phone (portrait)       spinning record + name on top, sign-in card below
//   Landscape / tablet     record + name on the left, sign-in card on the right
//
// Everything is sized from the space available and scrolls if it has to, so
// nothing is cut off on small phones, in landscape or with large system text.
// ═════════════════════════════════════════════════════════════════════════════

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with TickerProviderStateMixin {
  late AnimationController _rotationController;

  /// Plays once when the screen opens: the record first, then the card.
  late final AnimationController _intro;

  /// Clears the "offline" notice by itself when the connection comes back.
  StreamSubscription<dynamic>? _connectivitySubscription;

  bool _isLoading = false;
  String? _loadingMessage;
  bool _isOffline = false;

  @override
  void initState() {
    super.initState();
    _rotationController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 20),
    )..repeat();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))..forward();
    _checkConnectivity();
    try {
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((_) => _checkConnectivity());
    } catch (_) {}
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold still when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _rotationController.stop();
      _intro.value = 1;
    } else if (!_rotationController.isAnimating) {
      _rotationController.repeat();
    }
  }

  @override
  void dispose() {
    _connectivitySubscription?.cancel();
    _rotationController.dispose();
    _intro.dispose();
    super.dispose();
  }

  // ── Sign-in logic (original, unchanged) ────────────────────────────────────

  Future<void> _checkConnectivity() async {
    try {
      final results = await Connectivity().checkConnectivity();
      final hasConnection = !results.contains(ConnectivityResult.none);
      if (mounted) {
        setState(() => _isOffline = !hasConnection);
      }
    } catch (_) {}
  }

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFC62828),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        content: Row(
          children: [
            const Icon(Icons.error_outline_rounded, color: Colors.white, size: 20),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                message,
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _handleGoogleSignIn() async {
    await _checkConnectivity();
    if (_isOffline) {
      _showError('No internet connection. Please connect to the internet to sign in.');
      return;
    }

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Connecting to Google...';
    });

    final result = await AuthService.instance.signInWithGoogle();

    if (mounted) {
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
      });

      if (result.success) {
        context.go('/home');
      } else if (result.message != null && !result.message!.contains('cancelled')) {
        _showError(result.message!);
      }
    }
  }

  Future<void> _handleGuestSignIn() async {
    await _checkConnectivity();
    if (_isOffline) {
      _showError('No internet connection. Please connect to the internet to initialize guest profile.');
      return;
    }
    if (!mounted) return;

    final chosenName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) => _GuestNameDialog(accent: ref.read(customizationProvider).accentColor),
    );

    if (chosenName == null || chosenName.isEmpty) return;
    if (!mounted) return;

    setState(() {
      _isLoading = true;
      _loadingMessage = 'Setting up guest session...';
    });

    final result = await AuthService.instance.signInAsGuest(chosenName);

    if (mounted) {
      setState(() {
        _isLoading = false;
        _loadingMessage = null;
      });

      if (result.success) {
        context.go('/home');
      } else {
        _showError(result.message ?? 'Guest sign-in failed');
      }
    }
  }

  void _showEmailAuthModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      // Keeps the sheet a comfortable width on tablets and in landscape
      constraints: const BoxConstraints(maxWidth: 560),
      builder: (ctx) => _EmailAuthBottomSheet(
        onSuccess: () {
          Navigator.pop(ctx);
          context.go('/home');
        },
      ),
    );
  }

  // ── Screen ─────────────────────────────────────────────────────────────────

  /// Fades [child] in between [begin] and [end] of the opening animation,
  /// lifting it by [dy] pixels and growing it from [scaleFrom].
  Widget _entrance({
    required double begin,
    required double end,
    double dy = 0,
    double scaleFrom = 1,
    required Widget child,
  }) {
    final curve = Interval(begin, end, curve: Curves.easeOutCubic);

    return AnimatedBuilder(
      animation: _intro,
      child: child,
      builder: (context, child) {
        final t = curve.transform(_intro.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(
            offset: Offset(0, dy * (1 - t)),
            child: Transform.scale(scale: scaleFrom + (1 - scaleFrom) * t, child: child),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090909) : const Color(0xFFFAF8F5),
      // Nothing is typed on this page itself (the dialog and the sheet handle
      // the keyboard), so the layout should not jump when the keyboard opens.
      resizeToAvoidBottomInset: false,
      body: Stack(
        fit: StackFit.expand,
        children: [
          _buildBackdrop(accentColor, isDark),

          // Main Responsive Content
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final twoPane = constraints.maxWidth >= 600 && constraints.maxWidth > constraints.maxHeight;
                return twoPane
                    ? _buildTwoPane(constraints, accentColor, isDark)
                    : _buildSinglePane(constraints, accentColor, isDark);
              },
            ),
          ),

          _buildLoadingOverlay(accentColor, isDark),
        ],
      ),
    );
  }

  /// Two soft glows in the accent color that drift very slowly.
  Widget _buildBackdrop(Color accentColor, bool isDark) {
    return IgnorePointer(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final d = constraints.biggest.shortestSide;

          Widget glow(double size, double alpha) {
            return RepaintBoundary(
              child: Container(
                width: size,
                height: size,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(
                    colors: [accentColor.withValues(alpha: alpha), accentColor.withValues(alpha: 0)],
                  ),
                ),
              ),
            );
          }

          // Built once; only their position changes while they drift.
          final topGlow = glow(d * 0.95, isDark ? 0.22 : 0.26);
          final bottomGlow = glow(d * 0.85, isDark ? 0.10 : 0.14);

          return AnimatedBuilder(
            animation: _rotationController,
            builder: (context, _) {
              final angle = _rotationController.value * math.pi * 2;
              final dx = math.cos(angle) * 14;
              final dy = math.sin(angle) * 14;

              return Stack(
                children: [
                  Positioned(top: -d * 0.35 + dy, right: -d * 0.3 + dx, child: topGlow),
                  Positioned(bottom: -d * 0.4 + dx, left: -d * 0.35 + dy, child: bottomGlow),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Phones in portrait: record and name, then the card, centered together.
  Widget _buildSinglePane(BoxConstraints constraints, Color accentColor, bool isDark) {
    final vinylSize = (constraints.maxHeight * 0.19).clamp(92.0, 150.0).toDouble();

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - 40)),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _entrance(
                  begin: 0.0,
                  end: 0.6,
                  scaleFrom: 0.88,
                  child: _buildHero(vinylSize, accentColor, isDark, large: false),
                ),
                SizedBox(height: constraints.maxHeight < 640 ? 24 : 34),
                _entrance(
                  begin: 0.25,
                  end: 1.0,
                  dy: 28,
                  child: _buildActionsCard(accentColor, isDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Landscape phones and tablets: record on the left, card on the right.
  Widget _buildTwoPane(BoxConstraints constraints, Color accentColor, bool isDark) {
    final paneWidth = math.min(constraints.maxWidth, 1040.0) * 4 / 9;
    final vinylSize = math.min(paneWidth * 0.55, constraints.maxHeight * 0.42).clamp(92.0, 230.0).toDouble();

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1040),
        child: Row(
          children: [
            Expanded(
              flex: 4,
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
                  child: _entrance(
                    begin: 0.0,
                    end: 0.6,
                    scaleFrom: 0.88,
                    child: _buildHero(vinylSize, accentColor, isDark, large: constraints.maxHeight >= 520),
                  ),
                ),
              ),
            ),
            Expanded(
              flex: 5,
              child: Center(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(12, 20, 24, 20),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440),
                    child: _entrance(
                      begin: 0.25,
                      end: 1.0,
                      dy: 28,
                      child: _buildActionsCard(accentColor, isDark),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Record + name ──────────────────────────────────────────────────────────

  Widget _buildHero(double vinylSize, Color accentColor, bool isDark, {required bool large}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Rotating Vinyl Branding
        Stack(
          alignment: Alignment.center,
          children: [
            Container(
              width: vinylSize * 1.06,
              height: vinylSize * 1.06,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: accentColor.withValues(alpha: 0.28),
                    blurRadius: vinylSize * 0.32,
                    spreadRadius: vinylSize * 0.05,
                  ),
                ],
              ),
            ),
            RotationTransition(
              turns: _rotationController,
              // Its own layer: spinning it never repaints the record itself.
              child: RepaintBoundary(child: VinylRecordWidget(size: vinylSize)),
            ),
          ],
        ),

        SizedBox(height: large ? 28 : 22),

        // App Branding Title. The left padding balances the letter spacing
        // after the last letter, so the word sits truly centered.
        Padding(
          padding: const EdgeInsets.only(left: 6),
          child: Text(
            'AURA',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                  fontFamily: 'Outfit',
                  fontSize: large ? 42 : 34,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 6,
                  height: 1.1,
                  color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                ),
          ),
        ),
        const SizedBox(height: 6),
        Padding(
          padding: const EdgeInsets.only(left: 2.5),
          child: Text(
            'Vinyl Music Player',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Outfit',
              fontSize: large ? 14.5 : 13,
              letterSpacing: 2.5,
              color: (isDark ? Colors.white70 : Colors.black54),
              fontWeight: FontWeight.w400,
            ),
          ),
        ),
      ],
    );
  }

  // ── Sign-in card ───────────────────────────────────────────────────────────

  Widget _buildActionsCard(Color accentColor, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF141414) : Colors.white).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(30),
        border: Border.all(color: _tint(context, 0.08)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.07),
            blurRadius: 30,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome',
            style: TextStyle(fontFamily: 'Outfit', fontSize: 25, fontWeight: FontWeight.w800, letterSpacing: -0.3),
          ),
          const SizedBox(height: 4),
          Text(
            'Sign in to keep your music backed up, or jump straight in as a guest.',
            style: TextStyle(fontSize: 13.5, height: 1.4, color: _muted(context)),
          ),
          const SizedBox(height: 20),

          // Offline Indicator if disconnected
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            alignment: Alignment.topCenter,
            child: _isOffline
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 16),
                    child: _buildOfflineNotice(isDark),
                  )
                : const SizedBox(width: double.infinity),
          ),

          // 1. Google Sign-In (Primary Action)
          _AuthButton(
            icon: const _GoogleLogo(size: 21),
            label: 'Continue with Google',
            background: Colors.white,
            foreground: const Color(0xFF1F1F1F),
            borderColor: isDark ? null : const Color(0xFFD5D7DA),
            onPressed: _isLoading ? null : _handleGoogleSignIn,
          ),

          const SizedBox(height: 12),

          // 2. Email + Password
          _AuthButton(
            icon: Icon(Icons.mail_outline_rounded, size: 21, color: Theme.of(context).colorScheme.onSurface),
            label: 'Email & Password',
            background: _tint(context, 0.07),
            foreground: Theme.of(context).colorScheme.onSurface,
            borderColor: _tint(context, 0.1),
            onPressed: _isLoading ? null : _showEmailAuthModal,
          ),

          const SizedBox(height: 18),

          // Divider
          Row(
            children: [
              Expanded(child: Divider(color: _tint(context, 0.12))),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Text(
                  'OR',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.5,
                    color: _tint(context, 0.4),
                  ),
                ),
              ),
              Expanded(child: Divider(color: _tint(context, 0.12))),
            ],
          ),

          const SizedBox(height: 18),

          // 3. Continue as Guest (Secondary Action)
          _AuthButton(
            icon: Icon(Icons.person_pin_circle_outlined, size: 21, color: _onColor(accentColor)),
            label: 'Continue as Guest',
            background: accentColor,
            foreground: _onColor(accentColor),
            onPressed: _isLoading ? null : _handleGuestSignIn,
          ),

          const SizedBox(height: 14),

          // Guest disclaimer note
          Text(
            'Guest data stays on this device account.\nSign in later in Settings to back up safely.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 11.5, height: 1.45, color: _muted(context)),
          ),
        ],
      ),
    );
  }

  Widget _buildOfflineNotice(bool isDark) {
    final color = isDark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828);

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_off_rounded, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Offline. Connect to internet to sign in.',
              style: TextStyle(fontSize: 12.5, height: 1.3, color: color, fontWeight: FontWeight.w600),
            ),
          ),
          TextButton(
            onPressed: _checkConnectivity,
            style: TextButton.styleFrom(foregroundColor: color),
            child: const Text('Retry', style: TextStyle(fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  // ── Loading Overlay ────────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(Color accentColor, bool isDark) {
    return IgnorePointer(
      ignoring: !_isLoading,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 240),
        switchInCurve: Curves.easeOut,
        switchOutCurve: Curves.easeIn,
        child: !_isLoading
            ? const SizedBox.shrink(key: ValueKey('idle'))
            : Container(
                key: const ValueKey('loading'),
                color: Colors.black.withValues(alpha: 0.55),
                alignment: Alignment.center,
                padding: const EdgeInsets.all(32),
                child: TweenAnimationBuilder<double>(
                  tween: Tween<double>(begin: 0.9, end: 1.0),
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutBack,
                  builder: (context, scale, child) => Transform.scale(scale: scale, child: child),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 22),
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 34,
                          height: 34,
                          child: CircularProgressIndicator(color: accentColor, strokeWidth: 3.2),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _loadingMessage ?? 'Signing in...',
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

/// White in dark mode, black in light mode, at the given opacity.
Color _tint(BuildContext context, double alpha) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

Color _muted(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
}

/// Readable text/icon color on top of [background] (any accent the user picks).
Color _onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// Filled, rounded text field used in the dialog and the email sheet.
InputDecoration _fieldDecoration(
  BuildContext context, {
  required String label,
  required IconData icon,
  required Color accent,
  String? hint,
  Widget? suffix,
}) {
  const errorColor = Color(0xFFE5484D);

  OutlineInputBorder border(Color color, double width) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: width == 0 ? BorderSide.none : BorderSide(color: color, width: width),
    );
  }

  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: Icon(icon, size: 20),
    suffixIcon: suffix,
    filled: true,
    fillColor: _tint(context, 0.06),
    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 16),
    floatingLabelStyle: TextStyle(color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8)),
    border: border(Colors.transparent, 0),
    enabledBorder: border(Colors.transparent, 0),
    focusedBorder: border(accent, 1.5),
    errorBorder: border(errorColor, 1.2),
    focusedErrorBorder: border(errorColor, 1.5),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// One sign-in option. Dips slightly while pressed and dims while disabled.
class _AuthButton extends StatefulWidget {
  const _AuthButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
    required this.onPressed,
    this.borderColor,
  });

  final Widget icon;
  final String label;
  final Color background;
  final Color foreground;
  final Color? borderColor;
  final VoidCallback? onPressed;

  @override
  State<_AuthButton> createState() => _AuthButtonState();
}

class _AuthButtonState extends State<_AuthButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null;
    final borderColor = widget.borderColor;

    return AnimatedScale(
      scale: (_pressed && enabled) ? 0.97 : 1.0,
      duration: const Duration(milliseconds: 110),
      curve: Curves.easeOut,
      child: AnimatedOpacity(
        opacity: enabled ? 1.0 : 0.55,
        duration: const Duration(milliseconds: 200),
        child: Material(
          color: widget.background,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
            side: borderColor == null ? BorderSide.none : BorderSide(color: borderColor),
          ),
          child: InkWell(
            onTap: widget.onPressed,
            onHighlightChanged: (value) {
              if (mounted) setState(() => _pressed = value);
            },
            child: ConstrainedBox(
              // A minimum, not a fixed height: it grows with large system text.
              constraints: const BoxConstraints(minHeight: 54),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    widget.icon,
                    const SizedBox(width: 12),
                    Flexible(
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: widget.foreground),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Google "G", drawn as four colored shapes. No font and no image file,
/// so it stays sharp at any size.
class _GoogleLogo extends StatelessWidget {
  const _GoogleLogo({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: const CustomPaint(painter: _GoogleLogoPainter()),
    );
  }
}

class _GoogleLogoPainter extends CustomPainter {
  const _GoogleLogoPainter();

  @override
  void paint(Canvas canvas, Size size) {
    // The shapes are defined on a 48 x 48 grid and scaled to fit.
    canvas.save();
    canvas.scale(size.width / 48, size.height / 48);
    final paint = Paint()..isAntiAlias = true;

    // Red
    paint.color = const Color(0xFFEA4335);
    canvas.drawPath(
      Path()
        ..moveTo(24, 9.5)
        ..cubicTo(27.54, 9.5, 30.71, 10.72, 33.21, 13.1)
        ..lineTo(40.06, 6.25)
        ..cubicTo(35.9, 2.38, 30.47, 0, 24, 0)
        ..cubicTo(14.62, 0, 6.51, 5.38, 2.56, 13.22)
        ..lineTo(10.54, 19.41)
        ..cubicTo(12.43, 13.72, 17.74, 9.5, 24, 9.5)
        ..close(),
      paint,
    );

    // Blue
    paint.color = const Color(0xFF4285F4);
    canvas.drawPath(
      Path()
        ..moveTo(46.98, 24.55)
        ..cubicTo(46.98, 22.98, 46.83, 21.46, 46.6, 20)
        ..lineTo(24, 20)
        ..lineTo(24, 29.02)
        ..lineTo(36.94, 29.02)
        ..cubicTo(36.36, 31.98, 34.68, 34.5, 32.16, 36.2)
        ..lineTo(39.89, 42.2)
        ..cubicTo(44.4, 38.02, 46.98, 31.84, 46.98, 24.55)
        ..close(),
      paint,
    );

    // Yellow
    paint.color = const Color(0xFFFBBC05);
    canvas.drawPath(
      Path()
        ..moveTo(10.53, 28.59)
        ..cubicTo(10.05, 27.14, 9.77, 25.6, 9.77, 24)
        ..cubicTo(9.77, 22.4, 10.04, 20.86, 10.53, 19.41)
        ..lineTo(2.55, 13.22)
        ..cubicTo(0.92, 16.46, 0, 20.12, 0, 24)
        ..cubicTo(0, 27.88, 0.92, 31.54, 2.56, 34.78)
        ..lineTo(10.53, 28.59)
        ..close(),
      paint,
    );

    // Green
    paint.color = const Color(0xFF34A853);
    canvas.drawPath(
      Path()
        ..moveTo(24, 48)
        ..cubicTo(30.48, 48, 35.93, 45.87, 39.89, 42.19)
        ..lineTo(32.16, 36.19)
        ..cubicTo(30.01, 37.64, 27.24, 38.49, 24, 38.49)
        ..cubicTo(17.74, 38.49, 12.43, 34.27, 10.53, 28.58)
        ..lineTo(2.55, 34.77)
        ..cubicTo(6.51, 42.62, 14.62, 48, 24, 48)
        ..close(),
      paint,
    );

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoogleLogoPainter oldDelegate) => false;
}

/// Two options side by side with a pill that slides to the selected one.
class _Segmented extends StatelessWidget {
  const _Segmented({
    required this.labels,
    required this.index,
    required this.accent,
    required this.onChanged,
  });

  final List<String> labels;
  final int index;
  final Color accent;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    final last = math.max(1, labels.length - 1);

    return Container(
      height: 46,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + 2 * index / last, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / labels.length,
                heightFactor: 1,
                child: Container(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.32),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < labels.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onChanged(i),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: AnimatedDefaultTextStyle(
                              duration: const Duration(milliseconds: 200),
                              style: TextStyle(
                                fontFamily: 'Outfit',
                                fontSize: 13.5,
                                fontWeight: i == index ? FontWeight.w800 : FontWeight.w600,
                                color: i == index ? _onColor(accent) : _muted(context),
                              ),
                              child: Text(labels[i], maxLines: 1),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GUEST NAME DIALOG
// ═════════════════════════════════════════════════════════════════════════════

/// Asks for a display name. Pops with the trimmed name, or null if cancelled.
class _GuestNameDialog extends StatefulWidget {
  const _GuestNameDialog({required this.accent});

  final Color accent;

  @override
  State<_GuestNameDialog> createState() => _GuestNameDialogState();
}

class _GuestNameDialogState extends State<_GuestNameDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _submit() {
    if (_formKey.currentState?.validate() == true) {
      Navigator.pop(context, _nameController.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;
    final noteColor = isDark ? Colors.amber.shade200 : Colors.amber.shade900;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF181818) : const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.person_outline_rounded, color: accent, size: 23),
                    ),
                    const SizedBox(width: 13),
                    const Expanded(
                      child: Text(
                        'Guest Profile',
                        style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w800, fontSize: 20),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  'Enter a display name so collaborators can recognize who added tracks.',
                  style: TextStyle(fontSize: 13.5, height: 1.4, color: _muted(context)),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: _nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  textInputAction: TextInputAction.done,
                  onFieldSubmitted: (_) => _submit(),
                  decoration: _fieldDecoration(
                    context,
                    label: 'Display Name',
                    hint: 'e.g. VinylLover',
                    icon: Icons.badge_outlined,
                    accent: accent,
                  ),
                  validator: (val) {
                    final trimmed = val?.trim() ?? '';
                    if (trimmed.length < 2) return 'Must be at least 2 characters';
                    if (trimmed.length > 24) return 'Maximum 24 characters allowed';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(11),
                  decoration: BoxDecoration(
                    color: Colors.amber.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: Colors.amber.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, color: noteColor, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest data stays on this device account. Sign in later to keep it safe.',
                          style: TextStyle(fontSize: 11.5, height: 1.4, color: noteColor),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.pop(context),
                        style: TextButton.styleFrom(
                          foregroundColor: Theme.of(context).colorScheme.onSurface,
                          backgroundColor: _tint(context, 0.07),
                          minimumSize: const Size(0, 50),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: FilledButton(
                        onPressed: _submit,
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          foregroundColor: _onColor(accent),
                          minimumSize: const Size(0, 50),
                          shape: const StadiumBorder(),
                          textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                        ),
                        child: const Text('Continue'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// EMAIL SHEET
// ═════════════════════════════════════════════════════════════════════════════

/// Email + Password Sheet with Sign In, Create Account and Forgot Password
class _EmailAuthBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;

  const _EmailAuthBottomSheet({required this.onSuccess});

  @override
  ConsumerState<_EmailAuthBottomSheet> createState() => _EmailAuthBottomSheetState();
}

class _EmailAuthBottomSheetState extends ConsumerState<_EmailAuthBottomSheet> {
  /// 0 = Sign In, 1 = Create Account
  int _tab = 0;

  final _signInFormKey = GlobalKey<FormState>();
  final _signUpFormKey = GlobalKey<FormState>();

  final _signInEmailController = TextEditingController();
  final _signInPasswordController = TextEditingController();

  final _signUpNameController = TextEditingController();
  final _signUpEmailController = TextEditingController();
  final _signUpPasswordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscureSignInPass = true;
  bool _obscureSignUpPass = true;

  /// Shown inside the sheet. (A snackbar would appear behind the sheet,
  /// where it cannot be seen.)
  String? _message;
  bool _messageIsError = true;

  @override
  void dispose() {
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = true;
    });
  }

  void _showInfo(String message) {
    if (!mounted) return;
    setState(() {
      _message = message;
      _messageIsError = false;
    });
  }

  void _selectTab(int tab) {
    if (_tab == tab || _isSubmitting) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _tab = tab;
      _message = null;
    });
  }

  Future<void> _submitSignIn() async {
    if (_isSubmitting) return;
    if (_signInFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final res = await AuthService.instance.signInWithEmail(
      _signInEmailController.text.trim(),
      _signInPasswordController.text,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res.success) {
        widget.onSuccess();
      } else {
        _showError(res.message ?? 'Sign-in failed');
      }
    }
  }

  Future<void> _submitSignUp() async {
    if (_isSubmitting) return;
    if (_signUpFormKey.currentState?.validate() != true) return;
    FocusScope.of(context).unfocus();
    setState(() {
      _isSubmitting = true;
      _message = null;
    });

    final res = await AuthService.instance.signUpWithEmail(
      _signUpNameController.text.trim(),
      _signUpEmailController.text.trim(),
      _signUpPasswordController.text,
    );

    if (mounted) {
      setState(() => _isSubmitting = false);
      if (res.success) {
        widget.onSuccess();
      } else {
        _showError(res.message ?? 'Sign-up failed');
      }
    }
  }

  Future<void> _handleForgotPassword() async {
    final email = await showDialog<String>(
      context: context,
      builder: (ctx) => _ResetPasswordDialog(
        initialEmail: _signInEmailController.text.trim(),
        accent: ref.read(customizationProvider).accentColor,
      ),
    );

    if (email == null || email.isEmpty) return;

    final res = await AuthService.instance.sendPasswordReset(email);
    if (res.success) {
      _showInfo('Password reset link sent to your email!');
    } else {
      _showError(res.message ?? 'Failed to send reset link');
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;

    return Padding(
      // Lifts the whole sheet above the keyboard
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
          borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
        ),
        child: SafeArea(
          top: false,
          // Scrolls when it does not fit (small phones, landscape, big text)
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 38,
                    height: 4,
                    decoration: BoxDecoration(
                      color: _tint(context, 0.18),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 16),

                Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.mail_outline_rounded, color: accent, size: 22),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: const Duration(milliseconds: 200),
                        layoutBuilder: (currentChild, previousChildren) {
                          return Stack(
                            alignment: Alignment.centerLeft,
                            children: [
                              ...previousChildren,
                              if (currentChild != null) currentChild,
                            ],
                          );
                        },
                        child: Text(
                          _tab == 0 ? 'Welcome back' : 'Create your account',
                          key: ValueKey(_tab),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w800, fontSize: 20),
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Close',
                      onPressed: () => Navigator.pop(context),
                      icon: Icon(Icons.close_rounded, size: 22, color: _muted(context)),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _Segmented(
                  labels: const ['Sign In', 'Create Account'],
                  index: _tab,
                  accent: accent,
                  onChanged: _selectTab,
                ),

                // Error / confirmation message
                AnimatedSize(
                  duration: const Duration(milliseconds: 240),
                  curve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  child: _message == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 14),
                          child: _buildMessage(isDark),
                        ),
                ),
                const SizedBox(height: 16),

                // Both forms stay alive (what you typed is kept when you
                // switch) and the sheet's height glides between them.
                AnimatedCrossFade(
                  duration: const Duration(milliseconds: 240),
                  sizeCurve: Curves.easeOutCubic,
                  alignment: Alignment.topCenter,
                  crossFadeState: _tab == 0 ? CrossFadeState.showFirst : CrossFadeState.showSecond,
                  firstChild: _buildSignInForm(accent),
                  secondChild: _buildSignUpForm(accent),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildMessage(bool isDark) {
    final color = _messageIsError
        ? (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFC62828))
        : (isDark ? const Color(0xFF4ADE80) : const Color(0xFF2E7D32));

    return Container(
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            _messageIsError ? Icons.error_outline_rounded : Icons.check_circle_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 9),
          Expanded(
            child: Text(
              _message ?? '',
              style: TextStyle(fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600, color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _submitButton({
    required Color accent,
    required String label,
    required VoidCallback onPressed,
  }) {
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: accent,
        foregroundColor: _onColor(accent),
        disabledBackgroundColor: accent.withValues(alpha: 0.6),
        minimumSize: const Size(0, 54),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15),
      ),
      onPressed: _isSubmitting ? null : onPressed,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 180),
        child: _isSubmitting
            ? SizedBox(
                key: const ValueKey('busy'),
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2.4, color: _onColor(accent)),
              )
            : Text(label, key: const ValueKey('label')),
      ),
    );
  }

  Widget _visibilityToggle(bool obscured, VoidCallback onPressed) {
    return IconButton(
      tooltip: obscured ? 'Show password' : 'Hide password',
      icon: Icon(obscured ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
      onPressed: onPressed,
    );
  }

  // Tab 1: Sign In
  Widget _buildSignInForm(Color accent) {
    return Form(
      key: _signInFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signInEmailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: _fieldDecoration(context, label: 'Email', icon: Icons.email_outlined, accent: accent),
              validator: (v) => v?.contains('@') == true ? null : 'Enter valid email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signInPasswordController,
              obscureText: _obscureSignInPass,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.password],
              onFieldSubmitted: (_) => _submitSignIn(),
              decoration: _fieldDecoration(
                context,
                label: 'Password',
                icon: Icons.lock_outline_rounded,
                accent: accent,
                suffix: _visibilityToggle(
                  _obscureSignInPass,
                  () => setState(() => _obscureSignInPass = !_obscureSignInPass),
                ),
              ),
              validator: (v) => (v?.length ?? 0) >= 6 ? null : 'Min 6 characters',
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: _isSubmitting ? null : _handleForgotPassword,
                style: TextButton.styleFrom(foregroundColor: Theme.of(context).colorScheme.onSurface),
                child: const Text('Forgot Password?', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
              ),
            ),
            const SizedBox(height: 6),
            _submitButton(accent: accent, label: 'Sign In', onPressed: _submitSignIn),
          ],
        ),
      ),
    );
  }

  // Tab 2: Sign Up
  Widget _buildSignUpForm(Color accent) {
    return Form(
      key: _signUpFormKey,
      child: AutofillGroup(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextFormField(
              controller: _signUpNameController,
              textCapitalization: TextCapitalization.words,
              textInputAction: TextInputAction.next,
              autofillHints: const [AutofillHints.name],
              decoration: _fieldDecoration(context, label: 'Your Name', icon: Icons.person_outline_rounded, accent: accent),
              validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Min 2 characters',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signUpEmailController,
              keyboardType: TextInputType.emailAddress,
              textInputAction: TextInputAction.next,
              autocorrect: false,
              autofillHints: const [AutofillHints.email],
              decoration: _fieldDecoration(context, label: 'Email', icon: Icons.email_outlined, accent: accent),
              validator: (v) => v?.contains('@') == true ? null : 'Enter valid email',
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _signUpPasswordController,
              obscureText: _obscureSignUpPass,
              textInputAction: TextInputAction.done,
              autofillHints: const [AutofillHints.newPassword],
              onFieldSubmitted: (_) => _submitSignUp(),
              decoration: _fieldDecoration(
                context,
                label: 'Password (min 6 characters)',
                icon: Icons.lock_outline_rounded,
                accent: accent,
                suffix: _visibilityToggle(
                  _obscureSignUpPass,
                  () => setState(() => _obscureSignUpPass = !_obscureSignUpPass),
                ),
              ),
              validator: (v) => (v?.length ?? 0) >= 6 ? null : 'Min 6 characters',
            ),
            const SizedBox(height: 18),
            _submitButton(accent: accent, label: 'Create Account', onPressed: _submitSignUp),
          ],
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// RESET PASSWORD DIALOG
// ═════════════════════════════════════════════════════════════════════════════

/// Asks which email to send the reset link to. Pops with the trimmed email,
/// or null if cancelled.
class _ResetPasswordDialog extends StatefulWidget {
  const _ResetPasswordDialog({required this.initialEmail, required this.accent});

  final String initialEmail;
  final Color accent;

  @override
  State<_ResetPasswordDialog> createState() => _ResetPasswordDialogState();
}

class _ResetPasswordDialogState extends State<_ResetPasswordDialog> {
  late final TextEditingController _controller = TextEditingController(text: widget.initialEmail);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF181818) : const Color(0xFFFFFFFF),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(22),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: accent.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: Icon(Icons.lock_reset_rounded, color: accent, size: 23),
                  ),
                  const SizedBox(width: 13),
                  const Expanded(
                    child: Text(
                      'Reset Password',
                      style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.w800, fontSize: 20),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'Enter your account email to receive a password reset link:',
                style: TextStyle(fontSize: 13.5, height: 1.4, color: _muted(context)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _controller,
                autofocus: true,
                keyboardType: TextInputType.emailAddress,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                onSubmitted: (_) => Navigator.pop(context, _controller.text.trim()),
                decoration: _fieldDecoration(
                  context,
                  label: 'Email Address',
                  icon: Icons.email_outlined,
                  accent: accent,
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.pop(context),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        backgroundColor: _tint(context, 0.07),
                        minimumSize: const Size(0, 50),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                      ),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: () => Navigator.pop(context, _controller.text.trim()),
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: _onColor(accent),
                        minimumSize: const Size(0, 50),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                      ),
                      child: const Text('Send Link'),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}