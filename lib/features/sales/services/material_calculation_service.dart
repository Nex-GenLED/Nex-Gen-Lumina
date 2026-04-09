import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MaterialCalculationService
//
// Calculates the product material list for a sales job based on zone data
// entered during the sales visit. Covers rails, lights, rope, connectors,
// and accessories — NOT electrical pre-wire (handled by pdf_service.dart).
// ─────────────────────────────────────────────────────────────────────────────

class MaterialCalculationService {
  final FirebaseFirestore _db;

  MaterialCalculationService(this._db);

  // ── Constants ────────────────────────────────────────────────────────────

  /// 1m rail = 3.28084 ft
  static const double kFeetPerRail = 3.28084;

  /// 5 lights fit in 1 uncut 1m rail
  static const int kPixelsPerFullRail = 5;

  /// Each corner: 80mm cut on both meeting rail ends → 1 light lost per end = 2 total.
  /// Verified: 90m run, 10 corners → (100 rails × 5) − (10 × 2) = 480 lights.
  static const int kLightsLostPerCorner = 2;

  /// 5m rope light piece = 16.4042 ft
  static const double kFeetPerRopePiece = 16.4042;

  static const double kRailOverageRate = 0.10;
  static const double kLightOverageRate = 0.10;
  static const double kRopeOverageRate = 0.10;
  static const double kConnectorOverageRate = 0.15;

  /// Add 1 amplifier per zone where exact pixel count exceeds this
  static const int kAmplifierThreshold = 100;

  // ── Public API ───────────────────────────────────────────────────────────

  Future<JobMaterialList> calculateForJob({
    required SalesJob job,
    required String calculatedBy,
  }) async {
    final catalog = await _loadCatalog(job.dealerCode);
    final lines = <JobMaterialLine>[];

    for (final zone in job.zones) {
      switch (zone.productType) {
        case ProductType.roofline:
          _calculateRooflineZone(job, zone, catalog, lines);
        case ProductType.diffusedRope:
          _calculateRopeZone(zone, catalog, lines);
        case ProductType.custom:
          // Custom type — no materials calculated, flagged for PM review
          break;
      }
    }

    _addJobLevelItems(job, catalog, lines);
    _deduplicateLines(lines);

    return JobMaterialList(
      jobId: job.id,
      jobNumber: job.jobNumber,
      dealerCode: job.dealerCode,
      status: JobMaterialStatus.draft,
      lines: lines,
      calculatedBy: calculatedBy,
      calculatedAt: DateTime.now(),
    );
  }

  // ── Estimate calculation (Estimate Wizard data) ──────────────────────────
  //
  // Synchronous, dealer-pricing-driven estimate generation. Reads the new
  // ChannelRun / PowerInjectionPoint / ControllerMount fields populated by
  // the Estimate Wizard (see Prompt 2) and produces an EstimateBreakdown
  // suitable for display on EstimatePreviewScreen and persistence on the
  // SalesJob document.
  //
  // Unlike calculateForJob() this does NOT touch the dealers/{code}/
  // materialCatalog Firestore collection — all unit prices come from the
  // [DealerPricing] argument so the wizard can generate an estimate
  // immediately without an extra round-trip.

