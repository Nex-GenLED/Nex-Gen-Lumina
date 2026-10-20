// test/features/wled/cfg_target_fps_wire_test.dart
//
// The two highest-frequency cfg writers, driven for real and observed at the
// wire: the controller-defaults healer (its heals) and the schedule sync's
// cfg push. Companion to cfg_target_fps_test.dart, which pins the normaliser
// over every builder; this file pins that the WRITERS reach the boundary and
// that the body a controller would receive carries hw.led.fps.
//
// The RecordingWledRepository mirrors the write boundary (wireConfigs =
// normalizeWledCfgPayload of what the caller handed over, with the rate the
// transport would have cached). WledService('http://mock') IS the real
// boundary in simulation. Synthetic ids and documentation addresses only.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart'
    show WledConfigPushResult;

import '../../helpers/recording_wled_repository.dart';

final _now = DateTime(2026, 10, 20, 12, 0);

int? _fpsOf(Map<String, dynamic> cfg) =>
    ((cfg['hw'] as Map?)?['led'] as Map?)?['fps'] as int?;

ControllerHealContext _ctx() => ControllerHealContext(
      profileLat: null,
      profileLon: null,
      ianaTimezone: 'America/Chicago',
      resolvePhonePosition: () async => null,
      now: () => _now,
      phoneUtcOffset: const Duration(hours: -5),
    );

/// A device whose clock is fine but whose timezone reads UTC (the tz heal
/// fires) and whose AudioReactive usermod is on (the AR heal fires): two cfg
/// writes in one run, both through applyConfig.
ControllerClockInfo _tzSuspect() => ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 0,
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost,
    );

ControllerDefaultsHealer _healer(RecordingWledRepository repo) =>
    ControllerDefaultsHealer(
      repo: repo,
      isLan: true,
      controllerIp: '192.0.2.50',
      ctx: _ctx(),
      gammaAction: (_) async => const WledConfigPushResult(success: true),
    );

void main() {
  group('healer heals at the wire', () {
    test('tz + audioreactive heals: both bodies carry the default rate',
        () async {
      final repo = RecordingWledRepository(
        clockInfo: _tzSuspect(),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
      );
      final report = await _healer(repo).run();
      expect(report.tzHealed, isTrue);
      expect(report.audioReactiveHealed, isTrue);
      expect(repo.appliedConfigs, hasLength(2));
      // What the healer built: no fps of its own (the boundary adds it).
      for (final raw in repo.appliedConfigs) {
        expect(raw.containsKey('hw'), isFalse);
      }
      // What the controller would receive.
      expect(repo.wireConfigs, hasLength(2));
      for (final wire in repo.wireConfigs) {
        expect(_fpsOf(wire), kDefaultTargetFps);
        expect(((wire['light'] as Map)['gc'] as Map)['col'], 2.8);
      }
    });

    test('the device\'s own rate is kept when the transport has seen it',
        () async {
      final repo = RecordingWledRepository(
        clockInfo: _tzSuspect(),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        simulatedTargetFps: 42,
      );
      await _healer(repo).run();
      expect(repo.wireConfigs, hasLength(2));
      for (final wire in repo.wireConfigs) {
        expect(_fpsOf(wire), 42);
      }
    });

    test('a device in the unlimited mode (0) gets the default', () async {
      final repo = RecordingWledRepository(
        clockInfo: _tzSuspect(),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        simulatedTargetFps: 0,
      );
      await _healer(repo).run();
      for (final wire in repo.wireConfigs) {
        expect(_fpsOf(wire), kDefaultTargetFps);
      }
    });
  });

  group('schedule sync cfg push at the wire', () {
    final ins = ScheduleSyncService.padTimersToMax([
      {'en': 1, 'hour': 19, 'min': 0, 'macro': 10, 'dow': 127},
      {'en': 1, 'hour': 7, 'min': 0, 'macro': 2, 'dow': 127},
    ]);
    final payload = <String, dynamic>{
      'timers': {'ins': ins},
    };

    test('through the real WledService boundary (simulation)', () async {
      final service = WledService('http://mock');
      final outcome = await pushCfgWithVerify(
        repo: service,
        payload: payload,
        ins: ins,
        delay: (_) async {},
      );
      expect(outcome, CfgPushOutcome.confirmed);
      final wire = service.lastSimulatedConfigPayload!;
      expect(_fpsOf(wire), kDefaultTargetFps);
      expect(((wire['timers'] as Map)['ins'] as List).length, 8,
          reason: 'the timer table is untouched');
    });

    test('through the real boundary with the device\'s rate cached', () async {
      final service = WledService('http://mock');
      service.seedTargetFpsForTest(42);
      await pushCfgWithVerify(
        repo: service,
        payload: payload,
        ins: ins,
        delay: (_) async {},
      );
      expect(_fpsOf(service.lastSimulatedConfigPayload!), 42);
    });

    test('through the recording repository mirror', () async {
      final repo = RecordingWledRepository(applyConfigSucceeds: true);
      final outcome = await pushCfgWithVerify(
        repo: repo,
        payload: payload,
        ins: ins,
        delay: (_) async {},
      );
      expect(outcome, CfgPushOutcome.confirmed,
          reason: 'a non-LAN repository trusts the 2xx');
      expect(repo.appliedConfigs.single.containsKey('hw'), isFalse);
      expect(_fpsOf(repo.wireConfigs.single), kDefaultTargetFps);
    });
  });
}
