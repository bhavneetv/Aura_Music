import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
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
    if (dt == null) return 'Never Synced';

    final now = DateTime.now();
    final diff = now.difference(dt);
    final hour = dt.hour.toString().padLeft(2, '0');
    final minute = dt.minute.toString().padLeft(2, '0');
    final timeStr = '$hour:$minute';

    if (diff.inDays == 0 && now.day == dt.day) {
      return 'Today at $timeStr';
    } else if (diff.inDays <= 1 && (now.day - dt.day == 1 || now.day - dt.day < 0)) {
      return 'Yesterday at $timeStr';
    } else {
      const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
      return '${dt.day} ${months[dt.month - 1]} at $timeStr';
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
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.security_rounded, size: 64, color: Colors.red),
              const SizedBox(height: 16),
              const Text(
                'Access Denied',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 8),
              const Text(
                'This section is restricted to the verified admin email address.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0C0C0C) : const Color(0xFFFAF8F5),
      appBar: AppBar(
        title: const Text(
          'Admin Portal',
          style: TextStyle(fontFamily: 'Outfit', fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.sync_rounded),
            tooltip: 'Sync Database',
            onPressed: () {
              _loadStats(forceRefresh: true);
              _usersTabKey.currentState?.loadUsers(force: true);
              _playlistsTabKey.currentState?.loadPlaylists(force: true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('Syncing live data from Cloud Firestore...'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: accent,
          labelColor: accent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.dashboard_outlined), text: 'Overview'),
            Tab(icon: Icon(Icons.people_outline), text: 'Users'),
            Tab(icon: Icon(Icons.queue_music_outlined), text: 'Playlists'),
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
    final syncDateStr = _formatSyncDate(syncedAt);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: accent.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.cloud_done_rounded, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Data as of: $syncDateStr',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                Text(
                  'Offline cache active. Tap sync to fetch fresh Firestore data.',
                  style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                ),
              ],
            ),
          ),
          FilledButton.tonalIcon(
            style: FilledButton.styleFrom(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              visualDensity: VisualDensity.compact,
            ),
            onPressed: () {
              _loadStats(forceRefresh: true);
              _usersTabKey.currentState?.loadUsers(force: true);
              _playlistsTabKey.currentState?.loadPlaylists(force: true);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Syncing database...'), duration: Duration(seconds: 2)),
              );
            },
            icon: const Icon(Icons.sync_rounded, size: 15),
            label: const Text('Sync', style: TextStyle(fontSize: 12)),
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
      margin: const EdgeInsets.only(bottom: 22),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white12 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: Colors.blue.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.storage_rounded, color: Colors.blue, size: 18),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'DATABASE CAPACITY & QUOTA',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2),
                    ),
                    Text(
                      'Cloud Firestore (Spark Free Tier)',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                decoration: BoxDecoration(
                  color: Colors.green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Text(
                  '1.0 GB FREE',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.green),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Numbers
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${usedMB.toStringAsFixed(2)} MB Used',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
                  ),
                  Text(
                    'of 1,024 MB (${percent.toStringAsFixed(2)}%)',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '${leftMB.toStringAsFixed(2)} MB Left',
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold, fontFamily: 'Outfit', color: Colors.teal),
                  ),
                  Text(
                    'Free Space Remaining',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Progress bar
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: (percent / 100).clamp(0.005, 1.0),
              minHeight: 8,
              backgroundColor: isDark ? Colors.white10 : Colors.black12,
              valueColor: AlwaysStoppedAnimation<Color>(progressColor),
            ),
          ),
          const SizedBox(height: 14),

          // Playlist Probability / Capacity Forecast Box
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: isDark ? Colors.white.withValues(alpha: 0.04) : Colors.black.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.auto_graph_rounded, color: Colors.amber, size: 20),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Playlist Capacity Forecast',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'At ~5.2 KB per playlist, your database can hold ~$remainingPl more playlists before reaching the 1 GB free limit.',
                        style: TextStyle(fontSize: 11, color: isDark ? Colors.white70 : Colors.black87),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Spark Limits: 50,000 reads/day • 20,000 writes/day',
                        style: TextStyle(fontSize: 10, color: isDark ? Colors.white54 : Colors.black54),
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

  Widget _buildOverviewTab(bool isDark, Color accent) {
    if (_isLoadingStats) {
      return const Center(child: CircularProgressIndicator());
    }

    final stats = _stats;
    if (stats == null) {
      return const Center(child: Text('Unable to load aggregate analytics.'));
    }

    return RefreshIndicator(
      onRefresh: () => _loadStats(forceRefresh: true),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final isTabletOrDesktop = constraints.maxWidth > 650;

          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildSyncBanner(isDark, accent),
                _buildDatabaseCapacityCard(stats, isDark, accent),

                Text(
                  'AGGREGATE METRICS',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),

                // Responsive Cards Grid
                GridView.count(
                  crossAxisCount: isTabletOrDesktop ? 4 : 2,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  children: [
                    _buildStatCard('Registered Users', stats.registeredUsers.toString(), Icons.person, Colors.blue, isDark),
                    _buildStatCard('Guest Accounts', stats.guestUsers.toString(), Icons.person_outline, Colors.amber, isDark),
                    _buildStatCard('Total Logins', stats.totalLogins.toString(), Icons.login, Colors.green, isDark),
                    _buildStatCard('Total Playlists', stats.totalPlaylists.toString(), Icons.library_music, Colors.purple, isDark),
                    _buildStatCard('Public Playlists', stats.publicPlaylists.toString(), Icons.public, Colors.teal, isDark),
                    _buildStatCard('Collab Playlists', stats.collabPlaylists.toString(), Icons.group_work, Colors.orange, isDark),
                    _buildStatCard('Songs Listened', stats.totalSongsListened.toString(), Icons.headphones, accent, isDark),
                    _buildStatCard('Total Users', (stats.registeredUsers + stats.guestUsers).toString(), Icons.groups, Colors.indigo, isDark),
                  ],
                ),

                const SizedBox(height: 28),

                // Chart: New Users Last 7 Days
                Text(
                  'NEW USERS (LAST 7 DAYS)',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 220,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  child: stats.usersJoinedLast7Days.isEmpty
                      ? const Center(child: Text('No recent registrations'))
                      : BarChart(
                          BarChartData(
                            alignment: BarChartAlignment.spaceAround,
                            maxY: (stats.usersJoinedLast7Days.values.fold(0, (max, v) => v > max ? v : max) + 2).toDouble(),
                            barTouchData: BarTouchData(enabled: true),
                            titlesData: FlTitlesData(
                              leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: true, reservedSize: 28)),
                              bottomTitles: AxisTitles(
                                sideTitles: SideTitles(
                                  showTitles: true,
                                  getTitlesWidget: (value, meta) {
                                    final keys = stats.usersJoinedLast7Days.keys.toList();
                                    final idx = value.toInt();
                                    if (idx >= 0 && idx < keys.length) {
                                      return Padding(
                                        padding: const EdgeInsets.only(top: 6),
                                        child: Text(keys[idx], style: const TextStyle(fontSize: 10)),
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
                                    width: 14,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                ],
                              );
                            }).toList(),
                          ),
                        ),
                ),

                const SizedBox(height: 24),

                // Breakdown: Guests vs Registered (Pie Chart)
                Text(
                  'USER COMPOSITION',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.5,
                    color: isDark ? Colors.white54 : Colors.black54,
                  ),
                ),
                const SizedBox(height: 12),
                Container(
                  height: 200,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF161616) : Colors.white,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: PieChart(
                          PieChartData(
                            sectionsSpace: 3,
                            centerSpaceRadius: 36,
                            sections: [
                              PieChartSectionData(
                                value: stats.registeredUsers.toDouble().clamp(0.1, 999999),
                                title: '${stats.registeredUsers}',
                                color: Colors.blue,
                                radius: 45,
                                titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.white),
                              ),
                              PieChartSectionData(
                                value: stats.guestUsers.toDouble().clamp(0.1, 999999),
                                title: '${stats.guestUsers}',
                                color: Colors.amber,
                                radius: 45,
                                titleStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.black),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _buildLegendItem(Colors.blue, 'Registered Users (${stats.registeredUsers})'),
                          const SizedBox(height: 8),
                          _buildLegendItem(Colors.amber, 'Guest Users (${stats.guestUsers})'),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color, bool isDark) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF161616) : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: isDark ? Colors.white10 : Colors.black12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 16),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
          ),
        ],
      ),
    );
  }

  Widget _buildLegendItem(Color color, String label) {
    return Row(
      children: [
        Container(width: 12, height: 12, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Text(label, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500)),
      ],
    );
  }
}

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
          title: Text('Block ${user.displayName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Blocked users will be denied all read/write permissions via Firestore security rules.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason for block (optional)'),
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
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by user name or email...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.people_outline_rounded, size: 64, color: isDark ? Colors.white38 : Colors.black38),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty ? 'No users matching "$_searchQuery"' : 'No Users Found in Firestore',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try searching with a different name or email.'
                                      : 'No user accounts found in Firestore. Tap below to sync cloud records.',
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () => loadUsers(force: true),
                                  icon: const Icon(Icons.sync_rounded, size: 18),
                                  label: const Text('Sync & Refresh Users'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
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

                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          onTap: () => _showUserPlaylists(context, user),
                          leading: CircleAvatar(
                            backgroundColor: avatarColor,
                            child: Icon(
                              isThisAdmin
                                  ? Icons.star_rounded
                                  : (isBlocked
                                      ? Icons.block_rounded
                                      : (user.isGuest ? Icons.person_outline : Icons.person)),
                              color: Colors.white,
                            ),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(
                                  user.displayName,
                                  style: const TextStyle(fontWeight: FontWeight.bold),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (isThisAdmin) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.amber.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.amber.withValues(alpha: 0.6)),
                                  ),
                                  child: const Text('👑 ADMIN', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber)),
                                ),
                              ],
                              if (isBlocked) ...[
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.red.withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(color: Colors.red.withValues(alpha: 0.6)),
                                  ),
                                  child: const Text('⛔ BLOCKED', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.red)),
                                ),
                              ],
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 3),
                              Text(
                                user.email != null && user.email!.isNotEmpty ? user.email! : (user.isGuest ? 'Guest Listener' : 'No Email'),
                                style: const TextStyle(fontSize: 12),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                'Logins: ${user.loginCount} • Plays: ${user.stats.totalSongsPlayed}',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.playlist_play_rounded),
                                tooltip: 'View Playlists',
                                onPressed: () => _showUserPlaylists(context, user),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'block') _toggleBlock(user);
                                  if (val == 'playlists') _showUserPlaylists(context, user);
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'playlists',
                                    child: Row(
                                      children: [
                                        Icon(Icons.queue_music_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('View User Playlists'),
                                      ],
                                    ),
                                  ),
                                  if (!isThisAdmin)
                                    PopupMenuItem(
                                      value: 'block',
                                      child: Row(
                                        children: [
                                          Icon(
                                            isBlocked ? Icons.lock_open_rounded : Icons.block_rounded,
                                            size: 18,
                                            color: isBlocked ? Colors.green : Colors.red,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            isBlocked ? 'Unblock User' : 'Block User',
                                            style: TextStyle(color: isBlocked ? Colors.green : Colors.red),
                                          ),
                                        ],
                                      ),
                                    )
                                  else
                                    const PopupMenuItem(
                                      enabled: false,
                                      value: 'protected',
                                      child: Row(
                                        children: [
                                          Icon(Icons.shield_rounded, size: 18, color: Colors.amber),
                                          SizedBox(width: 8),
                                          Text('Admin (Protected)'),
                                        ],
                                      ),
                                    ),
                                ],
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

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181818) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.blue.withValues(alpha: 0.2),
                  child: const Icon(Icons.person, color: Colors.blue),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${widget.user.displayName}\'s Playlists',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      Text(
                        'UID: ${widget.user.uid.substring(0, widget.user.uid.length > 12 ? 12 : widget.user.uid.length)}...',
                        style: const TextStyle(fontSize: 11, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _userPlaylists.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.queue_music_rounded, size: 54, color: isDark ? Colors.white38 : Colors.black38),
                              const SizedBox(height: 12),
                              const Text('No Playlists Found', style: TextStyle(fontWeight: FontWeight.bold)),
                              const SizedBox(height: 4),
                              Text('This user has not created or backed up playlists.', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
                            ],
                          ),
                        )
                      : ListView.separated(
                          controller: scrollController,
                          itemCount: _userPlaylists.length,
                          separatorBuilder: (_, __) => const SizedBox(height: 8),
                          itemBuilder: (ctx, idx) {
                            final p = _userPlaylists[idx];
                            return Card(
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: p.isPublic ? Colors.teal : Colors.purple,
                                  child: Icon(p.isPublic ? Icons.public : Icons.lock_outline, color: Colors.white, size: 18),
                                ),
                                title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                subtitle: Text(
                                  'Tracks: ${p.trackCount} • ${p.collabEnabled ? "👥 Collab" : "Solo"} • ${p.isPublic ? "🌐 Public" : "🔒 Private"}',
                                  style: const TextStyle(fontSize: 12),
                                ),
                                trailing: TextButton.icon(
                                  icon: const Icon(Icons.library_music_rounded, size: 16),
                                  label: const Text('Tracks', style: TextStyle(fontSize: 12)),
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
        title: Text('Delete "${p.name}"?'),
        content: Text('This will delete the playlist document from Firestore permanently. ID: ${p.id}'),
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
            const Icon(Icons.qr_code_rounded, color: Colors.teal),
            const SizedBox(width: 8),
            Text('Share Code: ${p.name}', style: const TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Users can import or join this playlist with this code:'),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.teal.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.teal.withValues(alpha: 0.3)),
              ),
              child: SelectableText(
                code,
                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'monospace'),
                textAlign: TextAlign.center,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
          FilledButton.icon(
            icon: const Icon(Icons.copy_rounded, size: 16),
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
            padding: const EdgeInsets.all(12),
            child: TextField(
              decoration: InputDecoration(
                hintText: 'Search by playlist name, owner, or share code...',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
              ),
              onChanged: (val) => setState(() => _searchQuery = val),
            ),
          ),
          Expanded(
            child: filtered.isEmpty
                ? LayoutBuilder(
                    builder: (context, constraints) => SingleChildScrollView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: constraints.maxHeight),
                        child: Center(
                          child: Padding(
                            padding: const EdgeInsets.all(32),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.queue_music_rounded, size: 64, color: isDark ? Colors.white38 : Colors.black38),
                                const SizedBox(height: 16),
                                Text(
                                  _searchQuery.isNotEmpty ? 'No playlists matching "$_searchQuery"' : 'No Playlists Found in Firestore',
                                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  _searchQuery.isNotEmpty
                                      ? 'Try searching with a different keyword.'
                                      : 'Playlists created or backed up to Cloud Firestore will appear here. Tap below to push local playlists.',
                                  style: TextStyle(fontSize: 13, color: isDark ? Colors.white60 : Colors.black54),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 20),
                                FilledButton.icon(
                                  onPressed: () => loadPlaylists(force: true),
                                  icon: const Icon(Icons.cloud_upload_rounded, size: 18),
                                  label: const Text('Push Local Playlists & Refresh'),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 8),
                    itemBuilder: (context, idx) {
                      final p = filtered[idx];
                      return Card(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        child: ListTile(
                          onTap: () => _showTracksModal(p),
                          leading: CircleAvatar(
                            backgroundColor: p.isPublic ? Colors.teal : Colors.purple,
                            child: Icon(p.isPublic ? Icons.public : Icons.lock_outline, color: Colors.white),
                          ),
                          title: Row(
                            children: [
                              Flexible(
                                child: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold), overflow: TextOverflow.ellipsis),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: (p.isPublic ? Colors.teal : Colors.purple).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  p.isPublic ? '🌐 Public' : '🔒 Private',
                                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: p.isPublic ? Colors.teal : Colors.purple),
                                ),
                              ),
                            ],
                          ),
                          subtitle: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const SizedBox(height: 3),
                              Text('Owner: ${p.ownerName} • Tracks: ${p.trackCount}', style: const TextStyle(fontSize: 12)),
                              const SizedBox(height: 2),
                              Text(
                                '${p.collabEnabled ? "👥 Collaboration Active" : "👤 Solo Playlist"}${p.shareCode != null ? " • Code: ${p.shareCode}" : ""}',
                                style: TextStyle(fontSize: 11, color: isDark ? Colors.white60 : Colors.black54),
                              ),
                            ],
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.queue_music_rounded),
                                tooltip: 'View Tracks',
                                onPressed: () => _showTracksModal(p),
                              ),
                              PopupMenuButton<String>(
                                onSelected: (val) {
                                  if (val == 'tracks') _showTracksModal(p);
                                  if (val == 'visibility') _toggleVisibility(p);
                                  if (val == 'collab') _toggleCollab(p);
                                  if (val == 'code') _showShareCodeDialog(p);
                                  if (val == 'delete') _deletePlaylist(p);
                                },
                                itemBuilder: (ctx) => [
                                  const PopupMenuItem(
                                    value: 'tracks',
                                    child: Row(
                                      children: [
                                        Icon(Icons.queue_music_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('View Tracks'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'visibility',
                                    child: Row(
                                      children: [
                                        Icon(p.isPublic ? Icons.lock_outline : Icons.public, size: 18),
                                        SizedBox(width: 8),
                                        Text(p.isPublic ? 'Make Private' : 'Make Public'),
                                      ],
                                    ),
                                  ),
                                  PopupMenuItem(
                                    value: 'collab',
                                    child: Row(
                                      children: [
                                        Icon(p.collabEnabled ? Icons.person : Icons.group_work_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text(p.collabEnabled ? 'Disable Collaboration' : 'Enable Collaboration'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'code',
                                    child: Row(
                                      children: [
                                        Icon(Icons.qr_code_rounded, size: 18),
                                        SizedBox(width: 8),
                                        Text('Show Share Code'),
                                      ],
                                    ),
                                  ),
                                  const PopupMenuItem(
                                    value: 'delete',
                                    child: Row(
                                      children: [
                                        Icon(Icons.delete_rounded, size: 18, color: Colors.red),
                                        SizedBox(width: 8),
                                        Text('Delete Playlist', style: TextStyle(color: Colors.red)),
                                      ],
                                    ),
                                  ),
                                ],
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

/// Modal Sheet: Displays all tracks inside a playlist
class _PlaylistTracksModal extends StatelessWidget {
  final Playlist playlist;
  const _PlaylistTracksModal({required this.playlist});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final tracks = playlist.tracks;

    return DraggableScrollableSheet(
      initialChildSize: 0.65,
      minChildSize: 0.35,
      maxChildSize: 0.9,
      builder: (ctx, scrollController) => Container(
        decoration: BoxDecoration(
          color: isDark ? const Color(0xFF181818) : Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 14),
                decoration: BoxDecoration(color: Colors.grey.withValues(alpha: 0.4), borderRadius: BorderRadius.circular(2)),
              ),
            ),
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: playlist.isPublic ? Colors.teal : Colors.purple,
                  child: Icon(playlist.isPublic ? Icons.public : Icons.lock_outline, color: Colors.white, size: 18),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(playlist.name, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        'Owner: ${playlist.ownerName} • ${tracks.length} track(s)',
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
                IconButton(icon: const Icon(Icons.close), onPressed: () => Navigator.pop(context)),
              ],
            ),
            const Divider(height: 24),
            Expanded(
              child: tracks.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.music_note_rounded, size: 54, color: isDark ? Colors.white38 : Colors.black38),
                          const SizedBox(height: 12),
                          const Text('No Tracks in this Playlist', style: TextStyle(fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text('This playlist does not have any song tracks yet.', style: TextStyle(fontSize: 12, color: Colors.grey[500])),
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
                        final durationStr = sec > 0
                            ? '${sec ~/ 60}:${(sec % 60).toString().padLeft(2, '0')}'
                            : '--:--';

                        return ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                          leading: Container(
                            width: 32,
                            height: 32,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: isDark ? Colors.white10 : Colors.black12,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '${idx + 1}',
                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                            ),
                          ),
                          title: Text(t.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 14)),
                          subtitle: Text(t.artist, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 12, color: Colors.grey)),
                          trailing: Text(durationStr, style: const TextStyle(fontSize: 11, color: Colors.grey)),
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
