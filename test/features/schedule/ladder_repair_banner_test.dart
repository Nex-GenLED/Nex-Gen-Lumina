// +114 item 1d — the banner that says what the ladder repair did.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/widgets/ladder_repair_banner.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/text_scale_harness.dart';

LadderRepairStatus _status(LadderRepairOutcome o,
        {List<int> repaired = const [1, 4], List<int> stillBad = const []}) =>
    LadderRepairStatus(
      controllerId: 'AA00000000A1',
      outcome: o,
      repairedIds: repaired,
      stillBadIds: stillBad,
      at: DateTime(2026, 10, 2, 13, 1),
    );

class _Seeded extends LadderRepairStatusNotifier {
  _Seeded(LadderRepairStatus? s) {
    if (s != null) show(s);
  }
}

Widget _banner(LadderRepairStatus? s) => ProviderScope(
      overrides: [
        ladderRepairStatusProvider.overrideWith((ref) => _Seeded(s)),
      ],
      child: const LadderRepairBanner(),
    );

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('copy', () {
    test('repaired names settings by what they do, never by slot number', () {
      final c = ladderRepairCopy(_status(LadderRepairOutcome.repaired));
      expect(c.title, 'We fixed your everyday lighting');
      final all = c.lines.join(' ');
      expect(all, contains('On and Low settings'));
      expect(all, contains('Lumina Blue'));
      expect(all, contains('kept a copy'));
      expect(all, isNot(contains('preset')));
      expect(all, isNot(contains('1')));
    });

    test('an Off repair says what Off does now', () {
      final c = ladderRepairCopy(
          _status(LadderRepairOutcome.repaired, repaired: const [2]));
      final all = c.lines.join(' ');
      expect(all, contains('Off setting would have left some lights on'));
      expect(all, contains('Off now turns every channel off'));
      expect(all, isNot(contains('Lumina Blue')));
    });

    test('three settings read as a list', () {
      final c = ladderRepairCopy(
          _status(LadderRepairOutcome.repaired, repaired: const [1, 3, 5]));
      expect(c.lines.first, contains('On, Dim and Medium settings'));
    });

    test('partial names both halves', () {
      final c = ladderRepairCopy(_status(LadderRepairOutcome.partial,
          repaired: const [1], stillBad: const [4]));
      expect(c.title, 'We fixed part of your everyday lighting');
      expect(c.lines.first, 'Fixed: On. Not fixed: Low — the controller did '
          'not save it.');
    });

    test('failed says nothing was changed', () {
      final c = ladderRepairCopy(_status(LadderRepairOutcome.failed,
          repaired: const [], stillBad: const [1]));
      expect(c.title, 'We could not fix your everyday lighting');
      expect(c.lines.join(' '), contains('nothing was changed'));
    });
  });

  group('widget', () {
    testWidgets('renders nothing without a status', (tester) async {
      await tester.pumpWidget(MaterialApp(home: Scaffold(body: _banner(null))));
      expect(find.byType(Container), findsNothing);
    });

    testWidgets('renders the copy and "Got it" dismisses it', (tester) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: _banner(_status(LadderRepairOutcome.repaired)))));
      expect(find.text('We fixed your everyday lighting'), findsOneWidget);
      await tester.tap(find.text('Got it'));
      await tester.pump();
      expect(find.text('We fixed your everyday lighting'), findsNothing);
    });

    for (final o in [
      LadderRepairOutcome.repaired,
      LadderRepairOutcome.partial,
      LadderRepairOutcome.failed,
    ]) {
      testWidgets('${o.name}: survives 1.0 / 1.75 / 2.0 with Bold Text',
          (tester) async {
        await expectNoTextScaleDefectsAcrossMatrix(
          tester,
          _banner(_status(o,
              repaired: o == LadderRepairOutcome.failed ? const [] : const [1, 4],
              stillBad: o == LadderRepairOutcome.repaired ? const [] : const [3])),
        );
      });
    }
  });
}
