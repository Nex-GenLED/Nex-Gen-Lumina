// NOTE: This file contains legacy cross-dealer inventory intelligence
// (network aggregation, waste %, active demand). Not currently wired
// into any screen after the warehouse tab replacement. Preserved for
// future analytics use.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_job_providers.dart';
import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────
// Cross-dealer inventory snapshot
//
// Inventory lives at /dealers/{dealerCode}/inventory/{materialId}, so to
// query across all dealers we use a Firestore COLLECTION GROUP query on
// `inventory`. Required Firestore index:
//
//     collectionGroup: "inventory"  (no extra fields needed for the
//                                    base query — implicit __name__
//                                    index is sufficient)
//
// Note: collection group queries require enabling the index even when
// the query is unfiltered. Flagged in the build summary.
// ─────────────────────────────────────────────────────────────────────────

/// Streams every `inventory` subcollection across every dealer, grouped
/// by `dealerCode`.
///
/// The Firestore parent path encodes the dealer code, so we extract it
/// from `doc.reference.parent.parent?.id`.
final allDealerInventoryProvider =
    StreamProvider<Map<String, List<InventoryRecord>>>((ref) {
  return FirebaseFirestore.instance
      .collectionGroup('inventory')
      .snapshots()
      .map((snap) {
    final byDealer = <String, List<InventoryRecord>>{};
    for (final doc in snap.docs) {
      final parent = doc.reference.parent.parent;
      final dealerCode = parent?.id ?? '';
      if (dealerCode.isEmpty) continue;
      byDealer
          .putIfAbsent(dealerCode, () => <InventoryRecord>[])
          .add(InventoryRecord.fromFirestore(doc));
    }
    return byDealer;
  });
});

/// Streams the union of every dealer's `materialCatalog` subcollection
/// so we can render material names alongside cross-dealer inventory rows.
///
/// Required Firestore index: collection group on `materialCatalog`.
///
/// Returned map is keyed by `materialId`. If the same materialId appears
/// in multiple dealer catalogs with different names, the most recently
/// streamed one wins (acceptable for display purposes).
final allMaterialCatalogProvider =
    StreamProvider<Map<String, MaterialItem>>((ref) {
  return FirebaseFirestore.instance
      .collectionGroup('materialCatalog')
      .where('isActive', isEqualTo: true)
      .snapshots()
      .map((snap) {
    final out = <String, MaterialItem>{};
    for (final doc in snap.docs) {
      out[doc.id] = MaterialItem.fromFirestore(doc);
    }
    return out;
  });
});

// ─────────────────────────────────────────────────────────────────────────
// Aggregate demand (from active jobs' estimateBreakdown)
// ─────────────────────────────────────────────────────────────────────────

/// One row in the active-demand table — per estimate line item id.
///
/// IMPORTANT SCHEMA NOTE: [SalesJob.estimateBreakdown.lineItems] is keyed
/// by [EstimateLineItem.id], which is a stable hash of
/// `description + category` — NOT the [InventoryRecord.materialId] used
/// by the dealer catalog. The two ID systems are independent. We aggregate
/// by EstimateLineItem.id here and surface the description for display;
/// the warehouse "fulfillment gap" join against inventory is a best-effort
/// match by description (case-insensitive contains) since there is no
/// authoritative bridge between the two ID systems today. Flagged in the
/// build summary as a known schema gap.
class CorporateMaterialDemand {
  final String lineItemId;
  final String description;
  final String unit;
  final double totalQuantity;

  /// Number of distinct active jobs that include this line.
  final int jobCount;

  const CorporateMaterialDemand({
    required this.lineItemId,
    required this.description,
    required this.unit,
    required this.totalQuantity,
    required this.jobCount,
  });
}

/// Aggregate quantity demand across every ACTIVE job (status not
/// [SalesJobStatus.installComplete]). Computed from
/// [SalesJob.estimateBreakdown.lineItems].
///
/// Returns a Map keyed by [EstimateLineItem.id].
final networkMaterialDemandProvider =
    Provider<AsyncValue<Map<String, CorporateMaterialDemand>>>((ref) {
  final jobsAsync = ref.watch(allJobsProvider);
  return jobsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (jobs) {
      final out = <String, CorporateMaterialDemand>{};
      for (final job in jobs) {
        if (job.status == SalesJobStatus.installComplete) continue;
        final breakdown = job.estimateBreakdown;
        if (breakdown == null) continue;
        for (final line in breakdown.lineItems) {
          final existing = out[line.id];
          if (existing == null) {
            out[line.id] = CorporateMaterialDemand(
              lineItemId: line.id,
              description: line.description,
              unit: line.unit,
              totalQuantity: line.quantity,
              jobCount: 1,
            );
          } else {
            out[line.id] = CorporateMaterialDemand(
              lineItemId: line.id,
              description: existing.description,
              unit: existing.unit,
              totalQuantity: existing.totalQuantity + line.quantity,
              jobCount: existing.jobCount + 1,
            );
          }
        }
      }
      return AsyncValue.data(out);
    },
  );
});

// ─────────────────────────────────────────────────────────────────────────
// Network waste intelligence
// ─────────────────────────────────────────────────────────────────────────

/// Aggregate waste statistics for one estimate-line-item across the
/// network. Surfaced on the Warehouse tab's "Network Waste Intelligence"
/// section so corporate can see which materials are over-quoted.
class WasteStats {
  /// Estimate line item id this row aggregates over.
  final String itemId;
  final String description;

  /// Average waste percentage across [sampleCount] completed jobs.
  /// Waste % = (estimatedQty - usedQty) / estimatedQty.
  final double avgWastePct;

