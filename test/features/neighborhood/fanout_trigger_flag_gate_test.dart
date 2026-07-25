// SYNC-3 TASK B — coverage for the flag-gated crew-fanout trigger.
//
// The fanout chain is wired end-to-end via NeighborhoodNotifier.broadcastSync
// and gated by the `config/sync_fanout` feature flag (syncFanoutEnabledSyncProvider).
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
// Plus the SYNC-3 TASK A bypass fix: triggerScoreCelebration (game_day_setup_screen)
// now routes through broadcastSync (the gate) instead of calling
// broadcastSyncCommand directly, so a score celebration fans out to closed-app
// crew when the flag is ON and stays inert (broadcast-only) when it's OFF.
//
// The Cloud Function boundary is mocked by overriding fanoutAdHocSync on a
// NeighborhoodService subclass (fake_cloud_firestore + hand-rolled auth stub,
// matching neighborhood_service_two_tier_stop_test.dart) — no network, no emulator.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';
import 'package:nexgen_command/features/neighborhood/sync_fanout_feature_flag.dart';
import 'package:nexgen_command/features/neighborhood/widgets/game_day_setup_screen.dart'
    show triggerScoreCelebration;

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
  Future<void> broadcastSyncCommand(SyncCommand command) async {
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

void main() {
  group('broadcastSync — flag gate', () {
    test('flag OFF → fanoutAdHocSync NOT called, only broadcastSyncCommand '
        '(byte-identical to today)', () async {
      final service = _makeService();
      final container = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(service),
        syncFanoutEnabledSyncProvider.overrideWithValue(false),
      ]);
      addTearDown(container.dispose);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 0, reason: 'flag off ⇒ no server fanout');
      expect(service.broadcastCalls, 1);
      expect(service.callOrder, ['broadcast']);
      // Flag off returns null (no FanoutResult to surface) — unchanged contract.
      expect(result, isNull);
    });

    test('flag ON → fanout fires FIRST, then broadcast', () async {
      final service = _makeService(fanoutResult: const FanoutResult(ok: true));
      final container = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(service),
        syncFanoutEnabledSyncProvider.overrideWithValue(true),
      ]);
      addTearDown(container.dispose);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 1);
      expect(service.broadcastCalls, 1);
      // Ordering matters: fanout enforces the server rate limit before the
      // app-open broadcast goes out.
      expect(service.callOrder, ['fanout', 'broadcast']);
      expect(result?.ok, isTrue);
      expect(result?.rateLimited, isFalse);
    });

    test('flag ON + rate-limited (server reject) → broadcast SKIPPED, '
        'result returned gracefully (no throw)', () async {
      final service = _makeService(
        fanoutResult: const FanoutResult(rateLimited: true, retryAfterMs: 17000),
      );
      final container = ProviderContainer(overrides: [
        neighborhoodServiceProvider.overrideWithValue(service),
        syncFanoutEnabledSyncProvider.overrideWithValue(true),
      ]);
      addTearDown(container.dispose);

      final result = await container
          .read(neighborhoodNotifierProvider.notifier)
          .broadcastSync(_cmd());

      expect(service.fanoutCalls, 1);
      // Reject = nothing fires: not even the app-open broadcast.
      expect(service.broadcastCalls, 0);
      expect(service.callOrder, ['fanout']);
      expect(result?.rateLimited, isTrue);
      expect(result?.retryAfterMs, 17000);
      // Notifier settled cleanly, not into an error state.
      final state = container.read(neighborhoodNotifierProvider);
      expect(state.hasError, isFalse);
    });
  });

  // ── SYNC-3 TASK A: the game_day_setup_screen :931 bypass fix ────────────────
  // triggerScoreCelebration now routes through broadcastSync (the flag gate).
  // Pre-fix it called broadcastSyncCommand directly → NEVER fanned out. These
  // widget tests drive the real function with a captured WidgetRef.
  group('triggerScoreCelebration — routes through the flag gate (bypass fix)',
      () {
    Future<_RecordingService> pumpAndTrigger(
      WidgetTester tester, {
      required bool flagEnabled,
      FanoutResult fanoutResult = const FanoutResult(ok: true),
    }) async {
      final service = _RecordingService(
        firestore: FakeFirebaseFirestore(),
        auth: _StubAuth(_StubUser('u1')),
        fanoutResult: fanoutResult,
      );
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'Me',
        positionIndex: 0,
        lastSeen: DateTime(2024, 1, 1),
      );

      late WidgetRef capturedRef;
      await tester.pumpWidget(
        ProviderScope(
          overrides: [
            neighborhoodServiceProvider.overrideWithValue(service),
            syncFanoutEnabledSyncProvider.overrideWithValue(flagEnabled),
            activeNeighborhoodIdProvider.overrideWith((ref) => 'g1'),
            neighborhoodMembersProvider
                .overrideWith((ref) => Stream.value([member])),
          ],
          child: Consumer(
            builder: (ctx, ref, _) {
              // Keep the members stream subscribed so it resolves before the
              // one-shot ref.read inside triggerScoreCelebration.
              ref.watch(neighborhoodMembersProvider);
              capturedRef = ref;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pump(); // let the members stream emit its first value

      await triggerScoreCelebration('nfl_bills', capturedRef);
      return service;
    }

    testWidgets('flag ON → celebration fans out to the crew', (tester) async {
      final service = await pumpAndTrigger(tester, flagEnabled: true);
      expect(service.fanoutCalls, 1, reason: 'flag on ⇒ fans out (fix works)');
      expect(service.broadcastCalls, 1);
      expect(service.callOrder, ['fanout', 'broadcast']);
    });

    testWidgets('flag OFF → inert: broadcast only, no fanout', (tester) async {
      final service = await pumpAndTrigger(tester, flagEnabled: false);
      expect(service.fanoutCalls, 0);
      expect(service.broadcastCalls, 1);
      expect(service.callOrder, ['broadcast']);
    });
  });
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
