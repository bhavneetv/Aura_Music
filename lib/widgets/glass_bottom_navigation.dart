import 'dart:math' as math;
import 'dart:ui';
import 'package:flutter/material.dart';

// ═════════════════════════════════════════════════════════════════════════════
// GLASS BOTTOM BAR
//
// A Flutter take on iOS 26 "Liquid Glass": see-through capsules that blur
// what is behind them, with a bright rim and a lens that slides to the
// selected item. Search is its own round button beside the bar.
//
// The public classes and their parameters are the same as before.
// ═════════════════════════════════════════════════════════════════════════════

/// Platform behavior mode for glass action buttons
enum GlassActionButtonMode {
  nativeLiquidGlassOnIOS26,
  flutter,
}

/// Glass Action Icon Types
enum GlassActionIcon {
  back,
  more,
  custom,
}

/// Item model for GlassBarItem
class GlassBarItem {
  final IconData icon;
  final String label;
  final String? nativeSymbolName;

  const GlassBarItem({
    required this.icon,
    required this.label,
    this.nativeSymbolName,
  });
}

/// Action item model for GlassActionButton
class GlassActionButtonItem {
  final GlassActionIcon type;
  final IconData? icon;
  final String? nativeSymbolName;
  final String? semanticLabel;
  final VoidCallback? onTap;

  const GlassActionButtonItem({
    this.type = GlassActionIcon.custom,
    this.icon,
    this.nativeSymbolName,
    this.semanticLabel,
    this.onTap,
  });

  factory GlassActionButtonItem.back({VoidCallback? onTap}) {
    return GlassActionButtonItem(
      type: GlassActionIcon.back,
      icon: Icons.arrow_back_rounded,
      nativeSymbolName: 'chevron.left',
      semanticLabel: 'Back',
      onTap: onTap,
    );
  }

  factory GlassActionButtonItem.more({VoidCallback? onTap}) {
    return GlassActionButtonItem(
      type: GlassActionIcon.more,
      icon: Icons.more_horiz_rounded,
      nativeSymbolName: 'ellipsis',
      semanticLabel: 'More Options',
      onTap: onTap,
    );
  }
}

/// Customization knobs for GlassBottomBar styling
class GlassBottomNavStyle {
  final Color? accent;
  final double? height;
  final double? widthFactor;
  final GlassActionButtonMode actionButtonMode;

  /// Tint laid over the blur. Keep it see-through (alpha around 0.6).
  final Color? pillTint;
  final double? pillBlurSigma;

  /// Sheen across the top half of the glass: from this color...
  final Color? pillFilmStart;

  /// ...to this one.
  final Color? pillFilmEnd;

  /// Accent opacity at the top of the lens behind the selected item...
  final double? selectedStartOpacity;

  /// ...and at its bottom.
  final double? selectedEndOpacity;

  /// Size of the magnifier icon inside the round Search button.
  final double? searchButtonSize;

  /// Space between the bar and the buttons beside it.
  final double? searchGap;

  const GlassBottomNavStyle({
    this.accent,
    this.height,
    this.widthFactor,
    this.actionButtonMode = GlassActionButtonMode.nativeLiquidGlassOnIOS26,
    this.pillTint,
    this.pillBlurSigma,
    this.pillFilmStart,
    this.pillFilmEnd,
    this.selectedStartOpacity,
    this.selectedEndOpacity,
    this.searchButtonSize,
    this.searchGap,
  });
}

/// Glass Action Button Widget
class GlassActionButton extends StatelessWidget {
  final GlassActionButtonItem item;

