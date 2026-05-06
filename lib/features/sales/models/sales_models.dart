import 'dart:ui';

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
// 4. SystemVoltage enum
// ─────────────────────────────────────────

enum SystemVoltage { v24, v36 }

// ─────────────────────────────────────────
// 5. RailType enum
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

// TODO: migrate — consolidate with PowerInjectionPoint (defined below). This
// class is zone-scoped (lives in InstallZone.injections) and is consumed by
// MaterialCalculationService and InstallPlanService. The new
// PowerInjectionPoint is channel-run-scoped and lives at the SalesJob level.
// A future migration prompt should rewrite the services to read from the new
// model and delete this class.
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

// TODO: migrate — the `isController == true` case here overlaps with the new
// ControllerMount class (defined below). Today the controller's mount lives
// inside InstallZone.mounts as a PowerMount with isController: true and is
// found that way in InstallPlanService.buildDay1Tasks. ControllerMount is a
// single top-level field on SalesJob with different fields
// (isInteriorMount, distanceFromOutletFeet). A future migration prompt should
// unify these — likely by splitting PowerMount into PowerSupplyMount (for
// 350w/600w supplies) and using ControllerMount exclusively for the
// controller location.
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
  // TODO: migrate — zone-scoped injections will be replaced by the new
  // SalesJob.powerInjectionPoints (channel-run-scoped) in a future prompt.
  final List<InjectionPoint> injections;
  final List<PowerMount> mounts;
  final List<String> photoUrls;
  final String notes;
  final double priceUsd;
  final RailType railType;
  final RailColor railColor;
  final double connectorRunFt;   // distance from controller/previous zone to start of this zone (ft)
  final int cornerCount;         // number of corners in this zone's run

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
    this.cornerCount = 0,
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
    'cornerCount': cornerCount,
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
    cornerCount: (j['cornerCount'] as int?) ?? 0,
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
// 8b. RunDirection enum
// ─────────────────────────────────────────

/// Physical direction a [ChannelRun] travels along the home, viewed from
/// the front of the home in the primary blueprint photo.
enum RunDirection {
  leftToRight,
  rightToLeft,
  topToBottom,
  bottomToTop,
}

extension RunDirectionX on RunDirection {
  String get label => const {
    RunDirection.leftToRight: 'Left → Right',
    RunDirection.rightToLeft: 'Right → Left',
    RunDirection.topToBottom: 'Top → Bottom',
    RunDirection.bottomToTop: 'Bottom → Top',
  }[this]!;
}

// ─────────────────────────────────────────
// 8c. ChannelRun class
// ─────────────────────────────────────────

/// One continuous LED strip run on the home — i.e. one WLED channel's
/// physical path from start to end. Lives at the [SalesJob] level (not
/// nested under [InstallZone]) so it can be used by the new blueprint
/// system independently of the legacy zone-based estimation flow.
class ChannelRun {
  final String id;

  /// 1-based channel number (Channel 1, Channel 2, ...).
  final int channelNumber;

  /// Human-readable label, e.g. "Front Roofline" or "Garage".
  final String label;

  final double linearFeet;

  /// Free-text description of where this run begins.
  final String startDescription;

  /// Free-text description of where this run ends.
  final String endDescription;

  final RunDirection direction;

  /// Photo of the start point.
  final String? startPhotoPath;

  /// Photo of the end point.
  final String? endPhotoPath;

  /// Normalized 0.0–1.0 trace points on the home photo, same convention as
  /// `RooflineSegment.points` in the roofline system.
  final List<Offset> tracePoints;

  const ChannelRun({
    required this.id,
    required this.channelNumber,
    required this.label,
    required this.linearFeet,
    this.startDescription = '',
    this.endDescription = '',
    this.direction = RunDirection.leftToRight,
    this.startPhotoPath,
    this.endPhotoPath,
    this.tracePoints = const [],
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelNumber': channelNumber,
    'label': label,
    'linearFeet': linearFeet,
    'startDescription': startDescription,
    'endDescription': endDescription,
    'direction': direction.name,
    'startPhotoPath': startPhotoPath,
    'endPhotoPath': endPhotoPath,
    'tracePoints': tracePoints.map((p) => {'dx': p.dx, 'dy': p.dy}).toList(),
  };

  factory ChannelRun.fromJson(Map<String, dynamic> j) => ChannelRun(
    id: j['id'] ?? '',
    channelNumber: (j['channelNumber'] as num?)?.toInt() ?? 1,
    label: j['label'] ?? '',
    linearFeet: (j['linearFeet'] as num?)?.toDouble() ?? 0.0,
    startDescription: j['startDescription'] ?? '',
    endDescription: j['endDescription'] ?? '',
    direction: RunDirection.values.firstWhere(
      (d) => d.name == (j['direction'] ?? ''),
      orElse: () => RunDirection.leftToRight,
    ),
    startPhotoPath: j['startPhotoPath'] as String?,
    endPhotoPath: j['endPhotoPath'] as String?,
    tracePoints: (j['tracePoints'] as List? ?? [])
        .map((e) {
          final m = e as Map<String, dynamic>;
          return Offset(
            (m['dx'] as num?)?.toDouble() ?? 0.0,
            (m['dy'] as num?)?.toDouble() ?? 0.0,
          );
        })
        .toList(),
  );

  ChannelRun copyWith({
    String? id,
    int? channelNumber,
    String? label,
    double? linearFeet,
    String? startDescription,
    String? endDescription,
    RunDirection? direction,
    String? startPhotoPath,
    String? endPhotoPath,
    List<Offset>? tracePoints,
  }) => ChannelRun(
    id: id ?? this.id,
    channelNumber: channelNumber ?? this.channelNumber,
    label: label ?? this.label,
    linearFeet: linearFeet ?? this.linearFeet,
    startDescription: startDescription ?? this.startDescription,
    endDescription: endDescription ?? this.endDescription,
    direction: direction ?? this.direction,
    startPhotoPath: startPhotoPath ?? this.startPhotoPath,
    endPhotoPath: endPhotoPath ?? this.endPhotoPath,
    tracePoints: tracePoints ?? this.tracePoints,
  );
}

// ─────────────────────────────────────────
// 8d. PowerInjectionPoint class
// ─────────────────────────────────────────

/// A power injection point on a [ChannelRun]. Distinct from the legacy
/// [InjectionPoint] (which is zone-scoped); this one is channel-run-scoped
/// and outlet-aware. Used by the new blueprint / Day 1 dispatch system.
///
/// See the // TODO: migrate breadcrumb above [InjectionPoint] for context.
class PowerInjectionPoint {
  final String id;

