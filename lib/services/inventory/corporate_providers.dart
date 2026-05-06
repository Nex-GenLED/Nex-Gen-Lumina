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
