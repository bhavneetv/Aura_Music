import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../themes/app_theme.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  List<Track> _filteredTracks = [];
  List<String> _recentSearches = [];
  final List<String> _trendingSearches = ['Synthwave', 'Ambient', 'Acoustic', 'Jazz', 'Lo-Fi'];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(_onSearchChanged);
    _filteredTracks = Track.mockTracks;
    _recentSearches = StorageService.getRecentSearches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() async {
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredTracks = Track.mockTracks;
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    try {
      final results = await ref.read(musicSourceProvider).searchTracks(query);
      if (mounted && _searchController.text.trim() == query) {
        setState(() {
          _filteredTracks = results;
          _isSearching = false;
        });
        StorageService.addSearchQuery(query);
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isSearching = false;
        });
      }
    }
  }

  void _showFilterBottomSheet(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF171717) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(28),
              topRight: Radius.circular(28),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withOpacity(0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              const Text(
                'Filter & Sort',
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('Popularity', true),
                  _buildFilterChip('Release Date', false),
                  _buildFilterChip('Title A-Z', false),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Duration', style: TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                children: [
                  _buildFilterChip('Any', true),
                  _buildFilterChip('< 3 min', false),
                  _buildFilterChip('3-5 min', false),
                  _buildFilterChip('> 5 min', false),
                ],
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () => Navigator.pop(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppTheme.goldAccent,
                  foregroundColor: isDark ? Colors.black : Colors.white,
                  minimumSize: const Size(double.infinity, 50),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                  ),
                ),
                child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold)),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildFilterChip(String label, bool isSelected) {
    return ChoiceChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (val) {},
      selectedColor: AppTheme.goldAccent.withOpacity(0.2),
      checkmarkColor: AppTheme.goldAccent,
      labelStyle: TextStyle(
        color: isSelected ? AppTheme.goldAccent : Colors.grey,
        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Column(
      children: [
        // Search & Filter Header
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 8),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 48,
                  decoration: AppTheme.glassDecoration(
                    context: context,
                    opacity: isDark ? 0.06 : 0.05,
                    radius: AppTheme.pillRadius,
                  ),
                  child: TextField(
                    controller: _searchController,
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (query) async {
                      await StorageService.addSearchQuery(query);
                      setState(() {
                        _recentSearches = StorageService.getRecentSearches();
                      });
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Search songs, albums, artists...',
                      prefixIcon: const Icon(Icons.search_rounded, size: 20),
                      suffixIcon: _searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => _searchController.clear(),
                            )
                          : null,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              GestureDetector(
                onTap: () => _showFilterBottomSheet(context),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: AppTheme.glassDecoration(
                    context: context,
                    opacity: isDark ? 0.06 : 0.05,
                    radius: 24,
                  ),
                  child: const Icon(Icons.tune_rounded, size: 20),
                ),
              ),
            ],
          ),
        ),

        // Segmented Tabs
        TabBar(
          controller: _tabController,
          indicatorColor: AppTheme.goldAccent,
          labelColor: AppTheme.goldAccent,
          unselectedLabelColor: isDark ? Colors.white38 : Colors.black38,
          labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
          tabs: const [
            Tab(text: 'Songs'),
            Tab(text: 'Albums'),
            Tab(text: 'Artists'),
            Tab(text: 'Playlists'),
          ],
        ),

        // Body Content
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSongsTab(),
              _buildDummyTab('Albums Grid View'),
              _buildDummyTab('Artists List View'),
              _buildDummyTab('Playlists Grid View'),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildSongsTab() {
    if (_searchController.text.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 96, top: 16),
        children: [
          _buildChipSection('Recent Searches', _recentSearches, true),
          const SizedBox(height: 24),
          _buildChipSection('Trending Now', _trendingSearches, false),
        ],
      );
    }

    if (_isSearching) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(AppTheme.goldAccent)),
            SizedBox(height: 16),
            Text('Searching live Jamendo catalog...', style: TextStyle(color: Colors.grey)),
          ],
        ),
      );
    }

    if (_filteredTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.music_off_rounded, size: 64, color: Colors.grey.withOpacity(0.5)),
            const SizedBox(height: 16),
            const Text(
              'No results found',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 96, top: 8),
          itemCount: _filteredTracks.length,
          itemBuilder: (context, index) {
            final track = _filteredTracks[index];
            return Dismissible(
              key: Key('search_${track.id}_$index'),
              direction: DismissDirection.startToEnd,
              confirmDismiss: (direction) async {
                notifier.addToQueue(track);
                triggerHaptic(HapticFeedbackType.medium);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Added "${track.title}" to Queue 🎵'),
                    duration: const Duration(seconds: 1),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                return false; // Keep item in search list
              },
              background: Container(
                alignment: Alignment.centerLeft,
                padding: const EdgeInsets.only(left: 24),
                color: AppTheme.goldAccent.withOpacity(0.8),
                child: const Row(
                  children: [
                    Icon(Icons.queue_music_rounded, color: Colors.black),
                    SizedBox(width: 8),
                    Text('Add to Queue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              child: ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.network(
                    track.artworkUrl,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) => Container(
                      width: 48,
                      height: 48,
                      color: Colors.grey.shade800,
                      child: const Icon(Icons.music_note_rounded),
                    ),
                  ),
                ),
                title: Text(
                  track.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  '${track.artist} • ${track.genre}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 12),
                onTap: () {
                  notifier.playTrack(track);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildChipSection(String title, List<String> items, bool isRecent) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              if (isRecent)
                TextButton(
                  onPressed: () async {
                    await StorageService.clearSearchHistory();
                    setState(() {
                      _recentSearches = StorageService.getRecentSearches();
                    });
                  },
                  child: const Text('Clear', style: TextStyle(color: AppTheme.goldAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((tag) {
              return GestureDetector(
                onTap: () async {
                  _searchController.text = tag;
                  await StorageService.addSearchQuery(tag);
                  setState(() {
                    _recentSearches = StorageService.getRecentSearches();
                  });
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: AppTheme.glassDecoration(
                    context: context,
                    opacity: 0.05,
                    radius: 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRecent) ...[
                        const Icon(Icons.history_rounded, size: 14, color: Colors.grey),
                        const SizedBox(width: 6),
                      ],
                      Text(
                        tag,
                        style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildDummyTab(String placeholderText) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.library_music_rounded, size: 48, color: Colors.grey.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(placeholderText, style: const TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }
}
