// Roofline slice 1, item 3 — Light Up Now's revert capture is FREEZE-AWARE.
//
// A per-pixel write (a painted design, a Static favourite, a smart preset)
// sets `seg.frz = true` on the controller and nothing unfreezes it. The live
// `/json/state` then reports the segment's BASE look (fx 0, the black base
// the spine wrote under the pixels) with `frz: true` and no pixel data —
// WLED never serialises `i`. Captured as the revert look, that is a black
// solid, and the chokepoint's `frz:false` on the way back out only makes it
// render: the house comes back DARK at final + 30 min, not showing the
// painted design the customer had on (ROOFLINE_CUSTOM_DESIGN_AUDIT_2026-11-03
// §B.4, gate G3; frozen_segment_swallows_writes bench record).
//
// Now a live segment reporting `frz: true` REFUSES the capture with a plain
// message that says what is showing and what to do (apply a pattern or a
// colour first). Nothing is stored and nothing is written — no repair is
// attempted either, because the frame cannot be captured whatever the layout.
//
// This file is the fail-before proof: it uses only the API that existed
// before the change (captureRevertLook, RevertCaptureOutcome.refused,
// RevertCapture.message), so it compiles and FAILS on the unchanged code,
// where every frozen case below was captured with `frz: true` in the stored
// payload.
//
// Fixtures: one controller with three buses of 100 (ids 0, 1, 2; bounds
// 0/100, 100/200, 200/300) and the one-bus, one-segment controller.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/revert_capture.dart';
import 'package:nexgen_command/features/wled/device_channel.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/fake_lan_controller.dart';
import '../../helpers/recording_wled_repository.dart';

const kThreeBuses = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
  DeviceChannel(id: 1, name: 'Channel 2', start: 100, stop: 200, gpioPin: 14),
  DeviceChannel(id: 2, name: 'Channel 3', start: 200, stop: 300, gpioPin: 12),
];
const kOneBus = [
  DeviceChannel(id: 0, name: 'Channel 1', start: 0, stop: 100, gpioPin: 2),
];

Map<String, dynamic> _state(List<Map<String, dynamic>> segs) => {
      'on': true,
      'bri': 200,
      'transition': 7,
      'ps': -1,
      'seg': segs,
    };

/// A bus-aligned segment as the controller reports it after a per-pixel
/// paint: the spine's black base (fx 0, col black) and the freeze flag.
Map<String, dynamic> frozenSeg(int id, int start, int stop) => {
      ...lanSeg(id, start, stop, col: const [0, 0, 0, 0]),
      'frz': true,
    };

List<Map<String, dynamic>> threeLive({Set<int> frozen = const {}}) => [
      for (var id = 0; id < 3; id++)
        frozen.contains(id)
            ? frozenSeg(id, id * 100, id * 100 + 100)
            : lanSeg(id, id * 100, id * 100 + 100),
    ];

/// A non-LAN repository (the relay's shape): canned state, no provisioning.
class _RelayLike extends RecordingWledRepository {
  _RelayLike(this.canned);
  final Map<String, dynamic> canned;
  @override
  Future<Map<String, dynamic>?> getState() async => canned;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('three buses of 100, non-LAN repository', () {
    test('nothing frozen → captured, three segments, no frz:true stored', () async {
      final repo = _RelayLike(_state(threeLive()));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
      final segs = (c.payload['seg'] as List).cast<Map>();
      expect(segs, hasLength(3));
      expect(segs.every((s) => s['frz'] != true), isTrue);
      expect(repo.applied, isEmpty);
    });

    test('one bus frozen (a painted design on channel 2) → REFUSED with the '
        'painted-design message; nothing stored, nothing written', () async {
      final repo = _RelayLike(_state(threeLive(frozen: {1})));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.refused,
          reason: 'was captured with frz:true on the unchanged code (${c.note})');
      expect(c.payload, isEmpty);
      expect(c.message, contains('painted design'));
      expect(c.message, contains('Apply a pattern'));
      expect(c.message, isNot(contains('mid-repair')),
          reason: 'this is not the layout sentence');
      expect(repo.applied, isEmpty);
    });

    test('all three buses frozen (a whole-roofline design) → refused', () async {
      final repo = _RelayLike(_state(threeLive(frozen: {0, 1, 2})));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(c.payload, isEmpty);
    });

    test('a frozen segment that is switched OFF does not count — it is not '
        'showing anything', () async {
      final segs = threeLive(frozen: {2});
      segs[2]['on'] = false;
      final repo = _RelayLike(_state(segs));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
    });

    test('a frozen DELETED slot (stop 0) does not count', () async {
      final segs = threeLive()..add({...frozenSeg(3, 0, 0)});
      final repo = _RelayLike(_state(segs));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
      expect((c.payload['seg'] as List), hasLength(3));
    });

    test('frozen AND collapsed to one segment → refused for the freeze, no '
        'repair attempted (the frame could not be captured anyway)', () async {
      final repo = _RelayLike(_state([frozenSeg(0, 0, 300)]));
      final c = await captureRevertLook(repo: repo, channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(c.message, contains('painted design'));
      expect(repo.applied, isEmpty);
    });

    test('frozen with NO channel model (simulation, cfg never read) → still '
        'refused: the freeze is a content problem, not a layout one', () async {
      final repo = _RelayLike(_state(threeLive(frozen: {0})));
      final c = await captureRevertLook(repo: repo, channels: const []);
      expect(c.outcome, RevertCaptureOutcome.refused,
          reason: 'was capturedUnchecked with frz:true (${c.note})');
    });
  });

  group('one bus, one segment', () {
    test('unfrozen → captured', () async {
      final repo = _RelayLike(_state([lanSeg(0, 0, 100)]));
      final c = await captureRevertLook(repo: repo, channels: kOneBus);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
    });

    test('frozen → refused with the painted-design message', () async {
      final repo = _RelayLike(_state([frozenSeg(0, 0, 100)]));
      final c = await captureRevertLook(repo: repo, channels: kOneBus);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(c.message, contains('painted design'));
    });
  });

  group('LAN service against the stateful fake controller', () {
    late FakeLanController ctl;

    setUp(() async {
      HttpOverrides.global = null;
      SharedPreferences.setMockInitialValues(<String, Object>{});
      resetWledHttpClientsForTest();
      ctl = FakeLanController(segs: threeLive());
      await ctl.start();
    });

    tearDown(() => ctl.stop());

    test('frozen on the LAN → refused with ZERO posts: no unfreeze, no repair',
        () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      ctl.segs = threeLive(frozen: {1});
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(ctl.posted, isEmpty, reason: 'the capture never writes on a refusal');
      expect(c.message, contains('painted design'));
    });

    test('frozen AND collapsed on the LAN → refused for the freeze BEFORE the '
        'repair would run: zero posts', () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      ctl.segs = [frozenSeg(0, 0, 300)];
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.refused, reason: c.note);
      expect(ctl.posted, isEmpty, reason: 'was one repair POST on the unchanged code');
    });

    test('unfrozen on the LAN → captured, zero posts (unchanged)', () async {
      if (ctl.base == null) {
        markTestSkipped('no reachable non-simulation host in this environment');
        return;
      }
      final c = await captureRevertLook(
          repo: WledService(ctl.base!), channels: kThreeBuses);
      expect(c.outcome, RevertCaptureOutcome.captured, reason: c.note);
      expect(ctl.posted, isEmpty);
      expect((c.payload['seg'] as List), hasLength(3));
    });
  });
}
