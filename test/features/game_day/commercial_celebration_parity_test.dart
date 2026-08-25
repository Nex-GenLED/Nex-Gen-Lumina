// Phase F — commercial parity.
//
// Pre-check P2: CommercialTeamProfile is a GENUINELY SEPARATE model from
// GameDayAutopilotConfig — different key names, hex colour strings rather than
// ARGB ints, AlertIntensity rather than AlertSensitivity. So the celebration
// slot had to be added there too. What must NOT be separate is the FIRING:
// these lock that a commercial celebration resolves and renders through the
// identical code path a residential one does.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_config.dart';
import 'package:nexgen_command/features/sports_alerts/models/score_alert_event.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/sports_alerts/services/alert_trigger_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';

final _team = kTeamColors['nfl_chiefs']!;

CommercialTeamProfile _profile({int? celebrationEffectId}) =>
    CommercialTeamProfile(
      priorityRank: 1,
      teamId: '12',
      teamName: 'Kansas City Chiefs',
      sport: 'nfl',
      primaryColor: '#E31837',
      secondaryColor: '#FFB81C',
      celebrationEffectId: celebrationEffectId,
      celebrationSpeed: 200,
      celebrationIntensity: 180,
    );

/// The ScoreAlertConfig game_day_service hands to AlertTriggerService.
ScoreAlertConfig _asAlertConfig(CommercialTeamProfile p) => ScoreAlertConfig(
      id: 'commercial_${p.teamId}',
      teamSlug: 'nfl_chiefs',
      sport: SportType.nfl,
      celebrationEffectId: p.celebrationEffectId,
      celebrationSpeed: p.celebrationSpeed,
      celebrationIntensity: p.celebrationIntensity,
    );

void main() {
  group('the venue profile carries a celebration', () {
    test('all three fields round-trip through JSON', () {
      final round = CommercialTeamProfile.fromJson(
          _profile(celebrationEffectId: 79).toJson());
      expect(round.celebrationEffectId, 79);
      expect(round.celebrationSpeed, 200);
      expect(round.celebrationIntensity, 180);
    });

    test('written under the same snake_case keys as the residential model', () {
      final raw = _profile(celebrationEffectId: 79).toJson();
      expect(raw, containsPair('celebration_effect_id', 79));
      expect(raw, containsPair('celebration_speed', 200));
      expect(raw, containsPair('celebration_intensity', 180));
    });

    // Every venue profile in the field predates this.
    test('an unset celebration writes no keys and reads back null', () {
      final raw = _profile().toJson();
      expect(raw.containsKey('celebration_effect_id'), isFalse);
      expect(CommercialTeamProfile.fromJson(raw).celebrationEffectId, isNull);
    });

    test('choosing one leaves the existing alert settings alone', () {
      final before = _profile();
      final after = before.copyWith(celebrationEffectId: 79);
      expect(after.celebrationEffectId, 79);
      expect(after.alertIntensity, before.alertIntensity);
      expect(after.alertChannelScope, before.alertChannelScope);
      expect(after.selectedChannelIds, before.selectedChannelIds);
      expect(after.gameDayLeadTimeMinutes, before.gameDayLeadTimeMinutes);
    });

    test('clearCelebrationEffect resets only the celebration', () {
      final after = _profile(celebrationEffectId: 79)
          .copyWith(clearCelebrationEffect: true);
      expect(after.celebrationEffectId, isNull);
      expect(after.teamName, 'Kansas City Chiefs');
    });
  });

  // THE POINT OF THE PHASE: one shared firing path, not a parallel one.
  group('a commercial celebration fires through the residential path', () {
    test('the same contrast resolver runs on it', () {
      final cfg = _asAlertConfig(_profile(celebrationEffectId: 23));
      final clash = resolveCelebration(
        chosenEffectId: cfg.celebrationEffectId,
        chosenSpeed: cfg.celebrationSpeed,
        chosenIntensity: cfg.celebrationIntensity,
        capturedState: const {
          'seg': [
            {'id': 0, 'on': true, 'fx': 23},
          ],
        },
      );
      expect(clash!.usedFallback, isTrue,
          reason: 'a venue gets the same contrast protection');
    });

    test('a distinct effect passes through unmodified, as residential does',
        () {
      final cfg = _asAlertConfig(_profile(celebrationEffectId: 79));
      final r = resolveCelebration(
        chosenEffectId: cfg.celebrationEffectId,
        chosenSpeed: cfg.celebrationSpeed,
        chosenIntensity: cfg.celebrationIntensity,
        capturedState: const {
          'seg': [
            {'id': 0, 'on': true, 'fx': 9},
          ],
        },
      );
      expect(r!.usedFallback, isFalse);
      expect(r.effectId, 79);
      expect(r.speed, 200);
    });

    test('it renders through the same timing table', () {
      const chosen =
          CelebrationResolution(effectId: 79, speed: 200, intensity: 180);
      final steps = AlertTriggerService.buildAnimationSteps(
          AlertEventType.touchdown, _team, chosen);
      expect(steps.fold(Duration.zero, (a, s) => a + s.hold),
          const Duration(seconds: 15));
      for (final s in steps) {
        expect((s.payload['seg'] as List).first as Map,
            containsPair('fx', 79));
      }
    });

    test('a venue win gets the same longest-in-the-table treatment', () {
      const chosen =
          CelebrationResolution(effectId: 79, speed: 200, intensity: 180);
      final steps = AlertTriggerService.buildAnimationSteps(
          AlertEventType.win, _team, chosen);
      expect(steps.fold(Duration.zero, (a, s) => a + s.hold),
          const Duration(seconds: 30));
    });

    test('an unset venue celebration keeps the legacy sequences', () {
      final cfg = _asAlertConfig(_profile());
      expect(
        resolveCelebration(
          chosenEffectId: cfg.celebrationEffectId,
          chosenSpeed: cfg.celebrationSpeed,
          chosenIntensity: cfg.celebrationIntensity,
          capturedState: const {},
        ),
        isNull,
      );
    });
  });
}
