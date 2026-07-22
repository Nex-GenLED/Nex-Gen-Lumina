import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/models/inventory/corporate_inventory_item.dart';
import 'package:nexgen_command/models/inventory/dealer_order.dart';
import 'package:nexgen_command/models/inventory/purchase_order.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Corporate Providers
//
// All admin/owner-only at the rule layer (firestore.rules). The
// providers here are read-only streams — write paths for corporate
// inventory and purchase orders live in the Part 7/8 screens, and
// dealer-order updates go through DealerOrderNotifier in
// dealer_order_providers.dart.
//
// Naming: kept distinct from the dealer-side ordersByStatusProvider
// (in dealer_order_providers.dart) to avoid import collisions —
// there it's family<List<DealerOrder>, ({dealerCode, status})>; here
// it's family<List<DealerOrder>, OrderStatus> across all dealers.
// ─────────────────────────────────────────────────────────────────────────────

/// Every dealer order across the network, ordered by createdAt
/// descending. Powers Tyler's corporate orders queue (Part 7).
final allDealerOrdersProvider =
    StreamProvider<List<DealerOrder>>((ref) {
  return FirebaseFirestore.instance
      .collection('dealer_orders')
      .snapshots()
      .map((snap) {
    final orders = snap.docs
        .map((d) => DealerOrder.fromJson(d.data()))
        .toList();
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

/// Cross-dealer orders filtered to a single status. Keyed by status
/// so the corporate orders screen can mount one provider per tab.
final allOrdersByStatusProvider =
    Provider.family<List<DealerOrder>, OrderStatus>((ref, status) {
  final orders = ref.watch(allDealerOrdersProvider).valueOrNull ?? const [];
  return orders.where((o) => o.status == status).toList();
});

/// Count of orders awaiting corporate review (status == submitted).
/// Drives the badge on the corporate orders nav entry.
final pendingReviewCountProvider = Provider<int>((ref) {
  final orders = ref.watch(allDealerOrdersProvider).valueOrNull ?? const [];
  return orders.where((o) => o.status == OrderStatus.submitted).length;
});

// ─── Corporate warehouse inventory ──────────────────────────────────────────

/// Stream of every /corporate_inventory doc, sorted by SKU. Powers
/// the Part 8 warehouse screen.
final corporateInventoryProvider =
    StreamProvider<List<CorporateInventoryItem>>((ref) {
  return FirebaseFirestore.instance
      .collection('corporate_inventory')
      .snapshots()
      .map((snap) {
    final items = snap.docs
        .map((d) => CorporateInventoryItem.fromJson(d.data()))
        .toList();
    items.sort((a, b) => a.sku.compareTo(b.sku));
    return items;
  });
});

/// Single corporate-warehouse SKU lookup.
final corporateInventoryItemProvider =
    Provider.family<CorporateInventoryItem?, String>((ref, sku) {
  final list = ref.watch(corporateInventoryProvider).valueOrNull;
  if (list == null) return null;
  for (final item in list) {
    if (item.sku == sku) return item;
  }
  return null;
});

/// Corporate warehouse items at or below their reorder point.
final corporateLowStockProvider =
    Provider<List<CorporateInventoryItem>>((ref) {
  final list = ref.watch(corporateInventoryProvider).valueOrNull ?? const [];
  return list.where((i) => i.isLow).toList();
});

// ─── Purchase orders ────────────────────────────────────────────────────────

/// Stream of every /purchase_orders doc, ordered by createdAt
/// descending. Powers the Part 8 PO list.
final purchaseOrdersProvider =
    StreamProvider<List<PurchaseOrder>>((ref) {
  return FirebaseFirestore.instance
      .collection('purchase_orders')
      .snapshots()
      .map((snap) {
    final pos = snap.docs
        .map((d) => PurchaseOrder.fromJson(d.data()))
        .toList();
    pos.sort((a, b) {
      final ad = a.createdAt;
      final bd = b.createdAt;
      if (ad == null && bd == null) return 0;
      if (ad == null) return 1;
      if (bd == null) return -1;
      return bd.compareTo(ad);
    });
    return pos;
  });
});

/// POs that are still open (status != received). Drives the active
/// POs section on the warehouse screen.
final openPurchaseOrdersProvider =
    Provider<List<PurchaseOrder>>((ref) {
  final pos = ref.watch(purchaseOrdersProvider).valueOrNull ?? const [];
  return pos.where((p) => p.status != POStatus.received).toList();
});

/// Distinct supplier names across every existing PO, used to populate
/// the create-PO supplier dropdown so Tyler can pick from past
/// suppliers instead of retyping.
final knownSuppliersProvider = Provider<List<String>>((ref) {
  final pos = ref.watch(purchaseOrdersProvider).valueOrNull ?? const [];
  final names = <String>{
    for (final p in pos)
      if (p.supplierName.trim().isNotEmpty) p.supplierName.trim(),
  };
  final list = names.toList()
    ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
  return list;
});

// ─────────────────────────────────────────────────────────────────────────────
// CorporateInventoryNotifier
//
// Write-side surface for the corporate warehouse (POs + on-hand
// inventory). Stateless — every method writes directly to Firestore;
// streams above re-render on the resulting snapshot.
//
// Atomic guarantees:
//   • createPO: single-doc write.
//   • receivePOShipment: batch over PO line-item update + status
//     flip + per-SKU corporate_inventory.on_hand increment.
//   • setReorderPoint: single-doc write with set(merge:true) so a
//     SKU that has never had inventory still gets a doc on first
//     reorder-point edit.
// ─────────────────────────────────────────────────────────────────────────────

class CorporateInventoryNotifier {
  final FirebaseFirestore _db;
  CorporateInventoryNotifier(this._db);

  CollectionReference<Map<String, dynamic>> get _pos =>
      _db.collection('purchase_orders');

  CollectionReference<Map<String, dynamic>> get _inv =>
      _db.collection('corporate_inventory');

  /// Create a PO with status 'ordered'. Returns the new poId.
  Future<String> createPO({
    required String supplierName,
    required List<POLineItem> lineItems,
    required String createdBy,
    DateTime? expectedDelivery,
    String? notes,
  }) async {
    final ref = _pos.doc();
    final now = Timestamp.now();
    await ref.set({
      ...PurchaseOrder(
        poId: ref.id,
        supplierName: supplierName,
        status: POStatus.ordered,
        lineItems: lineItems,
        expectedDelivery: expectedDelivery,
        createdBy: createdBy,
        notes: notes,
      ).toJson(),
      // Server-controlled timestamp so the create order is the
      // source of truth for createdAt.
      'created_at': now,
    });
    return ref.id;
  }

  /// Apply a partial-or-full receive against an existing PO.
  ///
  /// [received] maps each line's SKU to the quantity received in
  /// THIS shipment. Quantities are clamped to the line's outstanding
  /// units server-side so a typo can't push qty_received past
  /// qty_ordered. After applying, status auto-resolves:
  ///   • all lines fullyReceived  → POStatus.received  + received_at
  ///   • some lines have qtyReceived > 0 but not all  → POStatus.partial
  ///   • else (no-op shipment)    → unchanged
  ///
  /// Side effect: each SKU with delta > 0 increments
  /// /corporate_inventory/{sku}.on_hand by the delta and bumps
  /// last_received_at. Inventory docs are upserted via merge so a
  /// brand-new SKU works on first receive.
  Future<void> receivePOShipment({
    required String poId,
    required Map<String, int> received,
  }) async {
    final poRef = _pos.doc(poId);
    final snap = await poRef.get();
    if (!snap.exists) {
      throw StateError('PO $poId not found');
    }
    final po = PurchaseOrder.fromJson(snap.data()!);

    // Build updated line items with clamped qty_received.
    final updatedLines = <POLineItem>[];
    final deltas = <String, int>{};
    for (final line in po.lineItems) {
      final raw = received[line.sku] ?? 0;
      if (raw <= 0) {
        updatedLines.add(line);
        continue;
      }
      final outstanding = line.qtyOutstanding;
      final delta = raw > outstanding ? outstanding : raw;
      if (delta <= 0) {
        updatedLines.add(line);
        continue;
      }
      updatedLines.add(line.copyWith(qtyReceived: line.qtyReceived + delta));
      deltas[line.sku] = (deltas[line.sku] ?? 0) + delta;
    }

    if (deltas.isEmpty) {
      // No-op receive — caller passed all zeros (or only over-ship
      // attempts). Nothing to write; signal cleanly.
      return;
    }

    final newPo = po.copyWith(lineItems: updatedLines);
    final newStatus = newPo.isAllReceived
        ? POStatus.received
        : (newPo.isPartial ? POStatus.partial : POStatus.ordered);

    final batch = _db.batch();
    final now = Timestamp.now();

    // 1) Update the PO doc.
    batch.update(poRef, {
      'line_items': updatedLines.map((l) => l.toJson()).toList(),
      'status': newStatus.toJson(),
      if (newStatus == POStatus.received) 'received_at': now,
    });

    // 2) Increment corporate_inventory.on_hand per SKU. Upsert via
    //    merge so a brand-new SKU's inventory doc gets created on
    //    first receive (with sku field populated for query-time
    //    sanity).
    for (final entry in deltas.entries) {
      final invRef = _inv.doc(entry.key);
      batch.set(
        invRef,
        {
          'sku': entry.key,
          'on_hand': FieldValue.increment(entry.value),
          'last_updated': now,
          'last_received_at': now,
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();

    // TODO (future scope, per Tyler's spec note for Part 8):
    // dealer orders that are payment_confirmed/processing and
    // contain any of `deltas.keys` are now "ready to ship" if they
    // were waiting on this stock. A notification surface here would
    // surface those orders to Tyler. Out of scope until the
    // notification system lands.
  }

  /// Set or update the reorder_point for a SKU. Upserts via merge so
  /// SKUs Tyler hasn't received yet still get a config doc.
  Future<void> setReorderPoint({
    required String sku,
    required int reorderPoint,
  }) async {
    await _inv.doc(sku).set(
      {
        'sku': sku,
        'reorder_point': reorderPoint,
        'last_updated': Timestamp.now(),
      },
      SetOptions(merge: true),
    );
  }
}

/// Singleton notifier provider.
final corporateInventoryNotifierProvider =
    Provider<CorporateInventoryNotifier>(
  (ref) => CorporateInventoryNotifier(FirebaseFirestore.instance),
);
