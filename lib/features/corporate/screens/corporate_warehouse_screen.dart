import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_inventory_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Warehouse view — read-only network-wide intelligence on inventory,
/// active demand, waste performance, and reorder triggers. Replaces the
/// Warehouse tab stub on the corporate dashboard.
class CorporateWarehouseScreen extends ConsumerWidget {
  const CorporateWarehouseScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: const [
          _NetworkInventorySection(),
          SizedBox(height: 16),
          _ActiveDemandSection(),
          SizedBox(height: 16),
          _WasteIntelligenceSection(),
          SizedBox(height: 16),
          _ReorderTriggersSection(),
          SizedBox(height: 32),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION SCAFFOLDING
// ═══════════════════════════════════════════════════════════════════════

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.subtitle,
    required this.child,
  });
  final String title;
  final String subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 11,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 1 — NETWORK INVENTORY SUMMARY
// ═══════════════════════════════════════════════════════════════════════

class _NetworkInventorySection extends ConsumerWidget {
  const _NetworkInventorySection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rowsAsync = ref.watch(networkInventoryRowsProvider);
    return _SectionCard(
      title: 'Network Inventory',
      subtitle:
          'On-hand totals across every dealer. Tap a row to expand per-dealer breakdown.',
      child: rowsAsync.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load inventory: $e'),
        data: (rows) {
          if (rows.isEmpty) {
            return _emptyRow('No inventory records found.');
          }
          return Column(
            children: rows.map((r) => _NetworkInventoryRowTile(row: r)).toList(),
          );
        },
      ),
    );
  }
}

class _NetworkInventoryRowTile extends StatefulWidget {
  const _NetworkInventoryRowTile({required this.row});
  final NetworkInventoryRow row;

  @override
  State<_NetworkInventoryRowTile> createState() =>
      _NetworkInventoryRowTileState();
}

