import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Sales jobs list — "My Estimates" screen.
class SalesJobsScreen extends ConsumerStatefulWidget {
  const SalesJobsScreen({super.key});

  @override
  ConsumerState<SalesJobsScreen> createState() => _SalesJobsScreenState();
}

class _SalesJobsScreenState extends ConsumerState<SalesJobsScreen> {
  SalesJobStatus? _filter; // null = all

  @override
  Widget build(BuildContext context) {
    final jobsAsync = ref.watch(
      salesJobsByStatusProvider(_filter == null ? null : [_filter!]),
    );

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('My Estimates'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: NexGenPalette.cyan,
        onPressed: () => context.push(AppRoutes.salesProspect),
        child: const Icon(Icons.add, color: Colors.black),
      ),
      body: Column(
        children: [
          // Filter row
          _buildFilterRow(),
          const SizedBox(height: 8),

          // Job list
          Expanded(
            child: jobsAsync.when(
              loading: () => const Center(
                child: CircularProgressIndicator(color: NexGenPalette.cyan),
              ),
              error: (e, _) => Center(
                child: Text('Error: $e', style: TextStyle(color: Colors.red.withValues(alpha: 0.7))),
              ),
              data: (jobs) {
                if (jobs.isEmpty) return _buildEmptyState();

                return ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
                  itemCount: jobs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (_, i) => _JobCard(
                    job: jobs[i],
                    onTap: () => context.push(
                      AppRoutes.salesJobDetail.replaceFirst(':jobId', jobs[i].id),
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterRow() {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Row(
        children: [
          _filterPill(null, 'All'),
          _filterPill(SalesJobStatus.draft, 'Draft'),
          _filterPill(SalesJobStatus.estimateSent, 'Sent'),
          _filterPill(SalesJobStatus.estimateSigned, 'Signed'),
          _filterPill(SalesJobStatus.prewireScheduled, 'Pre-wire'),
          _filterPill(SalesJobStatus.installComplete, 'Complete'),
        ],
      ),
    );
  }

  Widget _filterPill(SalesJobStatus? status, String label) {
    final selected = _filter == status;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: GestureDetector(
        onTap: () => setState(() => _filter = status),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(
              color: selected ? NexGenPalette.cyan : NexGenPalette.line,
            ),
          ),
          child: Text(
            label,
            style: TextStyle(
              color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
              fontSize: 13,
              fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.receipt_long_outlined, size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No estimates yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
          const SizedBox(height: 16),
          OutlinedButton.icon(
            onPressed: () => context.push(AppRoutes.salesProspect),
            icon: Icon(Icons.add, color: NexGenPalette.cyan),
            label: Text('Start a new visit', style: TextStyle(color: NexGenPalette.cyan)),
            style: OutlinedButton.styleFrom(
              side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Job card ──────────────────────────────────────────────────

class _JobCard extends StatelessWidget {
  final SalesJob job;
  final VoidCallback onTap;

  const _JobCard({required this.job, required this.onTap});

  static Color _statusColor(SalesJobStatus s) => switch (s) {
    SalesJobStatus.draft => Colors.grey,
    SalesJobStatus.estimateSent => const Color(0xFF6E2FFF), // violet
    SalesJobStatus.estimateSigned => const Color(0xFF00D4FF), // cyan/teal
    SalesJobStatus.prewireScheduled => const Color(0xFFFFAB00), // amber
    SalesJobStatus.prewireComplete => const Color(0xFFFFAB00),
    SalesJobStatus.installScheduled => const Color(0xFF00E5A0), // green
    SalesJobStatus.installComplete => const Color(0xFF00E5A0), // green
    SalesJobStatus.completePaid => const Color(0xFF00E5A0), // terminal green
  };

  static double _statusProgress(SalesJobStatus s) => switch (s) {
    SalesJobStatus.draft => 0.0,
    SalesJobStatus.estimateSent => 0.17,
    SalesJobStatus.estimateSigned => 0.33,
    SalesJobStatus.prewireScheduled => 0.5,
    SalesJobStatus.prewireComplete => 0.67,
    SalesJobStatus.installScheduled => 0.83,
    SalesJobStatus.installComplete => 1.0,
    SalesJobStatus.completePaid => 1.0,
  };

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(job.status);
    final progress = _statusProgress(job.status);
    final totalPrice = job.zones.fold(0.0, (acc, z) => acc + z.priceUsd);

    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Name + job number
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          job.prospect.fullName,
                          style: GoogleFonts.montserrat(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Text(
                        job.jobNumber,
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Address
                  Text(
                    '${job.prospect.address}, ${job.prospect.city}',
                    style: TextStyle(color: Colors.white.withValues(alpha: 0.4), fontSize: 13),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 10),

                  // Status pill + price
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: color.withValues(alpha: 0.3)),
                        ),
                        child: Text(
                          job.status.label,
                          style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '\$${totalPrice.toStringAsFixed(0)}',
                        style: TextStyle(
                          color: NexGenPalette.green,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),

            // Progress bar
            ClipRRect(
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(11)),
              child: LinearProgressIndicator(
                value: progress,
                backgroundColor: Colors.white.withValues(alpha: 0.05),
                color: color,
                minHeight: 3,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
