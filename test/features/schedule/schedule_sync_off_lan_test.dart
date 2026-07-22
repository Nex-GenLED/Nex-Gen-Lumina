// Off-LAN schedule sync — the silent-success fix.
//
// Arming a schedule is a /json/cfg write (`timers.ins`). In Bridge Mode the
// ESP32 cannot deliver one: its dispatch maps only getState → /json/state and
// getInfo → /json/info, and routes everything else — applyConfig included — to
// POST /json/state, where WLED accepts-and-ignores the cfg keys and returns
// 200. The old code read that as success, so an off-LAN schedule edit reported
// "Synced" while the timers never armed, and did not self-correct (sync only
// runs on a schedule mutation, never on reconnect).
//
// syncAll must now: not attempt the write, not claim success, and not shout —
// the schedule IS saved, it just arms on the next on-LAN sync.

import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

final _refProvider = Provider<Ref>((ref) => ref);

/// A real relay repo in BRIDGE mode (no webhookUrl) — the shape that cannot
/// carry cfg. Firestore is faked, so any queued command would be observable.
CloudRelayRepository _bridgeRepo(FakeFirebaseFirestore fs) =>
    CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '10.0.0.32',
      webhookUrl: '',
      firestore: fs,
      commandTimeout: const Duration(milliseconds: 300),
    );

/// A real relay repo in WEBHOOK mode — the Cloud Function DOES route
/// applyConfig to /json/cfg, so cfg writes are supported here.
CloudRelayRepository _webhookRepo(FakeFirebaseFirestore fs) =>
    CloudRelayRepository(
      userId: 'u1',
      controllerId: 'c1',
      controllerIp: '10.0.0.32',
      webhookUrl: 'https://myhome.duckdns.org:8080',
      firestore: fs,
      commandTimeout: const Duration(milliseconds: 300),
    );

ScheduleItem _item() => const ScheduleItem(
      id: 's1',
      timeLabel: '7:00 PM',
      repeatDays: ['Mon'],
      actionLabel: 'Pattern: Test',
      enabled: true,
      presetId: 10,
      wledPayload: {'on': true},
    );

void main() {
  const svc = ScheduleSyncService();

  ({ProviderContainer container, FakeFirebaseFirestore fs}) harness(
      CloudRelayRepository Function(FakeFirebaseFirestore) build) {
    final fs = FakeFirebaseFirestore();
    final container = ProviderContainer(overrides: [
      wledRepositoryProvider.overrideWithValue(build(fs)),
    ]);
    addTearDown(container.dispose);
    return (container: container, fs: fs);
  }

  group('bridge mode (off-LAN)', () {
    test('does not claim success, and does not report a failure either',
        () async {
      final h = harness(_bridgeRepo);
      final result =
          await svc.syncAll(h.container.read(_refProvider), [_item()]);

      expect(result.deferredOffLan, isTrue);
      expect(result.success, isFalse,
          reason: 'the timers genuinely did not arm — success must not lie');
      expect(result.summaryMessage, kScheduleOffLanNotice);
    });

    test('the copy reads as saved, not broken', () async {
      final h = harness(_bridgeRepo);
      final result =
          await svc.syncAll(h.container.read(_refProvider), [_item()]);

      // The user did nothing wrong and nothing failed — the words must not
      // imply either. This is the whole point of the deferredOffLan channel.
      final msg = result.summaryMessage.toLowerCase();
      expect(msg, contains('saved'));
      expect(msg, contains('home wifi'));
      for (final alarming in ['fail', 'error', 'exception', 'offline']) {
        expect(msg, isNot(contains(alarming)), reason: 'copy must stay calm');
      }
    });

    test('queues NO applyConfig command — the write is not attempted', () async {
      final h = harness(_bridgeRepo);
      await svc.syncAll(h.container.read(_refProvider), [_item()]);

      final cmds = await h.fs
          .collection('users')
          .doc('u1')
          .collection('commands')
          .get();
      expect(
        cmds.docs.where((d) => d.data()['type'] == 'applyConfig'),
        isEmpty,
        reason: 'REGRESSION GUARD: a cfg write over the bridge silently '
            'evaporates while reporting 200 — never send one',
      );
    });

    test('never throws CfgWriteUnsupportedException at the caller', () async {
      // The pre-flight should return before applyConfig is reached; the typed
      // catch is the backstop. Either way syncAll returns a result.
      final h = harness(_bridgeRepo);
      expect(
        await svc.syncAll(h.container.read(_refProvider), [_item()]),
        isA<ScheduleSyncResult>(),
      );
    });
  });

  group('webhook mode (DIY) still arms', () {
    test('is NOT treated as deferred — the Cloud Function routes cfg properly',
        () async {
      final h = harness(_webhookRepo);
      final result =
          await svc.syncAll(h.container.read(_refProvider), [_item()]);

      // The command round-trip has no bridge to answer it here, so it times
      // out rather than succeeding — the point is only that it was ATTEMPTED
      // and not short-circuited into the off-LAN notice.
      expect(result.deferredOffLan, isFalse);
    });
  });

  group('ScheduleSyncResult.deferredOffLan', () {
    test('carries the schedules through so callers keep preset assignments',
        () {
      final r = ScheduleSyncResult.deferredOffLan(
        schedulesWithPresets: [_item()],
        presetErrors: const ['w'],
      );
      expect(r.schedulesWithPresets, hasLength(1));
      expect(r.presetErrors, ['w']);
      expect(r.deferredOffLan, isTrue);
      expect(r.success, isFalse);
      expect(r.error, kScheduleOffLanNotice);
    });
  });
}
