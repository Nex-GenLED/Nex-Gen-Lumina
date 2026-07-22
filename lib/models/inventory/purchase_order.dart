import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle state for a Nex-Gen → supplier purchase order.
enum POStatus {
  ordered,
  partial,
  received;

  String toJson() {
    switch (this) {
      case POStatus.ordered:
        return 'ordered';
      case POStatus.partial:
        return 'partial';
      case POStatus.received:
        return 'received';
    }
  }

  static POStatus fromJson(String? raw) {
    switch (raw) {
      case 'ordered':
        return POStatus.ordered;
      case 'partial':
        return POStatus.partial;
      case 'received':
        return POStatus.received;
      default:
        return POStatus.ordered;
    }
  }

  String get label {
    switch (this) {
      case POStatus.ordered:
        return 'Ordered';
      case POStatus.partial:
        return 'Partial';
      case POStatus.received:
        return 'Received';
    }
  }
}

/// Single PO line item. `qty_received` advances over multiple receive
/// shipments — when it equals `qty_ordered` for every line, the PO
/// transitions to [POStatus.received] (until then it sits in
/// [POStatus.partial]).
class POLineItem {
  final String sku;
  final int qtyOrdered;
  final int qtyReceived;
  final double unitCost;

  const POLineItem({
    required this.sku,
    required this.qtyOrdered,
    this.qtyReceived = 0,
    this.unitCost = 0.0,
  });

  /// Whether this line is fully fulfilled.
  bool get isFullyReceived => qtyReceived >= qtyOrdered;

  /// Units still expected on this line.
  int get qtyOutstanding =>
      qtyOrdered - qtyReceived < 0 ? 0 : qtyOrdered - qtyReceived;

  factory POLineItem.fromJson(Map<String, dynamic> json) {
    return POLineItem(
      sku: json['sku'] as String? ?? '',
      qtyOrdered: (json['qty_ordered'] as num?)?.toInt() ?? 0,
      qtyReceived: (json['qty_received'] as num?)?.toInt() ?? 0,
      unitCost: (json['unit_cost'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'qty_ordered': qtyOrdered,
        'qty_received': qtyReceived,
        'unit_cost': unitCost,
      };

  POLineItem copyWith({int? qtyReceived, double? unitCost}) {
    return POLineItem(
      sku: sku,
      qtyOrdered: qtyOrdered,
      qtyReceived: qtyReceived ?? this.qtyReceived,
      unitCost: unitCost ?? this.unitCost,
    );
  }
}

/// Tyler's inbound order to a supplier (Gouly, etc.). Stored at
/// /purchase_orders/{poId}. Admin/owner-only — no dealer or installer
/// access at all (firestore.rules /purchase_orders/{poId} rule).
///
/// Receiving a PO line increments /corporate_inventory/{sku}.on_hand
/// for that SKU; partial-receive keeps the PO open with status
/// `partial`, full-receive sets it to `received`.
class PurchaseOrder {
  final String poId;
  final String supplierName;
  final POStatus status;
  final List<POLineItem> lineItems;
  final DateTime? expectedDelivery;
  final DateTime? receivedAt;
  final String createdBy;
  final DateTime? createdAt;
  final String? notes;

  const PurchaseOrder({
    required this.poId,
    required this.supplierName,
    this.status = POStatus.ordered,
    this.lineItems = const [],
    this.expectedDelivery,
    this.receivedAt,
    required this.createdBy,
    this.createdAt,
    this.notes,
  });

  /// True when every line is fully received. Source of truth for
  /// transitioning to [POStatus.received].
  bool get isAllReceived => lineItems.every((l) => l.isFullyReceived);

  /// True when at least one but not all lines have inbound stock.
  bool get isPartial =>
      !isAllReceived && lineItems.any((l) => l.qtyReceived > 0);

  factory PurchaseOrder.fromJson(Map<String, dynamic> json) {
    return PurchaseOrder(
      poId: json['po_id'] as String? ?? '',
      supplierName: json['supplier_name'] as String? ?? '',
      status: POStatus.fromJson(json['status'] as String?),
      lineItems: (json['line_items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(POLineItem.fromJson)
              .toList() ??
          const [],
      expectedDelivery: (json['expected_delivery'] as Timestamp?)?.toDate(),
      receivedAt: (json['received_at'] as Timestamp?)?.toDate(),
      createdBy: json['created_by'] as String? ?? '',
      createdAt: (json['created_at'] as Timestamp?)?.toDate(),
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'po_id': poId,
        'supplier_name': supplierName,
        'status': status.toJson(),
        'line_items': lineItems.map((l) => l.toJson()).toList(),
        if (expectedDelivery != null)
          'expected_delivery': Timestamp.fromDate(expectedDelivery!),
        if (receivedAt != null) 'received_at': Timestamp.fromDate(receivedAt!),
        'created_by': createdBy,
        if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
        'notes': notes,
      };

  PurchaseOrder copyWith({
    String? supplierName,
    POStatus? status,
    List<POLineItem>? lineItems,
    DateTime? expectedDelivery,
    DateTime? receivedAt,
    String? createdBy,
    DateTime? createdAt,
    String? notes,
  }) {
    return PurchaseOrder(
      poId: poId,
      supplierName: supplierName ?? this.supplierName,
      status: status ?? this.status,
      lineItems: lineItems ?? this.lineItems,
      expectedDelivery: expectedDelivery ?? this.expectedDelivery,
      receivedAt: receivedAt ?? this.receivedAt,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      notes: notes ?? this.notes,
    );
  }
}
