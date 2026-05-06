import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_job_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/theme.dart';

/// Whole-dollar currency formatter — local copy to avoid coupling to the
/// dashboard screen and to keep this file standalone.
String _formatUsd(double value) {
  final whole = value.round();
  final s = whole.abs().toString();
  final buf = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
    buf.write(s[i]);
  }
  return '${whole < 0 ? '-' : ''}\$${buf.toString()}';
}

Color _statusColor(SalesJobStatus s) => switch (s) {
      SalesJobStatus.draft => const Color(0xFF555555),
      SalesJobStatus.estimateSent => const Color(0xFF6E2FFF),
      SalesJobStatus.estimateSigned => const Color(0xFF1D9E75),
      SalesJobStatus.prewireScheduled => const Color(0xFFEF9F27),
      SalesJobStatus.prewireComplete => const Color(0xFFEF9F27),
      SalesJobStatus.installScheduled => const Color(0xFF00D4FF),
      SalesJobStatus.installComplete => const Color(0xFF00D4FF),
      SalesJobStatus.completePaid => const Color(0xFF00D4FF),
    };

/// Cross-dealer pipeline view — replaces the Pipeline tab stub on the
/// corporate dashboard. Stats bar + status filter chips + search +
/// scrollable job list. Tap a row to drill into a read-only detail view.
class CorporatePipelineScreen extends ConsumerStatefulWidget {
  const CorporatePipelineScreen({super.key});

  @override
  ConsumerState<CorporatePipelineScreen> createState() =>
      _CorporatePipelineScreenState();
}

class _CorporatePipelineScreenState
    extends ConsumerState<CorporatePipelineScreen> {
  final Set<SalesJobStatus> _statusFilter = <SalesJobStatus>{};
  String _search = '';
  final TextEditingController _searchController = TextEditingController();

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<SalesJob> _applySearch(List<SalesJob> jobs) {
    if (_search.trim().isEmpty) return jobs;
    final q = _search.trim().toLowerCase();
    return jobs.where((j) {
      return j.prospect.fullName.toLowerCase().contains(q) ||
          j.prospect.address.toLowerCase().contains(q) ||
          j.prospect.city.toLowerCase().contains(q) ||
          j.dealerCode.toLowerCase().contains(q);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filterStatuses = _statusFilter.isEmpty ? null : _statusFilter.toList();
    final jobsAsync = ref.watch(allJobsByStatusProvider(filterStatuses));
    final statsAsync = ref.watch(corporateJobStatsProvider);

    return Column(
      children: [
        // ── Stats bar ──
        _PipelineStatsBar(statsAsync: statsAsync),

        // ── Filter chips ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _statusFilter.isEmpty,
                  onTap: () => setState(() => _statusFilter.clear()),
                ),
                const SizedBox(width: 6),
                ...SalesJobStatus.values.map((s) {
                  final selected = _statusFilter.contains(s);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: _FilterChip(
                      label: s.label,
                      selected: selected,
                      color: _statusColor(s),
                      onTap: () => setState(() {
                        if (selected) {
                          _statusFilter.remove(s);
                        } else {
                          _statusFilter.add(s);
                        }
                      }),
                    ),
                  );
                }),
              ],
            ),
          ),
        ),

        // ── Search bar ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: TextField(
            controller: _searchController,
            onChanged: (v) => setState(() => _search = v),
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'Search by name, address, or dealer code',
              hintStyle: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.search,
                color: NexGenPalette.textMedium,
                size: 18,
              ),
              suffixIcon: _search.isEmpty
                  ? null
                  : IconButton(
                      icon: Icon(
                        Icons.close,
                        color: NexGenPalette.textMedium,
                        size: 18,
                      ),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _search = '');
                      },
                    ),
              isDense: true,
              filled: true,
              fillColor: NexGenPalette.gunmetal90,
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 12, vertical: 12),
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
                borderSide: BorderSide(
                  color: NexGenPalette.gold.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
        ),

        // ── Job list ──
        Expanded(
          child: jobsAsync.when(
            loading: () => const Center(
              child: CircularProgressIndicator(color: NexGenPalette.gold),
            ),
            error: (e, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Failed to load jobs: $e',
                  style: const TextStyle(color: Colors.red, fontSize: 12),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
            data: (jobs) {
              final filtered = _applySearch(jobs);
              if (filtered.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.inbox_outlined,
                        color: NexGenPalette.textMedium,
                        size: 36,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'No jobs match',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                );
              }
              return ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                itemCount: filtered.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final job = filtered[i];
                  return _CorporateJobCard(
                    job: job,
                    onTap: () {
                      context.push(
                        '${AppRoutes.corporateJobDetailBase}/${job.id}',
                      );
                    },
                  );
                },
              );
            },
          ),
        ),
      ],
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// STATS BAR
// ═══════════════════════════════════════════════════════════════════════

