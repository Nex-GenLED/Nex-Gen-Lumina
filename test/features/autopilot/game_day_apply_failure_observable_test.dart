// PART A — a failed Game Day device apply must be OBSERVABLE.
//
// audit/GAMEDAY_WEDGE_U1_U6.md §2: `onApplyPayload` was
// `void Function(Map<String, dynamic>)`, so the Future returned by
// `repo.applyJson` was discarded. The provider's own try/catch could then only
// catch a SYNCHRONOUS throw — a timeout, or an exception raised inside the
// apply, became an unhandled async error and was lost entirely.
//
// On the SCHEDULED path that is the part that matters: it fires unattended, so
// a controller that failed to light produced no error anywhere and nobody was
// present to notice. These tests pin the fix: the Future is awaited, and the
// failure reaches `onApplyFailure`.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/espn_api_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/game_schedule_service.dart';

DesignSelection _design({List<Map<String, dynamic>>? seg}) => DesignSelection(
      mode: AutopilotDesignMode.fallback,
      designName: 'Test Design',
      effectId: 0,
      speed: 128,
      intensity: 128,
      brightness: 200,
      colors: const [
        [255, 0, 0, 0]
      ],
      wledPayload: {
        'on': true,
        'bri': 200,
        'seg': seg ?? [
          {'id': 0, 'fx': 0, 'col': [[255, 0, 0, 0]]}
        ],
      },
    );

void main() {
  late GameDayAutopilotService svc;

  setUp(() {
    svc = GameDayAutopilotService(
      espnApi: EspnApiService(),
      scheduleService: GameScheduleService(),
    );
  });

  group('Part A — an async apply failure is not swallowed', () {
    test('a THROWN failure reaches onApplyFailure', () async {
      Object? seenError;
      DesignSelection? seenDesign;
      svc.onApplyPayload = (_) async => throw StateError('device write failed');
      svc.onApplyFailure = (design, error, stack) {
        seenDesign = design;
        seenError = error;
      };

      // rethrown so the caller can react too; the point is that it was SEEN.
      await expectLater(
        svc.applyDesignForTest(_design()),
        throwsA(isA<StateError>()),
      );

      expect(seenError, isA<StateError>(),
          reason: 'the failure must reach onApplyFailure, not vanish');
      expect(seenDesign?.designName, 'Test Design',
          reason: 'the report must name WHICH design failed');
    });

    test('a DELAYED failure is still caught — this is the regression', () async {
      // The old shape dropped the Future, so anything that failed after an
      // await boundary was unobservable. A synchronous throw would have been
      // caught even before the fix; only this case proves the await landed.
      Object? seenError;
      svc.onApplyPayload = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 10));
        throw StateError('timeout after the await boundary');
      };
      svc.onApplyFailure = (_, error, __) => seenError = error;

      await expectLater(
        svc.applyDesignForTest(_design()),
        throwsA(isA<StateError>()),
      );
      expect(seenError, isA<StateError>());
    });

    test('the apply is AWAITED — applyDesignForTest does not return early',
        () async {
      // Without an await, the future returns before the handler completes and
      // `completed` would still be false when we check it.
      var completed = false;
      svc.onApplyPayload = (_) async {
        await Future<void>.delayed(const Duration(milliseconds: 20));
        completed = true;
      };

      await svc.applyDesignForTest(_design());

      expect(completed, isTrue,
          reason: 'applyDesignForTest must not resolve before the apply does');
    });

    test('a successful apply reports NO failure', () async {
      var failures = 0;
      svc.onApplyPayload = (_) async {};
      svc.onApplyFailure = (_, __, ___) => failures++;

      await svc.applyDesignForTest(_design());

      expect(failures, 0);
    });

    test('the empty-seg skip still short-circuits before any apply', () async {
      // The Bundle 3b.3c gate must survive Part A unchanged.
      var applied = 0;
      var failures = 0;
      svc.onApplyPayload = (_) async => applied++;
      svc.onApplyFailure = (_, __, ___) => failures++;

      await svc.applyDesignForTest(_design(seg: const []));

      expect(applied, 0, reason: 'seg: [] must skip-apply, as before');
      expect(failures, 0, reason: 'a deliberate skip is not a failure');
    });
  });
}
