import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';

// ═════════════════════════════════════════════════════════════════════════════
// AI PLAYLIST REVIEW
//
//   Fixed      back · title · "12/30" counter
//   Scrolling  header card (name, selection progress, select all)
//              source filter (stays pinned while you scroll)
//              song cards (tap to keep or drop a song)
//   Fixed      Save Playlist · Play Now
//
// Responsive: content is capped and centered on wide screens and the song
// cards go from one per row to two or three.
// ═════════════════════════════════════════════════════════════════════════════

class AiPlaylistReviewScreen extends ConsumerStatefulWidget {
  final String suggestedName;
  final List<Track> tracks;

  const AiPlaylistReviewScreen({
    super.key,
    required this.suggestedName,
    required this.tracks,
  });

  @override
  ConsumerState<AiPlaylistReviewScreen> createState() => _AiPlaylistReviewScreenState();
}

class _AiPlaylistReviewScreenState extends ConsumerState<AiPlaylistReviewScreen> with TickerProviderStateMixin {
  late TextEditingController _nameController;
  late Set<String> _selectedTrackIds;
  String _sourceFilter = 'All'; // 'All', 'Saavn', 'YT'

  /// Plays once when the screen opens: the header, then the cards one by one.
  late final AnimationController _intro;

  /// Loops while the screen is open: the twinkles on the header card.
  late final AnimationController _sparkle;

  bool _introStarted = false;

