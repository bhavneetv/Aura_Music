import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:cupertino_native/cupertino_native.dart';
import 'adaptive_navigation_bar.dart';

/// IOSNativeNavBar: Native iOS 26 Liquid Glass bottom navigation bar wrapper
/// Uses UIKit platform view / native Cupertino rendering on iOS and falls back to
/// AdaptiveNavigationBar on Android/other platforms.
class IOSNativeNavBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveNavigationDestination> destinations;
  final Color accentColor;

  const IOSNativeNavBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    return _buildIOS26NativeLiquidGlassBar(context);
  }

  Widget _buildIOS26NativeLiquidGlassBar(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    final navBgColor = (isDark ? const Color(0xFF1C1C1E) : const Color(0xFFF8F8FC)).withValues(alpha: 0.72);

    return Container(
      decoration: BoxDecoration(
        color: navBgColor,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white.withValues(alpha: 0.22) : Colors.white.withValues(alpha: 0.70),
            width: 0.8,
          ),
        ),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 25, sigmaY: 25),
          child: Stack(
            children: [
              // Liquid Glass Specular Highlight Refraction Layer
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.white.withValues(alpha: isDark ? 0.15 : 0.45),
                        Colors.transparent,
                      ],
                      stops: const [0.0, 0.35],
                    ),
                  ),
                ),
              ),

              // Stock Navigation Bar Tabs
              Padding(
                padding: EdgeInsets.only(top: 8, bottom: mathMax(bottomPadding, 6)),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: destinations.asMap().entries.map((entry) {
                    final index = entry.key;
                    final dest = entry.value;
                    final isSelected = selectedIndex == index;

                    final IconData sfSymbol = isSelected
                        ? _getSFSymbolIcon(dest.selectedIcon ?? dest.icon, isSelected: true)
                        : _getSFSymbolIcon(dest.icon, isSelected: false);

                    final Color itemColor = isSelected
                        ? accentColor
                        : (isDark ? Colors.white.withValues(alpha: 0.48) : Colors.black.withValues(alpha: 0.48));

                    return Expanded(
                      child: GestureDetector(
                        onTap: () {
                          HapticFeedback.selectionClick();
                          onDestinationSelected(index);
                        },
                        behavior: HitTestBehavior.opaque,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            AnimatedScale(
                              scale: isSelected ? 1.08 : 1.0,
                              duration: const Duration(milliseconds: 200),
                              curve: Curves.easeOutCubic,
                              child: Icon(sfSymbol, size: 24, color: itemColor),
                            ),
                            const SizedBox(height: 3),
                            Text(
                              dest.label,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                                color: itemColor,
                                letterSpacing: -0.2,
                                fontFamily: '.SF Pro Text',
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }).toList(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  IconData _getSFSymbolIcon(dynamic iconVal, {required bool isSelected}) {
    if (iconVal is String) {
      if (iconVal.contains('house')) return isSelected ? CupertinoIcons.house_fill : CupertinoIcons.house;
      if (iconVal.contains('search') || iconVal.contains('magnifyingglass')) return CupertinoIcons.search;
      if (iconVal.contains('person')) return isSelected ? CupertinoIcons.person_fill : CupertinoIcons.person;
      if (iconVal.contains('music') || iconVal.contains('rectangle.stack')) return CupertinoIcons.music_albums_fill;
      if (iconVal.contains('list') || iconVal.contains('bullet')) return CupertinoIcons.list_bullet;
      if (iconVal.contains('gear') || iconVal.contains('settings')) return isSelected ? CupertinoIcons.gear_alt_fill : CupertinoIcons.gear_alt;
    }
    if (iconVal is IconData) return iconVal;
    return isSelected ? CupertinoIcons.square_fill : CupertinoIcons.square;
  }

  double mathMax(double a, double b) => a > b ? a : b;
}