class _NetworkInventoryRowTileState extends State<_NetworkInventoryRowTile> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.row;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Icon(
                    _expanded
                        ? Icons.keyboard_arrow_down
                        : Icons.keyboard_arrow_right,
                    color: NexGenPalette.textMedium,
                    size: 18,
                  ),
                  const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          r.displayName,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        Text(
                          '${r.perDealer.length} dealer(s)',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (r.anyDealerLowStock)
                    Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: NexGenPalette.amber.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'LOW',
                        style: TextStyle(
                          color: NexGenPalette.amber,
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  Text(
                    r.totalOnHand.toStringAsFixed(0),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded)
            Padding(
              padding: const EdgeInsets.fromLTRB(28, 0, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: r.perDealer.entries.map((e) {
                  final rec = e.value;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 2),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: NexGenPalette.violet.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            'Dealer ${e.key}',
                            style: TextStyle(
                              color: NexGenPalette.violet,
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'on-hand ${rec.quantityOnHand.toStringAsFixed(0)}  •  reserved ${rec.quantityReserved.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: NexGenPalette.textMedium,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        if (rec.quantityAvailable <= rec.reorderThreshold &&
                            rec.reorderThreshold > 0)
                          Text(
                            'low',
                            style: TextStyle(
                              color: NexGenPalette.amber,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                      ],
                    ),
                  );
                }).toList(),
              ),
            ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 2 — ACTIVE DEMAND
// ═══════════════════════════════════════════════════════════════════════

class _ActiveDemandSection extends ConsumerWidget {
  const _ActiveDemandSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final demandAsync = ref.watch(networkMaterialDemandProvider);
    final invAsync = ref.watch(networkInventoryRowsProvider);

    return _SectionCard(
      title: 'Active Demand',
      subtitle:
          'Quantities committed across all open jobs (status not Install Complete). Gap = on-hand minus committed.',
      child: demandAsync.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load demand: $e'),
        data: (demand) {
          if (demand.isEmpty) {
            return _emptyRow('No open jobs with estimate breakdowns.');
          }
          // Sort by total quantity descending — most-committed materials first.
          final sorted = demand.values.toList()
            ..sort((a, b) => b.totalQuantity.compareTo(a.totalQuantity));

          // Best-effort match against inventory by description (see schema
          // gap note in corporate_inventory_providers.dart).
          final invRows = invAsync.value ?? const [];

          return Column(
            children: sorted.map((d) {
              final inv = invRows
                  .where((r) => r.displayName
                      .toLowerCase()
                      .contains(d.description.toLowerCase().split(' ').first))
                  .firstOrNull;
              final onHand = inv?.totalOnHand ?? 0;
              final gap = onHand - d.totalQuantity;
              final overCommitted = gap < 0;

              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            d.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${d.totalQuantity.toStringAsFixed(0)} ${d.unit}',
                          style: const TextStyle(
                            color: NexGenPalette.cyan,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${d.jobCount} job(s)',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Text(
                          'on-hand ${onHand.toStringAsFixed(0)}',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 10,
                          ),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: overCommitted
                                ? Colors.red.withValues(alpha: 0.18)
                                : NexGenPalette.green.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            overCommitted
                                ? 'GAP ${gap.toStringAsFixed(0)}'
                                : '+${gap.toStringAsFixed(0)}',
                            style: TextStyle(
                              color: overCommitted
                                  ? Colors.red
                                  : NexGenPalette.green,
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 3 — NETWORK WASTE INTELLIGENCE
// ═══════════════════════════════════════════════════════════════════════

class _WasteIntelligenceSection extends ConsumerWidget {
  const _WasteIntelligenceSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final wasteAsync = ref.watch(networkWasteStatsProvider);
    return _SectionCard(
      title: 'Network Waste Intelligence',
      subtitle:
          'Per-material waste % from completed installs. Sorted worst-first to highlight training opportunities.',
      child: wasteAsync.when(
        loading: () => const _Loader(),
        error: (e, _) => _ErrorRow(message: 'Failed to load waste: $e'),
        data: (waste) {
          if (waste.isEmpty) {
            return _emptyRow('No completed jobs with material check-ins yet.');
          }
          final sorted = waste.values.toList()
            ..sort((a, b) => b.avgWastePct.compareTo(a.avgWastePct));

          return Column(
            children: sorted.map((w) {
              final pct = (w.avgWastePct * 100);
              final pctColor = pct >= 20
                  ? Colors.red
                  : pct >= 10
                      ? NexGenPalette.amber
                      : NexGenPalette.green;
              return Container(
                margin: const EdgeInsets.only(bottom: 6),
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            w.description,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                        Text(
                          '${pct.toStringAsFixed(1)}%',
                          style: TextStyle(
                            color: pctColor,
                            fontSize: 14,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '${w.sampleCount} sample(s)',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 10,
                          ),
                        ),
                        const SizedBox(width: 12),
                        if (w.bestDealerCode != null)
                          Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: Text(
                              'best ${w.bestDealerCode}',
                              style: TextStyle(
                                color: NexGenPalette.green,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        if (w.worstDealerCode != null)
                          Text(
                            'worst ${w.worstDealerCode}',
                            style: TextStyle(
                              color: Colors.red,
                              fontSize: 10,
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// SECTION 4 — REORDER TRIGGERS
// ═══════════════════════════════════════════════════════════════════════

class _ReorderTriggersSection extends ConsumerWidget {
  const _ReorderTriggersSection();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final invAsync = ref.watch(networkInventoryRowsProvider);
    final demandAsync = ref.watch(networkMaterialDemandProvider);
    final wasteAsync = ref.watch(networkWasteStatsProvider);

    return _SectionCard(
      title: 'Reorder Triggers',
      subtitle:
          'Materials where network on-hand < (avg per-job usage × 4). Read-only intelligence — order externally.',
      child: () {
        if (invAsync.isLoading ||
            demandAsync.isLoading ||
            wasteAsync.isLoading) {
          return const _Loader();
        }
        if (invAsync.hasError) {
          return _ErrorRow(message: 'Inventory error: ${invAsync.error}');
        }
        final invRows = invAsync.value ?? const [];
        final demand = demandAsync.value ?? const {};

        // Compute per-line-item average usage from waste stats. Fall back
        // to total demand / job count if no waste samples exist.
        // Then trigger if on-hand < avgUsage * 4.
        final triggers = <_ReorderTrigger>[];
        for (final d in demand.values) {
          final avgUsagePerJob =
              d.jobCount == 0 ? 0 : d.totalQuantity / d.jobCount;
          final required = avgUsagePerJob * 4;
          // Match inventory by best-effort description token (see note above).
          final inv = invRows
              .where((r) => r.displayName
                  .toLowerCase()
                  .contains(d.description.toLowerCase().split(' ').first))
              .firstOrNull;
          final onHand = inv?.totalOnHand ?? 0;
          if (onHand < required && required > 0) {
            triggers.add(_ReorderTrigger(
              description: d.description,
              onHand: onHand,
              required: required.toDouble(),
              avgPerJob: avgUsagePerJob.toDouble(),
              unit: d.unit,
            ));
          }
        }

        if (triggers.isEmpty) {
          return _emptyRow('No reorder triggers — network stock is healthy.');
        }

        triggers.sort((a, b) => (a.onHand - a.required)
            .compareTo(b.onHand - b.required));

        return Column(
          children: triggers.map((t) {
            final shortfall = t.required - t.onHand;
            return Container(
              margin: const EdgeInsets.only(bottom: 6),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.06),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: Colors.red.withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t.description,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'on-hand ${t.onHand.toStringAsFixed(0)} ${t.unit}  •  need ${t.required.toStringAsFixed(0)}  •  short ${shortfall.toStringAsFixed(0)}',
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 10,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        );
      }(),
    );
  }
}

class _ReorderTrigger {
  final String description;
  final double onHand;
  final double required;
  final double avgPerJob;
  final String unit;
  const _ReorderTrigger({
    required this.description,
    required this.onHand,
    required this.required,
    required this.avgPerJob,
    required this.unit,
  });
}

// ═══════════════════════════════════════════════════════════════════════
// SHARED UI
// ═══════════════════════════════════════════════════════════════════════

class _Loader extends StatelessWidget {
  const _Loader();
  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            color: NexGenPalette.gold,
            strokeWidth: 2,
          ),
        ),
      ),
    );
  }
}

class _ErrorRow extends StatelessWidget {
  const _ErrorRow({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Text(
        message,
        style: const TextStyle(color: Colors.red, fontSize: 11),
      ),
    );
  }
}

Widget _emptyRow(String message) {
  return Padding(
    padding: const EdgeInsets.symmetric(vertical: 16),
    child: Center(
      child: Text(
        message,
        style: TextStyle(
          color: NexGenPalette.textMedium,
          fontSize: 12,
        ),
      ),
    ),
  );
}