  /// References [ChannelRun.id].
  final String channelRunId;

  final String locationDescription;

  /// Distance along the channel run from its start.
  final double distanceFromStartFeet;

  final bool hasNearbyOutlet;

  /// Distance from the injection point to the nearest existing outlet, if any.
  final double? outletDistanceFeet;

  final String? photoPath;

  final WireGauge wireGauge;

  final bool requiresNewOutlet;

  const PowerInjectionPoint({
    required this.id,
    required this.channelRunId,
    required this.locationDescription,
    required this.distanceFromStartFeet,
    this.hasNearbyOutlet = false,
    this.outletDistanceFeet,
    this.photoPath,
    this.wireGauge = WireGauge.direct,
    this.requiresNewOutlet = false,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'channelRunId': channelRunId,
    'locationDescription': locationDescription,
    'distanceFromStartFeet': distanceFromStartFeet,
    'hasNearbyOutlet': hasNearbyOutlet,
    'outletDistanceFeet': outletDistanceFeet,
    'photoPath': photoPath,
    'wireGauge': wireGauge.name,
    'requiresNewOutlet': requiresNewOutlet,
  };

  factory PowerInjectionPoint.fromJson(Map<String, dynamic> j) =>
      PowerInjectionPoint(
        id: j['id'] ?? '',
        channelRunId: j['channelRunId'] ?? '',
        locationDescription: j['locationDescription'] ?? '',
        distanceFromStartFeet:
            (j['distanceFromStartFeet'] as num?)?.toDouble() ?? 0.0,
        hasNearbyOutlet: j['hasNearbyOutlet'] ?? false,
        outletDistanceFeet: (j['outletDistanceFeet'] as num?)?.toDouble(),
        photoPath: j['photoPath'] as String?,
        wireGauge: WireGauge.values.firstWhere(
          (g) => g.name == (j['wireGauge'] ?? ''),
          orElse: () => WireGauge.direct,
        ),
        requiresNewOutlet: j['requiresNewOutlet'] ?? false,
      );

  PowerInjectionPoint copyWith({
    String? id,
    String? channelRunId,
    String? locationDescription,
    double? distanceFromStartFeet,
    bool? hasNearbyOutlet,
    double? outletDistanceFeet,
    String? photoPath,
    WireGauge? wireGauge,
    bool? requiresNewOutlet,
  }) => PowerInjectionPoint(
    id: id ?? this.id,
    channelRunId: channelRunId ?? this.channelRunId,
    locationDescription: locationDescription ?? this.locationDescription,
    distanceFromStartFeet:
        distanceFromStartFeet ?? this.distanceFromStartFeet,
    hasNearbyOutlet: hasNearbyOutlet ?? this.hasNearbyOutlet,
    outletDistanceFeet: outletDistanceFeet ?? this.outletDistanceFeet,
    photoPath: photoPath ?? this.photoPath,
    wireGauge: wireGauge ?? this.wireGauge,
    requiresNewOutlet: requiresNewOutlet ?? this.requiresNewOutlet,
  );
}

// ─────────────────────────────────────────
// 8e. ControllerMount class
// ─────────────────────────────────────────

/// Where the WLED controller will be mounted on the home. Distinct from
/// the legacy [PowerMount] with `isController == true`; this is a single
/// top-level field on [SalesJob] used by the new blueprint system.
///
/// See the // TODO: migrate breadcrumb above [PowerMount] for context.
class ControllerMount {
  final String id;

  final String locationDescription;

  final String? photoPath;

  /// True if mounted indoors, false if mounted on the exterior.
  final bool isInteriorMount;