  /// Build a customer-facing line-item estimate from the wizard data on
  /// [job], using [pricing] for unit prices and waste factor.
  EstimateBreakdown calculateEstimate(SalesJob job, DealerPricing pricing) {
    final lineItems = <EstimateLineItem>[];

    double subtotalMaterial = 0;
    double dealerMaterialCost = 0;

    // ── LED strip — one line per channel run ──────────────────────────────
    double totalRunFeet = 0;
    for (final run in job.channelRuns) {
      if (run.linearFeet <= 0) continue;
      totalRunFeet += run.linearFeet;

      final orderedFeet = run.linearFeet * (1 + pricing.wasteFactor);

      final stripDescription = run.label.isEmpty
          ? 'Channel ${run.channelNumber} LED strip'
          : '${run.label} — LED strip';
      final stripLine = EstimateLineItem(
        id: EstimateLineItem.stableId(
          description: stripDescription,
          category: EstimateLineCategory.strip,
        ),
        description: stripDescription,
        quantity: double.parse(orderedFeet.toStringAsFixed(2)),
        unit: 'ft',
        unitRetailPrice: pricing.pricePerLinearFoot,
        unitDealerCost: pricing.dealerCostPerLinearFoot,
        category: EstimateLineCategory.strip,
      );
      lineItems.add(stripLine);
      subtotalMaterial += stripLine.retailTotal;
      dealerMaterialCost += stripLine.dealerCostTotal;
    }

    // ── Power injection hardware ──────────────────────────────────────────
    //
    // Each PowerInjectionPoint contributes:
    //   • one injection-point hardware line
    //   • one wire run line, sized by gauge and a heuristic distance
    //
    // Wire footage heuristic: if the user recorded an outlet distance, use
    // that. Otherwise fall back to the existing WireGauge.fromDistance
    // table by walking distanceFromStartFeet — this matches the legacy
    // ZoneEditorSheet behavior in zone_builder_screen.dart.
    if (job.powerInjectionPoints.isNotEmpty) {
      // Group identical injection-point hardware into a single line.
      final injCount = job.powerInjectionPoints.length;
      const injHardwareDescription =
          'Power injection hardware (T-connector + tap)';
      final injHardwareLine = EstimateLineItem(
        id: EstimateLineItem.stableId(
          description: injHardwareDescription,
          category: EstimateLineCategory.hardware,
        ),
        description: injHardwareDescription,
        quantity: injCount.toDouble(),
        unit: 'unit',
        // Hardware retail/cost are folded into the dealer's per-unit
        // controller/power board prices today; expose a 0-priced line so
        // the customer sees the part count without double-billing.
        unitRetailPrice: 0,
        unitDealerCost: 0,
        category: EstimateLineCategory.hardware,
      );
      lineItems.add(injHardwareLine);

      // Wire footage — sum across all injection points.
      double wireFeet = 0;
      for (final p in job.powerInjectionPoints) {
        if (p.outletDistanceFeet != null && p.outletDistanceFeet! > 0) {
          wireFeet += p.outletDistanceFeet!;
        } else if (p.distanceFromStartFeet > 0) {
          // Heuristic: assume the wire run from the controller is roughly
          // the injection point's distance from the run start.
          wireFeet += p.distanceFromStartFeet;
        }
      }
      // Apply the same waste factor to wire as to strip.
      wireFeet = wireFeet * (1 + pricing.wasteFactor);
      if (wireFeet > 0) {
        const wireDescription = 'Power injection wire runs';
        final wireLine = EstimateLineItem(
          id: EstimateLineItem.stableId(
            description: wireDescription,
            category: EstimateLineCategory.power,
          ),
          description: wireDescription,
          quantity: double.parse(wireFeet.toStringAsFixed(2)),
          unit: 'ft',
          unitRetailPrice: 0,
          unitDealerCost: 0,
          category: EstimateLineCategory.power,
        );
        lineItems.add(wireLine);
      }
    }

    // ── Controller — one per job ──────────────────────────────────────────
    const controllerDescription = 'WLED controller';
    final controllerLine = EstimateLineItem(
      id: EstimateLineItem.stableId(
        description: controllerDescription,
        category: EstimateLineCategory.controller,
      ),
      description: controllerDescription,
      quantity: 1,
      unit: 'unit',
      unitRetailPrice: pricing.controllerRetailPrice,
      unitDealerCost: pricing.dealerControllerCost,
      category: EstimateLineCategory.controller,
    );
    lineItems.add(controllerLine);
    subtotalMaterial += controllerLine.retailTotal;
    dealerMaterialCost += controllerLine.dealerCostTotal;

    // ── Power board — one per controller ──────────────────────────────────
    const powerBoardDescription = 'Power distribution board';
    final powerBoardLine = EstimateLineItem(
      id: EstimateLineItem.stableId(
        description: powerBoardDescription,
        category: EstimateLineCategory.power,
      ),
      description: powerBoardDescription,
      quantity: 1,
      unit: 'unit',
      unitRetailPrice: pricing.powerBoardRetailPrice,
      unitDealerCost: pricing.dealerPowerBoardCost,
      category: EstimateLineCategory.power,
    );
    lineItems.add(powerBoardLine);
    subtotalMaterial += powerBoardLine.retailTotal;
    dealerMaterialCost += powerBoardLine.dealerCostTotal;

    // ── Labor — max(flat min, totalFt × per-foot rate) ────────────────────
    final perFootLabor = totalRunFeet * pricing.laborRatePerFoot;
    final laborTotal = perFootLabor < pricing.flatLaborMinimum
        ? pricing.flatLaborMinimum
        : perFootLabor;

    final laborDescription = perFootLabor < pricing.flatLaborMinimum
        ? 'Professional installation (flat minimum)'
        : 'Professional installation';
    final laborLine = EstimateLineItem(
      id: EstimateLineItem.stableId(
        description: laborDescription,
        category: EstimateLineCategory.labor,
      ),
      description: laborDescription,
      quantity: perFootLabor < pricing.flatLaborMinimum
          ? 1
          : double.parse(totalRunFeet.toStringAsFixed(2)),
      unit: perFootLabor < pricing.flatLaborMinimum ? 'flat' : 'ft',
      unitRetailPrice: perFootLabor < pricing.flatLaborMinimum
          ? pricing.flatLaborMinimum
          : pricing.laborRatePerFoot,
      unitDealerCost: 0,
      category: EstimateLineCategory.labor,
    );
    lineItems.add(laborLine);

    final subtotalRetail = subtotalMaterial + laborTotal;
    final estimatedMargin = subtotalRetail - dealerMaterialCost;
    final estimatedMarginPct =
        subtotalRetail > 0 ? (estimatedMargin / subtotalRetail) * 100 : 0;

    return EstimateBreakdown(
      lineItems: lineItems,
      subtotalMaterial: double.parse(subtotalMaterial.toStringAsFixed(2)),
      subtotalLabor: double.parse(laborTotal.toStringAsFixed(2)),
      subtotalRetail: double.parse(subtotalRetail.toStringAsFixed(2)),
      dealerMaterialCost: double.parse(dealerMaterialCost.toStringAsFixed(2)),
      estimatedMargin: double.parse(estimatedMargin.toStringAsFixed(2)),
      estimatedMarginPct:
          double.parse(estimatedMarginPct.toStringAsFixed(2)),
      generatedAt: DateTime.now(),
    );
  }

