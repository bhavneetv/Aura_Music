import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show RenderSliver;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';
import '../../themes/app_theme.dart';
import '../handoff/nearby_share_screen.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Queue
//
//   Fixed header    title + [ share | save | clear ] capsule
//   Now playing     accent card
//   Up next         reorderable cards
//
// Reordering: drag the grip on the right, or press and hold anywhere on a
// row. Haptics: a light tap on pick-up, a tick each time the song passes
// another position, and a firmer tap when it is dropped in a new place.
//
// Responsive: on phones everything is one scrolling column. On wide screens
// (tablet / landscape) Now playing becomes a side panel next to the list.
// ─────────────────────────────────────────────────────────────────────────────

class QueueScreen extends ConsumerStatefulWidget {
  const QueueScreen({super.key});

  @override
  ConsumerState<QueueScreen> createState() => _QueueScreenState();
}

class _QueueScreenState extends ConsumerState<QueueScreen> {
  /// From this width up, Now playing sits beside the list.
  static const double _wideBreakpoint = 720;

  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 1040;

  /// Vertical gap between two queue cards.
  static const double _rowGap = 8;

  final ScrollController _scrollController = ScrollController();
  final GlobalKey _listKey = GlobalKey();

  // Drag tracking, used only to time the haptic ticks.
  bool _dragging = false;
  int _dragSlot = -1;
  double _pointerY = 0;

  // Layout values from the latest build, read by the drag callbacks.
  double _rowExtent = 76;
  double _listSidePadding = 20;
  int _upcomingCount = 0;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_tickIfSlotChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(playbackProvider.notifier).ensureUpcomingRecommendations();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  // ── Reorder haptics ────────────────────────────────────────────────────────

  void _onReorderStart(int index) {
    _dragging = true;
    _dragSlot = index;
    triggerHaptic(HapticFeedbackType.light);
  }

  void _onReorderEnd(int index) {
    _dragging = false;
  }

  void _onPointerMove(PointerEvent event) {
    _pointerY = event.localPosition.dy;
    _tickIfSlotChanged();
  }

