import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../services/network/app_connectivity.dart';
import '../../config/admin_config.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/admin/admin_service.dart';
import '../../services/auth/auth_service.dart';
import '../../services/stats/stats_service.dart';
import '../../services/storage/storage_service.dart';
import '../../services/user_service.dart';
import '../../models/app_user.dart';
import '../../models/playlist.dart';

// ─────────────────────────────────────────────────────────────
// Compact design helpers
// ─────────────────────────────────────────────────────────────

Color _surface(bool isDark) => isDark ? const Color(0xFF161616) : Colors.white;
Color _hairline(bool isDark) => isDark ? Colors.white10 : Colors.black12;
Color _muted(bool isDark) => isDark ? Colors.white60 : Colors.black54;

BoxDecoration _cardDeco(bool isDark, {double radius = 14, Color? border}) => BoxDecoration(
      color: _surface(isDark),
      borderRadius: BorderRadius.circular(radius),
      border: Border.all(color: border ?? _hairline(isDark)),
    );

RoundedRectangleBorder _cardShape(bool isDark) => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
      side: BorderSide(color: _hairline(isDark)),
    );

Widget _sectionLabel(String text, bool isDark) => Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 10.5,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.2,
          color: _muted(isDark),
        ),
      ),
    );

Widget _badge(String text, Color color) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(text, style: TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: color)),
    );

Widget _iconDot(IconData icon, Color color, {double size = 28, double iconSize = 15}) => Container(
      width: size,
      height: size,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), shape: BoxShape.circle),
      child: Icon(icon, color: color, size: iconSize),
    );

InputDecoration _searchDeco(String hint) => InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(fontSize: 13),
      prefixIcon: const Icon(Icons.search, size: 18),
      isDense: true,
      filled: true,
      contentPadding: const EdgeInsets.symmetric(vertical: 10),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
    );

class _EmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final IconData actionIcon;
  final VoidCallback onAction;
  final bool isDark;

  const _EmptyState({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.actionIcon,
    required this.onAction,
    required this.isDark,
  });

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) => SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: constraints.maxHeight),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(icon, size: 44, color: isDark ? Colors.white38 : Colors.black38),
                  const SizedBox(height: 10),
                  Text(title,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                      textAlign: TextAlign.center),
                  const SizedBox(height: 4),
                  Text(message,
                      style: TextStyle(fontSize: 12, color: _muted(isDark)), textAlign: TextAlign.center),
                  const SizedBox(height: 14),
                  FilledButton.icon(
                    style: FilledButton.styleFrom(visualDensity: VisualDensity.compact),
                    onPressed: onAction,
                    icon: Icon(actionIcon, size: 16),
                    label: Text(actionLabel, style: const TextStyle(fontSize: 12)),
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

class _SheetHeader extends StatelessWidget {
  final Widget avatar;
  final String title;
  final String subtitle;
  const _SheetHeader({required this.avatar, required this.title, required this.subtitle});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Center(
          child: Container(
            width: 32,
            height: 4,
            margin: const EdgeInsets.only(bottom: 10),
            decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
          ),
        ),
        Row(
          children: [
            avatar,
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold)),
                  Text(subtitle, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              visualDensity: VisualDensity.compact,
              icon: const Icon(Icons.close, size: 20),
              onPressed: () => Navigator.pop(context),
            ),
          ],
        ),
        const Divider(height: 16),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Dashboard
// ─────────────────────────────────────────────────────────────

class AdminDashboardScreen extends ConsumerStatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  ConsumerState<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends ConsumerState<AdminDashboardScreen> with SingleTickerProviderStateMixin {
  final AdminService _adminService = AdminService();
  late TabController _tabController;
  final GlobalKey<_AdminUsersTabState> _usersTabKey = GlobalKey<_AdminUsersTabState>();
  final GlobalKey<_AdminPlaylistsTabState> _playlistsTabKey = GlobalKey<_AdminPlaylistsTabState>();

