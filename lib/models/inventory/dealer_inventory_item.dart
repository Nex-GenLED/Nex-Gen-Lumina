import 'package:cloud_firestore/cloud_firestore.dart';

/// Per-dealer warehouse stock for a single SKU.
///
/// Stored at /dealers/{dealerCode}/sku_inventory/{sku}. Distinct from
/// the materialId-keyed /dealers/{dealerCode}/inventory used by the
/// Day-1/Day-2 install material checkout flow — that one tracks
/// per-job material commitments; this one tracks SKU-level on-hand
/// stock for the ordering pipeline.
///
/// `needed` is denormalized (computed on read elsewhere — typically
/// total_required_by_jobs - in_warehouse - on_order, clamped to 0)
/// and stored on the doc so dealers can query "show me items where
/// needed > 0" without fanning out to every open job.
class DealerInventoryItem {
  final String sku;
  final int inWarehouse;
  final int reserved;
  final int onTruck;
  final int onOrder;
  final int needed;
  final int reorderThreshold;
  final bool autoReorderEnabled;
  final int autoReorderQty;
  final DateTime? lastUpdated;

  const DealerInventoryItem({
    required this.sku,
    this.inWarehouse = 0,
    this.reserved = 0,
    this.onTruck = 0,
    this.onOrder = 0,
    this.needed = 0,
    this.reorderThreshold = 0,
    this.autoReorderEnabled = false,
    this.autoReorderQty = 0,
    this.lastUpdated,
  });

  /// Units physically on the shelf and not already reserved for a job.
  int get totalAvailable => inWarehouse - reserved;

  /// Below the dealer's configured reorder threshold (and a threshold
  /// has actually been set — 0 means "no threshold", not "always low").
  bool get isLow => reorderThreshold > 0 && totalAvailable <= reorderThreshold;

  /// Has unmet demand from scheduled jobs.
  bool get needsReorder => needed > 0;

  /// Auto-reorder eligible: feature enabled + below threshold.
  bool get isAutoReorderEligible =>
      autoReorderEnabled && reorderThreshold > 0 && isLow;

  factory DealerInventoryItem.fromJson(Map<String, dynamic> json) {
    return DealerInventoryItem(
      sku: json['sku'] as String? ?? '',
      inWarehouse: (json['in_warehouse'] as num?)?.toInt() ?? 0,
      reserved: (json['reserved'] as num?)?.toInt() ?? 0,
      onTruck: (json['on_truck'] as num?)?.toInt() ?? 0,
      onOrder: (json['on_order'] as num?)?.toInt() ?? 0,
      needed: (json['needed'] as num?)?.toInt() ?? 0,
      reorderThreshold: (json['reorder_threshold'] as num?)?.toInt() ?? 0,
      autoReorderEnabled: json['auto_reorder_enabled'] as bool? ?? false,
      autoReorderQty: (json['auto_reorder_qty'] as num?)?.toInt() ?? 0,
      lastUpdated: (json['last_updated'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'in_warehouse': inWarehouse,
        'reserved': reserved,
        'on_truck': onTruck,
        'on_order': onOrder,
        'needed': needed,
        'reorder_threshold': reorderThreshold,
        'auto_reorder_enabled': autoReorderEnabled,
        'auto_reorder_qty': autoReorderQty,
        if (lastUpdated != null) 'last_updated': Timestamp.fromDate(lastUpdated!),
      };

  DealerInventoryItem copyWith({
    int? inWarehouse,
    int? reserved,
    int? onTruck,
    int? onOrder,
    int? needed,
    int? reorderThreshold,
    bool? autoReorderEnabled,
    int? autoReorderQty,
    DateTime? lastUpdated,
  }) {
    return DealerInventoryItem(
      sku: sku,
      inWarehouse: inWarehouse ?? this.inWarehouse,
      reserved: reserved ?? this.reserved,
      onTruck: onTruck ?? this.onTruck,
      onOrder: onOrder ?? this.onOrder,
      needed: needed ?? this.needed,
      reorderThreshold: reorderThreshold ?? this.reorderThreshold,
      autoReorderEnabled: autoReorderEnabled ?? this.autoReorderEnabled,
      autoReorderQty: autoReorderQty ?? this.autoReorderQty,
      lastUpdated: lastUpdated ?? this.lastUpdated,
    );
  }
}
