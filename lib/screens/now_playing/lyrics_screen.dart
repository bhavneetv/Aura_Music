import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/lyrics/lyrics_service.dart';
import '../../services/ai/song_summary_service.dart';

class LyricsScreen extends ConsumerStatefulWidget {
  final Track track;
  final LyricsResult lyricsResult;

  const LyricsScreen({
    super.key,
    required this.track,
    required this.lyricsResult,
  });

  @override
  ConsumerState<LyricsScreen> createState() => _LyricsScreenState();
}

class _LyricsScreenState extends ConsumerState<LyricsScreen> {
  final ScrollController _scrollController = ScrollController();
  late LyricsCandidate _selectedCandidate;
  List<LyricLine>? _currentSyncedLines;
  List<LyricLine>? _originalSyncedLines;
  String? _currentPlainLyrics;
  int _activeLineIndex = -1;
  String _activeLanguage = 'Original';
  bool _isTranslating = false;
  bool _userIsScrolling = false;
  Timer? _userScrollTimer;

  // Sync / Center lock state
  bool _isSyncLocked = true;

  // AI Line Explanations state
  Map<int, String> _lineExplanations = {};
  bool _isLoadingExplanations = false;
  bool _showExplanations = false;

  @override
  void initState() {
    super.initState();
    if (widget.lyricsResult.candidates.isNotEmpty) {
      _selectedCandidate = widget.lyricsResult.candidates.first;
      _applyCandidate(_selectedCandidate);
    } else {
      _currentSyncedLines = widget.lyricsResult.synced;
      _originalSyncedLines = widget.lyricsResult.synced;
      _currentPlainLyrics = widget.lyricsResult.plain;
    }
  }

  void _applyCandidate(LyricsCandidate candidate) {
    setState(() {
      _selectedCandidate = candidate;
      _activeLanguage = 'Original';
      _lineExplanations = {};
      _showExplanations = false;
      if (candidate.syncedLyrics != null && candidate.syncedLyrics!.isNotEmpty) {
        _currentSyncedLines = parseLrc(candidate.syncedLyrics!);
        _originalSyncedLines = _currentSyncedLines;
        _currentPlainLyrics = candidate.plainLyrics;
      } else {
        _currentSyncedLines = null;
        _originalSyncedLines = null;
        _currentPlainLyrics = candidate.plainLyrics;
      }
      _activeLineIndex = -1;
    });
  }

  Future<void> _translateLyrics(String targetLang) async {
    if (targetLang == 'Original') {
      setState(() {
        _activeLanguage = 'Original';
        _currentSyncedLines = _originalSyncedLines;
      });
      return;
    }

    final sourceLines = _originalSyncedLines;
    if (sourceLines == null || sourceLines.isEmpty) return;

    setState(() {
      _isTranslating = true;
    });

    try {
      final textToTranslate = sourceLines.map((l) => l.text).join('\n');
      final translatedText = await LyricsService.instance.translateLyrics(
        trackId: widget.track.id,
        lyricsText: textToTranslate,
        targetLanguage: targetLang,
      );

      final translatedSplit = translatedText.split('\n');
      final newSynced = <LyricLine>[];
      for (int i = 0; i < sourceLines.length; i++) {
        final originalLine = sourceLines[i];
        final transText = (i < translatedSplit.length && translatedSplit[i].trim().isNotEmpty)
            ? translatedSplit[i].trim()
            : originalLine.text;
        newSynced.add(LyricLine(originalLine.time, transText));
      }

      if (mounted) {
        setState(() {
          _activeLanguage = targetLang;
          _currentSyncedLines = newSynced;
          _isTranslating = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isTranslating = false;
        });
      }
    }
  }

  List<String> _extractRawLines() {
    if (_currentSyncedLines != null && _currentSyncedLines!.isNotEmpty) {
      return _currentSyncedLines!.map((l) => l.text).toList();
    }
    if (_currentPlainLyrics != null && _currentPlainLyrics!.isNotEmpty) {
      return _currentPlainLyrics!.split('\n').where((l) => l.trim().isNotEmpty).toList();
    }
    return [];
  }

