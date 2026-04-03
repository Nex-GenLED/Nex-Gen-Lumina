import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────
// 1. ProductType enum
// ─────────────────────────────────────────

enum ProductType { roofline, diffusedRope, custom }

extension ProductTypeX on ProductType {
  String get label => const {
    ProductType.roofline: 'Roofline (9" spacing)',
    ProductType.diffusedRope: 'Diffused rope light',
    ProductType.custom: 'Custom',
  }[this]!;

  double get pixelsPerFoot => const {
    ProductType.roofline: 1.333,   // 12 pixels / 9 inches
    ProductType.diffusedRope: 18.0,
    ProductType.custom: 0.0,       // user-supplied
  }[this]!;
}

// ─────────────────────────────────────────
// 2. ColorPreset enum
// ─────────────────────────────────────────

enum ColorPreset { rgbw, warmWhite, coolWhite, fullRgb }

extension ColorPresetX on ColorPreset {
  String get label => const {
    ColorPreset.rgbw: 'RGBW',
    ColorPreset.warmWhite: 'Warm white',
    ColorPreset.coolWhite: 'Cool white',
    ColorPreset.fullRgb: 'Full RGB',
  }[this]!;
}

// ─────────────────────────────────────────
// 3. WireGauge enum
// ─────────────────────────────────────────

enum WireGauge { direct, g14_2, g12_2, g10_2, exceeds }

extension WireGaugeX on WireGauge {
  String get label => const {
    WireGauge.direct: 'Direct',
    WireGauge.g14_2: '14/2',
    WireGauge.g12_2: '12/2',
    WireGauge.g10_2: '10/2',
    WireGauge.exceeds: 'EXCEEDS 140ft',
  }[this]!;

  static WireGauge fromDistance(double distFt) {
    if (distFt <= 0) return WireGauge.direct;
    if (distFt <= 30) return WireGauge.g14_2;
    if (distFt <= 90) return WireGauge.g12_2;
    if (distFt <= 140) return WireGauge.g10_2;
    return WireGauge.exceeds;
  }
}

// ─────────────────────────────────────────
// 4. RailType enum
// ─────────────────────────────────────────

enum RailType {
  onePiece,   // Aluminum 1-piece rail, 1m per piece
  twoPiece,   // Aluminum 2-piece rail, 1m per piece
  none,       // No rail — used for rope light zones
}

extension RailTypeX on RailType {
  String get label => const {
    RailType.onePiece: '1-Piece Rail',
    RailType.twoPiece: '2-Piece Rail',
    RailType.none: 'None',
  }[this]!;
}

// ─────────────────────────────────────────
// 5. RailColor enum
// ─────────────────────────────────────────

enum RailColor {
  black,
  brown,
  beige,
  white,
  navy,
  silver,
  grey,
  none,       // No color — used when railType == none
}

extension RailColorX on RailColor {
  String get label => const {
    RailColor.black: 'Black',
    RailColor.brown: 'Brown',
    RailColor.beige: 'Beige',
    RailColor.white: 'White',
    RailColor.navy: 'Navy',
    RailColor.silver: 'Silver',
    RailColor.grey: 'Grey',
    RailColor.none: 'None',
  }[this]!;
}

// ─────────────────────────────────────────
// 6. OutletType enum
// ─────────────────────────────────────────

enum OutletType { existing, newRequired }

extension OutletTypeX on OutletType {
  String get label => const {
    OutletType.existing: 'Existing outlet',
    OutletType.newRequired: 'New outlet needed',
  }[this]!;
}

// ─────────────────────────────────────────
// 5. InjectionPoint class
// ─────────────────────────────────────────

class InjectionPoint {
  final String id;
  final double positionFt;        // position along the run
  final bool servedByController;  // true = controller, false = additional supply
  final WireGauge wireGauge;
  final double wireRunFt;         // distance from mount to this point
  final String architecturalNote; // salesperson field note

