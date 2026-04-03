import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/providers/material_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/pdf_service.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Material Checkout Screen
//
// Allows the installer to adjust per-line pull quantities before checking out
// materials from dealer inventory. Guards against insufficient stock.
// ─────────────────────────────────────────────────────────────────────────────

class MaterialCheckoutScreen extends ConsumerStatefulWidget {
  final String jobId;
  const MaterialCheckoutScreen({super.key, required this.jobId});

  @override
  ConsumerState<MaterialCheckoutScreen> createState() =>
      _MaterialCheckoutScreenState();
}

class _MaterialCheckoutScreenState
    extends ConsumerState<MaterialCheckoutScreen> {
  /// Local pull qty overrides, keyed by materialId.
  final Map<String, double> _pullQty = {};
  bool _isSubmitting = false;

  double _getPullQty(JobMaterialLine line) =>
      _pullQty[line.materialId] ?? line.overageQty;

  void _adjust(JobMaterialLine line, int delta) {
    final current = _getPullQty(line);
    final next = (current + delta).clamp(0.0, 9999.0);
    setState(() => _pullQty[line.materialId] = next);
  }

  Future<void> _confirmCheckout(JobMaterialList matList) async {
    setState(() => _isSubmitting = true);
    try {
      final session = ref.read(currentSalesSessionProvider);
      final invService = ref.read(inventoryServiceProvider);

      // Build updated lines with checkedOutQty = adjusted pull qty
      final updatedLines = matList.lines.map((line) {
        final qty = _getPullQty(line);
        return JobMaterialLine(
          materialId: line.materialId,
          materialName: line.materialName,
          unit: line.unit,
          calculatedQty: line.calculatedQty,
          overageQty: line.overageQty,
          checkedOutQty: qty,
        );
      }).toList();

      await invService.checkOutMaterials(
        jobId: widget.jobId,
        dealerCode: session?.dealerCode ?? matList.dealerCode,
        installerId: session?.salespersonUid ?? 'unknown',
        lines: updatedLines,
      );

      if (mounted) {
        context.push('/sales/jobs/${widget.jobId}/materials/day1');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Checkout failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  Future<void> _exportPackingList(JobMaterialList matList) async {
    try {
      // Build lines snapshot with current pull qty
      final snapshot = matList.lines.map((line) {
        return JobMaterialLine(
          materialId: line.materialId,
          materialName: line.materialName,
          unit: line.unit,
          calculatedQty: line.calculatedQty,
          overageQty: line.overageQty,
          checkedOutQty: _getPullQty(line),
        );
      }).toList();

      final exportList = JobMaterialList(
        jobId: matList.jobId,
        jobNumber: matList.jobNumber,
        dealerCode: matList.dealerCode,
        status: matList.status,
        lines: snapshot,
        calculatedBy: matList.calculatedBy,
        calculatedAt: matList.calculatedAt,
      );

      final pdfService = ref.read(pdfServiceProvider);
      final bytes = await pdfService.generatePackingList(exportList);
      await pdfService.savePdfToDevice(
          bytes, 'packing_list_${matList.jobNumber}.pdf');
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Export failed: $e')),
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
        title: const Text('Material Checkout'),
      ),
      body: matListAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white))),
        data: (matList) {
          if (matList == null) {
            return _buildNotReady('No material list found');
          }
          if (matList.status != JobMaterialStatus.approved) {
            return _buildNotReady(
                'Not ready for checkout — status is "${matList.status.name}"');
          }
          return _buildCheckoutView(matList);
        },
      ),
    );
  }

  // ── Guard state ────────────────────────────────────────────────────────

  Widget _buildNotReady(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block,
              size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5), fontSize: 15)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Go back', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  // ── Checkout view ──────────────────────────────────────────────────────

  Widget _buildCheckoutView(JobMaterialList matList) {
    final session = ref.watch(currentSalesSessionProvider);
    final dealerCode = session?.dealerCode ?? matList.dealerCode;
    final inventoryAsync = ref.watch(inventoryProvider(dealerCode));
    final invMap = inventoryAsync.when<Map<String, InventoryRecord>>(
      data: (records) => {for (final r in records) r.materialId: r},
      loading: () => {},
      error: (_, __) => {},
    );

    // Check for over-pull warnings
    final warnings = <String>[];
    bool anyOverPull = false;
    for (final line in matList.lines) {
      final pull = _getPullQty(line);
      if (pull <= 0) continue;
      final inv = invMap[line.materialId];
      if (inv != null && pull > inv.quantityAvailable) {
        anyOverPull = true;
        warnings.add(
            '${line.materialName} — only ${inv.quantityAvailable.toStringAsFixed(0)} on hand, pulling ${pull.toStringAsFixed(0)}');
      }
    }

    return Column(
      children: [
        // Phase indicator
        _buildPhaseBar(1),

        // Warning banner
        if (warnings.isNotEmpty)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.red.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: warnings
                  .map((w) => Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Icon(Icons.warning_amber_rounded,
                                size: 14, color: Colors.red),
                            const SizedBox(width: 6),
                            Expanded(
                                child: Text(w,
                                    style: const TextStyle(
                                        color: Colors.red, fontSize: 12))),
                          ],
                        ),
                      ))
                  .toList(),
            ),
          ),

        // Lines
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: matList.lines.length,
            itemBuilder: (context, i) {
              final line = matList.lines[i];
              final inv = invMap[line.materialId];
              final isConnWire = line.materialId.startsWith('wire_conn_');
              final showConnHeader = isConnWire &&
                  (i == 0 ||
                      !matList.lines[i - 1].materialId
                          .startsWith('wire_conn_'));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (showConnHeader)
                    Padding(
                      padding: const EdgeInsets.only(top: 12, bottom: 6),
                      child: Text(
                          'Connector Wires · optimized for fewest pieces',
                          style: TextStyle(
                              color: NexGenPalette.cyan,
                              fontSize: 12,
                              fontWeight: FontWeight.w500)),
                    ),
                  _buildLineRow(line, inv),
                ],
              );
            },
          ),
        ),

        // Bottom bar
        _buildBottomBar(matList, anyOverPull),
      ],
    );
  }

  // ── Phase indicator ────────────────────────────────────────────────────

  Widget _buildPhaseBar(int activeIndex) {
    const labels = ['Approved', 'Checkout', 'Day 1', 'Final'];

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
                // Dot / check
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color:
                        isComplete || isActive ? color.withValues(alpha: 0.15) : Colors.transparent,
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
                                      shape: BoxShape.circle, color: color)))
                          : null,
                ),
                const SizedBox(width: 4),
                Text(labels[i],
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400)),
                // Connector line between dots
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

  // ── Line row ───────────────────────────────────────────────────────────

  Widget _buildLineRow(JobMaterialLine line, InventoryRecord? inv) {
    final isRail = line.materialId.startsWith('rail_');
    final isYZero =
        line.materialId == 'y_connector' && line.overageQty == 0;
    final pull = _getPullQty(line);

    // Availability label
    Widget availLabel;
    if (inv != null) {
      final avail = inv.quantityAvailable;
      if (avail <= 0) {
        availLabel = Text('Out of stock',
            style: TextStyle(color: Colors.red, fontSize: 10, fontWeight: FontWeight.w600));
      } else if (avail < pull) {
        availLabel = Text('Only ${avail.toStringAsFixed(0)} avail',
            style: TextStyle(color: NexGenPalette.amber, fontSize: 10, fontWeight: FontWeight.w600));
      } else {
        availLabel = Text('${avail.toStringAsFixed(0)} avail',
            style: TextStyle(color: NexGenPalette.green, fontSize: 10, fontWeight: FontWeight.w600));
      }
    } else {
      availLabel = Text('—',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 10));
    }

    final dimmed = isYZero;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Opacity(
        opacity: dimmed ? 0.4 : 1.0,
        child: Row(
          children: [
            // Rail swatch
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

            // Name + unit + Y-connector note
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(line.materialName,
                      style: const TextStyle(
                          color: Colors.white, fontSize: 13)),
                  Text(
                    line.unit == MaterialUnit.piece ? 'piece' : 'each',
                    style: TextStyle(
                        color: NexGenPalette.textMedium, fontSize: 10),
                  ),
                  if (isYZero)
                    Text('Not required — PM set to 0',
                        style: TextStyle(
                            color: NexGenPalette.amber, fontSize: 10)),
                ],
              ),
            ),

            // Suggested qty (muted)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Column(
                children: [
                  Text(line.overageQty.toStringAsFixed(0),
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 11)),
                  Text('sug.',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 9)),
                ],
              ),
            ),

            // Stepper
            if (!dimmed) ...[
              _stepperButton(Icons.remove, () => _adjust(line, -1)),
              Container(
                width: 40,
                alignment: Alignment.center,
                child: Text(pull.toStringAsFixed(0),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600)),
              ),
              _stepperButton(Icons.add, () => _adjust(line, 1)),
            ],

            const SizedBox(width: 8),

            // Availability
            SizedBox(width: 70, child: availLabel),
          ],
        ),
      ),
    );
  }

  Widget _stepperButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 28,
        height: 28,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: NexGenPalette.gunmetal,
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Icon(icon, size: 16, color: NexGenPalette.cyan),
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(JobMaterialList matList, bool anyOverPull) {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Confirm checkout
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed:
                  _isSubmitting || anyOverPull ? null : () => _confirmCheckout(matList),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.cyan,
                disabledBackgroundColor:
                    NexGenPalette.cyan.withValues(alpha: 0.3),
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
                      anyOverPull
                          ? 'Insufficient stock — adjust quantities'
                          : 'Confirm Checkout',
                      style: const TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.w600,
                          fontSize: 15)),
            ),
          ),
          const SizedBox(height: 8),
          // Export packing list
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _exportPackingList(matList),
              icon: Icon(Icons.print_outlined,
                  size: 18, color: NexGenPalette.cyan),
              label: Text('Export Packing List',
                  style: TextStyle(color: NexGenPalette.cyan)),
              style: OutlinedButton.styleFrom(
                side: BorderSide(
                    color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Helpers ────────────────────────────────────────────────────────────

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
}
