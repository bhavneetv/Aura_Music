import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/network/app_connectivity.dart';
import '../providers/customization_provider.dart';
import '../services/auth/auth_service.dart';

class AuthModalDialog extends ConsumerStatefulWidget {
  final VoidCallback? onLoggedIn;
  final String? featurePrompt;

  const AuthModalDialog({
    super.key,
    this.onLoggedIn,
    this.featurePrompt,
  });

  static Future<bool> show(
    BuildContext context, {
    VoidCallback? onLoggedIn,
    String? featurePrompt,
  }) async {
    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Account features are unavailable in offline mode. Connect to the internet first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return false;
    }

    if (!context.mounted) return false;

    final result = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => AuthModalDialog(
        onLoggedIn: onLoggedIn,
        featurePrompt: featurePrompt,
      ),
    );
    return result == true;
  }

  @override
  ConsumerState<AuthModalDialog> createState() => _AuthModalDialogState();
}

class _AuthModalDialogState extends ConsumerState<AuthModalDialog> {
  bool _isSignUp = false;
  bool _isLoading = false;
  bool _obscurePassword = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  String? _errorMessage;

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  Future<void> _handleSubmit() async {
    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      setState(() {
        _isLoading = false;
        _errorMessage = 'Internet connection required. Login is disabled in offline mode.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    final email = _emailController.text.trim();
    final password = _passwordController.text.trim();

    AuthResult result;
    if (_isSignUp) {
      final name = _nameController.text.trim();
      result = await AuthService.instance.register(
        name: name,
        email: email,
        password: password,
      );
    } else {
      result = await AuthService.instance.login(
        email: email,
        password: password,
      );
    }

    if (mounted) {
      setState(() => _isLoading = false);
      if (result.success) {
        widget.onLoggedIn?.call();
        Navigator.pop(context, true);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.black, size: 20),
                const SizedBox(width: 8),
                Expanded(child: Text(result.message ?? 'Success', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
              ],
            ),
            backgroundColor: ref.read(customizationProvider).accentColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      } else {
        setState(() => _errorMessage = result.message ?? 'Authentication failed');
      }
    }
  }

  Future<void> _handleLogout() async {
    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot log out in offline mode. Connect to the internet first.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    await AuthService.instance.logout();
    if (mounted) {
      Navigator.pop(context, false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Logged out. You are now using Aura as a guest.'),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handleBackupPlaylists() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final accentColor = ref.read(customizationProvider).accentColor;

    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      if (mounted) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Account sync is disabled in offline mode. Connect to the internet to back up playlists.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    setState(() => _isLoading = true);
    final msg = await AuthService.instance.backupUserPlaylists();
    if (mounted) {
      setState(() => _isLoading = false);
      if (nav.canPop()) {
        nav.pop(true);
      }
      widget.onLoggedIn?.call();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_upload_rounded, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Expanded(child: Text(msg, style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
            ],
          ),
          backgroundColor: accentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _handlePullPlaylists() async {
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final accentColor = ref.read(customizationProvider).accentColor;

    setState(() => _isLoading = true);
    final count = await AuthService.instance.restoreUserPlaylists();
    if (mounted) {
      setState(() => _isLoading = false);
      if (nav.canPop()) {
        nav.pop(true);
      }
      widget.onLoggedIn?.call();
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.cloud_download_rounded, color: Colors.black, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  count > 0
                      ? 'Pulled and restored $count playlists from your cloud backup! 📥'
                      : 'Playlists are already up to date with your cloud backup.',
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
                ),
              ),
            ],
          ),
          backgroundColor: accentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = ref.watch(customizationProvider).accentColor;
    final user = AuthService.instance.currentUser;
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Padding(
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Container(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.85,
        ),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF16161E) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 24,
              offset: const Offset(0, -6),
            ),
          ],
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: user != null ? _buildLoggedInView(user, isDark, accentColor) : _buildAuthForm(isDark, accentColor),
        ),
      ),
    );
  }

  Widget _buildLoggedInView(dynamic user, bool isDark, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 20),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        Center(
          child: Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [accentColor, accentColor.withValues(alpha: 0.6)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              shape: BoxShape.circle,
            ),
            child: const Center(
              child: Icon(Icons.person_rounded, size: 40, color: Colors.black),
            ),
          ),
        ),
        const SizedBox(height: 14),
        Text(
          user.name,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
        ),
        Text(
          AuthService.instance.isGuest ? 'Guest Account (Local Session)' : user.email,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 14, color: isDark ? Colors.white60 : Colors.black54),
        ),
        const SizedBox(height: 24),
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AuthService.instance.isGuest
                ? Colors.amber.withValues(alpha: 0.12)
                : accentColor.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: AuthService.instance.isGuest
                  ? Colors.amber.withValues(alpha: 0.4)
                  : accentColor.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            children: [
              Icon(
                AuthService.instance.isGuest ? Icons.info_outline_rounded : Icons.cloud_done_rounded,
                color: AuthService.instance.isGuest ? Colors.amber : accentColor,
                size: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      AuthService.instance.isGuest ? 'Guest Account (Sync Disabled)' : 'Cloud Account Active',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AuthService.instance.isGuest ? Colors.amber : (isDark ? Colors.white : Colors.black87),
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      AuthService.instance.isGuest
                          ? 'Guest accounts cannot sync playlists to cloud. Please sign in or link an account in Settings to enable multi-device sync.'
                          : 'Global playlist publishing, collaboration, and instant multi-device restore enabled.',
                      style: TextStyle(
                        fontSize: 12,
                        color: AuthService.instance.isGuest
                            ? (isDark ? Colors.amber.shade200 : Colors.amber.shade900)
                            : (isDark ? Colors.white70 : Colors.black54),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        // Push / Backup Button
        ElevatedButton.icon(
          onPressed: (_isLoading || AuthService.instance.isGuest) ? null : _handleBackupPlaylists,
          icon: _isLoading
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.cloud_upload_rounded, color: Colors.black),
          label: Text(
            AuthService.instance.isGuest ? 'Cloud Playlist Sync Disabled (Guest)' : 'Push / Backup Playlists to Cloud ☁️',
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AuthService.instance.isGuest ? Colors.grey.shade400 : accentColor,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 10),
        // Pull / Restore Button
        ElevatedButton.icon(
          onPressed: (_isLoading || AuthService.instance.isGuest) ? null : _handlePullPlaylists,
          icon: _isLoading
              ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
              : Icon(Icons.cloud_download_rounded, color: AuthService.instance.isGuest ? Colors.grey : accentColor),
          label: Text(
            AuthService.instance.isGuest ? 'Cloud Playlist Restore Disabled (Guest)' : 'Pull / Restore Playlists from Cloud 📥',
            style: TextStyle(fontWeight: FontWeight.bold, color: AuthService.instance.isGuest ? Colors.grey : (isDark ? Colors.white : Colors.black87)),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: isDark ? const Color(0xFF22222E) : const Color(0xFFF0F0F5),
            foregroundColor: AuthService.instance.isGuest ? Colors.grey : (isDark ? Colors.white : Colors.black87),
            padding: const EdgeInsets.symmetric(vertical: 14),
            elevation: 0,
            side: BorderSide(color: (AuthService.instance.isGuest ? Colors.grey : accentColor).withValues(alpha: 0.4)),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
        const SizedBox(height: 12),
        OutlinedButton.icon(
          onPressed: _handleLogout,
          icon: const Icon(Icons.logout_rounded, color: Colors.redAccent, size: 18),
          label: const Text('Sign Out', style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold)),
          style: OutlinedButton.styleFrom(
            padding: const EdgeInsets.symmetric(vertical: 12),
            side: const BorderSide(color: Colors.redAccent),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
        ),
      ],
    );
  }

  Widget _buildAuthForm(bool isDark, Color accentColor) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 44,
            height: 4,
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: isDark ? Colors.white24 : Colors.black12,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        if (widget.featurePrompt != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Icon(Icons.lock_person_rounded, color: accentColor, size: 22),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    widget.featurePrompt!,
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _buildTabButton('Log In', !_isSignUp, isDark, accentColor, () => setState(() => _isSignUp = false)),
            const SizedBox(width: 8),
            _buildTabButton('Create Account', _isSignUp, isDark, accentColor, () => setState(() => _isSignUp = true)),
          ],
        ),
        const SizedBox(height: 20),
        Text(
          _isSignUp ? 'Create your Aura Account' : 'Welcome Back to Aura',
          style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 4),
        Text(
          _isSignUp
              ? 'Simple zero-database account. Sync playlists across devices and publish globally!'
              : 'Sign in to access your cloud playlists and collaborative feeds.',
          style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
        ),
        if (_errorMessage != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.redAccent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
            ),
            child: Row(
              children: [
                const Icon(Icons.error_outline_rounded, color: Colors.redAccent, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _errorMessage!,
                    style: const TextStyle(color: Colors.redAccent, fontSize: 13, fontWeight: FontWeight.w500),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 18),
        if (_isSignUp) ...[
          TextField(
            controller: _nameController,
            textCapitalization: TextCapitalization.words,
            decoration: InputDecoration(
              labelText: 'Full Name',
              hintText: 'e.g. Alex Rivera',
              prefixIcon: const Icon(Icons.person_outline_rounded),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 12),
        ],
        TextField(
          controller: _emailController,
          keyboardType: TextInputType.emailAddress,
          autocorrect: false,
          decoration: InputDecoration(
            labelText: 'Email Address',
            hintText: 'you@example.com',
            prefixIcon: const Icon(Icons.email_outlined),
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _passwordController,
          obscureText: _obscurePassword,
          decoration: InputDecoration(
            labelText: 'Password',
            hintText: _isSignUp ? 'Min 4 characters' : 'Enter your password',
            prefixIcon: const Icon(Icons.lock_outline_rounded),
            suffixIcon: IconButton(
              icon: Icon(_obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined, size: 20),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
            filled: true,
            fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
          ),
        ),
        const SizedBox(height: 22),
        ElevatedButton(
          onPressed: _isLoading ? null : _handleSubmit,
          style: ElevatedButton.styleFrom(
            backgroundColor: accentColor,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 14),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          ),
          child: _isLoading
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : Text(
                  _isSignUp ? 'Create Free Account ✨' : 'Sign In 🚀',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(
            'Continue as Guest (No Account Required)',
            style: TextStyle(color: isDark ? Colors.white60 : Colors.black54, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildTabButton(String title, bool isSelected, bool isDark, Color accentColor, VoidCallback onTap) {
    return Expanded(
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? accentColor : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Center(
            child: Text(
              title,
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 14,
                color: isSelected ? Colors.black : (isDark ? Colors.white70 : Colors.black87),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