  /// Distance from the chosen mount location to the nearest existing outlet.
  final double? distanceFromOutletFeet;

  const ControllerMount({
    required this.id,
    required this.locationDescription,
    this.photoPath,
    this.isInteriorMount = true,
    this.distanceFromOutletFeet,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'locationDescription': locationDescription,
    'photoPath': photoPath,
    'isInteriorMount': isInteriorMount,
    'distanceFromOutletFeet': distanceFromOutletFeet,
  };

  factory ControllerMount.fromJson(Map<String, dynamic> j) => ControllerMount(
    id: j['id'] ?? '',
    locationDescription: j['locationDescription'] ?? '',
    photoPath: j['photoPath'] as String?,
    isInteriorMount: j['isInteriorMount'] ?? true,
    distanceFromOutletFeet: (j['distanceFromOutletFeet'] as num?)?.toDouble(),
  );

  ControllerMount copyWith({
    String? id,
    String? locationDescription,
    String? photoPath,
    bool? isInteriorMount,
    double? distanceFromOutletFeet,
  }) => ControllerMount(
    id: id ?? this.id,
    locationDescription: locationDescription ?? this.locationDescription,
    photoPath: photoPath ?? this.photoPath,
    isInteriorMount: isInteriorMount ?? this.isInteriorMount,
    distanceFromOutletFeet:
        distanceFromOutletFeet ?? this.distanceFromOutletFeet,
  );
}

// ─────────────────────────────────────────
// 8f. DealerPricing class
// ─────────────────────────────────────────

/// Pricing inputs supplied by the dealer when generating an estimate.
/// Passed into [MaterialCalculationService.calculateEstimate] alongside
/// a [SalesJob]; not persisted on the job itself (the resulting
/// [EstimateBreakdown] captures the prices that were used).
class DealerPricing {
  /// Customer-facing price per linear foot of LED strip.
  final double pricePerLinearFoot;

  /// Customer-facing labor rate per linear foot.
  final double laborRatePerFoot;

  /// Minimum labor charge applied when the per-foot total falls below it.
  final double flatLaborMinimum;

  /// Customer-facing retail price for one WLED controller.
  final double controllerRetailPrice;

  /// Customer-facing retail price for one power distribution board.
  final double powerBoardRetailPrice;

  /// Material overage factor (e.g. 0.08 = 8% extra strip purchased to
  /// cover waste).
  final double wasteFactor;

  /// Optional dealer cost basis used to compute margin. Falls back to
  /// 0 (i.e. no margin info) when omitted.
  final double dealerCostPerLinearFoot;
  final double dealerControllerCost;
  final double dealerPowerBoardCost;

  const DealerPricing({
    required this.pricePerLinearFoot,
    required this.laborRatePerFoot,
    required this.flatLaborMinimum,
    required this.controllerRetailPrice,
    required this.powerBoardRetailPrice,
    this.wasteFactor = 0.08,
    this.dealerCostPerLinearFoot = 0,
    this.dealerControllerCost = 0,
    this.dealerPowerBoardCost = 0,
  });

  Map<String, dynamic> toJson() => {
    'pricePerLinearFoot': pricePerLinearFoot,
    'laborRatePerFoot': laborRatePerFoot,
    'flatLaborMinimum': flatLaborMinimum,
    'controllerRetailPrice': controllerRetailPrice,
    'powerBoardRetailPrice': powerBoardRetailPrice,
    'wasteFactor': wasteFactor,
    'dealerCostPerLinearFoot': dealerCostPerLinearFoot,
    'dealerControllerCost': dealerControllerCost,
    'dealerPowerBoardCost': dealerPowerBoardCost,
  };

  /// Sensible fallback values used when a dealer has not yet set their
  /// own pricing in Firestore. Lets the wizard generate an estimate
  /// immediately on a freshly-provisioned dealer; once the dealer
  /// populates `dealers/{dealerCode}/pricing` the loader will pick up
  /// the real values automatically with no code change.
  factory DealerPricing.defaults() => const DealerPricing(
        pricePerLinearFoot: 18,
        laborRatePerFoot: 4,
        flatLaborMinimum: 150,
        controllerRetailPrice: 285,
        powerBoardRetailPrice: 95,
        wasteFactor: 0.08,
      );

  factory DealerPricing.fromJson(Map<String, dynamic> j) => DealerPricing(
    pricePerLinearFoot:
        (j['pricePerLinearFoot'] as num?)?.toDouble() ?? 0,
    laborRatePerFoot: (j['laborRatePerFoot'] as num?)?.toDouble() ?? 0,
    flatLaborMinimum: (j['flatLaborMinimum'] as num?)?.toDouble() ?? 0,
    controllerRetailPrice:
        (j['controllerRetailPrice'] as num?)?.toDouble() ?? 0,
    powerBoardRetailPrice:
        (j['powerBoardRetailPrice'] as num?)?.toDouble() ?? 0,
    wasteFactor: (j['wasteFactor'] as num?)?.toDouble() ?? 0.08,
    dealerCostPerLinearFoot:
        (j['dealerCostPerLinearFoot'] as num?)?.toDouble() ?? 0,
    dealerControllerCost:
        (j['dealerControllerCost'] as num?)?.toDouble() ?? 0,
    dealerPowerBoardCost:
        (j['dealerPowerBoardCost'] as num?)?.toDouble() ?? 0,
  );

