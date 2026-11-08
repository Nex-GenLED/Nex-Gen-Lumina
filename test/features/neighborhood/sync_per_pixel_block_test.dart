// Roofline slice 1, item 4 — a per-pixel (painted) design is BLOCKED from
// Neighborhood Sync: never fanned out, never broadcast.
//
// Cause (from code): nothing in the Sync path inspected a payload for
// per-pixel data. The picker excludes saved designs by node id and the
// fan-out builder reads colours + an effect, so no path produces one TODAY;
// but a `SyncPatternAssignment.wledPayload` (global or a member override) is
// free-form, `isWellFormedSyncAssignment` only checked colours and the
// effect id, and `broadcastSync` fired whatever it was handed. The server's
// fan-out whitelist drops `i` and keeps `col`, so a closed-app neighbour
// would have shown the design's black base under the design's name.
//
// Now: `isWellFormedSyncAssignment` is false for a per-pixel assignment and
// the panel shows the per-pixel sentence; `broadcastSync` refuses the
// command before the flag read with reason `per_pixel_design` — no fan-out
// call, no broadcast, no error-sink record — and the Start feedback maps
// that reason to the same plain sentence.
//
// This file is the fail-before proof: it uses only API that existed before
// (broadcastSync, SyncStartResult.failure, isWellFormedSyncAssignment,
// syncStartFeedbackFor, literal reason/text), so it compiles and FAILS on
// the unchanged code (the command was broadcast and fanned out).
//
// Fixture: a painted design over one controller's three buses of 100, as a
// member override and as the global pattern's payload; and the plain
// effect command of sync_fanout_payload_key_whitelist_test.dart.

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/features/neighborhood/sync_start_feedback.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_control_panel.dart'
    show isWellFormedSyncAssignment;

final _now = DateTime(2026, 11, 4);

CustomDesign painted() => CustomDesign(
      id: 'd1',
      name: 'Porch stripes',
      ownerId: 'host-uid',
      createdAt: _now,
      updatedAt: _now,
      perPixel: true,
      brightness: 120,
      brightnessStated: true,
      layoutStamp: const DesignLayoutStamp(controllerId: 'ctl-a', busLengths: [100, 100, 100]),
      channels: [
        for (var id = 0; id < 3; id++)
          ChannelDesign(channelId: id, channelName: 'Channel ${id + 1}', ledCount: 100,
              colorGroups: const [
                LedColorGroup(startLed: 0, endLed: 49, color: [255, 0, 0, 0]),
                LedColorGroup(startLed: 50, endLed: 99, color: [0, 0, 255, 0]),
              ]),
      ],
    );

/// The assignment a future "My Designs" picker would hand the panel.
SyncPatternAssignment perPixelAssignment() => SyncPatternAssignment.fromWledPayload(
      name: 'Porch stripes',
      payload: painted().toWledPayload(),
    );

const effectAssignment = SyncPatternAssignment(
  name: 'Crimson chase',
  effectId: 28,
  colors: [0xE31837, 0xFFFFFF],
);

SyncCommand command({Map<String, SyncPatternAssignment>? overrides}) => SyncCommand(
      id: 'c1',
      groupId: 'g',
      effectId: 28,
      colors: const [0xE31837, 0xFFFFFF],
      speed: 128,
      intensity: 128,
      brightness: 200,
      startTimestamp: _now,
      memberDelays: const {'u1': 0, 'u2': 250},
      timingConfig: const SyncTimingConfig(),
      patternName: 'Crimson chase',
      memberPatternOverrides: overrides,
    );

class _CapturingService implements NeighborhoodService {
  final List<Map<String, dynamic>> fanoutPayloads = [];
  final List<SyncCommand> broadcasts = [];

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    fanoutPayloads.add(payload);
    return const FanoutResult(ok: true);
  }

  @override
  Future<void> broadcastSyncCommand(
    SyncCommand command, {
    Duration writeTimeout = kSyncCommandWriteTimeout,
  }) async {
    broadcasts.add(command);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

ProviderContainer _containerWith(_CapturingService service) {
  final c = ProviderContainer(overrides: [
    neighborhoodServiceProvider.overrideWithValue(service),
    syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  test('fixture sanity: the painted assignment carries i; the effect one does not', () {
    final seg = (perPixelAssignment().wledPayload!['seg'] as List).cast<Map>();
    expect(seg.every((s) => s.containsKey('i')), isTrue);
    expect(effectAssignment.wledPayload, isNull);
  });

  group('the panel\'s assignment check', () {
    test('a per-pixel assignment is NOT well-formed for Sync', () {
      expect(isWellFormedSyncAssignment(perPixelAssignment()), isFalse,
          reason: 'was true on the unchanged code (colours + a real fx id)');
    });

    test('an effect assignment still is', () {
      expect(isWellFormedSyncAssignment(effectAssignment), isTrue);
    });
  });

  group('broadcastSync', () {
    test('a per-pixel member override → refused: no fan-out, no broadcast, '
        'reason per_pixel_design', () async {
      final svc = _CapturingService();
      final c = _containerWith(svc);
      final result = await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(overrides: {'u2': perPixelAssignment()}));
      expect(result.commandWritten, isFalse, reason: 'was broadcast on the unchanged code');
      expect(result.failure, isNotNull);
      expect(result.failure!.reason, 'per_pixel_design');
      expect(svc.fanoutPayloads, isEmpty, reason: 'nothing fanned out');
      expect(svc.broadcasts, isEmpty, reason: 'nothing broadcast');
      expect(c.read(neighborhoodNotifierProvider).hasError, isFalse,
          reason: 'a deliberate refusal is not an error state');
    });

    test('the Start feedback turns the reason into the plain sentence', () async {
      final svc = _CapturingService();
      final c = _containerWith(svc);
      final result = await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(overrides: {'u1': perPixelAssignment()}));
      final feedback = syncStartFeedbackFor(result);
      expect(feedback, isNotNull);
      expect(feedback!.isError, isTrue);
      expect(feedback.text, contains('painted design'));
      expect(feedback.text, contains('Neighborhood Sync'));
      expect(feedback.text, contains('Nothing was sent'));
      expect(shouldMarkEngineActive(result), isFalse);
    });

    test('the effect command still fans out and broadcasts exactly as before',
        () async {
      final svc = _CapturingService();
      final c = _containerWith(svc);
      final result = await c
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(command(overrides: {'u2': effectAssignment}));
      expect(result.commandWritten, isTrue);
      expect(result.failure, isNull);
      expect(svc.fanoutPayloads, hasLength(1));
      expect(svc.broadcasts, hasLength(1));
    });
  });
}
