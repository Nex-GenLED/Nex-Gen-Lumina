// SYNC-3 TASK B — coverage for the flag-gated crew-fanout trigger.
//
// The fanout chain is wired end-to-end via NeighborhoodNotifier.broadcastSync
// and gated by the `config/sync_fanout` feature flag (syncFanoutEnabledProvider).
// Nothing in test/ locked that gate down. These tests pin the exact contract so a
// future refactor can't silently change activation behavior:
//
//   • flag OFF  → fanoutAdHocSync is NOT called; only broadcastSyncCommand fires
//                 (byte-identical to the pre-fanout world).
//   • flag ON   → fanoutAdHocSync fires FIRST, then broadcastSyncCommand.
//   • flag ON + rate-limited (server reject) → broadcastSyncCommand is SKIPPED
//                 entirely and the rate-limit result is returned gracefully
//                 (no throw, notifier settles to data — anti-strobe policy).
//
// Sync Start window (2026-11-02): broadcastSync now AWAITS the flag stream's
// real value, so the tests override the STREAM provider (the synchronous
// `maybeWhen(orElse: false)` provider that made the first Start of a session
// read `false` is gone), and the result is a SyncStartResult.
//
// The Cloud Function boundary is mocked by overriding fanoutAdHocSync on a
// NeighborhoodService subclass (fake_cloud_firestore + hand-rolled auth stub,
// matching neighborhood_service_two_tier_stop_test.dart) — no network, no emulator.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';

/// NeighborhoodService fake that records the two delivery calls and lets a test
/// configure what the server-side fanout returns (ok / rate-limited). This is
/// the mocked CF boundary — fanoutAdHocSync would otherwise POST to the
/// applySyncPattern function.
class _RecordingService extends NeighborhoodService {
  _RecordingService({
    required super.firestore,
    required super.auth,
    this.fanoutResult = const FanoutResult(ok: true),
  });

  final FanoutResult fanoutResult;
  int fanoutCalls = 0;
  int broadcastCalls = 0;

  /// Interleaved call log so a test can assert fanout fires BEFORE broadcast.
  final List<String> callOrder = [];

  @override
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    fanoutCalls++;
    callOrder.add('fanout');
    return fanoutResult;
  }

  @override
  Future<void> broadcastSyncCommand(
    SyncCommand command, {
    Duration writeTimeout = kSyncCommandWriteTimeout,
  }) async {
    broadcastCalls++;
    callOrder.add('broadcast');
  }
}

SyncCommand _cmd() => SyncCommand(
      id: 'c1',
      groupId: 'g1',
      effectId: 88,
      colors: const [0xFF0000, 0x00FF00],
      speed: 128,
      intensity: 128,
      brightness: 200,
      startTimestamp: DateTime(2024, 1, 1),
      memberDelays: const {'u1': 0},
      timingConfig: const SyncTimingConfig(),
    );

_RecordingService _makeService({FanoutResult? fanoutResult}) => _RecordingService(
      firestore: FakeFirebaseFirestore(),
      auth: _StubAuth(_StubUser('u1')),
      fanoutResult: fanoutResult ?? const FanoutResult(ok: true),
    );

ProviderContainer _container(_RecordingService service, {required bool flag}) {
  final c = ProviderContainer(overrides: [
    neighborhoodServiceProvider.overrideWithValue(service),
    syncFanoutEnabledProvider.overrideWith((ref) => Stream.value(flag)),
  ]);
  addTearDown(c.dispose);
  return c;
}

void main() {
  group('broadcastSync — flag gate', () {
    test('flag OFF → fanoutAdHocSync NOT called, only broadcastSyncCommand '
        '(byte-identical to today)', () async {
      final service = _makeService();
      final container = _container(service, flag: false);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 0, reason: 'flag off ⇒ no server fanout');
      expect(service.broadcastCalls, 1);
      expect(service.callOrder, ['broadcast']);
      // Flag off: no fan-out outcome to surface, the command was written.
      expect(result.fanout, isNull);
      expect(result.commandWritten, isTrue);
      expect(result.failure, isNull);
    });

    test('flag ON → fanout fires FIRST, then broadcast', () async {
      final service = _makeService(fanoutResult: const FanoutResult(ok: true));
      final container = _container(service, flag: true);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 1);
      expect(service.broadcastCalls, 1);
      // Ordering matters: fanout enforces the server rate limit before the
      // app-open broadcast goes out.
      expect(service.callOrder, ['fanout', 'broadcast']);
      expect(result.fanout?.ok, isTrue);
      expect(result.rateLimited, isFalse);
      expect(result.commandWritten, isTrue);
    });

    test('flag ON + rate-limited (server reject) → broadcast SKIPPED, '
        'result returned gracefully (no throw)', () async {
      final service = _makeService(
        fanoutResult: const FanoutResult(rateLimited: true, retryAfterMs: 17000),
      );
      final container = _container(service, flag: true);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 1);
      // Reject = nothing fires: not even the app-open broadcast.
      expect(service.broadcastCalls, 0);
      expect(service.callOrder, ['fanout']);
      expect(result.rateLimited, isTrue);
      expect(result.fanout?.retryAfterMs, 17000);
      expect(result.commandWritten, isFalse);
      expect(result.failure, isNull, reason: 'a reject is not a failure');
      // Notifier settled cleanly, not into an error state.
      final state = container.read(neighborhoodNotifierProvider);
      expect(state.hasError, isFalse);
    });
  });

  // The triggerScoreCelebration group was REMOVED with the function it tested
  // (C11): it asserted a routing contract nothing in production exercised.
  // The broadcastSync gate group above is KEPT — broadcastSync is live code on
  // the neighborhood sync path, and that coverage is real.
}

// FirebaseAuth is sealed; subclassing for a scoped test fake is intentional.
// ignore: subtype_of_sealed_class
class _StubAuth implements FirebaseAuth {
  _StubAuth(this._user);
  final User? _user;
  @override
  User? get currentUser => _user;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}

// User is sealed; same reasoning as _StubAuth.
// ignore: subtype_of_sealed_class
class _StubUser implements User {
  _StubUser(this._uid);
  final String _uid;
  @override
  String get uid => _uid;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}