  final int sampleCount;

  /// Dealer code with the LOWEST waste % for this material (best
  /// performer). Null if only one sample exists.
  final String? bestDealerCode;

  /// Dealer code with the HIGHEST waste % for this material (worst
  /// performer). Null if only one sample exists.
  final String? worstDealerCode;

  const WasteStats({
    required this.itemId,
    required this.description,
    required this.avgWastePct,
    required this.sampleCount,
    required this.bestDealerCode,
    required this.worstDealerCode,
  });
}

/// Compute per-line-item waste stats across all completed jobs that have
/// an `actualMaterialUsage` record. Returns a map keyed by line item id.
final networkWasteStatsProvider =
    Provider<AsyncValue<Map<String, WasteStats>>>((ref) {
  final jobsAsync = ref.watch(allJobsProvider);
  return jobsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (jobs) {
      // itemId -> list of (dealerCode, wastePct, description)
      final samples = <String, List<_WasteSample>>{};

      for (final job in jobs) {
        final usage = job.actualMaterialUsage;
        if (usage == null) continue;
        for (final entry in usage.entries) {
          if (entry.estimatedQty <= 0) continue;
          final wastePct =
              (entry.estimatedQty - entry.usedQty) / entry.estimatedQty;
          samples
              .putIfAbsent(entry.itemId, () => <_WasteSample>[])
              .add(_WasteSample(
                dealerCode: job.dealerCode,
                description: entry.description,
                wastePct: wastePct,
              ));
        }
      }

      final out = <String, WasteStats>{};
      for (final entry in samples.entries) {
        final list = entry.value;
        final avg = list.fold<double>(0, (a, s) => a + s.wastePct) /
            list.length;

        String? best;
        String? worst;
        if (list.length > 1) {
          var minSample = list.first;
          var maxSample = list.first;
          for (final s in list) {
            if (s.wastePct < minSample.wastePct) minSample = s;
            if (s.wastePct > maxSample.wastePct) maxSample = s;
          }
          best = minSample.dealerCode;
          worst = maxSample.dealerCode;
        }

        out[entry.key] = WasteStats(
          itemId: entry.key,
          description: list.first.description,
          avgWastePct: avg,
          sampleCount: list.length,
          bestDealerCode: best,
          worstDealerCode: worst,
        );
      }
      return AsyncValue.data(out);
    },
  );
});

class _WasteSample {
  final String dealerCode;
  final String description;
  final double wastePct;
  const _WasteSample({
    required this.dealerCode,
    required this.description,
    required this.wastePct,
  });
}

// ─────────────────────────────────────────────────────────────────────────
// Network-wide rollup of inventory: total on-hand by materialId
// ─────────────────────────────────────────────────────────────────────────

class NetworkInventoryRow {
  final String materialId;
  final String displayName;
  final double totalOnHand;
  final double totalReserved;
  final double totalAvailable;

  /// True if ANY dealer is at-or-below their reorder threshold for this
  /// material — surfaces the network low-stock indicator on the table.
  final bool anyDealerLowStock;

  /// Map of dealerCode -> InventoryRecord for the per-dealer expansion row.
  final Map<String, InventoryRecord> perDealer;

  const NetworkInventoryRow({
    required this.materialId,
    required this.displayName,
    required this.totalOnHand,
    required this.totalReserved,
    required this.totalAvailable,
    required this.anyDealerLowStock,
    required this.perDealer,
  });
}

/// Joins [allDealerInventoryProvider] with [allMaterialCatalogProvider]
/// into per-material network rows.
final networkInventoryRowsProvider =
    Provider<AsyncValue<List<NetworkInventoryRow>>>((ref) {
  final invAsync = ref.watch(allDealerInventoryProvider);
  final catAsync = ref.watch(allMaterialCatalogProvider);

  if (invAsync.isLoading || catAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (invAsync.hasError) {
    return AsyncValue.error(
        invAsync.error!, invAsync.stackTrace ?? StackTrace.current);
  }
  if (catAsync.hasError) {
    return AsyncValue.error(
        catAsync.error!, catAsync.stackTrace ?? StackTrace.current);
  }

  final inv = invAsync.value ?? const {};
  final cat = catAsync.value ?? const <String, MaterialItem>{};

  // materialId -> list of (dealerCode, record)
  final byMaterial = <String, Map<String, InventoryRecord>>{};
  for (final entry in inv.entries) {
    final dealerCode = entry.key;
    for (final rec in entry.value) {
      byMaterial
          .putIfAbsent(rec.materialId, () => <String, InventoryRecord>{})[
              dealerCode] = rec;
    }
  }

  final rows = <NetworkInventoryRow>[];
  for (final entry in byMaterial.entries) {
    final materialId = entry.key;
    final perDealer = entry.value;
    var onHand = 0.0;
    var reserved = 0.0;
    var anyLow = false;
    for (final rec in perDealer.values) {
      onHand += rec.quantityOnHand;
      reserved += rec.quantityReserved;
      if (rec.quantityAvailable <= rec.reorderThreshold &&
          rec.reorderThreshold > 0) {
        anyLow = true;
      }
    }
    rows.add(NetworkInventoryRow(
      materialId: materialId,
      displayName: cat[materialId]?.name ?? materialId,
      totalOnHand: onHand,
      totalReserved: reserved,
      totalAvailable: onHand - reserved,
      anyDealerLowStock: anyLow,
      perDealer: perDealer,
    ));
  }

  rows.sort((a, b) => a.displayName.compareTo(b.displayName));
  return AsyncValue.data(rows);
});
