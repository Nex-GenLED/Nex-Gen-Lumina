import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────
// 1. MaterialCategory enum
// ─────────────────────────────────────────

enum MaterialCategory {
  lightPcs,       // 1-PCS, 5-PCS, 10-PCS pixel nodes
  ropeLighting,   // Diffused rope light
  railOnePiece,   // 1-piece aluminum rails (per color)
  railTwoPiece,   // 2-piece aluminum rails (per color)
  connectorWire,  // Extension wires (per length)
  accessories,    // T/Y connectors, amplifier, radar sensor
  controller,     // Controller unit
  powerSupply,    // 350W and 600W supplies
}

// ─────────────────────────────────────────
// 2. MaterialUnit enum
// ─────────────────────────────────────────

enum MaterialUnit {
  each,   // individual unit (lights, rails, accessories, etc.)
  piece,  // rope light piece (5m per piece)
}

// ─────────────────────────────────────────
// 3. JobMaterialStatus enum
// ─────────────────────────────────────────

enum JobMaterialStatus { draft, approved, checkedOut, day1Complete, complete }

// ─────────────────────────────────────────
// 4. MaterialItem class
// ─────────────────────────────────────────

class MaterialItem {
  final String id;
  final String name;
  final MaterialCategory category;
  final MaterialUnit unit;
  final double unitCostCents;
  final double overageRate;
  final String? sku;
  final String? colorVariant;   // 'black'|'brown'|'beige'|'white'|'navy'|'silver'|'grey' — null if not a rail
  final String? lengthVariant;  // '1ft'|'2ft'|'5ft'|'10ft'|'20ft' — null if not a connector wire
  final bool isActive;

  const MaterialItem({
    required this.id,
    required this.name,
    required this.category,
    required this.unit,
    required this.unitCostCents,
    this.overageRate = 0.0,
    this.sku,
    this.colorVariant,
    this.lengthVariant,
    this.isActive = true,
  });

  factory MaterialItem.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return MaterialItem(
      id: doc.id,
      name: d['name'] ?? '',
      category: MaterialCategory.values.byName(d['category'] ?? 'lightPcs'),
      unit: MaterialUnit.values.byName(d['unit'] ?? 'each'),
      unitCostCents: (d['unitCostCents'] as num?)?.toDouble() ?? 0,
      overageRate: (d['overageRate'] as num?)?.toDouble() ?? 0,
      sku: d['sku'],
      colorVariant: d['colorVariant'],
      lengthVariant: d['lengthVariant'],
      isActive: d['isActive'] ?? true,
    );
  }

  Map<String, dynamic> toFirestore() => {
    'name': name,
    'category': category.name,
    'unit': unit.name,
    'unitCostCents': unitCostCents,
    'overageRate': overageRate,
    'sku': sku,
    'colorVariant': colorVariant,
    'lengthVariant': lengthVariant,
    'isActive': isActive,
  };

  MaterialItem copyWith({
    String? id,
    String? name,
    MaterialCategory? category,
    MaterialUnit? unit,
    double? unitCostCents,
    double? overageRate,
    String? sku,
    String? colorVariant,
    String? lengthVariant,
    bool? isActive,
  }) => MaterialItem(
    id: id ?? this.id,
    name: name ?? this.name,
    category: category ?? this.category,
    unit: unit ?? this.unit,
    unitCostCents: unitCostCents ?? this.unitCostCents,
    overageRate: overageRate ?? this.overageRate,
    sku: sku ?? this.sku,
    colorVariant: colorVariant ?? this.colorVariant,
    lengthVariant: lengthVariant ?? this.lengthVariant,
    isActive: isActive ?? this.isActive,
  );
}

// ─────────────────────────────────────────
// 5. InventoryRecord class
// ─────────────────────────────────────────

class InventoryRecord {
  final String materialId;
  double quantityOnHand;
  double quantityReserved;
  double reorderThreshold;
  DateTime lastUpdated;
  String lastUpdatedBy;

  InventoryRecord({
    required this.materialId,
    required this.quantityOnHand,
    this.quantityReserved = 0,
    this.reorderThreshold = 0,
    required this.lastUpdated,
    required this.lastUpdatedBy,
  });

  double get quantityAvailable => quantityOnHand - quantityReserved;

  factory InventoryRecord.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return InventoryRecord(
      materialId: doc.id,
      quantityOnHand: (d['quantityOnHand'] as num?)?.toDouble() ?? 0,
      quantityReserved: (d['quantityReserved'] as num?)?.toDouble() ?? 0,
      reorderThreshold: (d['reorderThreshold'] as num?)?.toDouble() ?? 0,
      lastUpdated: (d['lastUpdated'] as Timestamp?)?.toDate() ?? DateTime.now(),
      lastUpdatedBy: d['lastUpdatedBy'] ?? '',
    );
  }

  Map<String, dynamic> toFirestore() => {
    'quantityOnHand': quantityOnHand,
    'quantityReserved': quantityReserved,
    'reorderThreshold': reorderThreshold,
    'lastUpdated': Timestamp.fromDate(lastUpdated),
    'lastUpdatedBy': lastUpdatedBy,
  };
}

// ─────────────────────────────────────────
// 6. JobMaterialLine class
// ─────────────────────────────────────────

class JobMaterialLine {
  final String materialId;
  final String materialName;
  final MaterialUnit unit;
  final double calculatedQty;
  final double overageQty;
  double checkedOutQty;
  double usedDay1;
  double usedDay2;
  double returnedQty;

