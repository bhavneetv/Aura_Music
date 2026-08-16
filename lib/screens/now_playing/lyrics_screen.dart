import 'dart:async';
import 'dart:ui';
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

class _LyricsScreenState extends ConsumerState<LyricsScreen>
    with SingleTickerProviderStateMixin {
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

  // Zoom / Font Scale state
  double _fontScale = 1.0;

  // AI Line Explanations state
  Map<int, String> _lineExplanations = {};
  bool _isLoadingExplanations = false;
  bool _showExplanations = false;

  // Entrance animation for the whole screen
  late final AnimationController _entranceController;
  late final Animation<double> _entranceFade;
  late final Animation<Offset> _entranceSlide;

  void _zoomIn() {
    setState(() {
      _fontScale = (_fontScale + 0.15).clamp(0.7, 1.8);
    });
  }

  void _zoomOut() {
    setState(() {
      _fontScale = (_fontScale - 0.15).clamp(0.7, 1.8);
    });
  }

  void _resetZoom() {
    setState(() {
      _fontScale = 1.0;
    });
  }

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _entranceFade = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _entranceSlide = Tween<Offset>(
      begin: const Offset(0, 0.04),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOutCubic,
    ));
    _entranceController.forward();

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
    _entranceController.dispose();
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
      final targetOffset = _mathMax(0.0, (index * estimatedHeight));
      _scrollController.animateTo(
        targetOffset,
        duration: const Duration(milliseconds: 350),
        curve: Curves.easeInOutCubic,
      );
    }
  }

  double _mathMax(double a, double b) => a > b ? a : b;

  // ── Bottom sheet with all secondary controls (translate, versions, zoom, sync) ──
  void _openControlsSheet({
    required Color textColor,
    required Color subTextColor,
    required Color accentColor,
    required bool isDark,
  }) {
    final candidates = widget.lyricsResult.candidates;
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, sheetSetState) {
            void update(VoidCallback fn) {
              setState(fn);
              sheetSetState(() {});
            }

            return ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
                child: Container(
                  padding: EdgeInsets.only(
                    left: 20,
                    right: 20,
                    top: 14,
                    bottom: MediaQuery.of(sheetContext).viewInsets.bottom + 28,
                  ),
                  decoration: BoxDecoration(
                    color: (isDark ? const Color(0xFF15110D) : Colors.white)
                        .withValues(alpha: 0.88),
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
                    border: Border(
                      top: BorderSide(
                        color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
                      ),
                    ),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                          width: 40,
                          height: 4,
                          margin: const EdgeInsets.only(bottom: 18),
                          decoration: BoxDecoration(
                            color: subTextColor.withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(4),
                          ),
                        ),
                      ),
                      Text(
                        'Lyrics settings',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Sync lock row
                      _sheetTile(
                        icon: _isSyncLocked ? Icons.gps_fixed_rounded : Icons.gps_not_fixed_rounded,
                        iconColor: _isSyncLocked ? accentColor : subTextColor,
                        title: 'Center lock',
                        subtitle: _isSyncLocked
                            ? 'Active line stays centered while playing'
                            : 'Scroll freely without auto re-centering',
                        textColor: textColor,
                        subTextColor: subTextColor,
                        trailing: Switch.adaptive(
                          value: _isSyncLocked,
                          activeColor: accentColor,
                          onChanged: (v) {
                            update(() {
                              _isSyncLocked = v;
                              _userIsScrolling = false;
                            });
                            final synced = _currentSyncedLines;
                            if (v && synced != null && synced.isNotEmpty) {
                              _scrollToActiveLine(_activeLineIndex, synced.length);
                            }
                          },
                        ),
                      ),

                      const SizedBox(height: 8),

                      // Font size row
                      _sheetTile(
                        icon: Icons.format_size_rounded,
                        iconColor: accentColor,
                        title: 'Text size',
                        subtitle: '${(_fontScale * 100).round()}%',
                        textColor: textColor,
                        subTextColor: subTextColor,
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _roundIconButton(
                              icon: Icons.remove_rounded,
                              onTap: () => update(_zoomOut),
                              color: textColor,
                              background: subTextColor.withValues(alpha: 0.12),
                            ),
                            GestureDetector(
                              onTap: () => update(_resetZoom),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                child: Icon(Icons.refresh_rounded, size: 16, color: subTextColor),
                              ),
                            ),
                            _roundIconButton(
                              icon: Icons.add_rounded,
                              onTap: () => update(_zoomIn),
                              color: textColor,
                              background: subTextColor.withValues(alpha: 0.12),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 18),
                      Text(
                        'TRANSLATE',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.8,
                          color: subTextColor,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: ['Original', 'Hindi', 'English', 'Hinglish'].map((lang) {
                          final isSel = lang == _activeLanguage;
                          return GestureDetector(
                            onTap: () {
                              update(() {});
                              _translateLyrics(lang);
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                              decoration: BoxDecoration(
                                color: isSel ? accentColor : subTextColor.withValues(alpha: 0.1),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  if (isSel && _isTranslating)
                                    Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: SizedBox(
                                        width: 12,
                                        height: 12,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 1.6,
                                          color: isDark ? Colors.black : Colors.white,
                                        ),
                                      ),
                                    ),
                                  Text(
                                    lang,
                                    style: TextStyle(
                                      fontSize: 13,
                                      fontWeight: FontWeight.w700,
                                      color: isSel
                                          ? (isDark ? Colors.black : Colors.white)
                                          : textColor,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),

                      if (candidates.length > 1) ...[
                        const SizedBox(height: 22),
                        Text(
                          'LYRICS VERSION',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 0.8,
                            color: subTextColor,
                          ),
                        ),
                        const SizedBox(height: 10),
                        ...candidates.map((cand) {
                          final isSel = cand.id == _selectedCandidate.id;
                          return GestureDetector(
                            onTap: () {
                              _applyCandidate(cand);
                              sheetSetState(() {});
                            },
                            child: Container(
                              margin: const EdgeInsets.only(bottom: 8),
                              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                              decoration: BoxDecoration(
                                color: isSel
                                    ? accentColor.withValues(alpha: 0.16)
                                    : subTextColor.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isSel ? accentColor : Colors.transparent,
                                  width: 1.2,
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    isSel ? Icons.check_circle_rounded : Icons.circle_outlined,
                                    size: 18,
                                    color: isSel ? accentColor : subTextColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Text(
                                      cand.languageLabel,
                                      style: TextStyle(
                                        fontSize: 14,
                                        fontWeight: isSel ? FontWeight.w700 : FontWeight.w500,
                                        color: textColor,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }),
                      ],
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _sheetTile({
    required IconData icon,
    required Color iconColor,
    required String title,
    required String subtitle,
    required Color textColor,
    required Color subTextColor,
    required Widget trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: iconColor.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: textColor)),
              const SizedBox(height: 2),
              Text(subtitle, style: TextStyle(fontSize: 11.5, color: subTextColor)),
            ],
          ),
        ),
        trailing,
      ],
    );
  }

  Widget _roundIconButton({
    required IconData icon,
    required VoidCallback onTap,
    required Color color,
    required Color background,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: background, shape: BoxShape.circle),
        child: Icon(icon, size: 15, color: color),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final playbackState = ref.watch(playbackProvider);
    final customBranding = ref.watch(customizationProvider);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accentColor = customBranding.accentColor;

    final Color bgTop = isDark
        ? HSLColor.fromColor(accentColor).withLightness(0.08).withSaturation(0.40).toColor()
        : const Color(0xFFFAF7F2);

    final Color bgBottom = isDark
        ? HSLColor.fromColor(accentColor).withLightness(0.04).withSaturation(0.30).toColor()
        : const Color(0xFFF2ECE1);

    final Color textColor = isDark ? Colors.white : Colors.black87;
    final Color subTextColor = isDark ? Colors.white60 : Colors.black54;
    final Color activeTextColor = accentColor;
    final Color inactiveTextColor = isDark ? Colors.white38 : Colors.black38;

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

    final double activeFontSize = (23 * _fontScale).clamp(14.0, 38.0);
    final double inactiveFontSize = (16 * _fontScale).clamp(11.0, 26.0);

    return Scaffold(
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          // ── Ambient gradient background with a soft glow behind the active area ──
          AnimatedContainer(
            duration: const Duration(milliseconds: 400),
            width: double.infinity,
            height: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [bgTop, bgBottom],
              ),
            ),
          ),
          Positioned(
            top: -120,
            left: -60,
            child: Container(
              width: 320,
              height: 320,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: RadialGradient(
                  colors: [accentColor.withValues(alpha: isDark ? 0.22 : 0.12), Colors.transparent],
                ),
              ),
            ),
          ),

          FadeTransition(
            opacity: _entranceFade,
            child: SlideTransition(
              position: _entranceSlide,
              child: SafeArea(
                child: Column(
                  children: [
                    _buildHeader(
                      textColor: textColor,
                      subTextColor: subTextColor,
                      accentColor: activeTextColor,
                      isDark: isDark,
                    ),
                    _buildStatusStrip(
                      synced: synced,
                      accentColor: activeTextColor,
                      isDark: isDark,
                    ),
                    Expanded(
                      child: widget.lyricsResult.instrumental
                          ? _buildInstrumentalState(textColor, subTextColor, activeTextColor)
                          : (synced != null && synced.isNotEmpty)
                              ? _buildSyncedList(
                                  synced: synced,
                                  isDark: isDark,
                                  activeTextColor: activeTextColor,
                                  inactiveTextColor: inactiveTextColor,
                                  activeFontSize: activeFontSize,
                                  inactiveFontSize: inactiveFontSize,
                                )
                              : _buildPlainList(
                                  isDark: isDark,
                                  textColor: textColor,
                                  subTextColor: subTextColor,
                                  inactiveFontSize: inactiveFontSize,
                                ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          // ── Floating quick-access AI toggle, bottom-right ──
          Positioned(
            right: 18,
            bottom: 22,
            child: FadeTransition(
              opacity: _entranceFade,
              child: _buildAiFab(isDark: isDark, accentColor: activeTextColor),
            ),
          ),
        ],
      ),
    );
  }

  // ── Header: back button, title/artist, single "more" control ──
  Widget _buildHeader({
    required Color textColor,
    required Color subTextColor,
    required Color accentColor,
    required bool isDark,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(
                color: (isDark ? Colors.white : Colors.black).withValues(alpha: 0.08),
              ),
            ),
            child: Row(
              children: [
                _glassIconButton(
                  icon: Icons.keyboard_arrow_down_rounded,
                  color: textColor,
                  onTap: () => Navigator.pop(context),
                ),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        widget.track.title,
                        style: TextStyle(fontWeight: FontWeight.w800, fontSize: 15, color: textColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        widget.track.artist,
                        style: TextStyle(fontSize: 11.5, color: subTextColor),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                _glassIconButton(
                  icon: Icons.tune_rounded,
                  color: accentColor,
                  onTap: () => _openControlsSheet(
                    textColor: textColor,
                    subTextColor: subTextColor,
                    accentColor: accentColor,
                    isDark: isDark,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassIconButton({
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Icon(icon, size: 24, color: color),
      ),
    );
  }

  // ── Slim auto badge strip: mode + translation state, no longer a button row ──
  Widget _buildStatusStrip({
    required List<LyricLine>? synced,
    required Color accentColor,
    required bool isDark,
  }) {
    final isKaraoke = synced != null && synced.isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 250),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(isKaraoke ? Icons.graphic_eq_rounded : Icons.notes_rounded, size: 12, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  isKaraoke ? 'Synced' : 'Plain text',
                  style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: accentColor),
                ),
              ],
            ),
          ),
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            transitionBuilder: (child, anim) => FadeTransition(
              opacity: anim,
              child: SizeTransition(sizeFactor: anim, axis: Axis.horizontal, child: child),
            ),
            child: _activeLanguage != 'Original'
                ? Padding(
                    key: ValueKey(_activeLanguage),
                    padding: const EdgeInsets.only(left: 8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(color: Colors.amber.withValues(alpha: 0.5), width: 0.8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.translate_rounded, size: 11, color: Colors.amber),
                          const SizedBox(width: 4),
                          Text(
                            _activeLanguage,
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w800, color: Colors.amber),
                          ),
                        ],
                      ),
                    ),
                  )
                : const SizedBox.shrink(key: ValueKey('none')),
          ),
        ],
      ),
    );
  }

  // ── Floating AI sparkle FAB — quick access to line-by-line meaning ──
  Widget _buildAiFab({required bool isDark, required Color accentColor}) {
    return GestureDetector(
      onTap: _toggleLineExplanations,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOutBack,
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: _showExplanations
                ? [Colors.amber.shade400, Colors.amber.shade700]
                : [accentColor.withValues(alpha: 0.9), accentColor.withValues(alpha: 0.6)],
          ),
          boxShadow: [
            BoxShadow(
              color: (_showExplanations ? Colors.amber : accentColor).withValues(alpha: 0.35),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Center(
          child: _isLoadingExplanations
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                )
              : Icon(
                  _showExplanations ? Icons.auto_awesome_rounded : Icons.auto_awesome_outlined,
                  color: Colors.white,
                  size: 24,
                ),
        ),
      ),
    );
  }

  Widget _buildInstrumentalState(Color textColor, Color subTextColor, Color accentColor) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.music_note_rounded, size: 64, color: accentColor.withValues(alpha: 0.5)),
          const SizedBox(height: 16),
          Text('🎼 Instrumental Track', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: textColor)),
          const SizedBox(height: 8),
          Text('This song has no spoken or sung lyrics.', style: TextStyle(color: subTextColor)),
        ],
      ),
    );
  }

  Widget _buildSyncedList({
    required List<LyricLine> synced,
    required bool isDark,
    required Color activeTextColor,
    required Color inactiveTextColor,
    required double activeFontSize,
    required double inactiveFontSize,
  }) {
    return NotificationListener<ScrollNotification>(
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
          top: MediaQuery.of(context).size.height * 0.30,
          bottom: MediaQuery.of(context).size.height * 0.38,
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
              child: AnimatedScale(
                duration: const Duration(milliseconds: 260),
                curve: Curves.easeOutCubic,
                scale: isActive ? 1.0 : 0.97,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 260),
                  curve: Curves.easeOutCubic,
                  margin: const EdgeInsets.symmetric(vertical: 4),
                  padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                  decoration: BoxDecoration(
                    color: isActive ? activeTextColor.withValues(alpha: 0.10) : Colors.transparent,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      AnimatedDefaultTextStyle(
                        duration: const Duration(milliseconds: 260),
                        curve: Curves.easeOutCubic,
                        style: TextStyle(
                          fontSize: isActive ? activeFontSize : inactiveFontSize,
                          fontWeight: isActive ? FontWeight.w900 : FontWeight.w500,
                          color: isActive ? activeTextColor : inactiveTextColor,
                          height: 1.4,
                          fontFamily: 'Outfit',
                          shadows: isActive
                              ? [Shadow(color: activeTextColor.withValues(alpha: 0.35), blurRadius: 18)]
                              : null,
                        ),
                        child: Text(line.text.isEmpty ? '♪' : line.text),
                      ),
                      AnimatedSwitcher(
                        duration: const Duration(milliseconds: 220),
                        transitionBuilder: (child, anim) => FadeTransition(
                          opacity: anim,
                          child: SizeTransition(sizeFactor: anim, child: child),
                        ),
                        child: (_showExplanations)
                            ? _buildExplanationChip(
                                key: ValueKey('exp_$index${explanation ?? ''}'),
                                isDark: isDark,
                                isLoading: _isLoadingExplanations && explanation == null,
                                explanation: explanation,
                              )
                            : const SizedBox.shrink(key: ValueKey('exp_empty')),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildExplanationChip({
    required Key key,
    required bool isDark,
    required bool isLoading,
    required String? explanation,
  }) {
    if (isLoading) {
      return Padding(
        key: key,
        padding: const EdgeInsets.only(top: 4),
        child: Text(
          '✨ Reading between the lines…',
          style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.amber.withValues(alpha: 0.7)),
        ),
      );
    }
    if (explanation == null || explanation.isEmpty) {
      return SizedBox.shrink(key: key);
    }
    return Container(
      key: key,
      margin: const EdgeInsets.only(top: 6, bottom: 2),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF2B2215), const Color(0xFF201A10)]
              : [const Color(0xFFFFF9EE), const Color(0xFFFFF3DA)],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border(left: BorderSide(color: Colors.amber.withValues(alpha: 0.7), width: 3)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💡 ', style: TextStyle(fontSize: 12)),
          Expanded(
            child: Text(
              explanation,
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
    );
  }

  Widget _buildPlainList({
    required bool isDark,
    required Color textColor,
    required Color subTextColor,
    required double inactiveFontSize,
  }) {
    if (_currentPlainLyrics == null || _currentPlainLyrics!.isEmpty) {
      return Center(child: Text('No lyrics available.', style: TextStyle(fontSize: 16, color: subTextColor)));
    }
    final lines = _currentPlainLyrics!.split('\n');
    return ListView.builder(
      padding: const EdgeInsets.all(24),
      itemCount: lines.length,
      itemBuilder: (context, idx) {
        final lineStr = lines[idx];
        final explanation = _lineExplanations[idx];
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AnimatedDefaultTextStyle(
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOutCubic,
                style: TextStyle(
                  fontSize: inactiveFontSize,
                  height: 1.5,
                  color: textColor.withValues(alpha: 0.85),
                  fontFamily: 'Outfit',
                ),
                child: Text(lineStr.isEmpty ? '♪' : lineStr),
              ),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 220),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SizeTransition(sizeFactor: anim, child: child),
                ),
                child: (_showExplanations && explanation != null && explanation.isNotEmpty)
                    ? _buildExplanationChip(
                        key: ValueKey('plain_exp_$idx'),
                        isDark: isDark,
                        isLoading: false,
                        explanation: explanation,
                      )
                    : const SizedBox.shrink(key: ValueKey('plain_exp_empty')),
              ),
            ],
          ),
        );
      },
    );
  }
}