  const InjectionPoint({
    required this.id,
    required this.positionFt,
    required this.servedByController,
    required this.wireGauge,
    required this.wireRunFt,
    this.architecturalNote = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'positionFt': positionFt,
    'servedByController': servedByController,
    'wireGauge': wireGauge.name,
    'wireRunFt': wireRunFt,
    'architecturalNote': architecturalNote,
  };

  factory InjectionPoint.fromJson(Map<String, dynamic> j) => InjectionPoint(
    id: j['id'],
    positionFt: (j['positionFt'] as num).toDouble(),
    servedByController: j['servedByController'] ?? true,
    wireGauge: WireGauge.values.byName(j['wireGauge'] ?? 'direct'),
    wireRunFt: (j['wireRunFt'] as num).toDouble(),
    architecturalNote: j['architecturalNote'] ?? '',
  );
}

// ─────────────────────────────────────────
// 6. PowerMount class
// ─────────────────────────────────────────

class PowerMount {
  final String id;
  final double positionFt;
  final bool isController;        // true = primary controller mount
  final String supplySize;        // '350w' | '600w' | 'controller'
  final List<String> servesInjectionIds;
  final OutletType outletType;
  final String outletNote;
  final String mountLocationNote;

  const PowerMount({
    required this.id,
    required this.positionFt,
    required this.isController,
    required this.supplySize,
    required this.servesInjectionIds,
    this.outletType = OutletType.existing,
    this.outletNote = '',
    this.mountLocationNote = '',
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'positionFt': positionFt,
    'isController': isController,
    'supplySize': supplySize,
    'servesInjectionIds': servesInjectionIds,
    'outletType': outletType.name,
    'outletNote': outletNote,
    'mountLocationNote': mountLocationNote,
  };

  factory PowerMount.fromJson(Map<String, dynamic> j) => PowerMount(
    id: j['id'],
    positionFt: (j['positionFt'] as num).toDouble(),
    isController: j['isController'] ?? false,
    supplySize: j['supplySize'] ?? '350w',
    servesInjectionIds: List<String>.from(j['servesInjectionIds'] ?? []),
    outletType: OutletType.values.byName(j['outletType'] ?? 'existing'),
    outletNote: j['outletNote'] ?? '',
    mountLocationNote: j['mountLocationNote'] ?? '',
  );
}

// ─────────────────────────────────────────
// 7. InstallZone class
// ─────────────────────────────────────────

class InstallZone {
  final String id;
  final String name;              // e.g. 'Front roofline'
  final double runLengthFt;
  final ProductType productType;
  final double pixelsPerFoot;     // overrides productType default for custom
  final ColorPreset colorPreset;
  final List<InjectionPoint> injections;
  final List<PowerMount> mounts;
  final List<String> photoUrls;
  final String notes;
  final double priceUsd;
  final RailType railType;
  final RailColor railColor;
  final double connectorRunFt;   // distance from controller/previous zone to start of this zone (ft)

  const InstallZone({
    required this.id,
    required this.name,
    required this.runLengthFt,
    required this.productType,
    required this.pixelsPerFoot,
    required this.colorPreset,
    required this.injections,
    required this.mounts,
    required this.photoUrls,
    this.notes = '',
    this.priceUsd = 0.0,
    this.railType = RailType.none,
    this.railColor = RailColor.none,
    this.connectorRunFt = 0.0,
  });

  int get totalPixels => (runLengthFt * pixelsPerFoot).round();

  int get controllerSlotCount =>
      injections.where((i) => i.servedByController).length;

  Map<String, dynamic> toJson() => {
    'id': id,
    'name': name,
    'runLengthFt': runLengthFt,
    'productType': productType.name,
    'pixelsPerFoot': pixelsPerFoot,
    'colorPreset': colorPreset.name,
    'injections': injections.map((i) => i.toJson()).toList(),
    'mounts': mounts.map((m) => m.toJson()).toList(),
    'photoUrls': photoUrls,
    'notes': notes,
    'priceUsd': priceUsd,
    'railType': railType.name,
    'railColor': railColor.name,
    'connectorRunFt': connectorRunFt,
  };

