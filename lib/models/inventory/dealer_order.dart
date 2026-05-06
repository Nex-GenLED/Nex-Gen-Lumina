import 'package:cloud_firestore/cloud_firestore.dart';

/// Lifecycle state for a dealer-to-corporate order.
///
/// Wire format is snake_case (`payment_pending`); Dart naming follows
/// camelCase. fromJson/toJson handle the mapping; default on parse
/// errors is [draft] so a malformed doc never crashes a list view.
enum OrderStatus {
  draft,
  submitted,
  paymentPending,
  paymentConfirmed,
  processing,
  shipped,
  received;

  String toJson() {
    switch (this) {
      case OrderStatus.draft:
        return 'draft';
      case OrderStatus.submitted:
        return 'submitted';
      case OrderStatus.paymentPending:
        return 'payment_pending';
      case OrderStatus.paymentConfirmed:
        return 'payment_confirmed';
      case OrderStatus.processing:
        return 'processing';
      case OrderStatus.shipped:
        return 'shipped';
      case OrderStatus.received:
        return 'received';
    }
  }

  static OrderStatus fromJson(String? raw) {
    switch (raw) {
      case 'draft':
        return OrderStatus.draft;
      case 'submitted':
        return OrderStatus.submitted;
      case 'payment_pending':
        return OrderStatus.paymentPending;
      case 'payment_confirmed':
        return OrderStatus.paymentConfirmed;
      case 'processing':
        return OrderStatus.processing;
      case 'shipped':
        return OrderStatus.shipped;
      case 'received':
        return OrderStatus.received;
      default:
        return OrderStatus.draft;
    }
  }

  /// Human-readable label for status badges.
  String get label {
    switch (this) {
      case OrderStatus.draft:
        return 'Draft';
      case OrderStatus.submitted:
        return 'Submitted';
      case OrderStatus.paymentPending:
        return 'Payment Pending';
      case OrderStatus.paymentConfirmed:
        return 'Payment Confirmed';
      case OrderStatus.processing:
        return 'Processing';
      case OrderStatus.shipped:
        return 'Shipped';
      case OrderStatus.received:
        return 'Received';
    }
  }
}

/// Single line item on a [DealerOrder]. Carries denormalized name +
/// pack info so older orders keep rendering intelligibly even after
/// a SKU is renamed or its pack_qty is updated in /product_catalog.
class DealerOrderLineItem {
  final String sku;
  final String name;
  final int quantityOrdered;
  final int packQty;
  final int packsOrdered;
  final double unitPrice;
  final double lineTotal;

  const DealerOrderLineItem({
    required this.sku,
    required this.name,
    required this.quantityOrdered,
    required this.packQty,
    required this.packsOrdered,
    required this.unitPrice,
    required this.lineTotal,
  });

  factory DealerOrderLineItem.fromJson(Map<String, dynamic> json) {
    return DealerOrderLineItem(
      sku: json['sku'] as String? ?? '',
      name: json['name'] as String? ?? '',
      quantityOrdered: (json['quantity_ordered'] as num?)?.toInt() ?? 0,
      packQty: (json['pack_qty'] as num?)?.toInt() ?? 1,
      packsOrdered: (json['packs_ordered'] as num?)?.toInt() ?? 0,
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      lineTotal: (json['line_total'] as num?)?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'quantity_ordered': quantityOrdered,
        'pack_qty': packQty,
        'packs_ordered': packsOrdered,
        'unit_price': unitPrice,
        'line_total': lineTotal,
      };

  DealerOrderLineItem copyWith({
    int? quantityOrdered,
    int? packsOrdered,
    double? unitPrice,
    double? lineTotal,
  }) {
    return DealerOrderLineItem(
      sku: sku,
      name: name,
      quantityOrdered: quantityOrdered ?? this.quantityOrdered,
      packQty: packQty,
      packsOrdered: packsOrdered ?? this.packsOrdered,
      unitPrice: unitPrice ?? this.unitPrice,
      lineTotal: lineTotal ?? this.lineTotal,
    );
  }
}

/// Top-level dealer-to-corporate order. Stored at /dealer_orders/{orderId}.
///
/// Full lifecycle:
///   draft → submitted → payment_pending → payment_confirmed
///   → processing → shipped → received
///
/// Stakeholder identity (read/update access) is verified at the rule
/// layer — any of: matching dealer_code on the user doc,
/// installer_dealer_code, or staff custom-token claim. Admin/owner
/// always reads/updates.
class DealerOrder {
  final String orderId;
  final String dealerCode;
  final String dealerName;
  final OrderStatus status;
  final List<DealerOrderLineItem> lineItems;
  final double subtotal;
  final double shippingCost;
  final String? shippingCarrier;
  final String? trackingNumber;
  final double orderTotal;
  final String paymentStatus;
  final String? paymentConfirmedBy;
  final DateTime? paymentConfirmedAt;
  final DateTime? submittedAt;
  final String? approvedBy;
  final DateTime? approvedAt;
  final DateTime? shippedAt;
  final DateTime? receivedAt;
  final String? notes;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const DealerOrder({
    required this.orderId,
    required this.dealerCode,
    required this.dealerName,
    this.status = OrderStatus.draft,
    this.lineItems = const [],
    this.subtotal = 0.0,
    this.shippingCost = 0.0,
    this.shippingCarrier,
    this.trackingNumber,
    this.orderTotal = 0.0,
    this.paymentStatus = 'pending',
    this.paymentConfirmedBy,
    this.paymentConfirmedAt,
    this.submittedAt,
    this.approvedBy,
    this.approvedAt,
    this.shippedAt,
    this.receivedAt,
    this.notes,
    this.createdAt,
    this.updatedAt,
  });

