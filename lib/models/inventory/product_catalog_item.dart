import 'package:cloud_firestore/cloud_firestore.dart';

/// Single SKU in the global Nex-Gen LED catalog.
///
/// Stored at /product_catalog/{sku}. Schema is snake_case JSON; Dart
/// fields are camelCase. Read by every authenticated user; written
/// only by corporate user_role admins or admin/owner staff sessions
/// (firestore.rules /product_catalog/{sku} rule).
///
/// `voltage` is null for universal SKUs (rails, wire, accessories,
/// controllers). `voltage_specific` mirrors that distinction at the
/// schema level so query-side filtering doesn't need null-handling.
class ProductCatalogItem {
  final String sku;
  final String name;
  final String category;
  final String? subcategory;
  final String? voltage;
  final String? finish;
  final int packQty;
  final String packUnit;
  final double unitPrice;
  final bool isActive;
  final bool voltageSpecific;
  final String description;
  final String? goulyModel;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ProductCatalogItem({
    required this.sku,
    required this.name,
    required this.category,
    this.subcategory,
    this.voltage,
    this.finish,
    required this.packQty,
    required this.packUnit,
    required this.unitPrice,
    this.isActive = true,
    this.voltageSpecific = false,
    this.description = '',
    this.goulyModel,
    this.createdAt,
    this.updatedAt,
  });

  /// Number of packs needed to cover [unitsNeeded] units, rounding up.
  /// `pack_qty` of 50 + units 75 → 2 packs.
  int packsNeeded(int unitsNeeded) {
    if (packQty <= 0) return unitsNeeded > 0 ? 1 : 0;
    return (unitsNeeded / packQty).ceil();
  }

  /// Round `units` up to the next whole pack-quantity multiple.
  int roundUpToPackQty(int units) => packsNeeded(units) * packQty;

  /// Total price for [units], with pack-quantity rounding applied.
  double totalPrice(int units) => roundUpToPackQty(units) * unitPrice;

  factory ProductCatalogItem.fromJson(Map<String, dynamic> json) {
    return ProductCatalogItem(
      sku: json['sku'] as String? ?? '',
      name: json['name'] as String? ?? '',
      category: json['category'] as String? ?? '',
      subcategory: json['subcategory'] as String?,
      voltage: json['voltage'] as String?,
      finish: json['finish'] as String?,
      packQty: (json['pack_qty'] as num?)?.toInt() ?? 1,
      packUnit: json['pack_unit'] as String? ?? 'each',
      unitPrice: (json['unit_price'] as num?)?.toDouble() ?? 0.0,
      isActive: json['is_active'] as bool? ?? true,
      voltageSpecific: json['voltage_specific'] as bool? ?? false,
      description: json['description'] as String? ?? '',
      goulyModel: json['gouly_model'] as String?,
      createdAt: (json['created_at'] as Timestamp?)?.toDate(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toJson() => {
        'sku': sku,
        'name': name,
        'category': category,
        'subcategory': subcategory,
        'voltage': voltage,
        'finish': finish,
        'pack_qty': packQty,
        'pack_unit': packUnit,
        'unit_price': unitPrice,
        'is_active': isActive,
        'voltage_specific': voltageSpecific,
        'description': description,
        'gouly_model': goulyModel,
        if (createdAt != null) 'created_at': Timestamp.fromDate(createdAt!),
        if (updatedAt != null) 'updated_at': Timestamp.fromDate(updatedAt!),
      };

  ProductCatalogItem copyWith({
    String? name,
    String? category,
    String? subcategory,
    String? voltage,
    String? finish,
    int? packQty,
    String? packUnit,
    double? unitPrice,
    bool? isActive,
    bool? voltageSpecific,
    String? description,
    String? goulyModel,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return ProductCatalogItem(
      sku: sku,
      name: name ?? this.name,
      category: category ?? this.category,
      subcategory: subcategory ?? this.subcategory,
      voltage: voltage ?? this.voltage,
      finish: finish ?? this.finish,
      packQty: packQty ?? this.packQty,
      packUnit: packUnit ?? this.packUnit,
      unitPrice: unitPrice ?? this.unitPrice,
      isActive: isActive ?? this.isActive,
      voltageSpecific: voltageSpecific ?? this.voltageSpecific,
      description: description ?? this.description,
      goulyModel: goulyModel ?? this.goulyModel,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
