import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

/// Streams ALL dealers from the `dealers` collection, ordered by code.
///
/// Reuses the same [DealerInfo.fromMap] used by the existing dealer list
/// providers in `admin_providers.dart` so the corporate view stays in
/// sync with the master admin view.
final corporateDealersProvider =
    StreamProvider<List<DealerInfo>>((ref) {
  return FirebaseFirestore.instance
      .collection('dealers')
      .orderBy('dealerCode')
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => DealerInfo.fromMap(doc.data())).toList());
});

/// Streams ALL `sales_jobs` documents across every dealer, ordered by
/// `createdAt` descending. The corporate dashboard reads cross-dealer,
/// so there is no `dealerCode` filter here.
///
/// Note: this is a flat collection (not a subcollection), so a regular
/// stream — not a collection group query — is sufficient.
final corporateAllJobsStreamProvider =
    StreamProvider<List<SalesJob>>((ref) {
  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
});

/// Aggregate revenue + activity stats for the Network tab header.
///
/// Computed from [corporateAllJobsStreamProvider] entirely client-side
/// so we can reuse the live job stream rather than firing off separate
/// aggregation queries. Recomputes whenever the underlying jobs change.
class CorporateNetworkStats {
  final int totalActiveDealers;
  final int totalJobsThisMonth;
  final double totalRevenueThisMonth;
  final double averageJobValueThisMonth;

  const CorporateNetworkStats({
    required this.totalActiveDealers,
    required this.totalJobsThisMonth,
    required this.totalRevenueThisMonth,
    required this.averageJobValueThisMonth,
  });

  static const empty = CorporateNetworkStats(
    totalActiveDealers: 0,
    totalJobsThisMonth: 0,
    totalRevenueThisMonth: 0,
    averageJobValueThisMonth: 0,
  );
}

