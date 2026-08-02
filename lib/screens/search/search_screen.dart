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
      _filteredTracks = [];
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
      _aiLoadingText = 'Analyzing request & querying LLM...';
    });

    try {
      final prompt = '''
You are an expert music curator. The user entered the request: "$query".
Analyze their intent and generate a JSON object with:
1. "intent": "playlist" ONLY if the request contains EXPLICIT playlist-creation words ("create playlist", "make a playlist", "playlist of", "generate playlist"). For general queries ("old punjabi songs", "karan aujla hits"), return "intent": "search".
2. "queries": JSON array of 2-4 exact search terms. IMPORTANT: Correct any user typos or shorthand artist names into full canonical catalog names (for example: "shidhu" or "sidhu" -> "Sidhu Moose Wala", "karan" -> "Karan Aujla", "diljit" -> "Diljit Dosanjh", "arjit" -> "Arijit Singh").
3. "playlist_name_suggestion": A short creative title.
4. "requested_language": Optional language requested (e.g. "punjabi", "hindi", "english") or null.
5. "requested_artists": Optional array of explicit artist names mentioned (corrected for typos) or null.
6. "count": Optional explicit requested song count (e.g. 10) or null.

Examples:
- "create playlist of shidhu" -> {"intent": "playlist", "queries": ["Sidhu Moose Wala", "Sidhu Moose Wala hits"], "playlist_name_suggestion": "Sidhu Moose Wala Hits", "requested_artists": ["Sidhu Moose Wala"]}
- "create playlist of Karan Aujla" -> {"intent": "playlist", "queries": ["Karan Aujla"], "playlist_name_suggestion": "Karan Aujla Vibes", "requested_artists": ["Karan Aujla"]}
- "old punjabi songs" -> {"intent": "search", "queries": ["old punjabi songs", "classic punjabi"], "requested_language": "punjabi"}

Output ONLY valid JSON:
{
  "intent": "search",
  "queries": ["query 1", "query 2"],
  "playlist_name_suggestion": "Suggested Title",
  "requested_language": null,
  "requested_artists": null,
  "count": null
}
''';

      final (rawResponse, provider) = await AiService.instance.generate(prompt);
      setState(() {
        _aiLoadingText = 'Fetching matching tracks from catalog ($provider)...';
      });

      Map<String, dynamic>? parsedJson;
      try {
        final cleanText = rawResponse.substring(rawResponse.indexOf('{'), rawResponse.lastIndexOf('}') + 1);
        parsedJson = Map<String, dynamic>.from(jsonDecode(cleanText) as Map);
      } catch (_) {}

      List<String> searchQueries = [query];
      String intent = 'search';
      String playlistName = '$query Playlist';
      String? requestedLang;
      List<String>? requestedArtists;
      int? requestedCount;

      final countMatch = RegExp(r'\b(\d+)\s*(songs|tracks)?\b', caseSensitive: false).firstMatch(query);
      if (countMatch != null) {
        requestedCount = int.tryParse(countMatch.group(1) ?? '');
      }

      if (parsedJson != null) {
        intent = parsedJson['intent']?.toString() ?? 'search';
        playlistName = parsedJson['playlist_name_suggestion']?.toString() ?? playlistName;
        if (parsedJson['queries'] is List) {
          searchQueries = (parsedJson['queries'] as List).map((q) => q.toString()).toList();
        }
        if (parsedJson['requested_language'] != null) {
          requestedLang = parsedJson['requested_language'].toString().toLowerCase();
        }
        if (parsedJson['requested_artists'] is List) {
          requestedArtists = (parsedJson['requested_artists'] as List).map((a) => a.toString().toLowerCase()).toList();
        }
        if (parsedJson['count'] != null) {
          requestedCount = int.tryParse(parsedJson['count'].toString()) ?? requestedCount;
        }
      }

      // Hardcode common artist typo fixes into queries & requestedArtists fallback
      final lowerQuery = query.toLowerCase();
      if (lowerQuery.contains('shidhu') || lowerQuery.contains('sidhu')) {
        if (!searchQueries.any((q) => q.toLowerCase().contains('sidhu moose wala'))) {
          searchQueries.insert(0, 'Sidhu Moose Wala');
        }
        requestedArtists ??= ['sidhu moose wala'];
      }

      final hasExplicitPlaylistKeyword = lowerQuery.contains('playlist') || lowerQuery.contains('create') || lowerQuery.contains('make a');
      if (!hasExplicitPlaylistKeyword) {
        intent = 'search';
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
              bool matchesLang = true;
              if (requestedLang != null && requestedLang.isNotEmpty) {
                final trackGenre = t.genre.toLowerCase();
                matchesLang = trackGenre.contains(requestedLang) || t.artist.toLowerCase().contains(requestedLang) || t.title.toLowerCase().contains(requestedLang);
              }

              bool matchesArtist = true;
              if (requestedArtists != null && requestedArtists.isNotEmpty) {
                final trackArtistLower = t.artist.toLowerCase();
                matchesArtist = requestedArtists.any((reqA) => trackArtistLower.contains(reqA) || reqA.contains(trackArtistLower));
              }

              if (matchesLang && matchesArtist) {
                trackMap[normKey] = t;
              }
            }
          }
        } catch (_) {}
      }

      List<Track> resultsList = trackMap.values.toList();

      final targetLimit = (requestedCount != null && requestedCount > 0) ? requestedCount : 25;
      if (resultsList.length > targetLimit) {
        resultsList = resultsList.sublist(0, targetLimit);
      }

      await StorageService.addAiSearchQuery(query);

      if (mounted) {
        setState(() {
          _isAiLoading = false;
          _filteredTracks = resultsList;
          _recentSearches = StorageService.getAiRecentSearches();
        });

        if (intent == 'playlist' && resultsList.isNotEmpty) {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => AiPlaylistReviewScreen(
                suggestedName: playlistName,
                tracks: resultsList,
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
          SnackBar(
            content: Text('AI Search error: $e. Make sure keys are set in .env'),
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
                  child: ElevatedButton.icon(
                    onPressed: () {
                      Navigator.pop(context);
                      ref.read(playbackProvider.notifier).playCustomQueue(sessionTracks, initialIndex: 0);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, color: Colors.black),
                    label: const Text('Play All Songs', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: goldColor,
                      minimumSize: const Size(double.infinity, 44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                    ),
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

    final showBackButton = _searchController.text.isNotEmpty || _filteredTracks.isNotEmpty || _searchFocusNode.hasFocus;

    return Column(
      children: [
        // Search & Filter Header
        Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 4),
          child: Row(
            children: [
              // Search Back Button to easily return to recent searches (first page view)
              if (showBackButton) ...[
                IconButton(
                  icon: const Icon(Icons.arrow_back_rounded, size: 22),
                  tooltip: 'Back to Recent Searches',
                  onPressed: _resetSearch,
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
    if (_searchController.text.isEmpty && _filteredTracks.isEmpty) {
      return ListView(
        padding: const EdgeInsets.only(bottom: 96, top: 16),
        children: [
          _buildChipSection(
            _isAiMode ? 'AI Recent Searches' : 'Recent Searches',
            _recentSearches,
            true,
          ),
          const SizedBox(height: 16),
          _buildHistoryTracksList(),
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
                child: Container(
                  constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width - 64),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: AppTheme.glassDecoration(
                    context: context,
                    opacity: 0.05,
                    radius: 20,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (isRecent) ...[
                        Icon(_isAiMode ? Icons.auto_awesome_rounded : Icons.history_rounded, size: 14, color: _isAiMode ? goldColor : Colors.grey),
                        const SizedBox(width: 6),
                      ],
                      Flexible(
                        child: Text(
                          tag,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500),
                        ),
                      ),
                      if (isRecent) ...[
                        const SizedBox(width: 6),
                        GestureDetector(
                          onTap: () => _showGroupSongsSheet(tag),
                          child: const Icon(Icons.star_rounded, size: 16, color: AppTheme.goldAccent),
                        ),
                      ],
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

  Widget _buildHistoryTracksList() {
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

    if (historyTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 64, color: Colors.grey.withOpacity(0.4)),
            const SizedBox(height: 16),
            const Text(
              'Search for your favorite songs & artists',
              style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return Consumer(
      builder: (context, ref, child) {
        final notifier = ref.read(playbackProvider.notifier);
        return ListView(
          padding: const EdgeInsets.only(bottom: 96, top: 12),
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              child: Text(
                'Played Songs',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontFamily: 'Outfit',
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                    ),
              ),
            ),
            ...historyTracks.map((track) {
              return ListTile(
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
                trailing: const Icon(Icons.play_arrow_rounded, size: 20),
                onTap: () {
                  notifier.playTrack(track);
                },
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
