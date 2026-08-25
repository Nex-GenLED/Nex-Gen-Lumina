// Phase B — the automatic runtime contrast check.
//
// A celebration that matches what the house is already showing is invisible.
// The old code could not notice: buildAnimationSteps took only (eventType,
// team), and the captured state went to the restore path and nowhere else
// (audit/GAME_DAY_SPEC_AUDIT.md §2.4).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/sports_alerts/services/celebration_contrast.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// A `/json/state` snapshot with `seg` as a LIST (the common firmware shape).
Map<String, dynamic> _stateList(int fx, {bool on = true}) => {
      'on': true,
      'bri': 200,
      'seg': [
        {'id': 0, 'on': on, 'fx': fx},
      ],
    };

/// The same, with `seg` as a MAP — the other firmware shape.
Map<String, dynamic> _stateMap(int fx) => {
      'on': true,
      'seg': {
        '0': {'id': 0, 'on': true, 'fx': fx},
      },
    };

/// Two distinct Strobe-category effects, and a pulse-motion effect, taken from
/// the catalog rather than hardcoded so the test tracks the real data.
int get _strobeA => WledEffectsCatalog.celebrationPicks
    .firstWhere((e) => e.category == 'Strobe')
    .id;
int get _strobeB => WledEffectsCatalog.celebrationPicks
    .where((e) => e.category == 'Strobe')
    .elementAt(1)
    .id;
int get _pulse => WledEffectsCatalog.celebrationPicks
    .firstWhere((e) =>
        WledEffectsCatalog.getMotionType(e.category) == MotionType.pulse)
    .id;

CelebrationResolution? _resolve(int? chosen, Map<String, dynamic>? state) =>
    resolveCelebration(
      chosenEffectId: chosen,
      chosenSpeed: 200,
      chosenIntensity: 180,
      capturedState: state,
    );

void main() {
  group('the "too similar" definition', () {
    test('same effect id clashes', () {
      expect(WledEffectsCatalog.effectsTooSimilar(_strobeA, _strobeA), isTrue);
    });

    // The rule that matters: two DIFFERENT strobes still read as one strobe.
    test('two different Strobe-category effects clash', () {
      expect(_strobeA, isNot(_strobeB));
      expect(WledEffectsCatalog.effectsTooSimilar(_strobeA, _strobeB), isTrue);
    });

    test('two different pulse-motion effects clash', () {
      final pulses = WledEffectsCatalog.celebrationPicks
          .where((e) =>
              WledEffectsCatalog.getMotionType(e.category) == MotionType.pulse)
          .toList();
      expect(pulses.length, greaterThan(1));
      expect(
        WledEffectsCatalog.effectsTooSimilar(pulses[0].id, pulses[1].id),
        isTrue,
      );
    });

    // Strobe maps to MotionType.sweep, pulse comes from Ambient/Ripple/etc, so
    // these are genuinely different groups and must NOT clash with each other.
    test('a Strobe and a pulse effect do NOT clash', () {
      expect(WledEffectsCatalog.effectsTooSimilar(_strobeA, _pulse), isFalse);
    });

    test('an unknown effect id never clashes — it cannot be classified', () {
      expect(WledEffectsCatalog.effectsTooSimilar(_strobeA, 9999), isFalse);
    });
  });

  group('resolveCelebration — the required behaviours', () {
    // REQUIRED TEST 1: celebration equal to the captured base state's effect
    // → fallback fires.
    test('chosen effect == current house effect → fallback', () {
      final r = _resolve(_strobeA, _stateList(_strobeA));
      expect(r, isNotNull);
      expect(r!.usedFallback, isTrue);
      expect(r.effectId, kFallbackCelebrationEffectId);
      expect(r.speed, kFallbackCelebrationSpeed);
      expect(r.intensity, kFallbackCelebrationIntensity);
    });

    // REQUIRED TEST 2: different from captured state → user's choice fires
    // UNMODIFIED, speed and intensity included.
    test('chosen effect != current house effect → chosen, unmodified', () {
      final r = _resolve(_pulse, _stateList(_strobeA));
      expect(r, isNotNull);
      expect(r!.usedFallback, isFalse);
      expect(r.effectId, _pulse);
      expect(r.speed, 200);
      expect(r.intensity, 180);
    });

    test('a clash on CATEGORY, not just id, also falls back', () {
      final r = _resolve(_strobeA, _stateList(_strobeB));
      expect(r!.usedFallback, isTrue);
    });
  });

  group('reading the live state', () {
    test('seg as a List is read', () {
      expect(currentEffectId(_stateList(42)), 42);
    });

    // Same codebase gotcha that bit the schedule work: `seg` is a Map on some
    // firmware. Missing this would silently disable the check on that firmware.
    test('seg as a Map is read too', () {
      expect(currentEffectId(_stateMap(42)), 42);
    });

    test('an OFF segment is skipped in favour of one that is on', () {
      final state = {
        'seg': [
          {'id': 0, 'on': false, 'fx': 11},
          {'id': 1, 'on': true, 'fx': 42},
        ],
      };
      expect(currentEffectId(state), 42);
    });

    test('null / empty / shapeless state reads as unknown', () {
      expect(currentEffectId(null), isNull);
      expect(currentEffectId(const {}), isNull);
      expect(currentEffectId(const {'seg': []}), isNull);
      expect(currentEffectId(const {'seg': <String, dynamic>{}}), isNull);
      expect(currentEffectId(const {'on': true}), isNull);
      expect(currentEffectId(const {'seg': [{'id': 0}]}), isNull);
    });
  });

  group('the safety posture', () {
    // FAIL-OPEN. Substituting a white flood every time a read hiccups is worse
    // than the invisibility the check guards against.
    test('unreadable state → the user\'s choice fires, not the fallback', () {
      for (final state in <Map<String, dynamic>?>[
        null,
        const {},
        const {'seg': []},
      ]) {
        final r = _resolve(_strobeA, state);
        expect(r!.usedFallback, isFalse, reason: 'state: $state');
        expect(r.effectId, _strobeA);
      }
    });

    // This is what keeps the whole feature inert for every pre-existing config.
    test('no chosen effect → null, so the legacy sequences are used verbatim',
        () {
      expect(_resolve(null, _stateList(23)), isNull);
      expect(_resolve(null, null), isNull);
    });

    test('the fallback is one fixed thing, never a second user choice', () {
      final a = _resolve(_strobeA, _stateList(_strobeA))!;
      final b = _resolve(_strobeB, _stateList(_strobeB))!;
      expect(a, b, reason: 'every clash resolves to the same safe celebration');
    });

    test('the fallback colour is white, the one axis a team colour cannot match',
        () {
      expect(kFallbackCelebrationColor, [255, 255, 255, 255]);
    });
  });
}
