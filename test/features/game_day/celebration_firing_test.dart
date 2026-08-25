// Phase C — the firing logic finally reads the config it was already handed.
//
// handleAlertEvent has always RECEIVED the config and never read it
// (audit/GAME_DAY_SPEC_AUDIT.md §2.2): every celebration was a hardcoded
// switch over event type, identical for every team and user. These lock the
// substitution AND, just as importantly, the half that must not change — the
// per-event-type timing table.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_background_worker.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/autopilot/unified_monitoring.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';

final _team = kTeamColors['nfl_chiefs']!;

/// A user-chosen "Pulse" celebration — the scenario in the spec.
const _pulse = CelebrationResolution(
  effectId: 79,
  speed: 200,
  intensity: 180,
);

const _fallback = CelebrationResolution(
  effectId: kFallbackCelebrationEffectId,
  speed: kFallbackCelebrationSpeed,
  intensity: kFallbackCelebrationIntensity,
  usedFallback: true,
);

List<Map<String, dynamic>> _segsOf(AlertAnimationStep step) =>
    (step.payload['seg'] as List).cast<Map<String, dynamic>>();

BackgroundGameDayAutopilotConfig _bg({int? celebrationEffectId}) =>
    BackgroundGameDayAutopilotConfig(
      teamSlug: 'nfl_chiefs',
      teamName: 'Kansas City Chiefs',
      espnTeamId: '12',
      sport: 'nfl',
      primaryColorValue: 0xFFE31837,
      secondaryColorValue: 0xFFFFB81C,
      enabled: true,
      designMode: 'fallback',
      effectId: 9,
      speed: 160,
      intensity: 128,
      brightness: 200,
      skipDayGames: true,
      designVariety: 'rotating',
      scoreCelebrationEnabled: true,
      celebrationEffectId: celebrationEffectId,
      celebrationSpeed: 200,
      celebrationIntensity: 180,
    );

