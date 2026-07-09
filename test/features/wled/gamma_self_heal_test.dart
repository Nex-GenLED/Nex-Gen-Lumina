// Gamma self-heal — re-assert cfg.light.gc once per LAN connect.
//
// Audit context: no app cfg writer reverts cfg.light.gc; gamma is asserted only
// at install / manual Re-sync, so an external reset (reflash, WLED web-UI cfg
// save, factory restore) persists until re-sync. gammaSelfHealProvider closes
// that gap by re-asserting on each new LAN-controller connect. These tests
// cover the connect-transition predicate, LAN-only gating, the skip-vs-write
// decision (via the pure pushGammaConfig helpers), and failure inertness — all
// without an HTTP layer (the device write is injected via
// gammaSelfHealActionProvider).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

void main() {
  // ── Connect-lifecycle wiring: which repo transitions trigger a heal ────────
  group('shouldSelfHealGammaOnConnect', () {
    final lanA = WledService('http://192.168.1.250');
    final lanA2 = WledService('http://192.168.1.250'); // same IP, fresh instance
    final lanB = WledService('http://192.168.1.99');
    final relay = DemoWledRepository(); // stands in for any non-LAN repo

    test('null → LAN: fires (fresh connect / fireImmediately)', () {
      expect(shouldSelfHealGammaOnConnect(null, lanA), true);
    });

    test('non-LAN → LAN: fires (remote/relay switch to local)', () {
      expect(shouldSelfHealGammaOnConnect(relay, lanA), true);
    });

    test('same LAN IP (provider churn, new WledService instance): does NOT fire',
        () {
      expect(shouldSelfHealGammaOnConnect(lanA, lanA2), false);
    });

    test('LAN A → LAN B (controller switch): fires', () {
      expect(shouldSelfHealGammaOnConnect(lanA, lanB), true);
    });

    test('LAN → non-LAN or null (disconnect): does NOT fire', () {
      expect(shouldSelfHealGammaOnConnect(lanA, relay), false);
      expect(shouldSelfHealGammaOnConnect(lanA, null), false);
    });
  });

  // ── Skip-vs-write decision (the "satisfied → no POST / drift → POST+verify"
  //    contract lives inside pushGammaConfig; assert it via its pure helpers) ──
  group('gamma skip-vs-write decision', () {
    test('satisfied cfg → gammaConfigSatisfied true → pushGammaConfig skips POST',
        () {
      final satisfied = <String, dynamic>{
        'light': {'gc': {'bri': 1, 'col': 2.8, 'val': 2.8}},
        'if': {'live': {'no-gc': false}},
      };
      expect(gammaConfigSatisfied(satisfied), true);
    });

    test('drifted cfg (gamma off) → false → pushGammaConfig POSTs the standard',
        () {
      final gammaOff = <String, dynamic>{
        'light': {'gc': {'bri': 1, 'col': 1.0, 'val': 2.8}},
        'if': {'live': {'no-gc': false}},
      };
      expect(gammaConfigSatisfied(gammaOff), false);
      // The payload it would POST is the NGL standard (col:2.8) + no-gc:false.
      final p = buildGammaPayload();
      expect(((p['light'] as Map)['gc'] as Map)['col'], 2.8);
      expect(((p['if'] as Map)['live'] as Map)['no-gc'], false);
    });

    test('skipped result is flagged noChange (self-heal stays silent on it)', () {
      expect(WledConfigPushResult.skipped('already correct').noChange, true);
      expect(const WledConfigPushResult(success: true).noChange, false);
      expect(WledConfigPushResult.warning('readback mismatch').noChange, false);
    });
  });

  // ── Orchestration: LAN gating + action invocation + failure inertness ──────
  group('gammaSelfHealProvider', () {
    ProviderContainer makeContainer({
      required WledRepository? repo,
      required GammaSelfHealAction action,
    }) {
      return ProviderContainer(overrides: [
        wledRepositoryProvider.overrideWithValue(repo),
        gammaSelfHealActionProvider.overrideWithValue(action),
      ]);
    }

    test('LAN repo → action invoked once with the device IP', () async {
      final calls = <String>[];
      final container = makeContainer(
        repo: WledService('http://192.168.1.250'),
        action: (ip) async {
          calls.add(ip);
          return WledConfigPushResult.skipped('already correct');
        },
      );
      addTearDown(container.dispose);

      await container.read(gammaSelfHealProvider)();

      expect(calls, ['192.168.1.250']);
    });

    test('non-LAN repo (relay/demo) → action NOT invoked (no POST)', () async {
      final calls = <String>[];
      final container = makeContainer(
        repo: DemoWledRepository(),
        action: (ip) async {
          calls.add(ip);
          return const WledConfigPushResult(success: true);
        },
      );
      addTearDown(container.dispose);

      await container.read(gammaSelfHealProvider)();

      expect(calls, isEmpty);
    });

    test('null repo → action NOT invoked', () async {
      final calls = <String>[];
      final container = makeContainer(
        repo: null,
        action: (ip) async {
          calls.add(ip);
          return const WledConfigPushResult(success: true);
        },
      );
      addTearDown(container.dispose);

      await container.read(gammaSelfHealProvider)();

      expect(calls, isEmpty);
    });

    test('action failure is inert — future completes, no throw', () async {
      final container = makeContainer(
        repo: WledService('http://192.168.1.250'),
        action: (ip) async => throw Exception('device unreachable'),
      );
      addTearDown(container.dispose);

      await expectLater(container.read(gammaSelfHealProvider)(), completes);
    });
  });
}
