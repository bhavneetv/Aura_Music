import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import '../../models/track.dart';
import '../../providers/playback_provider.dart';
import '../../providers/customization_provider.dart';
import '../../services/storage/storage_service.dart';
import '../../widgets/app_artwork_image.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Listening insights & history
//
//   Summary     hero card (time listened) + three stat tiles
//   Switcher    sliding pill: History · Top artists · Top songs
//               (tap a segment or swipe left/right; it stays pinned on scroll)
//   Content     cards for the selected tab
//
// Responsive: content is capped and centered on wide screens, the summary
// sits side by side there, and card lists go from one column to two.
// ─────────────────────────────────────────────────────────────────────────────

class RecentlyPlayedScreen extends ConsumerStatefulWidget {
  const RecentlyPlayedScreen({super.key});

  @override
  ConsumerState<RecentlyPlayedScreen> createState() => _RecentlyPlayedScreenState();
}

class _RecentlyPlayedScreenState extends ConsumerState<RecentlyPlayedScreen>
    with SingleTickerProviderStateMixin {
  /// Content never grows wider than this; extra space becomes side margins.
  static const double _maxContentWidth = 860;

  /// From this content width up, cards go two per row.
  static const double _twoColumnWidth = 620;

  /// How many entries the "Top" tabs show.
  static const int _topLimit = 20;

  static const List<_Segment> _segments = [
    _Segment('History', Icons.history_rounded),
    _Segment('Top artists', Icons.mic_rounded),
    _Segment('Top songs', Icons.music_note_rounded),
  ];

  late _Insights _insights;
  int _tab = 0;

  late final AnimationController _tabFadeController;
  late final Animation<double> _tabFade;

  @override
  void initState() {
    super.initState();
    _insights = _Insights.from(StorageService.getListeningHistory(), _topLimit);
    _tabFadeController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      value: 1.0,
    );
    _tabFade = CurvedAnimation(parent: _tabFadeController, curve: Curves.easeOut);
  }

  @override
  void dispose() {
    _tabFadeController.dispose();
    super.dispose();
  }

  /// Re-reads the history and recomputes every stat once, instead of on
  /// every rebuild.
  void _loadHistory() {
    setState(() {
      _insights = _Insights.from(StorageService.getListeningHistory(), _topLimit);
    });
  }

  void _selectTab(int index) {
    if (index == _tab) return;
    setState(() {
      _tab = index;
    });
    _tabFadeController.forward(from: 0);
  }

  void _onSwipe(DragEndDetails details) {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity.abs() < 300) return;
    final next = (_tab + (velocity < 0 ? 1 : -1)).clamp(0, _segments.length - 1).toInt();
    _selectTab(next);
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: const Text(
            'Clear listening history?',
            style: TextStyle(fontWeight: FontWeight.bold, fontFamily: 'Outfit'),
          ),
          content: const Text(
            'This removes your entire listening history and resets your insights. It cannot be undone.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.redAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text('Clear all', style: TextStyle(fontWeight: FontWeight.bold)),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;
    await StorageService.clearListeningHistory();
    if (mounted) _loadHistory();
  }

  Future<void> _removePlay(_Play play) async {
    await StorageService.deleteHistoryItem(play.timestampRaw);
    if (mounted) _loadHistory();
  }

  void _play(Track track) {
    ref.read(playbackProvider.notifier).playTrack(track);
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // SCREEN
  // ═══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    final accentColor = ref.watch(customizationProvider).accentColor;
    final background = Theme.of(context).scaffoldBackgroundColor;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          tooltip: 'Back',
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Listening Insights',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 19, fontFamily: 'Outfit'),
        ),
        actions: [
          if (_insights.plays.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.redAccent),
              tooltip: 'Clear history',
              onPressed: _clearHistory,
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          // Cap the content width and center it on tablets / landscape.
          final side = math.max(16.0, (constraints.maxWidth - _maxContentWidth) / 2);
          final contentWidth = constraints.maxWidth - side * 2;
          final isWide = contentWidth >= _twoColumnWidth;
          final columns = isWide ? 2 : 1;

          return GestureDetector(
            behavior: HitTestBehavior.translucent,
            onHorizontalDragEnd: _onSwipe,
            child: CustomScrollView(
              physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
              slivers: [
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 8, side, 0),
                  sliver: SliverToBoxAdapter(child: _buildSummary(isWide, accentColor)),
                ),
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _PinnedBarDelegate(
                    height: 74,
                    child: Container(
                      color: background,
                      padding: EdgeInsets.fromLTRB(side, 14, side, 12),
                      child: _SlidingSegments(
                        segments: _segments,
                        selected: _tab,
                        accent: accentColor,
                        onSelected: _selectTab,
                      ),
                    ),
                  ),
                ),
                SliverPadding(
                  padding: EdgeInsets.fromLTRB(side, 2, side, 120),
                  sliver: SliverFadeTransition(
                    opacity: _tabFade,
                    sliver: SliverMainAxisGroup(
                      slivers: _buildTabSlivers(columns, accentColor),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── Summary ────────────────────────────────────────────────────────────────

  Widget _buildSummary(bool isWide, Color accentColor) {
    final insights = _insights;

    final hero = _HeroCard(
      accent: accentColor,
      value: _formatListening(insights.totalSeconds),
      caption: insights.plays.isEmpty
          ? 'Play something to start your stats'
          : '${_plural(insights.artistCount, 'artist')} · ${_plural(insights.songCount, 'song')}',
      pill: 'Today · ${_formatListening(insights.todaySeconds)}',
    );

    final tiles = [
      _StatTile(
        icon: Icons.local_fire_department_rounded,
        value: _plural(insights.streakDays, 'day'),
        label: 'Listening streak',
        accent: accentColor,
      ),
      _StatTile(
        icon: Icons.play_circle_fill_rounded,
        value: NumberFormat.decimalPattern().format(insights.plays.length),
        label: 'Songs played',
        accent: accentColor,
      ),
      _StatTile(
        icon: Icons.album_rounded,
        value: insights.topGenre ?? '—',
        label: 'Top genre',
        accent: accentColor,
      ),
    ];

    final tileRow = Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < tiles.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: tiles[i]),
        ],
      ],
    );

    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(flex: 5, child: hero),
            const SizedBox(width: 12),
            Expanded(flex: 6, child: tileRow),
          ],
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        hero,
        const SizedBox(height: 10),
        IntrinsicHeight(child: tileRow),
      ],
    );
  }

  // ── Tabs ───────────────────────────────────────────────────────────────────

  List<Widget> _buildTabSlivers(int columns, Color accentColor) {
    if (_insights.plays.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: _EmptyCard(
            icon: Icons.history_toggle_off_rounded,
            title: 'Nothing here yet',
            message: 'Songs you play show up here, along with your top artists and listening time.',
          ),
        ),
      ];
    }

    switch (_tab) {
      case 1:
        return _buildArtistSlivers(columns, accentColor);
      case 2:
        return _buildSongSlivers(columns, accentColor);
      default:
        return _buildHistorySlivers(columns, accentColor);
    }
  }

  /// Lays cards out [columns] per row without fixed heights, so cards grow
  /// with the system font size instead of clipping.
  Widget _cardRows({
    required int columns,
    required int itemCount,
    required Widget Function(int index) itemBuilder,
  }) {
    return SliverList.builder(
      itemCount: (itemCount / columns).ceil(),
      itemBuilder: (context, row) {
        final first = row * columns;
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
                        child: first + column < itemCount
                            ? itemBuilder(first + column)
                            : const SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }

  List<Widget> _buildHistorySlivers(int columns, Color accentColor) {
    final sections = [
      _Section('Today', _insights.today, showDate: false),
      _Section('Yesterday', _insights.yesterday, showDate: false),
      _Section('Earlier', _insights.earlier, showDate: true),
    ];

    return [
      for (final section in sections)
        if (section.plays.isNotEmpty) ...[
          SliverToBoxAdapter(
            child: _SectionLabel(
              label: section.label,
              trailing: _plural(section.plays.length, 'song'),
            ),
          ),
          _cardRows(
            columns: columns,
            itemCount: section.plays.length,
            itemBuilder: (index) {
              final play = section.plays[index];
              return _HistoryCard(
                play: play,
                showDate: section.showDate,
                accent: accentColor,
                onPlay: () => _play(play.track),
                onRemove: () => _removePlay(play),
              );
            },
          ),
        ],
    ];
  }

  List<Widget> _buildArtistSlivers(int columns, Color accentColor) {
    final artists = _insights.topArtists;
    if (artists.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: _EmptyCard(
            icon: Icons.mic_off_rounded,
            title: 'No artists yet',
            message: 'Your history has no artist names to rank yet.',
          ),
        ),
      ];
    }

    final top = artists.first;
    final rest = artists.sublist(1);
    // Rank by time when there is any; fall back to plays for old entries
    // that were saved without a listening time.
    final byTime = top.seconds > 0;

    return [
      SliverToBoxAdapter(
        child: _SectionLabel(
          label: 'Most listened',
          trailing: byTime ? 'By listening time' : 'By number of plays',
        ),
      ),
      SliverToBoxAdapter(
        child: _FeaturedCard(
          accent: accentColor,
          overline: '#1 · Top artist',
          title: top.title,
          artwork: _artworkFor(top.sample, 88, round: true),
          artworkRadius: _artworkRadius(88, round: true),
          chips: [
            _StatChip(icon: Icons.schedule_rounded, label: _formatListening(top.seconds)),
            _StatChip(icon: Icons.play_arrow_rounded, label: _plural(top.plays, 'play')),
            _StatChip(icon: Icons.music_note_rounded, label: _plural(top.songCount, 'song')),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      _cardRows(
        columns: columns,
        itemCount: rest.length,
        itemBuilder: (index) {
          final artist = rest[index];
          return _RankCard(
            rank: index + 2,
            title: artist.title,
            subtitle: byTime
                ? '${_plural(artist.plays, 'play')} · ${_plural(artist.songCount, 'song')}'
                : _plural(artist.songCount, 'song'),
            value: byTime ? _formatListening(artist.seconds) : _plural(artist.plays, 'play'),
            fraction: byTime ? artist.seconds / top.seconds : artist.plays / top.plays,
            artwork: _artworkFor(artist.sample, 48, round: true),
            accent: accentColor,
          );
        },
      ),
      const SliverToBoxAdapter(
        child: _Footnote(
          'A song with several singers counts toward each of them. Pictures come from the artist\'s songs in your history.',
        ),
      ),
    ];
  }

  List<Widget> _buildSongSlivers(int columns, Color accentColor) {
    final songs = _insights.topSongs;
    final top = songs.first;
    final rest = songs.sublist(1);

    return [
      const SliverToBoxAdapter(
        child: _SectionLabel(label: 'Most played', trailing: 'By number of plays'),
      ),
      SliverToBoxAdapter(
        child: _FeaturedCard(
          accent: accentColor,
          overline: '#1 · Top song',
          title: top.title,
          subtitle: top.subtitle,
          artwork: _artworkFor(top.sample, 88),
          artworkRadius: _artworkRadius(88),
          onPlay: () => _play(top.sample),
          chips: [
            _StatChip(icon: Icons.play_arrow_rounded, label: _plural(top.plays, 'play')),
            _StatChip(icon: Icons.schedule_rounded, label: _formatListening(top.seconds)),
          ],
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 10)),
      _cardRows(
        columns: columns,
        itemCount: rest.length,
        itemBuilder: (index) {
          final song = rest[index];
          return _RankCard(
            rank: index + 2,
            title: song.title,
            subtitle: '${song.subtitle} · ${_formatListening(song.seconds)}',
            value: _plural(song.plays, 'play'),
            fraction: song.plays / top.plays,
            artwork: _artworkFor(song.sample, 48),
            accent: accentColor,
            onTap: () => _play(song.sample),
          );
        },
      ),
    ];
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// DATA
// ═════════════════════════════════════════════════════════════════════════════

/// One entry of the listening history, parsed once.
class _Play {
  _Play({
    required this.timestampRaw,
    required this.time,
    required this.id,
    required this.title,
    required this.artist,
    required this.artistRaw,
    required this.genre,
    required this.seconds,
    required this.track,
  });

  factory _Play.fromMap(Map<String, dynamic> item) {
    final timestampRaw = item['timestamp']?.toString() ?? '';
    final id = item['track_id']?.toString() ?? '';
    final title = item['title']?.toString() ?? 'Track';
    final artistRaw = item['artist']?.toString().trim() ?? '';
    final artist = item['artist']?.toString() ?? 'Unknown Artist';
    final genre = item['genre']?.toString() ?? '';
    final played = double.tryParse(item['durationPlayed']?.toString() ?? '') ?? 0.0;

    return _Play(
      timestampRaw: timestampRaw,
      time: DateTime.tryParse(timestampRaw)?.toLocal(),
      id: id,
      title: title,
      artist: artist,
      artistRaw: artistRaw,
      genre: genre.trim(),
      seconds: played.isFinite && played > 0 ? played : 0.0,
      track: Track(
        id: id,
        title: title,
        artist: artist,
        album: item['album']?.toString() ?? 'Single',
        duration: item['duration']?.toString() ?? '3:30',
        artworkUrl: item['artworkUrl']?.toString() ?? '',
        audioUrl: item['audioUrl']?.toString() ?? '',
        genre: genre,
      ),
    );
  }

  /// The stored timestamp, exactly as saved (it is the key for deleting).
  final String timestampRaw;
  final DateTime? time;

  final String id;
  final String title;

  /// Artist text for display ("Unknown Artist" when the entry has none).
  final String artist;

  /// Artist text as stored; empty when the entry has none.
  final String artistRaw;
  final String genre;

  /// How long this play actually lasted.
  final double seconds;

  /// The track to hand to the player.
  final Track track;

  String get songKey => id.isNotEmpty ? id : '$title|$artist'.toLowerCase();
}

/// A ranked artist or song.
class _Ranked {
  _Ranked({required this.title, required this.subtitle, required this.sample});

  final String title;
  final String subtitle;

  /// A track to borrow artwork from (and to play, for songs).
  final Track sample;

  double seconds = 0;
  int plays = 0;
  final Set<String> _songs = {};

  int get songCount => _songs.length;

  void add(_Play play) {
    seconds += play.seconds;
    plays++;
    _songs.add(play.songKey);
  }
}

class _Section {
  const _Section(this.label, this.plays, {required this.showDate});

  final String label;
  final List<_Play> plays;
  final bool showDate;
}

class _Segment {
  const _Segment(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// Everything the screen shows, computed in one pass over the history.
class _Insights {
  _Insights._({
    required this.plays,
    required this.today,
    required this.yesterday,
    required this.earlier,
    required this.totalSeconds,
    required this.todaySeconds,
    required this.streakDays,
    required this.topGenre,
    required this.artistCount,
    required this.songCount,
    required this.topArtists,
    required this.topSongs,
  });

  factory _Insights.from(List<Map<String, dynamic>> history, int topLimit) {
    final now = DateTime.now();
    final todayDate = DateTime(now.year, now.month, now.day);
    final yesterdayDate = DateTime(now.year, now.month, now.day - 1);

    final plays = <_Play>[];
    final today = <_Play>[];
    final yesterday = <_Play>[];
    final earlier = <_Play>[];
    final activeDays = <DateTime>{};
    final genreCounts = <String, int>{};
    final artists = <String, _Ranked>{};
    final songs = <String, _Ranked>{};
    var totalSeconds = 0.0;
    var todaySeconds = 0.0;

    for (final item in history) {
      final play = _Play.fromMap(item);
      plays.add(play);
      totalSeconds += play.seconds;

      // Timeline bucket
      final time = play.time;
      if (time == null) {
        earlier.add(play);
      } else {
        final day = DateTime(time.year, time.month, time.day);
        activeDays.add(day);
        if (day == todayDate) {
          today.add(play);
          todaySeconds += play.seconds;
        } else if (day == yesterdayDate) {
          yesterday.add(play);
        } else {
          earlier.add(play);
        }
      }

      // Genre (entries without one are left out rather than guessed)
      final genre = play.genre;
      if (genre.isNotEmpty) {
        genreCounts[genre] = (genreCounts[genre] ?? 0) + 1;
      }

      // Artists: "A, B" credits both A and B
      for (final name in play.artistRaw.split(',')) {
        final artist = name.trim();
        if (artist.isEmpty) continue;
        artists
            .putIfAbsent(
              artist.toLowerCase(),
              () => _Ranked(title: artist, subtitle: '', sample: play.track),
            )
            .add(play);
      }

      // Songs
      songs
          .putIfAbsent(
            play.songKey,
            () => _Ranked(title: play.title, subtitle: play.artist, sample: play.track),
          )
          .add(play);
    }

    String? topGenre;
    var topGenreCount = 0;
    genreCounts.forEach((genre, count) {
      if (count > topGenreCount) {
        topGenreCount = count;
        topGenre = genre;
      }
    });

    final rankedArtists = artists.values.toList()
      ..sort((a, b) {
        final byTime = b.seconds.compareTo(a.seconds);
        return byTime != 0 ? byTime : b.plays.compareTo(a.plays);
      });
    final rankedSongs = songs.values.toList()
      ..sort((a, b) {
        final byPlays = b.plays.compareTo(a.plays);
        return byPlays != 0 ? byPlays : b.seconds.compareTo(a.seconds);
      });

    return _Insights._(
      plays: plays,
      today: today,
      yesterday: yesterday,
      earlier: earlier,
      totalSeconds: totalSeconds,
      todaySeconds: todaySeconds,
      streakDays: _streak(activeDays, todayDate),
      topGenre: topGenre,
      artistCount: artists.length,
      songCount: songs.length,
      topArtists: rankedArtists.take(topLimit).toList(),
      topSongs: rankedSongs.take(topLimit).toList(),
    );
  }

  /// Consecutive days with at least one play, ending today (or yesterday, so
  /// the streak is not lost before today's first song).
  static int _streak(Set<DateTime> activeDays, DateTime today) {
    var cursor = today;
    if (!activeDays.contains(cursor)) {
      cursor = DateTime(today.year, today.month, today.day - 1);
      if (!activeDays.contains(cursor)) return 0;
    }

    var streak = 0;
    while (activeDays.contains(cursor)) {
      streak++;
      cursor = DateTime(cursor.year, cursor.month, cursor.day - 1);
    }
    return streak;
  }

  final List<_Play> plays;
  final List<_Play> today;
  final List<_Play> yesterday;
  final List<_Play> earlier;
  final double totalSeconds;
  final double todaySeconds;
  final int streakDays;
  final String? topGenre;
  final int artistCount;
  final int songCount;
  final List<_Ranked> topArtists;
  final List<_Ranked> topSongs;
}

// ═════════════════════════════════════════════════════════════════════════════
// HELPERS
// ═════════════════════════════════════════════════════════════════════════════

/// "1h 12m", "34 min", "45s".
String _formatListening(double seconds) {
  final total = seconds.round();
  if (total <= 0) return '0 min';
  if (total < 60) return '${total}s';
  final hours = total ~/ 3600;
  final minutes = (total % 3600) ~/ 60;
  if (hours == 0) return '$minutes min';
  return minutes == 0 ? '${hours}h' : '${hours}h ${minutes}m';
}

String _plural(int count, String noun) => '$count $noun${count == 1 ? '' : 's'}';

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

double _artworkRadius(double size, {bool round = false}) => round ? size / 2 : size * 0.24;

Widget _artworkFor(Track track, double size, {bool round = false}) {
  return AppArtworkImage(
    artworkUrl: track.artworkUrl,
    trackId: track.id,
    width: size,
    height: size,
    fit: BoxFit.cover,
    borderRadius: BorderRadius.circular(_artworkRadius(size, round: round)),
  );
}

BoxDecoration _cardDecoration(BuildContext context) {
  return BoxDecoration(
    color: _tint(context, 0.045),
    borderRadius: BorderRadius.circular(20),
    border: Border.all(color: _tint(context, 0.06)),
  );
}

// ═════════════════════════════════════════════════════════════════════════════
// SUMMARY CARDS
// ═════════════════════════════════════════════════════════════════════════════

/// The big gradient card: total time listened.
class _HeroCard extends StatelessWidget {
  const _HeroCard({
    required this.accent,
    required this.value,
    required this.caption,
    required this.pill,
  });

  final Color accent;
  final String value;
  final String caption;
  final String pill;

  @override
  Widget build(BuildContext context) {
    final on = _onColor(accent);
    final hsl = HSLColor.fromColor(accent);
    final deep = hsl
        .withHue((hsl.hue + 16) % 360)
        .withLightness((hsl.lightness * 0.74).clamp(0.0, 1.0).toDouble())
        .toColor();

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(26),
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [accent, deep],
        ),
        boxShadow: [
          BoxShadow(
            color: accent.withValues(alpha: 0.28),
            blurRadius: 26,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: CustomPaint(
        painter: _GroovesPainter(color: on.withValues(alpha: 0.09)),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 18, 20, 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Row(
                children: [
                  Icon(Icons.headphones_rounded, size: 16, color: on.withValues(alpha: 0.8)),
                  const SizedBox(width: 6),
                  Text(
                    'TIME LISTENED',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1.3,
                      color: on.withValues(alpha: 0.8),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(
                  value,
                  maxLines: 1,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 44,
                    fontWeight: FontWeight.w900,
                    letterSpacing: -1,
                    height: 1.0,
                    color: on,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                caption,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                  color: on.withValues(alpha: 0.8),
                ),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: on.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(100),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.today_rounded, size: 14, color: on),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(
                        pill,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: on),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Faint record grooves in the corner of the hero card.
class _GroovesPainter extends CustomPainter {
  const _GroovesPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width - 6, size.height * 0.5);
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    final reach = math.min(size.height * 0.95, size.width * 0.42);
    for (var radius = 22.0; radius < reach; radius += 15) {
      canvas.drawCircle(center, radius, paint);
    }
    canvas.drawCircle(center, 9, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _GroovesPainter oldDelegate) => oldDelegate.color != color;
}

class _StatTile extends StatelessWidget {
  const _StatTile({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final String value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.14),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, size: 20, color: accent),
          ),
          const SizedBox(height: 14),
          // Shrinks long values ("Bollywood") instead of cutting them off.
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: Text(
              value,
              maxLines: 1,
              style: const TextStyle(
                fontFamily: 'Outfit',
                fontSize: 20,
                fontWeight: FontWeight.w800,
                height: 1.1,
              ),
            ),
          ),
          const SizedBox(height: 3),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 11.5, color: _muted(context)),
          ),
        ],
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// SLIDING SWITCHER
// ═════════════════════════════════════════════════════════════════════════════

/// Segmented control whose highlight pill slides between the options.
class _SlidingSegments extends StatelessWidget {
  const _SlidingSegments({
    required this.segments,
    required this.selected,
    required this.accent,
    required this.onSelected,
  });

  final List<_Segment> segments;
  final int selected;
  final Color accent;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final on = _onColor(accent);
    final last = segments.length - 1;

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: _tint(context, 0.07),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Stack(
        children: [
          // The pill
          Positioned.fill(
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 260),
              curve: Curves.easeOutCubic,
              alignment: Alignment(last == 0 ? 0 : -1 + 2 * selected / last, 0),
              child: FractionallySizedBox(
                widthFactor: 1 / segments.length,
                heightFactor: 1,
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(12),
                    boxShadow: [
                      BoxShadow(
                        color: accent.withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // The labels
          Row(
            children: [
              for (var i = 0; i < segments.length; i++)
                Expanded(
                  child: Semantics(
                    button: true,
                    selected: i == selected,
                    child: GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () => onSelected(i),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 11),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              TweenAnimationBuilder<Color?>(
                                duration: const Duration(milliseconds: 220),
                                tween: ColorTween(end: i == selected ? on : _muted(context)),
                                builder: (context, color, _) {
                                  return Icon(segments[i].icon, size: 16, color: color);
                                },
                              ),
                              const SizedBox(width: 6),
                              AnimatedDefaultTextStyle(
                                duration: const Duration(milliseconds: 220),
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: i == selected ? FontWeight.w800 : FontWeight.w600,
                                  color: i == selected ? on : _muted(context),
                                ),
                                child: Text(segments[i].label, maxLines: 1),
                              ),
                            ],
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
}

/// Keeps the switcher stuck to the top while the cards scroll under it.
class _PinnedBarDelegate extends SliverPersistentHeaderDelegate {
  _PinnedBarDelegate({required this.height, required this.child});

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
  bool shouldRebuild(covariant _PinnedBarDelegate oldDelegate) => true;
}

// ═════════════════════════════════════════════════════════════════════════════
// CONTENT CARDS
// ═════════════════════════════════════════════════════════════════════════════

class _SectionLabel extends StatelessWidget {
  const _SectionLabel({required this.label, this.trailing});

  final String label;
  final String? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 12, 4, 10),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(fontFamily: 'Outfit', fontSize: 17, fontWeight: FontWeight.w800),
            ),
          ),
          if (trailing != null)
            Text(
              trailing!,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: _muted(context)),
            ),
        ],
      ),
    );
  }
}

class _Footnote extends StatelessWidget {
  const _Footnote(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 6, 4, 0),
      child: Text(
        text,
        style: TextStyle(fontSize: 11.5, height: 1.4, color: _muted(context)),
      ),
    );
  }
}

/// One played song in the timeline.
class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.play,
    required this.showDate,
    required this.accent,
    required this.onPlay,
    required this.onRemove,
  });

  final _Play play;
  final bool showDate;
  final Color accent;
  final VoidCallback onPlay;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final time = play.time;
    final when = time == null
        ? null
        : DateFormat(showDate ? 'd MMM, h:mm a' : 'h:mm a').format(time);

    return Material(
      color: _tint(context, 0.045),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: _tint(context, 0.06)),
      ),
      child: InkWell(
        onTap: onPlay,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 10, 4, 10),
          child: Row(
            children: [
              _artworkFor(play.track, 54),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      play.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      play.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.5, color: _muted(context)),
                    ),
                    if (when != null) ...[
                      const SizedBox(height: 5),
                      Row(
                        children: [
                          Icon(Icons.schedule_rounded, size: 12, color: _tint(context, 0.4)),
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              play.seconds >= 1
                                  ? '$when · ${_formatListening(play.seconds)}'
                                  : when,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 11.5, color: _tint(context, 0.5)),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Play
              IconButton(
                tooltip: 'Play',
                onPressed: onPlay,
                icon: Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                  child: Icon(Icons.play_arrow_rounded, size: 22, color: _onColor(accent)),
                ),
              ),
              // Remove
              IconButton(
                tooltip: 'Remove from history',
                visualDensity: VisualDensity.compact,
                onPressed: onRemove,
                icon: Icon(Icons.close_rounded, size: 18, color: _tint(context, 0.45)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _tint(context, 0.08),
        borderRadius: BorderRadius.circular(100),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.75)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// The #1 artist / song, shown larger than the rest.
class _FeaturedCard extends StatelessWidget {
  const _FeaturedCard({
    required this.accent,
    required this.overline,
    required this.title,
    required this.artwork,
    required this.artworkRadius,
    required this.chips,
    this.subtitle,
    this.onPlay,
  });

  final Color accent;
  final String overline;
  final String title;
  final String? subtitle;
  final Widget artwork;

  /// Corner radius of [artwork], so the accent ring around it matches.
  final double artworkRadius;
  final List<Widget> chips;

  /// When set, the card is tappable and shows a play button.
  final VoidCallback? onPlay;

  @override
  Widget build(BuildContext context) {
    final on = _onColor(accent);

    return Material(
      color: Colors.transparent,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(26),
        side: BorderSide(color: accent.withValues(alpha: 0.32), width: 1.5),
      ),
      child: Ink(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              accent.withValues(alpha: 0.26),
              accent.withValues(alpha: 0.05),
            ],
          ),
        ),
        child: InkWell(
          onTap: onPlay,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                // Artwork with an accent ring
                Container(
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(artworkRadius + 3),
                  ),
                  child: artwork,
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: accent,
                          borderRadius: BorderRadius.circular(100),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.emoji_events_rounded, size: 13, color: on),
                            const SizedBox(width: 4),
                            Text(
                              overline.toUpperCase(),
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.6,
                                color: on,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 9),
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
                      if (subtitle != null) ...[
                        const SizedBox(height: 3),
                        Text(
                          subtitle!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(fontSize: 13, color: _muted(context)),
                        ),
                      ],
                      const SizedBox(height: 11),
                      Wrap(spacing: 6, runSpacing: 6, children: chips),
                    ],
                  ),
                ),
                if (onPlay != null) ...[
                  const SizedBox(width: 10),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                    child: Icon(Icons.play_arrow_rounded, size: 26, color: on),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// A ranked row: position, picture, name, a bar comparing it to #1, and the
/// headline number on the right.
class _RankCard extends StatelessWidget {
  const _RankCard({
    required this.rank,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.fraction,
    required this.artwork,
    required this.accent,
    this.onTap,
  });

  final int rank;
  final String title;
  final String subtitle;
  final String value;

  /// Share of the #1 entry, 0–1.
  final double fraction;
  final Widget artwork;
  final Color accent;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final share = fraction.isFinite ? fraction.clamp(0.03, 1.0).toDouble() : 0.03;

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
          padding: const EdgeInsets.fromLTRB(6, 12, 14, 12),
          child: Row(
            children: [
              SizedBox(
                width: 34,
                child: Text(
                  '$rank',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontFamily: 'Outfit',
                    fontSize: 17,
                    fontWeight: FontWeight.w800,
                    color: rank <= 3 ? null : _muted(context),
                  ),
                ),
              ),
              artwork,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Expanded(
                          child: Text(
                            title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14.5),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          value,
                          style: const TextStyle(
                            fontFamily: 'Outfit',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12, color: _muted(context)),
                    ),
                    const SizedBox(height: 9),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        height: 5,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            ColoredBox(color: _tint(context, 0.08)),
                            FractionallySizedBox(
                              alignment: Alignment.centerLeft,
                              widthFactor: share,
                              child: DecoratedBox(
                                decoration: BoxDecoration(
                                  color: accent,
                                  borderRadius: BorderRadius.circular(3),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyCard extends StatelessWidget {
  const _EmptyCard({required this.icon, required this.title, required this.message});

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      decoration: _cardDecoration(context),
      child: Column(
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: _tint(context, 0.06), shape: BoxShape.circle),
            child: Icon(icon, size: 30, color: _muted(context)),
          ),
          const SizedBox(height: 16),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(fontFamily: 'Outfit', fontSize: 18, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            message,
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 13, height: 1.45, color: _muted(context)),
          ),
        ],
      ),
    );
  }
}