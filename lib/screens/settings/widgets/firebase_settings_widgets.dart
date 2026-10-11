import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:go_router/go_router.dart';
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
      if (res.success) {
        _showSuccess(context, 'Display name updated!');
      } else {
        _showError(context, res.message ?? 'Failed to update name');
      }
    }
  }

  Future<void> _linkEmail(BuildContext context) async {
    final emailCtrl = TextEditingController();
    final passCtrl = TextEditingController();

    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add Email & Password'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Link an email and password to sign in from any device:'),
            const SizedBox(height: 12),
            TextField(controller: emailCtrl, keyboardType: TextInputType.emailAddress, decoration: const InputDecoration(labelText: 'Email')),
            const SizedBox(height: 8),
            TextField(controller: passCtrl, obscureText: true, decoration: const InputDecoration(labelText: 'Password (min 6 chars)')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('Link Account')),
        ],
      ),
    );

    if (ok == true && context.mounted) {
      final res = await AuthService.instance.linkEmailPassword(emailCtrl.text.trim(), passCtrl.text);
      if (res.success) {
        _showSuccess(context, 'Account linked! A verification email was sent.');
      } else {
        _showError(context, res.message ?? 'Failed to link account');
      }
    }
  }

  Future<void> _linkGoogle(BuildContext context) async {
    final res = await AuthService.instance.linkGoogleAccount();
    if (context.mounted) {
      if (res.success) {
        _showSuccess(context, 'Google account linked successfully!');
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

    final hasGoogle = appUser?.providers.contains('google') ?? false;
    final hasPassword = appUser?.providers.contains('password') ?? false;
    final displayName = appUser?.displayName.isNotEmpty == true
        ? appUser!.displayName
        : (user.displayName?.isNotEmpty == true ? user.displayName! : 'Aura Listener');

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 10, 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF151515) : Colors.white,
        borderRadius: BorderRadius.circular(20),
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
          Row(
            children: [
              // Sleek Avatar
              CircleAvatar(
                radius: 20,
                backgroundColor: accent.withValues(alpha: 0.18),
                backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                child: user.photoURL == null
                    ? Text(
                        (displayName.isNotEmpty ? displayName[0] : 'A').toUpperCase(),
                        style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 16),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // User Details
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
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
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
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            isGuest ? 'Guest Session' : (user.email ?? 'No email'),
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
                        ),
                        if (user.email != null && !user.emailVerified) ...[
                          const SizedBox(width: 6),
                          InkWell(
                            onTap: () => _sendVerification(context),
                            child: Text(
                              'Verify',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: accent,
                                decoration: TextDecoration.underline,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              // More Actions Menu Button
              PopupMenuButton<String>(
                icon: Icon(Icons.more_vert_rounded, size: 20, color: isDark ? Colors.white54 : Colors.black54),
                tooltip: 'Account Options',
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                onSelected: (val) {
                  if (val == 'edit') _editDisplayName(context);
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

          // If Guest or missing provider, show a sleek mini link row
          if (isGuest || !hasGoogle || !hasPassword) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: isGuest
                    ? Colors.amber.withValues(alpha: 0.1)
                    : (isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03)),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isGuest
                      ? Colors.amber.withValues(alpha: 0.25)
                      : (isDark ? Colors.white10 : Colors.black12),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    isGuest ? Icons.cloud_off_rounded : Icons.link_rounded,
                    size: 14,
                    color: isGuest ? Colors.amber.shade700 : (isDark ? Colors.white54 : Colors.black45),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isGuest ? 'Link to sync & save library:' : 'Link accounts:',
                      style: TextStyle(
                        fontSize: 11,
                        color: isGuest
                            ? (isDark ? Colors.amber.shade200 : Colors.amber.shade900)
                            : (isDark ? Colors.white60 : Colors.black54),
                        fontWeight: isGuest ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (!hasGoogle) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _linkGoogle(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: accent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.g_mobiledata_rounded, size: 16, color: accent),
                            const SizedBox(width: 1),
                            Text('Google', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: accent)),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 5),
                  ],
                  if (!hasPassword) ...[
                    InkWell(
                      borderRadius: BorderRadius.circular(6),
                      onTap: () => _linkEmail(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: isDark ? Colors.white10 : Colors.black12,
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.email_outlined, size: 12, color: isDark ? Colors.white70 : Colors.black87),
                            const SizedBox(width: 3),
                            Text('Email', style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)),
                          ],
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ],
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
                    activeColor: accent,
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
                    activeColor: accent,
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
              Icon(Icons.bar_chart_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
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
        color: Colors.deepPurple.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.deepPurple.withOpacity(0.3)),
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
