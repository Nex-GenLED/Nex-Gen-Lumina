// test/models/user_model_baseline_flag_test.dart
//
// COMMIT 2 (SCHEDULE CLARITY PAIR) — the consent-gate flag for autopilot's
// daily warm-white baseline.
//
// The flag governs whether autopilot seeds/re-adds the baseline. It must:
//   • default to TRUE (pre-checked; existing behavior preserved),
//   • default to TRUE when ABSENT from Firestore (existing users untouched),
//   • round-trip TRUE and FALSE through toJson/fromJson (a decline persists
//     across regenerations),
//   • flip via copyWith (how the setter writes it).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/models/user_model.dart';

void main() {
  final now = DateTime(2026, 7, 9, 12);
  UserModel base() => UserModel(
        id: 'u1',
        email: 'u1@example.com',
        displayName: 'U One',
        ownerId: 'u1',
        createdAt: now,
        updatedAt: now,
      );

  group('autopilotBaselineEnabled', () {
    test('defaults to true (pre-checked)', () {
      expect(base().autopilotBaselineEnabled, isTrue);
    });

    test('absent from Firestore JSON → defaults to true (existing users)', () {
      final json = base().toJson()..remove('autopilot_baseline_enabled');
      expect(json.containsKey('autopilot_baseline_enabled'), isFalse);
      expect(UserModel.fromJson(json).autopilotBaselineEnabled, isTrue);
    });

    test('declined state (false) round-trips through toJson/fromJson', () {
      final declined = base().copyWith(autopilotBaselineEnabled: false);
      expect(declined.autopilotBaselineEnabled, isFalse);

      final json = declined.toJson();
      expect(json['autopilot_baseline_enabled'], isFalse);

      final restored = UserModel.fromJson(json);
      expect(restored.autopilotBaselineEnabled, isFalse,
          reason: 'a decline must survive reload → regeneration honors it');
    });

    test('explicit true round-trips', () {
      final json = base().copyWith(autopilotBaselineEnabled: true).toJson();
      expect(json['autopilot_baseline_enabled'], isTrue);
      expect(UserModel.fromJson(json).autopilotBaselineEnabled, isTrue);
    });

    test('copyWith without the arg leaves the flag unchanged', () {
      final declined = base().copyWith(autopilotBaselineEnabled: false);
      expect(declined.copyWith(displayName: 'renamed').autopilotBaselineEnabled,
          isFalse);
    });
  });
}
