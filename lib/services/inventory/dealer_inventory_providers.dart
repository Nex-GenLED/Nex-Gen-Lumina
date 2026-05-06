import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/models/inventory/dealer_inventory_item.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Inventory Providers
//
// All scoped to a dealerCode passed as the family argument. The
// helper [currentDealerCodeProvider] resolves the active dealer from
// whatever staff session is open (sales, then installer) — the same
// pattern dealer_dashboard_screen._resolveDealerCode uses.
//
// Inventory docs are at /dealers/{dealerCode}/sku_inventory/{sku} —
// distinct from /dealers/{dealerCode}/inventory which is materialId-
// keyed and powers the Day-1/Day-2 install material checkout flow.
// ─────────────────────────────────────────────────────────────────────────────

/// Resolves the active dealerCode from the open staff session. Mirrors
/// the resolution order in DealerDashboardScreen._resolveDealerCode:
/// sales session first, then installer session. Returns null when no
/// staff session is open (the caller should treat null as "no
/// dealer-scoped data available" rather than crash).
final currentDealerCodeProvider = Provider<String?>((ref) {
  final salesSession = ref.watch(currentSalesSessionProvider);
  if (salesSession != null) return salesSession.dealerCode;
  final installerSession = ref.watch(installerSessionProvider);
  if (installerSession != null) return installerSession.dealer.dealerCode;
  return null;
});

/// Streams every sku_inventory doc for a dealer. Ordered by sku for
/// stable list rendering; the inventory screen re-sorts/filters in
/// memory (small list — 60-ish SKUs).
final dealerInventoryProvider =
    StreamProvider.family<List<DealerInventoryItem>, String>(
        (ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('dealers')
      .doc(dealerCode)
      .collection('sku_inventory')
      .snapshots()
      .map((snap) {
    final items = snap.docs
        .map((d) => DealerInventoryItem.fromJson(d.data()))
        .toList();
    items.sort((a, b) => a.sku.compareTo(b.sku));
    return items;
  });
});

/// Single inventory item lookup, family-keyed by (dealerCode, sku).
/// Returns null while loading or for SKUs the dealer has never
/// touched (no doc exists yet).
final inventoryItemProvider = Provider.family<DealerInventoryItem?,
    ({String dealerCode, String sku})>((ref, args) {
  final list = ref.watch(dealerInventoryProvider(args.dealerCode)).valueOrNull;
  if (list == null) return null;
  for (final item in list) {
    if (item.sku == args.sku) return item;
  }
  return null;
});

/// Items at or below the dealer's reorder threshold. Drives the low-
/// stock section on the inventory screen.
final lowStockItemsProvider =
    Provider.family<List<DealerInventoryItem>, String>((ref, dealerCode) {
  final list = ref.watch(dealerInventoryProvider(dealerCode)).valueOrNull
      ?? const [];
  return list.where((i) => i.isLow).toList();
});

/// Items with `needed > 0` — unmet demand from scheduled jobs.
/// Drives the red banner at the top of the inventory screen.
final neededItemsProvider =
    Provider.family<List<DealerInventoryItem>, String>((ref, dealerCode) {
  final list = ref.watch(dealerInventoryProvider(dealerCode)).valueOrNull
      ?? const [];
  return list.where((i) => i.needsReorder).toList();
});

/// Items eligible for auto-reorder: feature toggle on, threshold set,
/// and below threshold. The 48-hour batch window from Part 5 is
/// applied at the order-creation layer, not here.
final pendingAutoReorderItemsProvider =
    Provider.family<List<DealerInventoryItem>, String>((ref, dealerCode) {
  final list = ref.watch(dealerInventoryProvider(dealerCode)).valueOrNull
      ?? const [];
  return list.where((i) => i.isAutoReorderEligible).toList();
});