  JobMaterialLine({
    required this.materialId,
    required this.materialName,
    required this.unit,
    required this.calculatedQty,
    this.overageQty = 0,
    this.checkedOutQty = 0,
    this.usedDay1 = 0,
    this.usedDay2 = 0,
    this.returnedQty = 0,
  });

  double get totalUsed => usedDay1 + usedDay2;
  double get waste => checkedOutQty - totalUsed - returnedQty;

  Map<String, dynamic> toMap() => {
    'materialId': materialId,
    'materialName': materialName,
    'unit': unit.name,
    'calculatedQty': calculatedQty,
    'overageQty': overageQty,
    'checkedOutQty': checkedOutQty,
    'usedDay1': usedDay1,
    'usedDay2': usedDay2,
    'returnedQty': returnedQty,
  };

  factory JobMaterialLine.fromMap(Map<String, dynamic> m) => JobMaterialLine(
    materialId: m['materialId'] ?? '',
    materialName: m['materialName'] ?? '',
    unit: MaterialUnit.values.byName(m['unit'] ?? 'each'),
    calculatedQty: (m['calculatedQty'] as num?)?.toDouble() ?? 0,
    overageQty: (m['overageQty'] as num?)?.toDouble() ?? 0,
    checkedOutQty: (m['checkedOutQty'] as num?)?.toDouble() ?? 0,
    usedDay1: (m['usedDay1'] as num?)?.toDouble() ?? 0,
    usedDay2: (m['usedDay2'] as num?)?.toDouble() ?? 0,
    returnedQty: (m['returnedQty'] as num?)?.toDouble() ?? 0,
  );

  JobMaterialLine copyWith({
    String? materialId,
    String? materialName,
    MaterialUnit? unit,
    double? calculatedQty,
    double? overageQty,
    double? checkedOutQty,
    double? usedDay1,
    double? usedDay2,
    double? returnedQty,
  }) => JobMaterialLine(
    materialId: materialId ?? this.materialId,
    materialName: materialName ?? this.materialName,
    unit: unit ?? this.unit,
    calculatedQty: calculatedQty ?? this.calculatedQty,
    overageQty: overageQty ?? this.overageQty,
    checkedOutQty: checkedOutQty ?? this.checkedOutQty,
    usedDay1: usedDay1 ?? this.usedDay1,
    usedDay2: usedDay2 ?? this.usedDay2,
    returnedQty: returnedQty ?? this.returnedQty,
  );
}

// ─────────────────────────────────────────
// 7. JobMaterialList class
// ─────────────────────────────────────────

class JobMaterialList {
  final String jobId;
  final String jobNumber;
  final String dealerCode;
  JobMaterialStatus status;
  final List<JobMaterialLine> lines;
  final String calculatedBy;
  final DateTime calculatedAt;
  String? checkedOutBy;
  DateTime? checkedOutAt;
  String? day1CheckInBy;
  DateTime? day1CheckInAt;
  String? finalCheckInBy;
  DateTime? finalCheckInAt;
  String? notes;

  JobMaterialList({
    required this.jobId,
    required this.jobNumber,
    required this.dealerCode,
    this.status = JobMaterialStatus.draft,
    required this.lines,
    required this.calculatedBy,
    required this.calculatedAt,
    this.checkedOutBy,
    this.checkedOutAt,
    this.day1CheckInBy,
    this.day1CheckInAt,
    this.finalCheckInBy,
    this.finalCheckInAt,
    this.notes,
  });

  factory JobMaterialList.fromFirestore(DocumentSnapshot doc) {
    final d = doc.data() as Map<String, dynamic>;
    return JobMaterialList(
      jobId: doc.id,
      jobNumber: d['jobNumber'] ?? '',
      dealerCode: d['dealerCode'] ?? '',
      status: JobMaterialStatus.values.byName(d['status'] ?? 'draft'),
      lines: (d['lines'] as List? ?? [])
          .map((e) => JobMaterialLine.fromMap(e as Map<String, dynamic>))
          .toList(),
      calculatedBy: d['calculatedBy'] ?? '',
      calculatedAt: (d['calculatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      checkedOutBy: d['checkedOutBy'],
      checkedOutAt: (d['checkedOutAt'] as Timestamp?)?.toDate(),
      day1CheckInBy: d['day1CheckInBy'],
      day1CheckInAt: (d['day1CheckInAt'] as Timestamp?)?.toDate(),
      finalCheckInBy: d['finalCheckInBy'],
      finalCheckInAt: (d['finalCheckInAt'] as Timestamp?)?.toDate(),
      notes: d['notes'],
    );
  }

  Map<String, dynamic> toFirestore() => {
    'jobNumber': jobNumber,
    'dealerCode': dealerCode,
    'status': status.name,
    'lines': lines.map((l) => l.toMap()).toList(),
    'calculatedBy': calculatedBy,
    'calculatedAt': Timestamp.fromDate(calculatedAt),
    'checkedOutBy': checkedOutBy,
    'checkedOutAt': checkedOutAt != null ? Timestamp.fromDate(checkedOutAt!) : null,
    'day1CheckInBy': day1CheckInBy,
    'day1CheckInAt': day1CheckInAt != null ? Timestamp.fromDate(day1CheckInAt!) : null,
    'finalCheckInBy': finalCheckInBy,
    'finalCheckInAt': finalCheckInAt != null ? Timestamp.fromDate(finalCheckInAt!) : null,
    'notes': notes,
  };
}
