import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fl_chart/fl_chart.dart';
import '../../providers/auth_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/admin/admin_service.dart';
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

  Future<void> _loadStats({bool forceRefresh = false}) async {
    setState(() => _isLoadingStats = true);
    final data = await _adminService.getDashboardStats(forceRefresh: forceRefresh);
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
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Analytics',
            onPressed: () => _loadStats(forceRefresh: true),
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
          _AdminUsersTab(adminService: _adminService),
          _AdminPlaylistsTab(adminService: _adminService),
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
                  color: color.withOpacity(0.15),
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
  const _AdminUsersTab({required this.adminService});

  @override
  State<_AdminUsersTab> createState() => _AdminUsersTabState();
}

class _AdminUsersTabState extends State<_AdminUsersTab> {
  final List<AppUser> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _loadUsers();
  }

  Future<void> _loadUsers() async {
    setState(() => _isLoading = true);
    final list = await widget.adminService.getPaginatedUsers();
    if (mounted) {
      setState(() {
        _users.clear();
        _users.addAll(list);
        _isLoading = false;
      });
    }
  }

  Future<void> _toggleBlock(AppUser user) async {
    final isBlocked = await widget.adminService.isUserBlocked(user.uid);
    if (!mounted) return;

    if (isBlocked) {
      await widget.adminService.unblockUser(user.uid);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Unblocked ${user.displayName}')));
    } else {
      final reasonController = TextEditingController();
      final confirm = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text('Block ${user.displayName}?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Blocked users will be denied all read/write permissions via security rules.'),
              const SizedBox(height: 12),
              TextField(
                controller: reasonController,
                decoration: const InputDecoration(labelText: 'Reason for block'),
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
        if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Blocked ${user.displayName}')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    final filtered = _users.where((u) {
      final q = _searchQuery.toLowerCase();
      return u.displayName.toLowerCase().contains(q) || (u.email?.toLowerCase().contains(q) ?? false);
    }).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            decoration: InputDecoration(
              hintText: 'Search by name or email...',
              prefixIcon: const Icon(Icons.search),
              filled: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
            ),
            onChanged: (val) => setState(() => _searchQuery = val),
          ),
        ),
        Expanded(
          child: ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            itemCount: filtered.length,
            separatorBuilder: (_, __) => const SizedBox(height: 8),
            itemBuilder: (context, idx) {
              final user = filtered[idx];
              return Card(
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: user.isGuest ? Colors.amber : Colors.blue,
                    child: Icon(user.isGuest ? Icons.person_outline : Icons.person, color: Colors.white),
                  ),
                  title: Text(user.displayName, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text(
                    '${user.email ?? "Guest"} • Logins: ${user.loginCount} • Plays: ${user.stats.totalSongsPlayed}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (val) {
                      if (val == 'block') _toggleBlock(user);
                    },
                    itemBuilder: (ctx) => [
                      const PopupMenuItem(value: 'block', child: Text('Toggle Block / Unblock')),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

/// Admin Playlists Management Tab
class _AdminPlaylistsTab extends StatefulWidget {
  final AdminService adminService;
  const _AdminPlaylistsTab({required this.adminService});

  @override
  State<_AdminPlaylistsTab> createState() => _AdminPlaylistsTabState();
}

class _AdminPlaylistsTabState extends State<_AdminPlaylistsTab> {
  final List<Playlist> _playlists = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadPlaylists();
  }

  Future<void> _loadPlaylists() async {
    setState(() => _isLoading = true);
    final list = await widget.adminService.getPaginatedPlaylists();
    if (mounted) {
      setState(() {
        _playlists.clear();
        _playlists.addAll(list);
        _isLoading = false;
      });
    }
  }

  Future<void> _deletePlaylist(Playlist p) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Delete "${p.name}"?'),
        content: const Text('This will delete the playlist document from Firestore.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      await widget.adminService.forceDeletePlaylist(p.id);
      _loadPlaylists();
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) return const Center(child: CircularProgressIndicator());

    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: _playlists.length,
      separatorBuilder: (_, __) => const SizedBox(height: 8),
      itemBuilder: (context, idx) {
        final p = _playlists[idx];
        return Card(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: p.isPublic ? Colors.teal : Colors.purple,
              child: Icon(p.isPublic ? Icons.public : Icons.lock_outline, color: Colors.white),
            ),
            title: Text(p.name, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(
              'Owner: ${p.ownerName} • Tracks: ${p.trackCount} • ${p.collabEnabled ? "Collab Active" : "Private"}',
              style: const TextStyle(fontSize: 12),
            ),
            trailing: PopupMenuButton<String>(
              onSelected: (val) {
                if (val == 'delete') _deletePlaylist(p);
                if (val == 'private') {
                  widget.adminService.forceMakePrivate(p.id);
                  _loadPlaylists();
                }
              },
              itemBuilder: (ctx) => [
                if (p.isPublic) const PopupMenuItem(value: 'private', child: Text('Force Make Private')),
                const PopupMenuItem(value: 'delete', child: Text('Delete Playlist', style: TextStyle(color: Colors.red))),
              ],
            ),
          ),
        );
      },
    );
  }
}