  const GlassActionButton({
    super.key,
    required this.item,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final IconData displayIcon = item.icon ??
        (item.type == GlassActionIcon.back
            ? Icons.arrow_back_rounded
            : (item.type == GlassActionIcon.more ? Icons.more_horiz_rounded : Icons.tune_rounded));

    return Semantics(
      label: item.semanticLabel ?? 'Action',
      button: true,
      child: _Pressable(
        onTap: item.onTap,
        child: SizedBox(
          width: 44,
          height: 44,
          child: _Glass(
            radius: 22,
            child: Center(
              child: Icon(
                displayIcon,
                size: 20,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Row container for grouping Glass Action Buttons
class GlassActionButtonRow extends StatelessWidget {
  final List<GlassActionButtonItem> actions;

  const GlassActionButtonRow({
    super.key,
    required this.actions,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: actions.map((act) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 4),
          child: GlassActionButton(item: act),
        );
      }).toList(),
    );
  }
}

/// Main Liquid Glass Bottom Navigation Bar Widget
class GlassBottomBar extends StatelessWidget {
  final List<GlassBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double? width;
  final double? height;
  final VoidCallback? onSearchTap;
  final List<GlassActionButtonItem>? leadingActions;
  final List<GlassActionButtonItem>? trailingActions;
  final GlassBottomNavStyle? style;

  const GlassBottomBar({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
    this.width,
    this.height,
    this.onSearchTap,
    this.leadingActions,
    this.trailingActions,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final effectiveAccent = style?.accent ?? Theme.of(context).colorScheme.primary;
    final barHeight = height ?? style?.height ?? 60.0;
    final gap = style?.searchGap ?? 8.0;

    Widget barContent = _GlassBarCapsule(
      items: items,
      currentIndex: currentIndex,
      onTap: onTap,
      height: barHeight,
      accent: effectiveAccent,
      style: style,
    );

    // Optional Search Button: its own round piece of glass beside the bar
    if (onSearchTap != null) {
      barContent = Row(
        children: [
          Expanded(child: barContent),
          SizedBox(width: gap),
          Semantics(
            label: 'Search',
            button: true,
            child: _Pressable(
              onTap: onSearchTap,
              child: SizedBox(
                width: barHeight,
                height: barHeight,
                child: _Glass(
                  radius: barHeight / 2,
                  blurSigma: style?.pillBlurSigma,
                  tint: style?.pillTint,
                  sheenStart: style?.pillFilmStart,
                  sheenEnd: style?.pillFilmEnd,
                  child: Center(
                    child: Icon(
                      Icons.search_rounded,
                      color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                      size: style?.searchButtonSize ?? 22,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      );
    }

    if (width != null) {
      barContent = SizedBox(width: width, child: barContent);
    } else if (style?.widthFactor != null) {
      barContent = FractionallySizedBox(widthFactor: style!.widthFactor, child: barContent);
    }

    // Attach optional leading / trailing actions beside the bar
    if (leadingActions != null || trailingActions != null) {
      barContent = Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leadingActions != null) ...[
            GlassActionButtonRow(actions: leadingActions!),
            SizedBox(width: gap),
          ],
          Flexible(child: barContent),
          if (trailingActions != null) ...[
            SizedBox(width: gap),
            GlassActionButtonRow(actions: trailingActions!),
          ],
        ],
      );
    }

    // Like the system bar, the labels grow only a little with large text.
    return MediaQuery.withClampedTextScaling(maxScaleFactor: 1.15, child: barContent);
  }
}

// ═════════════════════════════════════════════════════════════════════════════
// PIECES
// ═════════════════════════════════════════════════════════════════════════════

/// Movement with a small overshoot, so the lens settles like liquid.
const Cubic _liquid = Cubic(0.3, 1.3, 0.5, 1.0);

/// The capsule that holds the items, with the lens behind the selected one.
class _GlassBarCapsule extends StatelessWidget {
  const _GlassBarCapsule({
    required this.items,
    required this.currentIndex,
    required this.onTap,
    required this.height,
    required this.accent,
    required this.style,
  });

  final List<GlassBarItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;
  final double height;
  final Color accent;
  final GlassBottomNavStyle? style;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final hasSelection = currentIndex >= 0 && currentIndex < items.length;
    final lensIndex = currentIndex.clamp(0, math.max(0, items.length - 1)).toInt();
    final startOpacity = style?.selectedStartOpacity ?? 0.22;
    final endOpacity = style?.selectedEndOpacity ?? 0.13;

    const inset = 5.0;

    return SizedBox(
      height: height,
      child: _Glass(
        radius: height / 2,
        blurSigma: style?.pillBlurSigma,
        tint: style?.pillTint,
        sheenStart: style?.pillFilmStart,
        sheenEnd: style?.pillFilmEnd,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final count = math.max(1, items.length);
            final cellWidth = math.max(0.0, (constraints.maxWidth - inset * 2) / count);

            return Stack(
              children: [
                // The lens behind the selected item
                AnimatedPositionedDirectional(
                  duration: const Duration(milliseconds: 420),
                  curve: _liquid,
                  start: inset + lensIndex * cellWidth,
                  top: inset,
                  bottom: inset,
                  width: cellWidth,
                  child: AnimatedOpacity(
                    duration: const Duration(milliseconds: 220),
                    opacity: hasSelection ? 1.0 : 0.0,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [
                            accent.withValues(alpha: startOpacity),
                            accent.withValues(alpha: endOpacity),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(height / 2),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: isDark ? 0.14 : 0.55),
                          width: 0.8,
                        ),
                      ),
                    ),
                  ),
                ),

                // Bar items layout
                Padding(
                  padding: const EdgeInsets.all(inset),
                  child: Row(
                    children: [
                      for (var index = 0; index < items.length; index++)
                        Expanded(
                          child: _GlassBarTab(
                            item: items[index],
                            isSelected: currentIndex == index,
                            accent: accent,
                            onTap: () => onTap(index),
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

/// One item: an icon, with its label sliding out beside it when selected.
class _GlassBarTab extends StatelessWidget {
  const _GlassBarTab({
    required this.item,
    required this.isSelected,
    required this.accent,
    required this.onTap,
  });

  final GlassBarItem item;
  final bool isSelected;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final inactive = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.6);

    return Semantics(
      button: true,
      selected: isSelected,
      label: item.label,
      excludeSemantics: true,
      onTap: onTap,
      child: _Pressable(
        onTap: onTap,
        child: TweenAnimationBuilder<double>(
          tween: Tween<double>(end: isSelected ? 1.0 : 0.0),
          duration: const Duration(milliseconds: 260),
          curve: Curves.easeOutCubic,
          builder: (context, t, _) {
            final color = Color.lerp(inactive, accent, t)!;

            return Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(item.icon, size: 22, color: color),
                  Flexible(
                    child: AnimatedSize(
                      duration: const Duration(milliseconds: 280),
                      curve: Curves.easeOutCubic,
                      alignment: AlignmentDirectional.centerStart,
                      child: isSelected
                          ? Padding(
                              padding: const EdgeInsetsDirectional.only(start: 5),
                              child: Text(
                                item.label,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                softWrap: false,
                                style: TextStyle(
                                  color: color,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 12,
                                  fontFamily: 'Outfit',
                                ),
                              ),
                            )
                          : const SizedBox(height: 22),
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Makes its child dip slightly while pressed.
class _Pressable extends StatefulWidget {
  const _Pressable({required this.onTap, required this.child});

  final VoidCallback? onTap;
  final Widget child;

  @override
  State<_Pressable> createState() => _PressableState();
}

class _PressableState extends State<_Pressable> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (mounted && _pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: enabled ? (_) => _setPressed(true) : null,
      onTapUp: enabled ? (_) => _setPressed(false) : null,
      onTapCancel: enabled ? () => _setPressed(false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.9 : 1.0,
        duration: const Duration(milliseconds: 130),
        curve: Curves.easeOut,
        child: widget.child,
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
  const _Glass({
    required this.radius,
    required this.child,
    this.blurSigma,
    this.tint,
    this.sheenStart,
    this.sheenEnd,
  });

  final double radius;
  final Widget child;
  final double? blurSigma;
  final Color? tint;
  final Color? sheenStart;
  final Color? sheenEnd;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final sigma = blurSigma ?? 22.0;
    final fill =
        tint ?? (isDark ? const Color(0xFF1B1B1F).withValues(alpha: 0.58) : Colors.white.withValues(alpha: 0.64));

    return CustomPaint(
      painter: _GlassShadowPainter(radius: radius, isDark: isDark),
      foregroundPainter: _GlassRimPainter(radius: radius, isDark: isDark),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill),
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    sheenStart ?? Colors.white.withValues(alpha: isDark ? 0.10 : 0.45),
                    sheenEnd ?? Colors.white.withValues(alpha: 0),
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
    const blur = 16.0;
    const offset = Offset(0, 7);
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
        ..color = Colors.black.withValues(alpha: isDark ? 0.42 : 0.15)
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