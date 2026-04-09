import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/providers/material_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// InventoryDashboardScreen
//
// Dealer-scoped material intelligence dashboard. Five sections:
//
//   1. On Hand                — real, joined catalog + inventory + low-stock
//   2. Committed              — STUBBED, see "Inventory bridge required"
//   3. Available              — STUBBED, see "Inventory bridge required"
//   4. Waste Intelligence     — real, per-material rolling avg from
//                                ActualMaterialUsage on installComplete jobs.
//                                Trend arrow needs ≥3 samples.
//   5. Reorder Suggestions    — STUBBED, see "Inventory bridge required"
//
// Sections 2/3/5 are stubbed because the wizard-generated EstimateBreakdown
// items don't share a keyspace with the dealer's materialCatalog inventory.
// Bridging the two requires a new MaterialCalculationService method that
// converts ChannelRun data into JobMaterialLines keyed against the catalog
// — that's a follow-up prompt's worth of work. The dashboard explicitly
// shows this gap rather than fabricating numbers from incompatible sources.
// See the recon report from Prompt 8 for the full rationale.
//
// The dealer code is passed in by the parent DealerDashboardScreen, which
// already resolves it from sales-session / installer-session / admin
// override. This screen does not re-resolve.
// ─────────────────────────────────────────────────────────────────────────────

