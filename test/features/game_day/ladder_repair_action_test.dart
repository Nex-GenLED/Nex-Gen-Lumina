// #183 — "Repair base lighting" on the Game Day screen.
//
//   • the card shows only when the readiness status says the ladder needs it;
//   • off the LAN the button is disabled and says why; nothing runs;
//   • the tap asks first, in plain words; "Not now" runs nothing;
//   • "Repair" runs it, shows the steps, then the result; a stopped run
//     offers to put the previous settings back;
//   • every view survives 1.0 / 1.75 / 2.0 text with Bold Text on.

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status.dart';
import 'package:nexgen_command/features/game_day/game_day_server_status_provider.dart';
import 'package:nexgen_command/features/game_day/gate_status.dart';
import 'package:nexgen_command/features/game_day/gate_status_provider.dart';
import 'package:nexgen_command/features/game_day/ladder_repair_action.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

import '../../helpers/text_scale_harness.dart';

class _FakeAction implements LadderRepairAction {
  _FakeAction({this.blocked, required this.result});
  final String? blocked;
  LadderRepairRun result;

  /// What `restore` answers; null = put back cleanly.
  LadderRepairRun? restoreResult;
  int runs = 0;
  int restores = 0;
  final gate = Completer<void>();

  @override
  String? blockedReason() => blocked;

  @override
  Future<LadderRepairRun> run({void Function(String step)? onProgress}) async {
    runs++;
    onProgress?.call('backup');
    onProgress?.call('save:1');
    await gate.future;
    return result;
  }

  @override
  Future<LadderRepairRun> restore(
      {void Function(String step)? onProgress}) async {
    restores++;
    onProgress?.call('save:1');
    return restoreResult ??
        const LadderRepairRun(LadderRepairOutcome.repaired, 'put back');
  }
}

const _repaired = LadderRepairRun(LadderRepairOutcome.repaired, 'wrote 5 of 5',
    repairedIds: [1, 2, 3, 4, 5]);
const _stopped = LadderRepairRun(LadderRepairOutcome.partial,
    'wrote 2 of 5, stopped at preset 3',
    repairedIds: [1, 2], stillBadIds: [3, 4, 5], stoppedAtId: 3);

Widget _app(_FakeAction action, {bool needed = true}) => ProviderScope(
      overrides: [
        userLadderRepairProvider.overrideWithValue(action),
        gateStatusProvider.overrideWith((ref) => Stream.value(
            GateStatus(needed ? const [kGateLadderBad] : const []))),
        gameDayServerStatusProvider
            .overrideWith((ref) => Stream.value(GameDayServerStatus.notServed)),
        selectedControllerIdProvider.overrideWithValue(null),
      ],
      child: const MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(child: LadderRepairActionCard()),
        ),
      ),
    );

