import 'package:cloud_firestore/cloud_firestore.dart';

/// Nex-Gen master-warehouse on-hand for a single SKU. Stored at
/// /corporate_inventory/{sku}. Admin/owner-only at the rule layer.
///
/// `available` is intentionally NOT serialized — it's a computed
/// getter (on_hand minus reserved_for_orders) so the doc can never
/// drift out of sync with its inputs. If a denormalized `available`
/// field ever becomes necessary for query-side filtering, add it
/// alongside this getter and have writes maintain it explicitly.
class CorporateInventoryItem {
  final String sku;
  final int onHand;
  final int reservedForOrders;
  final int reorderPoint;
  final DateTime? lastUpdated;
  final DateTime? lastReceivedAt;

  const CorporateInventoryItem({
    required this.sku,
    this.onHand = 0,
    this.reservedForOrders = 0,
    this.reorderPoint = 0,
    this.lastUpdated,
    this.lastReceivedAt,
  });

  /// Units actually free to ship — on hand minus what's been
  /// committed to dealer orders that haven't shipped yet.
  int get available => onHand - reservedForOrders;

  /// Below the configured reorder threshold.
  bool get isLow => reorderPoint > 0 && available <= reorderPoint;

  /// Genuinely empty.
  bool get isOutOfStock => available <= 0;

  factory CorporateInventoryItem.fromJson(Map<String, dynamic> json) {
    return CorporateInventoryItem(
      sku: json['sku'] as String? ?? '',
      onHand: (json['on_hand'] as num?)?.toInt() ?? 0,
      reservedForOrders: (json['reserved_for_orders'] as num?)?.toInt() ?? 0,
      reorderPoint: (json['reorder_point'] as num?)?.toInt() ?? 0,
      lastUpdated: (json['last_updated'] as Timestamp?)?.toDate(),
      lastReceivedAt: (json['last_received_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'on_hand': onHand,
        'reserved_for_orders': reservedForOrders,
        'reorder_point': reorderPoint,
        if (lastUpdated != null) 'last_updated': Timestamp.fromDate(lastUpdated!),
        if (lastReceivedAt != null)
          'last_received_at': Timestamp.fromDate(lastReceivedAt!),
      };

  CorporateInventoryItem copyWith({
    int? onHand,
    int? reservedForOrders,
    int? reorderPoint,
    DateTime? lastUpdated,
    DateTime? lastReceivedAt,
  }) {
    return CorporateInventoryItem(
      sku: sku,
      onHand: onHand ?? this.onHand,
      reservedForOrders: reservedForOrders ?? this.reservedForOrders,
      reorderPoint: reorderPoint ?? this.reorderPoint,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      lastReceivedAt: lastReceivedAt ?? this.lastReceivedAt,
    );
  }
}