  // ── Catalog loader ───────────────────────────────────────────────────────

  Future<Map<String, MaterialItem>> _loadCatalog(String dealerCode) async {
    final snap = await _db
        .collection('dealers/$dealerCode/materialCatalog')
        .where('isActive', isEqualTo: true)
        .get();
    return {
      for (final doc in snap.docs) doc.id: MaterialItem.fromFirestore(doc),
    };
  }

  // ── Voltage helper ───────────────────────────────────────────────────────

  String _v(SalesJob job) =>
      job.systemVoltage == SystemVoltage.v24 ? '24v' : '36v';

  // ── Roofline zone ────────────────────────────────────────────────────────

  void _calculateRooflineZone(
    SalesJob job,
    InstallZone zone,
    Map<String, MaterialItem> catalog,
    List<JobMaterialLine> lines,
  ) {
    // Guard: rail selection must be complete before calculating
    if (zone.railType == RailType.none) {
      throw ArgumentError(
        'Zone is a roofline type but has no rail type set. '
        'Rail type must be selected during the sales visit.',
      );
    }
    if (zone.railColor == RailColor.none) {
      throw ArgumentError(
        'Zone has rail type set but no color chosen. '
        'Rail color must be selected during the sales visit.',
      );
    }

    // ── RAILS ──────────────────────────────────────────────────

    // Minimum rails to cover the run distance
    final int baseRails = (zone.runLengthFt / kFeetPerRail).ceil();

    // Each corner: 80mm cut leaves a gap — one extra full rail needed per corner
    final int cornerRails = zone.cornerCount;

    // Pre-overage total
    final int railsCalculated = baseRails + cornerRails;

    // With 10% ordering buffer
    final int railsOrdered =
        (railsCalculated * (1 + kRailOverageRate)).ceil();

    final String railPrefix =
        zone.railType == RailType.onePiece ? '1pc' : '2pc';
    final String railId = 'rail_${railPrefix}_${zone.railColor.name}';

    lines.add(JobMaterialLine(
      materialId: railId,
      materialName: _require(catalog, railId).name,
      unit: MaterialUnit.each,
      calculatedQty: railsCalculated.toDouble(),
      overageQty: railsOrdered.toDouble(),
    ));

    // ── LIGHTS ─────────────────────────────────────────────────
    // Lights are derived from railsCalculated (not railsOrdered).
    // Overage rails are buffer stock on the truck — not placed on the structure.
    //
    // Each full rail contributes 5 lights.
    // Each corner removes 2 light positions (1 per cut rail end × 2 ends per corner).
    //
    // Verification: 90m run, 10 corners
    //   railsCalculated = 90 + 10 = 100
    //   lightsExact = (100 × 5) − (10 × 2) = 480  ✓

    final int lightsExact = (railsCalculated * kPixelsPerFullRail) -
        (zone.cornerCount * kLightsLostPerCorner);

    // Apply 10% overage for defects and handling damage
    final int lightsOrdered =
        (lightsExact * (1 + kLightOverageRate)).ceil();

    // Greedy PCS packing — fewest pieces, largest denomination first
    final int count10 = lightsOrdered ~/ 10;
    final int rem10 = lightsOrdered % 10;
    final int count5 = rem10 ~/ 5;
    final int count1 = rem10 % 5;

    final String v = _v(job);

    // overageRate = 0.0 on all light catalog items — overage applied above
    if (count10 > 0) {
      lines.add(JobMaterialLine(
        materialId: 'light_10pcs_$v',
        materialName: _require(catalog, 'light_10pcs_$v').name,
        unit: MaterialUnit.each,
        calculatedQty: count10.toDouble(),
        overageQty: count10.toDouble(),
      ));
    }
    if (count5 > 0) {
      lines.add(JobMaterialLine(
        materialId: 'light_5pcs_$v',
        materialName: _require(catalog, 'light_5pcs_$v').name,
        unit: MaterialUnit.each,
        calculatedQty: count5.toDouble(),
        overageQty: count5.toDouble(),
      ));
    }
    if (count1 > 0) {
      lines.add(JobMaterialLine(
        materialId: 'light_1pcs_$v',
        materialName: _require(catalog, 'light_1pcs_$v').name,
        unit: MaterialUnit.each,
        calculatedQty: count1.toDouble(),
        overageQty: count1.toDouble(),
      ));
    }

    // ── AMPLIFIER ──────────────────────────────────────────────
    // Use exact (pre-overage) pixel count to decide amplifier need
    if (lightsExact > kAmplifierThreshold) {
      lines.add(_catalogLine(catalog, 'amplifier', 1.0));
    }

    // ── CONNECTOR WIRES ────────────────────────────────────────
    if (zone.connectorRunFt > 0) {
      lines.addAll(_optimizeConnectorWire(zone.connectorRunFt, catalog));
    }
  }

