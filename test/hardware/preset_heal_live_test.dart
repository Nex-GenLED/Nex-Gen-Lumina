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

    // +114: healer step (e) — the unguarded on-connect psave of presets
    // 1/3/4/5 that (3a)/(3e) used to pin — was REMOVED. Ladder repair is now
    // the guarded one-time BaseLadderRepairRunner (base_ladder_repair.dart),
    // pinned by test/features/wled/base_ladder_repair_test.dart. What a live
    // run can still prove here is the negative: a healer connect leaves every
    // ladder body exactly as it found it.
    test('(3a) +114: the healer itself writes NO ladder preset', () async {
      final pre = await _presets(svc);
      expect(pre, isNotEmpty, reason: 'controller unreachable or un-synced');
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
      print('HEAL report: $report');
      final post = await _presets(svc);
      for (final id in const [1, 2, 3, 4, 5]) {
        expect(post[id], pre[id], reason: 'preset $id must be untouched');
      }
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