void main() {
  // THE REQUIRED TEST. A touchdown with a chosen Pulse effect fires the 15s
  // multi-stage sequence using Pulse at EVERY stage — not the old hardcoded
  // Strobe → Wipe → Running.
  group('a chosen effect replaces the motion at every stage', () {
    final legacy = AlertTriggerService.buildAnimationSteps(
        AlertEventType.touchdown, _team);
    final chosen = AlertTriggerService.buildAnimationSteps(
        AlertEventType.touchdown, _team, _pulse);

    test('the legacy touchdown really is the 3-stage Strobe/Wipe/Running', () {
      expect(legacy.map((s) => _segsOf(s).first['fx']), [2, 9, 63]);
    });

    test('every stage now carries the chosen fx', () {
      expect(chosen.map((s) => _segsOf(s).first['fx']), [79, 79, 79]);
    });

    test('the chosen speed and intensity are honoured at every stage', () {
      for (final step in chosen) {
        expect(_segsOf(step).first['sx'], 200);
        expect(_segsOf(step).first['ix'], 180);
      }
    });

    // THE HALF THAT MUST NOT CHANGE.
    test('the timing table survives whole — same stages, same holds', () {
      expect(chosen.length, legacy.length);
      expect(chosen.map((s) => s.hold), legacy.map((s) => s.hold));
      expect(
        chosen.fold(Duration.zero, (a, s) => a + s.hold),
        const Duration(seconds: 15),
      );
    });

    test('the first stage still asserts on/bri so the flash is visible', () {
      expect(chosen.first.payload['on'], isTrue);
      expect(chosen.first.payload['bri'], 255);
    });

    test('colors remain per-team', () {
      expect(_segsOf(chosen.first).first['col'],
          _segsOf(legacy.first).first['col']);
    });
  });

  group('every other event type keeps its own duration', () {
    // Each entry is the spec'd total from the legacy timing table.
    const expected = {
      AlertEventType.touchdown: Duration(seconds: 15),
      AlertEventType.goal: Duration(seconds: 15),
      AlertEventType.fieldGoal: Duration(seconds: 8),
      AlertEventType.safety: Duration(seconds: 6),
      AlertEventType.run: Duration(seconds: 6),
      AlertEventType.quarterEndWinning: Duration(seconds: 10),
      AlertEventType.clutchBasket: Duration(seconds: 5),
      AlertEventType.soccerGoal: Duration(seconds: 20),
    };

    expected.forEach((type, total) {
      test('${type.name} still runs for ${total.inSeconds}s with a chosen effect',
          () {
        final steps =
            AlertTriggerService.buildAnimationSteps(type, _team, _pulse);
        expect(steps.fold(Duration.zero, (a, s) => a + s.hold), total);
        for (final s in steps) {
          expect(_segsOf(s).first['fx'], _pulse.effectId);
        }
      });
    });

    // Explicitly out of scope — the audit marks it a Phase-2 placeholder.
    test('turnover stays silent, chosen effect or not', () {
      expect(
        AlertTriggerService.buildAnimationSteps(
            AlertEventType.turnover, _team, _pulse),
        isEmpty,
      );
    });
  });

  group('no chosen effect keeps the legacy sequences byte-for-byte', () {
    for (final type in AlertEventType.values) {
      test('${type.name} is unchanged when nothing is chosen', () {
        final a = AlertTriggerService.buildAnimationSteps(type, _team);
        final b = AlertTriggerService.buildAnimationSteps(type, _team, null);
        expect(b.length, a.length);
        for (var i = 0; i < a.length; i++) {
          expect(b[i].payload, a[i].payload);
          expect(b[i].hold, a[i].hold);
        }
      });
    }
  });

  group('the fallback overrides colour as well as motion', () {
    final steps = AlertTriggerService.buildAnimationSteps(
        AlertEventType.touchdown, _team, _fallback);

    test('it uses the safe effect at every stage', () {
      for (final s in steps) {
        expect(_segsOf(s).first['fx'], kFallbackCelebrationEffectId);
      }
    });

    // A fallback substituted because the MOTION clashed would clash exactly the
    // same way if it kept team colours.
    test('team colours are replaced by white', () {
      final col = _segsOf(steps.first).first['col'] as List;
      expect(col.first, kFallbackCelebrationColor);
    });

    test('a non-fallback resolution leaves colours alone', () {
      final chosen = AlertTriggerService.buildAnimationSteps(
          AlertEventType.touchdown, _team, _pulse);
      final legacy = AlertTriggerService.buildAnimationSteps(
          AlertEventType.touchdown, _team);
      expect(_segsOf(chosen.first).first['col'],
          _segsOf(legacy.first).first['col']);
    });
  });

  // The choice has to reach the trigger service, which receives ONLY the
  // ScoreAlertConfig — the same reason sensitivity is carried there.
  group('the choice survives the hop into the monitoring config', () {
    test('monitoringConfigFor carries all three fields', () {
      final c = monitoringConfigFor(_bg(celebrationEffectId: 79));
      expect(c.celebrationEffectId, 79);
      expect(c.celebrationSpeed, 200);
      expect(c.celebrationIntensity, 180);
    });

    test('an unchosen effect stays null across the hop', () {
      expect(monitoringConfigFor(_bg()).celebrationEffectId, isNull);
    });
  });

  // P5 finding: the worker is a SECOND, independent renderer, and for a manual
  // join it is the only one that fires. A choice honoured on one path and
  // ignored on the other would be worse than not shipping it.
  group('the worker renderer honours the same choice', () {
    test('it uses the chosen effect', () {
      final payload = GameDayAutopilotBackgroundWorker
          .buildCelebrationPayloadForTest(_bg(celebrationEffectId: 79));
      final seg = (payload['seg'] as List).first as Map;
      expect(seg['fx'], 79);
      expect(seg['sx'], 200);
      expect(seg['ix'], 180);
    });

    test('with nothing chosen it keeps the legacy Sparkle default', () {
      final payload = GameDayAutopilotBackgroundWorker
          .buildCelebrationPayloadForTest(_bg());
      final seg = (payload['seg'] as List).first as Map;
      expect(seg['fx'], 11);
      expect(seg['sx'], 240);
      expect(seg['ix'], 240);
    });
  });
}
