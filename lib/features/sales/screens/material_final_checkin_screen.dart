import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/providers/material_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Final Check-In Screen
//
// Reconciles inventory after installation is complete. The installer enters
// Day 2 usage and returned quantities; waste is computed automatically.
// On submit, InventoryService releases reservations and restocks unused items.
// ─────────────────────────────────────────────────────────────────────────────

class MaterialFinalCheckInScreen extends ConsumerStatefulWidget {
  final String jobId;
  const MaterialFinalCheckInScreen({super.key, required this.jobId});

  @override
  ConsumerState<MaterialFinalCheckInScreen> createState() =>
      _MaterialFinalCheckInScreenState();
}

class _MaterialFinalCheckInScreenState
    extends ConsumerState<MaterialFinalCheckInScreen> {
  /// Per-line Day 2 used, keyed by materialId.
  final Map<String, double> _day2Used = {};

  /// Per-line returned qty, keyed by materialId.
  final Map<String, double> _returned = {};

  /// Catalog for cost calculations, loaded once.
  Map<String, MaterialItem>? _catalog;

  bool _isSubmitting = false;

  @override
  void initState() {
    super.initState();
    _loadCatalog();
  }

  Future<void> _loadCatalog() async {
    try {
      final session = ref.read(currentSalesSessionProvider);
      if (session == null) return;
      final snap = await FirebaseFirestore.instance
          .collection('dealers/${session.dealerCode}/materialCatalog')
          .where('isActive', isEqualTo: true)
          .get();
      if (mounted) {
        setState(() {
          _catalog = {
            for (final doc in snap.docs)
              doc.id: MaterialItem.fromFirestore(doc),
          };
        });
      }
    } catch (_) {
      // Catalog load failure is non-blocking — cost summaries show "—"
    }
  }

  double _getDay2(JobMaterialLine line) =>
      _day2Used[line.materialId] ?? 0;

  double _getReturned(JobMaterialLine line) =>
      _returned[line.materialId] ?? 0;

  double _getWaste(JobMaterialLine line) =>
      line.checkedOutQty - line.usedDay1 - _getDay2(line) - _getReturned(line);

  double _getAvailable(JobMaterialLine line) =>
      line.checkedOutQty - line.usedDay1;

  bool _hasError(List<JobMaterialLine> lines) {
    for (final line in lines) {
      final d2 = _getDay2(line);
      final ret = _getReturned(line);
      if (d2 + ret > _getAvailable(line)) return true;
      if (d2 < 0 || ret < 0) return true;
    }
    return false;
  }

  double _costCents(String materialId, double qty) {
    if (_catalog == null) return 0;
    final item = _catalog![materialId];
    if (item == null) return 0;
    return qty * item.unitCostCents;
  }

  Future<void> _submit(JobMaterialList matList) async {
    if (_hasError(matList.lines)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Fix validation errors before submitting')),
      );
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      final session = ref.read(currentSalesSessionProvider);
      final invService = ref.read(inventoryServiceProvider);

      final finalLines = matList.lines.map((line) {
        return JobMaterialLine(
          materialId: line.materialId,
          materialName: line.materialName,
          unit: line.unit,
          calculatedQty: line.calculatedQty,
          overageQty: line.overageQty,
          checkedOutQty: line.checkedOutQty,
          usedDay1: line.usedDay1,
          usedDay2: _day2Used[line.materialId] ?? 0,
          returnedQty: _returned[line.materialId] ?? 0,
        );
      }).toList();

      await invService.checkInFinal(
        jobId: widget.jobId,
        dealerCode: session?.dealerCode ?? matList.dealerCode,
        installerId: session?.salespersonUid ?? 'unknown',
        finalLines: finalLines,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Job complete. Inventory reconciled.')),
        );
        Navigator.of(context).popUntil((route) => route.isFirst);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Reconciliation failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
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
        title: const Text('Final Check-In'),
      ),
      body: matListAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white))),
        data: (matList) {
          if (matList == null) return _buildGuard('No material list found');
          if (matList.status != JobMaterialStatus.day1Complete) {
            return _buildGuard(
                'Not ready for final check-in — status is "${matList.status.name}"');
          }
          return _buildFinalView(matList);
        },
      ),
    );
  }

  // ── Guard ──────────────────────────────────────────────────────────────

  Widget _buildGuard(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block,
              size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                Text('Go back', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  // ── Final view ─────────────────────────────────────────────────────────

  Widget _buildFinalView(JobMaterialList matList) {
    // Compute live summaries
    double totalUsedCents = 0;
    double returnedCents = 0;
    double wasteCents = 0;
    double totalCheckedOut = 0;
    double totalWasteQty = 0;

    for (final line in matList.lines) {
      final d2 = _getDay2(line);
      final ret = _getReturned(line);
      final wasteQty = max(0.0,
          line.checkedOutQty - line.usedDay1 - d2 - ret);

      totalUsedCents += _costCents(line.materialId, line.usedDay1 + d2);
      returnedCents += _costCents(line.materialId, ret);
      wasteCents += _costCents(line.materialId, wasteQty);
      totalCheckedOut += line.checkedOutQty;
      totalWasteQty += wasteQty;
    }

    final efficiencyPct = totalCheckedOut > 0
        ? ((1 - (totalWasteQty / totalCheckedOut)) * 100)
        : 100.0;

    final hasError = _hasError(matList.lines);

    return Column(
      children: [
        // Phase indicator
        _buildPhaseBar(3),

        // Summary cards
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: Row(
            children: [
              _summaryCard(
                'Total Used',
                _formatCost(totalUsedCents),
                NexGenPalette.cyan,
              ),
              const SizedBox(width: 8),
              _summaryCard(
                'Returned',
                _formatCost(returnedCents),
                NexGenPalette.green,
              ),
              const SizedBox(width: 8),
              _summaryCard(
                'Waste / Loss',
                _formatCost(wasteCents),
                NexGenPalette.amber,
                subtitle: '${efficiencyPct.toStringAsFixed(1)}% efficiency',
              ),
            ],
          ),
        ),

        // Table
        Expanded(
          child: _buildTable(matList),
        ),

        // Bottom bar
        _buildBottomBar(matList, hasError),
      ],
    );
  }

  Widget _summaryCard(String label, String value, Color color,
      {String? subtitle}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Text(value,
                style: GoogleFonts.montserrat(
                    color: color,
                    fontSize: 16,
                    fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(label,
                style: TextStyle(
                    color: color.withValues(alpha: 0.7), fontSize: 10)),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle,
                  style: TextStyle(
                      color: color.withValues(alpha: 0.5), fontSize: 9)),
            ],
          ],
        ),
      ),
    );
  }

  String _formatCost(double cents) {
    if (_catalog == null) return '—';
    final dollars = cents / 100;
    return '\$${dollars.toStringAsFixed(2)}';
  }

  // ── Table ──────────────────────────────────────────────────────────────

  Widget _buildTable(JobMaterialList matList) {
    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      children: [
        // Header row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(8)),
          ),
          child: Row(
            children: [
              _headerCell('Material', flex: 3),
              _headerCell('Out', flex: 1),
              _headerCell('Day 2', flex: 2),
              _headerCell('Return', flex: 2),
              _headerCell('Waste', flex: 1),
              _headerCell('Unit', flex: 1),
            ],
          ),
        ),

        // Data rows
        ...matList.lines.asMap().entries.map((entry) {
          final i = entry.key;
          final line = entry.value;
          return _buildTableRow(line, i.isOdd);
        }),
      ],
    );
  }

  Widget _headerCell(String text, {required int flex}) {
    return Expanded(
      flex: flex,
      child: Text(text,
          style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 10,
              fontWeight: FontWeight.w600)),
    );
  }

  Widget _buildTableRow(JobMaterialLine line, bool alt) {
    final d2 = _getDay2(line);
    final ret = _getReturned(line);
    final wasteQty = _getWaste(line);
    final available = _getAvailable(line);
    final overUse = d2 + ret > available;

    // Waste coloring
    Color wasteColor;
    if (wasteQty <= 0) {
      wasteColor = NexGenPalette.green;
    } else if (line.checkedOutQty > 0 &&
        wasteQty / line.checkedOutQty <= 0.05) {
      wasteColor = NexGenPalette.amber;
    } else {
      wasteColor = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: alt
            ? NexGenPalette.gunmetal90
            : NexGenPalette.matteBlack,
        border: Border(
          bottom: BorderSide(color: NexGenPalette.line, width: 0.5),
          left: overUse
              ? const BorderSide(color: Colors.red, width: 2)
              : BorderSide.none,
        ),
      ),
      child: Row(
        children: [
          // Material name
          Expanded(
            flex: 3,
            child: Text(line.materialName,
                style:
                    const TextStyle(color: Colors.white, fontSize: 12),
                overflow: TextOverflow.ellipsis),
          ),

          // Checked out (read-only)
          Expanded(
            flex: 1,
            child: Text(
              line.checkedOutQty.toStringAsFixed(0),
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ),

          // Day 2 Used (input)
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextFormField(
                initialValue: d2 > 0 ? d2.toStringAsFixed(0) : '',
                keyboardType: TextInputType.number,
                style: TextStyle(
                    color: overUse ? Colors.red : Colors.white,
                    fontSize: 12),
                decoration: _compactInputDecoration(overUse),
                onChanged: (val) {
                  setState(() =>
                      _day2Used[line.materialId] =
                          double.tryParse(val) ?? 0);
                },
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Returned (input)
          Expanded(
            flex: 2,
            child: SizedBox(
              height: 32,
              child: TextFormField(
                initialValue: ret > 0 ? ret.toStringAsFixed(0) : '',
                keyboardType: TextInputType.number,
                style: const TextStyle(color: Colors.white, fontSize: 12),
                decoration: _compactInputDecoration(false),
                onChanged: (val) {
                  setState(() =>
                      _returned[line.materialId] =
                          double.tryParse(val) ?? 0);
                },
              ),
            ),
          ),
          const SizedBox(width: 4),

          // Waste (auto, read-only)
          Expanded(
            flex: 1,
            child: Text(
              max(0, wasteQty).toStringAsFixed(0),
              style: TextStyle(
                  color: wasteColor,
                  fontSize: 12,
                  fontWeight: FontWeight.w600),
            ),
          ),

          // Unit
          Expanded(
            flex: 1,
            child: Text(
              line.unit == MaterialUnit.piece ? 'pcs' : 'ea',
              style: TextStyle(
                  color: NexGenPalette.textMedium, fontSize: 10),
            ),
          ),
        ],
      ),
    );
  }

  InputDecoration _compactInputDecoration(bool hasError) {
    return InputDecoration(
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
      isDense: true,
      filled: true,
      fillColor: NexGenPalette.gunmetal,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(color: NexGenPalette.line),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide: BorderSide(
            color: hasError ? Colors.red : NexGenPalette.line),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(6),
        borderSide:
            const BorderSide(color: NexGenPalette.cyan),
      ),
    );
  }

  // ── Phase indicator ────────────────────────────────────────────────────

  Widget _buildPhaseBar(int activeIndex) {
    const labels = ['Approved', 'Checked Out', 'Day 1', 'Final'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isComplete = i < activeIndex;
          final isActive = i == activeIndex;
          final color = isComplete
              ? NexGenPalette.green
              : isActive
                  ? NexGenPalette.cyan
                  : NexGenPalette.textMedium;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isComplete || isActive
                        ? color.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: isComplete
                      ? Icon(Icons.check, size: 13, color: color)
                      : isActive
                          ? Center(
                              child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color)))
                          : null,
                ),
                const SizedBox(width: 4),
                Text(labels[i],
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400)),
                if (i < labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isComplete
                          ? NexGenPalette.green.withValues(alpha: 0.4)
                          : NexGenPalette.line,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(JobMaterialList matList, bool hasError) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Disclaimer
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: Row(
              children: [
                Icon(Icons.info_outline,
                    size: 14, color: NexGenPalette.textMedium),
                const SizedBox(width: 6),
                Text('Inventory will be updated on submit',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 12)),
              ],
            ),
          ),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _isSubmitting || hasError
                  ? null
                  : () => _submit(matList),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.green,
                disabledBackgroundColor:
                    NexGenPalette.green.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.black))
                  : Text(
                      hasError
                          ? 'Fix errors before submitting'
                          : 'Complete Job & Reconcile Inventory',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
            ),
          ),
        ],
      ),
    );
  }
}
