// Build 120 (owner decision 2026-10-22): the Neighborhood Sync fan-out — the
// payload the host's app hands applySyncPattern for members whose app is
// closed — crosses the same normalizer every applyJson does. Before this, an
// app-open member capped a Strobe at 230 through its own engine while a
// bridge-only member received the host's raw value. Nothing else on the sync
// path changes: flag off means no fan-out call, the broadcast still follows,
// and the payload keeps its one id-less segment (the function's partition
// path depends on that shape). Synthetic ids only.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/features/wled/pattern_flash_safety.dart';

void main() {
  final now = DateTime.utc(2026, 10, 25, 20, 0);

  SyncCommand command({
    required int effectId,
    required int speed,
    required int intensity,
  }) =>
      SyncCommand(
        id: 'c1',
        groupId: 'g',
        effectId: effectId,
        colors: const [0xFF0000, 0x00FF00],
        speed: speed,
        intensity: intensity,
        brightness: 200,
        startTimestamp: now,
        memberDelays: const {'u1': 0, 'u2': 250},
        timingConfig: const SyncTimingConfig(),
      );

  ProviderContainer containerWith(_CapturingService service,
      {required bool fanoutOn}) {
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(service),
      syncFanoutEnabledSyncProvider.overrideWithValue(fanoutOn),
    ]);
    addTearDown(c.dispose);
    return c;
  }

  Map<String, dynamic> seg0(Map<String, dynamic> p) =>
      Map<String, dynamic>.from((p['seg'] as List).single as Map);

  group('the fan-out payload is normalized before it is sent', () {
    test('a Strobe at 255 goes out at the cap; the broadcast still follows',
        () async {
      final svc = _CapturingService();
      final c = containerWith(svc, fanoutOn: true);
      final result = await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(effectId: 23, speed: 255, intensity: 128));
      expect(result?.ok, isTrue);
      expect(svc.fanoutPayloads, hasLength(1));
      final s = seg0(svc.fanoutPayloads.single);
      expect(s['fx'], 23);
      expect(s['sx'], kStrobeSpeedCap);
      expect(s['ix'], 128, reason: 'a strobe\'s intensity is duty cycle');
      expect(svc.broadcasts, hasLength(1));
    });

    test('a Lightning at 200 / 220 goes out at 40 / 60', () async {
      final svc = _CapturingService();
      final c = containerWith(svc, fanoutOn: true);
      await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(effectId: 57, speed: 200, intensity: 220));
      final s = seg0(svc.fanoutPayloads.single);
      expect(s['fx'], 57);
      expect(s['sx'], kLightningSpeedCap);
      expect(s['ix'], kLightningIntensityCap);
    });

    test('any other effect is untouched, and the shape the function partitions '
        'on is kept: one segment, no id, three colour slots, on and bri',
        () async {
      final svc = _CapturingService();
      final c = containerWith(svc, fanoutOn: true);
      await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(effectId: 28, speed: 255, intensity: 255));
      final p = svc.fanoutPayloads.single;
      expect(p['on'], isTrue);
      expect(p['bri'], 200);
      expect((p['seg'] as List), hasLength(1));
      final s = seg0(p);
      expect(s.containsKey('id'), isFalse);
      expect(s['fx'], 28);
      expect(s['sx'], 255);
      expect(s['ix'], 255);
      expect((s['col'] as List), hasLength(3));
      expect((s['col'] as List).first, [255, 0, 0, 0]);
      expect(s['grp'], 1);
      expect(s['spc'], 0);
    });

    test('flag off: no fan-out call at all, only the broadcast (unchanged)',
        () async {
      final svc = _CapturingService();
      final c = containerWith(svc, fanoutOn: false);
      final result = await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(effectId: 23, speed: 255, intensity: 128));
      expect(result, isNull);
      expect(svc.fanoutPayloads, isEmpty);
      expect(svc.broadcasts, hasLength(1));
    });
  });
}

/// `implements` on purpose: the real service's constructor wants a live
/// Firebase app. Only the two calls broadcastSync makes are answered; anything
/// else fails loudly.
class _CapturingService implements NeighborhoodService {
  final List<Map<String, dynamic>> fanoutPayloads = [];
  final List<SyncCommand> broadcasts = [];

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    fanoutPayloads.add(payload);
    return const FanoutResult(ok: true);
  }

  @override
  Future<void> broadcastSyncCommand(SyncCommand command) async {
    broadcasts.add(command);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}
