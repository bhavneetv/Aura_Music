import 'dart:io';
import 'dart:ui';
import 'package:flutter/cupertino.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:cupertino_native/cupertino_native.dart';
import '../providers/playback_provider.dart';
import 'glass_bottom_navigation.dart';

/// Platform detection helper for OS-specific rendering
class PlatformInfo {
  static bool get isIOS => !kIsWeb && Platform.isIOS;
  static bool get isAndroid => !kIsWeb && Platform.isAndroid;
  static bool get isMacOS => !kIsWeb && Platform.isMacOS;

  /// Detection for iOS 26 Liquid Glass translucent refractive material capabilities
  static bool isIOS26OrHigher() {
    return isIOS;
  }
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
/// (iOS 26 Liquid Glass / Android 16 Material 3)
class AdaptiveNavigationBar extends StatelessWidget {
  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;
  final List<AdaptiveNavigationDestination> destinations;
  final String navBarStyle; // 'default' or 'os_style'
  final Color accentColor;

  const AdaptiveNavigationBar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.destinations,
    required this.navBarStyle,
    required this.accentColor,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    if (navBarStyle == 'os_style') {
      if (PlatformInfo.isIOS) {
        return _buildIOSLiquidGlassNavigationBar(context, isDark);
      } else {
        return _buildAndroidMaterial3NavigationBar(context, isDark);
      }
    }

    // Default: App's custom floating glass capsule nav bar
    return _buildDefaultFloatingGlassBar(context, isDark);
  }

  // ── 1. iOS 26 Stock "Liquid Glass" Navigation Bar ─────────────────────────
  Widget _buildIOSLiquidGlassNavigationBar(BuildContext context, bool isDark) {
    return CNTabBar(
      currentIndex: selectedIndex,
      onTap: (index) {
        triggerHaptic(HapticFeedbackType.light);
        onDestinationSelected(index);
      },
      tint: accentColor,
      iconSize: 18.0,
      height: 50,
      items: List.generate(destinations.length, (index) {
        final dest = destinations[index];
        final isSelected = selectedIndex == index;
        return CNTabBarItem(
          icon: CNSymbol(
            _getIOSSFSymbolName(
              isSelected ? (dest.selectedIcon ?? dest.icon) : dest.icon,
              isSelected: isSelected,
              isSearch: dest.isSearch,
            ),
            size: 18.0,
          ),
          label: dest.label,
        );
      }),
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

  // ── 3. Default App Floating Curved Glass Navigation Bar ──────────────────
  Widget _buildDefaultFloatingGlassBar(BuildContext context, bool isDark) {
    final double bottomInset = MediaQuery.of(context).padding.bottom;
    final double bottomMargin = bottomInset > 0 ? bottomInset + 8.0 : 16.0;

    return Container(
      margin: EdgeInsets.only(left: 14, right: 14, bottom: bottomMargin),
      decoration: BoxDecoration(
        color: (isDark ? const Color(0xFF141416) : Colors.white).withValues(alpha: 0.85),
        borderRadius: BorderRadius.circular(32),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: isDark ? 0.35 : 0.08),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
        border: Border.all(
          color: isDark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.08),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(32),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(destinations.length, (index) {
                final isSelected = selectedIndex == index;
                final dest = destinations[index];
                final IconData displayIcon = _getAndroidIcon(
                  isSelected ? (dest.selectedIcon ?? dest.icon) : dest.icon,
                  isSelected: isSelected,
                );

                return Expanded(
                  child: GestureDetector(
                    onTap: () {
                      triggerHaptic(HapticFeedbackType.light);
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
                          child: Icon(
                            displayIcon,
                            color: isSelected ? accentColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                            size: 22,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          dest.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: isSelected ? accentColor : (isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                            fontSize: 11,
                            fontFamily: 'Outfit',
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  String _getIOSSFSymbolName(dynamic val, {required bool isSelected, bool isSearch = false}) {
    if (isSearch) return 'magnifyingglass';

    if (val == Icons.home || val == Icons.home_rounded || val == Icons.home_outlined) {
      return isSelected ? 'house.fill' : 'house';
    }
    if (val == Icons.search || val == Icons.search_rounded || val == Icons.search_outlined) {
      return 'magnifyingglass';
    }
    if (val == Icons.library_music || val == Icons.library_music_rounded || val == Icons.library_music_outlined) {
      return isSelected ? 'music.note.list' : 'music.note.list';
    }
    if (val == Icons.queue_music || val == Icons.queue_music_rounded || val == Icons.queue_music_outlined) {
      return isSelected ? 'list.bullet.indent' : 'list.bullet.indent';
    }
    if (val == Icons.settings || val == Icons.settings_rounded || val == Icons.settings_outlined) {
      return isSelected ? 'gearshape.fill' : 'gearshape';
    }

    if (val is String) {
      if (val.contains('house')) return isSelected ? 'house.fill' : 'house';
      if (val.contains('person')) return isSelected ? 'person.fill' : 'person';
      if (val.contains('search') || val.contains('magnifyingglass')) return 'magnifyingglass';
    }

    return isSelected ? 'house.fill' : 'house';
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
