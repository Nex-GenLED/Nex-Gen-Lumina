// +114 item 1b — the healer measures base_ladder_restore_lit on a LAN connect.
//
// Pins the WIRING, not the rules (base_ladder_restore_test.dart owns those):
// the verdict comes from the SAME /presets.json read as R2, is measured against
// the RESOLVED participation, reaches the publisher on the one write, and rides
// the outcome so the on-connect repair acts on exactly what was published.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

final DateTime _now = DateTime(2026, 10, 2, 13, 0);

const WledHardwareConfig _threeBuses = WledHardwareConfig(
  totalLeds: 390,
  buses: [
    WledLedBus(pin: [2], start: 0, len: 162),
    WledLedBus(pin: [14], start: 162, len: 128),
    WledLedBus(pin: [16], start: 290, len: 100),
  ],
);

Map<String, dynamic> _live() => {
      'on': true,
      'bri': 128,
      'seg': [
        for (final id in const [0, 1, 2]) {'id': id, 'on': true},
      ],
    };

/// A healthy ladder as the +114 builders write it.
Map<int, Map<String, dynamic>> _healthyLadder() => {
      for (final e in ScheduleSyncService.kOnPresetSpecs.entries)
        e.key: {
          'n': e.value.name,
          ...ScheduleSyncService.buildNglOnPresetState(e.value.bri, _live()),
        },
      2: {'n': 'NGL Off', ...ScheduleSyncService.buildNglOffPresetState(_live())},
    };

/// The captured-black defect on preset 1: everything "on", nothing lit.
Map<int, Map<String, dynamic>> _blackLadder() => _healthyLadder()
  ..[1] = {
    'n': 'NGL On',
    'on': true,
    'bri': 200,
    'seg': [
      for (final id in const [0, 1, 2])
        {
          'id': id,
          'on': true,
          'fx': 0,
          'col': [
            [0, 0, 0, 0],
            [0, 0, 0, 0],
            [0, 0, 0, 0],
          ],
        },
    ],
  };

class _Lan extends WledService {
  _Lan(this.presets) : super('http://mock');
  final Map<int, Map<String, dynamic>> presets;
  final List<int> saved = [];

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => ControllerClockInfo(
        deviceTime: _now,
        tzIndex: 5,
        tzOffsetSeconds: 0,
        latitude: 39.1,
        longitude: -94.6,
        ntpHost: kHealNtpHost,
        timerRows: const [],
        hardware: _threeBuses,
      );

  @override
  Future<Map<int, Map<String, dynamic>>> fetchPresets() async => presets;

  @override
  Future<Map<String, dynamic>?> getState() async => _live();

  @override
  Future<bool> savePreset({
    required int presetId,
    required Map<String, dynamic> state,
    String? presetName,
  }) async {
    saved.add(presetId);
    return true;
  }
}

class _Pub extends ControllerFactsPublisher {
  final List<LadderRestoreVerdict?> restores = [];
  final List<bool?> asserts = [];

  @override
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
    String? participationDisposition,
    bool? ladderAssertsSegments,
    LadderRestoreVerdict? ladderRestore,
  }) async {
    restores.add(ladderRestore);
    asserts.add(ladderAssertsSegments);
    return true;
  }
}

RooflineSegment _seg(int ch, {required bool primary}) => RooflineSegment(
      id: 'ch$ch',
      name: 'ch$ch',
      pixelCount: 10,
      channelIndex: ch,
      isPrimary: primary,
      points: const <Offset>[],
    );

ControllerDefaultsHealer _healer(
  _Lan svc,
  _Pub pub, {
  Future<List<RooflineSegment>>? roofline,
  bool noInputs = false,
}) =>
    ControllerDefaultsHealer(
      repo: svc,
      isLan: true,
      controllerIp: '192.0.2.10',
      ctx: ControllerHealContext(
        profileLat: 39.1,
        profileLon: -94.6,
        ianaTimezone: 'America/Chicago',
        resolvePhonePosition: () async => null,
        now: () => _now,
        phoneUtcOffset: const Duration(hours: -5),
      ),
      gammaAction: (_) async => WledConfigPushResult.skipped('already correct'),
      controllerId: 'AA00000000A1',
      rooflineSegments: noInputs
          ? null
          : (roofline ?? Future.value(const <RooflineSegment>[])),
      publisher: pub,
    );

void main() {
  setUp(() {
    resetParticipationMemo();
    resetBaseBoundariesMemo();
    resetLadderRestoreMemo();
  });

  test('a healthy ladder publishes restore_lit:true', () async {
    final pub = _Pub();
    final report = await _healer(_Lan(_healthyLadder()), pub).run();
    final outcome = (await report.factsPublish)!;
    expect(pub.restores.single!.restoreLit, isTrue);
    expect(outcome.ladderRestore!.restoreLit, isTrue);
    expect(outcome.participating, [0, 1, 2]);
    expect(outcome.describe(), contains('ladder_restore=lit'));
  });

  test('the captured-black ladder publishes restore_lit:false with the dark '
      'buses — while R2 (segments asserted) still reads TRUE', () async {
    final pub = _Pub();
    final report = await _healer(_Lan(_blackLadder()), pub).run();
    final outcome = (await report.factsPublish)!;
    final v = pub.restores.single!;
    expect(v.restoreLit, isFalse);
    expect(v.darkChannels, [0, 1, 2]);
    expect(v.badPresetIds, [1]);
    expect(pub.asserts.single, isTrue,
        reason: 'R2 cannot see a black ladder — the reason this fact exists');
    expect(identical(outcome.ladderRestore, v), isTrue,
        reason: 'the repair must act on the verdict that was published');
    expect(outcome.describe(), contains('ladder_restore=NOT_LIT(bad [1])'));
  });

  test('measured against the RESOLVED participation, not every bus', () async {
    // Bus 2 traced secondary-only → out of shows; a black bus 2 is not a
    // restore failure.
    final ladder = _healthyLadder();
    ladder[1] = {
      ...ladder[1]!,
      'seg': [
        ...(ladder[1]!['seg'] as List).take(2),
        {
          'id': 2,
          'on': true,
          'fx': 0,
          'col': [
            [0, 0, 0, 0],
          ],
        },
      ],
    };
    final pub = _Pub();
    final report = await _healer(_Lan(ladder), pub,
            roofline: Future.value([
              _seg(0, primary: true),
              _seg(1, primary: true),
              _seg(2, primary: false),
            ]))
        .run();
    await report.factsPublish;
    expect(pub.restores.single!.restoreLit, isTrue);
  });

  test('participation unresolved → restore is UNMEASURED (null), never false',
      () async {
    final pub = _Pub();
    final report =
        await _healer(_Lan(_blackLadder()), pub, noInputs: true).run();
    final outcome = (await report.factsPublish)!;
    expect(pub.restores.single, isNull);
    expect(outcome.ladderRestore, isNull);
    expect(outcome.describe(), contains('ladder_restore=unmeasured'));
  });
}
