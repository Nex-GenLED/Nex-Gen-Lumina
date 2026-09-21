import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/models/inventory/product_catalog_item.dart';
import 'package:nexgen_command/services/inventory/dealer_order_providers.dart';

/// Regression guard for the flutterfire#18417 trigger condition: the app must
/// never have more than one `runTransaction` in flight from a call site that
/// can be driven in bursts.
///
/// The cloud_firestore iOS plugin (< 6.7.0) kept its in-flight transactions in
/// an unsynchronized dictionary mutated from Firestore's worker threads;
/// concurrent transactions corrupted it (EXC_BAD_ACCESS). The plugin is fixed
/// upstream (#18421), but these tests pin the app-side half: the two call
/// sites that COULD fan out now serialize behind an [AsyncLock].
///
/// What this can and cannot prove: it proves the DART side never overlaps
/// transactions. It cannot exercise the native plugin — a host `flutter test`
/// run never loads it.

/// A fake Firestore whose `runTransaction` records how many transactions were
/// in flight at once. fake_cloud_firestore's own implementation is a bare
/// passthrough; the delay here is what gives un-serialized callers the chance
/// to overlap (and, for a read-modify-write, to lose an update).
class _ConcurrencyProbeFirestore extends FakeFirebaseFirestore {
  int inFlight = 0;
  int peak = 0;
  int total = 0;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) async {
    inFlight++;
    total++;
    peak = math.max(peak, inFlight);
    try {
      // Hold the transaction open across an event-loop turn so any caller that
      // is NOT serialized gets to start its own before this one finishes.
      await Future<void>.delayed(const Duration(milliseconds: 15));
      return await super.runTransaction(
        transactionHandler,
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    } finally {
      inFlight--;
    }
  }
}

