// HEALER PUBLISH — the on-connect leg that makes device-only facts visible to
// a server that cannot read /json/cfg.
//
// Covers what the healer itself is responsible for: dispatching a publish on
// every LAN connect regardless of health, never on relay, from the cfg read it
// already performs, without a heal failure or a reboot skipping it. What gets
// WRITTEN (dedup, null-vs-empty, publish history) is
// controller_facts_writer_test.dart's job.
//
// The session semantics are pinned here deliberately: a second connect in the
// same process must NOT republish, and a relaunch MUST. Both are correct, and
// getting them backwards would produce a bug report against working code.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

// ── Fakes ────────────────────────────────────────────────────────────────────

class _Repo extends WledRepository implements ClockInfoSource {
  _Repo(this.info, {this.applyConfigResult = true});
  final ControllerClockInfo? info;
  final bool applyConfigResult;
  final List<Map<String, dynamic>> configPosts = [];
  final List<Map<String, dynamic>> jsonPosts = [];

  @override
  Future<ControllerClockInfo?> fetchClockInfo() async => info;

  @override
  Future<Map<String, dynamic>?> getState() async =>
      {'on': false, 'ps': kWledNoActivePreset};

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async {
    configPosts.add(cfg);
    return applyConfigResult;
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    jsonPosts.add(payload);
    return true;
  }

  // Unused abstract members.
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      true;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => true;
  @override
  Future<bool> configureSyncReceiver() async => true;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      true;
}

/// A publisher that records what it was handed AND applies the real dedup, so
/// the session-semantics tests exercise the actual memos rather than a stub.
class _RecordingPublisher extends ControllerFactsPublisher {
  final List<({List<int>? participation, List<BaseBoundaryRow>? rows})> calls =
      [];

  /// Publishes that survived dedup — i.e. would have hit Firestore.
  int writes = 0;

  @override
  Future<void> publishDeviceFacts({
    required String? controllerId,
    required List<int>? participation,
    required List<int> deviceChannelIds,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  }) async {
    calls.add((participation: participation, rows: baseBoundaries));
    final id = controllerId;
    if (id == null) return;
    final families = [
      prepareParticipationFacts(
        controllerId: id,
        resolved: participation,
        deviceChannelIds: deviceChannelIds,
        source: source,
      ),
      prepareBaseBoundaryFacts(
        controllerId: id,
        rows: baseBoundaries,
        slotsRead: slotsRead,
        source: source,
      ),
    ];
    final pending = families.where((f) => !f.isEmpty).toList();
    if (pending.isEmpty) return;
    writes++;
    for (final f in pending) {
      f.commit();
    }
  }
}

/// Throws SYNCHRONOUSLY, which is the case an `unawaited` cannot contain on its
/// own — an async throw would just become an unhandled future.
class _ThrowingPublisher extends ControllerFactsPublisher {
  @override
  Future<void> publishDeviceFacts({
    required String? controllerId,
    required List<int>? participation,
    required List<int> deviceChannelIds,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  }) {
    throw StateError('firestore unavailable');
  }
}

// ── Canned cfg ───────────────────────────────────────────────────────────────

final DateTime _now = DateTime(2026, 8, 11, 20, 0, 0);

/// The bench rig's table exactly as `/json/cfg` RETURNS it (captured from
/// `.150`, 2026-08-11): base ON 20:23 macro 10, base OFF 06:22 macro 2, a
/// Wednesday lease macro 40, and the slot-8 solar sentinel — which arrives at
/// INDEX 3 because WLED compacts the readback and drops the disabled stubs.
List<Map<String, dynamic>> _rigTimers() => [
      {'en': 1, 'hour': 20, 'min': 23, 'macro': 10, 'dow': 127},
      {'en': 1, 'hour': 6, 'min': 22, 'macro': 2, 'dow': 127},
      {'en': 1, 'hour': 20, 'min': 40, 'macro': 40, 'dow': 4},
      {'en': 1, 'hour': 255, 'min': 0, 'macro': 2, 'dow': 127},
    ];

/// A perfectly healthy controller — nothing to heal.
ControllerClockInfo _healthy({List<Map<String, dynamic>>? timers}) =>
    ControllerClockInfo(
      deviceTime: _now,
      tzIndex: 5,
      tzOffsetSeconds: 0,
      latitude: 41.88,
      longitude: -87.63,
      ntpHost: kHealNtpHost,
      timerRows: timers ?? _rigTimers(),
    );

/// Clock never synced → the NTP heal fires and, on a dealer-configured
/// controller (turn-on-at-boot OFF, no boot preset), so does a reboot.
ControllerClockInfo _clockUnset() => ControllerClockInfo(
      deviceTime: null,
      turnOnAtBoot: false,
      bootPresetId: kWledNoBootPreset,
      timerRows: _rigTimers(),
    );

