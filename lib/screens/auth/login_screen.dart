import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../themes/app_theme.dart';
import '../../providers/customization_provider.dart';
import '../../services/auth/auth_service.dart';
import '../splash/splash_screen.dart';

class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> with SingleTickerProviderStateMixin {
  late AnimationController _rotationController;
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
    _checkConnectivity();
  }

  @override
  void dispose() {
    _rotationController.dispose();
    super.dispose();
  }

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

    final nameController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final chosenName = await showDialog<String>(
      context: context,
      barrierDismissible: true,
      builder: (dialogCtx) {
        final isDark = Theme.of(dialogCtx).brightness == Brightness.dark;
        final accent = ref.watch(customizationProvider).accentColor;

        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF181818) : const Color(0xFFFFFFFF),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: accent.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.person_outline_rounded, color: accent, size: 22),
              ),
              const SizedBox(width: 12),
              const Text(
                'Guest Profile',
                style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ],
          ),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Enter a display name so collaborators can recognize who added tracks.',
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: nameController,
                  autofocus: true,
                  textCapitalization: TextCapitalization.words,
                  decoration: InputDecoration(
                    labelText: 'Display Name',
                    hintText: 'e.g. VinylLover',
                    filled: true,
                    fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                    prefixIcon: const Icon(Icons.badge_outlined, size: 20),
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
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.amber.withOpacity(0.3)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline_rounded, color: Colors.amber, size: 16),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Guest data stays on this device account. Sign in later to keep it safe.',
                          style: TextStyle(fontSize: 11, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: () {
                if (formKey.currentState?.validate() == true) {
                  Navigator.pop(dialogCtx, nameController.text.trim());
                }
              },
              child: const Text('Continue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (chosenName == null || chosenName.isEmpty) return;

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
      backgroundColor: Colors.transparent,
      builder: (ctx) => _EmailAuthBottomSheet(
        onSuccess: () {
          Navigator.pop(ctx);
          context.go('/home');
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;
    final size = MediaQuery.of(context).size;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF090909) : const Color(0xFFFAF8F5),
      body: Stack(
        children: [
          // Ambient Radial Glow
          Positioned(
            top: -size.width * 0.3,
            right: -size.width * 0.3,
            child: Container(
              width: size.width * 0.9,
              height: size.width * 0.9,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [
                    accentColor.withOpacity(isDark ? 0.20 : 0.25),
                    Colors.transparent,
                  ],
                ),
              ),
            ),
          ),

          // Main Responsive Content
          SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 480),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 24.0),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        physics: const BouncingScrollPhysics(),
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: constraints.maxHeight),
                          child: IntrinsicHeight(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Spacer(flex: 1),

                                // Rotating Vinyl Branding
                                Center(
                                  child: Stack(
                                    alignment: Alignment.center,
                                    children: [
                                      Container(
                                        width: 140,
                                        height: 140,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          boxShadow: [
                                            BoxShadow(
                                              color: accentColor.withOpacity(0.25),
                                              blurRadius: 40,
                                              spreadRadius: 8,
                                            ),
                                          ],
                                        ),
                                      ),
                                      RotationTransition(
                                        turns: _rotationController,
                                        child: const VinylRecordWidget(size: 130),
                                      ),
                                    ],
                                  ),
                                ),

                                const SizedBox(height: 24),

                                // App Branding Title
                                Text(
                                  'AURA',
                                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                                        fontFamily: 'Outfit',
                                        fontSize: 34,
                                        fontWeight: FontWeight.w900,
                                        letterSpacing: 6,
                                        color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                                      ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Vinyl Music Player',
                                  style: TextStyle(
                                    fontFamily: 'Outfit',
                                    fontSize: 13,
                                    letterSpacing: 2.5,
                                    color: (isDark ? Colors.white70 : Colors.black54),
                                    fontWeight: FontWeight.w400,
                                  ),
                                ),

                                const SizedBox(height: 36),

                                // Offline Indicator if disconnected
                                if (_isOffline) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                    margin: const EdgeInsets.only(bottom: 20),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withOpacity(0.12),
                                      borderRadius: BorderRadius.circular(14),
                                      border: Border.all(color: Colors.red.withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.wifi_off_rounded, color: Colors.red, size: 18),
                                        const SizedBox(width: 10),
                                        const Expanded(
                                          child: Text(
                                            'Offline. Connect to internet to sign in.',
                                            style: TextStyle(fontSize: 12, color: Colors.red, fontWeight: FontWeight.w500),
                                          ),
                                        ),
                                        TextButton(
                                          onPressed: _checkConnectivity,
                                          child: const Text('Retry', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // Actions Card (Glassmorphic)
                                Container(
                                  padding: const EdgeInsets.all(22),
                                  decoration: BoxDecoration(
                                    color: (isDark ? const Color(0xFF141414) : Colors.white).withOpacity(0.85),
                                    borderRadius: BorderRadius.circular(28),
                                    border: Border.all(
                                      color: (isDark ? Colors.white : Colors.black).withOpacity(0.08),
                                    ),
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.black.withOpacity(isDark ? 0.35 : 0.06),
                                        blurRadius: 30,
                                        offset: const Offset(0, 10),
                                      ),
                                    ],
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.stretch,
                                    children: [
                                      // 1. Google Sign-In (Primary Action)
                                      ElevatedButton(
                                        onPressed: _isLoading ? null : _handleGoogleSignIn,
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: isDark ? const Color(0xFF242424) : const Color(0xFFFFFFFF),
                                          foregroundColor: isDark ? Colors.white : Colors.black87,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                            side: BorderSide(
                                              color: (isDark ? Colors.white24 : Colors.black12),
                                            ),
                                          ),
                                          elevation: 1,
                                        ),
                                        child: Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            // Google "G" Icon
                                            Container(
                                              width: 22,
                                              height: 22,
                                              alignment: Alignment.center,
                                              child: Text(
                                                'G',
                                                style: TextStyle(
                                                  fontFamily: 'Outfit',
                                                  fontSize: 19,
                                                  fontWeight: FontWeight.w900,
                                                  color: accentColor,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 12),
                                            const Text(
                                              'Continue with Google',
                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 12),

                                      // 2. Email + Password
                                      OutlinedButton(
                                        onPressed: _isLoading ? null : _showEmailAuthModal,
                                        style: OutlinedButton.styleFrom(
                                          foregroundColor: isDark ? Colors.white : Colors.black87,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          side: BorderSide(
                                            color: (isDark ? Colors.white24 : Colors.black12),
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.mail_outline_rounded, size: 20),
                                            SizedBox(width: 10),
                                            Text(
                                              'Email & Password',
                                              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 16),

                                      // Divider
                                      Row(
                                        children: [
                                          Expanded(child: Divider(color: (isDark ? Colors.white12 : Colors.black12))),
                                          Padding(
                                            padding: const EdgeInsets.symmetric(horizontal: 12),
                                            child: Text(
                                              'OR',
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                letterSpacing: 1.5,
                                                color: (isDark ? Colors.white38 : Colors.black38),
                                              ),
                                            ),
                                          ),
                                          Expanded(child: Divider(color: (isDark ? Colors.white12 : Colors.black12))),
                                        ],
                                      ),

                                      const SizedBox(height: 16),

                                      // 3. Continue as Guest (Secondary Action)
                                      FilledButton(
                                        onPressed: _isLoading ? null : _handleGuestSignIn,
                                        style: FilledButton.styleFrom(
                                          backgroundColor: accentColor,
                                          foregroundColor: Colors.black,
                                          padding: const EdgeInsets.symmetric(vertical: 14),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(16),
                                          ),
                                        ),
                                        child: const Row(
                                          mainAxisAlignment: MainAxisAlignment.center,
                                          children: [
                                            Icon(Icons.person_pin_circle_outlined, size: 20),
                                            SizedBox(width: 8),
                                            Text(
                                              'Continue as Guest',
                                              style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(height: 14),

                                      // Guest disclaimer note
                                      Text(
                                        'Guest data stays on this device account.\nSign in later in Settings to back up safely.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          fontSize: 11,
                                          height: 1.4,
                                          color: (isDark ? Colors.white54 : Colors.black54),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),

                                const Spacer(flex: 2),
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),

          // Loading Overlay
          if (_isLoading) ...[
            Container(
              color: Colors.black.withOpacity(0.55),
              child: Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: accentColor),
                      const SizedBox(height: 16),
                      Text(
                        _loadingMessage ?? 'Signing in...',
                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Email + Password Sheet with Tabs for Sign In, Sign Up, and Forgot Password
class _EmailAuthBottomSheet extends ConsumerStatefulWidget {
  final VoidCallback onSuccess;

  const _EmailAuthBottomSheet({required this.onSuccess});

  @override
  ConsumerState<_EmailAuthBottomSheet> createState() => _EmailAuthBottomSheetState();
}

class _EmailAuthBottomSheetState extends ConsumerState<_EmailAuthBottomSheet> with SingleTickerProviderStateMixin {
  late TabController _tabController;
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

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    _signInEmailController.dispose();
    _signInPasswordController.dispose();
    _signUpNameController.dispose();
    _signUpEmailController.dispose();
    _signUpPasswordController.dispose();
    super.dispose();
  }

  void _showError(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        backgroundColor: const Color(0xFFC62828),
        content: Text(message, style: const TextStyle(color: Colors.white)),
      ),
    );
  }

  Future<void> _submitSignIn() async {
    if (_signInFormKey.currentState?.validate() != true) return;
    setState(() => _isSubmitting = true);

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
    if (_signUpFormKey.currentState?.validate() != true) return;
    setState(() => _isSubmitting = true);

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
    final email = _signInEmailController.text.trim();
    final resetController = TextEditingController(text: email);

    final send = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Reset Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Enter your account email to receive a password reset link:'),
            const SizedBox(height: 12),
            TextField(
              controller: resetController,
              keyboardType: TextInputType.emailAddress,
              decoration: const InputDecoration(labelText: 'Email Address'),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Send Link')),
        ],
      ),
    );

    if (send == true && resetController.text.isNotEmpty) {
      final res = await AuthService.instance.sendPasswordReset(resetController.text);
      if (mounted) {
        if (res.success) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Password reset link sent to your email!')),
          );
        } else {
          _showError(res.message ?? 'Failed to send reset link');
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
        top: 12,
        left: 20,
        right: 20,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Drag handle
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.withOpacity(0.4),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 12),

          TabBar(
            controller: _tabController,
            labelColor: accent,
            unselectedLabelColor: Colors.grey,
            indicatorColor: accent,
            tabs: const [
              Tab(text: 'Sign In'),
              Tab(text: 'Create Account'),
            ],
          ),

          const SizedBox(height: 16),

          SizedBox(
            height: 300,
            child: TabBarView(
              controller: _tabController,
              children: [
                // Tab 1: Sign In
                Form(
                  key: _signInFormKey,
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      TextFormField(
                        controller: _signInEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => v?.contains('@') == true ? null : 'Enter valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _signInPasswordController,
                        obscureText: _obscureSignInPass,
                        decoration: InputDecoration(
                          labelText: 'Password',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureSignInPass ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureSignInPass = !_obscureSignInPass),
                          ),
                        ),
                        validator: (v) => (v?.length ?? 0) >= 6 ? null : 'Min 6 characters',
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: _handleForgotPassword,
                          child: Text('Forgot Password?', style: TextStyle(color: accent, fontSize: 13)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isSubmitting ? null : _submitSignIn,
                        child: _isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text('Sign In', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),

                // Tab 2: Sign Up
                Form(
                  key: _signUpFormKey,
                  child: ListView(
                    shrinkWrap: true,
                    physics: const NeverScrollableScrollPhysics(),
                    children: [
                      TextFormField(
                        controller: _signUpNameController,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Your Name', prefixIcon: Icon(Icons.person_outline)),
                        validator: (v) => (v?.trim().length ?? 0) >= 2 ? null : 'Min 2 characters',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _signUpEmailController,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(labelText: 'Email', prefixIcon: Icon(Icons.email_outlined)),
                        validator: (v) => v?.contains('@') == true ? null : 'Enter valid email',
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _signUpPasswordController,
                        obscureText: _obscureSignUpPass,
                        decoration: InputDecoration(
                          labelText: 'Password (min 6 characters)',
                          prefixIcon: const Icon(Icons.lock_outline),
                          suffixIcon: IconButton(
                            icon: Icon(_obscureSignUpPass ? Icons.visibility_off : Icons.visibility),
                            onPressed: () => setState(() => _obscureSignUpPass = !_obscureSignUpPass),
                          ),
                        ),
                        validator: (v) => (v?.length ?? 0) >= 6 ? null : 'Min 6 characters',
                      ),
                      const SizedBox(height: 16),
                      FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: accent,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        onPressed: _isSubmitting ? null : _submitSignUp,
                        child: _isSubmitting
                            ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                            : const Text('Create Account', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
