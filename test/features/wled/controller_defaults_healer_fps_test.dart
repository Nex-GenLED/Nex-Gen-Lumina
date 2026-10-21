// test/features/wled/controller_defaults_healer_fps_test.dart
//
// Build 120, commit 2 of the frame-rate fix: the healer's once-per-controller
// target-frame-rate write and the AudioReactive seven-day backoff.
//
// - A controller reporting hw.led.fps 0 (the unlimited mode every earlier
//   partial cfg write left behind) with nothing else to heal gets exactly one
//   {"hw":{"led":{"fps":42}}} write, marked per controller; a later connect
//   writes nothing.
// - When another heal writes cfg in the same run, no dedicated write is spent:
//   the body that goes out carries the rate anyway (the wire mirror shows it).
// - An AudioReactive disable whose readback still says enabled is not retried
//   for seven days on that controller; a healthy readback never arms the
//   backoff.
//
// Synthetic ids and documentation addresses only.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/heal_marker_store.dart';
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart'
    show WledConfigPushResult;

import '../../helpers/recording_wled_repository.dart';

const _controller = 'ctl-a';
var _now = DateTime(2026, 10, 20, 12, 0);

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

/// Healthy clock, timezone and coordinates; only [targetFps] varies.
ControllerClockInfo _healthy({int? targetFps}) => ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 5,
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost,
      targetFps: targetFps,
    );

/// Timezone reads UTC → the tz heal writes cfg this run.
ControllerClockInfo _tzSuspect({int? targetFps}) => ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 0,
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost,
      targetFps: targetFps,
    );

ControllerDefaultsHealer _healer(
  RecordingWledRepository repo, {
  HealMarkerStore? markers,
  String? controllerId = _controller,
}) =>
    ControllerDefaultsHealer(
      repo: repo,
      isLan: true,
      controllerIp: '192.0.2.50',
      ctx: _ctx(),
      gammaAction: (_) async =>
          const WledConfigPushResult(success: true, noChange: true),
      controllerId: controllerId,
      markers: markers,
    );