  /// Eligible to submit: still a draft and has at least one line item.
  bool get canSubmit =>
      status == OrderStatus.draft && lineItems.isNotEmpty;

  /// Waiting on the dealer to send payment OR for corporate to mark
  /// payment received. Drives the amber banner on the dealer order
  /// history screen and the Payment Pending tab on the corporate side.
  bool get awaitingPayment =>
      status == OrderStatus.submitted ||
      status == OrderStatus.paymentPending;

  /// Total unit count across every line item.
  int get totalUnits =>
      lineItems.fold(0, (acc, l) => acc + l.quantityOrdered);

  factory DealerOrder.fromJson(Map<String, dynamic> json) {
    return DealerOrder(
      orderId: json['order_id'] as String? ?? '',
      dealerCode: json['dealer_code'] as String? ?? '',
      dealerName: json['dealer_name'] as String? ?? '',
      status: OrderStatus.fromJson(json['status'] as String?),
      lineItems: (json['line_items'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map(DealerOrderLineItem.fromJson)
              .toList() ??
          const [],
      subtotal: (json['subtotal'] as num?)?.toDouble() ?? 0.0,
      shippingCost: (json['shipping_cost'] as num?)?.toDouble() ?? 0.0,
      shippingCarrier: json['shipping_carrier'] as String?,
      trackingNumber: json['tracking_number'] as String?,
      orderTotal: (json['order_total'] as num?)?.toDouble() ?? 0.0,
      paymentStatus: json['payment_status'] as String? ?? 'pending',
      paymentConfirmedBy: json['payment_confirmed_by'] as String?,
      paymentConfirmedAt:
          (json['payment_confirmed_at'] as Timestamp?)?.toDate(),
      submittedAt: (json['submitted_at'] as Timestamp?)?.toDate(),
      approvedBy: json['approved_by'] as String?,
      approvedAt: (json['approved_at'] as Timestamp?)?.toDate(),
      shippedAt: (json['shipped_at'] as Timestamp?)?.toDate(),
      receivedAt: (json['received_at'] as Timestamp?)?.toDate(),
      notes: json['notes'] as String?,
      createdAt: (json['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'order_id': orderId,
        'dealer_code': dealerCode,
        'dealer_name': dealerName,
        'status': status.toJson(),
        'line_items': lineItems.map((l) => l.toJson()).toList(),
        'subtotal': subtotal,
        'shipping_cost': shippingCost,
        'shipping_carrier': shippingCarrier,
        'tracking_number': trackingNumber,
        'order_total': orderTotal,
        'payment_status': paymentStatus,
        'payment_confirmed_by': paymentConfirmedBy,
        if (paymentConfirmedAt != null)
          'payment_confirmed_at': Timestamp.fromDate(paymentConfirmedAt!),
        if (submittedAt != null)
          'submitted_at': Timestamp.fromDate(submittedAt!),
        'approved_by': approvedBy,
        if (approvedAt != null) 'approved_at': Timestamp.fromDate(approvedAt!),
        if (shippedAt != null) 'shipped_at': Timestamp.fromDate(shippedAt!),
        if (receivedAt != null) 'received_at': Timestamp.fromDate(receivedAt!),
        'notes': notes,
        if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
      };

  DealerOrder copyWith({
    String? dealerName,
    OrderStatus? status,
    List<DealerOrderLineItem>? lineItems,
    double? subtotal,
    double? shippingCost,
    String? shippingCarrier,
    String? trackingNumber,
    double? orderTotal,
    String? paymentStatus,
    String? paymentConfirmedBy,
    DateTime? paymentConfirmedAt,
    DateTime? submittedAt,
    String? approvedBy,
    DateTime? approvedAt,
    DateTime? shippedAt,
    DateTime? receivedAt,
    String? notes,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return DealerOrder(
      orderId: orderId,
      dealerCode: dealerCode,
      dealerName: dealerName ?? this.dealerName,
      status: status ?? this.status,
      lineItems: lineItems ?? this.lineItems,
      subtotal: subtotal ?? this.subtotal,
      shippingCost: shippingCost ?? this.shippingCost,
      shippingCarrier: shippingCarrier ?? this.shippingCarrier,
      trackingNumber: trackingNumber ?? this.trackingNumber,
      orderTotal: orderTotal ?? this.orderTotal,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentConfirmedBy: paymentConfirmedBy ?? this.paymentConfirmedBy,
      paymentConfirmedAt: paymentConfirmedAt ?? this.paymentConfirmedAt,
      submittedAt: submittedAt ?? this.submittedAt,
      approvedBy: approvedBy ?? this.approvedBy,
      approvedAt: approvedAt ?? this.approvedAt,
      shippedAt: shippedAt ?? this.shippedAt,
      receivedAt: receivedAt ?? this.receivedAt,
      notes: notes ?? this.notes,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
