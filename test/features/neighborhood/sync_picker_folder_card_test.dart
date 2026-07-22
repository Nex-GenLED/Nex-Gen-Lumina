// test/features/neighborhood/sync_picker_folder_card_test.dart
//
// #7 regression coverage for the Sync Control Center → "Browse All Patterns"
// pattern picker.
//
// The Sync picker's [FolderPickerCard] previously sourced its card colors from
// node.previewColors ?? node.themeColors, both of which are ALWAYS null for
// category/folder nodes (previewColors was never populated by the data layer).
// That left every category/folder card a blank grey tile, while leaf palette
// cards (which carry themeColors) rendered fine.
//
// The fix makes FolderPickerCard reuse the shared Explore iconography
// (LibraryNodeCard.iconForNode + .folderThemeColor) for category/folder nodes,
// rendering a per-id icon in a per-category accent instead of blank grey. Leaf
// palette cards keep their themeColors gradient bar.
//
// These tests assert:
//   1. The shared helpers return a real per-category icon + non-grey color.
//   2. A category/folder FolderPickerCard renders that icon (not blank).
//   3. A leaf palette FolderPickerCard still renders its gradient bar and does
//      NOT render the folder fallback icon.
//
// (The #8 scroll fix is a single framework flag — enableDrag:false on the
// showModalBottomSheet — and is verified manually; the private _PatternPickerSheet
// / _openPatternPicker aren't reachable from a widget test without re-plumbing
// the whole modal, so it's not unit-tested here.)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_control_panel.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_grid_widgets.dart';

void main() {
  // A top-level category node (no themeColors / previewColors — the blank-card case).
  const holidaysCategory = LibraryNode(
    id: LibraryCategoryIds.holidays,
    name: 'Holidays',
    nodeType: LibraryNodeType.category,
  );

  // An intermediate folder node (also no colors).
  const sportsCategory = LibraryNode(
    id: LibraryCategoryIds.sports,
    name: 'Game Day Fan Zone',
    nodeType: LibraryNodeType.category,
  );

  // A leaf palette node (carries themeColors — the working case).
  const paletteNode = LibraryNode(
    id: 'team_chiefs',
    name: 'Kansas City Chiefs',
    nodeType: LibraryNodeType.palette,
    themeColors: [Color(0xFFE31837), Color(0xFFFFB81C)],
  );

  group('shared Explore iconography (LibraryNodeCard statics)', () {
    test('folderThemeColor returns the per-category accent, not blank grey', () {
      expect(LibraryNodeCard.folderThemeColor(holidaysCategory),
          const Color(0xFFE53935));
      expect(LibraryNodeCard.folderThemeColor(sportsCategory),
          const Color(0xFF1976D2));
      // Crucially, never the old blank-grey fallback.
      expect(LibraryNodeCard.folderThemeColor(holidaysCategory),
          isNot(Colors.grey.shade700));
    });

    test('iconForNode returns the per-id category icon', () {
      expect(LibraryNodeCard.iconForNode(holidaysCategory),
          Icons.celebration_outlined);
      expect(LibraryNodeCard.iconForNode(sportsCategory),
          Icons.sports_football_outlined);
    });
  });

  Future<void> pumpCard(WidgetTester tester, LibraryNode node) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 160,
              height: 120,
              child: FolderPickerCard(node: node, onTap: () {}),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('#7 category card renders an icon (not blank grey)',
      (tester) async {
    await pumpCard(tester, holidaysCategory);
    // The shared per-category icon is rendered → card is no longer blank.
    expect(find.byIcon(Icons.celebration_outlined), findsOneWidget);
    expect(find.text('Holidays'), findsOneWidget);
  });

  testWidgets('#7 leaf palette card still renders its gradient bar (no fallback icon)',
      (tester) async {
    await pumpCard(tester, paletteNode);
    // Palette path renders the themeColors gradient bar, NOT the folder icon.
    expect(find.byIcon(Icons.celebration_outlined), findsNothing);
    expect(find.byType(Icon), findsNothing);
    expect(find.text('Kansas City Chiefs'), findsOneWidget);

    // The 4px gradient bar carries the palette's themeColors.
    final barFinder = find.byWidgetPredicate((w) {
      if (w is Container && w.decoration is BoxDecoration) {
        final gradient = (w.decoration as BoxDecoration).gradient;
        if (gradient is LinearGradient) {
          return gradient.colors.contains(const Color(0xFFE31837)) &&
              gradient.colors.contains(const Color(0xFFFFB81C));
        }
      }
      return false;
    });
    expect(barFinder, findsOneWidget);
  });
}