  /// Works out which position the finger is over and ticks when it changes.
  /// Runs on finger movement and on scrolling, so it also ticks while the
  /// list auto-scrolls under a held song.
  void _tickIfSlotChanged() {
    if (!_dragging || _upcomingCount <= 0 || !_scrollController.hasClients) return;

    final renderObject = _listKey.currentContext?.findRenderObject();
    if (renderObject is! RenderSliver) return;

    // Finger position measured from the top of the first queue card.
    final listStart = renderObject.constraints.precedingScrollExtent;
    final y = _pointerY + _scrollController.offset - listStart;
    final slot = (y / _rowExtent).floor().clamp(0, _upcomingCount - 1).toInt();

    if (slot != _dragSlot) {
      _dragSlot = slot;
      triggerHaptic(HapticFeedbackType.selection);
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _confirmClearQueue() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'Clear the queue?',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          content: const Text('All songs will be removed from the queue.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text(
                'Clear',
                style: TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;
    triggerHaptic(HapticFeedbackType.light);
    ref.read(playbackProvider.notifier).clearQueue();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(playbackProvider);
    final notifier = ref.read(playbackProvider.notifier);
    final accentColor = ref.watch(customizationProvider).accentColor;

    final upcomingStart = (state.currentIndex >= 0 && state.currentIndex < state.queue.length)
        ? state.currentIndex + 1
        : 0;
    final upcomingTracks = state.queue.skip(upcomingStart).toList();

    // The same song can be queued twice, so a key is the id plus which
    // occurrence it is. Unlike a key built from the row number, this stays
    // with the song when other rows move.
    final seen = <String, int>{};
    final rowKeys = <Key>[];
    for (final track in upcomingTracks) {
      final id = track.id.toString();
      final occurrence = seen[id] = (seen[id] ?? 0) + 1;
      rowKeys.add(ValueKey('queue_up_${id}_$occurrence'));
    }

    // Rows have one fixed height that follows the system font size.
    final textScale = MediaQuery.textScalerOf(context).scale(100) / 100;
    final rowHeight = math.max(48.0, 40.0 * textScale) + 20;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideBreakpoint;
        final side = math.max(20.0, (constraints.maxWidth - _maxContentWidth) / 2);

        _rowExtent = rowHeight + _rowGap;
        _upcomingCount = upcomingTracks.length;
        _listSidePadding = isWide ? 0 : side;

        final currentTrack = state.currentTrack;

        Widget upNextScroller({required double sidePadding, required bool withNowPlaying}) {
          return Listener(
            onPointerDown: _onPointerMove,
            onPointerMove: _onPointerMove,
            child: CustomScrollView(
              controller: _scrollController,
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                if (withNowPlaying && currentTrack != null)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(sidePadding, 6, sidePadding, 0),
                      child: _NowPlayingCard(
                        title: currentTrack.title,
                        artist: currentTrack.artist,
                        accent: accentColor,
                        artworkBuilder: (size, radius) => AppArtworkImage(
                          artworkUrl: currentTrack.artworkUrl,
                          trackId: currentTrack.id,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(radius),
                        ),
                      ),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(sidePadding, withNowPlaying ? 22 : 6, sidePadding, 6),
                    child: _UpNextHeader(count: upcomingTracks.length, accent: accentColor),
                  ),
                ),
                if (upcomingTracks.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(sidePadding, 8, sidePadding, 150),
                      child: _EmptyQueue(accent: accentColor),
                    ),
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.only(bottom: 150),
                    sliver: SliverReorderableList(
                      key: _listKey,
                      itemCount: upcomingTracks.length,
                      itemExtent: _rowExtent,
                      proxyDecorator: _proxyDecorator,
                      onReorderStart: _onReorderStart,
                      onReorderEnd: _onReorderEnd,
                      onReorder: (oldIndex, newIndex) {
                        triggerHaptic(HapticFeedbackType.medium);
                        notifier.reorderQueue(upcomingStart + oldIndex, upcomingStart + newIndex);
                      },
                      itemBuilder: (context, index) {
                        final track = upcomingTracks[index];
                        final isRec = state.queueSources[track.id] == QueueSource.recommendation;

                        return Padding(
                          key: rowKeys[index],
                          padding: EdgeInsets.fromLTRB(sidePadding, _rowGap / 2, sidePadding, _rowGap / 2),
                          child: _QueueRow(
                            index: index,
                            title: track.title,
                            artist: track.artist,
                            isRecommendation: isRec,
                            accent: accentColor,
                            artwork: AppArtworkImage(
                              artworkUrl: track.artworkUrl,
                              trackId: track.id,
                              width: 48,
                              height: 48,
                              fit: BoxFit.cover,
                              borderRadius: BorderRadius.circular(13),
                            ),
                            onPlay: () {
                              triggerHaptic(HapticFeedbackType.selection);
                              notifier.playTrack(track);
                            },
                            onRemove: () {
                              triggerHaptic(HapticFeedbackType.light);
                              notifier.removeFromQueue(upcomingStart + index);
                            },
                          ),
                        );
                      },
                    ),
                  ),
              ],
            ),
          );
        }

        final Widget body;
        if (isWide) {
          final panelWidth = (constraints.maxWidth * 0.36).clamp(260.0, 360.0).toDouble();
          body = Padding(
            padding: EdgeInsets.symmetric(horizontal: side),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (currentTrack != null) ...[
                  SizedBox(
                    width: panelWidth,
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.only(top: 6, bottom: 150),
                      child: _NowPlayingCard(
                        large: true,
                        title: currentTrack.title,
                        artist: currentTrack.artist,
                        accent: accentColor,
                        artworkBuilder: (size, radius) => AppArtworkImage(
                          artworkUrl: currentTrack.artworkUrl,
                          trackId: currentTrack.id,
                          width: size,
                          height: size,
                          fit: BoxFit.cover,
                          borderRadius: BorderRadius.circular(radius),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 24),
                ],
                Expanded(child: upNextScroller(sidePadding: 0, withNowPlaying: false)),
              ],
            ),
          );
        } else {
          body = upNextScroller(sidePadding: side, withNowPlaying: true);
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildHeader(context, side, accentColor, state.queue.length),
            Expanded(child: body),
          ],
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context, double side, Color accentColor, int queueLength) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSongs = queueLength > 0;

    return Padding(
      padding: EdgeInsets.fromLTRB(side, MediaQuery.of(context).padding.top + 14, side, 10),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Queue',
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 30,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -0.5,
                    height: 1.1,
                    color: isDark ? AppTheme.darkTextPrimary : AppTheme.lightTextPrimary,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  hasSongs
                      ? '$queueLength ${queueLength == 1 ? 'song' : 'songs'} · drag to reorder'
                      : 'Nothing queued yet',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          _ActionCapsule(
            actions: [
              _CapsuleAction(
                icon: Icons.share_rounded,
                tooltip: 'Nearby Share & Handoff Queue',
                onPressed: () => NearbyShareScreen.showHandoffModal(context),
              ),
              _CapsuleAction(
                icon: Icons.playlist_add_check_rounded,
                tooltip: 'Save Queue as Playlist',
                onPressed: hasSongs ? () => _showSaveQueueAsPlaylistSheet(context) : null,
              ),
              _CapsuleAction(
                icon: Icons.clear_all_rounded,
                tooltip: 'Clear Queue',
                onPressed: hasSongs ? _confirmClearQueue : null,
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// How a card looks while it is being carried: lifted, solid, outlined.
  Widget _proxyDecorator(Widget child, int index, Animation<double> animation) {
    final accentColor = ref.read(customizationProvider).accentColor;
    // Queue cards are see-through; give the carried one a solid back so the
    // rows underneath do not show through it.
    final solid = Color.alphaBlend(_tint(context, 0.08), Theme.of(context).scaffoldBackgroundColor);

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final lift = Curves.easeOut.transform(animation.value.clamp(0.0, 1.0).toDouble());
        return Transform.scale(
          scale: 1 + 0.025 * lift,
          child: Stack(
            children: [
              Positioned(
                left: _listSidePadding,
                right: _listSidePadding,
                top: _rowGap / 2,
                bottom: _rowGap / 2,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: solid,
                    borderRadius: BorderRadius.circular(_QueueRow.radius),
                    border: Border.all(color: accentColor.withValues(alpha: 0.7 * lift), width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.30 * lift),
                        blurRadius: 24 * lift,
                        offset: Offset(0, 10 * lift),
                      ),
                    ],
                  ),
                ),
              ),
              Material(type: MaterialType.transparency, child: child),
            ],
          ),
        );
      },
      child: child,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SAVE AS PLAYLIST
  // ═══════════════════════════════════════════════════════════════════════════

  void _showSaveQueueAsPlaylistSheet(BuildContext context) {
    final state = ref.read(playbackProvider);
    final accentColor = ref.read(customizationProvider).accentColor;
    final messenger = ScaffoldMessenger.of(context);

    final nameController = TextEditingController(
      text: 'Queue Playlist (${DateTime.now().day}/${DateTime.now().month})',
    );
    String selectedFilter = 'all';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            final isDark = Theme.of(sheetContext).brightness == Brightness.dark;
            final userTracks = state.queue
                .where((t) => state.queueSources[t.id] == QueueSource.user || state.queueSources[t.id] == null)
                .toList();
            final recTracks =
                state.queue.where((t) => state.queueSources[t.id] == QueueSource.recommendation).toList();

            final List<dynamic> targetTracks;
            if (selectedFilter == 'user') {
              targetTracks = userTracks;
            } else if (selectedFilter == 'recommendation') {
              targetTracks = recTracks;
            } else {
              targetTracks = state.queue;
            }
            final canSave = targetTracks.isNotEmpty && nameController.text.trim().isNotEmpty;

            Widget option(String value, String label, IconData icon, int count) {
              final isSelected = selectedFilter == value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Material(
                  color: isSelected ? accentColor.withValues(alpha: 0.12) : _tint(sheetContext, 0.04),
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: isSelected ? accentColor : Colors.transparent, width: 1.5),
                  ),
                  child: InkWell(
                    onTap: () {
                      triggerHaptic(HapticFeedbackType.selection);
                      setSheetState(() => selectedFilter = value);
                    },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
                      child: Row(
                        children: [
                          Icon(icon, size: 21, color: isSelected ? accentColor : _muted(sheetContext)),
                          const SizedBox(width: 13),
                          Expanded(
                            child: Text(
                              label,
                              style: TextStyle(
                                fontSize: 14.5,
                                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w600,
                              ),
                            ),
                          ),
                          Text(
                            '$count ${count == 1 ? 'song' : 'songs'}',
                            style: TextStyle(fontSize: 12.5, color: _muted(sheetContext)),
                          ),
                          const SizedBox(width: 10),
                          Icon(
                            isSelected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
                            size: 21,
                            color: isSelected ? accentColor : _tint(sheetContext, 0.25),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            }

            return Padding(
              // Lift the sheet above the keyboard.
              padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
              child: Container(
                decoration: BoxDecoration(
                  color: isDark ? const Color(0xFF161618) : const Color(0xFFFAF8F5),
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(30)),
                ),
                child: SafeArea(
                  top: false,
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.fromLTRB(20, 10, 20, 20),
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
                        const SizedBox(height: 18),
                        Row(
                          children: [
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: accentColor.withValues(alpha: 0.14),
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Icon(Icons.playlist_add_check_rounded, color: accentColor, size: 23),
                            ),
                            const SizedBox(width: 14),
                            const Expanded(
                              child: Text(
                                'Save Queue as Playlist',
                                style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, fontFamily: 'Outfit'),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 20),

                        TextField(
                          controller: nameController,
                          textCapitalization: TextCapitalization.sentences,
                          onChanged: (_) => setSheetState(() {}),
                          decoration: InputDecoration(
                            labelText: 'Playlist name',
                            filled: true,
                            fillColor: _tint(sheetContext, 0.05),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide.none,
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(16),
                              borderSide: BorderSide(color: accentColor, width: 1.5),
                            ),
                            contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                          ),
                        ),
                        const SizedBox(height: 20),

                        Padding(
                          padding: const EdgeInsets.only(left: 4, bottom: 10),
                          child: Text(
                            'SONGS TO INCLUDE',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.1,
                              color: _muted(sheetContext),
                            ),
                          ),
                        ),
                        option('all', 'Whole queue', Icons.queue_music_rounded, state.queue.length),
                        option('user', 'Added by you', Icons.person_rounded, userTracks.length),
                        option('recommendation', 'Recommended', Icons.auto_awesome_rounded, recTracks.length),
                        const SizedBox(height: 14),

                        SizedBox(
                          width: double.infinity,
                          height: 54,
                          child: FilledButton(
                            // Greyed out when there is no name or nothing to save.
                            onPressed: !canSave
                                ? null
                                : () async {
                                    final name = nameController.text.trim();
                                    if (name.isEmpty || targetTracks.isEmpty) return;

                                    final playlists = StorageService.getPlaylists();
                                    final newPl = {
                                      'id': DateTime.now().millisecondsSinceEpoch.toString(),
                                      'name': name,
                                      'description': 'Created from active queue (${targetTracks.length} tracks)',
                                      'trackIds': targetTracks.map((t) => t.id).toList(),
                                      'tracks': targetTracks.map((t) => t.toJson()).toList(),
                                    };
                                    playlists.add(newPl);
                                    await StorageService.savePlaylists(playlists);

                                    if (sheetContext.mounted) Navigator.pop(sheetContext);
                                    triggerHaptic(HapticFeedbackType.light);
                                    messenger.showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          'Saved "$name" with ${targetTracks.length} '
                                          '${targetTracks.length == 1 ? 'track' : 'tracks'}',
                                          style: TextStyle(
                                            color: _onColor(accentColor),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        backgroundColor: accentColor,
                                        behavior: SnackBarBehavior.floating,
                                      ),
                                    );
                                  },
                            style: FilledButton.styleFrom(
                              backgroundColor: accentColor,
                              foregroundColor: _onColor(accentColor),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                              textStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15.5),
                            ),
                            child: const Text('Save playlist'),
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

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

class _CapsuleAction {
  const _CapsuleAction({required this.icon, required this.tooltip, required this.onPressed});

  final IconData icon;
  final String tooltip;

  /// Null shows the button faded and switched off.
  final VoidCallback? onPressed;
}

/// A row of icon buttons inside one rounded capsule, split by hairlines.
class _ActionCapsule extends StatelessWidget {
  const _ActionCapsule({required this.actions});

  final List<_CapsuleAction> actions;

  @override
  Widget build(BuildContext context) {
    final onSurface = Theme.of(context).colorScheme.onSurface;

    return Material(
      color: _tint(context, 0.07),
      clipBehavior: Clip.antiAlias,
      shape: StadiumBorder(side: BorderSide(color: _tint(context, 0.08))),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0) Container(width: 1, height: 18, color: _tint(context, 0.12)),
            Tooltip(
              message: actions[i].tooltip,
              child: InkWell(
                onTap: actions[i].onPressed,
                child: SizedBox(
                  width: 46,
                  height: 44,
                  child: Icon(
                    actions[i].icon,
                    size: 21,
                    color: onSurface.withValues(alpha: actions[i].onPressed == null ? 0.28 : 0.9),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// The song playing right now. Compact (a row) on phones, [large] (artwork on
/// top) when it is the side panel on wide screens.
class _NowPlayingCard extends StatelessWidget {
  const _NowPlayingCard({
    required this.title,
    required this.artist,
    required this.accent,
    required this.artworkBuilder,
    this.large = false,
  });

  final String title;
  final String artist;
  final Color accent;
  final bool large;

  /// Builds the artwork at the given square size and corner radius.
  final Widget Function(double size, double radius) artworkBuilder;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final label = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.graphic_eq_rounded, color: accent, size: 15),
        const SizedBox(width: 6),
        Text(
          'NOW PLAYING',
          style: TextStyle(
            fontSize: 10.5,
            fontWeight: FontWeight.w800,
            letterSpacing: 1.2,
            color: _muted(context),
          ),
        ),
      ],
    );

    Widget shadowed(Widget artwork, double radius) {
      return DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.28),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: artwork,
      );
    }

    final Widget content;
    if (large) {
      content = LayoutBuilder(
        builder: (context, constraints) {
          final size = constraints.maxWidth;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              shadowed(artworkBuilder(size, 22), 22),
              const SizedBox(height: 18),
              label,
              const SizedBox(height: 8),
              Text(
                title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontFamily: 'Outfit',
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                artist,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 14, color: _muted(context)),
              ),
            ],
          );
        },
      );
    } else {
      content = Row(
        children: [
          shadowed(artworkBuilder(64, 18), 18),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                label,
                const SizedBox(height: 6),
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 2),
                Text(
                  artist,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 13, color: _muted(context)),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
            child: Icon(Icons.volume_up_rounded, color: _onColor(accent), size: 20),
          ),
        ],
      );
    }

    return Container(
      padding: EdgeInsets.all(large ? 16 : 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [accent.withValues(alpha: 0.32), const Color(0xFF1C1C20)]
              : [accent.withValues(alpha: 0.22), Colors.white],
        ),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: accent.withValues(alpha: 0.28)),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: isDark ? 0.12 : 0.16),
            blurRadius: 22,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: content,
    );
  }
}

