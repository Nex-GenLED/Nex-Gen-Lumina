import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/dealer_order.dart';
import 'package:nexgen_command/models/inventory/product_catalog_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Order Providers + Notifier
//
// All scoped to a dealerCode passed as the family argument. Reads
// happen through Firestore streams; writes go through
// [DealerOrderNotifier] (CRUD plus the 48-hour batch-window auto-
// reorder logic from Part 5).
// ─────────────────────────────────────────────────────────────────────────────

/// All orders for a dealer, ordered by createdAt descending. Drives
/// the order history screen (Part 6) and the active-order resolver
/// below.
final dealerOrdersProvider =
    StreamProvider.family<List<DealerOrder>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('dealer_orders')
      .where('dealer_code', isEqualTo: dealerCode)
      .snapshots()
      .map((snap) {
    final orders = snap.docs
        .map((d) => DealerOrder.fromJson(d.data()))
        .toList();
    // Sort in memory to avoid a composite index on (dealer_code,
    // created_at). Order count per dealer is small.
    orders.sort((a, b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return orders;
  });
});

/// The dealer's current draft order if one exists. There can only be
/// one draft at a time per dealer in normal use; if multiple drafts
/// exist (e.g. created in parallel before the batch window logic was
/// in place) the most recent one wins.
final activeOrderProvider =
    Provider.family<DealerOrder?, String>((ref, dealerCode) {
  final orders =
      ref.watch(dealerOrdersProvider(dealerCode)).valueOrNull ?? const [];
  for (final order in orders) {
    if (order.status == OrderStatus.draft) return order;
  }
  return null;
});

/// Filter orders by status. Family arg is a record so screens can
/// drive multiple status tabs from a single provider definition.
final ordersByStatusProvider = Provider.family<List<DealerOrder>,
    ({String dealerCode, OrderStatus status})>((ref, args) {
  final orders =
      ref.watch(dealerOrdersProvider(args.dealerCode)).valueOrNull
          ?? const [];
  return orders.where((o) => o.status == args.status).toList();
});

// ─── Notifier ───────────────────────────────────────────────────────────────

/// Manages [DealerOrder] lifecycle: draft creation, line-item edits,
/// submission, payment confirmation, receive-side inventory updates.
///
/// Stateless — all mutations write directly to Firestore. The screens
/// re-render via the streams above. This shape mirrors
/// [InventoryService] in lib/features/sales/services so the existing
/// dealer-side surface area stays stylistically consistent.
class DealerOrderNotifier {
  final FirebaseFirestore _db;
  DealerOrderNotifier(this._db);

  CollectionReference<Map<String, dynamic>> get _orders =>
      _db.collection('dealer_orders');

  CollectionReference<Map<String, dynamic>> _skuInventory(String dealerCode) =>
      _db.collection('dealers').doc(dealerCode).collection('sku_inventory');

  // ── Draft creation ────────────────────────────────────────────────

  /// Create a new draft order. Returns the new orderId.
  Future<String> createDraft({
    required String dealerCode,
    required String dealerName,
  }) async {
    final ref = _orders.doc();
    final now = Timestamp.now();
    await ref.set({
      ...DealerOrder(
        orderId: ref.id,
        dealerCode: dealerCode,
        dealerName: dealerName,
      ).toJson(),
      // Override with server timestamps so the DB clock is the source
      // of truth (the model's toJson uses Timestamp.fromDate when set,
      // but createdAt/updatedAt are null on a fresh DealerOrder).
      'created_at': now,
      'updated_at': now,
    });
    return ref.id;
  }

  /// Find an open draft for this dealer that was created within the
  /// last 48 hours; if none, create a new one. Implements the batch-
  /// window auto-reorder rule from the Part 5 spec — auto-reorder
  /// triggers append to the existing draft instead of fragmenting
  /// into many tiny orders.
  Future<DealerOrder> findOrCreateBatchDraft({
    required String dealerCode,
    required String dealerName,
    Duration window = const Duration(hours: 48),
  }) async {
    final cutoff = DateTime.now().subtract(window);
    // Single-field where avoids the composite index requirement; the
    // dealer order list is small so the in-memory filter is cheap.
    final snap =
        await _orders.where('dealer_code', isEqualTo: dealerCode).get();
    DealerOrder? newest;
    for (final doc in snap.docs) {
      final order = DealerOrder.fromJson(doc.data());
      if (order.status != OrderStatus.draft) continue;
      if (order.createdAt == null || order.createdAt!.isBefore(cutoff)) continue;
      if (newest == null || order.createdAt!.isAfter(newest.createdAt!)) {
        newest = order;
      }
    }
    if (newest != null) return newest;
    final id = await createDraft(dealerCode: dealerCode, dealerName: dealerName);
    final fresh = await _orders.doc(id).get();
    return DealerOrder.fromJson(fresh.data() ?? <String, dynamic>{});
  }