  AdminStatsData? _stats;
  bool _isLoadingStats = true;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _loadStats();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  String _formatSyncDate(DateTime? dt) {
    if (dt == null) {
      final stored = StorageService.getAdminLastSyncedAt();
      if (stored != null) dt = DateTime.tryParse(stored);
    }
    if (dt == null) return 'Never synced';

    final now = DateTime.now();
    final diff = now.difference(dt);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (diff.inDays == 0 && now.day == dt.day) {
      return 'Today, $timeStr';
    } else if (diff.inDays <= 1 && (now.day - dt.day == 1 || now.day - dt.day < 0)) {
      return 'Yesterday, $timeStr';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]}, $timeStr';
    }
  }

  Future<void> _loadStats({bool forceRefresh = false}) async {
    // 1. If not forcing refresh, immediately check local cache
    if (!forceRefresh) {
      final cachedJson = StorageService.getAdminCachedStatsJson();
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final decoded = jsonDecode(cachedJson) as Map<String, dynamic>;
          final cachedStats = AdminStatsData.fromJson(decoded);
          if (mounted) {
            setState(() {
              _stats = cachedStats;
              _isLoadingStats = false;
            });
          }
          return;
        } catch (_) {}
      }
    }

    setState(() => _isLoadingStats = true);

    // Auto-heal: Ensure current user document & playlists exist in Firestore
    final user = AuthService.instance.currentFirebaseUser ?? FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await UserService().syncUserOnLogin(user);
        if (!AuthService.instance.isGuest) {
          await AuthService.instance.backupUserPlaylists();
        }
        await StatsService.instance.forceSyncCurrentPlayCount();
      } catch (e) {
        debugPrint('Admin loadStats self-heal notice: $e');
      }
    }

    final data = await _adminService.getDashboardStats(forceRefresh: forceRefresh);
    try {
      await StorageService.saveAdminCachedStatsJson(jsonEncode(data.toJson()));
      await StorageService.setAdminLastSyncedAt(DateTime.now().toIso8601String());
    } catch (_) {}

    if (mounted) {
      setState(() {
        _stats = data;
        _isLoadingStats = false;
      });
    }
  }

  Future<void> _syncAll() async {
    final isOffline = await AppConnectivity.isOffline();
    if (isOffline) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot sync in offline mode. Please connect to the internet.'),
            duration: Duration(seconds: 2),
          ),
        );
      }
      return;
    }
    _loadStats(forceRefresh: true);
    _usersTabKey.currentState?.loadUsers(force: true);
    _playlistsTabKey.currentState?.loadPlaylists(force: true);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Syncing live data from Cloud Firestore...'),
        duration: Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isAdmin = ref.watch(isAdminProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ref.watch(customizationProvider).accentColor;

    // Security Gate in UI
    if (!isAdmin) {
      return Scaffold(
        appBar: AppBar(title: const Text('Admin Portal')),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: const [
                Icon(Icons.security_rounded, size: 48, color: Colors.red),
                SizedBox(height: 10),
                Text('Access Denied', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                SizedBox(height: 6),
                Text(
                  'This section is restricted to the verified admin email address.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0C) : const Color(0xFFFAF8F5),
      appBar: AppBar(
        toolbarHeight: 48,
        titleSpacing: 0,
        title: const Text(
          'Admin Portal',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold, fontSize: 18),
        ),
        actions: [
          IconButton(
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.sync_rounded, size: 22),
            tooltip: 'Sync Database',
            onPressed: _syncAll,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accent,
          labelColor: accent,
          unselectedLabelColor: Colors.grey,
          labelPadding: const EdgeInsets.symmetric(horizontal: 8),
          labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          tabs: const [
            _CompactTab(icon: Icons.dashboard_outlined, label: 'Overview'),
            _CompactTab(icon: Icons.people_outline, label: 'Users'),
            _CompactTab(icon: Icons.queue_music_outlined, label: 'Playlists'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildOverviewTab(isDark, accent),
          _AdminUsersTab(key: _usersTabKey, adminService: _adminService),
          _AdminPlaylistsTab(key: _playlistsTabKey, adminService: _adminService),
        ],
      ),
    );
  }

  Widget _buildSyncBanner(bool isDark, Color accent) {
    final syncedAt = _stats?.syncedAt ??
        (StorageService.getAdminLastSyncedAt() != null
            ? DateTime.tryParse(StorageService.getAdminLastSyncedAt()!)
            : null);

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.only(left: 10, right: 2),
      decoration: _cardDeco(isDark, radius: 12, border: accent.withValues(alpha: 0.3)),
      child: Row(
        children: [
          Icon(Icons.cloud_done_rounded, color: accent, size: 15),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Data as of ${_formatSyncDate(syncedAt)} · cached',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 11.5),
            ),
          ),
          TextButton.icon(
            style: TextButton.styleFrom(
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              minimumSize: const Size(0, 32),
            ),
            onPressed: _syncAll,
            icon: const Icon(Icons.sync_rounded, size: 14),
            label: const Text('Sync', style: TextStyle(fontSize: 11.5)),
          ),
        ],
      ),
    );
  }

  Widget _buildDatabaseCapacityCard(AdminStatsData stats, bool isDark, Color accent) {
    final usedMB = stats.storageUsedMB;
    final leftMB = stats.storageLeftMB;
    final percent = stats.percentStorageUsed;
    final remainingPl = stats.estimatedPlaylistsRemaining;

    Color progressColor = Colors.teal;
    if (percent > 80) {
      progressColor = Colors.red;
    } else if (percent > 50) {
      progressColor = Colors.orange;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      padding: const EdgeInsets.all(12),
      decoration: _cardDeco(isDark),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              _iconDot(Icons.storage_rounded, Colors.blue),
              const SizedBox(width: 8),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('DATABASE CAPACITY',
                        style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, letterSpacing: 1)),
                    Text('Cloud Firestore · Spark Free Tier', style: TextStyle(fontSize: 10, color: Colors.grey)),
                  ],
                ),
              ),
              _badge('1 GB FREE', Colors.green),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${usedMB.toStringAsFixed(2)} MB',
                    style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  TextSpan(
                    text: '  used · ${percent.toStringAsFixed(2)}%',
                    style: TextStyle(fontSize: 10.5, color: _muted(isDark)),
                  ),
                ]),
              ),
              Text.rich(
                TextSpan(children: [
                  TextSpan(
                    text: '${leftMB.toStringAsFixed(2)} MB',
                    style: const TextStyle(
                        fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'Outfit', color: Colors.teal),
                  ),
                  TextSpan(text: '  left', style: TextStyle(fontSize: 10.5, color: _muted(isDark))),
                ]),
              ),
            ],
          ),
          const SizedBox(height: 8),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.005, 1.0),
              minHeight: 6,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.auto_graph_rounded, color: Colors.amber, size: 15),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  '~5.2 KB/playlist → room for ~$remainingPl more playlists · Limits: 50K reads / 20K writes per day',
                  style: TextStyle(fontSize: 10.5, color: _muted(isDark), height: 1.3),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildStatTile(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: _cardDeco(isDark, radius: 12),
      child: Row(
        children: [
          _iconDot(icon, color, size: 28, iconSize: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit', height: 1.1),
                ),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: _muted(isDark)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNewUsersChart(AdminStatsData stats, bool isDark, Color accent) {
    final values = stats.usersJoinedLast7Days.values;
    final maxY = (values.fold<int>(0, (m, v) => v > m ? v : m) + 2).toDouble();

    return Container(
      height: 150,
      padding: const EdgeInsets.fromLTRB(8, 12, 12, 6),
      decoration: _cardDeco(isDark),
      child: stats.usersJoinedLast7Days.isEmpty
          ? const Center(child: Text('No recent registrations', style: TextStyle(fontSize: 12)))
          : BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: maxY,
                barTouchData: BarTouchData(enabled: true),
                titlesData: FlTitlesData(
                  leftTitles: const AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 22,
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 20,
                      getTitlesWidget: (value, meta) {
                        final keys = stats.usersJoinedLast7Days.keys.toList();
                        final idx = value.toInt();
                        if (idx >= 0 && idx < keys.length) {
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(keys[idx], style: const TextStyle(fontSize: 9)),
                          );
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                ),
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                barGroups: stats.usersJoinedLast7Days.entries.toList().asMap().entries.map((entry) {
                  return BarChartGroupData(
                    x: entry.key,
                    barRods: [
                      BarChartRodData(
                        toY: entry.value.value.toDouble(),
                        color: accent,
                        width: 10,
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ],
                  );
                }).toList(),
              ),
            ),
    );
  }

  Widget _buildCompositionChart(AdminStatsData stats, bool isDark) {
    return Container(
      height: 110,
      padding: const EdgeInsets.all(10),
      decoration: _cardDeco(isDark),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: PieChart(
              PieChartData(
                sectionsSpace: 2,
                centerSpaceRadius: 20,
                sections: [
                  PieChartSectionData(
                    value: stats.registeredUsers.toDouble().clamp(0.1, 999999),
                    title: '${stats.registeredUsers}',
                    color: Colors.blue,
                    radius: 24,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  PieChartSectionData(
                    value: stats.guestUsers.toDouble().clamp(0.1, 999999),
                    title: '${stats.guestUsers}',
                    color: Colors.amber,
                    radius: 24,
                    titleStyle: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.black),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildLegendItem(Colors.blue, 'Registered (${stats.registeredUsers})'),
                const SizedBox(height: 6),
                _buildLegendItem(Colors.amber, 'Guests (${stats.guestUsers})'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewTab(bool isDark, Color accent) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = _stats;
    if (stats == null) {
      return const Center(child: Text('Unable to load aggregate analytics.'));
    }

    final tiles = <Widget>[
      _buildStatTile('Registered', stats.registeredUsers.toString(), Icons.person, Colors.blue, isDark),
      _buildStatTile('Guests', stats.guestUsers.toString(), Icons.person_outline, Colors.amber, isDark),
      _buildStatTile('Total Logins', stats.totalLogins.toString(), Icons.login, Colors.green, isDark),
      _buildStatTile('Total Users', (stats.registeredUsers + stats.guestUsers).toString(), Icons.groups, Colors.indigo, isDark),
      _buildStatTile('Playlists', stats.totalPlaylists.toString(), Icons.library_music, Colors.purple, isDark),
      _buildStatTile('Public', stats.publicPlaylists.toString(), Icons.public, Colors.teal, isDark),
      _buildStatTile('Collab', stats.collabPlaylists.toString(), Icons.group_work, Colors.orange, isDark),
      _buildStatTile('Songs Played', stats.totalSongsListened.toString(), Icons.headphones, accent, isDark),
    ];

    return RefreshIndicator(
      onRefresh: () async {
        final isOffline = await AppConnectivity.isOffline();
        if (isOffline) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Cannot sync in offline mode. Please connect to the internet.'),
                duration: Duration(seconds: 2),
              ),
            );
          }
          return;
        }
        await _loadStats(forceRefresh: true);
      },
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 650;

          final newUsers = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('NEW USERS · LAST 7 DAYS', isDark),
              _buildNewUsersChart(stats, isDark, accent),
            ],
          );
          final composition = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionLabel('USER COMPOSITION', isDark),
              _buildCompositionChart(stats, isDark),
            ],
          );

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSyncBanner(isDark, accent),
                _buildDatabaseCapacityCard(stats, isDark, accent),
                _sectionLabel('AGGREGATE METRICS', isDark),
                GridView.count(
                  crossAxisCount: isWide ? 4 : 2,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  childAspectRatio: isWide ? 3.2 : 2.6,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: tiles,
                ),
                const SizedBox(height: 16),
                if (isWide)
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(flex: 3, child: newUsers),
                      const SizedBox(width: 12),
                      Expanded(flex: 2, child: composition),
                    ],
                  )
                else ...[
                  newUsers,
                  const SizedBox(height: 14),
                  composition,
                ],
                const SizedBox(height: 8),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 6),
        Flexible(
          child: Text(label,
              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w500)),
        ),
      ],
    );
  }
}

