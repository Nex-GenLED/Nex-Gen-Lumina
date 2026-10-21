import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

import '../../helpers/recording_wled_repository.dart';

// Store readiness 3a. The schedule editor defaulted a NEW schedule's OFF to
// sunrise whenever the solar flag was on. On the simulated controller (the App
// Store review account, the showroom demo) that schedule can never arm,
// because schedule_sync arms solar only for a ClockInfoSource. So the
// reviewer's first save ended in a red "None of your schedules could be
// armed". The editor now asks scheduleSolarSelectableProvider for both the
// default and the Solar segments.
void main() {
  bool selectable({required bool flag, required WledRepository? repo}) {
    final container = ProviderContainer(overrides: [
      solarSchedulingEnabledSyncProvider.overrideWithValue(flag),
      wledRepositoryProvider.overrideWithValue(repo),
    ]);
    addTearDown(container.dispose);
    return container.read(scheduleSolarSelectableProvider);
  }

  test('simulated controller: solar is never offered, even with the flag on',
      () {
    expect(selectable(flag: true, repo: DemoWledRepository()), isFalse);
  });

  test('real controller with the flag on: solar offered (unchanged)', () {
    expect(selectable(flag: true, repo: RecordingWledRepository()), isTrue);
  });

  test('offline (no repo) keeps the flag answer', () {
    expect(selectable(flag: true, repo: null), isTrue);
    expect(selectable(flag: false, repo: null), isFalse);
  });

  test('flag off: never offered, whatever the repo', () {
    expect(selectable(flag: false, repo: RecordingWledRepository()), isFalse);
    expect(selectable(flag: false, repo: DemoWledRepository()), isFalse);
  });
}
