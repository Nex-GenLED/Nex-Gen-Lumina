import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// InventoryService
//
// Real-time Firestore streams and atomic batch writes for material inventory,
// job material lists, and the checkout / check-in lifecycle.
//
// Firestore paths:
//   /dealers/{dealerCode}/materialCatalog/{materialId}
//   /dealers/{dealerCode}/inventory/{materialId}
//   /dealers/{dealerCode}/inventoryLedger/{auto}
//   /sales_jobs/{jobId}/materialList          (single document)
//   /sales_jobs/{jobId}/materialLedger/{auto}
// ─────────────────────────────────────────────────────────────────────────────

class InventoryService {
  final FirebaseFirestore _db;

  InventoryService(this._db);

  // ── Path helpers ─────────────────────────────────────────────────────────

  DocumentReference _materialListDoc(String jobId) =>
      _db.collection('sales_jobs').doc(jobId).collection('materialList').doc('current');

  CollectionReference _materialLedger(String jobId) =>
      _db.collection('sales_jobs').doc(jobId).collection('materialLedger');

  CollectionReference _inventoryCol(String dealerCode) =>
      _db.collection('dealers/$dealerCode/inventory');

  CollectionReference _dealerLedger(String dealerCode) =>
      _db.collection('dealers/$dealerCode/inventoryLedger');

  // ── Save material list ───────────────────────────────────────────────────

  Future<void> saveMaterialList(JobMaterialList list) async {
    await _materialListDoc(list.jobId).set(list.toFirestore());
  }

  // ── Watch job material list ──────────────────────────────────────────────