  factory InstallZone.fromJson(Map<String, dynamic> j) => InstallZone(
    id: j['id'],
    name: j['name'],
    runLengthFt: (j['runLengthFt'] as num).toDouble(),
    productType: ProductType.values.byName(j['productType'] ?? 'roofline'),
    pixelsPerFoot: (j['pixelsPerFoot'] as num).toDouble(),
    colorPreset: ColorPreset.values.byName(j['colorPreset'] ?? 'rgbw'),
    injections: (j['injections'] as List? ?? [])
        .map((e) => InjectionPoint.fromJson(e)).toList(),
    mounts: (j['mounts'] as List? ?? [])
        .map((e) => PowerMount.fromJson(e)).toList(),
    photoUrls: List<String>.from(j['photoUrls'] ?? []),
    notes: j['notes'] ?? '',
    priceUsd: (j['priceUsd'] as num?)?.toDouble() ?? 0.0,
    railType: RailType.values.byName(j['railType'] ?? 'none'),
    railColor: RailColor.values.byName(j['railColor'] ?? 'none'),
    connectorRunFt: (j['connectorRunFt'] as num?)?.toDouble() ?? 0.0,
  );
}

// ─────────────────────────────────────────
// 8. SalesProspect class
// ─────────────────────────────────────────

class SalesProspect {
  final String id;
  final String firstName;
  final String lastName;
  final String email;
  final String phone;
  final String address;
  final String city;
  final String state;
  final String zipCode;
  final String referrerUid;       // empty string if no referral
  final String referralCode;      // the LUM-XXXX code entered
  final List<String> homePhotoUrls;
  final String salespersonNotes;
  final DateTime createdAt;

  String get fullName => '$firstName $lastName';

