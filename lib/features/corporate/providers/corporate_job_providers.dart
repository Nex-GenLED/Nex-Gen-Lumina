import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/corporate/providers/corporate_network_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

/// Streams ALL `sales_jobs` documents across every dealer, ordered by
/// `createdAt` descending. Re-exported here under a stable name so the
/// pipeline screen can import a job-specific provider file rather than
/// the network providers file.
///
/// Aliases [corporateAllJobsStreamProvider].
final allJobsProvider = corporateAllJobsStreamProvider;

/// Server-side filtered stream of `sales_jobs` by status list.
///
/// Pass `null` or an empty list to return ALL jobs across all dealers
/// (delegates to [allJobsProvider]).
///
/// Pass a non-empty list to add a `where('status', whereIn: [...])`
/// clause server-side. Firestore allows one `whereIn` per query, which
/// is fine here since this is the only one used.
///
/// Note: combining `whereIn` with `orderBy('createdAt')` requires a
/// composite index on `(status, createdAt desc)` for the `sales_jobs`
/// collection. Flagged in the build summary, not added here.
final allJobsByStatusProvider = StreamProvider.family<
    List<SalesJob>, List<SalesJobStatus>?>((ref, statuses) {
  // Inline the unfiltered query when no statuses are provided rather than
  // forwarding to allJobsProvider — keeps this provider self-contained
  // and avoids the deprecated `.stream` member.
  if (statuses == null || statuses.isEmpty) {
    return FirebaseFirestore.instance
        .collection('sales_jobs')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) =>
            snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
  }

  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('status', whereIn: statuses.map((s) => s.name).toList())
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
});

/// Streams `sales_jobs` filtered by [dealerCode]. Family-keyed for use
/// from the dealer detail drill-down.
///
/// Reuses the existing composite index on
/// `(dealerCode asc, createdAt desc)` that powers the dealer-scoped
/// `salesJobsStreamProvider` in `sales_providers.dart`.
final jobsByDealerProvider =
    StreamProvider.family<List<SalesJob>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('dealerCode', isEqualTo: dealerCode)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
});

/// Aggregate corporate-wide job stats for the Pipeline tab header.
///
/// Computed client-side off [allJobsProvider] so we can reuse the live
/// stream rather than firing dedicated count queries.
class CorporateJobStats {
  final Map<SalesJobStatus, int> jobsByStatus;
  final double totalRevenue;
  final double averageCycleTimeDays;
  final int jobsLast30Days;
  final int jobsLast7Days;
  final int totalJobs;

  const CorporateJobStats({
    required this.jobsByStatus,
    required this.totalRevenue,
    required this.averageCycleTimeDays,
    required this.jobsLast30Days,
    required this.jobsLast7Days,
    required this.totalJobs,
  });

  static const empty = CorporateJobStats(
    jobsByStatus: {},
    totalRevenue: 0,
    averageCycleTimeDays: 0,
    jobsLast30Days: 0,
    jobsLast7Days: 0,
    totalJobs: 0,
  );
}

final corporateJobStatsProvider =
    Provider<AsyncValue<CorporateJobStats>>((ref) {
  final jobsAsync = ref.watch(allJobsProvider);

  return jobsAsync.when(
    loading: () => const AsyncValue.loading(),
    error: (e, s) => AsyncValue.error(e, s),
    data: (jobs) {
      final now = DateTime.now();
      final last7 = now.subtract(const Duration(days: 7));
      final last30 = now.subtract(const Duration(days: 30));

      final byStatus = <SalesJobStatus, int>{};
      for (final s in SalesJobStatus.values) {
        byStatus[s] = 0;
      }

      double totalRevenue = 0;
      var cycleSumDays = 0.0;
      var cycleCount = 0;
      var last7Count = 0;
      var last30Count = 0;

      for (final j in jobs) {
        byStatus[j.status] = (byStatus[j.status] ?? 0) + 1;

        if (j.status == SalesJobStatus.installComplete) {
          totalRevenue += j.totalPriceUsd;

          // Cycle time = signing → install complete (Day 2 wrap-up).
          final signed = j.estimateSignedAt;
          final completed = j.day2CompletedAt ?? j.updatedAt;
          if (signed != null && completed.isAfter(signed)) {
            cycleSumDays +=
                completed.difference(signed).inHours / 24.0;
            cycleCount++;
          }
        }

        if (j.createdAt.isAfter(last7)) last7Count++;
        if (j.createdAt.isAfter(last30)) last30Count++;
      }

      return AsyncValue.data(CorporateJobStats(
        jobsByStatus: byStatus,
        totalRevenue: totalRevenue,
        averageCycleTimeDays:
            cycleCount == 0 ? 0 : cycleSumDays / cycleCount,
        jobsLast30Days: last30Count,
        jobsLast7Days: last7Count,
        totalJobs: jobs.length,
      ));
    },
  );
});
