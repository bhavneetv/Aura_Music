import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/music_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../services/ai/ai_service.dart';
import '../../widgets/ai_search_loading.dart';
import '../../widgets/app_artwork_image.dart';
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
  String _selectedSortFilter = 'Popularity';

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

  void _onSearchChanged() {
    if (_isAiMode) return;
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
            _filteredTracks = _deduplicateTracks(results);
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
        _filteredTracks = [];
        _recentSearches = StorageService.getRecentSearches();
      });
      try {
        final results = await ref.read(musicSourceProvider).searchTracks(query);
        if (mounted && _searchController.text.trim() == query) {
          setState(() {
            _filteredTracks = _deduplicateTracks(results);
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
    final accentColor = ref.read(customizationProvider).accentColor;

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
                  Icon(Icons.star_rounded, color: accentColor, size: 22),
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
                            backgroundColor: accentColor,
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
                            side: BorderSide(color: accentColor),
                            foregroundColor: accentColor,
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
                            leading: AppArtworkImage(
                              artworkUrl: track.artworkUrl,
                              trackId: track.id,
                              width: 44,
                              height: 44,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(8),
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
    final accentColor = ref.read(customizationProvider).accentColor;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF171717) : const Color(0xFFFAF8F5),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
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
                  const SizedBox(height: 20),
                  const Text('Filter & Sort Results', style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
                  const SizedBox(height: 16),
                  const Text('Sort By', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: ['Popularity', 'Title A-Z', 'Artist A-Z'].map((filter) {
                      final isSelected = _selectedSortFilter == filter;
                      return ChoiceChip(
                        label: Text(filter),
                        selected: isSelected,
                        selectedColor: accentColor.withValues(alpha: 0.2),
                        checkmarkColor: accentColor,
                        labelStyle: TextStyle(
                          color: isSelected ? accentColor : Colors.grey,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        ),
                        onSelected: (val) {
                          setModalState(() => _selectedSortFilter = filter);
                          setState(() {
                            _selectedSortFilter = filter;
                            if (filter == 'Title A-Z') {
                              _filteredTracks.sort((a, b) => a.title.compareTo(b.title));
                            } else if (filter == 'Artist A-Z') {
                              _filteredTracks.sort((a, b) => a.artist.compareTo(b.artist));
                            }
                          });
                        },
                      );
                    }).toList(),
                  ),
                  const SizedBox(height: 24),
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: accentColor,
                      foregroundColor: isDark ? Colors.black : Colors.white,
                      minimumSize: const Size(double.infinity, 48),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: const Text('Apply Filters', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final customBranding = ref.watch(customizationProvider);
    final accentColor = customBranding.accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (_isAiLoading) {
      return Scaffold(
        body: AiSearchLoading(statusText: _aiLoadingText),
      );
    }

    final showBackButton = _searchController.text.isNotEmpty || _filteredTracks.isNotEmpty || _searchFocusNode.hasFocus || _isSearching;

    return Column(
      children: [
        // Premium Header & Search Bar Container
        Padding(
          padding: EdgeInsets.only(left: 20, right: 20, top: MediaQuery.of(context).padding.top + 8, bottom: 8),
          child: Column(
            children: [
              Row(
                children: [
                  if (showBackButton) ...[
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded, size: 22),
                      tooltip: 'Back to Discovery',
                      onPressed: () {
                        FocusScope.of(context).unfocus();
                        _resetSearch();
                      },
                    ),
                    const SizedBox(width: 4),
                  ],
                  Expanded(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: 52,
                      decoration: BoxDecoration(
                        color: _isAiMode
                            ? accentColor.withValues(alpha: 0.12)
                            : (isDark ? Colors.white.withValues(alpha: 0.07) : Colors.black.withValues(alpha: 0.04)),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(
                          color: _isAiMode ? accentColor : (_searchFocusNode.hasFocus ? accentColor.withValues(alpha: 0.5) : Colors.transparent),
                          width: 1.5,
                        ),
                        boxShadow: _isAiMode
                            ? [BoxShadow(color: accentColor.withValues(alpha: 0.25), blurRadius: 12, spreadRadius: 1)]
                            : null,
                      ),
                      child: TextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
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
                            color: _isAiMode ? accentColor.withValues(alpha: 0.8) : Colors.grey,
                          ),
                          prefixIcon: Icon(
                            _isAiMode ? Icons.auto_awesome_rounded : Icons.search_rounded,
                            size: 20,
                            color: _isAiMode ? accentColor : Colors.grey,
                          ),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              if (_searchController.text.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 18),
                                  onPressed: () => _searchController.clear(),
                                ),
                              if (_filteredTracks.isNotEmpty)
                                IconButton(
                                  icon: const Icon(Icons.tune_rounded, size: 18),
                                  tooltip: 'Filter & Sort',
                                  onPressed: () => _showFilterBottomSheet(context),
                                ),
                              IconButton(
                                icon: Icon(
                                  _isAiMode ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                                  color: _isAiMode ? accentColor : Colors.grey,
                                  size: 20,
                                ),
                                tooltip: 'Toggle AI Music Curator Mode',
                                onPressed: _toggleAiMode,
                              ),
                            ],
                          ),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // AI Mode Pill Banner
              if (_isAiMode)
                AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: accentColor.withValues(alpha: 0.4)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.auto_awesome_rounded, color: accentColor, size: 14),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'AI Curator Mode • Enter any prompt or mood to generate instant playlists',
                          style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleAiMode,
                        child: Icon(Icons.close_rounded, size: 14, color: accentColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // Floating Segmented Tab Selector
        Container(
          height: 38,
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          decoration: BoxDecoration(
            color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(20),
          ),
          child: TabBar(
            controller: _tabController,
            indicator: BoxDecoration(
              color: accentColor,
              borderRadius: BorderRadius.circular(18),
            ),
            indicatorSize: TabBarIndicatorSize.tab,
            labelColor: Colors.black,
            unselectedLabelColor: isDark ? Colors.white54 : Colors.black54,
            labelStyle: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
            dividerColor: Colors.transparent,
            tabs: const [
              Tab(text: 'Songs'),
              Tab(text: 'Albums'),
              Tab(text: 'Artists'),
              Tab(text: 'Playlists'),
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

  Widget _buildSongsTab(Color accentColor) {
    if (_searchController.text.isEmpty && _filteredTracks.isEmpty) {
      final isFocused = _searchFocusNode.hasFocus;

      if (isFocused) {
        return ListView(
          padding: const EdgeInsets.only(bottom: 150, top: 12),
          children: [
            _buildChipSection(
              _isAiMode ? 'AI Recent Prompts' : 'Recent Searches',
              _recentSearches,
              true,
              accentColor,
            ),
            const SizedBox(height: 20),
            _buildTrendingSection(accentColor),
          ],
        );
      }

      final aiSessionsMap = StorageService.getGroupedAiSessionsMap();
      final historyTracks = _getHistoryTracksList();

      return ListView(
        padding: const EdgeInsets.only(bottom: 150, top: 12),
        children: [
          if (aiSessionsMap.isNotEmpty) ...[
            _buildAiPlaylistGroupsSection(aiSessionsMap, accentColor),
            const SizedBox(height: 24),
          ],
          _buildTrendingArtistsCarousel(accentColor),
          const SizedBox(height: 24),
          _buildRecentlyPlayedSongsSection(historyTracks, accentColor),
        ],
      );
    }

    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            const SizedBox(height: 16),
            Text('Loading tracks for "${_searchController.text.trim()}"...', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
          ],
        ),
      );
    }

    if (_filteredTracks.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off_rounded, size: 64, color: Colors.grey.withValues(alpha: 0.5)),
            const SizedBox(height: 16),
            const Text('No tracks found for query', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 8),
            TextButton(
              onPressed: _resetSearch,
              child: Text('Back to Music Discovery', style: TextStyle(color: accentColor, fontWeight: FontWeight.bold)),
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
              return _buildAiPlaylistBannerCard(context, notifier, accentColor);
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
                color: accentColor.withValues(alpha: 0.85),
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
                leading: AppArtworkImage(
                  artworkUrl: track.artworkUrl,
                  trackId: track.id,
                  width: 48,
                  height: 48,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(10),
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
                trailing: IconButton(
                  icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                  onPressed: () async {
                    await StorageService.addSearchedAndPlayedTrack(track);
                    notifier.playTrack(track);
                  },
                ),
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

  Widget _buildAlbumsTab(Color accentColor) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            const SizedBox(height: 16),
            Text('Loading tracks for "${_searchController.text.trim()}"...', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<String, List<Track>> albumsMap = {};
    for (final track in _filteredTracks) {
      final albumName = track.album.trim().isNotEmpty ? track.album.trim() : 'Singles';
      albumsMap.putIfAbsent(albumName, () => []).add(track);
    }

    if (albumsMap.isEmpty) {
      return ListView(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        children: [
          const Text('Top Albums & Collections', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          const SizedBox(height: 12),
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.85,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: _genreCards.length,
            itemBuilder: (context, index) {
              final card = _genreCards[index];
              return GestureDetector(
                onTap: () => _executeSearchQuery(card['query'] as String),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: card['colors'] as List<Color>,
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8, offset: Offset(0, 4))],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Icon(card['icon'] as IconData, size: 28, color: Colors.white),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(card['title'] as String, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15)),
                          const SizedBox(height: 2),
                          const Text('Top Album Mix', style: TextStyle(color: Colors.white70, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Found ${albumsMap.keys.length} Albums', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        GridView.builder(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 2,
            childAspectRatio: 0.82,
            crossAxisSpacing: 12,
            mainAxisSpacing: 12,
          ),
          itemCount: albumsMap.keys.length,
          itemBuilder: (context, index) {
            final albumName = albumsMap.keys.elementAt(index);
            final tracks = albumsMap[albumName]!;
            final firstTrack = tracks.first;

            return GestureDetector(
              onTap: () => _executeSearchQuery(albumName),
              child: Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF1C1C1F) : Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: AppArtworkImage(
                          artworkUrl: firstTrack.artworkUrl,
                          trackId: firstTrack.id,
                          width: double.infinity,
                          height: double.infinity,
                          fit: BoxFit.cover,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(albumName, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                    Text('${firstTrack.artist} • ${tracks.length} songs', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                  ],
                ),
              ),
            );
          },
        ),
      ],
    );
  }

  Widget _buildArtistsTab(Color accentColor) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            const SizedBox(height: 16),
            Text('Loading tracks for "${_searchController.text.trim()}"...', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
          ],
        ),
      );
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;

    final Map<String, List<Track>> artistsMap = {};
    for (final track in _filteredTracks) {
      final artistName = track.artist.split(',').first.trim();
      if (artistName.isNotEmpty) {
        artistsMap.putIfAbsent(artistName, () => []).add(track);
      }
    }

    if (artistsMap.isEmpty) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Text('Popular Artists', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          const SizedBox(height: 14),
          ..._trendingArtists.map((artist) {
            return ListTile(
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              leading: CircleAvatar(
                radius: 24,
                backgroundColor: accentColor.withValues(alpha: 0.2),
                child: Text(
                  artist.substring(0, 1),
                  style: TextStyle(fontWeight: FontWeight.bold, color: accentColor, fontSize: 18),
                ),
              ),
              title: Text(artist, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: const Text('Artist • Top Hits Available', style: TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 14),
              onTap: () => _executeSearchQuery(artist),
            );
          }),
        ],
      );
    }

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Text('Found ${artistsMap.keys.length} Artists', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
        const SizedBox(height: 12),
        ...artistsMap.keys.map((artistName) {
          final tracks = artistsMap[artistName]!;
          final sampleTrack = tracks.first;

          return Card(
            margin: const EdgeInsets.only(bottom: 10),
            color: isDark ? const Color(0xFF1E1E22) : Colors.white,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            child: ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              leading: CircleAvatar(
                radius: 26,
                backgroundColor: Colors.grey.shade800,
                child: AppArtworkImage(
                  artworkUrl: sampleTrack.artworkUrl,
                  trackId: sampleTrack.id,
                  width: 52,
                  height: 52,
                  fit: BoxFit.cover,
                  borderRadius: BorderRadius.circular(26),
                ),
              ),
              title: Text(artistName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              subtitle: Text('${tracks.length} Tracks in search result', style: const TextStyle(fontSize: 12, color: Colors.grey)),
              trailing: IconButton(
                icon: Icon(Icons.play_circle_fill_rounded, color: accentColor, size: 32),
                onPressed: () {
                  ref.read(playbackProvider.notifier).playCustomQueue(tracks, initialIndex: 0);
                },
              ),
              onTap: () => _executeSearchQuery(artistName),
            ),
          );
        }),
      ],
    );
  }

  Widget _buildPlaylistsTab(Color accentColor) {
    if (_isSearching) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(valueColor: AlwaysStoppedAnimation<Color>(accentColor)),
            const SizedBox(height: 16),
            Text('Loading tracks for "${_searchController.text.trim()}"...', style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.w500, fontSize: 14)),
          ],
        ),
      );
    }

    final aiSessionsMap = StorageService.getGroupedAiSessionsMap();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Row(
          children: [
            Icon(Icons.auto_awesome_rounded, color: accentColor, size: 20),
            const SizedBox(width: 8),
            const Text('AI Curated Playlists', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          ],
        ),
        const SizedBox(height: 12),
        if (aiSessionsMap.isEmpty)
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1C1C1F) : Colors.white,
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: accentColor.withValues(alpha: 0.3)),
            ),
            child: Column(
              children: [
                Icon(Icons.auto_awesome_outlined, size: 36, color: accentColor),
                const SizedBox(height: 8),
                const Text('No AI Playlists Yet', style: TextStyle(fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                const Text('Switch to AI Curator mode and type any mood or genre to create custom playlists!', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey)),
                const SizedBox(height: 12),
                ElevatedButton.icon(
                  onPressed: _toggleAiMode,
                  icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                  label: const Text('Try AI Curator'),
                  style: ElevatedButton.styleFrom(backgroundColor: accentColor, foregroundColor: Colors.black),
                ),
              ],
            ),
          )
        else
          GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 0.9,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: aiSessionsMap.keys.length,
            itemBuilder: (context, index) {
              final key = aiSessionsMap.keys.elementAt(index);
              final rawTracks = aiSessionsMap[key] as List?;
              final count = rawTracks?.length ?? 0;
              final titleCapitalized = key.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

              return GestureDetector(
                onTap: () => _showGroupSongsSheet(key),
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF24221E) : const Color(0xFFFFF9EE),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3)),
                    boxShadow: const [BoxShadow(color: Colors.black12, blurRadius: 6)],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Icon(Icons.auto_awesome_rounded, color: accentColor, size: 24),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(color: accentColor.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(10)),
                            child: Text('$count songs', style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: accentColor)),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(titleCapitalized, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                          const SizedBox(height: 2),
                          const Text('AI Playlist', style: TextStyle(fontSize: 11, color: Colors.grey)),
                        ],
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
      ],
    );
  }

  Widget _buildTrendingSection(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trending Searches', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _trendingArtists.map((artist) {
              return ActionChip(
                label: Text(artist),
                backgroundColor: accentColor.withValues(alpha: 0.12),
                labelStyle: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: accentColor),
                avatar: Icon(Icons.trending_up_rounded, size: 14, color: accentColor),
                onPressed: () => _executeSearchQuery(artist),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildTrendingArtistsCarousel(Color accentColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Trending Artists', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit')),
          const SizedBox(height: 12),
          SizedBox(
            height: 90,
            child: ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: _trendingArtists.length,
              itemBuilder: (context, index) {
                final artist = _trendingArtists[index];
                return GestureDetector(
                  onTap: () => _executeSearchQuery(artist),
                  child: Container(
                    margin: const EdgeInsets.only(right: 14),
                    child: Column(
                      children: [
                        CircleAvatar(
                          radius: 28,
                          backgroundColor: accentColor.withValues(alpha: 0.2),
                          child: Text(
                            artist.substring(0, 1),
                            style: TextStyle(fontWeight: FontWeight.bold, color: accentColor, fontSize: 20),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(artist, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600)),
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

  Widget _buildAiPlaylistBannerCard(BuildContext context, PlaybackNotifier notifier, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final playlistTitle = _currentAiPlaylistName.isEmpty
        ? '${_searchController.text.trim()} Playlist'
        : _currentAiPlaylistName;

    return Container(
      margin: const EdgeInsets.fromLTRB(20, 4, 20, 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF24221E) : const Color(0xFFFFF9EE),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: accentColor.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.12),
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
              Icon(Icons.auto_awesome_rounded, color: accentColor, size: 20),
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
                  color: accentColor.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${_filteredTracks.length} Tracks',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: accentColor),
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
                    backgroundColor: accentColor,
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
                    side: BorderSide(color: accentColor),
                    foregroundColor: accentColor,
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

  Widget _buildChipSection(String title, List<String> items, bool isRecent, Color accentColor) {
    if (items.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(title, style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
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
                  child: Text('Clear All', style: TextStyle(color: accentColor, fontSize: 12)),
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
                      onTap: () => _executeSearchQuery(tag),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(_isAiMode ? Icons.auto_awesome_rounded : Icons.history_rounded, size: 14, color: _isAiMode ? accentColor : Colors.grey),
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

  Widget _buildAiPlaylistGroupsSection(Map<String, dynamic> aiSessionsMap, Color accentColor) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.auto_awesome_rounded, size: 18, color: accentColor),
              const SizedBox(width: 8),
              const Text(
                'AI Playlist Groups',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
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
                final trackId = firstTrackMap?['id']?.toString() ?? '';

                final titleCapitalized = key.split(' ').map((w) => w.isEmpty ? '' : '${w[0].toUpperCase()}${w.substring(1)}').join(' ');

                return Container(
                  width: 150,
                  margin: const EdgeInsets.only(right: 12),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: isDark ? const Color(0xFF1F1F23) : Colors.white,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: accentColor.withValues(alpha: 0.3), width: 1),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 8,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AppArtworkImage(
                        artworkUrl: artUrl,
                        trackId: trackId,
                        width: double.infinity,
                        height: 70,
                        fit: BoxFit.cover,
                        borderRadius: BorderRadius.circular(12),
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
                            child: CircleAvatar(
                              radius: 12,
                              backgroundColor: accentColor,
                              child: const Icon(Icons.play_arrow_rounded, size: 16, color: Colors.black),
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

  Widget _buildRecentlyPlayedSongsSection(List<Track> historyTracks, Color accentColor) {
    if (historyTracks.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            children: [
              Icon(Icons.search_rounded, size: 48, color: Colors.grey.withValues(alpha: 0.4)),
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
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
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
                  color: accentColor.withValues(alpha: 0.85),
                  child: const Row(
                    children: [
                      Icon(Icons.queue_music_rounded, color: Colors.black),
                      SizedBox(width: 8),
                      Text('Add to Queue', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                  leading: AppArtworkImage(
                    artworkUrl: track.artworkUrl,
                    trackId: track.id,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                    borderRadius: BorderRadius.circular(10),
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
                  trailing: IconButton(
                    icon: Icon(Icons.play_circle_fill_rounded, size: 30, color: accentColor),
                    onPressed: () {
                      notifier.playTrack(track);
                    },
                  ),
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
}
