import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/services/inventory_service.dart';

// Re-export service providers so consumers only need one import.
export 'package:nexgen_command/features/sales/services/inventory_service.dart'
    show inventoryServiceProvider;
export 'package:nexgen_command/features/sales/services/material_calculation_service.dart'
    show materialCalculationServiceProvider;

// ─────────────────────────────────────────────────────────────────────────────
// Job Material List — real-time stream for a single job
// ─────────────────────────────────────────────────────────────────────────────

final jobMaterialListProvider =
    StreamProvider.family<JobMaterialList?, String>((ref, jobId) {
  final service = ref.watch(inventoryServiceProvider);
  return service.watchJobMaterialList(jobId);
});

// ─────────────────────────────────────────────────────────────────────────────
// Inventory — real-time stream of all inventory records for a dealer
// ─────────────────────────────────────────────────────────────────────────────

final inventoryProvider =
    StreamProvider.family<List<InventoryRecord>, String>((ref, dealerCode) {
  final service = ref.watch(inventoryServiceProvider);
  return service.watchInventory(dealerCode);
});

// ─────────────────────────────────────────────────────────────────────────────
// Low Stock — items at or below reorder threshold
// ─────────────────────────────────────────────────────────────────────────────

final lowStockProvider =
    StreamProvider.family<List<InventoryRecord>, String>((ref, dealerCode) {
  final service = ref.watch(inventoryServiceProvider);
  return service.watchLowStock(dealerCode);
});

// ─────────────────────────────────────────────────────────────────────────────
// Material Catalog — per-dealer catalog of MaterialItem definitions
//
// Streams /dealers/{dealerCode}/materialCatalog filtered to active items
// and exposes them as a Map<materialId, MaterialItem> for cheap O(1)
// joining against InventoryRecord (which only carries the materialId).
//
// Used by the inventory dashboard's Section 1 to render material names
// and units alongside the per-item stock counts coming from
// inventoryProvider.
// ─────────────────────────────────────────────────────────────────────────────

final materialCatalogProvider =
    StreamProvider.family<Map<String, MaterialItem>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('dealers/$dealerCode/materialCatalog')
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((snap) => {
            for (final doc in snap.docs)
              doc.id: MaterialItem.fromFirestore(doc),
          });
});
