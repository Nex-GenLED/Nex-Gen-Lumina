// test/features/autopilot/commercial_autopilot_parity_test.dart
//
// COMMIT 1 regression pin — the "commercial autopilot trap".
//
// background_learning_service.dart used to early-return on commercial mode in
// BOTH checkAndRunSundayRegen and runAutopilotRegenIfNeeded, deferring to
// DayPartSchedulerService. That handoff was never wired: the scheduler's only
// caller is a manual save inside the orphaned /commercial shell, and nothing
// writes the `commercial_schedule` collection it reads. Net effect — flipping
// profile_type to 'commercial' turned residential automation OFF and never
// turned commercial automation ON, so the account's lights silently stopped
// changing. (2026-07-14 commercial audit.)
//
// Both gates are now removed, so autopilot regeneration must be driven purely
// by autopilotEnabled — never by profileType. These tests pin that parity: a
// commercial profile and a residential profile that differ ONLY in
// profile_type must gate identically.
//
// This asserts the GATING PROVIDERS rather than the static WidgetRef methods
// on BackgroundLearningService: those methods read exactly these providers to
// decide whether to regenerate, and driving them directly would require a
// full widget pump plus a live FirebaseAuth session for no added coverage.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/background_learning_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';

/// Records whether regeneration was actually invoked, without touching
/// Firestore. Subclasses the real service so the provider override keeps its
/// declared type.
class _RecordingSettingsService extends AutopilotSettingsService {
  _RecordingSettingsService(super.ref);

  int generateCalls = 0;

  @override
  Future<void> generateAndPopulateSchedules({bool force = false}) async {
    generateCalls++;
  }
}

/// A profile that differs from its sibling ONLY in [profileType].
UserModel _profile({
  required String profileType,
  bool autopilotEnabled = true,
}) {
  final ts = DateTime.utc(2026, 7, 14);
  return UserModel(
    id: 'uid-blue-line',
    email: 'steve@bluelinebar.example',
    displayName: 'Blue Line Bar',
    ownerId: 'uid-blue-line',
    createdAt: ts,
    updatedAt: ts,
    profileType: profileType,
    autopilotEnabled: autopilotEnabled,
  );
}

ProviderContainer _containerFor(UserModel profile) {
  final container = ProviderContainer(
    overrides: [
      currentUserProfileProvider.overrideWith((ref) => Stream.value(profile)),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

/// Resolves the async profile stream so downstream sync providers see data
/// rather than their `orElse` fallback.
Future<void> _settle(ProviderContainer c) async {
  await c.read(currentUserProfileProvider.future);
}

void main() {
  group('commercial autopilot parity — regen gate ignores profile_type', () {
    test('autopilotEnabled: commercial matches residential', () async {
      final residential = _containerFor(_profile(profileType: 'residential'));
      final commercial = _containerFor(_profile(profileType: 'commercial'));
      await _settle(residential);
      await _settle(commercial);

      expect(commercial.read(autopilotEnabledProvider), isTrue,
          reason: 'a commercial account must still run standard autopilot — '
              'the day-part scheduler that justified the old gate has no '
              'data writers and one orphaned caller');
      expect(
        commercial.read(autopilotEnabledProvider),
        residential.read(autopilotEnabledProvider),
        reason: 'profile_type must not influence the autopilot gate',
      );
    });

    test('needsScheduleRegeneration: commercial matches residential',
        () async {
      final residential = _containerFor(_profile(profileType: 'residential'));
      final commercial = _containerFor(_profile(profileType: 'commercial'));
      await _settle(residential);
      await _settle(commercial);

      // No lastGenerated stamp => regeneration is due for both.
      expect(commercial.read(needsScheduleRegenerationProvider), isTrue);
      expect(
        commercial.read(needsScheduleRegenerationProvider),
        residential.read(needsScheduleRegenerationProvider),
        reason: 'regeneration need must not depend on profile_type',
      );
    });

    test('autopilotEnabled:false still disables BOTH profile types', () async {
      final residential = _containerFor(
          _profile(profileType: 'residential', autopilotEnabled: false));
      final commercial = _containerFor(
          _profile(profileType: 'commercial', autopilotEnabled: false));
      await _settle(residential);
      await _settle(commercial);

      // Removing the commercial gate must not make autopilot unstoppable —
      // the user's own opt-out is still the one real switch.
      expect(commercial.read(autopilotEnabledProvider), isFalse);
      expect(commercial.read(needsScheduleRegenerationProvider), isFalse);
      expect(
        commercial.read(autopilotEnabledProvider),
        residential.read(autopilotEnabledProvider),
      );
    });

    // ── The load-bearing pin ────────────────────────────────────────────────
    // The three tests above assert provider parity, which is necessary but NOT
    // sufficient: the removed gate lived inside the static method, not in the
    // providers, so those tests would pass against the old code too. This one
    // drives runAutopilotRegenIfNeeded itself and asserts regeneration is
    // actually invoked for a commercial account. Against the old
    // `if (isCommercial) return;` this FAILS with generateCalls == 0.
    testWidgets('runAutopilotRegenIfNeeded REGENERATES for a commercial '
        'account (fails against the old early-return)', (tester) async {
      late _RecordingSettingsService recorder;
      late WidgetRef capturedRef;

      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            currentUserProfileProvider.overrideWith(
                (ref) => Stream.value(_profile(profileType: 'commercial'))),
            autopilotEnabledProvider.overrideWithValue(true),
            needsScheduleRegenerationProvider.overrideWithValue(true),
            autopilotSettingsServiceProvider.overrideWith((ref) {
              recorder = _RecordingSettingsService(ref);
              return recorder;
            }),
          ],
          child: Consumer(
            builder: (context, ref, _) {
              capturedRef = ref;
              return const SizedBox.shrink();
            },
          ),
        ),
      );

      // Drive the real static entry point with a live WidgetRef. Its internal
      // call to checkAndRunSundayRegen touches FirebaseAuth, which is
      // uninitialised here — that path is inside its own try/catch and is not
      // what this test measures.
      await BackgroundLearningService.runAutopilotRegenIfNeeded(capturedRef);
      await tester.pumpAndSettle();

      expect(recorder.generateCalls, 1,
          reason: 'a commercial account must regenerate its autopilot '
              'schedule — the old gate skipped this and handed off to a '
              'day-part scheduler that never runs, silently freezing the '
              "account's lights");
    });

    test('isCommercialProfileProvider still reports commercial correctly',
        () async {
      // The flag itself must keep working — Commit 1 removes autopilot's
      // dependence on it, not the flag. autopilot_weekly_preview still reads
      // this to render happy-hour rows.
      final commercial = _containerFor(_profile(profileType: 'commercial'));
      final residential = _containerFor(_profile(profileType: 'residential'));
      await _settle(commercial);
      await _settle(residential);

      expect(commercial.read(isCommercialProfileProvider), isTrue);
      expect(residential.read(isCommercialProfileProvider), isFalse);
    });
  });
}