class _UpNextHeader extends StatelessWidget {
  const _UpNextHeader({required this.count, required this.accent});

  final int count;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Text(
          'Up next',
          style: TextStyle(fontFamily: 'Outfit', fontSize: 20, fontWeight: FontWeight.w800, letterSpacing: -0.3),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
          decoration: BoxDecoration(
            color: _tint(context, 0.08),
            borderRadius: BorderRadius.circular(100),
          ),
          child: Text(
            '$count',
            style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: _muted(context)),
          ),
        ),
        const SizedBox(width: 12),
        // Takes the rest of the row; the chip shrinks rather than overflowing.
        Expanded(
          child: Align(
            alignment: Alignment.centerRight,
            child: FittedBox(
              fit: BoxFit.scaleDown,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: accent.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.auto_awesome_rounded, size: 13, color: accent),
                    const SizedBox(width: 5),
                    Text(
                      'Smart recommendations on',
                      style: TextStyle(color: accent, fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// One upcoming song. Tap to play. Press and hold the row, or drag the grip
/// on the right, to move it.
class _QueueRow extends StatelessWidget {
  const _QueueRow({
    required this.index,
    required this.title,
    required this.artist,
    required this.isRecommendation,
    required this.accent,
    required this.artwork,
    required this.onPlay,
    required this.onRemove,
  });

  static const double radius = 18;

  final int index;
  final String title;
  final String artist;
  final bool isRecommendation;
  final Color accent;
  final Widget artwork;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final isNext = index == 0;

    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radius),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Everything except the grip: tap plays, press-and-hold drags.
          Expanded(
            child: ReorderableDelayedDragStartListener(
              index: index,
              child: InkWell(
                onTap: onPlay,
                child: Row(
                  children: [
                    SizedBox(
                      width: 36,
                      child: Text(
                        '${index + 1}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontFamily: 'Outfit',
                          fontSize: 14.5,
                          fontWeight: FontWeight.w800,
                          color: isNext ? accent : _muted(context),
                        ),
                      ),
                    ),
                    artwork,
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5, height: 1.25),
                          ),
                          const SizedBox(height: 3),
                          Row(
                            children: [
                              if (isRecommendation) ...[
                                Icon(
                                  Icons.auto_awesome_rounded,
                                  size: 12,
                                  color: accent,
                                  semanticLabel: 'Recommended for you',
                                ),
                                const SizedBox(width: 4),
                              ],
                              Flexible(
                                child: Text(
                                  artist,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(fontSize: 12.5, height: 1.25, color: _muted(context)),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Remove from queue',
                      visualDensity: VisualDensity.compact,
                      onPressed: onRemove,
                      icon: Icon(Icons.close_rounded, size: 18, color: _tint(context, 0.45)),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // The grip: drags straight away, no hold needed.
          ReorderableDragStartListener(
            index: index,
            child: Semantics(
              label: 'Reorder',
              child: Container(
                width: 42,
                color: Colors.transparent,
                alignment: Alignment.center,
                child: Icon(Icons.drag_indicator_rounded, size: 22, color: _tint(context, 0.38)),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyQueue extends StatelessWidget {
  const _EmptyQueue({required this.accent});

  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 76,
            height: 76,
            decoration: BoxDecoration(color: accent.withValues(alpha: 0.14), shape: BoxShape.circle),
            child: Icon(Icons.queue_music_rounded, size: 36, color: accent),
          ),
          const SizedBox(height: 18),
          const Text(
            'Nothing up next',
            textAlign: TextAlign.center,
            style: TextStyle(fontFamily: 'Outfit', fontSize: 19, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            'Search for songs or play something to fill your queue.',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13.5, height: 1.45, color: _muted(context)),
          ),
        ],
      ),
    );
  }
}