  DealerPricing copyWith({
    double? pricePerLinearFoot,
    double? laborRatePerFoot,
    double? flatLaborMinimum,
    double? controllerRetailPrice,
    double? powerBoardRetailPrice,
    double? wasteFactor,
    double? dealerCostPerLinearFoot,
    double? dealerControllerCost,
    double? dealerPowerBoardCost,
  }) => DealerPricing(
    pricePerLinearFoot: pricePerLinearFoot ?? this.pricePerLinearFoot,
    laborRatePerFoot: laborRatePerFoot ?? this.laborRatePerFoot,
    flatLaborMinimum: flatLaborMinimum ?? this.flatLaborMinimum,
    controllerRetailPrice:
        controllerRetailPrice ?? this.controllerRetailPrice,
    powerBoardRetailPrice:
        powerBoardRetailPrice ?? this.powerBoardRetailPrice,
    wasteFactor: wasteFactor ?? this.wasteFactor,
    dealerCostPerLinearFoot:
        dealerCostPerLinearFoot ?? this.dealerCostPerLinearFoot,
    dealerControllerCost:
        dealerControllerCost ?? this.dealerControllerCost,
    dealerPowerBoardCost:
        dealerPowerBoardCost ?? this.dealerPowerBoardCost,
  );
}

// ─────────────────────────────────────────
// 8g. EstimateLineCategory enum
// ─────────────────────────────────────────

enum EstimateLineCategory { strip, controller, power, hardware, labor }

extension EstimateLineCategoryX on EstimateLineCategory {
  String get label => const {
    EstimateLineCategory.strip: 'LED Strip',
    EstimateLineCategory.controller: 'Controller',
    EstimateLineCategory.power: 'Power',
    EstimateLineCategory.hardware: 'Hardware',
    EstimateLineCategory.labor: 'Labor',
  }[this]!;
}

// ─────────────────────────────────────────
// 8h. EstimateLineItem class
// ─────────────────────────────────────────

/// One line on a customer-facing estimate, captured at the moment the
/// estimate was generated. Stored inside [EstimateBreakdown.lineItems]
/// — not a separate Firestore document.
class EstimateLineItem {
  /// Stable identifier for cross-referencing this line in downstream
  /// records (e.g. [ActualMaterialUsageEntry] on the wrap-up screen).
  /// Generated by [MaterialCalculationService.calculateEstimate] from
  /// a hash of `description + category` so the same line in the same
  /// estimate always gets the same id, even across regeneration.
  ///
  /// Older breakdowns persisted before this field existed deserialize
  /// without an explicit id; [fromJson] falls back to the same hash so
  /// they round-trip cleanly without a Firestore migration.
  final String id;

  final String description;
  final double quantity;
  final String unit;
  final double unitRetailPrice;
  final double unitDealerCost;
  final EstimateLineCategory category;

  const EstimateLineItem({
    required this.id,
    required this.description,
    required this.quantity,
    required this.unit,
    required this.unitRetailPrice,
    this.unitDealerCost = 0,
    required this.category,
  });

  /// Build a stable id from a description + category. Used both at
  /// generation time (when [MaterialCalculationService.calculateEstimate]
  /// constructs new line items) and as the [fromJson] fallback for
  /// pre-id breakdowns persisted before this field existed.
  static String stableId({
    required String description,
    required EstimateLineCategory category,
  }) {
    final input = '${category.name}::$description';
    return 'eli_${input.hashCode.toUnsigned(32).toRadixString(16)}';
  }

  double get retailTotal => quantity * unitRetailPrice;
  double get dealerCostTotal => quantity * unitDealerCost;

  Map<String, dynamic> toJson() => {
    'id': id,
    'description': description,
    'quantity': quantity,
    'unit': unit,
    'unitRetailPrice': unitRetailPrice,
    'unitDealerCost': unitDealerCost,
    'category': category.name,
  };

  factory EstimateLineItem.fromJson(Map<String, dynamic> j) {
    final description = j['description'] as String? ?? '';
    final category = EstimateLineCategory.values.firstWhere(
      (c) => c.name == (j['category'] ?? ''),
      orElse: () => EstimateLineCategory.hardware,
    );
    return EstimateLineItem(
      // Backwards-compat: pre-id breakdowns get a derived id so the
      // wrap-up screen can still key ActualMaterialUsageEntry off them.
      id: j['id'] as String? ??
          stableId(description: description, category: category),
      description: description,
      quantity: (j['quantity'] as num?)?.toDouble() ?? 0,
      unit: j['unit'] as String? ?? '',
      unitRetailPrice: (j['unitRetailPrice'] as num?)?.toDouble() ?? 0,
      unitDealerCost: (j['unitDealerCost'] as num?)?.toDouble() ?? 0,
      category: category,
    );
  }

