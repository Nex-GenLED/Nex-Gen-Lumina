import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/providers/material_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Job Material List Screen
//
// Shows the calculated material list for a sales job.
// If no list exists yet, offers a "Calculate Materials" button.
// ─────────────────────────────────────────────────────────────────────────────

class JobMaterialListScreen extends ConsumerStatefulWidget {
  final String jobId;
  const JobMaterialListScreen({super.key, required this.jobId});

  @override
  ConsumerState<JobMaterialListScreen> createState() =>
      _JobMaterialListScreenState();
}

class _JobMaterialListScreenState
    extends ConsumerState<JobMaterialListScreen> {
  bool _isCalculating = false;

  Future<void> _calculateMaterials() async {
    setState(() => _isCalculating = true);
    try {
      final doc = await FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(widget.jobId)
          .get();
      if (!doc.exists) throw StateError('Job not found');

      final job = SalesJob.fromJson(doc.data()!);
      final calcService = ref.read(materialCalculationServiceProvider);
      final invService = ref.read(inventoryServiceProvider);

      final session = ref.read(currentSalesSessionProvider);
      final calculatedBy = session?.salespersonUid ?? 'unknown';

      final list = await calcService.calculateForJob(
        job: job,
        calculatedBy: calculatedBy,
      );

      await invService.saveMaterialList(list);
    } on ArgumentError catch (e) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: NexGenPalette.gunmetal,
            title: const Text('Missing zone data',
                style: TextStyle(color: Colors.white)),
            content: Text(e.message.toString(),
                style: const TextStyle(color: NexGenPalette.textMedium)),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK',
                    style: TextStyle(color: NexGenPalette.cyan)),
              ),
            ],
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Calculation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isCalculating = false);
    }
  }

  Future<void> _approveList(JobMaterialList list) async {
    try {
      await FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(widget.jobId)
          .collection('materialList')
          .doc('current')
          .update({
        'status': JobMaterialStatus.approved.name,
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Approval failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final matListAsync = ref.watch(jobMaterialListProvider(widget.jobId));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Materials'),
      ),
      body: matListAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white))),
        data: (matList) {
          if (matList == null) return _buildEmptyState();
          return _buildMaterialList(matList);
        },
      ),
    );
  }

  // ── Empty state — no material list yet ─────────────────────────────────

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No material list yet',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
          const SizedBox(height: 8),
          Text('Calculate materials from the zone data',
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
          const SizedBox(height: 24),
          ElevatedButton.icon(
            onPressed: _isCalculating ? null : _calculateMaterials,
            icon: _isCalculating
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: Colors.black))
                : const Icon(Icons.calculate_outlined, color: Colors.black),
            label: Text(
              _isCalculating ? 'Calculating...' : 'Calculate Materials',
              style: const TextStyle(
                  color: Colors.black, fontWeight: FontWeight.w600),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              disabledBackgroundColor:
                  NexGenPalette.cyan.withValues(alpha: 0.3),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  // ── Material list view ─────────────────────────────────────────────────

  Widget _buildMaterialList(JobMaterialList matList) {
    // Load inventory for stock checks
    final session = ref.watch(currentSalesSessionProvider);
    final dealerCode = session?.dealerCode ?? matList.dealerCode;
    final inventoryAsync = ref.watch(inventoryProvider(dealerCode));
    final inventoryMap = inventoryAsync.when<Map<String, InventoryRecord>>(
      data: (records) => {for (final r in records) r.materialId: r},
      loading: () => {},
      error: (_, __) => {},
    );

    return Column(
      children: [
        // Header stats + note
        _buildHeader(matList, dealerCode),

        // Grouped material lines
        Expanded(
          child: _buildGroupedLines(matList, inventoryMap),
        ),

        // Bottom bar
        _buildBottomBar(matList),
      ],
    );
  }

  Widget _buildHeader(JobMaterialList matList, String dealerCode) {
    // We need SalesJob data for header stats — load from Firestore
    return FutureBuilder<DocumentSnapshot>(
      future: FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(widget.jobId)
          .get(),
      builder: (context, snap) {
        double totalRun = 0;
        int totalZones = 0;
        int totalCorners = 0;

        if (snap.hasData && snap.data!.exists) {
          final job = SalesJob.fromJson(snap.data!.data() as Map<String, dynamic>);
          totalRun = job.zones.fold(0.0, (acc, z) => acc + z.runLengthFt);
          totalZones = job.zones.length;
          totalCorners =
              job.zones.fold(0, (acc, z) => acc + z.cornerCount);
        }

        return Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 0),
          child: Column(
            children: [
              // 4 stat cells
              Row(
                children: [
                  _statCell('Total Run', '${totalRun.toStringAsFixed(0)} ft'),
                  _statCell('Zones', '$totalZones'),
                  _statCell('Corners', '$totalCorners'),
                  _statCell('Line Items', '${matList.lines.length}'),
                ],
              ),
              const SizedBox(height: 8),
              // Note
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: NexGenPalette.amber.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'Wire runs and power outlet costs are in the sales estimate.',
                  style: TextStyle(
                      color: NexGenPalette.amber, fontSize: 12),
                ),
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  Widget _statCell(String label, String value) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.montserrat(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: NexGenPalette.textMedium, fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ── Grouped lines by MaterialCategory ──────────────────────────────────

  Widget _buildGroupedLines(
    JobMaterialList matList,
    Map<String, InventoryRecord> inventoryMap,
  ) {
    // Group lines by category — we infer from materialId prefix
    final grouped = <MaterialCategory, List<JobMaterialLine>>{};
    for (final line in matList.lines) {
      final cat = _inferCategory(line.materialId);
      (grouped[cat] ??= []).add(line);
    }

    final categories = grouped.keys.toList()
      ..sort((a, b) => a.index.compareTo(b.index));

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: categories.map((cat) {
        final lines = grouped[cat]!;
        final isLightPcs = cat == MaterialCategory.lightPcs;

        // Total pixels for light PCS sub-note
        int totalLightPcs = 0;
        if (isLightPcs) {
          for (final l in lines) {
            final multiplier = _lightMultiplier(l.materialId);
            totalLightPcs += (l.overageQty * multiplier).toInt();
          }
        }

        return ExpansionTile(
          tilePadding: EdgeInsets.zero,
          childrenPadding:
              const EdgeInsets.only(left: 8, right: 8, bottom: 8),
          initiallyExpanded: true,
          title: Text(
            _categoryLabel(cat),
            style: TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 14,
                fontWeight: FontWeight.w600),
          ),
          subtitle: isLightPcs
              ? Text('$totalLightPcs pixels · optimized packing',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 11))
              : null,
          iconColor: NexGenPalette.cyan,
          collapsedIconColor: NexGenPalette.textMedium,
          children: lines.map((line) {
            final inv = inventoryMap[line.materialId];
            return _buildLineRow(line, inv);
          }).toList(),
        );
      }).toList(),
    );
  }

  Widget _buildLineRow(JobMaterialLine line, InventoryRecord? inv) {
    final isRail = line.materialId.startsWith('rail_');
    final isYConnector =
        line.materialId == 'y_connector' && line.calculatedQty == 0;

    // Stock chip
    Widget stockChip;
    if (inv != null) {
      final avail = inv.quantityAvailable;
      if (avail >= line.overageQty) {
        stockChip = _chip('In Stock', NexGenPalette.green);
      } else if (avail > 0) {
        stockChip = _chip('Low Stock', NexGenPalette.amber);
      } else {
        stockChip = _chip('Insufficient', Colors.red);
      }
    } else {
      stockChip = _chip('No data', NexGenPalette.textMedium);
    }

    if (isYConnector) {
      stockChip = _chip('Set qty', NexGenPalette.amber);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          // Rail color swatch
          if (isRail) ...[
            Container(
              width: 14,
              height: 14,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _railSwatchColor(line.materialId),
                border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2)),
              ),
            ),
          ],

          // Name
          Expanded(
            child: Text(line.materialName,
                style:
                    const TextStyle(color: Colors.white, fontSize: 13)),
          ),

          // Calculated qty (muted)
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Text(
              line.calculatedQty.toStringAsFixed(0),
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),

          // Overage qty (accent)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              line.overageQty.toStringAsFixed(0),
              style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 13,
                  fontWeight: FontWeight.w600),
            ),
          ),

          // Unit
          SizedBox(
            width: 30,
            child: Text(
              line.unit == MaterialUnit.piece ? 'pcs' : 'ea',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 11),
            ),
          ),

          // Stock chip
          stockChip,
        ],
      ),
    );
  }

  Widget _chip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(label,
          style: TextStyle(
              color: color, fontSize: 10, fontWeight: FontWeight.w600)),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(JobMaterialList matList) {
    final isDraft = matList.status == JobMaterialStatus.draft;
    final canCheckout = matList.status.index >=
        JobMaterialStatus.approved.index;

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border:
            Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Status badge
          Row(
            children: [
              Text('Status: ',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13)),
              _chip(matList.status.name.toUpperCase(),
                  _statusChipColor(matList.status)),
              const Spacer(),
              Text('${matList.lines.length} line items',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 12)),
            ],
          ),
          const SizedBox(height: 12),

          if (isDraft)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => _approveList(matList),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Approve Material List',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),

          if (canCheckout)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push(
                    '/sales/jobs/${widget.jobId}/materials/checkout'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Go to Checkout',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  MaterialCategory _inferCategory(String id) {
    if (id.startsWith('light_')) return MaterialCategory.lightPcs;
    if (id.startsWith('rope_')) return MaterialCategory.ropeLighting;
    if (id.startsWith('rail_1pc_')) return MaterialCategory.railOnePiece;
    if (id.startsWith('rail_2pc_')) return MaterialCategory.railTwoPiece;
    if (id.startsWith('wire_conn_')) return MaterialCategory.connectorWire;
    if (id.startsWith('psu_')) return MaterialCategory.powerSupply;
    if (id == 'controller') return MaterialCategory.controller;
    return MaterialCategory.accessories;
  }

  String _categoryLabel(MaterialCategory cat) {
    return const {
      MaterialCategory.lightPcs: 'Light PCS',
      MaterialCategory.ropeLighting: 'Rope Lighting',
      MaterialCategory.railOnePiece: '1-Piece Rails',
      MaterialCategory.railTwoPiece: '2-Piece Rails',
      MaterialCategory.connectorWire: 'Connector Wires',
      MaterialCategory.accessories: 'Accessories',
      MaterialCategory.controller: 'Controller',
      MaterialCategory.powerSupply: 'Power Supplies',
    }[cat]!;
  }

  int _lightMultiplier(String id) {
    if (id.contains('10pcs')) return 10;
    if (id.contains('5pcs')) return 5;
    return 1;
  }

  Color _railSwatchColor(String id) {
    if (id.contains('_black')) return const Color(0xFF1C1C1C);
    if (id.contains('_brown')) return const Color(0xFF5C3D1E);
    if (id.contains('_beige')) return const Color(0xFFD4B896);
    if (id.contains('_white')) return const Color(0xFFF5F5F5);
    if (id.contains('_navy')) return const Color(0xFF1B2A4A);
    if (id.contains('_silver')) return const Color(0xFFA8A8A8);
    if (id.contains('_grey')) return const Color(0xFF6B6B6B);
    return Colors.grey;
  }

  Color _statusChipColor(JobMaterialStatus status) {
    switch (status) {
      case JobMaterialStatus.draft:
        return NexGenPalette.textMedium;
      case JobMaterialStatus.approved:
        return NexGenPalette.cyan;
      case JobMaterialStatus.checkedOut:
        return NexGenPalette.amber;
      case JobMaterialStatus.day1Complete:
        return NexGenPalette.amber;
      case JobMaterialStatus.complete:
        return NexGenPalette.green;
    }
  }
}
