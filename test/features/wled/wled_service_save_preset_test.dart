// test/features/wled/wled_service_save_preset_test.dart
//
// Item #67 — coverage for the savePreset → explicit-Content-Length
// migration. Mirrors the simulation-capture pattern the Workstream B
// integration tests already use (host='mock'), so the assertions exercise
// the same control-flow branches that production WledService uses,
// including the presetId guard, the captured-state shape, and the
// optional preset-name field. The new non-simulate HTTP path is exercised
// in field testing on ESP32_Ethernet hardware where the chunked-transfer
// bug originally surfaced — unit tests stay on the simulation hook.
//
// The cache invalidation line (`_presetNamesCache = null;`) lives only
// on the live HTTP success path and was preserved verbatim through the
// migration. It's intentionally not exercised here: the cache field is
// private and the simulation branch — which these tests target — does
// not touch it. Coverage of the cache behavior belongs in a future test
// that goes through HttpOverrides against the live path.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';

void main() {
  group('WledService.savePreset (simulation mode)', () {
    late WledService service;

    setUp(() {
      service = WledService('http://mock');
    });

    test('returns true and populates lastSimulatedPresetSave', () async {
      final ok = await service.savePreset(
        presetId: 42,
        state: {'on': true, 'bri': 128},
      );

      expect(ok, isTrue);
      expect(service.lastSimulatedPresetSave, isNotNull);
      expect(service.lastSimulatedPresetSave!.presetId, 42);
      expect(service.lastSimulatedPresetSave!.state['on'], isTrue);
      expect(service.lastSimulatedPresetSave!.state['bri'], 128);
      expect(service.lastSimulatedPresetSave!.presetName, isNull);
    });

    test('returns false for presetId 0 without touching simulation capture',
        () async {
      final ok = await service.savePreset(
        presetId: 0,
        state: {'on': true},
      );

      expect(ok, isFalse);
      expect(service.lastSimulatedPresetSave, isNull);
    });

    test('returns false for presetId 251 without touching simulation capture',
        () async {
      final ok = await service.savePreset(
        presetId: 251,
        state: {'on': true},
      );

      expect(ok, isFalse);
      expect(service.lastSimulatedPresetSave, isNull);
    });

    test('returns false for negative presetId without touching simulation capture',
        () async {
      final ok = await service.savePreset(
        presetId: -1,
        state: {'on': true},
      );

      expect(ok, isFalse);
      expect(service.lastSimulatedPresetSave, isNull);
    });

    test('with presetName includes presetName in the captured record',
        () async {
      final ok = await service.savePreset(
        presetId: 100,
        state: {'on': true, 'bri': 200},
        presetName: 'Warm White',
      );

      expect(ok, isTrue);
      expect(service.lastSimulatedPresetSave, isNotNull);
      expect(service.lastSimulatedPresetSave!.presetName, 'Warm White');
    });

    test('without presetName leaves presetName null in the captured record',
        () async {
      final ok = await service.savePreset(
        presetId: 100,
        state: {'on': true},
      );

      expect(ok, isTrue);
      expect(service.lastSimulatedPresetSave, isNotNull);
      expect(service.lastSimulatedPresetSave!.presetName, isNull);
    });

    test('respects simulateSavePresetReturns=false', () async {
      service.simulateSavePresetReturns = false;
      final ok = await service.savePreset(
        presetId: 42,
        state: {'on': true},
      );

      expect(ok, isFalse);
      // Capture still happens — the flag toggles the return value only.
      expect(service.lastSimulatedPresetSave, isNotNull);
      expect(service.lastSimulatedPresetSave!.presetId, 42);
    });
  });
}