void main() {
  setUp(() => _now = DateTime(2026, 10, 20, 12, 0));

  group('target frame rate heal', () {
    test('fps 0, nothing else to heal → exactly one rate write, marked',
        () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: true);
      final report = await _healer(repo, markers: markers).run();
      expect(report.targetFpsHealed, isTrue);
      expect(repo.appliedConfigs, hasLength(1));
      expect(repo.appliedConfigs.single, {
        'hw': {
          'led': {'fps': kDefaultTargetFps},
        },
      });
      expect(_fpsOf(repo.wireConfigs.single), kDefaultTargetFps);
      expect(markers.fpsDone, {_controller});
      expect(report.rebooted, isFalse);
    });

    test('a later connect on the same controller writes nothing', () async {
      final markers = InMemoryHealMarkerStore();
      final first = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: true);
      await _healer(first, markers: markers).run();
      final again = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: true);
      final report = await _healer(again, markers: markers).run();
      expect(report.targetFpsHealed, isFalse);
      expect(again.appliedConfigs, isEmpty,
          reason: 'once per controller; the next cfg write carries the rate');
      expect(report.log.any((l) => l.contains('already ran')), isTrue);
    });

    test('another heal writing this run → no dedicated write; that body '
        'carries the rate', () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
          clockInfo: _tzSuspect(targetFps: 0),
          applyConfigSucceeds: true,
          simulatedTargetFps: 0);
      final report = await _healer(repo, markers: markers).run();
      expect(report.tzHealed, isTrue);
      expect(report.targetFpsHealed, isFalse);
      expect(repo.appliedConfigs, hasLength(1),
          reason: 'only the tz write');
      expect(repo.appliedConfigs.single.containsKey('if'), isTrue);
      expect(_fpsOf(repo.wireConfigs.single), kDefaultTargetFps,
          reason: 'the boundary turned the cached 0 into the default');
      expect(markers.fpsDone, isEmpty,
          reason: 'no dedicated write, so no marker spent');
    });

    test('a usable device rate (42) is left alone', () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 42), applyConfigSucceeds: true);
      final report = await _healer(repo, markers: markers).run();
      expect(report.targetFpsHealed, isFalse);
      expect(repo.appliedConfigs, isEmpty);
    });

    test('an unreadable rate (null) is left alone', () async {
      final repo = RecordingWledRepository(
          clockInfo: _healthy(targetFps: null), applyConfigSucceeds: true);
      final report =
          await _healer(repo, markers: InMemoryHealMarkerStore()).run();
      expect(report.targetFpsHealed, isFalse);
      expect(repo.appliedConfigs, isEmpty);
    });

    test('no marker store or no controller id → no dedicated write', () async {
      final noStore = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: true);
      await _healer(noStore, markers: null).run();
      expect(noStore.appliedConfigs, isEmpty);

      final noId = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: true);
      await _healer(noId, markers: InMemoryHealMarkerStore(), controllerId: null)
          .run();
      expect(noId.appliedConfigs, isEmpty);
    });

    test('a rejected rate write is not marked, so it is retried next time',
        () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
          clockInfo: _healthy(targetFps: 0), applyConfigSucceeds: false);
      final report = await _healer(repo, markers: markers).run();
      expect(report.targetFpsHealed, isFalse);
      expect(repo.appliedConfigs, hasLength(1), reason: 'attempted');
      expect(markers.fpsDone, isEmpty);
    });
  });

  group('AudioReactive backoff', () {
    test('a readback that still says enabled arms a seven-day backoff',
        () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
        clockInfo: _healthy(targetFps: 42),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        audioReactiveWriteSticks: false,
      );
      final first = await _healer(repo, markers: markers).run();
      expect(first.audioReactiveHealed, isTrue, reason: 'the POST went out');
      expect(first.log.any((l) => l.contains('still enabled')), isTrue);
      expect(markers.arAttempts[_controller], _now);

      // Next connect, two days later: no write.
      _now = _now.add(const Duration(days: 2));
      final again = RecordingWledRepository(
        clockInfo: _healthy(targetFps: 42),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        audioReactiveWriteSticks: false,
      );
      final second = await _healer(again, markers: markers).run();
      expect(second.audioReactiveHealed, isFalse);
      expect(second.audioReactiveBackedOff, isTrue);
      expect(again.appliedConfigs, isEmpty);

      // Eight days after the attempt: tried again.
      _now = _now.add(const Duration(days: 6));
      final later = RecordingWledRepository(
        clockInfo: _healthy(targetFps: 42),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        audioReactiveWriteSticks: false,
      );
      final third = await _healer(later, markers: markers).run();
      expect(third.audioReactiveBackedOff, isFalse);
      expect(later.appliedConfigs, hasLength(1));
    });

    test('a disable that takes never arms the backoff', () async {
      final markers = InMemoryHealMarkerStore();
      final repo = RecordingWledRepository(
        clockInfo: _healthy(targetFps: 42),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
      );
      final report = await _healer(repo, markers: markers).run();
      expect(report.audioReactiveHealed, isTrue);
      expect(markers.arAttempts, isEmpty);
    });

    test('without a marker store the heal behaves as before (no backoff)',
        () async {
      final repo = RecordingWledRepository(
        clockInfo: _healthy(targetFps: 42),
        audioReactiveEnabled: true,
        applyConfigSucceeds: true,
        audioReactiveWriteSticks: false,
      );
      final report = await _healer(repo, markers: null).run();
      expect(report.audioReactiveHealed, isTrue);
      expect(report.audioReactiveBackedOff, isFalse);
    });
  });

  group('ControllerClockInfo.fromMaps', () {
    test('reads hw.led.fps, 0 as 0, absent as null', () {
      expect(
          ControllerClockInfo.fromMaps(null, {
            'hw': {
              'led': {'fps': 0},
            },
          }).targetFps,
          0);
      expect(
          ControllerClockInfo.fromMaps(null, {
            'hw': {
              'led': {'fps': 42},
            },
          }).targetFps,
          42);
      expect(ControllerClockInfo.fromMaps(null, {'if': {}}).targetFps, isNull);
      expect(ControllerClockInfo.fromMaps(null, null).targetFps, isNull);
    });
  });
}
