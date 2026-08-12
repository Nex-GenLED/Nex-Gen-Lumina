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

import 'dart:async';

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
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
    required List<BaseBoundaryRow>? baseBoundaries,
    required int slotsRead,
    required String source,
  }) async {
    calls.add((participation: participation?.resolved, rows: baseBoundaries));
    final id = controllerId;
    if (id == null) return false;
    final families = [
      prepareParticipationFacts(
        controllerId: id,
        resolved: participation?.resolved,
        deviceChannelIds: participation?.deviceChannelIds ?? const <int>[],
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
    if (pending.isEmpty) return false;
    writes++;
    for (final f in pending) {
      f.commit();
    }
    return true;
  }
}

/// Throws SYNCHRONOUSLY, which is the case an `unawaited` cannot contain on its
/// own — an async throw would just become an unhandled future.
class _ThrowingPublisher extends ControllerFactsPublisher {
  @override
  Future<bool> publishDeviceFacts({
    required String? controllerId,
    required ParticipationInput? participation,
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

/// [participating] null models "the caller could not determine the device
/// shape" (the future resolves to null); [inputs] overrides the whole future so
/// a test can supply a slow or throwing one.
ControllerDefaultsHealer _healer(
  _Repo repo,
  _RecordingPublisher pub, {
  bool isLan = true,
  String? controllerId = '192_168_1_150',
  List<int>? participating = const [0, 1],
  List<int> deviceChannelIds = const [0, 1],
  Future<ParticipationInput?>? inputs,
  bool noInputs = false,
}) =>
    ControllerDefaultsHealer(
      repo: repo,
      isLan: isLan,
      controllerIp: '192.168.1.150',
      ctx: _ctx(),
      gammaAction: (ip) async => WledConfigPushResult.skipped('already correct'),
      controllerId: controllerId,
      participationInputs: noInputs
          ? null
          : (inputs ??
              Future<ParticipationInput?>.value(participating == null
                  ? null
                  : ParticipationInput(
                      resolved: participating,
                      deviceChannelIds: deviceChannelIds,
                    ))),
      publisher: pub,
    );

/// Runs the healer and AWAITS the fire-and-forget publish, so assertions are
/// deterministic rather than dependent on event-queue pumping.
Future<({ControllerHealReport report, FactsPublishOutcome? outcome})> _run(
    ControllerDefaultsHealer h) async {
  final report = await h.run();
  final outcome = await report.factsPublish;
  return (report: report, outcome: outcome);
}

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
      final report = (await _run(_healer(_Repo(_healthy()), pub))).report;

      expect(report.anyHealed, isFalse, reason: 'nothing was broken');
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.calls.single.participation, [0, 1]);
      expect(pub.writes, 1);
    });

    test('the resolved set is passed THROUGH, not re-derived', () async {
      await _run(_healer(_Repo(_healthy()), pub,
          participating: const [2], deviceChannelIds: const [0, 1, 2]));
      expect(pub.calls.single.participation, [2]);
    });

    test('a null resolution reaches the publisher as "no opinion"', () async {
      await _run(_healer(_Repo(_healthy()), pub, participating: null));
      expect(pub.calls.single.participation, isNull);
      expect(pub.writes, 1,
          reason: 'base boundaries still publish on their own');
    });
  });

  group('base boundaries come from the cfg read the healer already does', () {
    test('the rig table is published verbatim — four armed rows', () async {
      await _run(_healer(_Repo(_healthy()), pub));
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
      await _run(_healer(repo, pub));
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
      await _run(_healer(_Repo(info), pub));
      expect(pub.calls.single.rows, isNull);
      expect(pub.writes, 1, reason: 'participation still published');
    });

    test('a readable but EMPTY table publishes [] — a real answer', () async {
      final timers = List.generate(
          10, (_) => {'en': 0, 'hour': 0, 'min': 0, 'macro': 0, 'dow': 0});
      await _run(_healer(_Repo(_healthy(timers: timers)), pub));
      expect(pub.calls.single.rows, isEmpty);
    });
  });

  group('the publish cannot be skipped by a heal', () {
    test('it survives a heal that FAILS', () async {
      final repo = _Repo(_clockUnset(), applyConfigResult: false);
      final report = (await _run(_healer(repo, pub))).report;
      expect(report.ntpHostHealed, isFalse, reason: 'the POST was refused');
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.writes, 1);
    });

    test('it survives a run that REBOOTS the controller', () async {
      final repo = _Repo(_clockUnset());
      final report = (await _run(_healer(repo, pub))).report;
      expect(report.rebooted, isTrue);
      expect(report.factsPublishDispatched, isTrue);
      expect(pub.writes, 1);
    });
  });

  group('gating', () {
    test('a RELAY connect publishes nothing — the inputs do not exist there',
        () async {
      final report =
          (await _run(_healer(_Repo(_healthy()), pub, isLan: false))).report;
      expect(report.factsPublishDispatched, isFalse);
      expect(pub.calls, isEmpty);
    });

    test('an unreachable controller publishes nothing', () async {
      final report = (await _run(_healer(_Repo(null), pub))).report;
      expect(report.reachable, isFalse);
      expect(pub.calls, isEmpty);
    });

    test('no controller id → no publish, and the heals still run', () async {
      final repo = _Repo(_clockUnset());
      final report = (await _run(_healer(repo, pub, controllerId: null))).report;
      expect(pub.calls, isEmpty);
      expect(report.factsPublishDispatched, isFalse);
      expect(report.ntpHostHealed, isTrue);
    });
  });

  group('SESSION SEMANTICS — pinned deliberately', () {
    test('a SECOND connect in the same session does NOT republish', () async {
      await _run(_healer(_Repo(_healthy()), pub));
      await _run(_healer(_Repo(_healthy()), pub));

      expect(pub.calls.length, 2, reason: 'dispatched both times');
      expect(pub.writes, 1, reason: 'the second was deduped by the memos');
    });

    test('a RELAUNCH does republish — the memo is process-scoped', () async {
      // This is CORRECT BY DESIGN and must not be "fixed": the memo is never
      // read from Firestore, so a cold start republishes once and thereby
      // repairs a write that was lost in a prior session, with no read-back.
      await _run(_healer(_Repo(_healthy()), pub));
      expect(pub.writes, 1);

      resetParticipationMemo();
      resetBaseBoundariesMemo(); // ← the relaunch

      await _run(_healer(_Repo(_healthy()), pub));
      expect(pub.writes, 2);
    });

    test('a base row that MOVES republishes within the same session', () async {
      await _run(_healer(_Repo(_healthy()), pub));
      expect(pub.writes, 1);

      final moved = _rigTimers()..[0]['hour'] = 21;
      await _run(_healer(_Repo(_healthy(timers: moved)), pub));
      expect(pub.writes, 2, reason: 'the boundary changed — a real update');
    });

    test('a CHANNEL change republishes within the same session', () async {
      await _run(_healer(_Repo(_healthy()), pub, participating: const [0, 1]));
      await _run(_healer(_Repo(_healthy()), pub, participating: const [0]));
      expect(pub.writes, 2);
    });
  });

  group('THE ORDERING REGRESSION — inputs arrive late, not at t=0', () {
    test('a SLOW bus list still publishes participation', () async {
      // The bug this fix exists for. deviceHardwareConfigProvider is a
      // FutureProvider doing its own /json/cfg GET, so at connect time it has
      // NOT resolved. Sampling it (the old snapshot param) meant participation
      // was refused on EVERY connect and the feature never worked in
      // production — base boundaries published, participation never did.
      final slow = Future<ParticipationInput?>.delayed(
        const Duration(milliseconds: 120),
        () => const ParticipationInput(resolved: [0, 1], deviceChannelIds: [0, 1]),
      );
      final res = await _run(_healer(_Repo(_healthy()), pub, inputs: slow));
      expect(res.outcome!.participation, ParticipationDisposition.offered);
      expect(pub.calls.single.participation, [0, 1]);
      expect(pub.writes, 1);
    });

    test('inputs that resolve NULL are refused as shape-unknown, and say so',
        () async {
      // An empty bus list must never publish [] — the server reads that as a
      // usable "light nothing".
      final res = await _run(_healer(_Repo(_healthy()), pub, participating: null));
      expect(res.outcome!.participation, ParticipationDisposition.shapeUnknown);
      expect(res.outcome!.describe(), contains('shape unknown'));
      expect(pub.calls.single.participation, isNull);
      expect(pub.writes, 1, reason: 'base boundaries still publish alone');
    });

    test('inputs that never resolve TIME OUT, and base boundaries publish '
        'alone', () async {
      final never = Completer<ParticipationInput?>().future;
      final res = await _run(_healer(_Repo(_healthy()), pub, inputs: never));
      expect(res.outcome!.participation,
          ParticipationDisposition.inputsTimedOut);
      expect(res.outcome!.baseBoundariesOffered, isTrue);
      expect(res.outcome!.wrote, isTrue,
          reason: 'the timeout must not cost base boundaries their publish');
      expect(pub.calls.single.participation, isNull);
    }, timeout: const Timeout(Duration(seconds: 60)));

    test('inputs that THROW are recorded, not swallowed', () async {
      // Delayed rather than pre-failed: a Future.error with no listener yet is
      // reported as an UNHANDLED async error by the test zone before the healer
      // can attach. Production closes that same window with `.ignore()` on the
      // provider side — see resolveParticipationInputs' call site.
      final boom = Future<ParticipationInput?>.delayed(
          const Duration(milliseconds: 30),
          () => throw StateError('cfg blew up'));
      final res = await _run(_healer(_Repo(_healthy()), pub, inputs: boom));
      expect(res.outcome!.participation, ParticipationDisposition.inputsFailed);
      expect(res.outcome!.wrote, isTrue, reason: 'base boundaries unaffected');
    });

    test('no inputs supplied at all is its own, named outcome', () async {
      final res = await _run(_healer(_Repo(_healthy()), pub, noInputs: true));
      expect(res.outcome!.participation, ParticipationDisposition.inputsAbsent);
    });

    test('THE SILENCE IS THE DEFECT — every disposition describes itself', () {
      // A skipped publish used to leave no trace anywhere, which is why the
      // bench caught this and no log line did. Every outcome must be legible.
      for (final d in ParticipationDisposition.values) {
        final line = FactsPublishOutcome(
          participation: d,
          baseBoundariesOffered: false,
          wrote: false,
        ).describe();
        expect(line, contains('participation='));
        expect(line, contains('wrote=false'));
        if (d != ParticipationDisposition.offered) {
          expect(line, contains('SKIPPED'),
              reason: '$d must announce that it did nothing');
        }
      }
    });

    test('the bound exceeds the WledService HTTP timeout it waits on', () {
      // Below 15s this would abandon a /json/cfg GET that is still legitimately
      // in flight — the same too-aggressive-timeout mistake one layer up.
      expect(kParticipationInputTimeout.inSeconds, greaterThan(15));
      expect(kParticipationInputTimeout.inSeconds, lessThanOrEqualTo(30));
    });
  });

  group('report', () {
    test('records how many armed rows were read, null when unreadable',
        () async {
      var r = (await _run(_healer(_Repo(_healthy()), pub))).report;
      expect(r.baseBoundaryRowsRead, 4);

      r = (await _run(_healer(
        _Repo(ControllerClockInfo(
          deviceTime: _now,
          tzIndex: 5,
          latitude: 41.88,
          longitude: -87.63,
          ntpHost: kHealNtpHost,
        )),
        _RecordingPublisher(),
      ))).report;
      expect(r.baseBoundaryRowsRead, isNull);
    });

    test('a publisher that THROWS cannot abort the heals', () async {
      // Fire-and-forget means fire-and-forget. A Firestore problem must never
      // take out the NTP heal running behind it, and must not escape as an
      // unhandled async error either.
      final repo = _Repo(_clockUnset());
      final healer = ControllerDefaultsHealer(
        repo: repo,
        isLan: true,
        controllerIp: '192.168.1.150',
        ctx: _ctx(),
        gammaAction: (ip) async =>
            WledConfigPushResult.skipped('already correct'),
        controllerId: '192_168_1_150',
        participationInputs: Future<ParticipationInput?>.value(
          const ParticipationInput(resolved: [0, 1], deviceChannelIds: [0, 1]),
        ),
        publisher: _ThrowingPublisher(),
      );
      final r = await healer.run();
      final outcome = await r.factsPublish;

      expect(r.ntpHostHealed, isTrue);
      expect(r.rebooted, isTrue);
      expect(outcome!.wrote, isFalse);
      expect(outcome.participation, ParticipationDisposition.offered,
          reason: 'the inputs were fine — it was the WRITE that failed');
    });

    test('a publish alone does not make a healthy run look healed', () async {
      // anyHealed drives the "did we touch this controller" log line. A publish
      // is a Firestore write, not a device write, and must not read as a heal.
      final r = (await _run(_healer(_Repo(_healthy()), pub))).report;
      expect(r.anyHealed, isFalse);
      expect(r.toString(), 'facts-publish');
    });
  });
}
