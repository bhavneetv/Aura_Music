import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/customization_provider.dart';
import '../../../services/auth/auth_service.dart';
import '../../../services/sync/sync_service.dart';
import '../../admin/admin_dashboard_screen.dart';

// -------------------------------------------------------------
// 1. Account Section
// -------------------------------------------------------------

class FirebaseAccountSection extends ConsumerWidget {
  const FirebaseAccountSection({super.key});

  void _showError(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFFC62828), content: Text(msg)),
    );
  }

  void _showSuccess(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(backgroundColor: const Color(0xFF2E7D32), content: Text(msg)),
    );
  }

  Future<void> _editDisplayName(BuildContext context) async {
    final current = AuthService.instance.currentUserName;
    final controller = TextEditingController(text: current);

    final newName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Change Display Name'),
        content: TextField(
          controller: controller,
          textCapitalization: TextCapitalization.words,
          decoration: const InputDecoration(labelText: 'Display Name (2-24 chars)'),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && context.mounted) {
      final res = await AuthService.instance.updateDisplayName(newName);
      if (context.mounted) {
        if (res.success) {
          _showSuccess(context, 'Display name updated!');
        } else {
          _showError(context, res.message ?? 'Failed to update name');
        }
      }
    }
  }

  Future<void> _linkEmail(BuildContext context, Color accent) async {
    final connResults = await Connectivity().checkConnectivity();
    if (!context.mounted) return;
    if (connResults.contains(ConnectivityResult.none) || connResults.isEmpty) {
      _showError(context, 'Account linking is disabled in offline mode. Please connect to the internet.');
      return;
    }
    final initialEmail = AuthService.instance.googleEmail ?? AuthService.instance.currentFirebaseUser?.email ?? '';
    final ok = await showDialog<bool>(
      context: context,
      barrierDismissible: true,
      builder: (ctx) => _LinkEmailPasswordDialog(
        initialEmail: initialEmail,
        accent: accent,
      ),
    );

    if (ok == true && context.mounted) {
      _showSuccess(context, 'Account linked! You can now sign in using either Google or your email & password.');
    }
  }

  Future<void> _linkGoogle(BuildContext context) async {
    final connResults = await Connectivity().checkConnectivity();
    if (!context.mounted) return;
    if (connResults.contains(ConnectivityResult.none) || connResults.isEmpty) {
      _showError(context, 'Account linking is disabled in offline mode. Please connect to the internet.');
      return;
    }
    final res = await AuthService.instance.linkGoogleAccount();
    if (context.mounted) {
      if (res.success) {
        _showSuccess(context, 'Google account linked! You can now sign in using either Google or your email & password.');
      } else {
        _showError(context, res.message ?? 'Failed to link Google account');
      }
    }
  }

  Future<void> _sendVerification(BuildContext context) async {
    final res = await AuthService.instance.sendEmailVerification();
    if (context.mounted) {
      if (res.success) {
        _showSuccess(context, 'Verification email sent!');
      } else {
        _showError(context, res.message ?? 'Failed to send verification email');
      }
    }
  }

  Future<void> _signOut(BuildContext context) async {
    final connResults = await Connectivity().checkConnectivity();
    if (connResults.contains(ConnectivityResult.none) || connResults.isEmpty) {
      if (context.mounted) {
        _showError(context, 'Logout is disabled in offline mode. Please connect to the internet.');
      }
      return;
    }
    await AuthService.instance.signOut();
    if (context.mounted) context.go('/login');
  }

  Future<void> _confirmDeleteAccount(BuildContext context) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete Account?'),
        content: const Text(
          'This will permanently delete your user profile, personal stats, and cloud data. This action cannot be undone.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Permanently'),
          ),
        ],
      ),
    );

    if (confirm == true && context.mounted) {
      final res = await AuthService.instance.deleteAccount();
      if (res.success && context.mounted) {
        context.go('/login');
      } else if (context.mounted) {
        _showError(context, res.message ?? 'Failed to delete account');
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final appUser = ref.watch(currentAppUserStreamProvider).value;
    final isGuest = ref.watch(isGuestProvider);
    final isAdmin = ref.watch(isAdminProvider);
    final user = AuthService.instance.currentFirebaseUser;

    if (user == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161616) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.account_circle_outlined, size: 22, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Not Signed In', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                  const SizedBox(height: 1),
                  Text('Sign in to sync your library', style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.black54)),
                ],
              ),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: accent,
                foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
              ),
              onPressed: () => context.go('/login'),
              child: const Text('Sign In', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );
    }

    final isGoogleLinked = AuthService.instance.isGoogleLinked;
    final isEmailPasswordLinked = AuthService.instance.isEmailPasswordLinked;
    final googleEmail = AuthService.instance.googleEmail;
    final passwordEmail = AuthService.instance.passwordEmail;
    final isDualLogin = isGoogleLinked && isEmailPasswordLinked;

    final displayName = appUser?.displayName.isNotEmpty == true
        ? appUser!.displayName
        : (user.displayName?.isNotEmpty == true ? user.displayName! : 'Aura Listener');

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151515) : Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06),
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.25 : 0.04),
            blurRadius: 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 1. Profile Header Row
          Row(
            children: [
              CircleAvatar(
                radius: 22,
                backgroundColor: accent.withValues(alpha: 0.18),
                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? Text(
                        (displayName.isNotEmpty ? displayName[0] : 'A').toUpperCase(),
                        style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 17),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            displayName,
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isAdmin) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFF7C3AED),
                              borderRadius: BorderRadius.circular(5),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.shield_rounded, size: 9, color: Colors.white),
                                SizedBox(width: 2.5),
                                Text(
                                  'ADMIN',
                                  style: TextStyle(
                                    fontSize: 8.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                    letterSpacing: 0.6,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: () => _editDisplayName(context),
                          child: Padding(
                            padding: const EdgeInsets.all(2),
                            child: Icon(Icons.edit_outlined, size: 14, color: isDark ? Colors.white54 : Colors.black45),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      isGuest
                          ? 'Guest Session (Unsaved)'
                          : (user.email ?? 'Connected Account'),
                      style: TextStyle(
                        fontSize: 11.5,
                        color: isGuest
                            ? Colors.amber.shade700
                            : (isDark ? Colors.white54 : Colors.black54),
                        fontWeight: isGuest ? FontWeight.w600 : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black54),
                tooltip: 'Account Options',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'edit') _editDisplayName(context);
                  if (val == 'verify') _sendVerification(context);
                  if (val == 'admin') {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
                    );
                  }
                  if (val == 'logout') _signOut(context);
                  if (val == 'delete') _confirmDeleteAccount(context);
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                    value: 'edit',
                    height: 38,
                    child: Row(
                      children: [
                        Icon(Icons.edit_outlined, size: 17, color: isDark ? Colors.white70 : Colors.black87),
                        const SizedBox(width: 10),
                        const Text('Edit Name', style: TextStyle(fontSize: 13)),
                      ],
                    ),
                  ),
                  if (user.email != null && !user.emailVerified)
                    PopupMenuItem(
                      value: 'verify',
                      height: 38,
                      child: Row(
                        children: [
                          Icon(Icons.mark_email_read_outlined, size: 17, color: accent),
                          const SizedBox(width: 10),
                          const Text('Send Verification', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  if (isAdmin)
                    PopupMenuItem(
                      value: 'admin',
                      height: 38,
                      child: Row(
                        children: const [
                          Icon(Icons.admin_panel_settings_rounded, size: 17, color: Color(0xFF7C3AED)),
                          SizedBox(width: 10),
                          Text('Admin Portal', style: TextStyle(fontSize: 13)),
                        ],
                      ),
                    ),
                  PopupMenuItem(
                    value: 'logout',
                    height: 38,
                    child: Row(
                      children: const [
                        Icon(Icons.logout_rounded, size: 17, color: Colors.redAccent),
                        SizedBox(width: 10),
                        Text('Sign Out', style: TextStyle(fontSize: 13, color: Colors.redAccent, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    height: 38,
                    child: Row(
                      children: const [
                        Icon(Icons.delete_forever_rounded, size: 17, color: Colors.grey),
                        SizedBox(width: 10),
                        Text('Delete Account', style: TextStyle(fontSize: 13, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
            ],
          ),

          const SizedBox(height: 14),
          const Divider(height: 1),
          const SizedBox(height: 12),

          // 2. Sign-In Methods & Linked Accounts Section
          Row(
            children: [
              Icon(Icons.security_rounded, size: 14, color: isDark ? Colors.white54 : Colors.black54),
              const SizedBox(width: 6),
              Text(
                'SIGN-IN METHODS & LINKED ACCOUNTS',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.5,
                  color: isDark ? Colors.white54 : Colors.black54,
                ),
              ),
            ],
          ),

          const SizedBox(height: 10),

          // Google Account Tile (Shows Google email)
          _buildProviderTile(
            context: context,
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFFEA4335).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(
                child: Text(
                  'G',
                  style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.w900,
                    fontFamily: 'Outfit',
                    color: Color(0xFFEA4335),
                  ),
                ),
              ),
            ),
            title: 'Google Account',
            subtitle: isGoogleLinked
                ? (googleEmail?.isNotEmpty == true ? googleEmail! : (user.email ?? 'Connected'))
                : 'Not connected',
            isLinked: isGoogleLinked,
            onLink: () => _linkGoogle(context),
            linkButtonText: 'Link Google',
            accent: accent,
            isDark: isDark,
          ),

          const SizedBox(height: 8),

          // Email & Password Tile (Shows Email/Password email)
          _buildProviderTile(
            context: context,
            icon: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                color: const Color(0xFF3B82F6).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Center(
                child: Icon(Icons.mark_email_read_outlined, size: 17, color: Color(0xFF3B82F6)),
              ),
            ),
            title: 'Email & Password',
            subtitle: isEmailPasswordLinked
                ? (passwordEmail?.isNotEmpty == true ? passwordEmail! : (user.email ?? 'Connected'))
                : 'Not connected',
            isLinked: isEmailPasswordLinked,
            onLink: () => _linkEmail(context, accent),
            linkButtonText: 'Link Email & Pass',
            accent: accent,
            isDark: isDark,
          ),

          const SizedBox(height: 10),

          // 3. Dual Login Info Callout Banner
          if (isDualLogin) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: accent.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  Icon(Icons.swap_horiz_rounded, size: 16, color: accent),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Dual Login Active: You can sign in using either your Google Account or Email & Password to access this exact same account.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white70 : Colors.black87,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isGoogleLinked && !isEmailPasswordLinked) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 15, color: Colors.amber.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Link Email & Password above so you can sign in to this exact same account using either Google or your email & password.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isEmailPasswordLinked && !isGoogleLinked) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: isDark ? Colors.white.withValues(alpha: 0.03) : Colors.black.withValues(alpha: 0.02),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
              ),
              child: Row(
                children: [
                  Icon(Icons.lightbulb_outline_rounded, size: 15, color: Colors.amber.shade600),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Tip: Link your Google account above to enable instant 1-tap Google login into this exact same account.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.white60 : Colors.black54,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ] else if (isGuest) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withValues(alpha: 0.25)),
              ),
              child: Row(
                children: [
                  Icon(Icons.cloud_off_rounded, size: 15, color: Colors.amber.shade700),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Guest Session: Link Google or an Email & Password above to backup and sync your library across devices.',
                      style: TextStyle(
                        fontSize: 11,
                        color: isDark ? Colors.amber.shade200 : Colors.amber.shade900,
                        fontWeight: FontWeight.w600,
                        height: 1.3,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildProviderTile({
    required BuildContext context,
    required Widget icon,
    required String title,
    required String subtitle,
    required bool isLinked,
    required VoidCallback onLink,
    required String linkButtonText,
    required Color accent,
    required bool isDark,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? Colors.white.withValues(alpha: 0.035) : Colors.black.withValues(alpha: 0.025),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isLinked
              ? (isDark ? Colors.white.withValues(alpha: 0.08) : Colors.black.withValues(alpha: 0.06))
              : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
        ),
      ),
      child: Row(
        children: [
          icon,
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 11.5,
                    color: isLinked
                        ? (isDark ? Colors.white70 : Colors.black87)
                        : (isDark ? Colors.white38 : Colors.black38),
                    fontWeight: isLinked ? FontWeight.w500 : FontWeight.normal,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          if (isLinked)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.check_circle_rounded, size: 12, color: Color(0xFF4CAF50)),
                  SizedBox(width: 4),
                  Text(
                    'Linked',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF4CAF50),
                    ),
                  ),
                ],
              ),
            )
          else
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(9)),
                backgroundColor: accent.withValues(alpha: 0.16),
                foregroundColor: accent,
              ),
              onPressed: onLink,
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.link_rounded, size: 14),
                  const SizedBox(width: 4),
                  Text(
                    linkButtonText,
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

// -------------------------------------------------------------
// Dedicated Link Email & Password Dialog
// -------------------------------------------------------------

class _LinkEmailPasswordDialog extends StatefulWidget {
  final String initialEmail;
  final Color accent;

  const _LinkEmailPasswordDialog({
    required this.initialEmail,
    required this.accent,
  });

  @override
  State<_LinkEmailPasswordDialog> createState() => _LinkEmailPasswordDialogState();
}

class _LinkEmailPasswordDialogState extends State<_LinkEmailPasswordDialog> {
  late final TextEditingController _emailCtrl;
  final TextEditingController _passCtrl = TextEditingController();
  final TextEditingController _confirmPassCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _obscurePass = true;
  bool _obscureConfirmPass = true;
  bool _isSubmitting = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _emailCtrl = TextEditingController(text: widget.initialEmail);
  }

  @override
  void dispose() {
    _emailCtrl.dispose();
    _passCtrl.dispose();
    _confirmPassCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_formKey.currentState?.validate() != true) return;
    setState(() {
      _isSubmitting = true;
      _errorMessage = null;
    });

    final res = await AuthService.instance.linkEmailPassword(
      _emailCtrl.text.trim(),
      _passCtrl.text,
    );

    if (mounted) {
      if (res.success) {
        Navigator.pop(context, true);
      } else {
        setState(() {
          _isSubmitting = false;
          _errorMessage = res.message ?? 'Failed to link account';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = widget.accent;

    return Dialog(
      backgroundColor: isDark ? const Color(0xFF181818) : Colors.white,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: accent.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.link_rounded, color: accent, size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            'Link Email & Password',
                            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                          ),
                          const SizedBox(height: 1),
                          Text(
                            'Enable dual login for this account',
                            style: TextStyle(fontSize: 11.5, color: isDark ? Colors.white54 : Colors.black54),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close_rounded, size: 20),
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.info_outline_rounded, size: 16, color: accent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'You can keep your Google email address or choose another email. Once linked, logging in with Google OR this email and password will access this exact same account.',
                          style: TextStyle(fontSize: 11.5, height: 1.35, color: isDark ? Colors.white70 : Colors.black87),
                        ),
                      ),
                    ],
                  ),
                ),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline_rounded, size: 16, color: Colors.redAccent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(fontSize: 12, color: Colors.redAccent, fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                TextFormField(
                  controller: _emailCtrl,
                  keyboardType: TextInputType.emailAddress,
                  autocorrect: false,
                  decoration: InputDecoration(
                    labelText: 'Login Email',
                    hintText: 'name@example.com',
                    prefixIcon: const Icon(Icons.email_outlined, size: 20),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v != null && v.contains('@') && v.contains('.')) ? null : 'Please enter a valid email address',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _passCtrl,
                  obscureText: _obscurePass,
                  decoration: InputDecoration(
                    labelText: 'Password',
                    hintText: 'Min 6 characters',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscurePass ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                      onPressed: () => setState(() => _obscurePass = !_obscurePass),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) => (v != null && v.length >= 6) ? null : 'Password must be at least 6 characters',
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: _confirmPassCtrl,
                  obscureText: _obscureConfirmPass,
                  decoration: InputDecoration(
                    labelText: 'Confirm Password',
                    hintText: 'Re-enter your password',
                    prefixIcon: const Icon(Icons.lock_outline_rounded, size: 20),
                    suffixIcon: IconButton(
                      icon: Icon(_obscureConfirmPass ? Icons.visibility_off_rounded : Icons.visibility_rounded, size: 20),
                      onPressed: () => setState(() => _obscureConfirmPass = !_obscureConfirmPass),
                    ),
                    filled: true,
                    fillColor: isDark ? const Color(0xFF222222) : const Color(0xFFF5F5F5),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(14), borderSide: BorderSide.none),
                  ),
                  validator: (v) {
                    if (v != _passCtrl.text) return 'Passwords do not match';
                    return null;
                  },
                ),
                const SizedBox(height: 20),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: _isSubmitting ? null : () => Navigator.pop(context, false),
                      child: const Text('Cancel'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: accent,
                        foregroundColor: ThemeData.estimateBrightnessForColor(accent) == Brightness.dark ? Colors.white : Colors.black,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                      ),
                      onPressed: _isSubmitting ? null : _submit,
                      child: _isSubmitting
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                            )
                          : const Text('Link Account', style: TextStyle(fontWeight: FontWeight.bold)),
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

