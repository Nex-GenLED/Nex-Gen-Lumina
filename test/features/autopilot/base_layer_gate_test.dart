// BASE-LAYER GATE — audit/BASE_LAYER_GATE.md
//
// Game Day relies on an end signal; the base layer is what returns the house if
// that signal never lands. An account with no everyday schedule has no next
// boundary, so the design runs until a human intervenes.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/base_layer_gate.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

ScheduleItem sched({
  String id = 's1',
  bool enabled = true,
  List<String> days = const ['Mon'],
  String time = '8:00 PM',
}) =>
    ScheduleItem(
      id: id,
      timeLabel: time,
      actionLabel: 'Warm White',
      repeatDays: days,
      enabled: enabled,
      sortKey: 1,
    );

void main() {
  setUp(resetBaseLayerPromptSession);

  group('evaluateBaseLayer — what counts as a floor', () {
    test('an enabled recurring schedule IS a base layer', () {
      expect(evaluateBaseLayer([sched()]), BaseLayerStatus.present);
    });

    test('no schedules at all → absent', () {
      expect(evaluateBaseLayer(const []), BaseLayerStatus.absentInFirestore);
    });

    test('a DISABLED schedule is not a floor — it never fires', () {
      expect(evaluateBaseLayer([sched(enabled: false)]),
          BaseLayerStatus.absentInFirestore);
    });

    test('a schedule with no repeat days is not a floor', () {
      expect(evaluateBaseLayer([sched(days: const [])]),
          BaseLayerStatus.absentInFirestore);
    });

    test('one enabled among several disabled is enough', () {
      expect(
        evaluateBaseLayer([
          sched(id: 'a', enabled: false),
          sched(id: 'b', enabled: false),
          sched(id: 'c', enabled: true),
        ]),
        BaseLayerStatus.present,
      );
    });
  });

  group('the honesty of the naming', () {
    test('the absent state is named absentInFirestore, not absent', () {
      // The census counts Firestore intent, not device reality — a controller
      // can hold base timer rows with no Firestore schedules (the bench rig is
      // exactly that). Renaming this to `absent` would assert certainty the app
      // does not have. If this test fails, the caveat has been optimised away.
      expect(BaseLayerStatus.values.map((e) => e.name).toList(),
          ['present', 'absentInFirestore']);
    });
  });

  group('session-once behaviour', () {
    test('the same uid is prompted once per session', () {
      expect(markPromptedOnce('uid-a'), isTrue);
      expect(markPromptedOnce('uid-a'), isFalse);
      expect(markPromptedOnce('uid-a'), isFalse);
    });

    test('different accounts are tracked independently', () {
      expect(markPromptedOnce('uid-a'), isTrue);
      expect(markPromptedOnce('uid-b'), isTrue);
      expect(wasPromptedThisSession('uid-a'), isTrue);
      expect(wasPromptedThisSession('uid-b'), isTrue);
      expect(wasPromptedThisSession('uid-c'), isFalse);
    });

    test('a new session prompts again — no persisted suppression', () {
      expect(markPromptedOnce('uid-a'), isTrue);
      resetBaseLayerPromptSession();
      expect(markPromptedOnce('uid-a'), isTrue,
          reason: 'a persisted dismissal would hide this forever');
    });
  });

  group('the common path takes no new friction', () {
    test('an account WITH a base layer is never marked as prompted', () {
      // maybeWarnNoBaseLayer returns early on `present` and must not consume
      // the session slot — otherwise losing the schedule later would silently
      // skip the one prompt that account gets.
      expect(evaluateBaseLayer([sched()]), BaseLayerStatus.present);
      expect(wasPromptedThisSession('uid-a'), isFalse);
    });
  });
}