  EstimateLineItem copyWith({
    String? id,
    String? description,
    double? quantity,
    String? unit,
    double? unitRetailPrice,
    double? unitDealerCost,
    EstimateLineCategory? category,
  }) => EstimateLineItem(
    id: id ?? this.id,
    description: description ?? this.description,
    quantity: quantity ?? this.quantity,
    unit: unit ?? this.unit,
    unitRetailPrice: unitRetailPrice ?? this.unitRetailPrice,
    unitDealerCost: unitDealerCost ?? this.unitDealerCost,
    category: category ?? this.category,
  );
}

// ─────────────────────────────────────────
// 8i. EstimateBreakdown class
// ─────────────────────────────────────────

/// Full priced breakdown of an estimate. Embedded in the parent
/// [SalesJob] document under the `estimateBreakdown` field, so it
/// serializes alongside the rest of the job state.
class EstimateBreakdown {
  final List<EstimateLineItem> lineItems;
  final double subtotalMaterial;
  final double subtotalLabor;
  final double subtotalRetail;
  final double dealerMaterialCost;
  final double estimatedMargin;
  final double estimatedMarginPct;
  final DateTime generatedAt;

  const EstimateBreakdown({
    required this.lineItems,
    required this.subtotalMaterial,
    required this.subtotalLabor,
    required this.subtotalRetail,
    required this.dealerMaterialCost,
    required this.estimatedMargin,
    required this.estimatedMarginPct,
    required this.generatedAt,
  });

  Map<String, dynamic> toJson() => {
    'lineItems': lineItems.map((l) => l.toJson()).toList(),
    'subtotalMaterial': subtotalMaterial,
    'subtotalLabor': subtotalLabor,
    'subtotalRetail': subtotalRetail,
    'dealerMaterialCost': dealerMaterialCost,
    'estimatedMargin': estimatedMargin,
    'estimatedMarginPct': estimatedMarginPct,
    'generatedAt': Timestamp.fromDate(generatedAt),
  };