class _PipelineStatsBar extends StatelessWidget {
  const _PipelineStatsBar({required this.statsAsync});
  final AsyncValue<CorporateJobStats> statsAsync;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 80,
      child: statsAsync.when(
        loading: () => const Center(
          child: SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(
              color: NexGenPalette.gold,
              strokeWidth: 2,
            ),
          ),
        ),
        error: (e, _) => Center(
          child: Text(
            'Stats unavailable',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
          ),
        ),
        data: (s) {
          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            scrollDirection: Axis.horizontal,
            children: [
              _StatChip(label: 'Total jobs', value: '${s.totalJobs}'),
              _StatChip(label: 'This week', value: '${s.jobsLast7Days}'),
              _StatChip(label: 'Last 30 days', value: '${s.jobsLast30Days}'),
              _StatChip(
                label: 'Avg cycle',
                value: s.averageCycleTimeDays > 0
                    ? '${s.averageCycleTimeDays.toStringAsFixed(1)}d'
                    : '—',
              ),
              _StatChip(
                label: 'Total revenue',
                value: _formatUsd(s.totalRevenue),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 10),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// FILTER CHIP
// ═══════════════════════════════════════════════════════════════════════

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.color,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? NexGenPalette.gold;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected
              ? accent.withValues(alpha: 0.18)
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? accent : NexGenPalette.line,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: selected ? accent : NexGenPalette.textMedium,
            fontSize: 12,
            fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════
// JOB CARD
// ═══════════════════════════════════════════════════════════════════════

class _CorporateJobCard extends StatelessWidget {
  const _CorporateJobCard({required this.job, required this.onTap});
  final SalesJob job;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(job.status);
    final daysInStatus = DateTime.now().difference(job.updatedAt).inDays;

    Color? stalledColor;
    String? stalledLabel;
    if (daysInStatus > 14) {
      stalledColor = Colors.red;
      stalledLabel = 'Stalled ${daysInStatus}d';
    } else if (daysInStatus > 7) {
      stalledColor = NexGenPalette.amber;
      stalledLabel = '${daysInStatus}d in status';
    }

    return Material(
      color: NexGenPalette.gunmetal90,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      job.prospect.fullName.trim().isEmpty
                          ? '(No name)'
                          : job.prospect.fullName,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  Text(
                    _formatUsd(job.totalPriceUsd),
                    style: const TextStyle(
                      color: NexGenPalette.green,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 2),
              Text(
                '${job.prospect.address}, ${job.prospect.city}',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  // Status chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: color.withValues(alpha: 0.45)),
                    ),
                    child: Text(
                      job.status.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  // Dealer chip
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: NexGenPalette.violet.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: NexGenPalette.violet.withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      'Dealer ${job.dealerCode}',
                      style: TextStyle(
                        color: NexGenPalette.violet,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  if (stalledLabel != null) ...[
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: stalledColor!.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: stalledColor.withValues(alpha: 0.5),
                        ),
                      ),
                      child: Text(
                        stalledLabel,
                        style: TextStyle(
                          color: stalledColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    _shortDate(job.createdAt),
                    style: TextStyle(
                      color: NexGenPalette.textMedium,
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _shortDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year % 100}';
  }
}
