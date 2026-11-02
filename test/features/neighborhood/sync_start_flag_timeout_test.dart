// SYNC START WINDOW (2026-11-02), item 1: Start waits for the fan-out flag's
// REAL value, bounded by a short timeout, and a flag that cannot be read is a
// VISIBLE failure — nothing fires — rather than a silent app-open-only sync.
//
// "Off by policy" (the doc says enabled:false) is not a failure: the app-open
// broadcast runs and nothing is shown, as before.

import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/services/error_sink.dart';

SyncCommand _cmd() => SyncCommand(
      id: '',
      groupId: 'g-flag',
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
  int fanoutCalls = 0;
  int broadcastCalls = 0;

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    fanoutCalls++;
    return const FanoutResult(ok: true, memberCount: 2, commandCount: 2, skipped: 0);
  }

  @override
  Future<void> broadcastSyncCommand(
    SyncCommand command, {
    Duration writeTimeout = kSyncCommandWriteTimeout,
  }) async {
    broadcastCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _SinkRecorder {
  final List<String> contexts = [];
  Future<void> call({
    required Object error,
    required StackTrace? stack,
    required String context,
  }) async {
    contexts.add(context);
  }
}

void main() {
  test('flag never arrives within the timeout → flag_unavailable, nothing fires, recorded', () async {
    final svc = _CapturingService();
    final sink = _SinkRecorder();
    final never = StreamController<bool>();
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(svc),
      syncFanoutEnabledProvider.overrideWith((ref) => never.stream),
      errorReporterProvider.overrideWithValue(sink.call),
    ]);
    addTearDown(() {
      c.dispose();
      never.close();
    });

    final result = await c
        .read(neighborhoodNotifierProvider.notifier)
        .broadcastSync(_cmd(), flagTimeout: const Duration(milliseconds: 40));

    expect(result.failure?.reason, 'flag_unavailable');
    expect(result.failure?.error, isA<TimeoutException>());
    expect(result.commandWritten, isFalse);
    expect(svc.fanoutCalls, 0);
    expect(svc.broadcastCalls, 0, reason: 'no silent app-open-only sync');
    expect(sink.contexts, ['broadcastSync/flag_unavailable']);
  });

  test('flag stream errors (permission / no app) → flag_unavailable, nothing fires; '
      'the next Start re-reads the flag', () async {
    final svc = _CapturingService();
    final sink = _SinkRecorder();
    var builds = 0;
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(svc),
      // First subscription fails; after invalidation the next one answers true.
      syncFanoutEnabledProvider.overrideWith((ref) {
        builds++;
        return builds == 1
            ? Stream<bool>.error(StateError('permission-denied'))
            : Stream.value(true);
      }),
      errorReporterProvider.overrideWithValue(sink.call),
    ]);
    addTearDown(c.dispose);

    final first = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(_cmd());
    expect(first.failure?.reason, 'flag_unavailable');
    expect(first.failure?.error, isA<StateError>());
    expect(svc.fanoutCalls, 0);
    expect(svc.broadcastCalls, 0);
    expect(sink.contexts, ['broadcastSync/flag_unavailable']);

    final second = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(_cmd());
    expect(second.failure, isNull);
    expect(second.fanout?.ok, isTrue);
    expect(second.commandWritten, isTrue);
    expect(builds, 2, reason: 'the stream was re-subscribed, not cached in error');
  });

  test('flag reads false (off by policy) → no fan-out, broadcast runs, no failure', () async {
    final svc = _CapturingService();
    final sink = _SinkRecorder();
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(svc),
      syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(false)),
      errorReporterProvider.overrideWithValue(sink.call),
    ]);
    addTearDown(c.dispose);

    final result = await c.read(neighborhoodNotifierProvider.notifier).broadcastSync(_cmd());
    expect(result.failure, isNull);
    expect(result.fanout, isNull);
    expect(result.commandWritten, isTrue);
    expect(svc.fanoutCalls, 0);
    expect(svc.broadcastCalls, 1);
    expect(sink.contexts, isEmpty);
  });

  test('flag arrives after the tap but within the timeout → fan-out fires', () async {
    final svc = _CapturingService();
    final late = StreamController<bool>();
    final c = ProviderContainer(overrides: [
      neighborhoodServiceProvider.overrideWithValue(svc),
      syncFanoutEnabledProvider.overrideWith((ref) => late.stream),
    ]);
    addTearDown(() {
      c.dispose();
      late.close();
    });
    Timer(const Duration(milliseconds: 30), () => late.add(true));

    final result = await c
        .read(neighborhoodNotifierProvider.notifier)
        .broadcastSync(_cmd(), flagTimeout: const Duration(seconds: 2));
    expect(result.fanout?.ok, isTrue);
    expect(svc.fanoutCalls, 1);
    expect(svc.broadcastCalls, 1);
  });
}
