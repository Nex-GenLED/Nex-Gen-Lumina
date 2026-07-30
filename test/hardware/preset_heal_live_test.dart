// LIVE HARDWARE TEST — requires the bench controller at kBenchIp to be reachable.
//
// NOT part of the normal suite: it performs real network I/O and MUTATES the
// controller's presets. Run explicitly:
//
//   flutter test test/hardware/preset_heal_live_test.dart --dart-define=RUN_HW=1
//
// Without the define it skips, so `flutter test` in CI is unaffected.
//
// It drives the REAL shipping code path — ControllerDefaultsHealer.run() —
// against the REAL device, which is the only thing that proves the fix.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

const String kBenchIp = '192.168.1.150';
const bool kRunHw = bool.fromEnvironment('RUN_HW', defaultValue: false);

ControllerHealContext _ctx() => ControllerHealContext(
      // Rig already has coords/tz/NTP healthy, so these paths are no-ops.
      profileLat: null,
      profileLon: null,
      ianaTimezone: null,
      resolvePhonePosition: () async => null,
      now: DateTime.now,
      phoneUtcOffset: DateTime.now().timeZoneOffset,
    );

Future<Map<int, Map<String, dynamic>>> _presets(WledService svc) =>
    svc.fetchPresets();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  // flutter_test installs an HttpOverrides stub that returns 400 to every
  // request so unit tests cannot hit the network. This file DELIBERATELY does,
  // so drop the override — otherwise every call fails with a bogus 400 that
  // looks like a device fault.
  setUpAll(() {
    HttpOverrides.global = null;
    // WledService.applyJson reaches a SharedPreferences-backed channel cache;
    // flutter_test has no platform plugins, so seed the in-memory mock.
    SharedPreferences.setMockInitialValues(<String, Object>{});
  });

  group('preset master-power heal — LIVE against $kBenchIp', () {
    late WledService svc;

    setUp(() {
      svc = WledService('http://$kBenchIp');
    });

    test('(3a→3b) healer repairs presets 1/3/4/5 to assert root on', () async {
      // ── 3a PRE-STATE ────────────────────────────────────────────────────
      final pre = await _presets(svc);
      expect(pre, isNotEmpty, reason: 'controller unreachable or un-synced');
      final preBroken = <int>[];
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries) {
        final def = pre[e.key];
        if (def == null) continue;
        if (!ScheduleSyncService.isNglOnPresetSatisfied(def, e.value.name)) {
          preBroken.add(e.key);
        }
        // ignore: avoid_print
        print('PRE  preset ${e.key} (${e.value.name}): '
            'root on=${def['on'] ?? 'ABSENT'}');
      }
      // ignore: avoid_print
      print('PRE  broken: $preBroken');

      // ── 3b RUN THE REAL HEALER ──────────────────────────────────────────
      final healer = ControllerDefaultsHealer(
        repo: svc,
        isLan: true,
        controllerIp: kBenchIp,
        ctx: _ctx(),
        // Gamma is exercised by its own path; keep this run surgical.
        gammaAction: (_) async =>
            const WledConfigPushResult(success: true, noChange: true),
      );
      final report = await healer.run();
      // ignore: avoid_print
      print('HEAL report: $report  onPresetsHealed=${report.onPresetsHealed}');

      expect(report.onPresetsHealed.toSet(), preBroken.toSet(),
          reason: 'healer must repair exactly the broken presets');

      // ── POST-STATE ──────────────────────────────────────────────────────
      final post = await _presets(svc);
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries) {
        final def = post[e.key];
        if (def == null) continue;
        // ignore: avoid_print
        print('POST preset ${e.key} (${e.value.name}): '
            'root on=${def['on'] ?? 'ABSENT'} bri=${def['bri'] ?? 'ABSENT'}');
        expect(def['on'], isTrue,
            reason: 'preset ${e.key} must assert ROOT master power');
        expect(def.containsKey('ib'), isFalse,
            reason: 'ib is a request flag and must never be stored');
      }
    }, timeout: const Timeout(Duration(minutes: 2)), skip: !kRunHw);

    test('(3e) second healer run is a NO-OP (idempotent)', () async {
      final healer = ControllerDefaultsHealer(
        repo: svc,
        isLan: true,
        controllerIp: kBenchIp,
        ctx: _ctx(),
        gammaAction: (_) async =>
            const WledConfigPushResult(success: true, noChange: true),
      );
      final report = await healer.run();
      // ignore: avoid_print
      print('2nd run: $report  onPresetsHealed=${report.onPresetsHealed}');
      expect(report.onPresetsHealed, isEmpty,
          reason: 'healthy presets must receive ZERO writes (readback-gated)');
    }, timeout: const Timeout(Duration(minutes: 2)), skip: !kRunHw);

    test('(3c) FUNCTIONAL: master OFF → load preset 1 → strip powers on',
        () async {
      await svc.applyJson({'on': false});
      await Future<void>.delayed(const Duration(milliseconds: 500));
      final dark = await svc.getState();
      expect(dark?['on'], isFalse, reason: 'precondition: strip must be dark');

      await svc.applyJson({'ps': 1});
      await Future<void>.delayed(const Duration(milliseconds: 800));
      final after = await svc.getState();
      // ignore: avoid_print
      print('FUNCTIONAL: master off → ps:1 → on=${after?['on']} '
          'ps=${after?['ps']}');
      expect(after?['on'], isTrue,
          reason: 'preset 1 must assert master power — a timer firing macro:1 '
              'would otherwise fire DARK');

      await svc.applyJson({'on': false});
    }, timeout: const Timeout(Duration(minutes: 2)), skip: !kRunHw);
  });
}