class InventoryDashboardScreen extends ConsumerWidget {
  final String dealerCode;
  const InventoryDashboardScreen({super.key, required this.dealerCode});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final inventoryAsync = ref.watch(inventoryProvider(dealerCode));
    final catalogAsync = ref.watch(materialCatalogProvider(dealerCode));
    final completedJobsAsync = ref.watch(
      salesJobsByStatusProvider(const [SalesJobStatus.installComplete]),
    );

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 32),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Section 1 ────────────────────────────────────────────
          const _SectionHeader(
            number: 1,
            title: 'ON HAND',
            subtitle: 'Current dealer stock. Tap an item to record a '
                'received order.',
          ),
          const SizedBox(height: 12),
          _Section1OnHand(
            dealerCode: dealerCode,
            inventoryAsync: inventoryAsync,
            catalogAsync: catalogAsync,
          ),
          const SizedBox(height: 28),

          // ── Section 2 ────────────────────────────────────────────
          const _SectionHeader(
            number: 2,
            title: 'COMMITTED TO ACTIVE JOBS',
          ),
          const SizedBox(height: 12),
          const _StubCard(
            title: 'Inventory bridge required',
            body:
                'Active jobs created by the Estimate Wizard use line items '
                "that aren't keyed to the dealer's material catalog. "
                'Rolling them up into per-SKU committed quantities needs a '
                'follow-up prompt that bridges ChannelRun data to '
                'JobMaterialLine entries.',
          ),
          const SizedBox(height: 28),

          // ── Section 3 ────────────────────────────────────────────
          const _SectionHeader(
            number: 3,
            title: 'AVAILABLE',
          ),
          const SizedBox(height: 12),
          const _StubCard(
            title: 'Available = On Hand − Committed',
            body:
                'Computed once Section 2 is bridged. Until then, refer to '
                'Section 1 for the on-hand quantity directly.',
          ),
          const SizedBox(height: 28),

          // ── Section 4 ────────────────────────────────────────────
          const _SectionHeader(
            number: 4,
            title: 'WASTE INTELLIGENCE',
            subtitle: 'Average waste % per material across completed jobs. '
                'Trend compares the 5 most recent samples vs all earlier '
                'samples (3-sample minimum).',
          ),
          const SizedBox(height: 12),
          _Section4Waste(completedJobsAsync: completedJobsAsync),
          const SizedBox(height: 28),

          // ── Section 5 ────────────────────────────────────────────
          const _SectionHeader(
            number: 5,
            title: 'REORDER SUGGESTIONS',
          ),
          const SizedBox(height: 12),
          const _StubCard(
            title: 'Bridge required',
            body:
                'Reorder suggestions need average per-job usage per SKU, '
                'which is blocked on the same Inventory bridge as Sections '
                '2 and 3. The "Receive Stock" action on each Section 1 '
                'item lets dealers manually replenish in the meantime.',
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 1 — On Hand
// ─────────────────────────────────────────────────────────────────────────────

class _Section1OnHand extends ConsumerWidget {
  final String dealerCode;
  final AsyncValue<List<InventoryRecord>> inventoryAsync;
  final AsyncValue<Map<String, MaterialItem>> catalogAsync;

  const _Section1OnHand({
    required this.dealerCode,
    required this.inventoryAsync,
    required this.catalogAsync,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (inventoryAsync.isLoading || catalogAsync.isLoading) {
      return const _LoadingTile();
    }
    if (inventoryAsync.hasError) {
      return _ErrorTile(error: inventoryAsync.error.toString());
    }
    if (catalogAsync.hasError) {
      return _ErrorTile(error: catalogAsync.error.toString());
    }

    final inventory = inventoryAsync.value ?? const <InventoryRecord>[];
    final catalog = catalogAsync.value ?? const <String, MaterialItem>{};
    if (inventory.isEmpty) {
      return const _EmptyTile(
        icon: Icons.inventory_2_outlined,
        message: 'No inventory records for this dealer yet',
      );
    }

    // Sort: low-stock first, then alphabetical by name.
    final rows = [...inventory];
    rows.sort((a, b) {
      final aLow = a.quantityAvailable <= a.reorderThreshold ? 0 : 1;
      final bLow = b.quantityAvailable <= b.reorderThreshold ? 0 : 1;
      if (aLow != bLow) return aLow - bLow;
      final aName = catalog[a.materialId]?.name ?? a.materialId;
      final bName = catalog[b.materialId]?.name ?? b.materialId;
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    });

    return Column(
      children: [
        for (final record in rows) ...[
          _OnHandRow(
            record: record,
            item: catalog[record.materialId],
            onReceive: () => _showReceiveDialog(
              context,
              ref,
              record: record,
              item: catalog[record.materialId],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }

  Future<void> _showReceiveDialog(
    BuildContext context,
    WidgetRef ref, {
    required InventoryRecord record,
    required MaterialItem? item,
  }) async {
    final controller = TextEditingController();
    final qty = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: Text(
          'Receive stock',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              item?.name ?? record.materialId,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Currently on hand: ${_formatQty(record.quantityOnHand)}'
              '${item != null ? ' ${item.unit.name}' : ''}',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              style: const TextStyle(color: Colors.white),
              decoration: InputDecoration(
                labelText: 'Quantity received',
                labelStyle: const TextStyle(color: NexGenPalette.textMedium),
                suffixText: item?.unit.name ?? '',
                suffixStyle: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                ),
                filled: true,
                fillColor: NexGenPalette.matteBlack,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: NexGenPalette.cyan),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(
              'Cancel',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
          ),
          TextButton(
            onPressed: () {
              final v = double.tryParse(controller.text.trim());
              if (v == null || v <= 0) return;
              Navigator.of(ctx).pop(v);
            },
            child: Text(
              'Receive',
              style: TextStyle(color: NexGenPalette.cyan),
            ),
          ),
        ],
      ),
    );
    if (qty == null || qty <= 0) return;

    // Resolve installer id for the audit trail.
    final installerSession = ref.read(installerSessionProvider);
    final salesSession = ref.read(currentSalesSessionProvider);
    // TODO: replace with Firebase Auth UID when installer auth migrates
    final installerId = installerSession?.installer.fullPin ??
        salesSession?.salespersonUid ??
        'unknown';

    try {
      await ref.read(inventoryServiceProvider).recordStockReceived(
            dealerCode: dealerCode,
            materialId: record.materialId,
            quantity: qty,
            installerId: installerId,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Received ${_formatQty(qty)}'
            '${item != null ? ' ${item.unit.name}' : ''} of '
            '${item?.name ?? record.materialId}',
          ),
          backgroundColor: NexGenPalette.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record: $e')),
      );
    }
  }
}

class _OnHandRow extends StatelessWidget {
  final InventoryRecord record;
  final MaterialItem? item;
  final VoidCallback onReceive;

  const _OnHandRow({
    required this.record,
    required this.item,
    required this.onReceive,
  });

  @override
  Widget build(BuildContext context) {
    final isLow = record.quantityAvailable <= record.reorderThreshold;
    final accent = isLow ? NexGenPalette.amber : NexGenPalette.cyan;
    final unit = item?.unit.name ?? '';
    final name = item?.name ?? record.materialId;

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isLow ? accent.withValues(alpha: 0.4) : NexGenPalette.line,
        ),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          // Stock-status icon
          Container(
            width: 36,
            height: 36,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: accent.withValues(alpha: 0.4)),
            ),
            child: Icon(
              isLow ? Icons.warning_amber_rounded : Icons.inventory_2_outlined,
              color: accent,
              size: 18,
            ),
          ),
          const SizedBox(width: 12),

          // Name + secondary info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  isLow
                      ? 'Low stock — at or below reorder threshold of '
                          '${_formatQty(record.reorderThreshold)} $unit'
                      : 'Reorder threshold: '
                          '${_formatQty(record.reorderThreshold)} $unit',
                  style: TextStyle(
                    color:
                        isLow ? accent : Colors.white.withValues(alpha: 0.5),
                    fontSize: 11,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),

          // On-hand quantity stat
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                _formatQty(record.quantityOnHand),
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (unit.isNotEmpty)
                Text(
                  unit,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.5),
                    fontSize: 10,
                  ),
                ),
            ],
          ),
          const SizedBox(width: 8),

          // Receive action
          IconButton(
            tooltip: 'Receive stock',
            icon: Icon(Icons.add_circle_outline, color: accent),
            onPressed: onReceive,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Section 4 — Waste Intelligence
//
// Real per-material waste rollup, sourced from
// SalesJob.actualMaterialUsage on installComplete jobs (the data the
// Day 2 wrap-up screen captures). Per-material samples are sorted by
// job.day2CompletedAt; min sample size for a trend arrow is 3.
// ─────────────────────────────────────────────────────────────────────────────

class _Section4Waste extends StatelessWidget {
  final AsyncValue<List<SalesJob>> completedJobsAsync;
  const _Section4Waste({required this.completedJobsAsync});

  @override
  Widget build(BuildContext context) {
    if (completedJobsAsync.isLoading) {
      return const _LoadingTile();
    }
    if (completedJobsAsync.hasError) {
      return _ErrorTile(error: completedJobsAsync.error.toString());
    }
    final jobs = completedJobsAsync.value ?? const <SalesJob>[];
    final rows = _computeWasteRows(jobs);

    if (rows.isEmpty) {
      return const _EmptyTile(
        icon: Icons.history_toggle_off_outlined,
        message:
            'No completed jobs with material check-in data yet. Waste history '
            'appears here as installers finish wrap-up.',
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Column(
        children: [
          // Table header
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  flex: 5,
                  child: Text(
                    'MATERIAL',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                Expanded(
                  flex: 2,
                  child: Text(
                    'AVG WASTE',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                SizedBox(
                  width: 32,
                  child: Text(
                    'TREND',
                    textAlign: TextAlign.right,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.4),
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.8,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(color: NexGenPalette.line, height: 1),
          for (final row in rows) ...[
            _WasteTableRow(row: row),
            const Divider(color: NexGenPalette.line, height: 1),
          ],
        ],
      ),
    );
  }

  /// Per-itemId waste samples ordered most-recent-first.
  List<_WasteRow> _computeWasteRows(List<SalesJob> jobs) {
    // Materialize samples per itemId.
    final samples = <String, List<_WasteSample>>{};
    final descriptionByItemId = <String, String>{};

    for (final job in jobs) {
      final usage = job.actualMaterialUsage;
      if (usage == null) continue;
      final timestamp = job.day2CompletedAt ?? job.updatedAt;
      for (final entry in usage.entries) {
        if (entry.estimatedQty <= 0) continue;
        // Waste % = (estimated - actual_used) / estimated
        // = returnedQty / estimatedQty
        // (since usedQty = estimatedQty - returnedQty by definition)
        final wastePct = (entry.returnedQty / entry.estimatedQty) * 100;
        samples
            .putIfAbsent(entry.itemId, () => [])
            .add(_WasteSample(timestamp: timestamp, wastePct: wastePct));
        descriptionByItemId[entry.itemId] = entry.description;
      }
    }

    // Build rows.
    final rows = <_WasteRow>[];
    samples.forEach((itemId, items) {
      // Sort most-recent-first.
      items.sort((a, b) => b.timestamp.compareTo(a.timestamp));

      final allAvg =
          items.map((s) => s.wastePct).reduce((a, b) => a + b) / items.length;

      // Trend computation: compare the 5 most recent samples vs all
      // earlier samples. Need ≥3 samples total to show any trend.
      double? trendDelta;
      if (items.length >= 3) {
        final recentCount = math.min(5, items.length);
        final recent = items.sublist(0, recentCount);
        final earlier = items.sublist(recentCount);
        final recentAvg =
            recent.map((s) => s.wastePct).reduce((a, b) => a + b) /
                recent.length;
        if (earlier.isNotEmpty) {
          final earlierAvg =
              earlier.map((s) => s.wastePct).reduce((a, b) => a + b) /
                  earlier.length;
          trendDelta = recentAvg - earlierAvg;
        } else {
          // ≥3 samples but all in the recent window — no comparison set.
          trendDelta = null;
        }
      }

      rows.add(_WasteRow(
        itemId: itemId,
        description: descriptionByItemId[itemId] ?? itemId,
        avgWastePct: allAvg,
        sampleCount: items.length,
        trendDelta: trendDelta,
      ));
    });

    // Sort by avg waste descending — worst offenders first.
    rows.sort((a, b) => b.avgWastePct.compareTo(a.avgWastePct));
    return rows;
  }
}

class _WasteSample {
  final DateTime timestamp;
  final double wastePct;
  _WasteSample({required this.timestamp, required this.wastePct});
}

class _WasteRow {
  final String itemId;
  final String description;
  final double avgWastePct;
  final int sampleCount;

  /// Recent-vs-earlier delta in percentage points. Null when there
  /// aren't enough samples on either side to compute a trend.
  final double? trendDelta;

  _WasteRow({
    required this.itemId,
    required this.description,
    required this.avgWastePct,
    required this.sampleCount,
    required this.trendDelta,
  });
}

class _WasteTableRow extends StatelessWidget {
  final _WasteRow row;
  const _WasteTableRow({required this.row});

  @override
  Widget build(BuildContext context) {
    final wasteColor = row.avgWastePct >= 15
        ? Colors.red.shade400
        : row.avgWastePct >= 8
            ? NexGenPalette.amber
            : NexGenPalette.green;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 5,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  row.description,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  '${row.sampleCount} job${row.sampleCount == 1 ? '' : 's'}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.45),
                    fontSize: 11,
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            flex: 2,
            child: Text(
              '${row.avgWastePct.toStringAsFixed(1)}%',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: wasteColor,
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 32,
            child: _trendWidget(),
          ),
        ],
      ),
    );
  }

  Widget _trendWidget() {
    final delta = row.trendDelta;
    if (delta == null) {
      // Below the 3-sample threshold — show a neutral dash.
      return Text(
        '—',
        textAlign: TextAlign.right,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.3),
          fontSize: 16,
        ),
      );
    }
    // Tolerance window: anything within ±0.5 pp is "flat".
    if (delta.abs() < 0.5) {
      return Icon(
        Icons.trending_flat,
        color: Colors.white.withValues(alpha: 0.5),
        size: 18,
      );
    }
    // Positive delta = waste increased = bad.
    final improving = delta < 0;
    return Icon(
      improving ? Icons.trending_down : Icons.trending_up,
      color: improving ? NexGenPalette.green : Colors.red.shade400,
      size: 18,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared little widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final int number;
  final String title;
  final String? subtitle;

  const _SectionHeader({
    required this.number,
    required this.title,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Container(
              width: 22,
              height: 22,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(
                  color: NexGenPalette.cyan.withValues(alpha: 0.4),
                ),
              ),
              child: Text(
                '$number',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              title,
              style: TextStyle(
                color: NexGenPalette.cyan,
                fontSize: 12,
                fontWeight: FontWeight.w700,
                letterSpacing: 1.2,
              ),
            ),
          ],
        ),
        if (subtitle != null) ...[
          const SizedBox(height: 6),
          Text(
            subtitle!,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 12,
              height: 1.4,
            ),
          ),
        ],
      ],
    );
  }
}

