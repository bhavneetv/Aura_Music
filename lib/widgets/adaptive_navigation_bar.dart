import 'dart:io';
import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cupertino_native/cupertino_native.dart';
import '../providers/playback_provider.dart';

/// Platform detection helper for OS-specific rendering
class PlatformInfo {
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// The iOS major version (26, 27, ...), or 0 when not on iOS or when the
  /// version cannot be read. Worked out once, then remembered.
  ///
  /// Platform.operatingSystemVersion looks like "Version 26.1 (Build 23B82)".
  /// Note: an app built with an Xcode older than 26 is told "19" by iOS 26,
  /// and gets no Liquid Glass either, so falling back to the Flutter glass
  /// bar in that case is the correct result.
  static final int iosMajorVersion = _readIOSMajorVersion();

  static int _readIOSMajorVersion() {
    if (!isIOS) return 0;
    try {
      final version = Platform.operatingSystemVersion;
      final match = RegExp(r'Version\s+(\d+)').firstMatch(version) ?? RegExp(r'(\d+)').firstMatch(version);
      if (match != null) {
        return int.tryParse(match.group(1)!) ?? 0;
      }
    } catch (_) {}
    return 0;
  }

  /// Detection for iOS 26+ (26, 27, ...) Liquid Glass capabilities.
  static bool isIOS26OrHigher() => iosMajorVersion >= 26;
}

/// Destination model for Adaptive Navigation Bar
class AdaptiveNavigationDestination {
  final dynamic icon;
  final dynamic selectedIcon;
  final String label;
  final bool isSearch;

  const AdaptiveNavigationDestination({
    required this.icon,
    this.selectedIcon,
    required this.label,
    this.isSearch = false,
  });
}

