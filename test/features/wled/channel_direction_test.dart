// Direction is GEOMETRY, and it takes the PROVISIONING door.
//
// THE TWO FAILURES THIS SITS BETWEEN, and why both directions need pinning:
//
//   1. Before the wire pin covered orientation, `rev` leaked through `applyJson`
//      from paths that had no business stating it — a speed/intensity DRAG
//      re-asserting direction from a panel's local state, and the celebration
//      revert replaying a captured `/json/state`. That silently flipped a
//      reversed channel. (audit/ORIENTATION_ON_THE_WIRE.md)
//
//   2. Widening the pin (a356b5f) then killed the two SegmentedButtons where
//      flipping direction IS the control. They kept calling `applyJson`, whose
//      fence now stripped their only field, so they became silent no-ops.
//
// A fix for either one alone re-creates the other. So both are pinned here:
// the deliberate write must REACH the wire, and the incidental one must NOT.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/wled/channel_direction.dart';
import 'package:nexgen_command/features/wled/geometry_wire_pin.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

/// Records which DOOR each payload went through. The distinction is the whole
/// point — a fake that collapsed both into one "sent" list could not tell a
/// fixed control from a broken one.
class _RecordingRepo implements WledRepository {
  final List<Map<String, dynamic>> viaApplyJson = [];
  final List<Map<String, dynamic>> viaGeometry = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    viaApplyJson.add(payload);
    return true;
  }

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    viaGeometry.add(payload);
    return true;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      super.noSuchMethod(invocation);
}

/// A transport that cannot provision — stands in for off-LAN / demo.
///
/// EXTENDS rather than implements, deliberately: the behaviour under test IS
/// the interface's default `applyGeometryJson => false`, and `implements`
/// would discard that default and route to noSuchMethod instead — testing the
/// fake rather than the contract.
class _NoGeometryRepo extends WledRepository {
  final List<Map<String, dynamic>> viaApplyJson = [];

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async {
    viaApplyJson.add(payload);
    return true;
  }

  // Remaining abstract members: never called by these tests.
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
}

/// Stands in for CloudRelayRepository: geometry is LAN-only and it says so by
/// THROWING — a hard capability boundary, not a transient failure.
class _ThrowingRepo extends WledRepository {
  bool attempted = false;

  @override
  Future<bool> applyGeometryJson(Map<String, dynamic> payload) async {
    attempted = true;
    throw UnsupportedError('geometry writes are LAN-only');
  }

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async => true;
  @override
  Future<Map<String, dynamic>?> getState() async => null;
  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      false;
  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async => false;
  @override
  Future<bool> uploadLedMapJson(String jsonContent) async => false;
  @override
  Future<bool> configureSyncReceiver() async => false;
  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      false;
}