void main() {
  group('the card', () {
    testWidgets('renders nothing unless the readiness status says the ladder '
        'needs repair', (tester) async {
      await tester.pumpWidget(_app(_FakeAction(result: _repaired), needed: false));
      await tester.pump();
      expect(find.byKey(const ValueKey('ladder-repair-card')), findsNothing);
    });

    testWidgets('shows the cause, the action, and is enabled on the LAN',
        (tester) async {
      await tester.pumpWidget(_app(_FakeAction(result: _repaired)));
      await tester.pump();
      expect(find.text(kLadderRepairNeedTitle), findsOneWidget);
      expect(find.textContaining('channel was added or changed'), findsOneWidget);
      final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('ladder-repair-action')));
      expect(button.onPressed, isNotNull);
      expect(find.byKey(const ValueKey('ladder-repair-blocked')), findsNothing);
    });

    testWidgets('off the LAN: disabled, says why, and a tap runs nothing',
        (tester) async {
      final action = _FakeAction(
          blocked: 'Connect to your home Wi-Fi to repair your base lighting.',
          result: _repaired);
      await tester.pumpWidget(_app(action));
      await tester.pump();
      final button = tester.widget<FilledButton>(
          find.byKey(const ValueKey('ladder-repair-action')));
      expect(button.onPressed, isNull);
      expect(find.text('Connect to your home Wi-Fi to repair your base lighting.'),
          findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ladder-repair-action')),
          warnIfMissed: false);
      await tester.pump();
      expect(action.runs, 0);
      expect(find.byKey(const ValueKey('ladder-repair-confirm')), findsNothing);
    });
  });

  group('the flow', () {
    testWidgets('asks first, in plain words; "Not now" runs nothing',
        (tester) async {
      final action = _FakeAction(result: _repaired);
      await tester.pumpWidget(_app(action));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-action')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ladder-repair-confirm')), findsOneWidget);
      expect(find.text(kLadderRepairConfirmTitle), findsOneWidget);
      expect(find.textContaining('up to five presets'), findsOneWidget);
      expect(find.textContaining('about a minute'), findsOneWidget);
      expect(find.textContaining('never changes your schedules'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ladder-repair-cancel')));
      await tester.pumpAndSettle();
      expect(action.runs, 0);
      expect(find.byKey(const ValueKey('ladder-repair-running')), findsNothing);
    });

    testWidgets('"Repair" runs it, shows the steps, then the result',
        (tester) async {
      final action = _FakeAction(result: _repaired);
      await tester.pumpWidget(_app(action));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-go')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(action.runs, 1);
      expect(find.byKey(const ValueKey('ladder-repair-running')), findsOneWidget);
      expect(find.text('Saving On…'), findsOneWidget);

      action.gate.complete();
      await tester.pumpAndSettle();
      expect(find.text('Base lighting repaired'), findsOneWidget);
      expect(find.textContaining('now cover every channel'), findsOneWidget);
      expect(find.byKey(const ValueKey('ladder-repair-restore')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('ladder-repair-close')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('ladder-repair-result')), findsNothing);
    });

    testWidgets('a stopped run says where it stopped and offers the backup; '
        'the restore runs and reports', (tester) async {
      final action = _FakeAction(result: _stopped)..gate.complete();
      await tester.pumpWidget(_app(action));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-go')));
      await tester.pumpAndSettle();
      expect(find.text('Repair stopped'), findsOneWidget);
      expect(find.textContaining('Saving Dim did not work'), findsOneWidget);
      expect(find.textContaining('Repaired: On, Off.'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('ladder-repair-restore')));
      await tester.pumpAndSettle();
      expect(action.restores, 1);
      expect(find.text('Previous settings restored'), findsOneWidget);
    });

    testWidgets('a restore that cannot put everything back says so',
        (tester) async {
      final action = _FakeAction(result: _stopped)
        ..gate.complete()
        ..restoreResult = const LadderRepairRun(
            LadderRepairOutcome.partial, 'put back 3 of 5',
            repairedIds: [1, 2, 3], stillBadIds: [4, 5]);
      await tester.pumpWidget(_app(action));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-go')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('ladder-repair-restore')));
      await tester.pumpAndSettle();
      expect(find.text('Could not put everything back'), findsOneWidget);
      expect(find.textContaining('Contact support'), findsOneWidget);
    });
  });

  group('copy (pure)', () {
    test('steps read as what they do', () {
      expect(ladderRepairStepLabel('backup'), contains('Backing up'));
      expect(ladderRepairStepLabel('save:2'), 'Saving Off…');
      expect(ladderRepairStepLabel('verify:5'), 'Checking Medium…');
      expect(ladderRepairStepLabel('restore'), contains('Putting your lights'));
    });

    test('a deferred run names the real reason', () {
      String line(String reason) => ladderRepairResultCopy(
              LadderRepairRun(LadderRepairOutcome.deferred, reason))
          .lines
          .single;
      expect(line('refused(game_day_live: a game)'), contains('A game is on'));
      expect(line('refused(timer_near: p1 at 13:05)'), contains('schedule'));
      expect(line('refused(clock_unhealthy: …)'), contains('clock'));
      expect(line('refused(game_day_unknown: …)'), contains("hasn't loaded"));
    });

    test('a stopped run offers the restore; a repaired one does not', () {
      expect(ladderRepairResultCopy(_stopped).offerRestore, isTrue);
      expect(ladderRepairResultCopy(_repaired).offerRestore, isFalse);
      expect(
          ladderRepairResultCopy(const LadderRepairRun(
                  LadderRepairOutcome.cancelled, 'account changed'))
              .lines
              .single,
          contains('account changed'));
    });
  });

  group('large text (1.0 / 1.75 / 2.0, Bold Text on)', () {
    testWidgets('the card, enabled and blocked', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        LadderRepairActionView(blockedReason: null, onRepair: () {}),
      );
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        LadderRepairActionView(
          blockedReason:
              'Connect to your home Wi-Fi to repair your base lighting.',
          onRepair: () {},
        ),
      );
    });

    testWidgets('the confirmation dialog', (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        const LadderRepairConfirmDialog(),
      );
    });

    testWidgets('the progress sheet: running, repaired, stopped with restore',
        (tester) async {
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        LadderRepairProgressView(
          step: 'verify:4',
          run: null,
          onRestore: () {},
          onClose: () {},
        ),
        settle: const Duration(milliseconds: 100),
      );
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        LadderRepairProgressView(
          step: 'done',
          run: _repaired,
          onRestore: () {},
          onClose: () {},
        ),
      );
      await expectNoTextScaleDefectsAcrossMatrix(
        tester,
        LadderRepairProgressView(
          step: 'done',
          run: _stopped,
          onRestore: () {},
          onClose: () {},
        ),
      );
    });
  });
}