  /// True while a save / play is being written, so a double tap can't run twice.
  bool _busy = false;

  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 1000;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.suggestedName);
    _selectedTrackIds = widget.tracks.map((t) => t.id).toSet();
    _intro = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
    _sparkle = AnimationController(vsync: this, duration: const Duration(milliseconds: 3600));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Skip the motion when the system asks for reduced motion.
    if (MediaQuery.disableAnimationsOf(context)) {
      _intro.value = 1;
      _sparkle.stop();
      _sparkle.value = 0.15;
    } else {
      if (!_introStarted) _intro.forward();
      if (!_sparkle.isAnimating) _sparkle.repeat();
    }
    _introStarted = true;
  }

  @override
  void dispose() {
    _intro.dispose();
    _sparkle.dispose();
    _nameController.dispose();
    super.dispose();
  }

  List<Track> get _visibleTracks {
    if (_sourceFilter == 'Saavn') {
      return widget.tracks.where((t) => t.isJioSaavn).toList();
    } else if (_sourceFilter == 'YT') {
      return widget.tracks.where((t) => t.isYouTube).toList();
    }
    return widget.tracks;
  }

  int get _allCount => widget.tracks.length;
  int get _saavnCount => widget.tracks.where((t) => t.isJioSaavn).length;
  int get _ytCount => widget.tracks.where((t) => t.isYouTube).length;

  // ── Actions ────────────────────────────────────────────────────────────────

  void _setSourceFilter(String filter) {
    if (_sourceFilter == filter) return;
    triggerHaptic(HapticFeedbackType.selection);
    setState(() {
      _sourceFilter = filter;
    });
  }

  void _toggleTrack(Track track) {
    triggerHaptic(HapticFeedbackType.selection);
    setState(() {
      if (_selectedTrackIds.contains(track.id)) {
        _selectedTrackIds.remove(track.id);
      } else {
        _selectedTrackIds.add(track.id);
      }
    });
  }

  /// Selects every song in the current filter, or clears them if they are all
  /// selected already.
  void _toggleAllVisible(List<Track> visibleTracks, bool allVisibleSelected) {
    triggerHaptic(HapticFeedbackType.light);
    setState(() {
      if (allVisibleSelected) {
        for (final t in visibleTracks) {
          _selectedTrackIds.remove(t.id);
        }
      } else {
        for (final t in visibleTracks) {
          _selectedTrackIds.add(t.id);
        }
      }
    });
  }

  // Saving and playing are the original logic, unchanged.

  Future<void> _savePlaylist(List<Track> selectedTracks) async {
    if (_busy) return;
    setState(() => _busy = true);
    final customBranding = ref.read(customizationProvider);

    final name = _nameController.text.trim().isEmpty ? 'AI Curated Playlist' : _nameController.text.trim();
    final playlists = StorageService.getPlaylists();
    final newPl = {
      'id': DateTime.now().millisecondsSinceEpoch.toString(),
      'name': name,
      'description': 'AI generated playlist from prompt',
      'trackIds': selectedTracks.map((t) => t.id).toList(),
      'tracks': selectedTracks.map((t) => t.toJson()).toList(),
    };
    playlists.add(newPl);
    await StorageService.savePlaylists(playlists);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved AI Playlist "$name" with ${selectedTracks.length} tracks! ⚡'),
          backgroundColor: customBranding.accentColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.pop(context);
    }

    if (mounted) setState(() => _busy = false);
  }

  Future<void> _playNow(List<Track> selectedTracks) async {
    if (_busy) return;
    setState(() => _busy = true);

    final sessionName = widget.suggestedName.trim();
    final chipTag = '✨ $sessionName (${selectedTracks.length} songs)';
    await StorageService.saveGroupedAiSession(chipTag, selectedTracks);
    await StorageService.saveGroupedAiSession(sessionName, selectedTracks);
    await StorageService.addAiSearchQuery(chipTag);

    final notifier = ref.read(playbackProvider.notifier);
    notifier.playCustomQueue(selectedTracks, initialIndex: 0);
    if (context.mounted) {
      Navigator.pop(context);
    }

    if (mounted) setState(() => _busy = false);
  }

  // ── Layout ─────────────────────────────────────────────────────────────────

  /// Cards per row for a list that is [width] wide.
  int _columnsFor(double width) {
    if (width >= 980) return 3;
    if (width >= 620) return 2;
    return 1;
  }

  /// Fades and lifts [child] in as the screen opens. [order] staggers it:
  /// 0 is the header, 1 the first row of songs, and so on.
  Widget _entrance(int order, Widget child) {
    final start = math.min(order, 8) * 0.07;
    final curve = Interval(start, math.min(1.0, start + 0.44), curve: Curves.easeOutCubic);

    return AnimatedBuilder(
      animation: _intro,
      child: child,
      builder: (context, child) {
        final t = curve.transform(_intro.value);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, 20 * (1 - t)), child: child),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final background = isDark ? const Color(0xFF0F0F11) : const Color(0xFFFAF7F2);

    final selectedTracks = widget.tracks.where((t) => _selectedTrackIds.contains(t.id)).toList();
    final visibleTracks = _visibleTracks;
    final allVisibleSelected = visibleTracks.isNotEmpty && visibleTracks.every((t) => _selectedTrackIds.contains(t.id));

    return Scaffold(
      backgroundColor: background,
      body: LayoutBuilder(
        builder: (context, constraints) {
          final side = math.max(16.0, (constraints.maxWidth - _maxContentWidth) / 2);
          final columns = _columnsFor(constraints.maxWidth - side * 2);
          final rows = (visibleTracks.length / columns).ceil();

          return Column(
            children: [
              _buildTopBar(accentColor, side, selectedTracks.length),
              Expanded(
                child: CustomScrollView(
                  physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
                  keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                  slivers: [
                    SliverPadding(
                      padding: EdgeInsets.fromLTRB(side, 6, side, 0),
                      sliver: SliverToBoxAdapter(
                        child: _entrance(
                          0,
                          _buildHeaderCard(
                            accentColor: accentColor,
                            isDark: isDark,
                            selectedCount: selectedTracks.length,
                            visibleTracks: visibleTracks,
                            allVisibleSelected: allVisibleSelected,
                          ),
                        ),
                      ),
                    ),

                    // Source filter: All, Saavn, YT
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _PinnedHeader(
                        height: 66,
                        child: ColoredBox(
                          color: background,
                          child: Padding(
                            padding: EdgeInsets.fromLTRB(side, 11, side, 11),
                            child: _SourceSegments(
                              selected: _sourceFilter,
                              accent: accentColor,
                              allCount: _allCount,
                              saavnCount: _saavnCount,
                              ytCount: _ytCount,
                              onSelected: _setSourceFilter,
                            ),
                          ),
                        ),
                      ),
                    ),

                    // Songs
                    if (visibleTracks.isEmpty)
                      SliverFillRemaining(
                        hasScrollBody: false,
                        child: _buildEmptyFilter(accentColor),
                      )
                    else
                      SliverPadding(
                        padding: EdgeInsets.fromLTRB(side, 2, side, 24),
                        sliver: SliverList.builder(
                          itemCount: rows,
                          itemBuilder: (context, row) {
                            return _entrance(
                              row + 1,
                              _cardRow(
                                columns: columns,
                                first: row * columns,
                                itemCount: visibleTracks.length,
                                itemBuilder: (index) {
                                  final track = visibleTracks[index];
                                  return _TrackCard(
                                    key: ValueKey('review_${track.id}_$index'),
                                    track: track,
                                    isSelected: _selectedTrackIds.contains(track.id),
                                    accent: accentColor,
                                    onTap: () => _toggleTrack(track),
                                  );
                                },
                              ),
                            );
                          },
                        ),
                      ),
                  ],
                ),
              ),
              _buildBottomBar(accentColor, isDark, side, selectedTracks),
            ],
          );
        },
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(Color accentColor, double side, int selectedCount) {
    return Padding(
      padding: EdgeInsets.fromLTRB(side, MediaQuery.of(context).padding.top + 8, side, 6),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
            style: IconButton.styleFrom(
              backgroundColor: _tint(context, 0.07),
              fixedSize: const Size(42, 42),
            ),
            onPressed: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'AI Curated Playlist',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, fontFamily: 'Outfit', letterSpacing: -0.2),
            ),
          ),
          const SizedBox(width: 10),
          // Stays in view after the header card has scrolled away
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
            decoration: BoxDecoration(
              color: accentColor.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(100),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.check_circle_rounded, size: 14, color: accentColor),
                const SizedBox(width: 5),
                Text(
                  '$selectedCount/${widget.tracks.length}',
                  style: TextStyle(
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Header card ────────────────────────────────────────────────────────────

  Widget _buildHeaderCard({
    required Color accentColor,
    required bool isDark,
    required int selectedCount,
    required List<Track> visibleTracks,
    required bool allVisibleSelected,
  }) {
    final total = widget.tracks.length;
    final base = isDark ? const Color(0xFF18181A) : Colors.white;
    final fraction = total == 0 ? 0.0 : selectedCount / total;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.alphaBlend(accentColor.withValues(alpha: isDark ? 0.30 : 0.22), base),
            base,
          ],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accentColor.withValues(alpha: 0.3)),
      ),
      child: Stack(
        children: [
          // Twinkles. On their own layer, so the text never repaints with them.
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(painter: _SparklePainter(progress: _sparkle, color: accentColor)),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    // Badge that breathes with the twinkles
                    ScaleTransition(
                      scale: TweenSequence<double>([
                        TweenSequenceItem(tween: Tween(begin: 0.94, end: 1.06), weight: 1),
                        TweenSequenceItem(tween: Tween(begin: 1.06, end: 0.94), weight: 1),
                      ]).animate(_sparkle),
                      child: Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          color: accentColor,
                          borderRadius: BorderRadius.circular(15),
                          boxShadow: [
                            BoxShadow(
                              color: accentColor.withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: Icon(Icons.auto_awesome_rounded, color: _onColor(accentColor), size: 23),
                      ),
                    ),
                    const SizedBox(width: 13),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CURATED BY AI',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w800,
                              letterSpacing: 1.1,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.7),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            '$total ${total == 1 ? 'song' : 'songs'} picked for you',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Text(
                  'Playlist Name',
                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: _muted(context)),
                ),
                const SizedBox(height: 6),
                TextField(
                  controller: _nameController,
                  textInputAction: TextInputAction.done,
                  textCapitalization: TextCapitalization.words,
                  style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, fontFamily: 'Outfit'),
                  decoration: InputDecoration(
                    hintText: 'AI Curated Playlist',
                    hintStyle: TextStyle(fontWeight: FontWeight.w600, color: _tint(context, 0.35)),
                    suffixIcon: Icon(Icons.edit_rounded, color: accentColor, size: 18),
                    filled: true,
                    fillColor: isDark ? Colors.black26 : Colors.white70,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(16),
                      borderSide: BorderSide(color: accentColor.withValues(alpha: 0.6), width: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$selectedCount of $total selected',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                          ),
                          const SizedBox(height: 7),
                          // Fills and empties as songs are kept or dropped
                          TweenAnimationBuilder<double>(
                            tween: Tween<double>(end: fraction),
                            duration: const Duration(milliseconds: 320),
                            curve: Curves.easeOutCubic,
                            builder: (context, value, _) {
                              return ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: value,
                                  minHeight: 6,
                                  color: accentColor,
                                  backgroundColor: _tint(context, 0.1),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    TextButton.icon(
                      onPressed: visibleTracks.isEmpty
                          ? null
                          : () => _toggleAllVisible(visibleTracks, allVisibleSelected),
                      icon: Icon(
                        allVisibleSelected ? Icons.deselect_rounded : Icons.select_all_rounded,
                        size: 17,
                      ),
                      label: Text(
                        allVisibleSelected ? 'Deselect (${visibleTracks.length})' : 'Select All (${visibleTracks.length})',
                      ),
                      style: TextButton.styleFrom(
                        foregroundColor: Theme.of(context).colorScheme.onSurface,
                        backgroundColor: _tint(context, 0.08),
                        padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
                        minimumSize: const Size(0, 40),
                        shape: const StadiumBorder(),
                        textStyle: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w800),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyFilter(Color accentColor) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 76,
              height: 76,
              decoration: BoxDecoration(color: _tint(context, 0.06), shape: BoxShape.circle),
              child: Icon(
                _sourceFilter == 'YT' ? Icons.smart_display_outlined : Icons.graphic_eq_rounded,
                size: 36,
                color: _muted(context),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'No $_sourceFilter tracks in this curated playlist',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: () => _setSourceFilter('All'),
              icon: const Icon(Icons.all_inclusive_rounded, size: 19),
              label: const Text('Show All Tracks'),
              style: FilledButton.styleFrom(
                backgroundColor: accentColor,
                foregroundColor: _onColor(accentColor),
                minimumSize: const Size(0, 46),
                shape: const StadiumBorder(),
                textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Bottom bar (Save & Play) ───────────────────────────────────────────────

  Widget _buildBottomBar(Color accentColor, bool isDark, double side, List<Track> selectedTracks) {
    final enabled = selectedTracks.isNotEmpty && !_busy;

    return Container(
      padding: EdgeInsets.fromLTRB(side, 12, side, MediaQuery.of(context).padding.bottom + 12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF141416) : Colors.white,
        border: Border(top: BorderSide(color: _tint(context, 0.07))),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Says why the buttons are off when nothing is selected
          AnimatedSize(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOut,
            child: selectedTracks.isEmpty
                ? Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: Text(
                      'Select at least one song to save or play',
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: _muted(context)),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
          Row(
            children: [
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? () => _savePlaylist(selectedTracks) : null,
                  icon: const Icon(Icons.bookmark_add_rounded, size: 20),
                  label: const Text('Save Playlist', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    backgroundColor: accentColor,
                    foregroundColor: _onColor(accentColor),
                    disabledBackgroundColor: _tint(context, 0.07),
                    disabledForegroundColor: _tint(context, 0.3),
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed: enabled ? () => _playNow(selectedTracks) : null,
                  icon: const Icon(Icons.play_arrow_rounded, size: 22),
                  label: const Text('Play Now', maxLines: 1, overflow: TextOverflow.ellipsis),
                  style: FilledButton.styleFrom(
                    backgroundColor: _tint(context, 0.09),
                    foregroundColor: Theme.of(context).colorScheme.onSurface,
                    disabledBackgroundColor: _tint(context, 0.04),
                    disabledForegroundColor: _tint(context, 0.3),
                    minimumSize: const Size(0, 52),
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: const StadiumBorder(),
                    textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
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

/// A song you can keep or drop. Dropped songs dim and lose their tick.
class _TrackCard extends StatelessWidget {
  const _TrackCard({
    super.key,
    required this.track,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final Track track;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  static const Duration _duration = Duration(milliseconds: 220);

  @override
  Widget build(BuildContext context) {
    return Semantics(
      checked: isSelected,
      child: AnimatedContainer(
        duration: _duration,
        curve: Curves.easeOut,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: isSelected ? accent.withValues(alpha: 0.10) : _tint(context, 0.035),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? accent.withValues(alpha: 0.45) : _tint(context, 0.06),
            width: 1.2,
          ),
        ),
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 12, 10),
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedOpacity(
                      duration: _duration,
                      opacity: isSelected ? 1.0 : 0.5,
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
                                        track.artist,
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  // Tick
                  AnimatedContainer(
                    duration: _duration,
                    curve: Curves.easeOut,
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? accent : accent.withValues(alpha: 0),
                      border: Border.all(
                        color: isSelected ? accent : _tint(context, 0.3),
                        width: 2,
                      ),
                    ),
                    child: AnimatedScale(
                      duration: _duration,
                      curve: Curves.easeOutBack,
                      scale: isSelected ? 1.0 : 0.0,
                      child: Icon(Icons.check_rounded, size: 17, color: _onColor(accent)),
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
}

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

/// All / Saavn / YT with song counts, and a pill that slides (and changes
/// color) between them.
class _SourceSegments extends StatelessWidget {
  const _SourceSegments({
    required this.selected,
    required this.accent,
    required this.allCount,
    required this.saavnCount,
    required this.ytCount,
    required this.onSelected,
  });

  final String selected;
  final Color accent;
  final int allCount;
  final int saavnCount;
  final int ytCount;
  final ValueChanged<String> onSelected;

  static const Color _saavn = Color(0xFF00D1B2);
  static const Color _youtube = Color(0xFFFF0033);

  @override
  Widget build(BuildContext context) {
    final segments = [
      ('All', Icons.all_inclusive_rounded, accent, allCount),
      ('Saavn', Icons.graphic_eq_rounded, _saavn, saavnCount),
      ('YT', Icons.smart_display_rounded, _youtube, ytCount),
    ];
    var index = segments.indexWhere((s) => s.$1 == selected);
    if (index < 0) index = 0;
    final activeColor = segments[index].$3;

    return Container(
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

  Widget _label(BuildContext context, (String, IconData, Color, int) segment, bool isSelected) {
    final foreground = isSelected ? _onColor(segment.$3) : _muted(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(segment.$2, size: 15, color: foreground),
        const SizedBox(width: 5),
        Text(
          segment.$1,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: isSelected ? FontWeight.w800 : FontWeight.w600,
            fontFamily: 'Outfit',
            color: foreground,
          ),
        ),
        const SizedBox(width: 5),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
          decoration: BoxDecoration(
            color: foreground.withValues(alpha: 0.16),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '${segment.$4}',
            style: TextStyle(fontSize: 10, fontWeight: FontWeight.w800, color: foreground),
          ),
        ),
      ],
    );
  }
}

/// Keeps the source filter pinned under the top bar while the list scrolls.
class _PinnedHeader extends SliverPersistentHeaderDelegate {
  _PinnedHeader({required this.height, required this.child});

  final double height;
  final Widget child;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return SizedBox.expand(child: child);
  }

  @override
  bool shouldRebuild(covariant _PinnedHeader oldDelegate) => true;
}

/// Four-point stars that swell and fade in turn across the header card.
/// Each one completes a whole number of cycles per loop, so it never jumps.
class _SparklePainter extends CustomPainter {
  _SparklePainter({required this.progress, required this.color}) : super(repaint: progress);

  final Animation<double> progress;
  final Color color;

  // x, y (as fractions of the card), size, cycles per loop, phase
  static const List<List<double>> _stars = [
    [0.90, 0.12, 9.0, 1, 0.00],
    [0.76, 0.22, 5.0, 2, 0.30],
    [0.95, 0.36, 4.0, 1, 0.55],
    [0.62, 0.08, 4.5, 2, 0.75],
    [0.84, 0.52, 3.5, 1, 0.20],
    [0.48, 0.16, 3.0, 1, 0.65],
  ];

  @override
  void paint(Canvas canvas, Size size) {
    final t = progress.value;
    final bright = Color.lerp(color, Colors.white, 0.45)!;

    for (final star in _stars) {
      final wave = math.sin((t * star[3] + star[4]) * math.pi * 2);
      if (wave <= 0) continue;

      final x = size.width * star[0];
      final y = size.height * star[1];
      final arm = star[2] * wave;
      final path = Path()
        ..moveTo(x, y - arm)
        ..quadraticBezierTo(x, y, x + arm, y)
        ..quadraticBezierTo(x, y, x, y + arm)
        ..quadraticBezierTo(x, y, x - arm, y)
        ..quadraticBezierTo(x, y, x, y - arm)
        ..close();
      canvas.drawPath(path, Paint()..color = bright.withValues(alpha: 0.75 * wave));
    }
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) => oldDelegate.color != color;
}