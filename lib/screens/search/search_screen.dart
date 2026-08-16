import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/ai/ai_service.dart';
import '../../widgets/ai_search_loading.dart';
import '../../themes/app_theme.dart';
import 'ai_playlist_review_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _typewriterTimer;
  List<Track> _filteredTracks = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isAiMode = false;
  bool _isAiLoading = false;
  String _aiLoadingText = 'AI is curating your personalized music experience...';
  String _currentAiPlaylistName = '';

  // Typewriter placeholder animation state
  int _typewriterPromptIndex = 0;
  int _typewriterCharIndex = 0;
  bool _typewriterDeleting = false;
  String _typewriterText = '';

  static const List<String> _typewriterPrompts = [
    'create playlist of punjabi songs',
    'chill lo-fi beats for late night',
    'old romantic hindi classics',
    'upbeat workout gym tracks',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      setState(() {});
    });
    _recentSearches = StorageService.getRecentSearches();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    _searchFocusNode.dispose();
    _debounceTimer?.cancel();
    _typewriterTimer?.cancel();
    super.dispose();
  }

  void _startTypewriter() {
    _typewriterTimer?.cancel();
    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!mounted || !_isAiMode) return;
      final currentPrompt = _typewriterPrompts[_typewriterPromptIndex];

      if (!_typewriterDeleting) {
        if (_typewriterCharIndex < currentPrompt.length) {
          _typewriterCharIndex++;
          setState(() {
            _typewriterText = currentPrompt.substring(0, _typewriterCharIndex);
          });
        } else {
          _typewriterTimer?.cancel();
          Timer(const Duration(seconds: 2), () {
            if (mounted && _isAiMode) {
              _typewriterDeleting = true;
              _startTypewriter();
            }
          });
        }
      } else {
        if (_typewriterCharIndex > 0) {
          _typewriterCharIndex--;
          setState(() {
            _typewriterText = currentPrompt.substring(0, _typewriterCharIndex);
          });
        } else {
          _typewriterDeleting = false;
          _typewriterPromptIndex = (_typewriterPromptIndex + 1) % _typewriterPrompts.length;
        }
      }
    });
  }

  void _toggleAiMode() {
    triggerHaptic(HapticFeedbackType.light);
    setState(() {
      _isAiMode = !_isAiMode;
      _recentSearches = _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
      if (_isAiMode) {
        _startTypewriter();
        if (!StorageService.hasSeenAiTutorial()) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _showAiTutorialOverlay());
        }
      } else {
        _typewriterTimer?.cancel();
      }
    });
  }

  void _resetSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _isAiLoading = false;
      _filteredTracks = [];
      _currentAiPlaylistName = '';
      _recentSearches = _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
    });
  }

  void _showAiTutorialOverlay() {
    int currentStep = 0;
    Timer? autoAdvanceTimer;

    void startAutoAdvance(StateSetter modalSetState, BuildContext dialogContext) {
      autoAdvanceTimer?.cancel();
      autoAdvanceTimer = Timer.periodic(const Duration(seconds: 5), (timer) {
        if (currentStep < 2) {
          modalSetState(() {
            currentStep++;
          });
        } else {
          timer.cancel();
          StorageService.setHasSeenAiTutorial(true);
          if (Navigator.canPop(dialogContext)) {
            Navigator.pop(dialogContext);
          }
        }
      });
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, modalSetState) {
            if (autoAdvanceTimer == null || !autoAdvanceTimer!.isActive) {
              startAutoAdvance(modalSetState, dialogContext);
            }

            final titles = [
              'Welcome to AI Music Curator 🪄',
              'Smart Query Analysis ⚡',
              'Review & Instant Play 🎵',
            ];
            final descs = [
              'Type any natural language prompt to generate personalized playlists, genres, moods, or artist collections.',
              'AI translates your request into targeted search queries across live music catalogs.',
              'Customize tracks, edit playlist titles, and play or save your curated collections with one tap.',
            ];

            const goldColor = Color(0xFFFFC72C);

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1B1B1E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: goldColor, width: 1.5),
                  boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 20)],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: List.generate(3, (i) => Container(
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        width: i == currentStep ? 24 : 8,
                        height: 8,
                        decoration: BoxDecoration(
                          color: i == currentStep ? goldColor : Colors.grey.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      titles[currentStep],
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18, fontFamily: 'Outfit'),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      descs[currentStep],
                      style: const TextStyle(fontSize: 13, color: Colors.grey, height: 1.4),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton(
                      onPressed: () {
                        if (currentStep < 2) {
                          modalSetState(() {
                            currentStep++;
                          });
                          startAutoAdvance(modalSetState, dialogContext);
                        } else {
                          autoAdvanceTimer?.cancel();
                          StorageService.setHasSeenAiTutorial(true);
                          Navigator.pop(dialogContext);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: goldColor,
                        foregroundColor: Colors.black,
                        minimumSize: const Size(double.infinity, 46),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      child: Text(currentStep == 2 ? 'Get Started ✨' : 'Next (${3 - currentStep} remaining)'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    ).then((_) {
      autoAdvanceTimer?.cancel();
    });
  }



  void _onSearchChanged() {
    if (_isAiMode) return; // In AI mode, search runs on submission or enter key
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _filteredTracks = [];
        _isSearching = false;
      });
      return;
    }

    setState(() {
      _isSearching = true;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 350), () async {
      try {
        final results = await ref.read(musicSourceProvider).searchTracks(query);
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _filteredTracks = results;
            _isSearching = false;
          });
          await StorageService.addSearchQuery(query);
          setState(() {
            _recentSearches = StorageService.getRecentSearches();
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _executeAiSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isAiLoading = true;
      _aiLoadingText = 'Finding best match for you...';
    });

    try {
      final prompt = '''
You are an expert music curator. The user entered the request: "$query".
Analyze their intent and generate a JSON object with:
1. "intent": "playlist" if the request asks for a playlist, collection, or multi-artist/genre list (e.g. "make playlist", "punjabi and haryanvi songs", "workout songs", "create playlist"). For single specific track titles, return "intent": "search".
2. "queries": JSON array of 2-4 exact search terms. IMPORTANT: Correct any user typos or shorthand names (for example: "makr" -> "make", "shidhu" or "sidhu" -> "Sidhu Moose Wala", "karan" -> "Karan Aujla", "diljit" -> "Diljit Dosanjh", "haryanavi" -> "Haryanvi").
3. "playlist_name_suggestion": A short creative title.

Examples:
- "makr playlist of punjabi and haryanavi songs" -> {"intent": "playlist", "queries": ["Top Punjabi Songs", "Top Haryanvi Songs", "Punjabi Haryanvi Hits"], "playlist_name_suggestion": "Punjabi & Haryanvi Mix"}
- "create playlist of shidhu" -> {"intent": "playlist", "queries": ["Sidhu Moose Wala", "Sidhu Moose Wala hits"], "playlist_name_suggestion": "Sidhu Moose Wala Hits"}
- "old romantic hindi songs" -> {"intent": "playlist", "queries": ["old hindi romantic songs", "classic hindi romantic"], "playlist_name_suggestion": "Retro Hindi Romance"}

Output ONLY valid JSON:
{
  "intent": "playlist",
  "queries": ["query 1", "query 2"],
  "playlist_name_suggestion": "Suggested Title"
}
''';

      final (rawResponse, _) = await AiService.instance.generate(prompt);
      setState(() {
        _aiLoadingText = 'Curating your personalized tracks...';
      });

      Map<String, dynamic>? parsedJson;
      try {
        final cleanText = rawResponse.substring(rawResponse.indexOf('{'), rawResponse.lastIndexOf('}') + 1);
        parsedJson = Map<String, dynamic>.from(jsonDecode(cleanText) as Map);
      } catch (_) {}

      List<String> searchQueries = [query];
      String intent = 'playlist';
      String playlistName = '$query Playlist';

      if (parsedJson != null) {
        intent = parsedJson['intent']?.toString() ?? 'playlist';
        playlistName = parsedJson['playlist_name_suggestion']?.toString() ?? playlistName;
        if (parsedJson['queries'] is List && (parsedJson['queries'] as List).isNotEmpty) {
          searchQueries = (parsedJson['queries'] as List).map((q) => q.toString()).toList();
        }
      }

      // Handle multi-genre/language prompt fallback if AI queries missed any part
      final lowerQuery = query.toLowerCase();
      if (lowerQuery.contains('punjabi') && (lowerQuery.contains('haryanvi') || lowerQuery.contains('haryanavi'))) {
        intent = 'playlist';
        if (!searchQueries.any((q) => q.toLowerCase().contains('haryanv') || q.toLowerCase().contains('haryanav'))) {
          searchQueries.add('Top Haryanvi Songs');
        }
        if (!searchQueries.any((q) => q.toLowerCase().contains('punjabi'))) {
          searchQueries.add('Top Punjabi Songs');
        }
      }

      final musicSource = ref.read(musicSourceProvider);
      final trackMap = <String, Track>{};

      for (final q in searchQueries) {
        try {
          final results = await musicSource.searchTracks(q);
          for (final t in results) {
            final normTitle = t.title.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
            final normArtist = t.artist.toLowerCase().replaceAll(RegExp(r'[^\w\s]'), '').trim();
            final normKey = '${normTitle}_$normArtist';

            if (!trackMap.containsKey(normKey)) {
              trackMap[normKey] = t;
            }
          }
        } catch (_) {}
      }

      List<Track> resultsList = trackMap.values.toList();
      if (resultsList.isEmpty) {
        try {
          resultsList = await musicSource.searchTracks(query);
        } catch (_) {}
      }

      if (resultsList.length > 30) {
        resultsList = resultsList.sublist(0, 30);
      }

      await StorageService.addAiSearchQuery(query);
      if (resultsList.isNotEmpty) {
        await StorageService.saveGroupedAiSession(playlistName, resultsList);
        await StorageService.saveGroupedAiSession(query, resultsList);
      }

      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _filteredTracks = resultsList;
          _currentAiPlaylistName = playlistName;
          _recentSearches = StorageService.getAiRecentSearches();
        });

        if (resultsList.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => AiPlaylistReviewScreen(
                suggestedName: playlistName,
                tracks: List.from(resultsList),
              ),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isAiLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('AI Search completed with fallback search.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  void _showGroupSongsSheet(String tag) async {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const goldColor = Color(0xFFFFC72C);

    List<Track> sessionTracks = StorageService.getGroupedSessionTracks(tag);

    if (sessionTracks.isEmpty) {
      try {
        final cleanTag = tag.replaceAll(RegExp(r'✨|\(\d+\s*songs\)'), '').trim();
        sessionTracks = await ref.read(musicSourceProvider).searchTracks(cleanTag);
      } catch (_) {}
    }

    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          height: MediaQuery.of(context).size.height * 0.65,
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF171717) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.grey.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                children: [
                  const Icon(Icons.star_rounded, color: goldColor, size: 22),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      tag,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (sessionTracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            ref.read(playbackProvider.notifier).playCustomQueue(sessionTracks, initialIndex: 0);
                          },
                          icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                          label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: goldColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final name = tag.replaceAll(RegExp(r'✨|\(\d+\s*songs\)'), '').trim();
                            final playlists = StorageService.getPlaylists();
                            final newPl = {
                              'id': DateTime.now().millisecondsSinceEpoch.toString(),
                              'name': name,
                              'description': 'AI generated playlist',
                              'trackIds': sessionTracks.map((t) => t.id).toList(),
                              'tracks': sessionTracks.map((t) => {
                                'id': t.id,
                                'title': t.title,
                                'artist': t.artist,
                                'album': t.album,
                                'duration': t.duration,
                                'artworkUrl': t.artworkUrl,
                                'audioUrl': t.audioUrl,
                                'genre': t.genre,
                              }).toList(),
                            };
                            playlists.add(newPl);
                            await StorageService.savePlaylists(playlists);
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Saved "$name" to Playlists Library! ⚡'),
                                  behavior: SnackBarBehavior.floating,
                                ),
                              );
                            }
                          },
                          icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                          label: const Text('Save Playlist'),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: goldColor),
                            foregroundColor: goldColor,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: sessionTracks.isEmpty
                    ? const Center(child: Text('No saved tracks for this session', style: TextStyle(color: Colors.grey)))
                    : ListView.builder(
                        itemCount: sessionTracks.length,
                        itemBuilder: (context, index) {
                          final track = sessionTracks[index];
                          return ListTile(
                            contentPadding: EdgeInsets.zero,
                            leading: ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(
                                track.artworkUrl,
                                width: 44,
                                height: 44,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) => Container(
                                  width: 44,
                                  height: 44,
                                  color: Colors.grey.shade800,
                                  child: const Icon(Icons.music_note_rounded),
                                ),
                              ),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                            ),
                            subtitle: Text(
                              '${track.artist} • ${track.genre}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 12, color: Colors.grey),
                            ),
                            trailing: const Icon(Icons.play_arrow_rounded, size: 20),
                            onTap: () {
                              Navigator.pop(context);
                              ref.read(playbackProvider.notifier).playCustomQueue(sessionTracks, initialIndex: index);
                            },
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
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
                    color: Colors.grey.withValues(alpha: 0.3),
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
      selectedColor: AppTheme.goldAccent.withValues(alpha: 0.2),
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
    const goldColor = Color(0xFFFFC72C);

    if (_isAiLoading) {
      return Scaffold(
        body: AiSearchLoading(statusText: _aiLoadingText),
      );
    }

    final showBackButton = _searchController.text.isNotEmpty || _filteredTracks.isNotEmpty || _searchFocusNode.hasFocus || _isSearching;

    return Column(
      children: [
        // Search & Filter Header
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 4),
          child: Row(
            children: [
              // Search Back Button to return to recent searches & played music home page
              if (showBackButton) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  tooltip: 'Back to Recent Searches & Played Music',
                  onPressed: () {
                    FocusScope.of(context).unfocus();
                    _resetSearch();
                  },
                ),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  height: 48,
                  decoration: BoxDecoration(
                    color: _isAiMode
                        ? goldColor.withValues(alpha: 0.12)
                        : (isDark ? Colors.white.withValues(alpha: 0.06) : Colors.black.withValues(alpha: 0.05)),
                    borderRadius: BorderRadius.circular(AppTheme.pillRadius),
                    border: _isAiMode ? Border.all(color: goldColor, width: 1.5) : null,
                  ),
                  child: TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    style: const TextStyle(fontSize: 14),
                    onSubmitted: (query) async {
                      if (_isAiMode) {
                        await _executeAiSearch(query);
                      } else {
                        await StorageService.addSearchQuery(query);
                        setState(() {
                          _recentSearches = StorageService.getRecentSearches();
                        });
                      }
                    },
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: _isAiMode
                          ? (_searchController.text.isEmpty && _typewriterText.isNotEmpty ? 'Try "$_typewriterText"' : 'Ask AI for songs or playlist...')
                          : 'Search songs, albums, artists...',
                      hintStyle: TextStyle(
                        fontSize: 13,
                        color: _isAiMode ? goldColor.withValues(alpha: 0.8) : Colors.grey,
                      ),
                      prefixIcon: Icon(
                        _isAiMode ? Icons.auto_awesome_rounded : Icons.search_rounded,
                        size: 20,
                        color: _isAiMode ? goldColor : Colors.grey,
                      ),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (_searchController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear_rounded, size: 18),
                              onPressed: () => _searchController.clear(),
                            ),
                          IconButton(
                            icon: Icon(
                              _isAiMode ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                              color: _isAiMode ? goldColor : Colors.grey,
                              size: 20,
                            ),
                            tooltip: 'Toggle AI Music Curator Mode',
                            onPressed: _toggleAiMode,
                          ),
                        ],
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                    ),
                  ),
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
    if (_searchController.text.isEmpty && _filteredTracks.isEmpty) {
      final isFocused = _searchFocusNode.hasFocus;

      if (isFocused) {
        // FOCUSED STATE: Show ONLY Search History query chips
        return ListView(
          padding: const EdgeInsets.only(bottom: 150, top: 16),
          children: [
            _buildChipSection(
              _isAiMode ? 'AI Recent Searches' : 'Search History',
              _recentSearches,
              true,
            ),
          ],
        );
      }

      // DEFAULT / UN-FOCUSED LANDING INDEX STATE: Show ONLY AI Playlists & Played Songs
      final aiSessionsMap = StorageService.getGroupedAiSessionsMap();
      final historyTracks = _getHistoryTracksList();

      return ListView(
        padding: const EdgeInsets.only(bottom: 150, top: 16),
        children: [
          // 1. AI Playlist Groups Section
          if (aiSessionsMap.isNotEmpty) ...[
            _buildAiPlaylistGroupsSection(aiSessionsMap),
            const SizedBox(height: 20),
          ],

          // 2. Recently Played Songs Section
          _buildRecentlyPlayedSongsSection(historyTracks),
        ],
      );
    }

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary)),
            const SizedBox(height: 16),
            const Text('Searching live catalog...', style: TextStyle(color: Colors.grey)),
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

    final showAiBanner = _isAiMode && _filteredTracks.isNotEmpty;

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView.builder(
          padding: const EdgeInsets.only(bottom: 150, top: 8),
          itemCount: _filteredTracks.length + (showAiBanner ? 1 : 0),
          itemBuilder: (context, index) {
            if (showAiBanner && index == 0) {
              return _buildAiPlaylistBannerCard(context, notifier);
            }
            final trackIndex = showAiBanner ? index - 1 : index;
            final track = _filteredTracks[trackIndex];
            return Dismissible(
              key: Key('search_${track.id}_$trackIndex'),
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
                return false;
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
                onTap: () async {
                  await StorageService.addSearchedAndPlayedTrack(track);
                  notifier.playTrack(track);
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildAiPlaylistBannerCard(BuildContext context, PlaybackNotifier notifier) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const goldColor = Color(0xFFFFC72C);
    final playlistTitle = _currentAiPlaylistName.isEmpty
        ? '${_searchController.text.trim()} Playlist'
        : _currentAiPlaylistName;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: isDark
              ? [const Color(0xFF282417), const Color(0xFF19181B)]
              : [const Color(0xFFFFF9E6), const Color(0xFFF3EFE7)],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: goldColor.withOpacity(0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.auto_awesome_rounded, color: goldColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  playlistTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, fontFamily: 'Outfit'),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: goldColor.withOpacity(0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_filteredTracks.length} Tracks',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: goldColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () {
                    notifier.playCustomQueue(_filteredTracks, initialIndex: 0);
                  },
                  icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                  label: const Text('Play All', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: goldColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AiPlaylistReviewScreen(
                          suggestedName: playlistTitle,
                          tracks: List.from(_filteredTracks),
                        ),
                      ),
                    );
                  },
                  icon: const Icon(Icons.bookmark_add_rounded, size: 18),
                  label: const Text('Save / Edit'),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: goldColor),
                    foregroundColor: goldColor,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildChipSection(String title, List<String> items, bool isRecent) {
    if (items.isEmpty) return const SizedBox.shrink();
    const goldColor = Color(0xFFFFC72C);

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
                    if (_isAiMode) {
                      await StorageService.clearAiSearchHistory();
                    } else {
                      await StorageService.clearSearchHistory();
                    }
                    setState(() {
                      _recentSearches = _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
                    });
                  },
                  child: const Text('Clear All', style: TextStyle(color: AppTheme.goldAccent, fontSize: 12)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((tag) {
              final double maxTextWidth = (MediaQuery.of(context).size.width - 120).clamp(80.0, 400.0);
              return Container(
                constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 48),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: AppTheme.glassDecoration(
                  context: context,
                  opacity: 0.06,
                  radius: 20,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () async {
                        _searchController.text = tag;
                        if (_isAiMode) {
                          await _executeAiSearch(tag);
                        } else {
                          await StorageService.addSearchQuery(tag);
                          setState(() {
                            _recentSearches = StorageService.getRecentSearches();
                          });
                          _onSearchChanged();
                        }
                      },
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_isAiMode ? Icons.auto_awesome_rounded : Icons.history_rounded, size: 14, color: _isAiMode ? goldColor : Colors.grey),
                          const SizedBox(width: 6),
                          ConstrainedBox(
                            constraints: BoxConstraints(maxWidth: maxTextWidth),
                            child: Text(
                              tag,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    GestureDetector(
                      onTap: () async {
                        if (_isAiMode) {
                          final list = StorageService.getAiRecentSearches()..remove(tag);
                          await StorageService.saveSetting('ai_searches', list);
                        } else {
                          final list = StorageService.getRecentSearches()..remove(tag);
                          await StorageService.saveSetting('searches', list);
                        }
                        setState(() {
                          _recentSearches = _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
                        });
                      },
                      child: const Icon(Icons.close_rounded, size: 14, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildAiPlaylistGroupsSection(Map<String, dynamic> aiSessionsMap) {
    const goldColor = Color(0xFFFFC72C);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: const [
              Icon(Icons.auto_awesome_rounded, size: 18, color: goldColor),
              SizedBox(width: 8),
              Text(
                'AI Playlist Groups',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 155,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: aiSessionsMap.keys.length,
              itemBuilder: (context, index) {
                final key = aiSessionsMap.keys.elementAt(index);
                final rawTracks = aiSessionsMap[key] as List?;
                final count = rawTracks?.length ?? 0;
                final firstTrackMap = (rawTracks != null && rawTracks.isNotEmpty) ? Map<String, dynamic>.from(rawTracks.first as Map) : null;
                final artUrl = firstTrackMap?['artworkUrl']?.toString() ?? '';

                final titleCapitalized = key.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

                return Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1F23) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: goldColor.withOpacity(0.3), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withOpacity(0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(12),
                        child: artUrl.isNotEmpty
                            ? Image.network(
                                artUrl,
                                width: double.infinity,
                                height: 70,
                                fit: BoxFit.cover,
                                errorBuilder: (_, __, ___) => Container(width: double.infinity, height: 70, color: Colors.grey.shade800, child: const Icon(Icons.music_note_rounded)),
                              )
                            : Container(width: double.infinity, height: 70, color: Colors.grey.shade800, child: const Icon(Icons.music_note_rounded)),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        titleCapitalized,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '$count tracks',
                            style: const TextStyle(fontSize: 11, color: Colors.grey),
                          ),
                          GestureDetector(
                            onTap: () => _showGroupSongsSheet(key),
                            child: const CircleAvatar(
                              radius: 12,
                              backgroundColor: goldColor,
                              child: Icon(Icons.play_arrow_rounded, size: 16, color: Colors.black),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  List<Track> _getHistoryTracksList() {
    final rawHistory = StorageService.getSearchedAndPlayedTracks();
    final List<Track> historyTracks = [];
    for (final item in rawHistory) {
      if (item['track_id'] != null) {
        historyTracks.add(
          Track(
            id: item['track_id'].toString(),
            title: item['title']?.toString() ?? 'Track',
            artist: item['artist']?.toString() ?? 'Unknown Artist',
            album: item['album']?.toString() ?? 'Single',
            duration: item['duration']?.toString() ?? '3:30',
            artworkUrl: item['artworkUrl']?.toString() ?? '',
            audioUrl: item['audioUrl']?.toString() ?? '',
            genre: item['genre']?.toString() ?? '',
          ),
        );
      }
    }
    return historyTracks;
  }

  Widget _buildRecentlyPlayedSongsSection(List<Track> historyTracks) {
    if (historyTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.search_rounded, size: 48, color: Colors.grey.withOpacity(0.4)),
              const SizedBox(height: 12),
              const Text(
                'Search for your favorite songs & artists',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
              child: Text(
                'Recently Played Songs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Outfit',
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            ...historyTracks.map((track) {
              return Dismissible(
                key: Key('recent_swipe_${track.id}'),
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
                  return false;
                },
                background: Container(
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.only(left: 24),
                  color: AppTheme.goldAccent.withOpacity(0.85),
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
                    borderRadius: BorderRadius.circular(10),
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
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                  ),
                  subtitle: Text(
                    '${track.artist} • ${track.genre}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  trailing: const Icon(Icons.play_circle_fill_rounded, size: 28, color: AppTheme.goldAccent),
                  onTap: () {
                    notifier.playTrack(track);
                  },
                ),
              );
            }),
          ],
        );
      },
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