  Stream<JobMaterialList?> watchJobMaterialList(String jobId) {
    return _materialListDoc(jobId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return JobMaterialList.fromFirestore(doc);
    });
  }

  // ── Watch all inventory records for a dealer ─────────────────────────────

  Stream<List<InventoryRecord>> watchInventory(String dealerCode) {
    return _inventoryCol(dealerCode).snapshots().map((snap) {
      return snap.docs.map((doc) => InventoryRecord.fromFirestore(doc)).toList();
    });
  }

  // ── Watch items at or below reorder threshold ────────────────────────────

  Stream<List<InventoryRecord>> watchLowStock(String dealerCode) {
    return watchInventory(dealerCode).map(
      (records) => records
          .where((r) => r.quantityAvailable <= r.reorderThreshold)
          .toList(),
    );
  }

  // ── PRE-INSTALL CHECKOUT ─────────────────────────────────────────────────

  Future<void> checkOutMaterials({
    required String jobId,
    required String dealerCode,
    required String installerId,
    required List<JobMaterialLine> lines,
  }) async {
    final batch = _db.batch();
    final now = Timestamp.now();

    for (final line in lines) {
      if (line.checkedOutQty <= 0) continue;

      final invDoc = _inventoryCol(dealerCode).doc(line.materialId);

      // Decrement on-hand, increment reserved
      batch.update(invDoc, {
        'quantityOnHand': FieldValue.increment(-line.checkedOutQty),
        'quantityReserved': FieldValue.increment(line.checkedOutQty),
        'lastUpdated': now,
        'lastUpdatedBy': installerId,
      });

      // TODO (Part 10): Dual-write to /dealers/{dealerCode}/sku_inventory
      // when materialCatalogId → product_catalog SKU mapping exists.
      // Expected effect on each mapped SKU:
      //   in_warehouse -= checkedOutQty
      //   on_truck     += checkedOutQty
      //   reserved     -= checkedOutQty   (was reserved, now on truck)
      // Skipped today because JobMaterialLine.materialId is the per-
      // dealer materialCatalogId, not an NGL SKU. When MaterialCatalogItem
      // gains a `sku` field (or a mapping table is introduced), iterate
      // those into a parallel batch.update on
      // _db.collection('dealers').doc(dealerCode).collection('sku_inventory').doc(sku).

      // Dealer inventory ledger
      final dealerEntry = _dealerLedger(dealerCode).doc();
      batch.set(dealerEntry, {
        'type': 'checkout',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'quantity': line.checkedOutQty,
        'jobId': jobId,
        'performedBy': installerId,
        'timestamp': now,
      });

      // Job material ledger (mirror)
      final jobEntry = _materialLedger(jobId).doc();
      batch.set(jobEntry, {
        'type': 'checkout',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'quantity': line.checkedOutQty,
        'performedBy': installerId,
        'timestamp': now,
      });
    }

    // Update material list status
    batch.update(_materialListDoc(jobId), {
      'status': JobMaterialStatus.checkedOut.name,
      'lines': lines.map((l) => l.toMap()).toList(),
      'checkedOutBy': installerId,
      'checkedOutAt': now,
    });

    await batch.commit();
  }

  // ── DAY 1 CHECK-IN ──────────────────────────────────────────────────────

  Future<void> checkInDay1({
    required String jobId,
    required String dealerCode,
    required String installerId,
    required List<JobMaterialLine> updatedLines,
  }) async {
    final batch = _db.batch();
    final now = Timestamp.now();

    // Ledger entries only — no inventory count changes (materials still reserved)
    for (final line in updatedLines) {
      if (line.usedDay1 <= 0) continue;

      final dealerEntry = _dealerLedger(dealerCode).doc();
      batch.set(dealerEntry, {
        'type': 'usage_day1',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'quantity': line.usedDay1,
        'jobId': jobId,
        'performedBy': installerId,
        'timestamp': now,
      });

      final jobEntry = _materialLedger(jobId).doc();
      batch.set(jobEntry, {
        'type': 'usage_day1',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'quantity': line.usedDay1,
        'performedBy': installerId,
        'timestamp': now,
      });
    }

    // Update material list with day1 usage and status
    batch.update(_materialListDoc(jobId), {
      'status': JobMaterialStatus.day1Complete.name,
      'lines': updatedLines.map((l) => l.toMap()).toList(),
      'day1CheckInBy': installerId,
      'day1CheckInAt': now,
    });

    await batch.commit();
  }

  // ── FINAL CHECK-IN — reconciles inventory ────────────────────────────────

  Future<void> checkInFinal({
    required String jobId,
    required String dealerCode,
    required String installerId,
    required List<JobMaterialLine> finalLines,
  }) async {
    final batch = _db.batch();
    final now = Timestamp.now();

    for (final line in finalLines) {
      final invDoc = _inventoryCol(dealerCode).doc(line.materialId);

      // Calculate restock: unused materials that weren't returned
      final double totalUsed = line.usedDay1 + line.usedDay2;
      final double restockQty =
          max(0.0, line.checkedOutQty - totalUsed - line.returnedQty);

      // Release reservation, restock unused
      batch.update(invDoc, {
        'quantityReserved': FieldValue.increment(-line.checkedOutQty),
        'quantityOnHand': FieldValue.increment(restockQty),
        'lastUpdated': now,
        'lastUpdatedBy': installerId,
      });

      // TODO (Part 10): Dual-write to sku_inventory once materialId →
      // SKU mapping exists. Expected effect per mapped SKU:
      //   on_truck     -= line.checkedOutQty   (truck unloaded)
      //   in_warehouse += restockQty            (unused returns to shelf)
      // Note: actual usedDay1 + usedDay2 quantities are CONSUMED on
      // the job and don't return to inventory — they simply disappear
      // from the books, mirrored on both inventories.

      // Dealer inventory ledger
      final dealerEntry = _dealerLedger(dealerCode).doc();
      batch.set(dealerEntry, {
        'type': 'usage_final',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'checkedOutQty': line.checkedOutQty,
        'usedDay1': line.usedDay1,
        'usedDay2': line.usedDay2,
        'returnedQty': line.returnedQty,
        'restockQty': restockQty,
        'waste': line.waste,
        'jobId': jobId,
        'performedBy': installerId,
        'timestamp': now,
      });

      // Job material ledger (mirror)
      final jobEntry = _materialLedger(jobId).doc();
      batch.set(jobEntry, {
        'type': 'usage_final',
        'materialId': line.materialId,
        'materialName': line.materialName,
        'checkedOutQty': line.checkedOutQty,
        'usedDay1': line.usedDay1,
        'usedDay2': line.usedDay2,
        'returnedQty': line.returnedQty,
        'restockQty': restockQty,
        'waste': line.waste,
        'performedBy': installerId,
        'timestamp': now,
      });
    }

    // Update material list status to complete
    batch.update(_materialListDoc(jobId), {
      'status': JobMaterialStatus.complete.name,
      'lines': finalLines.map((l) => l.toMap()).toList(),
      'finalCheckInBy': installerId,
      'finalCheckInAt': now,
    });

    await batch.commit();
  }

  // ── STOCK RECEIVED — manual inventory replenishment ─────────────────────
  //
  // Optimistic dealer-side stock replenishment used by the inventory
  // dashboard's "Receive Stock" action. Atomically:
  //   • increments dealers/{dealerCode}/inventory/{materialId}.quantityOnHand
  //   • writes a 'stock_received' ledger entry to dealers/{dealerCode}/inventoryLedger
  //
  // The dashboard calls this immediately when the dealer marks an order
  // as received — there's no pending-order intermediate state. Negative
  // quantities are rejected so this method can't accidentally be used as
  // a backdoor for stock corrections.

  Future<void> recordStockReceived({
    required String dealerCode,
    required String materialId,
    required double quantity,
    required String installerId,
    String? note,
  }) async {
    if (quantity <= 0) {
      throw ArgumentError('quantity must be > 0');
    }

    final batch = _db.batch();
    final now = Timestamp.now();

    // 1. Bump on-hand stock
    final invDoc = _inventoryCol(dealerCode).doc(materialId);
    batch.update(invDoc, {
      'quantityOnHand': FieldValue.increment(quantity),
      'lastUpdated': now,
      'lastUpdatedBy': installerId,
    });

    // 2. Audit trail entry
    final ledgerEntry = _dealerLedger(dealerCode).doc();
    batch.set(ledgerEntry, {
      'type': 'stock_received',
      'materialId': materialId,
      'quantity': quantity,
      'performedBy': installerId,
      'timestamp': now,
      if (note != null && note.isNotEmpty) 'note': note,
    });

    await batch.commit();
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final inventoryServiceProvider = Provider<InventoryService>(
  (ref) => InventoryService(FirebaseFirestore.instance),
);