// -------------------------------------------------------------
// 2. Sync Section
// -------------------------------------------------------------

class FirebaseSyncSection extends ConsumerWidget {
  const FirebaseSyncSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final syncService = SyncService.instance;

    return ValueListenableBuilder<bool>(
      valueListenable: syncService.isSyncing,
      builder: (context, syncing, _) {
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: syncService.autoSync,
                builder: (context, auto, _) {
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Auto Sync Playlists', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Live listeners on open & collaborative playlists', style: TextStyle(fontSize: 12)),
                    activeThumbColor: accent,
                    value: auto,
                    onChanged: (val) => syncService.setAutoSync(val),
                  );
                },
              ),
              ValueListenableBuilder<bool>(
                valueListenable: syncService.syncWifiOnly,
                builder: (context, wifiOnly, _) {
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Sync on Wi-Fi Only', style: TextStyle(fontWeight: FontWeight.bold)),
                    subtitle: const Text('Preserve cellular data usage', style: TextStyle(fontSize: 12)),
                    activeThumbColor: accent,
                    value: wifiOnly,
                    onChanged: (val) => syncService.setSyncWifiOnly(val),
                  );
                },
              ),
              const Divider(height: 16),
              Row(
                children: [
                  Expanded(
                    child: ValueListenableBuilder<DateTime?>(
                      valueListenable: syncService.lastSyncedAt,
                      builder: (context, lastTime, _) {
                        final timeStr = lastTime != null
                            ? DateFormat('MMM d, h:mm a').format(lastTime)
                            : 'Never';
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Last synced:', style: TextStyle(fontSize: 11, color: Colors.grey)),
                            Text(timeStr, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                          ],
                        );
                      },
                    ),
                  ),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
                    onPressed: syncing
                        ? null
                        : () async {
                            final connResults = await Connectivity().checkConnectivity();
                            final isOffline = connResults.contains(ConnectivityResult.none) || connResults.isEmpty;
                            if (isOffline) {
                              if (context.mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  const SnackBar(content: Text('Account & database sync is disabled in offline mode.')),
                                );
                              }
                              return;
                            }
                            final msg = await syncService.syncNow();
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
                            }
                          },
                    icon: syncing
                        ? const SizedBox(width: 14, height: 14, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                        : const Icon(Icons.sync_rounded, size: 16),
                    label: Text(syncing ? 'Syncing...' : 'Sync Now'),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }
}

