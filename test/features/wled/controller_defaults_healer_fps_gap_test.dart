// +122 item 3 — the frame-rate heal gap.
//
// Build 120 made the healer's target-frame-rate write ONCE per controller: a
// marker set after the write blocked every later run. The marker was meant to
// keep a healthy connect write-free, but it also blocked the heal after a
// LATER cfg write that carried no rate (an older build, the controller's own
// UI, a dealer's tool) had put the device back into the unlimited mode. The
// device read fps 0 again; the healer logged "one-time heal already ran" and
// wrote nothing, forever.
//
// Now the marker means "written, not yet seen usable". A usable rate — on a
// later connect, or on the same run's read-back — SPENDS it, so the next
// unusable reading is healed again. A device that never takes the write keeps
// its marker and is never written twice, exactly as before.
//
// The rate heal does not touch segments, so the two layout fixtures below
// only prove it stays indifferent to them. Synthetic ids and documentation
// addresses only.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/heal_marker_store.dart';
import 'package:nexgen_command/features/wled/wled_cfg_gamma.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart'
    show WledConfigPushResult;

import '../../helpers/recording_wled_repository.dart';

const _controller = 'ctl-a';
final _now = DateTime(2026, 11, 2, 12, 0);

ControllerHealContext _ctx() => ControllerHealContext(
      profileLat: null,
      profileLon: null,
      ianaTimezone: 'America/Chicago',
      resolvePhonePosition: () async => null,
      now: () => _now,
      phoneUtcOffset: const Duration(hours: -6),
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

Map<String, dynamic> _seg(int id, int start, int stop) => {
      'id': id,
      'start': start,
      'stop': stop,
      'len': stop - start,
      'on': true,
      'bri': 255,
      'fx': 0,
      'col': [
        [255, 160, 0, 0]
      ],
    };

final _twoChannel = <String, dynamic>{
  'on': true,
  'bri': 200,
  'seg': [_seg(0, 0, 90), _seg(1, 90, 180)],
};
final _oneSegmentAfterRestart = <String, dynamic>{
  'on': true,
  'bri': 128,
  'ps': -1,
  'seg': [_seg(0, 0, 180)],
};

ControllerDefaultsHealer _healer(
  RecordingWledRepository repo, {
  required HealMarkerStore markers,
}) =>
    ControllerDefaultsHealer(
      repo: repo,
      isLan: true,
      controllerIp: '192.0.2.50',
      ctx: _ctx(),
      gammaAction: (_) async =>
          const WledConfigPushResult(success: true, noChange: true),
      controllerId: _controller,
      markers: markers,
    );

/// A device that HONOURS the rate write: its cfg reads 42 after the POST, so
/// the same run's read-back sees the rate land.
class _HonouringRepo extends RecordingWledRepository {
  _HonouringRepo({required super.clockInfo, required super.state})
      : super(applyConfigSucceeds: true);

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    final ok = await super.applyConfig(cfg);
    final fps = ((cfg['hw'] as Map?)?['led'] as Map?)?['fps'];
    if (ok && fps is int) clockInfo = _healthy(targetFps: fps);
    return ok;
  }
}

void main() {
  for (final (label, state) in [
    ('two-channel layout', _twoChannel),
    ('one segment after a restart', _oneSegmentAfterRestart),
  ]) {
    group('[$label] the marker re-arms', () {
      test(
          'a usable rate on a later connect spends the marker, so a later '
          'unusable rate is healed again', () async {
        final markers = InMemoryHealMarkerStore();

        // A — unlimited mode, nothing else to heal: the one rate write, marked.
        // This fake keeps reading 0 after the write, so the same run's
        // read-back cannot confirm it and the marker stays (no hammering).
        final a = RecordingWledRepository(
            clockInfo: _healthy(targetFps: 0),
            applyConfigSucceeds: true,
            state: state);
        final ra = await _healer(a, markers: markers).run();
        expect(ra.targetFpsHealed, isTrue);
        expect(a.appliedConfigs, hasLength(1));
        expect(markers.fpsDone, {_controller});

        // B — the next connect reads a usable rate: nothing written, marker
        // spent.
        final b = RecordingWledRepository(
            clockInfo: _healthy(targetFps: 42),
            applyConfigSucceeds: true,
            state: state);
        final rb = await _healer(b, markers: markers).run();
        expect(rb.targetFpsHealed, isFalse);
        expect(b.appliedConfigs, isEmpty, reason: 'healthy connect stays write-free');
        expect(markers.fpsDone, isEmpty,
            reason: 'seen usable: the one-time marker is spent');
        expect(rb.log.any((l) => l.contains('marker cleared')), isTrue,
            reason: rb.log.join('; '));

        // C — a later cfg write without the rate put the device back to 0:
        // healed again. Before +122 this run logged "already ran" and wrote
        // nothing.
        final c = RecordingWledRepository(
            clockInfo: _healthy(targetFps: 0),
            applyConfigSucceeds: true,
            state: state);
        final rc = await _healer(c, markers: markers).run();
        expect(rc.targetFpsHealed, isTrue, reason: rc.log.join('; '));
        expect(c.appliedConfigs.single, {
          'hw': {
            'led': {'fps': kDefaultTargetFps},
          },
        });
        expect(markers.fpsDone, {_controller});
      });

      test('a write the device honours is confirmed by the same run\'s '
          'read-back, and the marker is spent right there', () async {
        final markers = InMemoryHealMarkerStore();
        final repo =
            _HonouringRepo(clockInfo: _healthy(targetFps: 0), state: state);
        final report = await _healer(repo, markers: markers).run();
        expect(report.targetFpsHealed, isTrue);
        expect(repo.appliedConfigs, hasLength(1));
        expect(markers.fpsDone, isEmpty,
            reason: 'read-back saw 42: nothing left for the marker to guard');
        expect(report.log.any((l) => l.contains('marker cleared')), isTrue,
            reason: report.log.join('; '));
      });

      test('a device that never takes the write keeps its marker: the next '
          'connect writes nothing (no hammering, as before)', () async {
        final markers = InMemoryHealMarkerStore();
        final first = RecordingWledRepository(
            clockInfo: _healthy(targetFps: 0),
            applyConfigSucceeds: true,
            state: state);
        await _healer(first, markers: markers).run();
        final again = RecordingWledRepository(
            clockInfo: _healthy(targetFps: 0),
            applyConfigSucceeds: true,
            state: state);
        final report = await _healer(again, markers: markers).run();
        expect(report.targetFpsHealed, isFalse);
        expect(again.appliedConfigs, isEmpty);
        expect(report.log.any((l) => l.contains('already ran')), isTrue);
        expect(markers.fpsDone, {_controller});
      });
    });
  }

  test('the marker store can forget a controller', () async {
    final m = InMemoryHealMarkerStore();
    await m.markTargetFpsHealDone('x');
    expect(await m.targetFpsHealDone('x'), isTrue);
    await m.clearTargetFpsHealDone('x');
    expect(await m.targetFpsHealDone('x'), isFalse);
    await m.clearTargetFpsHealDone('never-marked'); // harmless
  });
}
