// Phase A — the celebration effect's second design slot.
//
// Before this existed there was exactly ONE design slot on the config, taken by
// the base look the house runs during the game (audit/GAME_DAY_SPEC_AUDIT.md
// §4). The whole risk of adding a second is that it quietly writes through to
// the first, so these lock the separation as hard as the round-trip.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_config.dart';
import 'package:nexgen_command/features/autopilot/game_day_background_persistence.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

GameDayAutopilotConfig _cfg({
  int? celebrationEffectId,
  int celebrationSpeed = 240,
  int celebrationIntensity = 240,
}) =>
    GameDayAutopilotConfig(
      teamSlug: 'nfl_chiefs',
      teamName: 'Kansas City Chiefs',
      espnTeamId: '12',
      sport: SportType.nfl,
      primaryColorValue: 0xFFE31837,
      secondaryColorValue: 0xFFFFB81C,
      // Base design — must survive every celebration write untouched.
      savedDesignName: 'Chiefs Sweep',
      savedDesignPayload: const {'seg': [{'fx': 9}]},
      effectId: 9,
      speed: 160,
      intensity: 128,
      celebrationEffectId: celebrationEffectId,
      celebrationSpeed: celebrationSpeed,
      celebrationIntensity: celebrationIntensity,
      createdAt: DateTime.utc(2026, 8, 25),
      updatedAt: DateTime.utc(2026, 8, 25),
    );

void main() {
  group('the second slot round-trips', () {
    test('effect id, speed and intensity survive Firestore', () {
      final round = GameDayAutopilotConfig.fromFirestore(
        _cfg(celebrationEffectId: 23, celebrationSpeed: 200, celebrationIntensity: 180)
            .toFirestore(),
      );
      expect(round.celebrationEffectId, 23);
      expect(round.celebrationSpeed, 200);
      expect(round.celebrationIntensity, 180);
    });

    test('written under snake_case keys', () {
      final raw = _cfg(celebrationEffectId: 23).toFirestore();
      expect(raw, containsPair('celebration_effect_id', 23));
      expect(raw, containsPair('celebration_speed', 240));
      expect(raw, containsPair('celebration_intensity', 240));
    });

    // Every config in the fleet predates this feature. None of them may
    // silently acquire an effect id.
    test('an absent field reads as null, NOT as a real effect', () {
      final raw = _cfg(celebrationEffectId: 23).toFirestore()
        ..remove('celebration_effect_id');
      final round = GameDayAutopilotConfig.fromFirestore(raw);
      expect(round.celebrationEffectId, isNull);
      expect(round.hasCelebrationEffect, isFalse);
    });

    test('an unset celebration writes NO celebration keys at all', () {
      final raw = _cfg().toFirestore();
      expect(raw.containsKey('celebration_effect_id'), isFalse);
      expect(raw.containsKey('celebration_speed'), isFalse);
      expect(raw.containsKey('celebration_intensity'), isFalse);
    });

    test('hasCelebrationEffect flips only when an id is set', () {
      expect(_cfg().hasCelebrationEffect, isFalse);
      expect(_cfg(celebrationEffectId: 23).hasCelebrationEffect, isTrue);
    });
  });

  // THE SEPARATION. This is the assertion the phase exists for.
  group('choosing a celebration does not touch the base design', () {
    test('copyWith leaves savedDesignPayload / effectId / speed / intensity',
        () {
      final before = _cfg();
      final after = before.copyWith(
        celebrationEffectId: 23,
        celebrationSpeed: 200,
        celebrationIntensity: 180,
      );

      expect(after.celebrationEffectId, 23);
      // ...and every base-design field is byte-identical.
      expect(after.savedDesignName, before.savedDesignName);
      expect(after.savedDesignPayload, before.savedDesignPayload);
      expect(after.effectId, before.effectId);
      expect(after.speed, before.speed);
      expect(after.intensity, before.intensity);
    });

    test('the two slots hold DIFFERENT values simultaneously', () {
      final c = _cfg(celebrationEffectId: 23, celebrationSpeed: 200);
      expect(c.effectId, 9, reason: 'base design');
      expect(c.celebrationEffectId, 23, reason: 'celebration');
      expect(c.speed, 160);
      expect(c.celebrationSpeed, 200);
    });

    test('a base-design change leaves the celebration alone', () {
      final after = _cfg(celebrationEffectId: 23).copyWith(effectId: 76);
      expect(after.effectId, 76);
      expect(after.celebrationEffectId, 23);
    });

    test('clearCelebrationEffect resets only the celebration', () {
      final after =
          _cfg(celebrationEffectId: 23).copyWith(clearCelebrationEffect: true);
      expect(after.celebrationEffectId, isNull);
      expect(after.effectId, 9);
      expect(after.savedDesignPayload, isNotNull);
    });
  });

  // The worker path renders celebrations too, so a choice invisible to the
  // background isolate would be honoured on one path and ignored on the other.
  group('the background mirror carries the choice', () {
    test('fromConfig copies all three fields', () {
      final bg = BackgroundGameDayAutopilotConfig.fromConfig(
          _cfg(celebrationEffectId: 23, celebrationSpeed: 200, celebrationIntensity: 180));
      expect(bg.celebrationEffectId, 23);
      expect(bg.celebrationSpeed, 200);
      expect(bg.celebrationIntensity, 180);
    });

    test('they survive the prefs JSON round-trip', () {
      final bg = BackgroundGameDayAutopilotConfig.fromJson(
        BackgroundGameDayAutopilotConfig.fromConfig(
                _cfg(celebrationEffectId: 23))
            .toJson(),
      );
      expect(bg.celebrationEffectId, 23);
    });

    test('an unset choice mirrors as null, not a default effect', () {
      final bg = BackgroundGameDayAutopilotConfig.fromConfig(_cfg());
      expect(bg.celebrationEffectId, isNull);
    });
  });

  group('the picker offers only attention-grabbing effects', () {
    test('celebrationPicks is non-empty', () {
      expect(WledEffectsCatalog.celebrationPicks, isNotEmpty);
    });

    test('every entry is a Strobe or a pulse-motion effect', () {
      for (final e in WledEffectsCatalog.celebrationPicks) {
        expect(WledEffectsCatalog.isCelebrationEffect(e), isTrue,
            reason: '${e.name} (${e.category}) should not be offered');
      }
    });

    // The union really is a union: the Strobe CATEGORY maps to
    // MotionType.sweep, not pulse, so filtering on either alone loses half.
    test('it spans BOTH groups, not just one', () {
      final picks = WledEffectsCatalog.celebrationPicks;
      expect(picks.any((e) => e.category == 'Strobe'), isTrue);
      expect(
        picks.any((e) =>
            WledEffectsCatalog.getMotionType(e.category) == MotionType.pulse),
        isTrue,
      );
    });

    test('calm ambience is NOT offered as a celebration', () {
      final names =
          WledEffectsCatalog.celebrationPicks.map((e) => e.name).toSet();
      expect(names.contains('Solid'), isFalse);
    });

    test('no 2D or audio-reactive effects — they need hardware not every install has',
        () {
      for (final e in WledEffectsCatalog.celebrationPicks) {
        expect(e.requires2D, isFalse, reason: e.name);
        expect(e.requiresAudio, isFalse, reason: e.name);
      }
    });
  });

  test('created_at/updated_at still serialize as Timestamps', () {
    final raw = _cfg(celebrationEffectId: 23).toFirestore();
    expect(raw['created_at'], isA<Timestamp>());
    expect(raw['updated_at'], isA<Timestamp>());
  });
}
