import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:music_app/widgets/adaptive_navigation_bar.dart';

void main() {
  testWidgets('iOS 26 liquid navbar search button has true 1:1 circular geometry', (WidgetTester tester) async {
    int selectedIndex = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: const SizedBox(),
          bottomNavigationBar: StatefulBuilder(
            builder: (context, setState) {
              return AdaptiveNavigationBar(
                selectedIndex: selectedIndex,
                onDestinationSelected: (idx) => setState(() => selectedIndex = idx),
                destinations: const [
                  AdaptiveNavigationDestination(
                    icon: Icons.home_rounded,
                    selectedIcon: Icons.home_rounded,
                    label: 'Home',
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.search_rounded,
                    selectedIcon: Icons.search_rounded,
                    label: 'Search',
                    isSearch: true,
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.library_music_rounded,
                    selectedIcon: Icons.library_music_rounded,
                    label: 'Library',
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.queue_music_rounded,
                    selectedIcon: Icons.queue_music_rounded,
                    label: 'Queue',
                  ),
                  AdaptiveNavigationDestination(
                    icon: Icons.settings_rounded,
                    selectedIcon: Icons.settings_rounded,
                    label: 'Settings',
                  ),
                ],
                navBarStyle: 'default',
                accentColor: const Color(0xFFFFC72C),
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();

    // Verify Search button is present
    final searchFinder = find.bySemanticsLabel('Search');
    expect(searchFinder, findsOneWidget);

    // Verify Search button is a true 1:1 circle
    final searchSize = tester.getSize(searchFinder);
    expect(searchSize.width, equals(52.0));
    expect(searchSize.height, equals(52.0));
    expect(searchSize.width / searchSize.height, equals(1.0));

    // Verify ClipOval is used for circular clipping
    final clipOvalFinder = find.byType(ClipOval);
    expect(clipOvalFinder, findsWidgets);

    // Tap Search button to select it
    await tester.tap(searchFinder);
    await tester.pumpAndSettle();

    // Verify after selection, dimensions remain an exact 1:1 circle
    final selectedSearchSize = tester.getSize(searchFinder);
    expect(selectedSearchSize.width, equals(52.0));
    expect(selectedSearchSize.height, equals(52.0));
    expect(selectedSearchSize.width / selectedSearchSize.height, equals(1.0));
  });
}