ControllerHealContext _ctx() => ControllerHealContext(
      profileLat: 41.88,
      profileLon: -87.63,
      ianaTimezone: 'America/Chicago',
      resolvePhonePosition: () async => null,
      now: () => _now,
      phoneUtcOffset: const Duration(hours: -5),
    );

ControllerDefaultsHealer _healer(
  _Repo repo,
  _RecordingPublisher pub, {
  bool isLan = true,
  String? controllerId = '192_168_1_150',
  List<int>? participating = const [0, 1],
  List<int> deviceChannelIds = const [0, 1],
}) =>
    ControllerDefaultsHealer(
      repo: repo,
      isLan: isLan,
      controllerIp: '192.168.1.150',
      ctx: _ctx(),
      gammaAction: (ip) async => WledConfigPushResult.skipped('already correct'),
      controllerId: controllerId,
      participatingChannels: participating,
      deviceChannelIds: deviceChannelIds,
      publisher: pub,
    );

void main() {
  late _RecordingPublisher pub;

  setUp(() {
    pub = _RecordingPublisher();
    resetParticipationMemo();
    resetBaseBoundariesMemo();
  });

  group('participation publishes without a neighborhood sync', () {
    test('a HEALTHY controller still publishes on connect', () async {
      // The gap this whole change exists to close: publishing used to require
      // an autopilot evaluation or a hand-run sync, so five accounts sat at
      // never_resolved through a 24-hour shadow. Health is irrelevant — the
      // publish is not a heal.
      final report = await _healer(_Repo(_healthy()), pub).run();

      expect(report.anyHealed, isFalse, reason: 'nothing was broken');
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.calls.single.participation, [0, 1]);
      expect(pub.writes, 1);
    });

    test('the resolved set is passed THROUGH, not re-derived', () async {
      await _healer(_Repo(_healthy()), pub,
              participating: const [2], deviceChannelIds: const [0, 1, 2])
          .run();
      expect(pub.calls.single.participation, [2]);
    });

    test('a null resolution reaches the publisher as "no opinion"', () async {
      await _healer(_Repo(_healthy()), pub, participating: null).run();
      expect(pub.calls.single.participation, isNull);
      expect(pub.writes, 1,
          reason: 'base boundaries still publish on their own');
    });
  });

  group('base boundaries come from the cfg read the healer already does', () {
    test('the rig table is published verbatim — four armed rows', () async {
      await _healer(_Repo(_healthy()), pub).run();
      final rows = pub.calls.single.rows!;
      expect(rows.length, 4);

      expect(rows[0].hour, 20);
      expect(rows[0].minute, 23);
      expect(rows[0].macro, 10);
      expect(rows[0].kind, kBoundaryKindClock);

      expect(rows[1].hour, 6);
      expect(rows[1].minute, 22);
      expect(rows[1].macro, 2);

      expect(rows[2].macro, 40);
      expect(rows[2].dow, 4, reason: 'Wednesday, Monday=bit0');
      expect(rows[2].role, 'lease');

      // Compaction: the slot-8 sentinel lands at index 3. Recognised as solar
      // by its 255 marker; direction refused because it is the only one.
      expect(rows[3].index, 3);
      expect(rows[3].isSolar, isTrue);
      expect(rows[3].kind, kBoundaryKindSolarUnknown);
    });

    test('the healer performs NO extra device read for them', () async {
      // The rows ride on ControllerClockInfo, which is the one fetchClockInfo
      // call the healer already makes. If this ever needs its own fetch, the
      // whole cost argument for putting the publish here collapses.
      final repo = _Repo(_healthy());
      await _healer(repo, pub).run();
      expect(repo.configPosts, isEmpty, reason: 'healthy → zero cfg writes');
      expect(pub.calls.single.rows, isNotNull);
    });

    test('an UNREADABLE timer table publishes nothing for that family',
        () async {
      // timerRows null (relay, failed cfg read) must not reach the planner as
      // "this house has no boundaries".
      final info = ControllerClockInfo(
        deviceTime: _now,
        tzIndex: 5,
        latitude: 41.88,
        longitude: -87.63,
        ntpHost: kHealNtpHost,
        timerRows: null,
      );
      await _healer(_Repo(info), pub).run();
      expect(pub.calls.single.rows, isNull);
      expect(pub.writes, 1, reason: 'participation still published');
    });

    test('a readable but EMPTY table publishes [] — a real answer', () async {
      final timers = List.generate(
          10, (_) => {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0});
      await _healer(_Repo(_healthy(timers: timers)), pub).run();
      expect(pub.calls.single.rows, isEmpty);
    });
  });

  group('the publish cannot be skipped by a heal', () {
    test('it survives a heal that FAILS', () async {
      final repo = _Repo(_clockUnset(), applyConfigResult: false);
      final report = await _healer(repo, pub).run();
      expect(report.ntpHostHealed, isFalse, reason: 'the POST was refused');
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.writes, 1);
    });

    test('it survives a run that REBOOTS the controller', () async {
      final repo = _Repo(_clockUnset());
      final report = await _healer(repo, pub).run();
      expect(report.rebooted, isTrue);
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.writes, 1);
    });
  });

  group('gating', () {
    test('a RELAY connect publishes nothing — the inputs do not exist there',
        () async {
      final report =
          await _healer(_Repo(_healthy()), pub, isLan: false).run();
      expect(report.factsPublishDispatched, isFalse);
      expect(pub.calls, isEmpty);
    });

    test('an unreachable controller publishes nothing', () async {
      final report = await _healer(_Repo(null), pub).run();
      expect(report.reachable, isFalse);
      expect(pub.calls, isEmpty);
    });

    test('no controller id → no publish, and the heals still run', () async {
      final repo = _Repo(_clockUnset());
      final report = await _healer(repo, pub, controllerId: null).run();
      expect(pub.calls, isEmpty);
      expect(report.factsPublishDispatched, isFalse);
      expect(report.ntpHostHealed, isTrue);
    });
  });

  group('SESSION SEMANTICS — pinned deliberately', () {
    test('a SECOND connect in the same session does NOT republish', () async {
      await _healer(_Repo(_healthy()), pub).run();
      await _healer(_Repo(_healthy()), pub).run();

      expect(pub.calls.length, 2, reason: 'dispatched both times');
      expect(pub.writes, 1, reason: 'the second was deduped by the memos');
    });

    test('a RELAUNCH does republish — the memo is process-scoped', () async {
      // This is CORRECT BY DESIGN and must not be "fixed": the memo is never
      // read from Firestore, so a cold start republishes once and thereby
      // repairs a write that was lost in a prior session, with no read-back.
      await _healer(_Repo(_healthy()), pub).run();
      expect(pub.writes, 1);

      resetParticipationMemo();
      resetBaseBoundariesMemo(); // ← the relaunch

      await _healer(_Repo(_healthy()), pub).run();
      expect(pub.writes, 2);
    });

    test('a base row that MOVES republishes within the same session', () async {
      await _healer(_Repo(_healthy()), pub).run();
      expect(pub.writes, 1);

      final moved = _rigTimers()..[0]['hour'] = 21;
      await _healer(_Repo(_healthy(timers: moved)), pub).run();
      expect(pub.writes, 2, reason: 'the boundary changed — a real update');
    });

    test('a CHANNEL change republishes within the same session', () async {
      await _healer(_Repo(_healthy()), pub, participating: const [0, 1]).run();
      await _healer(_Repo(_healthy()), pub, participating: const [0]).run();
      expect(pub.writes, 2);
    });
  });

  group('report', () {
    test('records how many armed rows were read, null when unreadable',
        () async {
      var r = await _healer(_Repo(_healthy()), pub).run();
      expect(r.baseBoundaryRowsRead, 4);

      r = await _healer(
        _Repo(ControllerClockInfo(
          deviceTime: _now,
          tzIndex: 5,
          latitude: 41.88,
          longitude: -87.63,
          ntpHost: kHealNtpHost,
        )),
        _RecordingPublisher(),
      ).run();
      expect(r.baseBoundaryRowsRead, isNull);
    });

    test('a publisher that THROWS cannot abort the heals', () async {
      // Fire-and-forget means fire-and-forget. A Firestore problem must never
      // take out the NTP heal running behind it.
      final repo = _Repo(_clockUnset());
      final r = await ControllerDefaultsHealer(
        repo: repo,
        isLan: true,
        controllerIp: '192.168.1.150',
        ctx: _ctx(),
        gammaAction: (ip) async =>
            WledConfigPushResult.skipped('already correct'),
        controllerId: '192_168_1_150',
        participatingChannels: const [0, 1],
        deviceChannelIds: const [0, 1],
        publisher: _ThrowingPublisher(),
      ).run();

      expect(r.ntpHostHealed, isTrue);
      expect(r.rebooted, isTrue);
      expect(r.log.any((l) => l.contains('facts publish dispatch failed')),
          isTrue);
    });

    test('a publish alone does not make a healthy run look healed', () async {
      // anyHealed drives the "did we touch this controller" log line. A publish
      // is a Firestore write, not a device write, and must not read as a heal.
      final r = await _healer(_Repo(_healthy()), pub).run();
      expect(r.anyHealed, isFalse);
      expect(r.toString(), 'facts-publish');
    });
  });
}