  // ── Rope light zone ──────────────────────────────────────────────────────

  void _calculateRopeZone(
    InstallZone zone,
    Map<String, MaterialItem> catalog,
    List<JobMaterialLine> lines,
  ) {
    // Rope light bends at corners — no cuts required, cornerCount is ignored.
    // No rails, no pixel PCS for rope zones.

    final int piecesExact = (zone.runLengthFt / kFeetPerRopePiece).ceil();
    final int piecesOrdered =
        (piecesExact * (1 + kRopeOverageRate)).ceil();

    lines.add(JobMaterialLine(
      materialId: 'rope_diffused_5m',
      materialName: _require(catalog, 'rope_diffused_5m').name,
      unit: MaterialUnit.piece,
      calculatedQty: piecesExact.toDouble(),
      overageQty: piecesOrdered.toDouble(),
    ));

    // Connector wires still apply — rope zones connect to the controller too
    if (zone.connectorRunFt > 0) {
      lines.addAll(_optimizeConnectorWire(zone.connectorRunFt, catalog));
    }
  }

  // ── Connector wire optimizer ─────────────────────────────────────────────

  List<JobMaterialLine> _optimizeConnectorWire(
    double totalFt,
    Map<String, MaterialItem> catalog,
  ) {
    // Greedy algorithm — always minimize number of wire pieces.
    // Uses largest available length first, works down to 1ft.
    // 15% overage applied to total distance BEFORE optimizing.

    const lengths = [20.0, 10.0, 5.0, 2.0, 1.0];
    const ids = [
      'wire_conn_20ft',
      'wire_conn_10ft',
      'wire_conn_5ft',
      'wire_conn_2ft',
      'wire_conn_1ft',
    ];

    // Apply 15% overage, then ceiling
    var remaining =
        (totalFt * (1 + kConnectorOverageRate)).ceilToDouble();
    final result = <JobMaterialLine>[];

    for (int i = 0; i < lengths.length; i++) {
      if (remaining <= 0) break;
      final count = (remaining / lengths[i]).floor();
      if (count > 0) {
        result.add(JobMaterialLine(
          materialId: ids[i],
          materialName: _require(catalog, ids[i]).name,
          unit: MaterialUnit.each,
          calculatedQty: count.toDouble(),
          overageQty: count.toDouble(), // overage applied at run level above
        ));
        remaining -= count * lengths[i];
      }
    }
    return result;
  }