// -------------------------------------------------------------
// 3. My Stats Graphs Section (fl_chart)
// -------------------------------------------------------------

class FirebaseMyStatsSection extends ConsumerWidget {
  const FirebaseMyStatsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;
    final appUser = ref.watch(currentAppUserStreamProvider).value;
    final stats = appUser?.stats;

    if (stats == null || stats.totalSongsPlayed == 0) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF161616) : Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
        ),
        child: Center(
          child: Column(
            children: [
              Icon(Icons.bar_chart_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.5)),
              const SizedBox(height: 8),
              const Text('No listening stats yet', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text('Play songs for at least 30 seconds to start tracking!', style: TextStyle(fontSize: 12, color: Colors.grey)),
            ],
          ),
        ),
      );
    }

    // Prepare 7-day daily listens data
    final now = DateTime.now();
    final last7Days = <String, int>{};
    for (int i = 6; i >= 0; i--) {
      final d = now.subtract(Duration(days: i));
      final key = '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
      final label = '${d.month}/${d.day}';
      last7Days[label] = stats.dailyListens[key] ?? 0;
    }

    // Prepare top 5 artists
    final sortedArtists = stats.topArtists.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final top5 = sortedArtists.take(5).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Big Metric Numbers
        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161616) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Total Listens', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                    const SizedBox(height: 6),
                    Text(
                      '${stats.totalSongsPlayed}',
                      style: const TextStyle(fontSize: 26, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161616) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Favorite Singer', style: TextStyle(fontSize: 12, color: isDark ? Colors.white60 : Colors.black54)),
                    const SizedBox(height: 6),
                    Text(
                      stats.favoriteArtist ?? 'Exploring',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, fontFamily: 'Outfit', color: accent),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // 7-day Bar Chart
        Container(
          height: 180,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('Daily Listens (Last 7 Days)', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(height: 12),
              Expanded(
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: (last7Days.values.fold(0, (m, v) => v > m ? v : m) + 2).toDouble(),
                    titlesData: FlTitlesData(
                      leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (val, _) {
                            final keys = last7Days.keys.toList();
                            final i = val.toInt();
                            if (i >= 0 && i < keys.length) {
                              return Padding(
                                padding: const EdgeInsets.only(top: 4),
                                child: Text(keys[i], style: const TextStyle(fontSize: 9)),
                              );
                            }
                            return const SizedBox.shrink();
                          },
                        ),
                      ),
                    ),
                    gridData: const FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    barGroups: last7Days.entries.toList().asMap().entries.map((e) {
                      return BarChartGroupData(
                        x: e.key,
                        barRods: [
                          BarChartRodData(
                            toY: e.value.value.toDouble(),
                            color: accent,
                            width: 12,
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 16),

        // Top 5 Artists list
        if (top5.isNotEmpty) ...[
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF161616) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Top Artists', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                const SizedBox(height: 8),
                ...top5.asMap().entries.map((entry) {
                  final idx = entry.key + 1;
                  final artist = entry.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Text('#$idx', style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 13)),
                        const SizedBox(width: 12),
                        Expanded(child: Text(artist.key, style: const TextStyle(fontWeight: FontWeight.w500))),
                        Text('${artist.value} plays', style: const TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  );
                }),
              ],
            ),
          ),
        ],
      ],
    );
  }
}

// -------------------------------------------------------------
// 4. Admin Portal Tile
// -------------------------------------------------------------

class FirebaseAdminPortalTile extends ConsumerWidget {
  const FirebaseAdminPortalTile({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAdmin = ref.watch(isAdminProvider);
    if (!isAdmin) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: Colors.deepPurple.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
      ),
      child: ListTile(
        leading: Container(
          padding: const EdgeInsets.all(8),
          decoration: const BoxDecoration(color: Colors.deepPurple, shape: BoxShape.circle),
          child: const Icon(Icons.admin_panel_settings_rounded, color: Colors.white, size: 20),
        ),
        title: const Text('Admin Portal', style: TextStyle(fontWeight: FontWeight.bold)),
        subtitle: const Text('Aggregate analytics, user management, and moderation', style: TextStyle(fontSize: 12)),
        trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
        onTap: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminDashboardScreen()),
          );
        },
      ),
    );
  }
}