  // ── Line item edits ───────────────────────────────────────────────

  /// Add a SKU to a draft order, or update its quantity if already
  /// present. Quantity is rounded up to the next pack-quantity multiple
  /// using [ProductCatalogItem.roundUpToPackQty]. Recomputes subtotal
  /// and order_total in the same write.
  Future<void> addOrUpdateLineItem({
    required String orderId,
    required ProductCatalogItem product,
    required int requestedUnits,
  }) async {
    final docRef = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final order = DealerOrder.fromJson(snap.data()!);
      if (order.status != OrderStatus.draft) {
        throw StateError(
            'Cannot edit line items on order $orderId — status is ${order.status.label}.');
      }
      final units = product.roundUpToPackQty(requestedUnits);
      final packs = product.packsNeeded(requestedUnits);
      final lineTotal = units * product.unitPrice;
      final newLine = DealerOrderLineItem(
        sku: product.sku,
        name: product.name,
        quantityOrdered: units,
        packQty: product.packQty,
        packsOrdered: packs,
        unitPrice: product.unitPrice,
        lineTotal: lineTotal,
      );

      final lines = List<DealerOrderLineItem>.from(order.lineItems);
      final idx = lines.indexWhere((l) => l.sku == product.sku);
      if (idx == -1) {
        lines.add(newLine);
      } else {
        lines[idx] = newLine;
      }

      final subtotal = lines.fold<double>(0, (acc, l) => acc + l.lineTotal);
      final orderTotal = subtotal + order.shippingCost;

      tx.update(docRef, {
        'line_items': lines.map((l) => l.toJson()).toList(),
        'subtotal': subtotal,
        'order_total': orderTotal,
        'updated_at': Timestamp.now(),
      });
    });
  }

  /// Remove a SKU line from a draft order. No-op if the SKU isn't
  /// present. Recomputes subtotal/order_total.
  Future<void> removeLineItem({
    required String orderId,
    required String sku,
  }) async {
    final docRef = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final order = DealerOrder.fromJson(snap.data()!);
      if (order.status != OrderStatus.draft) return;
      final lines = order.lineItems.where((l) => l.sku != sku).toList();
      final subtotal = lines.fold<double>(0, (acc, l) => acc + l.lineTotal);
      tx.update(docRef, {
        'line_items': lines.map((l) => l.toJson()).toList(),
        'subtotal': subtotal,
        'order_total': subtotal + order.shippingCost,
        'updated_at': Timestamp.now(),
      });
    });
  }

  /// Update freeform notes on the order. Allowed at any non-shipped
  /// status — useful for both dealer (delivery instructions) and
  /// admin (internal annotations).
  Future<void> updateNotes({
    required String orderId,
    String? notes,
  }) async {
    await _orders.doc(orderId).update({
      'notes': notes,
      'updated_at': Timestamp.now(),
    });
  }

  // ── Lifecycle transitions ─────────────────────────────────────────

  /// Dealer-side: mark a draft as submitted. App-side validation
  /// (lineItems.isNotEmpty) lives at the screen layer; here we just
  /// flip the status and timestamp.
  Future<void> submit(String orderId) async {
    await _orders.doc(orderId).update({
      'status': OrderStatus.submitted.toJson(),
      'submitted_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
  }

  /// Dealer-side: mark that the dealer has sent payment. Corporate
  /// confirms receipt separately.
  Future<void> markPaymentSent(String orderId) async {
    await _orders.doc(orderId).update({
      'status': OrderStatus.paymentPending.toJson(),
      'payment_status': 'sent',
      'updated_at': Timestamp.now(),
    });
  }

  /// Corporate-side: confirm payment received. Bumps status to
  /// `processing`. Caller is responsible for any inventory reservation
  /// side-effects (Part 7).
  Future<void> confirmPayment({
    required String orderId,
    required String confirmedBy,
  }) async {
    await _orders.doc(orderId).update({
      'status': OrderStatus.processing.toJson(),
      'payment_status': 'paid',
      'payment_confirmed_by': confirmedBy,
      'payment_confirmed_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
  }

  /// Corporate-side: approve the order with a shipping cost. Order
  /// transitions from submitted → payment_pending (waiting for the
  /// dealer to send funds).
  Future<void> approveWithShipping({
    required String orderId,
    required double shippingCost,
    String? shippingCarrier,
    required String approvedBy,
  }) async {
    await _db.runTransaction((tx) async {
      final docRef = _orders.doc(orderId);
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final order = DealerOrder.fromJson(snap.data()!);
      tx.update(docRef, {
        'shipping_cost': shippingCost,
        'shipping_carrier': shippingCarrier,
        'order_total': order.subtotal + shippingCost,
        'status': OrderStatus.paymentPending.toJson(),
        'approved_by': approvedBy,
        'approved_at': Timestamp.now(),
        'updated_at': Timestamp.now(),
      });
    });
  }

  /// Corporate-side: mark order shipped with tracking info. Dealer
  /// inventory `on_order` doesn't change here — it's decremented and
  /// `in_warehouse` is incremented when the dealer marks the order
  /// received.
  Future<void> markShipped({
    required String orderId,
    required String trackingNumber,
    String? carrier,
  }) async {
    await _orders.doc(orderId).update({
      'status': OrderStatus.shipped.toJson(),
      'tracking_number': trackingNumber,
      if (carrier != null) 'shipping_carrier': carrier,
      'shipped_at': Timestamp.now(),
      'updated_at': Timestamp.now(),
    });
  }

  /// Dealer-side: mark a shipped order as received. Atomically:
  ///   • flips order status to received + sets received_at
  ///   • for each line item: decrements sku_inventory.on_order and
  ///     increments sku_inventory.in_warehouse by quantity_ordered
  ///
  /// Uses set(merge: true) on inventory docs so a SKU the dealer has
  /// never stocked before (no doc) gets created on receive.
  Future<void> markReceived({
    required String orderId,
    required String dealerCode,
  }) async {
    final batch = _db.batch();
    final orderRef = _orders.doc(orderId);
    final orderSnap = await orderRef.get();
    if (!orderSnap.exists) return;
    final order = DealerOrder.fromJson(orderSnap.data()!);

    final now = Timestamp.now();
    batch.update(orderRef, {
      'status': OrderStatus.received.toJson(),
      'received_at': now,
      'updated_at': now,
    });

    for (final line in order.lineItems) {
      final invRef = _skuInventory(dealerCode).doc(line.sku);
      batch.set(
        invRef,
        {
          'sku': line.sku,
          'in_warehouse': FieldValue.increment(line.quantityOrdered),
          'on_order': FieldValue.increment(-line.quantityOrdered),
          'last_updated': now,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
  }

  /// Drafts can be deleted (rule already enforces draft-only delete).
  /// Submitted-or-later orders are an audit trail and must not be
  /// removed; this method throws if called on a non-draft.
  Future<void> deleteDraft(String orderId) async {
    final snap = await _orders.doc(orderId).get();
    if (!snap.exists) return;
    final order = DealerOrder.fromJson(snap.data()!);
    if (order.status != OrderStatus.draft) {
      throw StateError('Cannot delete order $orderId — not a draft.');
    }
    await _orders.doc(orderId).delete();
  }

  /// Corporate-side: reject a submitted order. Returns it to the
  /// dealer as a draft with the rejection reason appended to notes
  /// so the dealer can revise and resubmit. The audit trail
  /// (submitted_at) is intentionally preserved — only status, notes,
  /// and updated_at change.
  Future<void> rejectOrder({
    required String orderId,
    required String reason,
  }) async {
    final docRef = _orders.doc(orderId);
    await _db.runTransaction((tx) async {
      final snap = await tx.get(docRef);
      if (!snap.exists) return;
      final order = DealerOrder.fromJson(snap.data()!);
      final now = Timestamp.now();
      final stampedReason =
          'Rejected by Nex-Gen ${now.toDate().toIso8601String()}: '
          '$reason';
      final mergedNotes = order.notes == null || order.notes!.trim().isEmpty
          ? stampedReason
          : '${order.notes}\n\n$stampedReason';
      tx.update(docRef, {
        'status': OrderStatus.draft.toJson(),
        'notes': mergedNotes,
        'updated_at': now,
      });
    });
  }
}

/// Singleton notifier provider. The notifier is stateless (every call
/// hits Firestore directly), so a single instance is fine.
final dealerOrderNotifierProvider = Provider<DealerOrderNotifier>(
  (ref) => DealerOrderNotifier(FirebaseFirestore.instance),
);