  // ── Job-level items ──────────────────────────────────────────────────────

  void _addJobLevelItems(
    SalesJob job,
    Map<String, MaterialItem> catalog,
    List<JobMaterialLine> lines,
  ) {
    // T-CONNECTORS — mid-run injection points (not at zone start/end)
    int tCount = 0;
    for (final zone in job.zones) {
      tCount += zone.injections
          .where((p) => p.positionFt > 0 && p.positionFt < zone.runLengthFt)
          .length;
    }
    if (tCount > 0) {
      lines.add(JobMaterialLine(
        materialId: 't_connector',
        materialName: _require(catalog, 't_connector').name,
        unit: MaterialUnit.each,
        calculatedQty: tCount.toDouble(),
        overageQty: (tCount * 1.25).ceilToDouble(),
      ));
    }

    // Y-CONNECTORS — branch splits, unknown at calc time
    // Placeholder line so PM can fill in during approval
    lines.add(JobMaterialLine(
      materialId: 'y_connector',
      materialName: _require(catalog, 'y_connector').name,
      unit: MaterialUnit.each,
      calculatedQty: 0,
      overageQty: 0,
    ));

    // RADAR SENSOR — one per installation
    lines.add(_catalogLine(catalog, 'radar_sensor', 1.0));

    // CONTROLLER — one per installation
    lines.add(_catalogLine(catalog, 'controller', 1.0));

    // POWER SUPPLIES — read from existing PowerMount model, voltage-aware
    int count350 = 0;
    int count600 = 0;
    for (final zone in job.zones) {
      count350 += zone.mounts.where((m) => m.supplySize == '350w').length;
      count600 += zone.mounts.where((m) => m.supplySize == '600w').length;
    }
    final String v = _v(job);
    if (count350 > 0) {
      lines.add(
          _catalogLine(catalog, 'psu_350w_$v', count350.toDouble()));
    }
    if (count600 > 0) {
      lines.add(
          _catalogLine(catalog, 'psu_600w_$v', count600.toDouble()));
    }
  }

  // ── Deduplication ────────────────────────────────────────────────────────

  void _deduplicateLines(List<JobMaterialLine> lines) {
    // Group by materialId, sum calculatedQty and overageQty.
    // Different IDs (rail colors, wire lengths) are NOT merged.
    // Same-voltage light PCS across zones ARE merged.

    final Map<String, JobMaterialLine> merged = {};
    for (final line in lines) {
      if (merged.containsKey(line.materialId)) {
        final existing = merged[line.materialId]!;
        merged[line.materialId] = existing.copyWith(
          calculatedQty: existing.calculatedQty + line.calculatedQty,
          overageQty: existing.overageQty + line.overageQty,
        );
      } else {
        merged[line.materialId] = line;
      }
    }
    lines
      ..clear()
      ..addAll(merged.values);
  }

  // ── Helpers ──────────────────────────────────────────────────────────────

  JobMaterialLine _catalogLine(
    Map<String, MaterialItem> catalog,
    String id,
    double rawQty,
  ) {
    final item = _require(catalog, id);
    final overageQty = item.overageRate > 0
        ? (rawQty * (1 + item.overageRate)).ceilToDouble()
        : rawQty;
    return JobMaterialLine(
      materialId: id,
      materialName: item.name,
      unit: item.unit,
      calculatedQty: rawQty,
      overageQty: overageQty,
    );
  }

  MaterialItem _require(Map<String, MaterialItem> catalog, String id) {
    final item = catalog[id];
    if (item == null) {
      throw StateError(
        'Catalog item "$id" not found. '
        'Verify seed data is deployed for this dealer.',
      );
    }
    return item;
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final materialCalculationServiceProvider =
    Provider<MaterialCalculationService>(
  (ref) => MaterialCalculationService(FirebaseFirestore.instance),
);
