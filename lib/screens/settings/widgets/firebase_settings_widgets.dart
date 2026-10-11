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
    final user = AuthService.instance.currentFirebaseUser;

    if (user == null) {
      return Card(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        child: ListTile(
          leading: const Icon(Icons.account_circle_outlined, size: 36),
          title: const Text('Not Signed In'),
          subtitle: const Text('Sign in to sync your playlists and collaborate.'),
          trailing: FilledButton(
            style: FilledButton.styleFrom(backgroundColor: accent, foregroundColor: Colors.black),
            onPressed: () => context.go('/login'),
            child: const Text('Sign In'),
          ),
        ),
      );
    }

    final hasGoogle = appUser?.providers.contains('google') ?? false;
    final hasPassword = appUser?.providers.contains('password') ?? false;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Guest Warning Banner
        if (isGuest) ...[
          Container(
            padding: const EdgeInsets.all(14),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: Colors.amber.withOpacity(0.12),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withOpacity(0.3)),
            ),
            child: Row(
              children: [
                const Icon(Icons.warning_amber_rounded, color: Colors.amber, size: 24),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Guest Account Active',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: Colors.amber),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Link Google or Email to protect your playlists from data loss.',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.amber.shade200 : Colors.amber.shade900),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],

        // User Profile Card
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161616) : Colors.white,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  CircleAvatar(
                    radius: 26,
                    backgroundColor: accent.withOpacity(0.2),
                    backgroundImage: user.photoURL != null ? NetworkImage(user.photoURL!) : null,
                    child: user.photoURL == null
                        ? Text(
                            (appUser?.displayName.isNotEmpty == true ? appUser!.displayName[0] : 'A').toUpperCase(),
                            style: TextStyle(color: accent, fontWeight: FontWeight.bold, fontSize: 20),
                          )
                        : null,
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                appUser?.displayName ?? user.displayName ?? 'Aura Listener',
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              onPressed: () => _editDisplayName(context),
                              tooltip: 'Edit Name',
                            ),
                          ],
                        ),
                        Text(
                          isGuest ? 'Guest Session' : (user.email ?? 'No email'),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        if (user.email != null && !user.emailVerified) ...[
                          const SizedBox(height: 2),
                          Row(
                            children: [
                              const Text('Unverified', style: TextStyle(fontSize: 11, color: Colors.orange)),
                              const SizedBox(width: 6),
                              InkWell(
                                onTap: () async {
                                  final res = await AuthService.instance.sendEmailVerification();
                                  if (context.mounted) {
                                    if (res.success) {
                                      _showSuccess(context, 'Verification email sent!');
                                    } else {
                                      _showError(context, res.message ?? 'Failed to send');
                                    }
                                  }
                                },
                                child: Text('Send verification', style: TextStyle(fontSize: 11, color: accent, decoration: TextDecoration.underline)),
                              ),
                            ],
                          ),
                        ],
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(height: 24),

              // Account Linking Actions
              if (isGuest || !hasGoogle) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.g_mobiledata_rounded, size: 28),
                  title: Text(isGuest ? 'Upgrade with Google' : 'Link Google Account'),
                  subtitle: const Text('Keep the same UID & cloud playlists', style: TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () async {
                    final res = await AuthService.instance.linkGoogleAccount();
                    if (context.mounted) {
                      if (res.success) {
                        _showSuccess(context, 'Google account linked successfully!');
                      } else {
                        _showError(context, res.message ?? 'Failed to link');
                      }
                    }
                  },
                ),
              ],
              if (isGuest || !hasPassword) ...[
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.email_outlined),
                  title: Text(isGuest ? 'Upgrade with Email & Password' : 'Add Email & Password'),
                  subtitle: const Text('Add password login capability', style: TextStyle(fontSize: 11)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
                  onTap: () => _linkEmail(context),
                ),
              ],

              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.logout_rounded, color: Colors.red),
                title: const Text('Sign Out', style: TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
                onTap: () async {
                  await AuthService.instance.signOut();
                  if (context.mounted) context.go('/login');
                },
              ),
              ListTile(
                contentPadding: EdgeInsets.zero,
                leading: const Icon(Icons.delete_forever_rounded, color: Colors.grey),
                title: const Text('Delete My Account', style: TextStyle(color: Colors.grey, fontSize: 13)),
                onTap: () => _confirmDeleteAccount(context),
              ),
            ],
          ),
        ),
      ],
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

    final isDark = Theme.of(context).brightness == Brightness.dark;

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