/// Icon + label laid out horizontally to keep the tab bar short.
class _CompactTab extends StatelessWidget implements PreferredSizeWidget {
  final IconData icon;
  final String label;
  const _CompactTab({required this.icon, required this.label});

  @override
  Size get preferredSize => const Size.fromHeight(36);

  @override
  Widget build(BuildContext context) {
    return Tab(
      height: 36,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16),
          const SizedBox(width: 6),
          Text(label),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Users tab
// ─────────────────────────────────────────────────────────────

/// Admin Users Management Tab
class _AdminUsersTab extends StatefulWidget {
  final AdminService adminService;
  const _AdminUsersTab({super.key, required this.adminService});

  @override
  State<_AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<_AdminUsersTab> {
  final List<AppUser> _users = [];
  Set<String> _blockedUids = {};
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadUsers();
  }

  Future<void> loadUsers({bool force = false}) async {
    // 1. Try local cache if not forcing refresh
    if (!force && _users.isEmpty) {
      final cachedJson = StorageService.getAdminCachedUsersJson();
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final listRaw = jsonDecode(cachedJson) as List<dynamic>;
          final parsed = listRaw.map((e) => AppUser.fromMap(Map<String, dynamic>.from(e))).toList();
          if (mounted && parsed.isNotEmpty) {
            setState(() {
              _users.clear();
              _users.addAll(parsed);
              _isLoading = false;
            });
          }
        } catch (_) {}
      }
    }

    if (_users.isEmpty || force) {
      setState(() => _isLoading = true);
    }

    // Auto-heal current admin user
    final user = AuthService.instance.currentFirebaseUser ?? FirebaseAuth.instance.currentUser;
    if (user != null) {
      try {
        await UserService().syncUserOnLogin(user);
      } catch (e) {
        debugPrint('Admin loadUsers sync notice: $e');
      }
    }

    try {
      final blocked = await widget.adminService.getBlockedUserIds();
      final list = await widget.adminService.getPaginatedUsers();

      if (mounted) {
        setState(() {
          _blockedUids = blocked;
          _users.clear();
          _users.addAll(list);
          _isLoading = false;
        });

        // Save to cache
        try {
          final jsonStr = jsonEncode(_users.map((u) => u.toMap()).toList());
          await StorageService.saveAdminCachedUsersJson(jsonStr);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Admin loadUsers error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleBlock(AppUser user) async {
    final isThisAdmin = isConfiguredAdminEmail(user.email) ||
        user.email?.trim().toLowerCase() == kAdminEmail.trim().toLowerCase();

    if (isThisAdmin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('The administrator account is protected and cannot be blocked.'),
          backgroundColor: Colors.amber,
        ),
      );
      return;
    }

    final isBlocked = _blockedUids.contains(user.uid) || await widget.adminService.isUserBlocked(user.uid);
    if (!mounted) return;

    if (isBlocked) {
      await widget.adminService.unblockUser(user.uid);
      if (mounted) {
        setState(() => _blockedUids.remove(user.uid));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Unblocked ${user.displayName} (UID: ${user.uid.substring(0, 6)}...)')),
        );
      }
    } else {
      final reasonController = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Block ${user.displayName}?', style: const TextStyle(fontSize: 16)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Blocked users will be denied all read/write permissions via Firestore security rules.',
                style: TextStyle(fontSize: 13),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason for block (optional)', isDense: true),
              ),
            ],
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('Block User'),
            ),
          ],
        ),
      );

      if (confirm == true) {
        await widget.adminService.blockUser(user.uid, reasonController.text);
        if (mounted) {
          setState(() => _blockedUids.add(user.uid));
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Blocked ${user.displayName}')),
          );
        }
      }
    }
  }

  void _showUserPlaylists(BuildContext context, AppUser user) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _UserPlaylistsModal(user: user, adminService: widget.adminService),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading && _users.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _users.where((u) {
      final q = _searchQuery.toLowerCase();
      return u.displayName.toLowerCase().contains(q) || (u.email?.toLowerCase().contains(q) ?? false);
    }).toList();

    return RefreshIndicator(
      onRefresh: () => loadUsers(force: true),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              style: const TextStyle(fontSize: 13),
              decoration: _searchDeco('Search by name or email...'),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    isDark: isDark,
                    icon: Icons.people_outline_rounded,
                    title: _searchQuery.isNotEmpty ? 'No users matching "$_searchQuery"' : 'No Users Found in Firestore',
                    message: _searchQuery.isNotEmpty
                        ? 'Try a different name or email.'
                        : 'No user accounts found. Tap below to sync cloud records.',
                    actionLabel: 'Sync & Refresh Users',
                    actionIcon: Icons.sync_rounded,
                    onAction: () => loadUsers(force: true),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, idx) {
                      final user = filtered[idx];
                      final isThisAdmin = isConfiguredAdminEmail(user.email) ||
                          user.email?.trim().toLowerCase() == kAdminEmail.trim().toLowerCase();
                      final isBlocked = _blockedUids.contains(user.uid);

                      Color avatarColor = Colors.blue;
                      if (isThisAdmin) {
                        avatarColor = Colors.amber;
                      } else if (isBlocked) {
                        avatarColor = Colors.red;
                      } else if (user.isGuest) {
                        avatarColor = Colors.orange;
                      }

                      final emailText = user.email != null && user.email!.isNotEmpty
                          ? user.email!
                          : (user.isGuest ? 'Guest Listener' : 'No Email');

                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: _surface(isDark),
                        shape: _cardShape(isDark),
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -2),
                          minVerticalPadding: 4,
                          contentPadding: const EdgeInsets.only(left: 10, right: 0),
                          onTap: () => _showUserPlaylists(context, user),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: avatarColor,
                            child: Icon(
                              isThisAdmin
                                  ? Icons.star_rounded
                                  : (isBlocked
                                      ? Icons.block_rounded
                                      : (user.isGuest ? Icons.person_outline : Icons.person)),
                              color: Colors.white,
                              size: 16,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isThisAdmin) ...[
                                const SizedBox(width: 5),
                                _badge('👑 ADMIN', Colors.amber),
                              ],
                              if (isBlocked) ...[
                                const SizedBox(width: 5),
                                _badge('⛔ BLOCKED', Colors.red),
                              ],
                            ],
                          ),
                          subtitle: Text(
                            '$emailText · ${user.loginCount} logins · ${user.stats.totalSongsPlayed} plays',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: _muted(isDark)),
                          ),
                          trailing: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onSelected: (val) {
                              if (val == 'block') _toggleBlock(user);
                              if (val == 'playlists') _showUserPlaylists(context, user);
                            },
                            itemBuilder: (ctx) => [
                              const PopupMenuItem(
                                value: 'playlists',
                                height: 38,
                                child: Row(
                                  children: [
                                    Icon(Icons.queue_music_rounded, size: 16),
                                    SizedBox(width: 8),
                                    Text('View Playlists', style: TextStyle(fontSize: 13)),
                                  ],
                                ),
                              ),
                              if (!isThisAdmin)
                                PopupMenuItem(
                                  value: 'block',
                                  height: 38,
                                  child: Row(
                                    children: [
                                      Icon(
                                        isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                                        size: 16,
                                        color: isBlocked ? Colors.green : Colors.red,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        isBlocked ? 'Unblock User' : 'Block User',
                                        style: TextStyle(fontSize: 13, color: isBlocked ? Colors.green : Colors.red),
                                      ),
                                    ],
                                  ),
                                )
                              else
                                const PopupMenuItem(
                                  enabled: false,
                                  value: 'protected',
                                  height: 38,
                                  child: Row(
                                    children: [
                                      Icon(Icons.shield_rounded, size: 16, color: Colors.amber),
                                      SizedBox(width: 8),
                                      Text('Admin (Protected)', style: TextStyle(fontSize: 13)),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// User playlists modal
// ─────────────────────────────────────────────────────────────

/// Modal Sheet: Shows all playlists created by a specific user
class _UserPlaylistsModal extends StatefulWidget {
  final AppUser user;
  final AdminService adminService;
  const _UserPlaylistsModal({required this.user, required this.adminService});

  @override
  State<_UserPlaylistsModal> createState() => _UserPlaylistsModalState();
}

class _UserPlaylistsModalState extends State<_UserPlaylistsModal> {
  List<Playlist> _userPlaylists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    final list = await widget.adminService.getPlaylistsByOwner(widget.user.uid);
    if (mounted) {
      setState(() {
        _userPlaylists = list;
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final uid = widget.user.uid;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181818) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              avatar: CircleAvatar(
                radius: 16,
                backgroundColor: Colors.blue.withValues(alpha: 0.2),
                child: const Icon(Icons.person, color: Colors.blue, size: 16),
              ),
              title: '${widget.user.displayName}\'s Playlists',
              subtitle: 'UID: ${uid.substring(0, uid.length > 12 ? 12 : uid.length)}...',
            ),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _userPlaylists.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.queue_music_rounded, size: 40, color: isDark ? Colors.white38 : Colors.black38),
                              const SizedBox(height: 8),
                              const Text('No Playlists Found',
                                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              const SizedBox(height: 2),
                              Text('This user has not created or backed up playlists.',
                                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _userPlaylists.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 6),
                          itemBuilder: (ctx, idx) {
                            final p = _userPlaylists[idx];
                            return Card(
                              margin: EdgeInsets.zero,
                              elevation: 0,
                              color: _surface(isDark),
                              shape: _cardShape(isDark),
                              child: ListTile(
                                dense: true,
                                visualDensity: const VisualDensity(vertical: -2),
                                minVerticalPadding: 4,
                                contentPadding: const EdgeInsets.only(left: 10, right: 4),
                                leading: CircleAvatar(
                                  radius: 14,
                                  backgroundColor: p.isPublic ? Colors.teal : Colors.purple,
                                  child: Icon(p.isPublic ? Icons.public : Icons.lock_outline,
                                      color: Colors.white, size: 14),
                                ),
                                title: Text(p.name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                                subtitle: Text(
                                  '${p.trackCount} tracks · ${p.collabEnabled ? "👥 Collab" : "Solo"} · ${p.isPublic ? "🌐 Public" : "🔒 Private"}',
                                  style: const TextStyle(fontSize: 11),
                                ),
                                trailing: TextButton.icon(
                                  style: TextButton.styleFrom(
                                    visualDensity: VisualDensity.compact,
                                    padding: const EdgeInsets.symmetric(horizontal: 8),
                                  ),
                                  icon: const Icon(Icons.library_music_rounded, size: 14),
                                  label: const Text('Tracks', style: TextStyle(fontSize: 11)),
                                  onPressed: () {
                                    showModalBottomSheet(
                                      context: context,
                                      isScrollControlled: true,
                                      backgroundColor: Colors.transparent,
                                      builder: (c) => _PlaylistTracksModal(playlist: p),
                                    );
                                  },
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Playlists tab
// ─────────────────────────────────────────────────────────────

/// Admin Playlists Management Tab
class _AdminPlaylistsTab extends StatefulWidget {
  final AdminService adminService;
  const _AdminPlaylistsTab({super.key, required this.adminService});

  @override
  State<_AdminPlaylistsTab> createState() => _AdminPlaylistsTabState();
}

class _AdminPlaylistsTabState extends State<_AdminPlaylistsTab> {
  final List<Playlist> _playlists = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    loadPlaylists();
  }

  Future<void> loadPlaylists({bool force = false}) async {
    // 1. Try local cache if not forcing refresh
    if (!force && _playlists.isEmpty) {
      final cachedJson = StorageService.getAdminCachedPlaylistsJson();
      if (cachedJson != null && cachedJson.isNotEmpty) {
        try {
          final listRaw = jsonDecode(cachedJson) as List<dynamic>;
          final parsed = listRaw.map((e) => Playlist.fromMap(Map<String, dynamic>.from(e))).toList();
          if (mounted && parsed.isNotEmpty) {
            setState(() {
              _playlists.clear();
              _playlists.addAll(parsed);
              _isLoading = false;
            });
          }
        } catch (_) {}
      }
    }

    if (_playlists.isEmpty || force) {
      setState(() => _isLoading = true);
    }

    // Auto-heal local playlists backup
    final user = AuthService.instance.currentFirebaseUser ?? FirebaseAuth.instance.currentUser;
    if (user != null && !AuthService.instance.isGuest) {
      try {
        await AuthService.instance.backupUserPlaylists();
      } catch (e) {
        debugPrint('Admin loadPlaylists backup notice: $e');
      }
    }

    try {
      final list = await widget.adminService.getPaginatedPlaylists();
      if (mounted) {
        setState(() {
          _playlists.clear();
          _playlists.addAll(list);
          _isLoading = false;
        });

        // Save to cache
        try {
          final jsonStr = jsonEncode(_playlists.map((p) => p.toMap()).toList());
          await StorageService.saveAdminCachedPlaylistsJson(jsonStr);
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('Admin loadPlaylists error: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _toggleVisibility(Playlist p) async {
    final nextPublic = !p.isPublic;
    await widget.adminService.forceSetVisibility(p.id, nextPublic);

    if (mounted) {
      setState(() {
        final idx = _playlists.indexWhere((item) => item.id == p.id);
        if (idx != -1) {
          _playlists[idx] = p.copyWith(visibility: nextPublic ? 'public' : 'private');
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"${p.name}" is now ${nextPublic ? "Public 🌐" : "Private 🔒"}')),
      );
      _persistCache();
    }
  }

  Future<void> _toggleCollab(Playlist p) async {
    final nextCollab = !p.collabEnabled;
    await widget.adminService.forceSetCollab(p.id, nextCollab);

    if (mounted) {
      setState(() {
        final idx = _playlists.indexWhere((item) => item.id == p.id);
        if (idx != -1) {
          _playlists[idx] = p.copyWith(collabEnabled: nextCollab);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Collaboration ${nextCollab ? "enabled 👥" : "disabled 👤"} for "${p.name}"')),
      );
      _persistCache();
    }
  }

  Future<void> _deletePlaylist(Playlist p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?', style: const TextStyle(fontSize: 16)),
        content: Text(
          'This will delete the playlist document from Firestore permanently. ID: ${p.id}',
          style: const TextStyle(fontSize: 13),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete Playlist'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.adminService.forceDeletePlaylist(p.id);
      if (mounted) {
        setState(() => _playlists.removeWhere((item) => item.id == p.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Deleted playlist "${p.name}"')),
        );
        _persistCache();
      }
    }
  }

  void _showShareCodeDialog(Playlist p) {
    final code = p.shareCode ?? p.id;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.qr_code_rounded, color: Colors.teal, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text('Share Code: ${p.name}',
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 15)),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Users can import or join this playlist with this code:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 15),
            label: const Text('Copy Code'),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: code));
              Navigator.pop(ctx);
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text('Copied code to clipboard: $code')),
              );
            },
          ),
        ],
      ),
    );
  }

  void _showTracksModal(Playlist p) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => _PlaylistTracksModal(playlist: p),
    );
  }

  Future<void> _persistCache() async {
    try {
      final jsonStr = jsonEncode(_playlists.map((p) => p.toMap()).toList());
      await StorageService.saveAdminCachedPlaylistsJson(jsonStr);
    } catch (_) {}
  }

  PopupMenuItem<String> _menuItem(String value, IconData icon, String label, {Color? color}) {
    return PopupMenuItem(
      value: value,
      height: 38,
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Text(label, style: TextStyle(fontSize: 13, color: color)),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isLoading && _playlists.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }

    final filtered = _playlists.where((p) {
      final q = _searchQuery.toLowerCase();
      final nameMatches = p.name.toLowerCase().contains(q);
      final ownerMatches = p.ownerName.toLowerCase().contains(q);
      final codeMatches = (p.shareCode?.toLowerCase() ?? '').contains(q);
      return nameMatches || ownerMatches || codeMatches;
    }).toList();

    return RefreshIndicator(
      onRefresh: () => loadPlaylists(force: true),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
            child: TextField(
              style: const TextStyle(fontSize: 13),
              decoration: _searchDeco('Search by name, owner, or share code...'),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? _EmptyState(
                    isDark: isDark,
                    icon: Icons.queue_music_rounded,
                    title: _searchQuery.isNotEmpty
                        ? 'No playlists matching "$_searchQuery"'
                        : 'No Playlists Found in Firestore',
                    message: _searchQuery.isNotEmpty
                        ? 'Try a different keyword.'
                        : 'Playlists backed up to Cloud Firestore will appear here. Tap below to push local playlists.',
                    actionLabel: 'Push Local Playlists & Refresh',
                    actionIcon: Icons.cloud_upload_rounded,
                    onAction: () => loadPlaylists(force: true),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 6),
                    itemBuilder: (context, idx) {
                      final p = filtered[idx];
                      final tone = p.isPublic ? Colors.teal : Colors.purple;

                      return Card(
                        margin: EdgeInsets.zero,
                        elevation: 0,
                        color: _surface(isDark),
                        shape: _cardShape(isDark),
                        child: ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -2),
                          minVerticalPadding: 4,
                          contentPadding: const EdgeInsets.only(left: 10, right: 0),
                          onTap: () => _showTracksModal(p),
                          leading: CircleAvatar(
                            radius: 16,
                            backgroundColor: tone,
                            child: Icon(p.isPublic ? Icons.public : Icons.lock_outline,
                                color: Colors.white, size: 16),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(p.name,
                                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                    overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 5),
                              _badge(p.isPublic ? '🌐 Public' : '🔒 Private', tone),
                            ],
                          ),
                          subtitle: Text(
                            '${p.ownerName} · ${p.trackCount} tracks · ${p.collabEnabled ? "👥 Collab" : "👤 Solo"}'
                            '${p.shareCode != null ? " · ${p.shareCode}" : ""}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(fontSize: 11, color: _muted(isDark)),
                          ),
                          trailing: PopupMenuButton<String>(
                            padding: EdgeInsets.zero,
                            iconSize: 20,
                            onSelected: (val) {
                              if (val == 'tracks') _showTracksModal(p);
                              if (val == 'visibility') _toggleVisibility(p);
                              if (val == 'collab') _toggleCollab(p);
                              if (val == 'code') _showShareCodeDialog(p);
                              if (val == 'delete') _deletePlaylist(p);
                            },
                            itemBuilder: (ctx) => [
                              _menuItem('tracks', Icons.queue_music_rounded, 'View Tracks'),
                              _menuItem(
                                'visibility',
                                p.isPublic ? Icons.lock_outline : Icons.public,
                                p.isPublic ? 'Make Private' : 'Make Public',
                              ),
                              _menuItem(
                                'collab',
                                p.collabEnabled ? Icons.person : Icons.group_work_rounded,
                                p.collabEnabled ? 'Disable Collaboration' : 'Enable Collaboration',
                              ),
                              _menuItem('code', Icons.qr_code_rounded, 'Show Share Code'),
                              _menuItem('delete', Icons.delete_rounded, 'Delete Playlist', color: Colors.red),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Tracks modal
// ─────────────────────────────────────────────────────────────

/// Modal Sheet: Displays all tracks inside a playlist
class _PlaylistTracksModal extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTracksModal({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracks = playlist.tracks;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181818) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _SheetHeader(
              avatar: CircleAvatar(
                radius: 16,
                backgroundColor: playlist.isPublic ? Colors.teal : Colors.purple,
                child: Icon(playlist.isPublic ? Icons.public : Icons.lock_outline, color: Colors.white, size: 16),
              ),
              title: playlist.name,
              subtitle: 'Owner: ${playlist.ownerName} · ${tracks.length} track(s)',
            ),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_note_rounded, size: 40, color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(height: 8),
                          const Text('No Tracks in this Playlist',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                          const SizedBox(height: 2),
                          Text('This playlist does not have any song tracks yet.',
                              style: TextStyle(fontSize: 11, color: Colors.grey[500])),
                        ],
                      ),
                    )
                  : ListView.separated(
                      controller: scrollController,
                      itemCount: tracks.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (ctx, idx) {
                        final t = tracks[idx];
                        final sec = t.durationMs > 0 ? t.durationMs ~/ 1000 : 0;
                        final durationStr =
                            sec > 0 ? '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}' : '--:--';

                        return ListTile(
                          dense: true,
                          visualDensity: const VisualDensity(vertical: -3),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 2),
                          leading: SizedBox(
                            width: 22,
                            child: Text(
                              '${idx + 1}',
                              textAlign: TextAlign.center,
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11, color: _muted(isDark)),
                            ),
                          ),
                          title: Text(t.title,
                              maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 13)),
                          subtitle: Text(t.artist,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 11, color: Colors.grey)),
                          trailing: Text(durationStr, style: const TextStyle(fontSize: 10.5, color: Colors.grey)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}