void main() {
  group('buildDirectionPayload', () {
    test('one seg per channel, carrying ONLY id and rev', () {
      final p = buildDirectionPayload(channelIds: const [0, 1], reverse: true);
      expect(p['seg'], hasLength(2));
      expect((p['seg'] as List)[0], equals({'id': 0, 'rev': true}));
      expect((p['seg'] as List)[1], equals({'id': 1, 'rev': true}));
    });

    test('states direction and NOTHING else — no look field can ride along', () {
      // A direction write that could smuggle fx/col would re-create the
      // incidental-clobber class in mirror image.
      final seg = (buildDirectionPayload(
        channelIds: const [1],
        reverse: false,
      )['seg'] as List)
          .single as Map;
      expect(seg.keys.toSet(), equals({'id', 'rev'}));
    });

    test('reverse:false is stated explicitly, not omitted', () {
      // "Omit when false" is how #4 tried to fix the bounds leak and why it
      // only half-worked. Un-reversing a channel is a real instruction.
      final seg = (buildDirectionPayload(
        channelIds: const [0],
        reverse: false,
      )['seg'] as List)
          .single as Map;
      expect(seg['rev'], isFalse);
    });

    test('IS geometry by the pin\'s own definition', () {
      // The load-bearing fact: this payload is exactly what applyJson strips.
      // If this ever stops reporting a violation, the pin has been narrowed
      // and the leak is open again.
      expect(
        findGeometryViolations(
          buildDirectionPayload(channelIds: const [1], reverse: true),
        ),
        hasLength(1),
      );
    });
  });

  group('applyChannelDirection — the deliberate write REACHES the wire', () {
    test('goes through the PROVISIONING door, never applyJson', () async {
      final repo = _RecordingRepo();
      final ok = await applyChannelDirection(
        repo: repo,
        channelIds: const [0, 1],
        reverse: true,
      );

      expect(ok, isTrue);
      expect(repo.viaGeometry, hasLength(1));
      expect(repo.viaApplyJson, isEmpty,
          reason: 'applyJson strips rev — routing here is the no-op bug');
    });

    test('the rev SURVIVES: what the door receives still states direction',
        () async {
      final repo = _RecordingRepo();
      await applyChannelDirection(
        repo: repo,
        channelIds: const [1],
        reverse: true,
      );

      final seg = (repo.viaGeometry.single['seg'] as List).single as Map;
      expect(seg['rev'], isTrue,
          reason: 'the whole point: the user flipped direction and the '
              'device must be told');
    });

    test('no repo → writes nothing, reports false', () async {
      expect(
        await applyChannelDirection(
            repo: null, channelIds: const [0], reverse: true),
        isFalse,
      );
    });

    test('U1 gate: no participating channel → writes nothing, reports false',
        () async {
      final repo = _RecordingRepo();
      expect(
        await applyChannelDirection(
            repo: repo, channelIds: const [], reverse: true),
        isFalse,
      );
      expect(repo.viaGeometry, isEmpty);
      expect(repo.viaApplyJson, isEmpty);
    });

    test('a transport that cannot provision reports FALSE rather than '
        'pretending', () async {
      // The interface default. An off-LAN toggle must be reportable, not
      // silently swallowed — that is the failure mode being fixed.
      final repo = _NoGeometryRepo();
      expect(
        await applyChannelDirection(
            repo: repo, channelIds: const [0], reverse: true),
        isFalse,
      );
      expect(repo.viaApplyJson, isEmpty,
          reason: 'it must not fall back to the stripping door');
    });
  });

  group('transport capability boundaries', () {
    test('a relay-shaped transport THROWS, and the seam reports false rather '
        'than letting it escape a button tap', () async {
      final repo = _ThrowingRepo();
      expect(
        await applyChannelDirection(
            repo: repo, channelIds: const [0], reverse: true),
        isFalse,
      );
      expect(repo.attempted, isTrue,
          reason: 'it must actually try — a seam that pre-emptively refuses '
              'would also refuse transports that CAN provision');
    });
  });

  group('DemoWledRepository — the real one, not a fake', () {
    test('records the geometry write so a demo-mode test can assert the '
        'control actually fired', () async {
      final demo = DemoWledRepository();
      final ok = await applyChannelDirection(
        repo: demo,
        channelIds: const [0, 1],
        reverse: true,
      );

      expect(ok, isTrue, reason: 'demo accepted the write');
      expect(demo.appliedGeometry, hasLength(1));
      final segs = demo.appliedGeometry.single['seg'] as List;
      expect(segs.map((s) => (s as Map)['id']), equals([0, 1]));
      expect(segs.every((s) => (s as Map)['rev'] == true), isTrue);
    });

    test('a demo direction write does NOT go through applyJson', () async {
      // Same distinction as the fake: demo mode must exercise the same door
      // the real transport does, or it validates nothing about the routing.
      final demo = DemoWledRepository();
      await applyChannelDirection(
          repo: demo, channelIds: const [0], reverse: false);
      expect(demo.appliedGeometry, hasLength(1));
      expect((demo.appliedGeometry.single['seg'] as List).single,
          equals({'id': 0, 'rev': false}));
    });
  });

  group('the other direction of the fence — incidental rev must NOT pass', () {
    test('a slider-drag payload carries no rev at all', () {
      // Mirrors what PatternAdjustmentPanel._scheduleDebouncedApply now sends.
      // It used to be {'sx','ix','rev'}, so every drag re-asserted direction.
      final dragPayload = <String, dynamic>{
        'seg': [
          {'sx': 128, 'ix': 200}
        ]
      };
      expect(findGeometryViolations(dragPayload), isEmpty,
          reason: 'a look payload must not state geometry in the first place');
    });

    test('and if one ever regains rev, the wire pin still catches it', () {
      // Defence in depth: the panel could regress, so the fence is re-asserted
      // here rather than assumed.
      final regressed = <String, dynamic>{
        'seg': [
          {'sx': 128, 'ix': 200, 'rev': false}
        ]
      };
      final v = findGeometryViolations(regressed);
      expect(v, hasLength(1));
      expect(v.single.keys, equals(['rev']));

      final stripped = stripGeometry(regressed);
      final seg = (stripped['seg'] as List).single as Map;
      expect(seg.containsKey('rev'), isFalse);
      expect(seg['sx'], 128, reason: 'the LOOK survives; only geometry goes');
      expect(seg['ix'], 200);
    });
  });
}
