// Widget tests for [GameDaySportFilterChips] — the Path 2
// (Sync→Complement→Game Day) sport-filter chip row. After 601f888's
// re-apply, BOTH the Fan Zone picker and this Path 2 picker should
// render per-league chips in a multi-row Wrap (no horizontal scroll),
// so all ~11 leagues are visible at once.
//
// The test surface is intentionally a pure-presentation widget that
// takes the active sport + a callback. Riverpod glue lives at the
// caller in GameDayPath2Screen — keeping the chip row Riverpod-free
// makes this test cheap and independent of the screen's many
// dependencies (Firestore stream, auth state, team list provider).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/widgets/game_day_setup_screen.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';

Widget _harness({
  SportType? activeSport,
  ValueChanged<SportType?>? onSportChanged,
}) {
  return MaterialApp(
    home: Scaffold(
      body: GameDaySportFilterChips(
        activeSport: activeSport,
        onSportChanged: onSportChanged ?? (_) {},
      ),
    ),
  );
}

void main() {
  group('GameDaySportFilterChips', () {
    testWidgets('renders ALL + every SportType.values label', (tester) async {
      await tester.pumpWidget(_harness());

      expect(find.text('ALL'), findsOneWidget);
      for (final sport in SportType.values) {
        expect(
          find.text(sport.displayName),
          findsOneWidget,
          reason: 'expected ${sport.displayName} chip',
        );
      }
    });

    testWidgets(
        'uses Wrap layout (multi-row visible at once), NOT a horizontal '
        'ListView — matches the Fan Zone picker per 601f888', (tester) async {
      await tester.pumpWidget(_harness());

      expect(find.byType(Wrap), findsOneWidget);
      expect(
        find.byType(ListView),
        findsNothing,
        reason: 'reverting to horizontal scroll would re-introduce the '
            'pre-601f888 asymmetry with the Fan Zone picker',
      );
    });

    testWidgets('tapping a sport chip fires onSportChanged with that sport',
        (tester) async {
      SportType? selected = SportType.mlb; // seed with non-target
      await tester.pumpWidget(_harness(
        onSportChanged: (s) => selected = s,
      ));

      await tester.tap(find.text(SportType.nfl.displayName));
      await tester.pump();
      expect(selected, SportType.nfl);

      await tester.tap(find.text(SportType.wnba.displayName));
      await tester.pump();
      expect(selected, SportType.wnba,
          reason: 'per-league chips must isolate each league individually '
              '(no 5-bucket grouping)');
    });

    testWidgets('tapping ALL fires onSportChanged with null', (tester) async {
      SportType? selected = SportType.nfl;
      await tester.pumpWidget(_harness(
        activeSport: SportType.nfl,
        onSportChanged: (s) => selected = s,
      ));

      await tester.tap(find.text('ALL'));
      await tester.pump();
      expect(selected, isNull);
    });

    testWidgets(
        'chip count: 1 (ALL) + SportType.values.length leagues — '
        'guarantees no league is silently dropped from the layout',
        (tester) async {
      await tester.pumpWidget(_harness());

      // The Wrap should contain exactly 1 + SportType.values.length chips.
      final wrap = tester.widget<Wrap>(find.byType(Wrap));
      expect(wrap.children.length, 1 + SportType.values.length);
    });
  });
}
