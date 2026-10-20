// Build 119 hides three features from the first App Store build without
// deleting code or data: Lumina Autopilot (with its weekly generation), the
// "Generate This Week's Schedule" button and Simple Mode. These tests pin the
// hidden (flag-off) behaviour and the "returns later" path through the
// Provider twins, so flipping a constant back is the only change needed.
//
// Synthetic account only ("customer A").

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_router.dart' show AppRoutes;
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/feature_visibility.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A customer whose stored profile has Autopilot ON in Proactive mode with
/// the weekly brief opted in — the account shape the hide must neutralise.
UserModel _customerAWithAutopilotOn() {
  final ts = DateTime.utc(2026, 10, 1);
  return UserModel(
    id: 'customer-a',
    email: 'customer-a@example.com',
    displayName: 'Customer A',
    ownerId: 'customer-a',
    createdAt: ts,
    updatedAt: ts,
    autopilotEnabled: true,
    autonomyLevel: 2,
    weeklySchedulePreviewEnabled: true,
    autoDetectGameDays: true,
  );
}

ProviderContainer _container({List<Override> extra = const []}) {
  final c = ProviderContainer(overrides: [
    currentUserProfileProvider
        .overrideWith((ref) => Stream.value(_customerAWithAutopilotOn())),
    ...extra,
  ]);
  addTearDown(c.dispose);
  return c;
}

Future<void> _settle(ProviderContainer c) async {
  await c.read(currentUserProfileProvider.future);
}

/// Lets the notifier's SharedPreferences load (several microtask turns).
Future<void> _drain() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('build 119 visibility flags', () {
    test('all three features default to hidden', () {
      expect(kAutopilotVisible, isFalse);
      expect(kWeeklyScheduleGenerationVisible, isFalse);
      expect(kSimpleModeVisible, isFalse);
    });

    test('the Provider twins default to the constants', () {
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(autopilotVisibleProvider), kAutopilotVisible);
      expect(c.read(weeklyScheduleGenerationVisibleProvider),
          kWeeklyScheduleGenerationVisible);
      expect(c.read(simpleModeVisibleProvider), kSimpleModeVisible);
    });
  });

  group('Autopilot hidden', () {
    test('autopilotEnabledProvider reads false although the profile says ON',
        () async {
      final c = _container();
      await _settle(c);
      expect(c.read(autopilotEnabledProvider), isFalse,
          reason: 'the stored autopilot_enabled=true must not drive anything');
      expect(c.read(needsScheduleRegenerationProvider), isFalse,
          reason: 'no stale-schedule regeneration can be requested');
      expect(c.read(autopilotSyncEventsEnabledProvider), isFalse,
          reason: 'no Autopilot-triggered neighborhood sync events');
    });

    test('the scheduler is constructed but never started', () async {
      final c = _container();
      await _settle(c);
      final scheduler = c.read(autopilotSchedulerProvider);
      expect(scheduler.isRunning, isFalse,
          reason: 'start() runs _runCycle and the minute timer that applies '
              'Proactive patterns to the lights — it must not run while hidden');
      expect(scheduler.activeSchedule, isEmpty);
    });

    test('generation and enable requests are no-ops while hidden', () async {
      final c = _container();
      await _settle(c);
      final svc = c.read(autopilotSettingsServiceProvider);
      await svc.generateAndPopulateSchedules(force: true);
      expect(c.read(autopilotGenerationStateProvider).status,
          AutopilotGenerationStatus.idle,
          reason: 'the forced generation (the hidden button\'s path) returned '
              'before touching the generation state');
      await svc.setEnabled(true);
      await svc.setEnabled(false);
      expect(c.read(autopilotEnabledProvider), isFalse);
    });

    test('returns later: with the twin overridden ON the profile value wins',
        () async {
      final c = _container(
          extra: [autopilotVisibleProvider.overrideWithValue(true)]);
      await _settle(c);
      expect(c.read(autopilotEnabledProvider), isTrue);
      expect(c.read(needsScheduleRegenerationProvider), isTrue,
          reason: 'the profile has no autopilot_last_generated');
    });

    test('hidden Autopilot routes redirect to the Schedule tab', () {
      expect(hiddenAutopilotRouteTarget(), AppRoutes.schedule,
          reason: 'a stale weekly-brief deep link lands on the Schedule tab');
      expect(hiddenAutopilotRouteTarget(visible: true), isNull,
          reason: 'no redirect once the feature returns');
    });
  });

  group('Simple Mode hidden', () {
    test('a device with Simple Mode saved ON reads OFF and is not rewritten',
        () async {
      SharedPreferences.setMockInitialValues({'simple_mode_enabled': true});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      expect(c.read(simpleModeProvider), isFalse);
      await _drain();
      expect(c.read(simpleModeProvider), isFalse,
          reason: 'the saved ON value must not load while hidden');

      final n = c.read(simpleModeProvider.notifier);
      n.enable();
      expect(c.read(simpleModeProvider), isFalse, reason: 'enable() ignored');
      n.toggle();
      expect(c.read(simpleModeProvider), isFalse, reason: 'toggle() ignored');
      n.disable();
      await _drain();

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool('simple_mode_enabled'), isTrue,
          reason: 'the customer\'s saved choice is left in place for when '
              'the feature returns — nothing of theirs is changed');
    });

    test('returns later: with the twin overridden ON the saved value loads',
        () async {
      SharedPreferences.setMockInitialValues({'simple_mode_enabled': true});
      final c = ProviderContainer(
          overrides: [simpleModeVisibleProvider.overrideWithValue(true)]);
      addTearDown(c.dispose);
      // First read builds the notifier, which starts the async load.
      expect(c.read(simpleModeProvider), isFalse);
      await _drain();
      expect(c.read(simpleModeProvider), isTrue,
          reason: 'the saved ON value loads once the feature is visible');
      c.read(simpleModeProvider.notifier).disable();
      expect(c.read(simpleModeProvider), isFalse);
    });
  });
}
