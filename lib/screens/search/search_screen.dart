import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/ai/ai_service.dart';
// Replaced by the curating animation at the bottom of this file.
// ignore: unused_import
import '../../widgets/ai_search_loading.dart';
import '../../widgets/app_artwork_image.dart';
// ignore: unused_import
import '../../themes/app_theme.dart';
import '../../services/music_sources/source_manager.dart';
import 'ai_playlist_review_screen.dart';

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> with TickerProviderStateMixin {
  late TabController _tabController;
  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();
  Timer? _debounceTimer;
  Timer? _typewriterTimer;
  List<Track> _allSearchResults = [];
  List<Track> _filteredTracks = [];
  List<String> _recentSearches = [];
  bool _isSearching = false;
  bool _isAiMode = false;
  bool _isAiLoading = false;
  String _aiLoadingText = 'AI is curating your personalized music experience...';
  String _currentAiPlaylistName = '';
  String _selectedSortFilter = 'Popularity';
  String _sourceFilter = 'All'; // 'All', 'Saavn', 'YT'

  // Typewriter placeholder animation state
  int _typewriterPromptIndex = 0;
  int _typewriterCharIndex = 0;
  bool _typewriterDeleting = false;
  int _typewriterPause = 0;
  final ValueNotifier<String> _typewriter = ValueNotifier<String>('');

  // AI curating animation: which step is running, and on what
  int _aiStage = 0;
  String _aiStageDetail = '';
  String _aiQuery = '';
  int _aiQueryStep = 0;
  int _aiQueryTotal = 0;
  late final AnimationController _aiGlowController;

  static const List<String> _typewriterPrompts = [
    'create playlist of punjabi songs',
    'chill lo-fi beats for late night',
    'old romantic hindi classics',
    'upbeat workout gym tracks',
  ];

  static const List<Map<String, dynamic>> _genreCards = [
    {
      'title': 'Punjabi Hits',
      'query': 'Punjabi Hits',
      'colors': [Color(0xFFFF512F), Color(0xFFDD2476)],
      'icon': Icons.whatshot_rounded,
    },
    {
      'title': 'Bollywood Romance',
      'query': 'Hindi Romantic',
      'colors': [Color(0xFF8E2DE2), Color(0xFF4A00E0)],
      'icon': Icons.favorite_rounded,
    },
    {
      'title': 'Lo-Fi Chill',
      'query': 'Lo-Fi Beats',
      'colors': [Color(0xFF00B4DB), Color(0xFF0083B0)],
      'icon': Icons.nightlife_rounded,
    },
    {
      'title': 'Gym & Workout',
      'query': 'Workout Gym',
      'colors': [Color(0xFFF857A6), Color(0xFFFF5858)],
      'icon': Icons.fitness_center_rounded,
    },
    {
      'title': 'Haryanvi Mix',
      'query': 'Haryanvi Hits',
      'colors': [Color(0xFF11998E), Color(0xFF38EF7D)],
      'icon': Icons.graphic_eq_rounded,
    },
    {
      'title': 'Retro 90s',
      'query': '90s Hindi Classics',
      'colors': [Color(0xFFFF9900), Color(0xFFFF5500)],
      'icon': Icons.album_rounded,
    },
    {
      'title': 'Pop & Party',
      'query': 'Pop Dance Hits',
      'colors': [Color(0xFFB92B27), Color(0xFF1565C0)],
      'icon': Icons.celebration_rounded,
    },
    {
      'title': 'Acoustic Vibes',
      'query': 'Acoustic Unplugged',
      'colors': [Color(0xFF4776E6), Color(0xFF8E54E9)],
      'icon': Icons.music_note_rounded,
    },
  ];

  static const List<String> _trendingArtists = [
    'Sidhu Moose Wala',
    'Diljit Dosanjh',
    'Karan Aujla',
    'Arijit Singh',
    'AP Dhillon',
    'Shubh',
    'Badshah',
    'Taylor Swift',
  ];

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _aiGlowController = AnimationController(vsync: this, duration: const Duration(milliseconds: 2600));
    _searchController.addListener(_onSearchChanged);
    _searchFocusNode.addListener(() {
      if (mounted) setState(() {});
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
    _aiGlowController.dispose();
    _typewriter.dispose();
    super.dispose();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // AI MODE
  // ═══════════════════════════════════════════════════════════════════════════

  /// Types the example prompts into the search field's hint, one letter at a
  /// time. It writes to a notifier, so only the hint text repaints (the old
  /// version rebuilt the whole screen ten times a second).
  void _startTypewriter() {
    _typewriterTimer?.cancel();
    _typewriterPromptIndex = 0;
    _typewriterCharIndex = 0;
    _typewriterDeleting = false;
    _typewriterPause = 6;
    _typewriter.value = '';

    _typewriterTimer = Timer.periodic(const Duration(milliseconds: 65), (timer) {
      if (!mounted || !_isAiMode) return;
      if (_typewriterPause > 0) {
        _typewriterPause--;
        return;
      }
      final currentPrompt = _typewriterPrompts[_typewriterPromptIndex];

      if (!_typewriterDeleting) {
        if (_typewriterCharIndex < currentPrompt.length) {
          _typewriterCharIndex++;
          _typewriter.value = currentPrompt.substring(0, _typewriterCharIndex);
        } else {
          // Hold the finished prompt for about two seconds, then erase it.
          _typewriterDeleting = true;
          _typewriterPause = 30;
        }
      } else {
        if (_typewriterCharIndex > 0) {
          _typewriterCharIndex = math.max(0, _typewriterCharIndex - 2);
          _typewriter.value = currentPrompt.substring(0, _typewriterCharIndex);
        } else {
          _typewriterDeleting = false;
          _typewriterPromptIndex = (_typewriterPromptIndex + 1) % _typewriterPrompts.length;
          _typewriterPause = 6;
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
        _aiGlowController.repeat();
        if (!StorageService.hasSeenAiTutorial()) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _showAiTutorialOverlay());
        }
      } else {
        _typewriterTimer?.cancel();
        _typewriter.value = '';
        _aiGlowController.stop();
      }
    });
  }

  void _resetSearch() {
    _searchController.clear();
    _searchFocusNode.unfocus();
    setState(() {
      _isSearching = false;
      _isAiLoading = false;
      _allSearchResults = [];
      _filteredTracks = [];
      _currentAiPlaylistName = '';
      _recentSearches = _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
    });
  }

  void _showAiTutorialOverlay() {
    int currentStep = 0;
    Timer? autoAdvanceTimer;
    final accentColor = ref.read(customizationProvider).accentColor;

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

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 24),
              child: Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF1B1B1E) : Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: accentColor, width: 1.5),
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
                          color: i == currentStep ? accentColor : Colors.grey.withValues(alpha: 0.3),
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
                        backgroundColor: accentColor,
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

  // ═══════════════════════════════════════════════════════════════════════════
  // SEARCH LOGIC (original, unchanged except where noted)
  // ═══════════════════════════════════════════════════════════════════════════

  void _setSourceFilter(String filter) {
    if (_sourceFilter == filter) return;
    triggerHaptic(HapticFeedbackType.selection);
    setState(() {
      _sourceFilter = filter;
      _applySourceFilter();
    });
  }

  /// Applies the source filter, then the chosen sort. (Before, the sort was
  /// lost whenever the source changed, and "Popularity" could not undo an
  /// A–Z sort.)
  void _applySourceFilter() {
    if (_allSearchResults.isEmpty) {
      _filteredTracks = [];
      return;
    }
    if (_sourceFilter == 'Saavn') {
      _filteredTracks = _allSearchResults.where((t) => t.isJioSaavn).toList();
    } else if (_sourceFilter == 'YT') {
      _filteredTracks = _allSearchResults.where((t) => t.isYouTube).toList();
    } else {
      _filteredTracks = List.from(_allSearchResults);
    }

    if (_selectedSortFilter == 'Title A-Z') {
      _filteredTracks.sort((a, b) => a.title.toLowerCase().compareTo(b.title.toLowerCase()));
    } else if (_selectedSortFilter == 'Artist A-Z') {
      _filteredTracks.sort((a, b) => a.artist.toLowerCase().compareTo(b.artist.toLowerCase()));
    }
  }

  void _onSearchChanged() {
    if (_isAiMode) return;
    _debounceTimer?.cancel();
    final query = _searchController.text.trim();
    if (query.isEmpty) {
      setState(() {
        _allSearchResults = [];
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
        List<Track> results;
        try {
          results = await searchAllMusicSources(query);
        } catch (_) {
          results = await SourceManager.instance.searchTracks(query);
        }
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _allSearchResults = _deduplicateTracks(results);
            _applySourceFilter();
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

  Future<void> _executeSearchQuery(String query) async {
    if (query.trim().isEmpty) return;
    _searchController.text = query;
    _tabController.animateTo(0);

    if (_isAiMode) {
      await _executeAiSearch(query);
    } else {
      await StorageService.addSearchQuery(query);
      setState(() {
        _isSearching = true;
        _allSearchResults = [];
        _filteredTracks = [];
        _recentSearches = StorageService.getRecentSearches();
      });
      try {
        List<Track> results;
        try {
          results = await searchAllMusicSources(query);
        } catch (_) {
          results = await SourceManager.instance.searchTracks(query);
        }
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _allSearchResults = _deduplicateTracks(results);
            _applySourceFilter();
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted) {
          setState(() {
            _isSearching = false;
          });
        }
      }
    }
  }

  List<Track> _deduplicateTracks(List<Track> tracks) {
    final Map<String, Track> uniqueMap = {};
    for (final track in tracks) {
      final key = track.id.isNotEmpty
          ? track.id
          : '${track.title.toLowerCase().trim()}_${track.artist.toLowerCase().trim()}';
      if (!uniqueMap.containsKey(key)) {
        uniqueMap[key] = track;
      }
    }
    return uniqueMap.values.toList();
  }

  // The AI flow is the original. The only additions are the `_aiStage…`
  // updates, which tell the curating animation which step is running.
  Future<void> _executeAiSearch(String query) async {
    if (query.trim().isEmpty) return;
    setState(() {
      _isAiLoading = true;
      _aiLoadingText = 'Finding best match for you...';
      _aiStage = 0;
      _aiStageDetail = '';
      _aiQuery = query.trim();
      _aiQueryStep = 0;
      _aiQueryTotal = 0;
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
      if (!mounted) return;
      setState(() {
        _aiLoadingText = 'Curating your personalized tracks...';
        _aiStage = 1;
      });

      Map<String, dynamic>? parsedJson;
      try {
        final cleanText = rawResponse.substring(rawResponse.indexOf('{'), rawResponse.lastIndexOf('}') + 1);
        parsedJson = Map<String, dynamic>.from(jsonDecode(cleanText) as Map);
      } catch (_) {}

      List<String> searchQueries = [query];
      String playlistName = '$query Playlist';

      if (parsedJson != null) {
        playlistName = parsedJson['playlist_name_suggestion']?.toString() ?? playlistName;
        if (parsedJson['queries'] is List && (parsedJson['queries'] as List).isNotEmpty) {
          searchQueries = (parsedJson['queries'] as List).map((q) => q.toString()).toList();
        }
      }

      final lowerQuery = query.toLowerCase();
      if (lowerQuery.contains('punjabi') && (lowerQuery.contains('haryanvi') || lowerQuery.contains('haryanavi'))) {
        if (!searchQueries.any((q) => q.toLowerCase().contains('haryanv') || q.toLowerCase().contains('haryanav'))) {
          searchQueries.add('Top Haryanvi Songs');
        }
        if (!searchQueries.any((q) => q.toLowerCase().contains('punjabi'))) {
          searchQueries.add('Top Punjabi Songs');
        }
      }

      final trackMap = <String, Track>{};

      _aiQueryTotal = searchQueries.length;
      for (final q in searchQueries) {
        if (mounted) {
          setState(() {
            _aiStageDetail = q;
            _aiQueryStep++;
          });
        }
        try {
          List<Track> results;
          try {
            results = await searchAllMusicSources(q);
          } catch (_) {
            results = await SourceManager.instance.searchTracks(q);
          }
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

      if (mounted) {
        setState(() {
          _aiStage = 2;
          _aiStageDetail = '';
          _aiLoadingText = 'Putting your playlist together...';
        });
      }

      List<Track> resultsList = trackMap.values.toList();
      if (resultsList.isEmpty) {
        try {
          try {
            resultsList = await searchAllMusicSources(query);
          } catch (_) {
            resultsList = await SourceManager.instance.searchTracks(query);
          }
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
          _allSearchResults = resultsList;
          _applySourceFilter();
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

  Future<void> _playSearched(Track track) async {
    await StorageService.addSearchedAndPlayedTrack(track);
    ref.read(playbackProvider.notifier).playTrack(track);
  }

  void _addToQueue(Track track) {
    ref.read(playbackProvider.notifier).addToQueue(track);
    triggerHaptic(HapticFeedbackType.medium);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Added "${track.title}" to Queue 🎵'),
        duration: const Duration(seconds: 1),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String _capitalize(String text) {
    return text.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');
  }

  /// "Artist • Genre", or just the artist when there is no genre.
  String _artistLine(Track track) {
    final genre = '${track.genre}'.trim();
    return (genre.isEmpty || genre == 'null') ? track.artist : '${track.artist} • $genre';
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SHEETS
  // ═══════════════════════════════════════════════════════════════════════════

  void _showGroupSongsSheet(String tag) async {
    final accentColor = ref.read(customizationProvider).accentColor;

    List<Track> sessionTracks = StorageService.getGroupedSessionTracks(tag);

    if (sessionTracks.isEmpty) {
      try {
        final cleanTag = tag.replaceAll(RegExp(r'✨|\(\d+\s*songs\)'), '').trim();
        sessionTracks = await ref.read(musicSourceProvider).searchTracks(cleanTag);
      } catch (_) {}
    }

    if (!mounted) return;
    final messenger = ScaffoldMessenger.of(context);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;

        return Container(
          height: MediaQuery.of(sheetContext).size.height * 0.72,
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 10),
              Center(
                child: Container(
                  width: 38,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _tint(sheetContext, 0.18),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: accentColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _capitalize(tag),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${sessionTracks.length} ${sessionTracks.length == 1 ? 'song' : 'songs'}',
                            style: TextStyle(fontSize: 12.5, color: _muted(sheetContext)),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              if (sessionTracks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            ref.read(playbackProvider.notifier).playCustomQueue(sessionTracks, initialIndex: 0);
                          },
                          icon: const Icon(Icons.play_arrow_rounded, size: 22),
                          label: const Text('Play All'),
                          style: FilledButton.styleFrom(
                            backgroundColor: accentColor,
                            foregroundColor: _onColor(accentColor),
                            minimumSize: const Size(0, 48),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: () async {
                            final name = tag.replaceAll(RegExp(r'✨|\(\d+\s*songs\)'), '').trim();
                            final playlists = StorageService.getPlaylists();
                            final newPl = {
                              'id': DateTime.now().millisecondsSinceEpoch.toString(),
                              'name': name,
                              'description': 'AI generated playlist',
                              'trackIds': sessionTracks.map((t) => t.id).toList(),
                              'tracks': sessionTracks.map((t) => t.toJson()).toList(),
                            };
                            playlists.add(newPl);
                            await StorageService.savePlaylists(playlists);
                            // Close first: a snackbar would sit hidden behind the sheet.
                            if (sheetContext.mounted) Navigator.pop(sheetContext);
                            messenger.showSnackBar(
                              SnackBar(
                                content: Text('Saved "$name" to Playlists Library! ⚡'),
                                behavior: SnackBarBehavior.floating,
                              ),
                            );
                          },
                          icon: const Icon(Icons.bookmark_add_rounded, size: 19),
                          label: const Text('Save Playlist'),
                          style: FilledButton.styleFrom(
                            backgroundColor: _tint(sheetContext, 0.09),
                            foregroundColor: Theme.of(sheetContext).colorScheme.onSurface,
                            minimumSize: const Size(0, 48),
                            shape: const StadiumBorder(),
                            textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              Expanded(
                child: sessionTracks.isEmpty
                    ? Center(
                        child: Text('No saved tracks for this session', style: TextStyle(color: _muted(sheetContext))),
                      )
                    : ListView.builder(
                        physics: const BouncingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(8, 4, 8, MediaQuery.of(sheetContext).padding.bottom + 16),
                        itemCount: sessionTracks.length,
                        itemBuilder: (context, index) {
                          final track = sessionTracks[index];
                          return ListTile(
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                            leading: AppArtworkImage(
                              artworkUrl: track.artworkUrl,
                              trackId: track.id,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            title: Text(
                              track.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700),
                            ),
                            subtitle: Row(
                              children: [
                                _SourceTag(isYouTube: track.isYouTube),
                                Expanded(
                                  child: Text(
                                    _artistLine(track),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(fontSize: 12.5, color: _muted(context)),
                                  ),
                                ),
                              ],
                            ),
                            trailing: Icon(Icons.play_arrow_rounded, size: 22, color: _tint(context, 0.5)),
                            onTap: () {
                              Navigator.pop(sheetContext);
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
    final accentColor = ref.read(customizationProvider).accentColor;
    const options = [
      ('Popularity', 'As ranked by the source', Icons.trending_up_rounded),
      ('Title A-Z', 'Song name, alphabetical', Icons.sort_by_alpha_rounded),
      ('Artist A-Z', 'Artist name, alphabetical', Icons.person_rounded),
    ];

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        final isDark = Theme.of(sheetContext).brightness == Brightness.dark;

        return Container(
          decoration: BoxDecoration(
            color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
          ),
          child: SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 38,
                      height: 4,
                      decoration: BoxDecoration(
                        color: _tint(sheetContext, 0.18),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(8, 18, 8, 14),
                    child: Text(
                      'Sort Results',
                      style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                    ),
                  ),
                  for (final (filter, description, icon) in options)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: _selectedSortFilter == filter
                            ? accentColor.withValues(alpha: 0.12)
                            : _tint(sheetContext, 0.04),
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: _selectedSortFilter == filter ? accentColor : Colors.transparent,
                            width: 1.5,
                          ),
                        ),
                        child: InkWell(
                          // One tap applies it; no separate Apply step.
                          onTap: () {
                            triggerHaptic(HapticFeedbackType.selection);
                            setState(() {
                              _selectedSortFilter = filter;
                              _applySourceFilter();
                            });
                            Navigator.pop(sheetContext);
                          },
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                            child: Row(
                              children: [
                                Icon(
                                  icon,
                                  size: 21,
                                  color: _selectedSortFilter == filter ? accentColor : _muted(sheetContext),
                                ),
                                const SizedBox(width: 13),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(filter, style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w700)),
                                      const SizedBox(height: 2),
                                      Text(description, style: TextStyle(fontSize: 12, color: _muted(sheetContext))),
                                    ],
                                  ),
                                ),
                                Icon(
                                  _selectedSortFilter == filter
                                      ? Icons.check_circle_rounded
                                      : Icons.radio_button_unchecked_rounded,
                                  size: 21,
                                  color: _selectedSortFilter == filter ? accentColor : _tint(sheetContext, 0.25),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  //
  //   Fixed      search field + AI toggle · AI banner · tabs
  //   Scrolling  the selected tab
  //
  // Responsive: content is capped and centered on wide screens, song lists go
  // from one card per row to two or three, and every grid adds columns.
  // ═══════════════════════════════════════════════════════════════════════════

  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 1100;

  /// Side margin for the current screen width, set at the top of each build.
  double _side = 20;

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;

    // The search UI stays mounted underneath (so scroll positions and the
    // typed prompt survive) and the curating animation fades in over it.
    return Stack(
      fit: StackFit.expand,
      children: [
        TickerMode(
          enabled: !_isAiLoading,
          child: ExcludeSemantics(
            excluding: _isAiLoading,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _side = math.max(20.0, (constraints.maxWidth - _maxContentWidth) / 2);
                return _buildBody(context, accentColor);
              },
            ),
          ),
        ),
        Positioned.fill(
          child: IgnorePointer(
            ignoring: !_isAiLoading,
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 320),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeIn,
              layoutBuilder: (currentChild, previousChildren) {
                return Stack(
                  fit: StackFit.expand,
                  children: [
                    ...previousChildren,
                    if (currentChild != null) currentChild,
                  ],
                );
              },
              child: _isAiLoading
                  ? _AiCuratingView(
                      key: const ValueKey('ai-curating'),
                      accent: accentColor,
                      status: _aiLoadingText,
                      prompt: _aiQuery,
                      stage: _aiStage,
                      detail: _aiStageDetail,
                      step: _aiQueryStep,
                      total: _aiQueryTotal,
                    )
                  : const SizedBox.shrink(key: ValueKey('ai-idle')),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildBody(BuildContext context, Color accentColor) {
    final showBackButton =
        _searchController.text.isNotEmpty || _filteredTracks.isNotEmpty || _searchFocusNode.hasFocus || _isSearching;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(_side, MediaQuery.of(context).padding.top + 14, _side, 0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  // Back button slides in when a search is active
                  AnimatedSize(
                    duration: const Duration(milliseconds: 220),
                    curve: Curves.easeOutCubic,
                    child: showBackButton
                        ? Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: IconButton(
                              icon: const Icon(Icons.arrow_back_rounded, size: 22),
                              tooltip: 'Back to Discovery',
                              onPressed: () {
                                FocusScope.of(context).unfocus();
                                _resetSearch();
                              },
                            ),
                          )
                        : const SizedBox(height: 48),
                  ),
                  Expanded(child: _buildSearchField(accentColor)),
                  const SizedBox(width: 10),
                  _buildAiToggle(accentColor),
                ],
              ),

              // AI mode banner
              AnimatedSize(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                alignment: Alignment.topCenter,
                child: _isAiMode
                    ? Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Container(
                          padding: const EdgeInsets.fromLTRB(12, 8, 6, 8),
                          decoration: BoxDecoration(
                            color: accentColor.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: accentColor.withValues(alpha: 0.35)),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.auto_awesome_rounded, color: accentColor, size: 15),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'AI Curator · describe a mood, artist or playlist and press send',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.3,
                                    fontWeight: FontWeight.w700,
                                    color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.85),
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Turn off AI mode',
                                visualDensity: VisualDensity.compact,
                                constraints: const BoxConstraints.tightFor(width: 30, height: 30),
                                padding: EdgeInsets.zero,
                                icon: Icon(Icons.close_rounded, size: 16, color: _muted(context)),
                                onPressed: _toggleAiMode,
                              ),
                            ],
                          ),
                        ),
                      )
                    : const SizedBox(width: double.infinity),
              ),
              const SizedBox(height: 12),
              _buildTabBar(accentColor),
            ],
          ),
        ),

        // Main Tab Content Area
        Expanded(
          child: TabBarView(
            controller: _tabController,
            children: [
              _buildSongsTab(accentColor),
              _buildAlbumsTab(accentColor),
              _buildArtistsTab(accentColor),
              _buildPlaylistsTab(accentColor),
            ],
          ),
        ),
      ],
    );
  }

  // ── Search field ───────────────────────────────────────────────────────────

  Widget _buildSearchField(Color accentColor) {
    final hasFocus = _searchFocusNode.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
      height: 52,
      decoration: BoxDecoration(
        color: _isAiMode ? accentColor.withValues(alpha: 0.12) : _tint(context, 0.07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: _isAiMode
              ? accentColor.withValues(alpha: 0.35)
              : accentColor.withValues(alpha: hasFocus ? 0.55 : 0),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: accentColor.withValues(alpha: _isAiMode ? 0.24 : 0),
            blurRadius: 16,
            spreadRadius: 1,
          ),
        ],
      ),
      // In AI mode a highlight travels around the border. It is painted
      // straight from the animation, so nothing rebuilds while it runs.
      child: CustomPaint(
        foregroundPainter: _isAiMode ? _AiBorderPainter(progress: _aiGlowController, color: accentColor) : null,
        child: Row(
          children: [
            const SizedBox(width: 14),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 260),
              transitionBuilder: (child, animation) {
                return RotationTransition(
                  turns: Tween<double>(begin: 0.75, end: 1.0).animate(animation),
                  child: ScaleTransition(scale: animation, child: child),
                );
              },
              child: Icon(
                _isAiMode ? Icons.auto_awesome_rounded : Icons.search_rounded,
                key: ValueKey(_isAiMode),
                size: 21,
                color: _isAiMode ? accentColor : _muted(context),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Stack(
                alignment: Alignment.centerLeft,
                children: [
                  // Hint, hidden as soon as there is text
                  ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _searchController,
                    builder: (context, value, _) {
                      if (value.text.isNotEmpty) return const SizedBox.shrink();
                      return IgnorePointer(child: _buildHint(accentColor));
                    },
                  ),
                  TextField(
                    controller: _searchController,
                    focusNode: _searchFocusNode,
                    textInputAction: TextInputAction.search,
                    style: const TextStyle(fontSize: 14.5, fontWeight: FontWeight.w500),
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
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      isCollapsed: true,
                      contentPadding: EdgeInsets.symmetric(vertical: 15),
                    ),
                  ),
                ],
              ),
            ),
            // Clear / send, following the text as it is typed
            ValueListenableBuilder<TextEditingValue>(
              valueListenable: _searchController,
              builder: (context, value, _) {
                final hasText = value.text.trim().isNotEmpty;
                return Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (value.text.isNotEmpty)
                      IconButton(
                        tooltip: 'Clear',
                        visualDensity: VisualDensity.compact,
                        icon: Icon(Icons.clear_rounded, size: 19, color: _muted(context)),
                        onPressed: () => _searchController.clear(),
                      ),
                    if (_isAiMode)
                      Padding(
                        padding: const EdgeInsets.only(left: 2, right: 2),
                        child: AnimatedScale(
                          scale: hasText ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 180),
                          curve: Curves.easeOutBack,
                          child: Material(
                            color: accentColor,
                            shape: const CircleBorder(),
                            clipBehavior: Clip.antiAlias,
                            child: IconButton(
                              tooltip: 'Ask AI',
                              constraints: const BoxConstraints.tightFor(width: 36, height: 36),
                              padding: EdgeInsets.zero,
                              icon: Icon(Icons.arrow_upward_rounded, size: 20, color: _onColor(accentColor)),
                              onPressed: hasText
                                  ? () {
                                      FocusScope.of(context).unfocus();
                                      _executeAiSearch(_searchController.text.trim());
                                    }
                                  : null,
                            ),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }

  Widget _buildHint(Color accentColor) {
    if (!_isAiMode) {
      return Text(
        'Search songs, albums, artists...',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(fontSize: 14, color: _muted(context)),
      );
    }
    return ValueListenableBuilder<String>(
      valueListenable: _typewriter,
      builder: (context, typed, _) {
        return Text(
          typed.isEmpty ? 'Ask AI for songs or a playlist...' : 'Try "$typed"',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w500,
            color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6),
          ),
        );
      },
    );
  }

  /// The AI switch, next to the field so it is always one tap away.
  Widget _buildAiToggle(Color accentColor) {
    return Tooltip(
      message: 'Toggle AI Music Curator Mode',
      child: GestureDetector(
        onTap: _toggleAiMode,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOut,
          width: 52,
          height: 52,
          decoration: BoxDecoration(
            color: _isAiMode ? accentColor : _tint(context, 0.07),
            borderRadius: BorderRadius.circular(18),
            boxShadow: [
              BoxShadow(
                color: accentColor.withValues(alpha: _isAiMode ? 0.4 : 0),
                blurRadius: 14,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: AnimatedRotation(
            turns: _isAiMode ? 0.25 : 0,
            duration: const Duration(milliseconds: 380),
            curve: Curves.easeOutBack,
            child: Icon(
              _isAiMode ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
              size: 22,
              color: _isAiMode ? _onColor(accentColor) : _muted(context),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTabBar(Color accentColor) {
    Widget tab(String label) {
      return Tab(child: FittedBox(fit: BoxFit.scaleDown, child: Text(label, maxLines: 1)));
    }

    return Container(
      height: 46,
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: TabBar(
        controller: _tabController,
        indicator: BoxDecoration(
          color: accentColor,
          borderRadius: BorderRadius.circular(12),
          boxShadow: [
            BoxShadow(
              color: accentColor.withValues(alpha: 0.32),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        indicatorSize: TabBarIndicatorSize.tab,
        indicatorPadding: const EdgeInsets.all(4),
        labelPadding: const EdgeInsets.symmetric(horizontal: 6),
        labelColor: _onColor(accentColor),
        unselectedLabelColor: _muted(context),
        labelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
        unselectedLabelStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600, fontFamily: 'Outfit'),
        dividerColor: Colors.transparent,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        splashFactory: NoSplash.splashFactory,
        tabs: [tab('Songs'), tab('Albums'), tab('Artists'), tab('Playlists')],
      ),
    );
  }

  // ── Shared pieces ──────────────────────────────────────────────────────────

  EdgeInsets get _listPadding => EdgeInsets.fromLTRB(_side, 14, _side, 150);

  /// Cards per row for a list that is [width] wide.
  int _columnsFor(double width) {
    if (width >= 980) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  Widget _sectionTitle(String title, {IconData? icon, Color? iconColor, Widget? trailing}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          if (icon != null) ...[
            Icon(icon, size: 19, color: iconColor),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 19, fontWeight: FontWeight.w800, fontFamily: 'Outfit', letterSpacing: -0.2),
            ),
          ),
          if (trailing != null) trailing,
        ],
      ),
    );
  }

  /// A song as a card. Swipe right to add it to the queue.
  Widget _buildSwipeSongCard({
    required Key key,
    required Track track,
    required Color accentColor,
    required VoidCallback onPlay,
  }) {
    return ClipRRect(
      key: key,
      borderRadius: BorderRadius.circular(20),
      child: Dismissible(
        key: key,
        direction: DismissDirection.startToEnd,
        confirmDismiss: (direction) async {
          _addToQueue(track);
          return false;
        },
        background: Container(
          alignment: Alignment.centerLeft,
          padding: const EdgeInsets.only(left: 20),
          color: accentColor,
          child: Row(
            children: [
              Icon(Icons.queue_music_rounded, color: _onColor(accentColor)),
              const SizedBox(width: 8),
              Text(
                'Add to Queue',
                style: TextStyle(color: _onColor(accentColor), fontWeight: FontWeight.w800),
              ),
            ],
          ),
        ),
        child: Material(
          // Solid, so the swipe background stays hidden until you swipe.
          color: Color.alphaBlend(_tint(context, 0.05), Theme.of(context).scaffoldBackgroundColor),
          child: InkWell(
            onTap: onPlay,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
              child: Row(
                children: [
                  AppArtworkImage(
                    artworkUrl: track.artworkUrl,
                    trackId: track.id,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            _SourceTag(isYouTube: track.isYouTube),
                            Expanded(
                              child: Text(
                                _artistLine(track),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(fontSize: 12.5, color: _muted(context)),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: 'Play',
                    onPressed: onPlay,
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow_rounded, size: 22, color: accentColor),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Source filter (All / Saavn / YT) plus the sort button.
  Widget _buildResultsBar(Color accentColor) {
    final isSorted = _selectedSortFilter != 'Popularity';

    return Padding(
      padding: EdgeInsets.fromLTRB(_side, 12, _side, 0),
      child: Row(
        children: [
          Expanded(
            child: _SourceSegments(
              selected: _sourceFilter,
              accent: accentColor,
              showCounts: _allSearchResults.isNotEmpty,
              allCount: _allSearchResults.length,
              saavnCount: _allSearchResults.where((t) => t.isJioSaavn).length,
              ytCount: _allSearchResults.where((t) => t.isYouTube).length,
              onSelected: _setSourceFilter,
            ),
          ),
          const SizedBox(width: 10),
          Tooltip(
            message: 'Filter & Sort',
            child: Material(
              color: isSorted ? accentColor.withValues(alpha: 0.16) : _tint(context, 0.07),
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
                side: BorderSide(color: isSorted ? accentColor.withValues(alpha: 0.5) : Colors.transparent),
              ),
              child: InkWell(
                onTap: () => _showFilterBottomSheet(context),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(Icons.tune_rounded, size: 20, color: isSorted ? accentColor : _muted(context)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMessage({
    required IconData icon,
    required String title,
    String? message,
    Widget? action,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(_side + 12, 24, _side + 12, 150),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: math.max(0.0, constraints.maxHeight - 174)),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 360),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 76,
                      height: 76,
                      decoration: BoxDecoration(color: _tint(context, 0.06), shape: BoxShape.circle),
                      child: Icon(icon, size: 36, color: _muted(context)),
                    ),
                    const SizedBox(height: 18),
                    Text(
                      title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Outfit', fontSize: 19, fontWeight: FontWeight.w800),
                    ),
                    if (message != null) ...[
                      const SizedBox(height: 6),
                      Text(
                        message,
                        textAlign: TextAlign.center,
                        style: TextStyle(fontSize: 13.5, height: 1.45, color: _muted(context)),
                      ),
                    ],
                    if (action != null) ...[
                      const SizedBox(height: 18),
                      action,
                    ],
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _pillButton({
    required String label,
    required IconData icon,
    required Color accentColor,
    required VoidCallback onPressed,
  }) {
    return FilledButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: FilledButton.styleFrom(
        backgroundColor: accentColor,
        foregroundColor: _onColor(accentColor),
        minimumSize: const Size(0, 46),
        shape: const StadiumBorder(),
        textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
      ),
    );
  }

  // ── Songs tab ──────────────────────────────────────────────────────────────

  Widget _buildSongsTab(Color accentColor) {
    if (_searchController.text.isEmpty && _filteredTracks.isEmpty) {
      final isFocused = _searchFocusNode.hasFocus;

      if (isFocused) {
        return ListView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: _listPadding,
          children: [
            if (_isAiMode) ...[
              _buildAiPromptIdeas(accentColor),
              const SizedBox(height: 24),
            ],
            _buildChipSection(
              _isAiMode ? 'AI Recent Prompts' : 'Recent Searches',
              _recentSearches,
              true,
              accentColor,
            ),
            _buildTrendingSection(accentColor),
          ],
        );
      }

      final aiSessionsMap = StorageService.getGroupedAiSessionsMap();
      final historyTracks = _getHistoryTracksList();

      return ListView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        padding: const EdgeInsets.only(top: 18, bottom: 150),
        children: [
          if (aiSessionsMap.isNotEmpty) ...[
            _buildAiPlaylistGroupsSection(aiSessionsMap, accentColor),
            const SizedBox(height: 28),
          ],
          _buildTrendingArtistsCarousel(accentColor),
          const SizedBox(height: 28),
          _buildRecentlyPlayedSongsSection(historyTracks, accentColor),
        ],
      );
    }

    if (_isSearching) {
      return _SkeletonList(padding: _listPadding);
    }

    if (_filteredTracks.isEmpty) {
      if (_allSearchResults.isNotEmpty) {
        return Column(
          children: [
            _buildResultsBar(accentColor),
            Expanded(
              child: _buildMessage(
                icon: _sourceFilter == 'YT' ? Icons.smart_display_outlined : Icons.graphic_eq_rounded,
                title: 'No $_sourceFilter tracks found for this search',
                message: 'Found ${_allSearchResults.length} total songs in other sources.',
                action: _pillButton(
                  label: 'Show All (${_allSearchResults.length}) Songs',
                  icon: Icons.all_inclusive_rounded,
                  accentColor: accentColor,
                  onPressed: () => _setSourceFilter('All'),
                ),
              ),
            ),
          ],
        );
      }
      // AI mode, prompt typed but not sent yet
      if (_isAiMode && _currentAiPlaylistName.isEmpty) {
        return _buildMessage(
          icon: Icons.auto_awesome_rounded,
          title: 'Ready when you are',
          message: 'Press send and AI will build a playlist from your prompt.',
          action: _pillButton(
            label: 'Ask AI',
            icon: Icons.auto_awesome_rounded,
            accentColor: accentColor,
            onPressed: () {
              FocusScope.of(context).unfocus();
              _executeAiSearch(_searchController.text.trim());
            },
          ),
        );
      }
      return _buildMessage(
        icon: Icons.search_off_rounded,
        title: 'No tracks found',
        message: 'Try a different spelling, or search for the artist instead.',
        action: _pillButton(
          label: 'Back to Music Discovery',
          icon: Icons.explore_rounded,
          accentColor: accentColor,
          onPressed: _resetSearch,
        ),
      );
    }

    final showAiBanner = _isAiMode && _filteredTracks.isNotEmpty;
    final notifier = ref.read(playbackProvider.notifier);

    return Column(
      children: [
        _buildResultsBar(accentColor),
        Expanded(
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = _columnsFor(constraints.maxWidth - _side * 2);
              final rows = (_filteredTracks.length / columns).ceil();

              return ListView.builder(
                physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                padding: EdgeInsets.fromLTRB(_side, 12, _side, 150),
                itemCount: rows + (showAiBanner ? 1 : 0),
                itemBuilder: (context, index) {
                  if (showAiBanner && index == 0) {
                    return _buildAiPlaylistBannerCard(context, notifier, accentColor);
                  }
                  final row = showAiBanner ? index - 1 : index;
                  return _cardRow(
                    columns: columns,
                    first: row * columns,
                    itemCount: _filteredTracks.length,
                    itemBuilder: (trackIndex) {
                      final track = _filteredTracks[trackIndex];
                      return _buildSwipeSongCard(
                        key: Key('search_${track.id}_$trackIndex'),
                        track: track,
                        accentColor: accentColor,
                        onPlay: () => _playSearched(track),
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }

  /// Example prompts, shown in AI mode before anything is typed.
  Widget _buildAiPromptIdeas(Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Try asking', icon: Icons.auto_awesome_rounded, iconColor: accentColor),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            for (final prompt in _typewriterPrompts)
              Material(
                color: accentColor.withValues(alpha: 0.12),
                clipBehavior: Clip.antiAlias,
                shape: StadiumBorder(side: BorderSide(color: accentColor.withValues(alpha: 0.35))),
                child: InkWell(
                  onTap: () {
                    FocusScope.of(context).unfocus();
                    _executeSearchQuery(prompt);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
                    child: Text(
                      prompt,
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }

  // ── Albums tab ─────────────────────────────────────────────────────────────

  /// A grid that adds columns as the screen widens (about [targetWidth] each).
  Widget _adaptiveGrid({
    required Widget header,
    required int itemCount,
    required double targetWidth,
    required double Function(double tileWidth, double textScale) extentFor,
    required Widget Function(BuildContext context, int index, double tileWidth) itemBuilder,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const spacing = 14.0;
        final width = constraints.maxWidth - _side * 2;
        final columns = (width / targetWidth).floor().clamp(2, 6).toInt();
        final tileWidth = (width - spacing * (columns - 1)) / columns;
        final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;

        return CustomScrollView(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          slivers: [
            SliverPadding(
              padding: EdgeInsets.fromLTRB(_side, 18, _side, 0),
              sliver: SliverToBoxAdapter(child: header),
            ),
            SliverPadding(
              padding: EdgeInsets.fromLTRB(_side, 0, _side, 150),
              sliver: SliverGrid(
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: spacing,
                  mainAxisSpacing: spacing,
                  mainAxisExtent: extentFor(tileWidth, textScale),
                ),
                delegate: SliverChildBuilderDelegate(
                  (context, index) => itemBuilder(context, index, tileWidth),
                  childCount: itemCount,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildAlbumsTab(Color accentColor) {
    if (_isSearching) {
      return _SkeletonList(padding: _listPadding);
    }

    final Map<String, List<Track>> albumsMap = {};
    for (final track in _filteredTracks) {
      final albumName = track.album.trim().isNotEmpty ? track.album.trim() : 'Singles';
      albumsMap.putIfAbsent(albumName, () => []).add(track);
    }

    if (albumsMap.isEmpty) {
      return _adaptiveGrid(
        header: _sectionTitle('Top Albums & Collections'),
        itemCount: _genreCards.length,
        targetWidth: 170,
        extentFor: (tileWidth, textScale) => math.max(118.0, 76 + 44 * textScale),
        itemBuilder: (context, index, tileWidth) {
          final card = _genreCards[index];
          return Material(
            color: Colors.transparent,
            clipBehavior: Clip.antiAlias,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: card['colors'] as List<Color>,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: InkWell(
                onTap: () => _executeSearchQuery(card['query'] as String),
                child: Stack(
                  children: [
                    Positioned(
                      right: -10,
                      top: -10,
                      child: Icon(
                        card['icon'] as IconData,
                        size: 72,
                        color: Colors.white.withValues(alpha: 0.22),
                      ),
                    ),
                    Positioned(
                      left: 14,
                      right: 14,
                      bottom: 12,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            card['title'] as String,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontFamily: 'Outfit',
                              fontWeight: FontWeight.w800,
                              fontSize: 15.5,
                              height: 1.15,
                            ),
                          ),
                          const SizedBox(height: 2),
                          const Text('Top Album Mix', style: TextStyle(color: Colors.white70, fontSize: 11.5)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      );
    }

    final albumNames = albumsMap.keys.toList();

    return _adaptiveGrid(
      header: _sectionTitle('Found ${albumNames.length} Albums'),
      itemCount: albumNames.length,
      targetWidth: 170,
      extentFor: (tileWidth, textScale) => tileWidth + 10 + 40 * textScale,
      itemBuilder: (context, index, tileWidth) {
        final albumName = albumNames[index];
        final tracks = albumsMap[albumName]!;
        final firstTrack = tracks.first;

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _executeSearchQuery(albumName),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AppArtworkImage(
                artworkUrl: firstTrack.artworkUrl,
                trackId: firstTrack.id,
                width: tileWidth,
                height: tileWidth,
                fit: BoxFit.cover,
                borderRadius: BorderRadius.circular(22),
              ),
              const SizedBox(height: 10),
              Text(
                albumName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              const SizedBox(height: 2),
              Text(
                '${firstTrack.artist} • ${tracks.length} songs',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 12, color: _muted(context)),
              ),
            ],
          ),
        );
      },
    );
  }

  // ── Artists tab ────────────────────────────────────────────────────────────

  Widget _artistCard({
    required Widget avatar,
    required String name,
    required String subtitle,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
          child: Row(
            children: [
              avatar,
              const SizedBox(width: 13),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                  ],
                ),
              ),
              trailing ?? Icon(Icons.chevron_right_rounded, size: 22, color: _tint(context, 0.3)),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }

  Widget _initialAvatar(String name, Color accentColor, double size) {
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accentColor.withValues(alpha: 0.38), accentColor.withValues(alpha: 0.14)],
        ),
      ),
      child: Text(
        name.isEmpty ? '?' : name.substring(0, 1),
        style: TextStyle(
          fontFamily: 'Outfit',
          fontWeight: FontWeight.w800,
          color: accentColor,
          fontSize: size * 0.38,
        ),
      ),
    );
  }

  Widget _buildArtistsTab(Color accentColor) {
    if (_isSearching) {
      return _SkeletonList(padding: _listPadding);
    }

    final Map<String, List<Track>> artistsMap = {};
    for (final track in _filteredTracks) {
      final artistName = track.artist.split(',').first.trim();
      if (artistName.isNotEmpty) {
        artistsMap.putIfAbsent(artistName, () => []).add(track);
      }
    }

    final hasResults = artistsMap.isNotEmpty;
    final names = hasResults ? artistsMap.keys.toList() : _trendingArtists;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - _side * 2);
        final rows = (names.length / columns).ceil();

        return ListView.builder(
          physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
          padding: EdgeInsets.fromLTRB(_side, 18, _side, 150),
          itemCount: rows + 1,
          itemBuilder: (context, index) {
            if (index == 0) {
              return _sectionTitle(hasResults ? 'Found ${names.length} Artists' : 'Popular Artists');
            }
            return _cardRow(
              columns: columns,
              first: (index - 1) * columns,
              itemCount: names.length,
              itemBuilder: (i) {
                final artistName = names[i];

                if (!hasResults) {
                  return _artistCard(
                    avatar: _initialAvatar(artistName, accentColor, 52),
                    name: artistName,
                    subtitle: 'Artist • Top Hits Available',
                    onTap: () => _executeSearchQuery(artistName),
                  );
                }

                final tracks = artistsMap[artistName]!;
                final sampleTrack = tracks.first;

                return _artistCard(
                  avatar: AppArtworkImage(
                    artworkUrl: sampleTrack.artworkUrl,
                    trackId: sampleTrack.id,
                    width: 52,
                    height: 52,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(26),
                  ),
                  name: artistName,
                  subtitle: '${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'} in search result',
                  onTap: () => _executeSearchQuery(artistName),
                  trailing: IconButton(
                    tooltip: 'Play',
                    onPressed: () {
                      ref.read(playbackProvider.notifier).playCustomQueue(tracks, initialIndex: 0);
                    },
                    icon: Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.16),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(Icons.play_arrow_rounded, size: 22, color: accentColor),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Playlists tab ──────────────────────────────────────────────────────────

  Widget _buildPlaylistsTab(Color accentColor) {
    if (_isSearching) {
      return _SkeletonList(padding: _listPadding);
    }

    final aiSessionsMap = StorageService.getGroupedAiSessionsMap();

    if (aiSessionsMap.isEmpty) {
      return _buildMessage(
        icon: Icons.auto_awesome_outlined,
        title: 'No AI Playlists Yet',
        message: 'Switch to AI Curator mode and type any mood or genre to create custom playlists!',
        action: _pillButton(
          label: 'Try AI Curator',
          icon: Icons.auto_awesome_rounded,
          accentColor: accentColor,
          onPressed: _toggleAiMode,
        ),
      );
    }

    final keys = aiSessionsMap.keys.toList();

    return _adaptiveGrid(
      header: _sectionTitle('AI Curated Playlists', icon: Icons.auto_awesome_rounded, iconColor: accentColor),
      itemCount: keys.length,
      targetWidth: 170,
      extentFor: (tileWidth, textScale) => tileWidth + 10 + 40 * textScale,
      itemBuilder: (context, index, tileWidth) {
        return _buildAiPlaylistTile(aiSessionsMap, keys[index], tileWidth, accentColor);
      },
    );
  }

  /// Cover (first song's artwork), name and song count for one AI playlist.
  Widget _buildAiPlaylistTile(Map<String, dynamic> aiSessionsMap, String key, double size, Color accentColor) {
    final rawTracks = aiSessionsMap[key] as List?;
    final count = rawTracks?.length ?? 0;
    final firstTrackMap =
        (rawTracks != null && rawTracks.isNotEmpty) ? Map<String, dynamic>.from(rawTracks.first as Map) : null;
    final artUrl = firstTrackMap?['artworkUrl']?.toString() ?? '';
    final trackId = firstTrackMap?['id']?.toString() ?? '';

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _showGroupSongsSheet(key),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Stack(
            children: [
              artUrl.isNotEmpty
                  ? AppArtworkImage(
                      artworkUrl: artUrl,
                      trackId: trackId,
                      width: size,
                      height: size,
                      fit: BoxFit.cover,
                      borderRadius: BorderRadius.circular(22),
                    )
                  : Container(
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [accentColor.withValues(alpha: 0.4), accentColor.withValues(alpha: 0.14)],
                        ),
                        borderRadius: BorderRadius.circular(22),
                      ),
                      child: Icon(Icons.auto_awesome_rounded, color: accentColor, size: size * 0.3),
                    ),
              // "AI" mark
              Positioned(
                left: 8,
                top: 8,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(100),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.auto_awesome_rounded, size: 11, color: Colors.white),
                      SizedBox(width: 3),
                      Text('AI', style: TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w800)),
                    ],
                  ),
                ),
              ),
              Positioned(
                right: 8,
                bottom: 8,
                child: Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: accentColor,
                    shape: BoxShape.circle,
                    boxShadow: const [BoxShadow(color: Colors.black38, blurRadius: 8, offset: Offset(0, 2))],
                  ),
                  child: Icon(Icons.play_arrow_rounded, color: _onColor(accentColor), size: 22),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            _capitalize(key),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
          ),
          const SizedBox(height: 2),
          Text(
            '$count ${count == 1 ? 'song' : 'songs'} · AI Playlist',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 12, color: _muted(context)),
          ),
        ],
      ),
    );
  }

  // ── Discovery sections ─────────────────────────────────────────────────────

  Widget _buildTrendingSection(Color accentColor) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionTitle('Trending Searches'),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _trendingArtists.map((artist) {
            return Material(
              color: _tint(context, 0.06),
              clipBehavior: Clip.antiAlias,
              shape: StadiumBorder(side: BorderSide(color: _tint(context, 0.07))),
              child: InkWell(
                onTap: () => _executeSearchQuery(artist),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.trending_up_rounded, size: 15, color: accentColor),
                      const SizedBox(width: 6),
                      Text(artist, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildTrendingArtistsCarousel(Color accentColor) {
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _side),
          child: _sectionTitle('Trending Artists'),
        ),
        SizedBox(
          height: 68 + 8 + 32 * textScale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: _side),
            itemCount: _trendingArtists.length,
            separatorBuilder: (context, index) => const SizedBox(width: 12),
            itemBuilder: (context, index) {
              final artist = _trendingArtists[index];
              return GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _executeSearchQuery(artist),
                child: SizedBox(
                  width: 78,
                  child: Column(
                    children: [
                      _initialAvatar(artist, accentColor, 68),
                      const SizedBox(height: 8),
                      Text(
                        artist,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, height: 1.2),
                      ),
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

  Widget _buildAiPlaylistBannerCard(BuildContext context, PlaybackNotifier notifier, Color accentColor) {
    final playlistTitle = _currentAiPlaylistName.isEmpty
        ? '${_searchController.text.trim()} Playlist'
        : _currentAiPlaylistName;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [accentColor.withValues(alpha: 0.26), accentColor.withValues(alpha: 0.05)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: accentColor.withValues(alpha: 0.32), width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(color: accentColor, borderRadius: BorderRadius.circular(13)),
                  child: Icon(Icons.auto_awesome_rounded, color: _onColor(accentColor), size: 21),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        playlistTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 17, fontFamily: 'Outfit'),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${_filteredTracks.length} Tracks · curated by AI',
                        style: TextStyle(fontSize: 12.5, color: _muted(context)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      notifier.playCustomQueue(_filteredTracks, initialIndex: 0);
                    },
                    icon: const Icon(Icons.play_arrow_rounded, size: 22),
                    label: const Text('Play All'),
                    style: FilledButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: _onColor(accentColor),
                      minimumSize: const Size(0, 46),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
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
                    icon: const Icon(Icons.bookmark_add_rounded, size: 19),
                    label: const Text('Save / Edit'),
                    style: FilledButton.styleFrom(
                      backgroundColor: _tint(context, 0.09),
                      foregroundColor: Theme.of(context).colorScheme.onSurface,
                      minimumSize: const Size(0, 46),
                      shape: const StadiumBorder(),
                      textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChipSection(String title, List<String> items, bool isRecent, Color accentColor) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            title,
            trailing: isRecent
                ? TextButton(
                    onPressed: () async {
                      if (_isAiMode) {
                        await StorageService.clearAiSearchHistory();
                      } else {
                        await StorageService.clearSearchHistory();
                      }
                      setState(() {
                        _recentSearches =
                            _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
                      });
                    },
                    style: TextButton.styleFrom(
                      foregroundColor: _muted(context),
                      minimumSize: const Size(0, 32),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: const Text('Clear All', style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
                  )
                : null,
          ),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map((tag) {
              return Material(
                color: _tint(context, 0.06),
                clipBehavior: Clip.antiAlias,
                shape: StadiumBorder(side: BorderSide(color: _tint(context, 0.07))),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Wrap gives each chip at most the row width, so long
                    // prompts shorten with "…" instead of overflowing.
                    Flexible(
                      child: InkWell(
                        onTap: () => _executeSearchQuery(tag),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(12, 9, 6, 9),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _isAiMode ? Icons.auto_awesome_rounded : Icons.history_rounded,
                                size: 15,
                                color: _isAiMode ? accentColor : _muted(context),
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  tag,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () async {
                        if (_isAiMode) {
                          final list = StorageService.getAiRecentSearches()..remove(tag);
                          await StorageService.saveSetting('ai_searches', list);
                        } else {
                          final list = StorageService.getRecentSearches()..remove(tag);
                          await StorageService.saveSetting('searches', list);
                        }
                        setState(() {
                          _recentSearches =
                              _isAiMode ? StorageService.getAiRecentSearches() : StorageService.getRecentSearches();
                        });
                      },
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(6, 9, 11, 9),
                        child: Icon(Icons.close_rounded, size: 15, color: _muted(context)),
                      ),
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

  Widget _buildAiPlaylistGroupsSection(Map<String, dynamic> aiSessionsMap, Color accentColor) {
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final keys = aiSessionsMap.keys.toList();
    const size = 140.0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: _side),
          child: _sectionTitle('AI Playlist Groups', icon: Icons.auto_awesome_rounded, iconColor: accentColor),
        ),
        SizedBox(
          height: size + 10 + 40 * textScale,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: _side),
            itemCount: keys.length,
            separatorBuilder: (context, index) => const SizedBox(width: 14),
            itemBuilder: (context, index) {
              return SizedBox(
                width: size,
                child: _buildAiPlaylistTile(aiSessionsMap, keys[index], size, accentColor),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildRecentlyPlayedSongsSection(List<Track> historyTracks, Color accentColor) {
    if (historyTracks.isEmpty) {
      return Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: _tint(context, 0.06), shape: BoxShape.circle),
              child: Icon(Icons.search_rounded, size: 36, color: _muted(context)),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for your favorite songs & artists',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _muted(context)),
            ),
          ],
        ),
      );
    }

    final notifier = ref.read(playbackProvider.notifier);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = _columnsFor(constraints.maxWidth - _side * 2);

        return Padding(
          padding: EdgeInsets.symmetric(horizontal: _side),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionTitle('Recently Played Songs'),
              for (var first = 0; first < historyTracks.length; first += columns)
                _cardRow(
                  columns: columns,
                  first: first,
                  itemCount: historyTracks.length,
                  itemBuilder: (index) {
                    final track = historyTracks[index];
                    return _buildSwipeSongCard(
                      key: Key('recent_swipe_${track.id}_$index'),
                      track: track,
                      accentColor: accentColor,
                      onPlay: () => notifier.playTrack(track),
                    );
                  },
                ),
            ],
          ),
        );
      },
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

/// White in dark mode, black in light mode, at the given opacity.
Color _tint(BuildContext context, double alpha) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  return (isDark ? Colors.white : Colors.black).withValues(alpha: alpha);
}

Color _muted(BuildContext context) {
  return Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);
}

/// Readable text/icon color on top of [background] (any accent the user picks).
Color _onColor(Color background) {
  return ThemeData.estimateBrightnessForColor(background) == Brightness.dark
      ? Colors.white
      : Colors.black;
}

/// One row of up to [columns] cards, starting at item [first]. No fixed
/// heights, so cards grow with the system font size.
Widget _cardRow({
  required int columns,
  required int first,
  required int itemCount,
  required Widget Function(int index) itemBuilder,
}) {
  return Padding(
    padding: const EdgeInsets.only(bottom: 10),
    child: columns == 1
        ? itemBuilder(first)
        : Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var column = 0; column < columns; column++) ...[
                if (column > 0) const SizedBox(width: 10),
                Expanded(
                  child: first + column < itemCount ? itemBuilder(first + column) : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// "YT" / "Saavn" mark in front of the artist name.
class _SourceTag extends StatelessWidget {
  const _SourceTag({required this.isYouTube});

  final bool isYouTube;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final color = isYouTube
        ? (isDark ? const Color(0xFFFF6B6B) : const Color(0xFFD32F2F))
        : (isDark ? const Color(0xFF00D1B2) : const Color(0xFF00897B));

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      margin: const EdgeInsets.only(right: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        isYouTube ? 'YT' : 'Saavn',
        style: TextStyle(color: color, fontSize: 9.5, fontWeight: FontWeight.w800, letterSpacing: 0.4, height: 1.3),
      ),
    );
  }
}

/// All / Saavn / YT, with a pill that slides (and changes color) between them.
class _SourceSegments extends StatelessWidget {
  const _SourceSegments({
    required this.selected,
    required this.accent,
    required this.showCounts,
    required this.allCount,
    required this.saavnCount,
    required this.ytCount,
    required this.onSelected,
  });

  final String selected;
  final Color accent;
  final bool showCounts;
  final int allCount;
  final int saavnCount;
  final int ytCount;
  final ValueChanged<String> onSelected;

  static const Color _saavn = Color(0xFF00D1B2);
  static const Color _youtube = Color(0xFFFF0033);

  @override
  Widget build(BuildContext context) {
    final segments = [
      ('All', 'All', Icons.all_inclusive_rounded, accent, allCount),
      ('Saavn', 'Saavn', Icons.graphic_eq_rounded, _saavn, saavnCount),
      ('YT', 'YT', Icons.smart_display_rounded, _youtube, ytCount),
    ];
    var index = segments.indexWhere((s) => s.$1 == selected);
    if (index < 0) index = 0;
    final activeColor = segments[index].$4;

    return Container(
      height: 44,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Stack(
        children: [
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 240),
              curve: Curves.easeOutCubic,
              alignment: Alignment(-1 + index.toDouble(), 0),
              child: FractionallySizedBox(
                widthFactor: 1 / 3,
                heightFactor: 1,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 240),
                  decoration: BoxDecoration(
                    color: activeColor,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: activeColor.withValues(alpha: 0.32),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Row(
            children: [
              for (var i = 0; i < segments.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == index,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(segments[i].$1),
                      child: Center(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 6),
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            child: _label(context, segments[i], i == index),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _label(BuildContext context, (String, String, IconData, Color, int) segment, bool isSelected) {
    final foreground = isSelected ? _onColor(segment.$4) : _muted(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(segment.$3, size: 15, color: foreground),
        const SizedBox(width: 5),
        Text(
          segment.$2,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontFamily: 'Outfit',
            color: foreground,
          ),
        ),
        if (showCounts) ...[
          const SizedBox(width: 5),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
            decoration: BoxDecoration(
              color: foreground.withValues(alpha: 0.16),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${segment.$5}',
              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: foreground),
            ),
          ),
        ],
      ],
    );
  }
}

/// Placeholder cards that gently pulse while results load.
class _SkeletonList extends StatefulWidget {
  const _SkeletonList({required this.padding});

  final EdgeInsets padding;

  @override
  State<_SkeletonList> createState() => _SkeletonListState();
}

class _SkeletonListState extends State<_SkeletonList> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 950))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = _tint(context, 0.09);

    Widget bar(double widthFactor, double height) {
      return FractionallySizedBox(
        widthFactor: widthFactor,
        child: Container(
          height: height,
          decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(6)),
        ),
      );
    }

    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1.0).animate(CurvedAnimation(parent: _pulse, curve: Curves.easeInOut)),
      child: ListView.builder(
        physics: const NeverScrollableScrollPhysics(),
        padding: widget.padding,
        itemCount: 8,
        itemBuilder: (context, index) {
          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _tint(context, 0.045),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  Container(
                    width: 52,
                    height: 52,
                    decoration: BoxDecoration(color: block, borderRadius: BorderRadius.circular(14)),
                  ),
                  const SizedBox(width: 13),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Varied widths read as text rather than stripes.
                        bar(index.isEven ? 0.62 : 0.48, 13),
                        const SizedBox(height: 9),
                        bar(index.isEven ? 0.38 : 0.55, 11),
                      ],
                    ),
                  ),
                  const SizedBox(width: 12),
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(color: block, shape: BoxShape.circle),
                  ),
                  const SizedBox(width: 6),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

/// A highlight that travels around the search field's border in AI mode.
class _AiBorderPainter extends CustomPainter {
  _AiBorderPainter({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect.deflate(0.75), const Radius.circular(18));
    final bright = Color.lerp(color, Colors.white, 0.55)!;

    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8
      ..shader = SweepGradient(
        colors: [
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
          color,
          bright,
          color,
          color.withValues(alpha: 0),
          color.withValues(alpha: 0),
        ],
        stops: const [0.0, 0.55, 0.72, 0.8, 0.88, 0.97, 1.0],
        transform: GradientRotation(progress.value * math.pi * 2),
      ).createShader(rect);

    canvas.drawRRect(shape, paint);
  }

  @override
  bool shouldRepaint(covariant _AiBorderPainter oldDelegate) => oldDelegate.color != color;
}

// ═════════════════════════════════════════════════════════════════════════════
// AI CURATING ANIMATION
//
// Shown while the AI builds a playlist: an orb with orbiting sparks, the
// prompt, and three steps that tick off as the real work moves along
// (understanding the request → searching each query → building the list).
// ═════════════════════════════════════════════════════════════════════════════

class _AiCuratingView extends StatefulWidget {
  const _AiCuratingView({
    super.key,
    required this.accent,
    required this.status,
    required this.prompt,
    required this.stage,
    required this.detail,
    required this.step,
    required this.total,
  });

  final Color accent;

  /// Plain status line, read out by screen readers as it changes.
  final String status;
  final String prompt;

  /// 0 understanding · 1 searching · 2 building.
  final int stage;

  /// The search term being looked up right now (stage 1).
  final String detail;
  final int step;
  final int total;

  @override
  State<_AiCuratingView> createState() => _AiCuratingViewState();
}

class _AiCuratingViewState extends State<_AiCuratingView> with SingleTickerProviderStateMixin {
  late final AnimationController _loop;

  static const List<String> _stageLabels = [
    'Understanding your request',
    'Searching the music catalog',
    'Putting your playlist together',
  ];

  @override
  void initState() {
    super.initState();
    _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 4200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Hold still when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _loop.stop();
      _loop.value = 0.2;
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    return Material(
      color: Theme.of(context).scaffoldBackgroundColor,
      child: Semantics(
        liveRegion: true,
        label: widget.status,
        child: _buildContent(context, accent),
      ),
    );
  }

  Widget _buildContent(BuildContext context, Color accent) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // The orb shrinks on short screens so the steps always fit.
        final orbSize = (constraints.maxHeight * 0.3).clamp(120.0, 200.0).toDouble();

        return SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(28, MediaQuery.of(context).padding.top + 24, 28, 150),
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: math.max(0.0, constraints.maxHeight - MediaQuery.of(context).padding.top - 174),
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 380),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    SizedBox(
                      width: orbSize,
                      height: orbSize,
                      child: RepaintBoundary(
                        child: CustomPaint(
                          painter: _AiOrbPainter(progress: _loop, color: accent),
                          child: Center(
                            child: ScaleTransition(
                              scale: TweenSequence<double>([
                                TweenSequenceItem(tween: Tween(begin: 0.92, end: 1.08), weight: 1),
                                TweenSequenceItem(tween: Tween(begin: 1.08, end: 0.92), weight: 1),
                              ]).animate(_loop),
                              child: Icon(
                                Icons.auto_awesome_rounded,
                                size: orbSize * 0.2,
                                color: _onColor(accent),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 26),
                    const Text(
                      'Curating your playlist',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontFamily: 'Outfit', fontSize: 23, fontWeight: FontWeight.w900, letterSpacing: -0.3),
                    ),
                    if (widget.prompt.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Text(
                        '"${widget.prompt}"',
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 14, height: 1.4, fontStyle: FontStyle.italic, color: _muted(context)),
                      ),
                    ],
                    const SizedBox(height: 26),
                    Container(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      decoration: BoxDecoration(
                        color: _tint(context, 0.045),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(color: _tint(context, 0.06)),
                      ),
                      child: Column(
                        children: [
                          for (var i = 0; i < _stageLabels.length; i++)
                            _AiStageRow(
                              label: _stageLabels[i],
                              detail: (i == 1 && widget.stage == 1 && widget.detail.isNotEmpty)
                                  ? (widget.total > 1
                                      ? '"${widget.detail}" · ${widget.step} of ${widget.total}'
                                      : '"${widget.detail}"')
                                  : null,
                              isDone: i < widget.stage,
                              isActive: i == widget.stage,
                              accent: accent,
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _AiStageRow extends StatelessWidget {
  const _AiStageRow({
    required this.label,
    required this.detail,
    required this.isDone,
    required this.isActive,
    required this.accent,
  });

  final String label;
  final String? detail;
  final bool isDone;
  final bool isActive;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    final Widget marker;
    if (isDone) {
      marker = Icon(Icons.check_circle_rounded, key: const ValueKey('done'), size: 22, color: accent);
    } else if (isActive) {
      marker = SizedBox(
        key: const ValueKey('active'),
        width: 18,
        height: 18,
        child: CircularProgressIndicator(strokeWidth: 2.4, color: accent),
      );
    } else {
      marker = Icon(Icons.circle_outlined, key: const ValueKey('pending'), size: 16, color: _tint(context, 0.25));
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 9),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 24,
            height: 22,
            child: Center(
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 280),
                transitionBuilder: (child, animation) => ScaleTransition(scale: animation, child: child),
                child: marker,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AnimatedDefaultTextStyle(
                  duration: const Duration(milliseconds: 250),
                  style: TextStyle(
                    fontSize: 14.5,
                    height: 1.5,
                    fontWeight: isActive ? FontWeight.w800 : FontWeight.w600,
                    color: (isDone || isActive)
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.45),
                  ),
                  child: Text(label),
                ),
                // The term being searched, swapping as each one starts
                AnimatedSize(
                  duration: const Duration(milliseconds: 220),
                  alignment: Alignment.topLeft,
                  child: detail == null
                      ? const SizedBox(width: double.infinity)
                      : Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 220),
                            layoutBuilder: (currentChild, previousChildren) {
                              return Stack(
                                alignment: Alignment.centerLeft,
                                children: [
                                  ...previousChildren,
                                  if (currentChild != null) currentChild,
                                ],
                              );
                            },
                            child: Text(
                              detail!,
                              key: ValueKey(detail),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 12.5, color: _muted(context)),
                            ),
                          ),
                        ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Glowing core, three tilted orbits with a spark on each, and twinkles.
/// Every speed is a whole number of turns per loop, so the loop is seamless.
class _AiOrbPainter extends CustomPainter {
  _AiOrbPainter({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.shortestSide / 2;
    final breathe = math.sin(t * math.pi * 2);
    final bright = Color.lerp(color, Colors.white, 0.5)!;

    // Halo
    final haloRadius = radius * (0.92 + 0.05 * breathe);
    canvas.drawCircle(
      center,
      haloRadius,
      Paint()
        ..shader = RadialGradient(
          colors: [color.withValues(alpha: 0.34), color.withValues(alpha: 0.08), color.withValues(alpha: 0)],
          stops: const [0.0, 0.55, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: haloRadius)),
    );

    // Orbits
    const tilts = [0.0, math.pi / 3, -math.pi / 3];
    const speeds = [1, 2, 1];
    const phases = [0.0, 0.35, 0.7];
    final orbitA = radius * 0.86;
    final orbitB = radius * 0.34;

    for (var i = 0; i < tilts.length; i++) {
      canvas.save();
      canvas.translate(center.dx, center.dy);
      canvas.rotate(tilts[i]); // the rings stay put; only the sparks travel
      canvas.drawOval(
        Rect.fromCenter(center: Offset.zero, width: orbitA * 2, height: orbitB * 2),
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.1
          ..color = color.withValues(alpha: 0.26),
      );

      final angle = (t * speeds[i] + phases[i]) * math.pi * 2;
      final spark = Offset(math.cos(angle) * orbitA, math.sin(angle) * orbitB);
      // Fades slightly at the back of the orbit for a sense of depth.
      final depth = 0.65 + 0.35 * math.sin(angle);
      canvas.drawCircle(
        spark,
        radius * 0.085,
        Paint()
          ..color = color.withValues(alpha: 0.28 * depth)
          ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6),
      );
      canvas.drawCircle(spark, radius * 0.038, Paint()..color = bright.withValues(alpha: 0.55 + 0.45 * depth));
      canvas.restore();
    }

    // Core
    final coreRadius = radius * (0.3 + 0.018 * breathe);
    canvas.drawCircle(
      center,
      coreRadius * 1.25,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 14),
    );
    canvas.drawCircle(
      center,
      coreRadius,
      Paint()
        ..shader = RadialGradient(
          center: const Alignment(-0.35, -0.4),
          colors: [bright, color],
        ).createShader(Rect.fromCircle(center: center, radius: coreRadius)),
    );

    // Twinkles: four-point stars that swell and fade in turn
    const twinkles = [
      Offset(-0.78, -0.56),
      Offset(0.7, -0.72),
      Offset(0.86, 0.5),
      Offset(-0.62, 0.74),
      Offset(0.1, -0.94),
    ];
    for (var i = 0; i < twinkles.length; i++) {
      final wave = math.sin((t * 2 + i / twinkles.length) * math.pi * 2);
      if (wave <= 0) continue;
      final position = center + Offset(twinkles[i].dx * radius, twinkles[i].dy * radius);
      final arm = radius * 0.07 * wave;
      final star = Path()
        ..moveTo(position.dx, position.dy - arm)
        ..quadraticBezierTo(position.dx, position.dy, position.dx + arm, position.dy)
        ..quadraticBezierTo(position.dx, position.dy, position.dx, position.dy + arm)
        ..quadraticBezierTo(position.dx, position.dy, position.dx - arm, position.dy)
        ..quadraticBezierTo(position.dx, position.dy, position.dx, position.dy - arm)
        ..close();
      canvas.drawPath(star, Paint()..color = bright.withValues(alpha: 0.9 * wave));
    }
  }

  @override
  bool shouldRepaint(covariant _AiOrbPainter oldDelegate) => oldDelegate.color != color;
}