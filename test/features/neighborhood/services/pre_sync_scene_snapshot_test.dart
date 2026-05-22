// Tests for [capturePreSyncScene] — the pre-sync snapshot capture
// function that mirrors Game Day's revertWledPayload pattern.
//
// Convergence-Phase-1B groundwork — the capture function is dormant in
// production (not yet wired into sync start). These tests lock the
// contract so Phase 2 can wire it in safely:
//   • happy path: getState() success → PreSyncScene populated
//   • offline path: getState() returns null → null snapshot
//   • empty path: getState() returns {} → null snapshot
//   • error path: getState() throws → null snapshot (no propagation)
//   • the activeLabel arg is faithfully passed through
//   • the wledPayload field is a defensive copy (mutating the source
//     after capture does not affect the snapshot)

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/pre_sync_scene_snapshot.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

void main() {
  group('capturePreSyncScene', () {
    test('happy path: getState() returns a payload → snapshot is populated',
        () async {
      final repo = _FakeWledRepository(stateToReturn: {
        'on': true,
        'bri': 200,
        'seg': [
          {'fx': 5}
        ],
      });

      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: 'Manual Warm White',
        now: DateTime.utc(2026, 5, 22, 18, 30),
      );

      expect(scene, isNotNull);
      expect(scene!.groupId, 'group_1');
      expect(scene.wledPayload['on'], isTrue);
      expect(scene.wledPayload['bri'], 200);
      expect(scene.activeLabel, 'Manual Warm White');
      expect(scene.capturedAt, DateTime.utc(2026, 5, 22, 18, 30));
    });

    test('null state from repo → null snapshot (controller offline)',
        () async {
      final repo = _FakeWledRepository(stateToReturn: null);
      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: null,
      );
      expect(scene, isNull);
    });

    test('empty state map from repo → null snapshot (degenerate response)',
        () async {
      final repo = _FakeWledRepository(stateToReturn: <String, dynamic>{});
      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: null,
      );
      expect(scene, isNull);
    });

    test('getState() throws → null snapshot (errors do not propagate)',
        () async {
      final repo = _FakeWledRepository(throwOnGetState: true);
      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: 'X',
      );
      expect(scene, isNull);
    });

    test('activeLabel = null is preserved (not coerced to empty string)',
        () async {
      final repo = _FakeWledRepository(stateToReturn: {'on': true});
      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: null,
      );
      expect(scene, isNotNull);
      expect(scene!.activeLabel, isNull);
    });

    test('wledPayload is a defensive copy — mutating source after capture '
        'does not change the snapshot', () async {
      final source = <String, dynamic>{
        'on': true,
        'bri': 200,
      };
      final repo = _FakeWledRepository(stateToReturn: source);

      final scene = await capturePreSyncScene(
        groupId: 'group_1',
        repo: repo,
        activeLabel: null,
      );

      // Mutate the source after capture.
      source['bri'] = 50;
      source['injected'] = 'tampered';

      expect(scene!.wledPayload['bri'], 200);
      expect(scene.wledPayload.containsKey('injected'), isFalse);
    });

    test('groupId is propagated verbatim (used by Phase 2 staleness check)',
        () async {
      final repo = _FakeWledRepository(stateToReturn: {'on': true});
      final scene = await capturePreSyncScene(
        groupId: 'a-very-specific-group-id',
        repo: repo,
        activeLabel: null,
      );
      expect(scene!.groupId, 'a-very-specific-group-id');
    });

    test('capturedAt defaults to a recent DateTime.now() when not supplied',
        () async {
      final before = DateTime.now();
      final repo = _FakeWledRepository(stateToReturn: {'on': true});
      final scene = await capturePreSyncScene(
        groupId: 'g',
        repo: repo,
        activeLabel: null,
      );
      final after = DateTime.now();
      expect(scene, isNotNull);
      expect(
        scene!.capturedAt.isAfter(before.subtract(const Duration(seconds: 1))),
        isTrue,
      );
      expect(
        scene.capturedAt.isBefore(after.add(const Duration(seconds: 1))),
        isTrue,
      );
    });
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Minimal fake — covers only the getState() surface the capture needs.
// ─────────────────────────────────────────────────────────────────────────────

class _FakeWledRepository extends WledRepository {
  _FakeWledRepository({this.stateToReturn, this.throwOnGetState = false});

  final Map<String, dynamic>? stateToReturn;
  final bool throwOnGetState;

  @override
  Future<Map<String, dynamic>?> getState() async {
    if (throwOnGetState) throw StateError('simulated fetch failure');
    return stateToReturn;
  }

  @override
  Future<bool> setState({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
  }) async =>
      throw UnimplementedError('Not exercised by these tests');

  @override
  Future<bool> applyJson(Map<String, dynamic> payload) async =>
      throw UnimplementedError('Not exercised by these tests');

  @override
  Future<bool> applyConfig(Map<String, dynamic> cfg) async =>
      throw UnimplementedError('Not exercised by these tests');

  @override
  Future<bool> uploadLedMapJson(String jsonContent) async =>
      throw UnimplementedError('Not exercised by these tests');

  @override
  Future<bool> configureSyncReceiver() async =>
      throw UnimplementedError('Not exercised by these tests');

  @override
  Future<bool> configureSyncSender({
    List<String> targets = const [],
    int ddpPort = 4048,
  }) async =>
      throw UnimplementedError('Not exercised by these tests');
}
