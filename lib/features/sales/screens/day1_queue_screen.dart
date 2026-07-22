import 'package:firebase_auth/firebase_auth.dart';
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

/// Day 1 electrician queue. Lists every signed-but-not-yet-installed
/// sales job for the current installer's dealer, ordered by creation
/// date. Gated behind [installerModeActiveProvider]; bounces to the
/// installer PIN screen if no installer session is active.
///
/// Each card shows the customer name, address, the scheduled Day 1
/// date (or a "Schedule" button if not yet set), and a status chip.
/// Tapping a card opens the [Day1BlueprintScreen] (stub for now).
class Day1QueueScreen extends ConsumerWidget {
  const Day1QueueScreen({super.key});

  static const _statuses = [
    SalesJobStatus.estimateSigned,
    SalesJobStatus.prewireScheduled,
  ];

  /// Resolve a stable identifier for the person taking action — Firebase
  /// Auth uid when available (real user), else the installer-pin
  /// fallback (legacy installer auth still in use). Same fallback
  /// pattern as Day2WrapUpScreen._completeJob.
  String _byUid(WidgetRef ref) {
    final fbUid = FirebaseAuth.instance.currentUser?.uid;
    if (fbUid != null && fbUid.isNotEmpty) return fbUid;
    final session = ref.read(installerSessionProvider);
    return session?.installer.fullPin ?? 'unknown';
  }

  /// Deposit gate: 50% of total_price_usd must be collected before
  /// Day 1 can be scheduled. Snapshots the deposit amount on the job
  /// at the moment of collection so retroactive total-price edits
  /// don't change the historical record.
  Future<void> _markDepositCollected(
    BuildContext context,
    WidgetRef ref,
    SalesJob job,
  ) async {
    final depositAmount = job.totalPriceUsd * 0.5;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal,
        title: const Text('Confirm Deposit Collected',
            style: TextStyle(color: Colors.white)),
        content: Text(
          'Confirm that you have collected '
          '\$${depositAmount.toStringAsFixed(2)} from '
          '${job.prospect.fullName}? '
          'Day 1 scheduling unlocks immediately.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Yes, deposit collected'),
          ),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    try {
      await ref.read(salesJobServiceProvider).markDepositCollected(
            jobId: job.id,
            byUid: _byUid(ref),
            depositAmount: depositAmount,
          );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
              'Deposit recorded — Day 1 scheduling unlocked for ${job.prospect.fullName}'),
          backgroundColor: NexGenPalette.green,
        ),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to record deposit: $e')),
      );
    }
  }

  Future<void> _scheduleDay1(
    BuildContext context,
    WidgetRef ref,
    SalesJob job,
  ) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: job.day1Date ?? now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.dark(
            primary: NexGenPalette.cyan,
            surface: NexGenPalette.gunmetal,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;

    final updated = job.copyWith(
      day1Date: picked,
      // Move into the prewireScheduled bucket so the queue reflects the
      // change immediately.
      status: SalesJobStatus.prewireScheduled,
      updatedAt: DateTime.now(),
    );
    try {
      await ref.read(salesJobServiceProvider).updateJob(updated);
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Day 1 scheduled for '
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
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
        ),
      );
    }

    final jobsAsync = ref.watch(salesJobsByStatusProvider(_statuses));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Day 1 Queue'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: jobsAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: NexGenPalette.cyan),
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
            itemBuilder: (_, i) => _Day1JobCard(
              job: jobs[i],
              onTap: () => context.push(
                AppRoutes.day1JobBlueprint
                    .replaceFirst(':jobId', jobs[i].id),
              ),
              onSchedule: () => _scheduleDay1(context, ref, jobs[i]),
              onMarkDeposit: () =>
                  _markDepositCollected(context, ref, jobs[i]),
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
            Icons.electrical_services_outlined,
            size: 56,
            color: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 16),
          Text(
            'No Day 1 jobs in your queue',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.5),
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Signed estimates will appear here',
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

class _Day1JobCard extends StatelessWidget {
  final SalesJob job;
  final VoidCallback onTap;
  final VoidCallback onSchedule;
  final VoidCallback onMarkDeposit;

  const _Day1JobCard({
    required this.job,
    required this.onTap,
    required this.onSchedule,
    required this.onMarkDeposit,
  });

  static Color _statusColor(SalesJobStatus s) => switch (s) {
        SalesJobStatus.estimateSigned => const Color(0xFF00D4FF),
        SalesJobStatus.prewireScheduled => NexGenPalette.amber,
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
    final hasDate = job.day1Date != null;

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

              // Deposit gate — shown INSTEAD of scheduling UI when the
              // 50% deposit hasn't been collected yet (Part 10).
              if (!job.depositCollected)
                _DepositGateBanner(
                  job: job,
                  onMarkDeposit: onMarkDeposit,
                )
              // Date or schedule button
              else if (hasDate)
                Row(
                  children: [
                    Icon(
                      Icons.calendar_today,
                      size: 14,
                      color: NexGenPalette.cyan,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Day 1: ${_formatDate(job.day1Date!)}',
                      style: TextStyle(
                        color: NexGenPalette.cyan,
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
                      color: NexGenPalette.cyan,
                      size: 16,
                    ),
                    label: Text(
                      'Schedule Day 1',
                      style: TextStyle(color: NexGenPalette.cyan),
                    ),
                    style: OutlinedButton.styleFrom(
                      side: BorderSide(
                        color: NexGenPalette.cyan.withValues(alpha: 0.4),
                      ),
                      padding:
                          const EdgeInsets.symmetric(vertical: 10),
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

// ─────────────────────────────────────────────────────────────────────────────
// Deposit gate banner (Part 10)
// ─────────────────────────────────────────────────────────────────────────────

class _DepositGateBanner extends StatelessWidget {
  final SalesJob job;
  final VoidCallback onMarkDeposit;

  const _DepositGateBanner({required this.job, required this.onMarkDeposit});

  @override
  Widget build(BuildContext context) {
    final amount = job.totalPriceUsd * 0.5;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: NexGenPalette.amber.withValues(alpha: 0.1),
        border: Border.all(color: NexGenPalette.amber),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.payments_outlined,
                  color: NexGenPalette.amber, size: 18),
              const SizedBox(width: 8),
              const Text(
                '50% Deposit Required',
                style: TextStyle(
                  color: NexGenPalette.amber,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Collect \$${amount.toStringAsFixed(2)} from '
            '${job.prospect.fullName} before scheduling Day 1 installation.',
            style: TextStyle(
              color: NexGenPalette.textMedium,
              fontSize: 12,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: onMarkDeposit,
              icon: const Icon(Icons.check_circle_outline),
              label: const Text('Mark Deposit Collected'),
              style: ElevatedButton.styleFrom(
                backgroundColor: NexGenPalette.amber,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