  Future<void> _toggleLineExplanations() async {
    if (_showExplanations) {
      setState(() {
        _showExplanations = false;
      });
      return;
    }

    if (_lineExplanations.isNotEmpty) {
      setState(() {
        _showExplanations = true;
      });
      return;
    }

    final rawLines = _extractRawLines();
    if (rawLines.isEmpty) return;

    setState(() {
      _isLoadingExplanations = true;
      _showExplanations = true;
    });

    try {
      final map = await SongSummaryService.instance.getLineExplanations(
        title: widget.track.title,
        artist: widget.track.artist,
        lyricLines: rawLines,
      );
      if (mounted) {
        setState(() {
          _lineExplanations = map;
          _isLoadingExplanations = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _isLoadingExplanations = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _userScrollTimer?.cancel();
    _scrollController.dispose();
    super.dispose();
  }

  final Map<int, GlobalKey> _lineKeys = {};

  GlobalKey _getKeyForIndex(int index) {
    return _lineKeys.putIfAbsent(index, () => GlobalKey());
  }

  void _scrollToActiveLine(int index, int totalLines) {
    if (_userIsScrolling || !_scrollController.hasClients || index < 0 || totalLines <= 0) return;
    
    final key = _lineKeys[index];
    if (key != null && key.currentContext != null) {
      Scrollable.ensureVisible(
        key.currentContext!,
        alignment: 0.5,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    } else {
      const estimatedHeight = 65.0;
      final viewportHeight = MediaQuery.of(context).size.height;
      final targetOffset = mathMax(0.0, (index * estimatedHeight));
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  double mathMax(double a, double b) => a > b ? a : b;

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackProvider);
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = customBranding.accentColor;

    final synced = _currentSyncedLines;
    if (synced != null && synced.isNotEmpty) {
      final newIndex = currentLineIndex(synced, playbackState.currentPosition, offsetMs: -300);
      if (newIndex != _activeLineIndex) {
        _activeLineIndex = newIndex;
        WidgetsBinding.instance.addPostFrameCallback((_) {
          _scrollToActiveLine(_activeLineIndex, synced.length);
        });
      }
    }

    final candidates = widget.lyricsResult.candidates;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F0F11) : const Color(0xFFFAF7F2),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 28),
          onPressed: () => Navigator.pop(context),
        ),
        centerTitle: true,
        title: Column(
          children: [
            Text(
              widget.track.title,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              widget.track.artist,
              style: TextStyle(fontSize: 12, color: isDark ? Colors.white54 : Colors.black54),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: Icon(
              _showExplanations ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
              color: Colors.amber,
              size: 22,
            ),
            tooltip: 'AI Line-by-Line Meaning',
            onPressed: _toggleLineExplanations,
          ),
          PopupMenuButton<String>(
            icon: _isTranslating
                ? SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: accentColor))
                : Icon(Icons.g_translate_rounded, color: accentColor, size: 22),
            tooltip: 'Translate Lyrics (AI)',
            onSelected: (lang) => _translateLyrics(lang),
            itemBuilder: (context) {
              return ['Original', 'Hindi', 'English', 'Hinglish'].map((lang) {
                final isSel = lang == _activeLanguage;
                return PopupMenuItem<String>(
                  value: lang,
                  child: Row(
                    children: [
                      Icon(
                        isSel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                        size: 18,
                        color: isSel ? accentColor : Colors.grey,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        lang,
                        style: TextStyle(
                          fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList();
            },
          ),
          if (candidates.length > 1)
            PopupMenuButton<LyricsCandidate>(
              icon: Icon(Icons.layers_rounded, color: accentColor, size: 22),
              tooltip: 'Switch Lyrics Version',
              onSelected: _applyCandidate,
              itemBuilder: (context) {
                return candidates.map((cand) {
                  final isSel = cand.id == _selectedCandidate.id;
                  return PopupMenuItem<LyricsCandidate>(
                    value: cand,
                    child: Row(
                      children: [
                        Icon(
                          isSel ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                          size: 18,
                          color: isSel ? accentColor : Colors.grey,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            cand.languageLabel,
                            style: TextStyle(
                              fontWeight: isSel ? FontWeight.bold : FontWeight.normal,
                              fontSize: 13,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }).toList();
              },
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Header Controls Bar wrapped in SingleChildScrollView to prevent edge overflow
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    // Center Sync Lock Button
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          _isSyncLocked = !_isSyncLocked;
                          _userIsScrolling = false;
                        });
                        if (_isSyncLocked && synced != null && synced.isNotEmpty) {
                          _scrollToActiveLine(_activeLineIndex, synced.length);
                        }
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: _isSyncLocked ? accentColor.withValues(alpha: 0.22) : Colors.transparent,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _isSyncLocked ? accentColor : Colors.grey.withValues(alpha: 0.3),
                            width: 1.0,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              _isSyncLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                              size: 12,
                              color: _isSyncLocked ? accentColor : Colors.grey,
                            ),
                            const SizedBox(width: 5),
                            Text(
                              _isSyncLocked ? 'Sync Locked (Center) 🎯' : 'Sync 🎯',
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                                color: _isSyncLocked ? accentColor : Colors.grey,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),

                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            synced != null && synced.isNotEmpty ? Icons.sync_rounded : Icons.notes_rounded,
                            size: 12,
                            color: accentColor,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            synced != null && synced.isNotEmpty ? 'Karaoke Synced' : 'Plain Text',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: accentColor,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_activeLanguage != 'Original') ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: Colors.amber.withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.amber, width: 0.8),
                        ),
                        child: Text(
                          'AI Translated ($_activeLanguage)',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.amber),
                        ),
                      ),
                    ],
                    const SizedBox(width: 8),
                    GestureDetector(
                      onTap: _toggleLineExplanations,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: _showExplanations ? Colors.amber.withValues(alpha: 0.25) : accentColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: _showExplanations ? Colors.amber : accentColor.withValues(alpha: 0.3), width: 0.8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (_isLoadingExplanations) ...[
                              const SizedBox(width: 10, height: 10, child: CircularProgressIndicator(strokeWidth: 1.5, color: Colors.amber)),
                              const SizedBox(width: 4),
                            ] else ...[
                              Icon(Icons.auto_awesome_rounded, size: 12, color: _showExplanations ? Colors.amber : accentColor),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              _showExplanations ? 'Line Explanations ✨' : 'Summarize Lines ✨',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: _showExplanations ? Colors.amber : accentColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const Divider(height: 1),

            Expanded(
              child: widget.lyricsResult.instrumental
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.music_note_rounded, size: 64, color: accentColor.withValues(alpha: 0.5)),
                          const SizedBox(height: 16),
                          const Text(
                            '🎼 Instrumental Track',
                            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          ),
                          const SizedBox(height: 8),
                          const Text('This song has no spoken or sung lyrics.', style: TextStyle(color: Colors.grey)),
                        ],
                      ),
                    )
                  : (synced != null && synced.isNotEmpty)
                      ? NotificationListener<ScrollNotification>(
                          onNotification: (notification) {
                            if (notification is ScrollStartNotification && notification.dragDetails != null) {
                              _userIsScrolling = true;
                              _userScrollTimer?.cancel();
                            } else if (notification is ScrollEndNotification) {
                              _userScrollTimer?.cancel();
                              _userScrollTimer = Timer(const Duration(milliseconds: 3500), () {
                                if (mounted) {
                                  setState(() {
                                    _userIsScrolling = false;
                                  });
                                  _scrollToActiveLine(_activeLineIndex, synced.length);
                                }
                              });
                            }
                            return false;
                          },
                          child: ListView.builder(
                            controller: _scrollController,
                            padding: EdgeInsets.only(
                              left: 24,
                              right: 24,
                              top: MediaQuery.of(context).size.height * 0.35,
                              bottom: MediaQuery.of(context).size.height * 0.40,
                            ),
                            itemCount: synced.length,
                            itemBuilder: (context, index) {
                              final line = synced[index];
                              final isActive = index == _activeLineIndex;
                              final explanation = _lineExplanations[index];

                              return Container(
                                key: _getKeyForIndex(index),
                                child: GestureDetector(
                                onTap: () {
                                  _userScrollTimer?.cancel();
                                  _userIsScrolling = false;
                                  ref.read(playbackProvider.notifier).seekToDuration(line.time);
                                  _scrollToActiveLine(index, synced.length);
                                },
                                child: AnimatedContainer(
                                  duration: const Duration(milliseconds: 200),
                                  padding: const EdgeInsets.symmetric(vertical: 10),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      AnimatedDefaultTextStyle(
                                        duration: const Duration(milliseconds: 200),
                                        style: TextStyle(
                                          fontSize: isActive ? 22 : 16,
                                          fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                                          color: isActive
                                              ? accentColor
                                              : (isDark ? Colors.white : Colors.black).withValues(alpha: 0.4),
                                          height: 1.4,
                                          fontFamily: 'Outfit',
                                        ),
                                        child: Text(line.text.isEmpty ? '♪' : line.text),
                                      ),

                                      // Premium UI for Summarized Lyric Line Explanations
                                      if (_showExplanations) ...[
                                        const SizedBox(height: 4),
                                        if (_isLoadingExplanations && explanation == null)
                                          Text(
                                            ' (✨ Analyzing line meaning...)',
                                            style: TextStyle(
                                              fontSize: 11,
                                              fontStyle: FontStyle.italic,
                                              color: Colors.amber.withValues(alpha: 0.7),
                                            ),
                                          )
                                        else if (explanation != null && explanation.isNotEmpty)
                                          Container(
                                            margin: const EdgeInsets.only(top: 4, bottom: 2),
                                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                            decoration: BoxDecoration(
                                              color: (isDark ? const Color(0xFF2B2215) : const Color(0xFFFFF9EE)),
                                              borderRadius: BorderRadius.circular(10),
                                              border: Border.all(color: Colors.amber.withValues(alpha: 0.45), width: 0.8),
                                              boxShadow: [
                                                BoxShadow(
                                                  color: Colors.amber.withValues(alpha: 0.08),
                                                  blurRadius: 6,
                                                  offset: const Offset(0, 2),
                                                ),
                                              ],
                                            ),
                                            child: Row(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                const Text('💡 ', style: TextStyle(fontSize: 12)),
                                                Expanded(
                                                  child: Text(
                                                    '($explanation)',
                                                    style: TextStyle(
                                                      fontSize: 12,
                                                      fontStyle: FontStyle.italic,
                                                      fontWeight: FontWeight.w600,
                                                      color: isDark ? Colors.amber.shade200 : Colors.brown.shade900,
                                                      height: 1.35,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                            },
                          ),
                        )
                      : ListView(
                          padding: const EdgeInsets.all(24),
                          children: [
                            if (_currentPlainLyrics != null && _currentPlainLyrics!.isNotEmpty)
                              ..._currentPlainLyrics!.split('\n').asMap().entries.map((entry) {
                                final idx = entry.key;
                                final lineStr = entry.value;
                                final explanation = _lineExplanations[idx];

                                return Padding(
                                  padding: const EdgeInsets.symmetric(vertical: 6),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        lineStr.isEmpty ? '♪' : lineStr,
                                        style: TextStyle(
                                          fontSize: 16,
                                          height: 1.5,
                                          color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.8),
                                          fontFamily: 'Outfit',
                                        ),
                                      ),
                                      if (_showExplanations && explanation != null && explanation.isNotEmpty) ...[
                                        const SizedBox(height: 4),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: (isDark ? const Color(0xFF2B2215) : const Color(0xFFFFF9EE)),
                                            borderRadius: BorderRadius.circular(10),
                                            border: Border.all(color: Colors.amber.withValues(alpha: 0.45), width: 0.8),
                                          ),
                                          child: Row(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              const Text('💡 ', style: TextStyle(fontSize: 12)),
                                              Expanded(
                                                child: Text(
                                                  '($explanation)',
                                                  style: TextStyle(
                                                    fontSize: 12,
                                                    fontStyle: FontStyle.italic,
                                                    fontWeight: FontWeight.w600,
                                                    color: isDark ? Colors.amber.shade200 : Colors.brown.shade900,
                                                    height: 1.35,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                );
                              })
                            else
                              const Text('No lyrics available.', style: TextStyle(fontSize: 16, color: Colors.grey)),
                          ],
                        ),
            ),
          ],
        ),
      ),
    );
  }
}