/// Adaptive Navigation Bar Widget supporting Default Floating Glass and Native OS Style
/// (iOS 26+ Liquid Glass / Android 16 Material 3)
///
/// Both the glass bar and the native iOS bar follow the iOS 26 layout: the
/// tabs sit in a floating capsule and Search is a separate round button at
/// the trailing side. Pass `detachSearch: false` to keep Search inside the
/// capsule with the other tabs.
class AdaptiveNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveNavigationDestination> destinations;
  final String navBarStyle; // 'default' or 'os_style'
  final Color accentColor;

  /// Shows the Search destination as its own round button (iOS 26 style).
  final bool detachSearch;

  const AdaptiveNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.navBarStyle,
    required this.accentColor,
    this.detachSearch = true,
  });

  // ── Native iOS tab bar geometry ───────────────────────────────────────────
  // The native bar is given the same frame a real UITabBar has: full width,
  // touching the bottom of the screen, 49 pt tall plus the home-indicator
  // inset (83 pt on Face ID iPhones). UIKit then places the floating glass
  // capsule itself. If the bar looks cut off or sits too low/high on a
  // device, these two numbers are the ones to adjust.
  static const double _iosTabBarHeight = 49;
  static const double _iosTabBarMinHeight = 72;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (navBarStyle == 'os_style') {
      if (PlatformInfo.isIOS && PlatformInfo.isIOS26OrHigher()) {
        return _buildIOSLiquidGlassNavigationBar(context, isDark);
      } else if (PlatformInfo.isIOS) {
        // iOS below 26 — CNTabBar (Liquid Glass) not available, use default glass bar
        return _buildDefaultFloatingGlassBar(context, isDark);
      } else {
        return _buildAndroidMaterial3NavigationBar(context, isDark);
      }
    }

    // Default: App's custom floating glass capsule nav bar
    return _buildDefaultFloatingGlassBar(context, isDark);
  }

  // ── Search placement ──────────────────────────────────────────────────────

  bool _isSearchDestination(AdaptiveNavigationDestination dest) {
    if (dest.isSearch) return true;
    final icon = dest.icon;
    if (icon is IconData) {
      return icon == Icons.search || icon == Icons.search_rounded || icon == Icons.search_outlined;
    }
    if (icon is String) return icon.contains('search') || icon.contains('magnifyingglass');
    return false;
  }

  /// Index (in [destinations]) of the Search tab when it should be shown as
  /// a separate button, or -1 when every tab stays in the capsule.
  int get _detachedSearchIndex {
    // With fewer than three destinations there is nothing left to group.
    if (!detachSearch || destinations.length < 3) return -1;
    return destinations.indexWhere(_isSearchDestination);
  }

  /// [destinations] indices in the order they are shown: the capsule's tabs
  /// first, then the detached Search button (if any) last.
  List<int> _displayOrder(int searchIndex) {
    return [
      for (var i = 0; i < destinations.length; i++)
        if (i != searchIndex) i,
      if (searchIndex >= 0) searchIndex,
    ];
  }

  // ── 1. iOS 26+ Stock "Liquid Glass" Navigation Bar ────────────────────────
  Widget _buildIOSLiquidGlassNavigationBar(BuildContext context, bool isDark) {
    final searchIndex = _detachedSearchIndex;
    final order = _displayOrder(searchIndex);
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final brightness = isDark ? Brightness.dark : Brightness.light;

    // The native bar reads light/dark from the surrounding theme, so both are
    // pinned to the app's own setting (which may differ from the system's).
    return MediaQuery(
      data: MediaQuery.of(context).copyWith(platformBrightness: brightness),
      child: CupertinoTheme(
        data: CupertinoThemeData(brightness: brightness, primaryColor: accentColor),
        child: CNTabBar(
          currentIndex: math.max(0, order.indexOf(selectedIndex)),
          onTap: (position) {
            if (position < 0 || position >= order.length) return;
            triggerHaptic(HapticFeedbackType.light);
            onDestinationSelected(order[position]);
          },
          tint: accentColor,
          height: math.max(_iosTabBarHeight + bottomInset, _iosTabBarMinHeight),
          // Full width, like a real tab bar; UIKit centers the capsule.
          shrinkCentered: false,
          // iOS 26 layout: tabs in one capsule, Search in its own on the right.
          split: searchIndex >= 0,
          rightCount: 1,
          // The items never change with the selection. (Swapping symbols on
          // every tap made the native bar rebuild its items, which cut the
          // glass selection animation short.)
          items: [
            for (final index in order)
              if (index == searchIndex)
                const CNTabBarItem(icon: CNSymbol('magnifyingglass'))
              else
                CNTabBarItem(
                  icon: CNSymbol(_getIOSSFSymbolName(destinations[index])),
                  label: destinations[index].label,
                ),
          ],
        ),
      ),
    );
  }

  // ── 2. Android 16 Stock Material 3 Navigation Bar ────────────────────────
  Widget _buildAndroidMaterial3NavigationBar(BuildContext context, bool isDark) {
    return NavigationBarTheme(
      data: NavigationBarThemeData(
        height: 64,
        backgroundColor: isDark ? const Color(0xFF1E1E22) : const Color(0xFFF3F3F7),
        indicatorColor: accentColor.withValues(alpha: 0.22),
        elevation: 3,
        surfaceTintColor: Colors.transparent,
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return TextStyle(
            fontSize: 12,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? (isDark ? Colors.white : Colors.black87) : Colors.grey,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final isSelected = states.contains(WidgetState.selected);
          return IconThemeData(
            size: 24,
            color: isSelected ? accentColor : (isDark ? Colors.white60 : Colors.black54),
          );
        }),
      ),
      child: NavigationBar(
        selectedIndex: selectedIndex,
        onDestinationSelected: (index) {
          triggerHaptic(HapticFeedbackType.light);
          onDestinationSelected(index);
        },
        destinations: destinations.map((dest) {
          final IconData iconData = _getAndroidIcon(dest.icon, isSelected: false);
          final IconData selectedIconData = _getAndroidIcon(dest.selectedIcon ?? dest.icon, isSelected: true);

          return NavigationDestination(
            icon: Icon(iconData),
            selectedIcon: Icon(selectedIconData),
            label: dest.label,
          );
        }).toList(),
      ),
    );
  }

  // ── 3. Default App Floating Glass Navigation Bar (iOS 26 style) ──────────
  Widget _buildDefaultFloatingGlassBar(BuildContext context, bool isDark) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;

    // iOS 26 floats its bar low, just above the home indicator. On Android the
    // bar stays clear of the system navigation buttons.
    final double bottomMargin;
    if (bottomInset <= 0) {
      bottomMargin = 16.0;
    } else if (PlatformInfo.isIOS) {
      bottomMargin = math.max(bottomInset - 10.0, 14.0);
    } else {
      bottomMargin = bottomInset + 8.0;
    }

    final searchIndex = _detachedSearchIndex;

    _GlassTabSpec specFor(int index) {
      final dest = destinations[index];
      return _GlassTabSpec(
        index: index,
        label: dest.label,
        icon: _getAndroidIcon(dest.icon, isSelected: false),
        selectedIcon: _getAndroidIcon(dest.selectedIcon ?? dest.icon, isSelected: true),
      );
    }

    void select(int index) {
      triggerHaptic(HapticFeedbackType.light);
      onDestinationSelected(index);
    }

    return MediaQuery.withClampedTextScaling(
      // Like the system bar, the labels grow only a little with large text.
      maxScaleFactor: 1.15,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomMargin),
        child: Center(
          heightFactor: 1,
          child: ConstrainedBox(
            // Stays a compact capsule on tablets and in landscape
            constraints: const BoxConstraints(maxWidth: 560),
            child: Row(
              children: [
                Expanded(
                  child: _GlassTabCapsule(
                    tabs: [
                      for (var i = 0; i < destinations.length; i++)
                        if (i != searchIndex) specFor(i),
                    ],
                    selectedIndex: selectedIndex,
                    accent: accentColor,
                    onSelected: select,
                  ),
                ),
                if (searchIndex >= 0) ...[
                  const SizedBox(width: 10),
                  _GlassSearchButton(
                    spec: specFor(searchIndex),
                    isSelected: selectedIndex == searchIndex,
                    accent: accentColor,
                    onTap: () => select(searchIndex),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Icons ─────────────────────────────────────────────────────────────────

  /// Material icon → SF Symbol. Tab bars use the filled symbols throughout
  /// (Apple's own convention); the selected tab is shown by the tint.
  static final Map<IconData, String> _sfSymbols = {
    for (final icon in [Icons.home, Icons.home_rounded, Icons.home_outlined, Icons.home_filled]) icon: 'house.fill',
    for (final icon in [Icons.search, Icons.search_rounded, Icons.search_outlined]) icon: 'magnifyingglass',
    for (final icon in [Icons.library_music, Icons.library_music_rounded, Icons.library_music_outlined])
      icon: 'music.note.list',
    for (final icon in [Icons.queue_music, Icons.queue_music_rounded, Icons.queue_music_outlined])
      icon: 'list.bullet.indent',
    for (final icon in [Icons.settings, Icons.settings_rounded, Icons.settings_outlined]) icon: 'gearshape.fill',
    for (final icon in [
      Icons.person,
      Icons.person_rounded,
      Icons.person_outline,
      Icons.person_outline_rounded,
      Icons.person_outlined,
      Icons.account_circle,
      Icons.account_circle_rounded,
      Icons.account_circle_outlined,
    ])
      icon: 'person.fill',
    for (final icon in [
      Icons.favorite,
      Icons.favorite_rounded,
      Icons.favorite_border,
      Icons.favorite_border_rounded,
      Icons.favorite_outline,
    ])
      icon: 'heart.fill',
    for (final icon in [Icons.history, Icons.history_rounded, Icons.history_outlined]) icon: 'clock.fill',
    for (final icon in [Icons.explore, Icons.explore_rounded, Icons.explore_outlined]) icon: 'safari.fill',
    for (final icon in [
      Icons.album,
      Icons.album_rounded,
      Icons.album_outlined,
      Icons.music_note,
      Icons.music_note_rounded,
      Icons.music_note_outlined,
    ])
      icon: 'music.note',
    for (final icon in [Icons.download, Icons.download_rounded, Icons.download_outlined])
      icon: 'arrow.down.circle.fill',
    for (final icon in [Icons.radio, Icons.radio_rounded, Icons.radio_outlined]) icon: 'dot.radiowaves.left.and.right',
    for (final icon in [
      Icons.equalizer,
      Icons.equalizer_rounded,
      Icons.equalizer_outlined,
      Icons.graphic_eq,
      Icons.graphic_eq_rounded,
      Icons.graphic_eq_outlined,
    ])
      icon: 'waveform',
    for (final icon in [
      Icons.insights,
      Icons.insights_rounded,
      Icons.insights_outlined,
      Icons.bar_chart,
      Icons.bar_chart_rounded,
      Icons.bar_chart_outlined,
    ])
      icon: 'chart.bar.fill',
  };

  String _getIOSSFSymbolName(AdaptiveNavigationDestination dest) {
    if (dest.isSearch) return 'magnifyingglass';

    for (final val in [dest.selectedIcon, dest.icon]) {
      if (val is IconData) {
        final symbol = _sfSymbols[val];
        if (symbol != null) return symbol;
      }
      if (val is String) {
        if (val.contains('house')) return 'house.fill';
        if (val.contains('person')) return 'person.fill';
        if (val.contains('search') || val.contains('magnifyingglass')) return 'magnifyingglass';
        // Anything else that looks like an SF Symbol name is used as it is,
        // so a destination can ask for a specific symbol (e.g. 'heart.fill').
        if (RegExp(r'^[a-z0-9]+(\.[a-z0-9]+)*$').hasMatch(val)) return val;
      }
    }

    // Unknown icon: a neutral dot. (It used to fall back to the Home icon,
    // which gave you two "houses" in the bar.)
    return 'circle.fill';
  }

  IconData _getAndroidIcon(dynamic val, {required bool isSelected}) {
    if (val is IconData) return val;
    if (val is String) {
      if (val.contains('house')) return isSelected ? Icons.home : Icons.home_outlined;
      if (val.contains('person')) return isSelected ? Icons.person : Icons.person_outline;
      if (val.contains('search')) return Icons.search;
    }
    return isSelected ? Icons.circle : Icons.circle_outlined;
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// FLOATING GLASS BAR
//
// A Flutter take on iOS 26 "Liquid Glass": a see-through capsule that blurs
// what is behind it, a bright rim, and a lens that slides to the selected tab.
// ═════════════════════════════════════════════════════════════════════════════

const double _barHeight = 64;

/// Movement with a small overshoot, so the lens settles like liquid.
const Cubic _liquid = Cubic(0.3, 1.3, 0.5, 1.0);

class _GlassTabSpec {
  const _GlassTabSpec({
    required this.index,
    required this.label,
    required this.icon,
    required this.selectedIcon,
  });

  /// Position in the caller's destinations list.
  final int index;
  final String label;
  final IconData icon;
  final IconData selectedIcon;
}

/// The capsule that holds the tabs.
class _GlassTabCapsule extends StatefulWidget {
  const _GlassTabCapsule({
    required this.tabs,
    required this.selectedIndex,
    required this.accent,
    required this.onSelected,
  });

  final List<_GlassTabSpec> tabs;
  final int selectedIndex;
  final Color accent;
  final ValueChanged<int> onSelected;

  @override
  State<_GlassTabCapsule> createState() => _GlassTabCapsuleState();
}

class _GlassTabCapsuleState extends State<_GlassTabCapsule> {
  /// Where the lens last was. When Search (outside the capsule) is selected,
  /// the lens fades out in place instead of sliding away.
  int _lensPosition = 0;

  int get _selectedPosition => widget.tabs.indexWhere((tab) => tab.index == widget.selectedIndex);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedPosition = _selectedPosition;
    if (selectedPosition >= 0) _lensPosition = selectedPosition;
    final lensPosition = _lensPosition.clamp(0, math.max(0, widget.tabs.length - 1)).toInt();

    const inset = 5.0;

    return SizedBox(
      height: _barHeight,
      child: _Glass(
        radius: _barHeight / 2,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = math.max(1, widget.tabs.length);
            final tabWidth = math.max(0.0, (constraints.maxWidth - inset * 2) / count);

            return Stack(
              children: [
                // The lens behind the selected tab
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 420),
                  curve: _liquid,
                  start: inset + lensPosition * tabWidth,
                  top: inset,
                  bottom: inset,
                  width: tabWidth,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: selectedPosition >= 0 ? 1.0 : 0.0,
                    child: _Lens(accent: widget.accent, isDark: isDark),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(inset),
                  child: Row(
                    children: [
                      for (final tab in widget.tabs)
                        Expanded(
                          child: _GlassTab(
                            spec: tab,
                            isSelected: tab.index == widget.selectedIndex,
                            accent: widget.accent,
                            showLabel: true,
                            onTap: () => widget.onSelected(tab.index),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// The round Search button beside the capsule.
class _GlassSearchButton extends StatelessWidget {
  const _GlassSearchButton({
    required this.spec,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final _GlassTabSpec spec;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return SizedBox(
      width: _barHeight,
      height: _barHeight,
      child: _Glass(
        radius: _barHeight / 2,
        child: Stack(
          fit: StackFit.expand,
          children: [
            Padding(
              padding: const EdgeInsets.all(5),
              child: AnimatedOpacity(
                duration: const Duration(milliseconds: 220),
                opacity: isSelected ? 1.0 : 0.0,
                child: _Lens(accent: accent, isDark: isDark),
              ),
            ),
            _GlassTab(
              spec: spec,
              isSelected: isSelected,
              accent: accent,
              showLabel: false,
              onTap: onTap,
            ),
          ],
        ),
      ),
    );
  }
}

/// The highlight behind the selected tab: a lighter, accent-tinted bubble.
class _Lens extends StatelessWidget {
  const _Lens({required this.accent, required this.isDark});

  final Color accent;
  final bool isDark;

  @override
  Widget build(BuildContext context) {
    final base = (isDark ? Colors.white : Colors.black).withValues(alpha: isDark ? 0.09 : 0.05);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: Color.alphaBlend(accent.withValues(alpha: 0.17), base),
        borderRadius: BorderRadius.circular(100),
        border: Border.all(
          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.55),
          width: 0.8,
        ),
      ),
    );
  }
}

/// One tab: icon over label. Dips while pressed; color and size ease between
/// the selected and unselected look.
class _GlassTab extends StatefulWidget {
  const _GlassTab({
    required this.spec,
    required this.isSelected,
    required this.accent,
    required this.showLabel,
    required this.onTap,
  });

  final _GlassTabSpec spec;
  final bool isSelected;
  final Color accent;
  final bool showLabel;
  final VoidCallback onTap;

  @override
  State<_GlassTab> createState() => _GlassTabState();
}

class _GlassTabState extends State<_GlassTab> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.62);

    return Semantics(
      button: true,
      selected: widget.isSelected,
      label: widget.spec.label,
      excludeSemantics: true,
      onTap: widget.onTap,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: AnimatedScale(
          scale: _pressed ? 0.9 : 1.0,
          duration: const Duration(milliseconds: 130),
          curve: Curves.easeOut,
          child: TweenAnimationBuilder<double>(
            tween: Tween<double>(end: widget.isSelected ? 1.0 : 0.0),
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutCubic,
            builder: (context, t, _) {
              final color = Color.lerp(inactive, widget.accent, t)!;

              return Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Transform.scale(
                    scale: 1.0 + 0.07 * t,
                    child: Icon(
                      t > 0.5 ? widget.spec.selectedIcon : widget.spec.icon,
                      color: color,
                      size: widget.showLabel ? 23 : 25,
                    ),
                  ),
                  if (widget.showLabel) ...[
                    const SizedBox(height: 2),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 4),
                      child: Text(
                        widget.spec.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: color,
                          fontWeight: t > 0.5 ? FontWeight.w700 : FontWeight.w600,
                          fontSize: 10.5,
                          height: 1.2,
                          fontFamily: 'Outfit',
                        ),
                      ),
                    ),
                  ],
                ],
              );
            },
          ),
        ),
      ),
    );
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// GLASS SURFACE
// ═════════════════════════════════════════════════════════════════════════════

/// A see-through surface: blurs what is behind it, adds a light tint and a
/// soft sheen across the top, then a bright rim and a shadow around it.
///
/// The tint and the rim are painted on top of the blur. (Before, the border
/// was painted underneath it, so the blur smeared it away.)
class _Glass extends StatelessWidget {
  const _Glass({required this.radius, required this.child});

  final double radius;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final fill = isDark ? const Color(0xFF1B1B1F).withValues(alpha: 0.58) : Colors.white.withValues(alpha: 0.64);

    return CustomPaint(
      painter: _GlassShadowPainter(radius: radius, isDark: isDark),
      foregroundPainter: _GlassRimPainter(radius: radius, isDark: isDark),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.white.withValues(alpha: isDark ? 0.10 : 0.45),
                    Colors.white.withValues(alpha: 0),
                  ],
                  stops: const [0.0, 0.5],
                ),
              ),
              child: child,
            ),
          ),
        ),
      ),
    );
  }
}