void main() {
  group('CloudRelayRepository post-watchdog reconcile', () {
    const uid = 'u1';

    CloudRelayRepository repoWith(FirebaseFirestore fs, String controllerId) =>
        CloudRelayRepository(
          userId: uid,
          controllerId: controllerId,
          controllerIp: '10.0.0.32',
          webhookUrl: '',
          firestore: fs,
          commandTimeout: const Duration(milliseconds: 60),
        );

    test('a burst of timed-out commands reconciles one transaction at a time',
        () async {
      final fs = _ConcurrencyProbeFirestore();
      final repo = repoWith(fs, 'c1');

      // No bridge ever answers: all 8 watchdogs expire in the same window,
      // which is exactly when the old code launched 8 transactions together.
      final results =
          await Future.wait(List.generate(8, (_) => repo.getState()));

      expect(results, everyElement(isNull), reason: 'genuine timeouts');
      expect(fs.total, 8, reason: 'every command still gets its reconcile');
      expect(fs.peak, 1, reason: 'reconcile transactions must not overlap');

      // Serializing must not change the outcome: every doc is stamped timeout.
      final docs =
          await fs.collection('users').doc(uid).collection('commands').get();
      expect(docs.docs, hasLength(8));
      expect(docs.docs.map((d) => d.data()['status']), everyElement('timeout'));
    });

    test('the gate is shared ACROSS repository instances', () async {
      // wledRepositoryProvider rebuilds the repo on every connectivity or
      // controller change, so concurrent reconciles routinely belong to
      // different instances. A per-instance lock would not cover that.
      final fs = _ConcurrencyProbeFirestore();
      final repos = List.generate(4, (i) => repoWith(fs, 'c$i'));

      await Future.wait(repos.map((r) => r.getState()));

      expect(fs.total, 4);
      expect(fs.peak, 1);
    });

    test('a failing reconcile releases the gate for the next one', () async {
      final fs = _ThrowOnceFirestore();
      final repo = repoWith(fs, 'c1');

      final results = await Future.wait([repo.getState(), repo.getState()]);

      // First transaction throws (caught → treated as timeout); the second
      // must still run rather than deadlock behind it.
      expect(results, everyElement(isNull));
      expect(fs.total, 2);
      expect(fs.peak, 1);
    });
  });

  group('DealerOrderNotifier line-item transactions', () {
    ProductCatalogItem product(String sku) => ProductCatalogItem(
          sku: sku,
          name: 'Product $sku',
          category: 'rail',
          packQty: 1,
          packUnit: 'each',
          unitPrice: 10,
        );

    test('concurrent edits to ONE order serialize and lose no update',
        () async {
      final fs = _ConcurrencyProbeFirestore();
      final notifier = DealerOrderNotifier(fs);
      final orderId =
          await notifier.createDraft(dealerCode: '01', dealerName: 'Test');

      // "Add to Order" tapped on six product cards in a row — six
      // read-modify-writes of the same document, none awaited by the UI.
      await Future.wait(List.generate(
        6,
        (i) => notifier.addOrUpdateLineItem(
          orderId: orderId,
          product: product('SKU-$i'),
          requestedUnits: i + 1,
        ),
      ));

      expect(fs.total, 6);
      expect(fs.peak, 1, reason: 'same-document transactions must not overlap');

      // The functional half: under the passthrough fake an overlapped
      // read-modify-write silently drops lines. All six must survive.
      final snap = await fs.collection('dealer_orders').doc(orderId).get();
      final lines = (snap.data()!['line_items'] as List).cast<Map>();
      expect(lines.map((l) => l['sku']).toSet(),
          {for (var i = 0; i < 6; i++) 'SKU-$i'});
      expect(snap.data()!['subtotal'], 10.0 * (1 + 2 + 3 + 4 + 5 + 6));
    });

    test('add and remove interleaved on one order stay ordered', () async {
      final fs = _ConcurrencyProbeFirestore();
      final notifier = DealerOrderNotifier(fs);
      final orderId =
          await notifier.createDraft(dealerCode: '01', dealerName: 'Test');

      await Future.wait([
        notifier.addOrUpdateLineItem(
            orderId: orderId, product: product('A'), requestedUnits: 2),
        notifier.addOrUpdateLineItem(
            orderId: orderId, product: product('B'), requestedUnits: 3),
        notifier.removeLineItem(orderId: orderId, sku: 'A'),
      ]);

      expect(fs.peak, 1);
      final snap = await fs.collection('dealer_orders').doc(orderId).get();
      final lines = (snap.data()!['line_items'] as List).cast<Map>();
      expect(lines.map((l) => l['sku']), ['B'], reason: 'FIFO: A added then removed');
    });

    test('different orders do not block each other', () async {
      final fs = _ConcurrencyProbeFirestore();
      final notifier = DealerOrderNotifier(fs);
      final a = await notifier.createDraft(dealerCode: '01', dealerName: 'T');
      final b = await notifier.createDraft(dealerCode: '02', dealerName: 'T');

      await Future.wait([
        notifier.addOrUpdateLineItem(
            orderId: a, product: product('X'), requestedUnits: 1),
        notifier.addOrUpdateLineItem(
            orderId: b, product: product('X'), requestedUnits: 1),
      ]);

      // The lock is keyed per order: two DIFFERENT documents may overlap
      // (no shared-document contention), so this is allowed to reach 2.
      expect(fs.total, 2);
      expect(fs.peak, 2);
    });
  });
}

/// First transaction throws; later ones pass through. Proves a failed
/// reconcile cannot wedge the shared gate.
class _ThrowOnceFirestore extends _ConcurrencyProbeFirestore {
  bool _thrown = false;

  @override
  Future<T> runTransaction<T>(
    TransactionHandler<T> transactionHandler, {
    Duration timeout = const Duration(seconds: 30),
    int maxAttempts = 5,
  }) {
    if (!_thrown) {
      _thrown = true;
      return super.runTransaction<T>(
        (_) async => throw FirebaseException(
            plugin: 'cloud_firestore', code: 'unavailable'),
        timeout: timeout,
        maxAttempts: maxAttempts,
      );
    }
    return super.runTransaction(transactionHandler,
        timeout: timeout, maxAttempts: maxAttempts);
  }
}
