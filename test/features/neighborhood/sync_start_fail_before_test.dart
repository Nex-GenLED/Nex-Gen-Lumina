// SYNC START WINDOW (2026-11-02). Written first as FAIL-BEFORE tests against
// build-121 (both FAILED there; see the window report), kept as the
// regression lock for the fix on fix/122-sync-start:
//
//   F1. THE FIRST START OF AN APP SESSION MUST FAN OUT when the server flag
//       is on. On build-121 broadcastSync read the flag through a synchronous
//       provider nothing watched (`maybeWhen(orElse: false)`), so the first
//       read of a session created the stream, saw it loading, and answered
//       false: no POST, ever, from a first tap. Now broadcastSync awaits the
//       stream's real value.
//
//   F2. A THROW BETWEEN THE FLAG READ AND THE FIRST REQUEST MUST SURFACE. On
//       build-121 it was swallowed (`state = error; return null`): no record,
//       no message, and `null` was indistinguishable from "flag off". Now it
//       is recorded in the app's error sink and returned with a reason.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/services/error_sink.dart';

/// The command the panel builds for the Popular-strip 'Classic Christmas'
/// pick (fx 28) for a two-member group. Mirrors sync_control_panel.dart.
SyncCommand classicChristmas() => SyncCommand(
      id: '',
      groupId: 'g-sync-window',
      effectId: 28,
      colors: const [0xFF0000, 0x00FF00],
      speed: 128,
      intensity: 128,
      brightness: 200,
      startTimestamp: DateTime.utc(2026, 11, 2, 22, 35, 2),
      memberDelays: const {'u-host': 0, 'u-guest': 9800},
      timingConfig: const SyncTimingConfig(),
      patternName: 'Classic Christmas',
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

/// Stand-in for a throw that happens AFTER the flag read and BEFORE the POST
/// (the builder/normalizer pair is proven not to throw for any look kind in
/// sync_start_look_kinds_matrix_test.dart, so the throw is injected at the
/// next statement in the same try block).
class _ThrowingService extends _CapturingService {
  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) {
    throw StateError('pre-POST failure (stand-in for a throw inside the try block)');
  }
}

/// Records what the app's error sink would have written.
class _SinkRecorder {
  final List<({Object error, String context})> records = [];
  Future<void> call({
    required Object error,
    required StackTrace? stack,
    required String context,
  }) async {
    records.add((error: error, context: context));
  }
}

void main() {
  group('F1 — first Start of a session: the flag stream is still loading at the tap', () {
    test('with config/sync_fanout.enabled == true, the FIRST broadcastSync fans out', () async {
      final svc = _CapturingService();
      // The backing stream emits `true` exactly as Firestore would —
      // asynchronously, after the tap.
      final flag = StreamController<bool>();
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(svc),
        syncFanoutEnabledProvider.overrideWith((ref) => flag.stream),
      ]);
      addTearDown(() {
        c.dispose();
        flag.close();
      });
      scheduleMicrotask(() => flag.add(true));

      final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(classicChristmas());

      expect(svc.fanoutPayloads, hasLength(1),
          reason: 'the server flag is true, so the first Start must POST to applySyncPattern');
      expect(svc.broadcasts, hasLength(1));
      expect(result.fanout?.ok, isTrue);
      expect(result.commandWritten, isTrue);
    });

    test('the flag is read, not cached: a later value is seen by a later Start', () async {
      final svc = _CapturingService();
      final flag = StreamController<bool>.broadcast();
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(svc),
        syncFanoutEnabledProvider.overrideWith((ref) => flag.stream),
      ]);
      addTearDown(() {
        c.dispose();
        flag.close();
      });
      scheduleMicrotask(() => flag.add(false));
      final first = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(classicChristmas());
      expect(first.fanout, isNull, reason: 'off by policy → app-open broadcast only');
      expect(svc.fanoutPayloads, isEmpty);

      flag.add(true);
      await Future<void>.delayed(Duration.zero);
      final second = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(classicChristmas());
      expect(second.fanout?.ok, isTrue);
      expect(svc.fanoutPayloads, hasLength(1));
      expect(svc.broadcasts, hasLength(2));
    });
  });

  group('F2 — a throw between the flag read and the first request', () {
    test('surfaces: non-null failure with a reason, recorded in the error sink, nothing fires', () async {
      final svc = _ThrowingService();
      final sink = _SinkRecorder();
      final c = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(svc),
        syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(true)),
        errorReporterProvider.overrideWithValue(sink.call),
      ]);
      addTearDown(c.dispose);

      final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(classicChristmas());

      expect(result.failure, isNotNull, reason: 'a pre-POST failure must be surfaced to the caller');
      expect(result.failure!.reason, 'client_error');
      expect(result.failure!.error, isA<StateError>());
      expect(result.commandWritten, isFalse);
      expect(svc.fanoutPayloads, isEmpty, reason: 'no POST');
      expect(svc.broadcasts, isEmpty, reason: 'no group command doc either');
      // Recorded where an uncaught error would be recorded.
      expect(sink.records, hasLength(1));
      expect(sink.records.single.context, 'broadcastSync/client_error');
      expect(sink.records.single.error, isA<StateError>());
      // The notifier's error state is still set for anything that watches it.
      final state = c.read(neighborhoodNotifierProvider);
      expect(state.hasError, isTrue);
    });
  });
}