/// Shadow drawn only outside the shape, so it never darkens the glass itself.
class _GlassShadowPainter extends CustomPainter {
  const _GlassShadowPainter({required this.radius, required this.isDark});

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    const blur = 18.0;
    const offset = Offset(0, 8);
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(radius));

    canvas.save();
    canvas.clipPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(rect.inflate(blur * 3 + offset.dy))
        ..addRRect(shape),
    );
    canvas.drawRRect(
      shape.shift(offset),
      Paint()
        ..color = Colors.black.withValues(alpha: isDark ? 0.45 : 0.16)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, blur),
    );
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GlassShadowPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.isDark != isDark;
  }
}

/// The edge of the glass: brightest at the top-left, where light would catch
/// it, fading around the shape and picking up again at the bottom-right.
class _GlassRimPainter extends CustomPainter {
  const _GlassRimPainter({required this.radius, required this.isDark});

  final double radius;
  final bool isDark;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect.deflate(0.5), Radius.circular(radius));

    // In light mode a faint dark line keeps the edge visible on white pages.
    if (!isDark) {
      canvas.drawRRect(
        shape,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.0
          ..color = Colors.black.withValues(alpha: 0.07),
      );
    }

    final bright = isDark ? 0.36 : 0.95;
    final dim = isDark ? 0.07 : 0.30;
    final mid = isDark ? 0.18 : 0.60;

    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0
        ..shader = LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.white.withValues(alpha: bright),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: dim),
            Colors.white.withValues(alpha: mid),
          ],
          stops: const [0.0, 0.38, 0.7, 1.0],
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _GlassRimPainter oldDelegate) {
    return oldDelegate.radius != radius || oldDelegate.isDark != isDark;
  }
}