  factory EstimateBreakdown.fromJson(Map<String, dynamic> j) =>
      EstimateBreakdown(
        lineItems: (j['lineItems'] as List? ?? [])
            .map((e) => EstimateLineItem.fromJson(e as Map<String, dynamic>))
            .toList(),
        subtotalMaterial:
            (j['subtotalMaterial'] as num?)?.toDouble() ?? 0,
        subtotalLabor: (j['subtotalLabor'] as num?)?.toDouble() ?? 0,
        subtotalRetail: (j['subtotalRetail'] as num?)?.toDouble() ?? 0,
        dealerMaterialCost:
            (j['dealerMaterialCost'] as num?)?.toDouble() ?? 0,
        estimatedMargin: (j['estimatedMargin'] as num?)?.toDouble() ?? 0,
        estimatedMarginPct:
            (j['estimatedMarginPct'] as num?)?.toDouble() ?? 0,
        generatedAt:
            (j['generatedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      );

  EstimateBreakdown copyWith({
    List<EstimateLineItem>? lineItems,
    double? subtotalMaterial,
    double? subtotalLabor,
    double? subtotalRetail,
    double? dealerMaterialCost,
    double? estimatedMargin,
    double? estimatedMarginPct,
    DateTime? generatedAt,
  }) => EstimateBreakdown(
    lineItems: lineItems ?? this.lineItems,
    subtotalMaterial: subtotalMaterial ?? this.subtotalMaterial,
    subtotalLabor: subtotalLabor ?? this.subtotalLabor,
    subtotalRetail: subtotalRetail ?? this.subtotalRetail,
    dealerMaterialCost: dealerMaterialCost ?? this.dealerMaterialCost,
    estimatedMargin: estimatedMargin ?? this.estimatedMargin,
    estimatedMarginPct: estimatedMarginPct ?? this.estimatedMarginPct,
    generatedAt: generatedAt ?? this.generatedAt,
  );
}

// ─────────────────────────────────────────
// 8j. ActualMaterialUsage — wrap-up check-in record
// ─────────────────────────────────────────

/// One actual-vs-estimate row captured during the Day 2 wrap-up screen
/// when the install team checks in unused materials.
///
/// This is a **record-only** model — no inventory math happens against
/// it in this prompt. A future prompt will wire it up to
/// [InventoryService] for the full check-out → check-in lifecycle. Until
/// then, [ActualMaterialUsage] just lives on the [SalesJob] document
/// for audit and dealer-dashboard reporting.
class ActualMaterialUsageEntry {
  /// References [EstimateLineItem.id] from the same job's
  /// [EstimateBreakdown.lineItems]. Stable across regeneration.
  final String itemId;

  /// Description copied from the source [EstimateLineItem] at capture
  /// time. Persisted so reports stay readable even if the underlying
  /// estimate is later edited or regenerated.
  final String description;

  /// What [MaterialCalculationService.calculateEstimate] originally
  /// quoted for this line.
  final double estimatedQty;

  /// Actual quantity returned to dealer inventory at wrap-up.
  final double returnedQty;

  /// Computed used quantity. Negative values are nonsensical and
  /// indicate the installer entered a return greater than the estimate.
  double get usedQty => estimatedQty - returnedQty;

  const ActualMaterialUsageEntry({
    required this.itemId,
    required this.description,
    required this.estimatedQty,
    required this.returnedQty,
  });

  Map<String, dynamic> toJson() => {
    'itemId': itemId,
    'description': description,
    'estimatedQty': estimatedQty,
    'returnedQty': returnedQty,
  };

  factory ActualMaterialUsageEntry.fromJson(Map<String, dynamic> j) =>
      ActualMaterialUsageEntry(
        itemId: j['itemId'] as String? ?? '',
        description: j['description'] as String? ?? '',
        estimatedQty: (j['estimatedQty'] as num?)?.toDouble() ?? 0,
        returnedQty: (j['returnedQty'] as num?)?.toDouble() ?? 0,
      );

  ActualMaterialUsageEntry copyWith({
    String? itemId,
    String? description,
    double? estimatedQty,
    double? returnedQty,
  }) =>
      ActualMaterialUsageEntry(
        itemId: itemId ?? this.itemId,
        description: description ?? this.description,
        estimatedQty: estimatedQty ?? this.estimatedQty,
        returnedQty: returnedQty ?? this.returnedQty,
      );
}

/// Wrap-up material check-in record stored on the [SalesJob]. Captured
/// in Step 2 of the Day 2 wrap-up screen.
class ActualMaterialUsage {
  final List<ActualMaterialUsageEntry> entries;
  final DateTime recordedAt;

  /// Installer who performed the check-in. Currently the
  /// `InstallerInfo.fullPin` 4-digit string — see the
  /// `// TODO: replace with Firebase Auth UID when installer auth migrates`
  /// breadcrumbs in [SalesJobService] for context.
  final String recordedByPin;

  const ActualMaterialUsage({
    required this.entries,
    required this.recordedAt,
    required this.recordedByPin,
  });

  Map<String, dynamic> toJson() => {
    'entries': entries.map((e) => e.toJson()).toList(),
    'recordedAt': Timestamp.fromDate(recordedAt),
    'recordedByPin': recordedByPin,
  };

  factory ActualMaterialUsage.fromJson(Map<String, dynamic> j) =>
      ActualMaterialUsage(
        entries: (j['entries'] as List? ?? [])
            .map((e) =>
                ActualMaterialUsageEntry.fromJson(e as Map<String, dynamic>))
            .toList(),
        recordedAt:
            (j['recordedAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
        recordedByPin: j['recordedByPin'] as String? ?? '',
      );

  ActualMaterialUsage copyWith({
    List<ActualMaterialUsageEntry>? entries,
    DateTime? recordedAt,
    String? recordedByPin,
  }) =>
      ActualMaterialUsage(
        entries: entries ?? this.entries,
        recordedAt: recordedAt ?? this.recordedAt,
        recordedByPin: recordedByPin ?? this.recordedByPin,
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
  installScheduled,
  installComplete,
  // Terminal state: install is complete AND final payment has been
  // collected. Filtered out of active queues — only appears in
  // historical job lists.
  completePaid,
}

extension SalesJobStatusX on SalesJobStatus {
  String get label => const {
    SalesJobStatus.draft: 'Draft',
    SalesJobStatus.estimateSent: 'Estimate sent',
    SalesJobStatus.estimateSigned: 'Signed',
    SalesJobStatus.prewireScheduled: 'Pre-wire scheduled',
    SalesJobStatus.prewireComplete: 'Pre-wire complete',
    SalesJobStatus.installScheduled: 'Install scheduled',
    SalesJobStatus.installComplete: 'Install complete',
    SalesJobStatus.completePaid: 'Complete (paid)',
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
  final SystemVoltage systemVoltage;
  /// UID of the user account created when this job's install is completed.
  /// Set by [SalesJobService.linkToInstall]. Null until install is finalized.
  final String? linkedUserId;

  // ── Blueprint / field ops fields (added in Prompt 1) ──

  /// Channel-run-scoped LED runs for the new blueprint system. Parallel to
  /// the legacy [InstallZone] structure — see // TODO: migrate breadcrumbs.
  final List<ChannelRun> channelRuns;

  /// Channel-run-scoped power injection points. Parallel to the legacy
  /// zone-scoped [InjectionPoint] list inside [InstallZone.injections].
  final List<PowerInjectionPoint> powerInjectionPoints;

  /// Where the WLED controller will be mounted on the home.
  final ControllerMount? controllerMount;

  /// Primary home photo used as the blueprint overlay background.
  final String? homePhotoPath;

  /// Notes captured by the Day 1 electrician.
  final String? day1Notes;

  /// Notes captured by the Day 2 install team.
  final String? day2Notes;

  /// IDs of Day 1 checklist items the electrician has marked complete.
  final List<String> day1CompletedTaskIds;

  /// IDs of Day 2 checklist items the install team has marked complete.
  final List<String> day2CompletedTaskIds;

  /// UID of the technician who performed the Day 1 pre-wire.
  final String? day1TechUid;

  /// UID of the technician who performed the Day 2 install.
  final String? day2TechUid;

  /// When Day 1 was marked complete.
  final DateTime? day1CompletedAt;

  /// When Day 2 was marked complete.
  final DateTime? day2CompletedAt;

  /// Priced line-item breakdown produced by
  /// [MaterialCalculationService.calculateEstimate]. Null until the
  /// salesperson generates an estimate from the wizard.
  final EstimateBreakdown? estimateBreakdown;

  /// Photo URLs captured during the Day 2 wrap-up screen — one per
  /// completed channel install. Empty until the install team uploads
  /// any photos.
  final List<String> installCompletePhotoUrls;

  /// Material check-in record captured during the Day 2 wrap-up.
  /// Null until the install team confirms quantities returned.
  final ActualMaterialUsage? actualMaterialUsage;

  // ── Payment gates (Part 10) ────────────────────────────────────────────
  //
  // Two-step payment cycle introduced for the post-launch inventory build:
  //   1. 50% deposit collected before Day 1 can be scheduled.
  //   2. Final payment collected after Day 2 install is complete.
  //
  // All fields default to safe nulls/false so jobs created before this
  // schema change continue to round-trip without migration. Naming
  // matches the existing camelCase JSON convention on this model
  // (existing keys: dealerCode, totalPriceUsd, day2CompletedAt) — the
  // newer snake_case convention used elsewhere in the inventory build is
  // intentionally NOT applied here so SalesJob stays internally
  // consistent.

  /// Whether the 50% deposit has been collected. Gates Day 1 scheduling.
  final bool depositCollected;

  /// When the deposit was marked collected (server timestamp).
  final DateTime? depositCollectedAt;

  /// UID (or installer pin fallback) of the person who marked the
  /// deposit collected.
  final String? depositCollectedBy;

  /// The deposit amount that was collected. Snapshot of
  /// totalPriceUsd * 0.5 at the moment of collection — preserved so
  /// retroactive total-price edits don't change the historical record.
  final double? depositAmount;

  /// Whether the final balance has been collected. Drives the
  /// completePaid status transition.
  final bool finalPaymentCollected;

  /// When the final payment was marked collected.
  final DateTime? finalPaymentCollectedAt;

  /// UID (or installer pin fallback) of the person who marked the
  /// final payment collected.
  final String? finalPaymentCollectedBy;

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
    this.systemVoltage = SystemVoltage.v24,
    this.linkedUserId,
    this.channelRuns = const [],
    this.powerInjectionPoints = const [],
    this.controllerMount,
    this.homePhotoPath,
    this.day1Notes,
    this.day2Notes,
    this.day1CompletedTaskIds = const [],
    this.day2CompletedTaskIds = const [],
    this.day1TechUid,
    this.day2TechUid,
    this.day1CompletedAt,
    this.day2CompletedAt,
    this.estimateBreakdown,
    this.installCompletePhotoUrls = const [],
    this.actualMaterialUsage,
    this.depositCollected = false,
    this.depositCollectedAt,
    this.depositCollectedBy,
    this.depositAmount,
    this.finalPaymentCollected = false,
    this.finalPaymentCollectedAt,
    this.finalPaymentCollectedBy,
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
    'systemVoltage': systemVoltage.name,
    'linkedUserId': linkedUserId,
    'channelRuns': channelRuns.map((r) => r.toJson()).toList(),
    'powerInjectionPoints':
        powerInjectionPoints.map((p) => p.toJson()).toList(),
    'controllerMount': controllerMount?.toJson(),
    'homePhotoPath': homePhotoPath,
    'day1Notes': day1Notes,
    'day2Notes': day2Notes,
    'day1CompletedTaskIds': day1CompletedTaskIds,
    'day2CompletedTaskIds': day2CompletedTaskIds,
    'day1TechUid': day1TechUid,
    'day2TechUid': day2TechUid,
    'day1CompletedAt': day1CompletedAt != null
        ? Timestamp.fromDate(day1CompletedAt!)
        : null,
    'day2CompletedAt': day2CompletedAt != null
        ? Timestamp.fromDate(day2CompletedAt!)
        : null,
    'estimateBreakdown': estimateBreakdown?.toJson(),
    'installCompletePhotoUrls': installCompletePhotoUrls,
    'actualMaterialUsage': actualMaterialUsage?.toJson(),
    'depositCollected': depositCollected,
    'depositCollectedAt': depositCollectedAt != null
        ? Timestamp.fromDate(depositCollectedAt!)
        : null,
    'depositCollectedBy': depositCollectedBy,
    'depositAmount': depositAmount,
    'finalPaymentCollected': finalPaymentCollected,
    'finalPaymentCollectedAt': finalPaymentCollectedAt != null
        ? Timestamp.fromDate(finalPaymentCollectedAt!)
        : null,
    'finalPaymentCollectedBy': finalPaymentCollectedBy,
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
    systemVoltage: SystemVoltage.values.firstWhere(
      (v) => v.name == (j['systemVoltage'] ?? ''),
      orElse: () => SystemVoltage.v24,
    ),
    linkedUserId: j['linkedUserId'] as String?,
    channelRuns: (j['channelRuns'] as List? ?? [])
        .map((e) => ChannelRun.fromJson(e as Map<String, dynamic>))
        .toList(),
    powerInjectionPoints: (j['powerInjectionPoints'] as List? ?? [])
        .map((e) => PowerInjectionPoint.fromJson(e as Map<String, dynamic>))
        .toList(),
    controllerMount: j['controllerMount'] == null
        ? null
        : ControllerMount.fromJson(
            j['controllerMount'] as Map<String, dynamic>),
    homePhotoPath: j['homePhotoPath'] as String?,
    day1Notes: j['day1Notes'] as String?,
    day2Notes: j['day2Notes'] as String?,
    day1CompletedTaskIds:
        List<String>.from(j['day1CompletedTaskIds'] ?? const []),
    day2CompletedTaskIds:
        List<String>.from(j['day2CompletedTaskIds'] ?? const []),
    day1TechUid: j['day1TechUid'] as String?,
    day2TechUid: j['day2TechUid'] as String?,
    day1CompletedAt: (j['day1CompletedAt'] as Timestamp?)?.toDate(),
    day2CompletedAt: (j['day2CompletedAt'] as Timestamp?)?.toDate(),
    estimateBreakdown: j['estimateBreakdown'] == null
        ? null
        : EstimateBreakdown.fromJson(
            j['estimateBreakdown'] as Map<String, dynamic>),
    installCompletePhotoUrls:
        List<String>.from(j['installCompletePhotoUrls'] ?? const []),
    actualMaterialUsage: j['actualMaterialUsage'] == null
        ? null
        : ActualMaterialUsage.fromJson(
            j['actualMaterialUsage'] as Map<String, dynamic>),
    depositCollected: j['depositCollected'] as bool? ?? false,
    depositCollectedAt: (j['depositCollectedAt'] as Timestamp?)?.toDate(),
    depositCollectedBy: j['depositCollectedBy'] as String?,
    depositAmount: (j['depositAmount'] as num?)?.toDouble(),
    finalPaymentCollected: j['finalPaymentCollected'] as bool? ?? false,
    finalPaymentCollectedAt:
        (j['finalPaymentCollectedAt'] as Timestamp?)?.toDate(),
    finalPaymentCollectedBy: j['finalPaymentCollectedBy'] as String?,
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
    SystemVoltage? systemVoltage,
    String? linkedUserId,
    List<ChannelRun>? channelRuns,
    List<PowerInjectionPoint>? powerInjectionPoints,
    ControllerMount? controllerMount,
    String? homePhotoPath,
    String? day1Notes,
    String? day2Notes,
    List<String>? day1CompletedTaskIds,
    List<String>? day2CompletedTaskIds,
    String? day1TechUid,
    String? day2TechUid,
    DateTime? day1CompletedAt,
    DateTime? day2CompletedAt,
    EstimateBreakdown? estimateBreakdown,
    List<String>? installCompletePhotoUrls,
    ActualMaterialUsage? actualMaterialUsage,
    bool? depositCollected,
    DateTime? depositCollectedAt,
    String? depositCollectedBy,
    double? depositAmount,
    bool? finalPaymentCollected,
    DateTime? finalPaymentCollectedAt,
    String? finalPaymentCollectedBy,
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
    systemVoltage: systemVoltage ?? this.systemVoltage,
    linkedUserId: linkedUserId ?? this.linkedUserId,
    channelRuns: channelRuns ?? this.channelRuns,
    powerInjectionPoints: powerInjectionPoints ?? this.powerInjectionPoints,
    controllerMount: controllerMount ?? this.controllerMount,
    homePhotoPath: homePhotoPath ?? this.homePhotoPath,
    day1Notes: day1Notes ?? this.day1Notes,
    day2Notes: day2Notes ?? this.day2Notes,
    day1CompletedTaskIds: day1CompletedTaskIds ?? this.day1CompletedTaskIds,
    day2CompletedTaskIds: day2CompletedTaskIds ?? this.day2CompletedTaskIds,
    day1TechUid: day1TechUid ?? this.day1TechUid,
    day2TechUid: day2TechUid ?? this.day2TechUid,
    day1CompletedAt: day1CompletedAt ?? this.day1CompletedAt,
    day2CompletedAt: day2CompletedAt ?? this.day2CompletedAt,
    estimateBreakdown: estimateBreakdown ?? this.estimateBreakdown,
    installCompletePhotoUrls:
        installCompletePhotoUrls ?? this.installCompletePhotoUrls,
    actualMaterialUsage: actualMaterialUsage ?? this.actualMaterialUsage,
    depositCollected: depositCollected ?? this.depositCollected,
    depositCollectedAt: depositCollectedAt ?? this.depositCollectedAt,
    depositCollectedBy: depositCollectedBy ?? this.depositCollectedBy,
    depositAmount: depositAmount ?? this.depositAmount,
    finalPaymentCollected:
        finalPaymentCollected ?? this.finalPaymentCollected,
    finalPaymentCollectedAt:
        finalPaymentCollectedAt ?? this.finalPaymentCollectedAt,
    finalPaymentCollectedBy:
        finalPaymentCollectedBy ?? this.finalPaymentCollectedBy,
  );
}
