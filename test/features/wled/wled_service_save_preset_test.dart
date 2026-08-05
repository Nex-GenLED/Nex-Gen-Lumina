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

    // Audit 2026-05-29 — savePreset must run state through
    // normalizeWledPayload so the persisted preset's seg.col is padded to
    // all 3 slots. Without this, loadPreset later restores a 1-slot preset
    // and the controller's col[1]/col[2] keep the prior pattern's values
    // (same root cause as the setState bypass).
    test('1-slot col seg → captured state has col padded to 3 slots', () async {
      final ok = await service.savePreset(
        presetId: 7,
        state: <String, dynamic>{
          'on': true,
          'bri': 200,
          'seg': [
            <String, dynamic>{
              'fx': 0,
              'col': [
                [0, 0, 255, 0],
              ],
            },
          ],
        },
      );

      expect(ok, isTrue);
      final captured = service.lastSimulatedPresetSave;
      expect(captured, isNotNull);
      final seg = (captured!.state['seg'] as List).first as Map;
      expect(seg['col'], equals([
        [0, 0, 255, 0],
        [0, 0, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('2-slot col seg → captured state has col padded to 3 slots', () async {
      final ok = await service.savePreset(
        presetId: 8,
        state: <String, dynamic>{
          'on': true,
          'seg': [
            <String, dynamic>{
              'fx': 28,
              'col': [
                [255, 0, 0, 0],
                [255, 215, 0, 0],
              ],
            },
          ],
        },
      );

      expect(ok, isTrue);
      final seg = (service.lastSimulatedPresetSave!.state['seg'] as List)
          .first as Map;
      expect(seg['col'], equals([
        [255, 0, 0, 0],
        [255, 215, 0, 0],
        [0, 0, 0, 0],
      ]));
    });

    test('no-seg payload → gains ONLY a freeze-clearing seg entry', () async {
      // CONTRACT CHANGED DELIBERATELY — audit/FROZEN_SEGMENT_FIX.md.
      //
      // This previously asserted the payload round-tripped unchanged, on the
      // grounds that normalizeWledPayload short-circuits without a seg key.
      // That is still true OF NORMALIZE, but savePreset now also runs
      // ensurePsaveClearsFreeze, because a seg-less psave lets WLED capture the
      // LIVE segment state — including `frz:true` after a per-pixel paint.
      // Bench-proven: such a preset re-freezes on every load and cannot render
      // its own stored colours. The seg-less shape is exactly the ON-presets
      // (1/3/4/5) that schedules fire, so this is the path that mattered.
      //
      // The ORIGINAL INTENT of this test — savePreset must not fabricate
      // segment content — is preserved and still asserted below: the injected
      // entry carries `id` and `frz` and nothing else, so live colour/effect
      // state is untouched and is captured normally.
      final ok = await service.savePreset(
        presetId: 9,
        state: {'on': true, 'bri': 128},
      );

      expect(ok, isTrue);
      final captured = service.lastSimulatedPresetSave!.state;
      expect(captured['on'], isTrue);
      expect(captured['bri'], 128);

      final seg = (captured['seg'] as List).cast<Map<String, dynamic>>();
      expect(seg, isNotEmpty);
      for (final s in seg) {
        expect(s['frz'], isFalse);
        expect(s.keys.toSet(), {'id', 'frz'},
            reason: 'no colour/effect may be synthesized — the psave must '
                'capture whatever is live');
      }
    });
  });
}