class _StubCard extends StatelessWidget {
  final String title;
  final String body;
  const _StubCard({required this.title, required this.body});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: NexGenPalette.amber.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.amber.withValues(alpha: 0.3)),
      ),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.construction_outlined,
                color: NexGenPalette.amber,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    color: NexGenPalette.amber,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.7),
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _LoadingTile extends StatelessWidget {
  const _LoadingTile();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 80,
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      alignment: Alignment.center,
      child: const SizedBox(
        height: 22,
        width: 22,
        child: CircularProgressIndicator(
          color: NexGenPalette.cyan,
          strokeWidth: 2,
        ),
      ),
    );
  }
}

class _ErrorTile extends StatelessWidget {
  final String error;
  const _ErrorTile({required this.error});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.4)),
      ),
      padding: const EdgeInsets.all(14),
      child: Row(
        children: [
          Icon(Icons.error_outline,
              color: Colors.red.withValues(alpha: 0.7), size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              error,
              style: TextStyle(
                color: Colors.red.withValues(alpha: 0.7),
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyTile extends StatelessWidget {
  final IconData icon;
  final String message;
  const _EmptyTile({required this.icon, required this.message});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      padding: const EdgeInsets.all(20),
      child: Row(
        children: [
          Icon(icon, color: Colors.white.withValues(alpha: 0.3), size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
                fontSize: 12,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatQty(double q) {
  if (q == q.roundToDouble()) return q.toStringAsFixed(0);
  return q.toStringAsFixed(1);
}
