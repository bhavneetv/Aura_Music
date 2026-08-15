import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

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
  final Color? pillTint;
  final double? pillBlurSigma;
  final Color? pillFilmStart;
  final Color? pillFilmEnd;
  final double? selectedStartOpacity;
  final double? selectedEndOpacity;
  final double? searchButtonSize;
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
      child: GestureDetector(
        onTap: item.onTap,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: (isDark ? const Color(0xFF1E1E22) : Colors.white).withValues(alpha: 0.72),
            border: Border.all(
              color: isDark ? Colors.white.withValues(alpha: 0.20) : Colors.black.withValues(alpha: 0.08),
              width: 0.9,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: isDark ? 0.30 : 0.08),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ClipOval(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final effectiveAccent = style?.accent ?? Theme.of(context).colorScheme.primary;
    final barHeight = height ?? style?.height ?? 60.0;

    final blurSigma = style?.pillBlurSigma ?? 20.0;
    final pillTint = style?.pillTint ??
        (isDark ? const Color(0xFF161618).withValues(alpha: 0.76) : Colors.white.withValues(alpha: 0.78));

    final filmStart = style?.pillFilmStart ??
        (isDark ? Colors.white.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.65));
    final filmEnd = style?.pillFilmEnd ?? Colors.transparent;

    Widget barContent = Container(
      height: barHeight,
      decoration: BoxDecoration(
        color: pillTint,
        borderRadius: BorderRadius.circular(barHeight / 2),
        border: Border.all(
          color: filmStart,
          width: 0.9,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(barHeight / 2),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma),
          child: Stack(
            children: [
              // Specular film gradient
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [filmStart, filmEnd],
                      stops: const [0.0, 0.45],
                    ),
                  ),
                ),
              ),

              // Bar items layout
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  ...List.generate(items.length, (index) {
                    final isSelected = currentIndex == index;
                    final item = items[index];

                    return Expanded(
                      child: GestureDetector(
                        onTap: () => onTap(index),
                        behavior: HitTestBehavior.opaque,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 220),
                          curve: Curves.easeOutCubic,
                          margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? effectiveAccent.withValues(alpha: style?.selectedStartOpacity ?? 0.18)
                                : Colors.transparent,
                            borderRadius: BorderRadius.circular(barHeight / 2),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  item.icon,
                                  size: 22,
                                  color: isSelected
                                      ? effectiveAccent
                                      : (isDark ? Colors.white54 : Colors.black54),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(width: 4),
                                  Flexible(
                                    child: Text(
                                      item.label,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      softWrap: false,
                                      style: TextStyle(
                                        color: effectiveAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 11,
                                        fontFamily: 'Outfit',
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }),

                  // Optional Search Button
                  if (onSearchTap != null) ...[
                    const SizedBox(width: 4),
                    IconButton(
                      icon: Icon(
                        Icons.search_rounded,
                        color: isDark ? Colors.white70 : Colors.black54,
                        size: style?.searchButtonSize ?? 22,
                      ),
                      onPressed: onSearchTap,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );

    if (width != null) {
      barContent = SizedBox(width: width, child: barContent);
    } else if (style?.widthFactor != null) {
      barContent = FractionallySizedBox(widthFactor: style!.widthFactor, child: barContent);
    }

    // Attach optional leading / trailing actions beside the bar
    if (leadingActions != null || trailingActions != null) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (leadingActions != null) ...[
            GlassActionButtonRow(actions: leadingActions!),
            SizedBox(width: style?.searchGap ?? 8),
          ],
          Flexible(child: barContent),
          if (trailingActions != null) ...[
            SizedBox(width: style?.searchGap ?? 8),
            GlassActionButtonRow(actions: trailingActions!),
          ],
        ],
      );
    }

    return barContent;
  }
}
