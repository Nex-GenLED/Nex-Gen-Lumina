import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/features/sales/services/sales_job_service.dart';
import 'package:nexgen_command/theme.dart';

/// Day 2 install team queue. Lists every job that has finished pre-wire
/// (status `prewireComplete` or `installScheduled`) for the current
/// installer's dealer, ordered by creation date. Gated behind
/// [installerModeActiveProvider]; bounces to the installer PIN screen
/// if no installer session is active.
///
/// Each card shows the customer name, address, the scheduled Day 2
/// date (or a "Schedule Day 2" button if not yet set), and a status
/// chip. Tapping a card opens the [Day2BlueprintScreen].
///
/// Mirrors [Day1QueueScreen] in structure and styling — visual
/// differentiation is the green accent color (vs cyan for Day 1).
class Day2QueueScreen extends ConsumerWidget {
  const Day2QueueScreen({super.key});

  static const _statuses = [
    SalesJobStatus.prewireComplete,
    SalesJobStatus.installScheduled,
  ];

  Future<void> _scheduleDay2(
    BuildContext context,
    WidgetRef ref,
    SalesJob job,
  ) async {
    final now = DateTime.now();
    // Day 2 cannot be scheduled before Day 1 was completed.
    final earliest = job.day1CompletedAt ?? now;
    final picked = await showDatePicker(
      context: context,
      initialDate: job.day2Date ?? earliest,
      firstDate: earliest,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: NexGenPalette.green,
            surface: NexGenPalette.gunmetal,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final updated = job.copyWith(
      day2Date: picked,
      // Move into the installScheduled bucket so the queue reflects
      // the change immediately and the dealer dashboard / job-list
      // status pill picks it up.
      status: SalesJobStatus.installScheduled,
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(salesJobServiceProvider).updateJob(updated);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Day 2 scheduled for '
            '${picked.month}/${picked.day}/${picked.year}',
          ),
          backgroundColor: NexGenPalette.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to schedule: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Role gate — bounce to installer PIN if no active installer session.
    final installerModeActive = ref.watch(installerModeActiveProvider);
    if (!installerModeActive) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.installerPin);
      });
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(
          child: CircularProgressIndicator(color: NexGenPalette.green),
        ),
      );
    }

    final jobsAsync = ref.watch(salesJobsByStatusProvider(_statuses));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Day 2 Queue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: jobsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.green),
        ),
        error: (e, _) => Center(
          child: Text(
            'Error: $e',
            style: TextStyle(color: Colors.red.withValues(alpha: 0.7)),
          ),
        ),
        data: (jobs) {
          if (jobs.isEmpty) return _buildEmptyState();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            itemCount: jobs.length,
            separatorBuilder: (_, __) => const SizedBox(height: 10),
            itemBuilder: (_, i) => _Day2JobCard(
              job: jobs[i],
              onTap: () => context.push(
                AppRoutes.day2JobBlueprint
                    .replaceFirst(':jobId', jobs[i].id),
              ),
              onSchedule: () => _scheduleDay2(context, ref, jobs[i]),
            ),
          );
        },
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.construction_outlined,
            size: 56,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No Day 2 jobs in your queue',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Pre-wired jobs will appear here',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.3),
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Job card
// ─────────────────────────────────────────────────────────────────────────────

class _Day2JobCard extends StatelessWidget {
  final SalesJob job;
  final VoidCallback onTap;
  final VoidCallback onSchedule;

  const _Day2JobCard({
    required this.job,
    required this.onTap,
    required this.onSchedule,
  });

  static Color _statusColor(SalesJobStatus s) => switch (s) {
        SalesJobStatus.prewireComplete => NexGenPalette.amber,
        SalesJobStatus.installScheduled => NexGenPalette.green,
        _ => Colors.grey,
      };

  String _formatDate(DateTime d) =>
      '${_monthName(d.month)} ${d.day}, ${d.year}';

  static String _monthName(int m) => const [
        '',
        'Jan',
        'Feb',
        'Mar',
        'Apr',
        'May',
        'Jun',
        'Jul',
        'Aug',
        'Sep',
        'Oct',
        'Nov',
        'Dec',
      ][m];

  @override
  Widget build(BuildContext context) {
    final color = _statusColor(job.status);
    final hasDate = job.day2Date != null;

    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Customer + status pill
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: color.withValues(alpha: 0.3),
                      ),
                    ),
                    child: Text(
                      job.status.label,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),

              // Address
              Text(
                '${job.prospect.address}, ${job.prospect.city}, '
                '${job.prospect.state} ${job.prospect.zipCode}',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 13,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 12),

              // Date or schedule button
              if (hasDate)
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: NexGenPalette.green,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Day 2: ${_formatDate(job.day2Date!)}',
                      style: TextStyle(
                        color: NexGenPalette.green,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: onSchedule,
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 0,
                        ),
                        minimumSize: const Size(0, 28),
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: Text(
                        'Reschedule',
                        style: TextStyle(
                          color: NexGenPalette.textMedium,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: onSchedule,
                    icon: const Icon(
                      Icons.schedule,
                      color: NexGenPalette.green,
                      size: 16,
                    ),
                    label: Text(
                      'Schedule Day 2',
                      style: TextStyle(color: NexGenPalette.green),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: NexGenPalette.green.withValues(alpha: 0.4),
                      ),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