  const SalesProspect({
    required this.id,
    required this.firstName,
    required this.lastName,
    required this.email,
    required this.phone,
    required this.address,
    required this.city,
    required this.state,
    required this.zipCode,
    this.referrerUid = '',
    this.referralCode = '',
    this.homePhotoUrls = const [],
    this.salespersonNotes = '',
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'firstName': firstName,
    'lastName': lastName,
    'email': email,
    'phone': phone,
    'address': address,
    'city': city,
    'state': state,
    'zipCode': zipCode,
    'referrerUid': referrerUid,
    'referralCode': referralCode,
    'homePhotoUrls': homePhotoUrls,
    'salespersonNotes': salespersonNotes,
    'createdAt': Timestamp.fromDate(createdAt),
  };

  factory SalesProspect.fromJson(Map<String, dynamic> j) => SalesProspect(
    id: j['id'] ?? '',
    firstName: j['firstName'] ?? '',
    lastName: j['lastName'] ?? '',
    email: j['email'] ?? '',
    phone: j['phone'] ?? '',
    address: j['address'] ?? '',
    city: j['city'] ?? '',
    state: j['state'] ?? '',
    zipCode: j['zipCode'] ?? '',
    referrerUid: j['referrerUid'] ?? '',
    referralCode: j['referralCode'] ?? '',
    homePhotoUrls: List<String>.from(j['homePhotoUrls'] ?? []),
    salespersonNotes: j['salespersonNotes'] ?? '',
    createdAt: (j['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );
}

// ─────────────────────────────────────────
// 9. SalesJobStatus enum
// ─────────────────────────────────────────

enum SalesJobStatus {
  draft,
  estimateSent,
  estimateSigned,
  prewireScheduled,
  prewireComplete,
  installComplete,
}

extension SalesJobStatusX on SalesJobStatus {
  String get label => const {
    SalesJobStatus.draft: 'Draft',
    SalesJobStatus.estimateSent: 'Estimate sent',
    SalesJobStatus.estimateSigned: 'Signed',
    SalesJobStatus.prewireScheduled: 'Pre-wire scheduled',
    SalesJobStatus.prewireComplete: 'Pre-wire complete',
    SalesJobStatus.installComplete: 'Install complete',
  }[this]!;

  static SalesJobStatus fromString(String s) =>
      SalesJobStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => SalesJobStatus.draft,
      );
}

// ─────────────────────────────────────────
// 10. SalesJob class
// ─────────────────────────────────────────

class SalesJob {
  final String id;                // Firestore doc ID
  final String jobNumber;         // e.g. 'NXG-0847'
  final String dealerCode;
  final String salespersonUid;
  final SalesProspect prospect;
  final List<InstallZone> zones;
  final SalesJobStatus status;
  final double totalPriceUsd;
  final DateTime? estimateSentAt;
  final DateTime? estimateSignedAt;
  final String? customerSignatureUrl;
  final DateTime? day1Date;
  final DateTime? day2Date;
  final DateTime createdAt;
  final DateTime updatedAt;

  double get calculatedTotal =>
      zones.fold(0.0, (acc, z) => acc + z.priceUsd);

  int get totalControllerSlotsUsed =>
      zones.fold(0, (acc, z) => acc + z.controllerSlotCount);

  const SalesJob({
    required this.id,
    required this.jobNumber,
    required this.dealerCode,
    required this.salespersonUid,
    required this.prospect,
    required this.zones,
    required this.status,
    required this.totalPriceUsd,
    this.estimateSentAt,
    this.estimateSignedAt,
    this.customerSignatureUrl,
    this.day1Date,
    this.day2Date,
    required this.createdAt,
    required this.updatedAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'jobNumber': jobNumber,
    'dealerCode': dealerCode,
    'salespersonUid': salespersonUid,
    'prospect': prospect.toJson(),
    'zones': zones.map((z) => z.toJson()).toList(),
    'status': status.name,
    'totalPriceUsd': totalPriceUsd,
    'estimateSentAt': estimateSentAt != null
        ? Timestamp.fromDate(estimateSentAt!) : null,
    'estimateSignedAt': estimateSignedAt != null
        ? Timestamp.fromDate(estimateSignedAt!) : null,
    'customerSignatureUrl': customerSignatureUrl,
    'day1Date': day1Date != null ? Timestamp.fromDate(day1Date!) : null,
    'day2Date': day2Date != null ? Timestamp.fromDate(day2Date!) : null,
    'createdAt': Timestamp.fromDate(createdAt),
    'updatedAt': Timestamp.fromDate(updatedAt),
  };

  factory SalesJob.fromJson(Map<String, dynamic> j) => SalesJob(
    id: j['id'] ?? '',
    jobNumber: j['jobNumber'] ?? '',
    dealerCode: j['dealerCode'] ?? '',
    salespersonUid: j['salespersonUid'] ?? '',
    prospect: SalesProspect.fromJson(j['prospect'] ?? {}),
    zones: (j['zones'] as List? ?? [])
        .map((e) => InstallZone.fromJson(e)).toList(),
    status: SalesJobStatusX.fromString(j['status'] ?? 'draft'),
    totalPriceUsd: (j['totalPriceUsd'] as num?)?.toDouble() ?? 0.0,
    estimateSentAt: (j['estimateSentAt'] as Timestamp?)?.toDate(),
    estimateSignedAt: (j['estimateSignedAt'] as Timestamp?)?.toDate(),
    customerSignatureUrl: j['customerSignatureUrl'],
    day1Date: (j['day1Date'] as Timestamp?)?.toDate(),
    day2Date: (j['day2Date'] as Timestamp?)?.toDate(),
    createdAt: (j['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
    updatedAt: (j['updatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
  );

  SalesJob copyWith({
    String? id,
    String? jobNumber,
    String? dealerCode,
    String? salespersonUid,
    SalesProspect? prospect,
    List<InstallZone>? zones,
    SalesJobStatus? status,
    double? totalPriceUsd,
    DateTime? estimateSentAt,
    DateTime? estimateSignedAt,
    String? customerSignatureUrl,
    DateTime? day1Date,
    DateTime? day2Date,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) => SalesJob(
    id: id ?? this.id,
    jobNumber: jobNumber ?? this.jobNumber,
    dealerCode: dealerCode ?? this.dealerCode,
    salespersonUid: salespersonUid ?? this.salespersonUid,
    prospect: prospect ?? this.prospect,
    zones: zones ?? this.zones,
    status: status ?? this.status,
    totalPriceUsd: totalPriceUsd ?? this.totalPriceUsd,
    estimateSentAt: estimateSentAt ?? this.estimateSentAt,
    estimateSignedAt: estimateSignedAt ?? this.estimateSignedAt,
    customerSignatureUrl: customerSignatureUrl ?? this.customerSignatureUrl,
    day1Date: day1Date ?? this.day1Date,
    day2Date: day2Date ?? this.day2Date,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
}