final corporateNetworkStatsProvider =
    Provider<AsyncValue<CorporateNetworkStats>>((ref) {
  final dealersAsync = ref.watch(corporateDealersProvider);
  final jobsAsync = ref.watch(corporateAllJobsStreamProvider);

  if (dealersAsync.isLoading || jobsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (dealersAsync.hasError) {
    return AsyncValue.error(
        dealersAsync.error!, dealersAsync.stackTrace ?? StackTrace.current);
  }
  if (jobsAsync.hasError) {
    return AsyncValue.error(
        jobsAsync.error!, jobsAsync.stackTrace ?? StackTrace.current);
  }

  final dealers = dealersAsync.value ?? const [];
  final jobs = jobsAsync.value ?? const [];

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final nextMonthStart = DateTime(now.year, now.month + 1, 1);

  final activeDealers = dealers.where((d) => d.isActive).length;

  final jobsThisMonth = jobs.where((j) {
    return !j.createdAt.isBefore(monthStart) &&
        j.createdAt.isBefore(nextMonthStart);
  }).toList();

  final completedThisMonth = jobsThisMonth.where(
    (j) =>
        j.status == SalesJobStatus.installComplete &&
        !j.updatedAt.isBefore(monthStart) &&
        j.updatedAt.isBefore(nextMonthStart),
  );

  final totalRevenueThisMonth =
      completedThisMonth.fold<double>(0, (acc, j) => acc + j.totalPriceUsd);

  final avgJobValue = jobsThisMonth.isEmpty
      ? 0.0
      : jobsThisMonth.fold<double>(0, (a, j) => a + j.totalPriceUsd) /
          jobsThisMonth.length;

  return AsyncValue.data(CorporateNetworkStats(
    totalActiveDealers: activeDealers,
    totalJobsThisMonth: jobsThisMonth.length,
    totalRevenueThisMonth: totalRevenueThisMonth,
    averageJobValueThisMonth: avgJobValue,
  ));
});

/// Per-dealer summary used to render dealer cards on the Network tab.
class DealerNetworkSummary {
  final DealerInfo dealer;
  final int jobsThisMonth;
  final int activeJobsCount;
  final DateTime? lastJobCreatedAt;
  final double mtdRevenue;
  /// Composite health score in [0.0, 1.0] — average of activity recency
  /// and revenue progress against a $10k/month target. Drives the
  /// red/amber/green dot on each dealer card in the Corporate Network tab.
  final double healthScore;

  const DealerNetworkSummary({
    required this.dealer,
    required this.jobsThisMonth,
    required this.activeJobsCount,
    required this.lastJobCreatedAt,
    this.mtdRevenue = 0,
    this.healthScore = 0,
  });

  /// Health classification based on most recent job activity.
  DealerHealth get health {
    final last = lastJobCreatedAt;
    if (last == null) return DealerHealth.stalled;
    final daysSince = DateTime.now().difference(last).inDays;
    if (daysSince <= 14) return DealerHealth.active;
    if (daysSince <= 30) return DealerHealth.quiet;
    return DealerHealth.stalled;
  }
}

/// Default monthly revenue target used by the dealer health composite.
/// Tweaking this only changes the color band — the underlying revenue is
/// still surfaced verbatim alongside the score.
const double _kDealerMtdRevenueTarget = 10000.0;

enum DealerHealth { active, quiet, stalled }

/// Provider that joins [corporateDealersProvider] and
/// [corporateAllJobsStreamProvider] into per-dealer summaries.
///
/// Active jobs = anything that is not [SalesJobStatus.installComplete].
/// (There is currently no `lost` status in the SalesJobStatus enum.)
final corporateDealerSummariesProvider =
    Provider<AsyncValue<List<DealerNetworkSummary>>>((ref) {
  final dealersAsync = ref.watch(corporateDealersProvider);
  final jobsAsync = ref.watch(corporateAllJobsStreamProvider);

  if (dealersAsync.isLoading || jobsAsync.isLoading) {
    return const AsyncValue.loading();
  }
  if (dealersAsync.hasError) {
    return AsyncValue.error(
        dealersAsync.error!, dealersAsync.stackTrace ?? StackTrace.current);
  }
  if (jobsAsync.hasError) {
    return AsyncValue.error(
        jobsAsync.error!, jobsAsync.stackTrace ?? StackTrace.current);
  }

  final dealers = dealersAsync.value ?? const [];
  final jobs = jobsAsync.value ?? const [];

  final now = DateTime.now();
  final monthStart = DateTime(now.year, now.month, 1);
  final nextMonthStart = DateTime(now.year, now.month + 1, 1);

  final byDealer = <String, List<SalesJob>>{};
  for (final j in jobs) {
    byDealer.putIfAbsent(j.dealerCode, () => <SalesJob>[]).add(j);
  }

  final summaries = dealers.map((dealer) {
    final list = byDealer[dealer.dealerCode] ?? const <SalesJob>[];

    final monthly = list.where((j) =>
        !j.createdAt.isBefore(monthStart) &&
        j.createdAt.isBefore(nextMonthStart));

    final active =
        list.where((j) => j.status != SalesJobStatus.installComplete);

    DateTime? mostRecent;
    for (final j in list) {
      if (mostRecent == null || j.createdAt.isAfter(mostRecent)) {
        mostRecent = j.createdAt;
      }
    }

    // MTD revenue — installs completed this month.
    final mtdRevenue = list
        .where((j) =>
            j.status == SalesJobStatus.installComplete &&
            !j.updatedAt.isBefore(monthStart) &&
            j.updatedAt.isBefore(nextMonthStart))
        .fold<double>(0, (acc, j) => acc + j.totalPriceUsd);

    // Composite health score: activity recency × revenue-vs-target.
    final daysSinceLast = mostRecent == null
        ? 9999
        : DateTime.now().difference(mostRecent).inDays;
    final activityScore = daysSinceLast <= 7
        ? 1.0
        : daysSinceLast <= 30
            ? 0.5
            : 0.0;
    final revenueScore =
        (mtdRevenue / _kDealerMtdRevenueTarget).clamp(0.0, 1.0);
    final healthScore = (activityScore + revenueScore) / 2;

    return DealerNetworkSummary(
      dealer: dealer,
      jobsThisMonth: monthly.length,
      activeJobsCount: active.length,
      lastJobCreatedAt: mostRecent,
      mtdRevenue: mtdRevenue,
      healthScore: healthScore,
    );
  }).toList();

  return AsyncValue.data(summaries);
});
