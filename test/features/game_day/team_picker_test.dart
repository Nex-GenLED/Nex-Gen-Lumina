// The Game Day team picker browses Explore Designs' Sports folders.
//
// Before: one flat list per sport, and "Football" lumped NFL with NCAA
// football. Now: the picker reuses Explore's league folder nodes VERBATIM
// (team_picker_folders.dart) — league → teams, Soccer grouping its leagues —
// and search stays flat across every league.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/features/game_day/team_picker_folders.dart';
import 'package:nexgen_command/features/game_day/team_picker_sheet.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';

void main() {
  group('folder tree — Explore Designs, reused', () {
    test('the root lists Explore\'s Sports folders in Explore\'s order', () {
      final names = GameDayTeamFolders.childFolders(GameDayTeamFolders.rootId)
          .map((n) => n.name)
          .toList();
      expect(names, [
        'NFL',
        'NBA',
        'MLB',
        'NHL',
        'Soccer',
        'WNBA',
        'NCAA Football',
        'NCAA Basketball',
      ]);
    });

    test('Soccer groups its leagues exactly as Explore does', () {
      final names = GameDayTeamFolders.childFolders(LeagueFolderIds.soccer)
          .map((n) => n.name)
          .toList();
      expect(names, ['MLS', 'NWSL', 'Champions League', 'FIFA World Cup 2026']);
    });

    test('every picker folder IS the Explore node (same id, name, parent, order)',
        () {
      final explore = <String, LibraryNode>{
        for (final n in SportsLibraryBuilder.getLeagueFolders()) n.id: n,
        for (final n in NcaaConferences.getNcaaFolders()) n.id: n,
      };
      for (final folder in GameDayTeamFolders.all) {
        final original = explore[folder.id];
        expect(original, isNotNull, reason: '${folder.id} is not an Explore folder');
        expect(folder.name, original!.name);
        expect(folder.parentId, original.parentId);
        expect(folder.sortOrder, original.sortOrder);
        expect(folder.nodeType, LibraryNodeType.folder);
      }
    });

    test('folders with no Game Day sport are not shown', () {
      for (final id in [
        LeagueFolderIds.epl,
        LeagueFolderIds.laLiga,
        LeagueFolderIds.bundesliga,
        LeagueFolderIds.serieA,
        LeagueFolderIds.golf,
        'ncaafb_sec',
        'ncaabb_sec',
      ]) {
        expect(GameDayTeamFolders.node(id), isNull, reason: id);
      }
    });

    test('NFL and NCAA Football are separate folders with disjoint teams', () {
      final nfl = GameDayTeamFolders.teamsIn(LeagueFolderIds.nfl);
      final ncaa = GameDayTeamFolders.teamsIn(LeagueFolderIds.ncaaFootball);
      expect(nfl.every((e) => e.value.sport == SportType.nfl), isTrue);
      expect(ncaa.every((e) => e.value.sport == SportType.ncaaFB), isTrue);
      expect(nfl.map((e) => e.key).toSet().intersection(
              ncaa.map((e) => e.key).toSet()),
          isEmpty);
      expect(nfl.map((e) => e.value.teamName), contains('Green Bay Packers'));
      expect(ncaa.map((e) => e.value.teamName),
          contains('Alabama Crimson Tide'));
    });

    test('every Game Day team lives in exactly one league folder', () {
      final seen = <String, int>{};
      for (final folder in GameDayTeamFolders.all) {
        for (final e in GameDayTeamFolders.teamsIn(folder.id)) {
          seen[e.key] = (seen[e.key] ?? 0) + 1;
        }
      }
      expect(seen.length, kTeamColors.length);
      expect(seen.values.every((n) => n == 1), isTrue);
    });

    test('a grouping folder has no teams of its own', () {
      expect(GameDayTeamFolders.teamsIn(LeagueFolderIds.soccer), isEmpty);
      expect(GameDayTeamFolders.sportFor(LeagueFolderIds.soccer), isNull);
    });

    test('teams inside a folder are alphabetical', () {
      final names = GameDayTeamFolders.teamsIn(LeagueFolderIds.mlb)
          .map((e) => e.value.teamName)
          .toList();
      expect(names, List.of(names)..sort());
    });

    test('the breadcrumb runs root → league', () {
      expect(GameDayTeamFolders.ancestry(LeagueFolderIds.mls).map((n) => n.name),
          ['Soccer', 'MLS']);
      expect(GameDayTeamFolders.ancestry(LeagueFolderIds.nfl).map((n) => n.name),
          ['NFL']);
    });
  });

  group('TeamPickerSheet', () {
    Future<void> pump(WidgetTester tester,
        {Set<String> existing = const {}}) async {
      // A tall viewport so a whole league (32 NFL rows) is laid out at once;
      // the assertions below name teams from anywhere in the alphabet.
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(800, 2400);
      addTearDown(tester.view.reset);
      final controller = ScrollController();
      addTearDown(controller.dispose);
      await tester.pumpWidget(
        ProviderScope(
          child: MaterialApp(
            home: Scaffold(
              body: TeamPickerSheet(
                scrollController: controller,
                existingTeamSlugs: existing,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Finder folder(String name) =>
        find.widgetWithText(ListTile, name);

    testWidgets('opens on the league folders, not on teams', (tester) async {
      await pump(tester);
      for (final name in ['NFL', 'NBA', 'MLB', 'NHL', 'Soccer', 'WNBA']) {
        expect(folder(name), findsOneWidget, reason: name);
      }
      expect(find.text('Green Bay Packers'), findsNothing);
      expect(find.text('Alabama Crimson Tide'), findsNothing);
    });

    testWidgets('NCAA Football is its own folder, without NFL teams',
        (tester) async {
      await pump(tester);
      await tester.dragUntilVisible(
        folder('NCAA Football'),
        find.byType(ListView),
        const Offset(0, -200),
      );
      await tester.tap(folder('NCAA Football'));
      await tester.pumpAndSettle();

      expect(find.text('NCAA Football'), findsOneWidget); // breadcrumb
      expect(find.text('Air Force Falcons'), findsOneWidget);
      expect(find.text('Alabama Crimson Tide'), findsOneWidget);
      expect(find.text('Green Bay Packers'), findsNothing);
      // League folders are gone while inside one.
      expect(folder('NFL'), findsNothing);
    });

    testWidgets('Soccer → MLS drills two levels and the back arrow climbs',
        (tester) async {
      await pump(tester);
      await tester.tap(folder('Soccer'));
      await tester.pumpAndSettle();
      expect(folder('MLS'), findsOneWidget);
      expect(folder('NWSL'), findsOneWidget);
      expect(folder('Champions League'), findsOneWidget);
      expect(folder('FIFA World Cup 2026'), findsOneWidget);

      await tester.tap(folder('MLS'));
      await tester.pumpAndSettle();
      expect(find.text('Soccer › MLS'), findsOneWidget);
      expect(find.text('Atlanta United FC'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(folder('MLS'), findsOneWidget);
      expect(find.text('Atlanta United FC'), findsNothing);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(folder('NFL'), findsOneWidget);
    });

    testWidgets('search spans every league, from any folder', (tester) async {
      await pump(tester);
      // Go inside NFL first: results must still come from OTHER leagues.
      await tester.tap(folder('NFL'));
      await tester.pumpAndSettle();
      expect(find.text('Green Bay Packers'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'Tigers');
      await tester.pumpAndSettle();

      expect(find.text('Green Bay Packers'), findsNothing);
      // "Auburn Tigers" is both an NCAA Football and an NCAA Basketball team;
      // Detroit Tigers is MLB. Three leagues, one flat list, league on each
      // row so they can be told apart.
      expect(find.text('Auburn Tigers'), findsNWidgets(2));
      expect(find.text('Detroit Tigers'), findsOneWidget);
      expect(find.text('MLB'), findsOneWidget);
      expect(find.text('NCAA Football'), findsWidgets);
      expect(find.text('NCAA Basketball'), findsWidgets);

      // Clearing the query goes back to browsing where we were.
      await tester.enterText(find.byType(TextField), '');
      await tester.pumpAndSettle();
      expect(find.text('Green Bay Packers'), findsOneWidget);
      expect(find.text('Detroit Tigers'), findsNothing);
    });

    testWidgets('an already-added team is shown checked and not tappable',
        (tester) async {
      await pump(tester, existing: {'nfl_packers'});
      await tester.tap(folder('NFL'));
      await tester.pumpAndSettle();
      final tile = tester.widget<ListTile>(
          find.byKey(const ValueKey('team_nfl_packers')));
      expect(tile.onTap, isNull);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('team_nfl_packers')),
              matching: find.byIcon(Icons.check_circle)),
          findsOneWidget);
    });
  });
}
