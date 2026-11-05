// Roofline slice 1, G4 (the TD-9 remainder) — the bus-change watcher re-heals
// on a COUNT-ONLY change: the same buses, one of them a different length.
//
// Before: `ladderBusChangeWatchProvider` handed the watcher the channel ids
// only, and `busSetChanged` compared id lists, so bus 2 going from 100 to 120
// LEDs on the same three ids compared equal — no marker clear, no re-heal,
// and the facts stayed as they were. This file is the fail-before proof
// against that code: it drives the provider through the surface that existed
// before the change (deviceHardwareConfigProvider as the watcher's input,
// controllerDefaultsHealerProvider as its output), so it compiles there and
// the first test fails there.
//
// Fixture: one controller, three buses of 100 LEDs (ids 0, 1, 2); then the
// same three with bus 2 at 120 (count-only); then two buses (count differs);
// and the same three read again (provider churn, not a change).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_hardware_config.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _threeOf100 = WledHardwareConfig(totalLeds: 300, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 100),
  WledLedBus(pin: [16], start: 200, len: 100),
]);

/// The same three buses after the LED-count save set bus 2 to 120.
const _bus2At120 = WledHardwareConfig(totalLeds: 320, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 120),
  WledLedBus(pin: [16], start: 220, len: 100),
]);

const _twoOf100 = WledHardwareConfig(totalLeds: 200, buses: [
  WledLedBus(pin: [2], start: 0, len: 100),
  WledLedBus(pin: [14], start: 100, len: 100),
]);

class _FakeWledNotifier extends WledNotifier {
  @override
  WledStateModel build() => WledStateModel.initial();
}

/// The hardware config as the app re-reads it: the watcher's one input.
final _hw = StateProvider<WledHardwareConfig?>((ref) => _threeOf100);

/// The watcher acts from a microtask and awaits the marker store and the
/// heal; a few turns of the event loop let all of that finish.
Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProviderContainer container;
  late int reheals;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    reheals = 0;
    container = ProviderContainer(overrides: [
      deviceHardwareConfigProvider.overrideWith((ref) async => ref.watch(_hw)),
      controllerDefaultsHealerProvider.overrideWithValue(() async {
        reheals++;
        return ControllerHealReport();
      }),
      // The watcher acts only for a LAN endpoint; the address is never
      // contacted (documentation range).
      wledRepositoryProvider.overrideWith((ref) => WledService('http://192.0.2.10')),
      selectedControllerIdProvider.overrideWithValue('AA00000000A1'),
      wledStateProvider.overrideWith(() => _FakeWledNotifier()),
    ]);
    addTearDown(container.dispose);
  });

  /// Connect: the watcher takes its first reading of the three buses.
  Future<void> firstReading() async {
    container.read(ladderBusChangeWatchProvider);
    await container.read(deviceHardwareConfigProvider.future);
    await _settle();
    expect(reheals, 0, reason: 'a first reading is not a change');
  }

  /// The hardware config is re-read and shows [hw].
  Future<void> busesBecome(WledHardwareConfig hw) async {
    container.read(_hw.notifier).state = hw;
    await container.read(deviceHardwareConfigProvider.future);
    await _settle();
  }

  test('bus 2 goes from 100 to 120 LEDs on the same three ids → the heal re-runs',
      () async {
    await firstReading();
    await busesBecome(_bus2At120);
    expect(reheals, 1,
        reason: 'an ids-only comparison misses a count-only change (TD-9 remainder)');
  });

  test('the same three buses read again (provider churn) → no re-heal', () async {
    await firstReading();
    await busesBecome(_threeOf100);
    expect(reheals, 0);
  });

  test('a bus removed (three → two) still re-heals, as before', () async {
    await firstReading();
    await busesBecome(_twoOf100);
    expect(reheals, 1);
  });

  test('after a count-only change, reading the same changed layout again is not '
      'another change', () async {
    await firstReading();
    await busesBecome(_bus2At120);
    await busesBecome(_bus2At120);
    expect(reheals, 1);
  });
}
