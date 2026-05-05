import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Dashboard Providers — all scoped to a single dealerCode
// ─────────────────────────────────────────────────────────────────────────────

/// Jobs for a specific dealer, ordered by most recently updated.
///
/// Hard-capped at 50 — drives the visible Jobs tab list. Use
/// [dealerJobsAllProvider] for revenue/conversion stats so the cap doesn't
/// silently truncate aggregates as a dealer's job count grows.
final dealerJobsProvider =
    StreamProvider.family<List<SalesJob>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('dealerCode', isEqualTo: dealerCode)
      .orderBy('updatedAt', descending: true)
      .limit(50)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
});

/// Unbounded stream of every job for the dealer — used only for the
/// stats row (MTD/YTD revenue, avg ticket, conversion). Does NOT feed any
/// list UI — the visible list still pulls from [dealerJobsProvider].
final dealerJobsAllProvider =
    StreamProvider.family<List<SalesJob>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('sales_jobs')
      .where('dealerCode', isEqualTo: dealerCode)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => SalesJob.fromJson(doc.data())).toList());
});

// ─── Revenue + conversion stats ─────────────────────────────────────────────

class DealerRevenueStats {
  final double mtdRevenue;
  final double ytdRevenue;
  final double avgTicket;
  /// 0.0 — 1.0 fraction of jobs that reached installComplete.
  final double conversionRate;

  const DealerRevenueStats({
    required this.mtdRevenue,
    required this.ytdRevenue,
    required this.avgTicket,
    required this.conversionRate,
  });

  static const empty = DealerRevenueStats(
    mtdRevenue: 0,
    ytdRevenue: 0,
    avgTicket: 0,
    conversionRate: 0,
  );
}

final dealerRevenueStatsProvider =
    Provider.family<DealerRevenueStats, String>((ref, dealerCode) {
  final jobs = ref.watch(dealerJobsAllProvider(dealerCode)).valueOrNull;
  if (jobs == null || jobs.isEmpty) return DealerRevenueStats.empty;

  final now = DateTime.now();
  final mtdStart = DateTime(now.year, now.month, 1);
  final ytdStart = DateTime(now.year, 1, 1);

  double mtd = 0;
  double ytd = 0;
  int completedTotal = 0;
  double completedRevenueTotal = 0;

  for (final j in jobs) {
    if (j.status == SalesJobStatus.installComplete) {
      completedTotal++;
      completedRevenueTotal += j.totalPriceUsd;
      // Use updatedAt as the completion proxy — installComplete is set on
      // the same write that bumps updatedAt.
      if (!j.updatedAt.isBefore(mtdStart)) mtd += j.totalPriceUsd;
      if (!j.updatedAt.isBefore(ytdStart)) ytd += j.totalPriceUsd;
    }
  }

  final avgTicket =
      completedTotal == 0 ? 0.0 : completedRevenueTotal / completedTotal;
  final conversion = jobs.isEmpty ? 0.0 : completedTotal / jobs.length;

  return DealerRevenueStats(
    mtdRevenue: mtd,
    ytdRevenue: ytd,
    avgTicket: avgTicket,
    conversionRate: conversion,
  );
});

/// Jobs grouped by status for the pipeline view.
final dealerJobsByStatusProvider =
    Provider.family<Map<SalesJobStatus, List<SalesJob>>, String>(
        (ref, dealerCode) {
  final jobs = ref.watch(dealerJobsProvider(dealerCode)).valueOrNull ?? [];
  final map = <SalesJobStatus, List<SalesJob>>{
    for (final s in SalesJobStatus.values) s: [],
  };
  for (final job in jobs) {
    map[job.status]!.add(job);
  }
  return map;
});

/// Pending referral payouts scoped to this dealer.
///
/// Filters by `dealerCode` at the Firestore query level so the rule's
/// per-doc check (hasStaffClaim / dealer_code match) is satisfiable —
/// staff sessions can't list-read this collection without the where
/// clause. Single source of truth is `payout.dealerCode` (added to
/// the model in commit 3bbb6da); the previous client-side filter via
/// dealerJobsProvider's jobIds is gone.
final dealerPendingPayoutsProvider =
    StreamProvider.family<List<ReferralPayout>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('dealerCode', isEqualTo: dealerCode)
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList());
});

/// All payouts scoped to this dealer (all statuses). Used by the Payouts tab.
///
/// Same scoping pattern as [dealerPendingPayoutsProvider] — query-level
/// dealerCode filter, no client-side jobId membership join.
final dealerAllPayoutsProvider =
    StreamProvider.family<List<ReferralPayout>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('dealerCode', isEqualTo: dealerCode)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList());
});

/// Active installers under this dealer.
final dealerInstallersProvider =
    StreamProvider.family<List<InstallerInfo>, String>((ref, dealerCode) {
  return FirebaseFirestore.instance
      .collection('installers')
      .where('dealerCode', isEqualTo: dealerCode)
      .orderBy('fullPin')
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => InstallerInfo.fromMap(doc.data())).toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// Activity Event model
// ─────────────────────────────────────────────────────────────────────────────

enum DealerActivityType {
  jobCreated,
  estimateSent,
  estimateSigned,
  prewireComplete,
  installComplete,
  payoutPending,
  payoutApproved,
}

extension DealerActivityTypeX on DealerActivityType {
  String get iconLabel => const {
        DealerActivityType.jobCreated: 'NEW',
        DealerActivityType.estimateSent: 'EST',
        DealerActivityType.estimateSigned: 'SGN',
        DealerActivityType.prewireComplete: 'D1',
        DealerActivityType.installComplete: 'DONE',
        DealerActivityType.payoutPending: 'PAY',
        DealerActivityType.payoutApproved: 'PAID',
      }[this]!;
}

class DealerActivityEvent {
  final String title;
  final String subtitle;
  final DateTime timestamp;
  final DealerActivityType type;

  const DealerActivityEvent({
    required this.title,
    required this.subtitle,
    required this.timestamp,
    required this.type,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// Recent activity feed — merges job updates + payout events
// ─────────────────────────────────────────────────────────────────────────────

String fmtCurrency(double v) {
  final s = v.toStringAsFixed(0);
  return s.replaceAllMapped(
      RegExp(r'(\d)(?=(\d{3})+$)'), (m) => '${m[1]},');
}

DealerActivityEvent _jobToActivity(SalesJob job) {
  DealerActivityType type;
  switch (job.status) {
    case SalesJobStatus.draft:
      type = DealerActivityType.jobCreated;
    case SalesJobStatus.estimateSent:
      type = DealerActivityType.estimateSent;
    case SalesJobStatus.estimateSigned:
      type = DealerActivityType.estimateSigned;
    case SalesJobStatus.prewireScheduled:
    case SalesJobStatus.prewireComplete:
    case SalesJobStatus.installScheduled:
      type = DealerActivityType.prewireComplete;
    case SalesJobStatus.installComplete:
      type = DealerActivityType.installComplete;
  }

  return DealerActivityEvent(
    title: '${job.status.label} — ${job.prospect.fullName}',
    subtitle: 'Job #${job.jobNumber} · \$${fmtCurrency(job.totalPriceUsd)}',
    timestamp: job.updatedAt,
    type: type,
  );
}

DealerActivityEvent _payoutToActivity(ReferralPayout payout) {
  final isApproved = payout.status == RewardPayoutStatus.approved ||
      payout.status == RewardPayoutStatus.fulfilled;

  return DealerActivityEvent(
    title:
        '${isApproved ? 'Reward approved' : 'Reward pending'} — ${payout.prospectName}',
    subtitle:
        'Job #${payout.jobNumber} · \$${fmtCurrency(payout.rewardAmountUsd)}',
    timestamp: payout.approvedAt ?? payout.createdAt,
    type: isApproved
        ? DealerActivityType.payoutApproved
        : DealerActivityType.payoutPending,
  );
}

final dealerRecentActivityProvider =
    StreamProvider.family<List<DealerActivityEvent>, String>(
        (ref, dealerCode) {
  final jobsAsync = ref.watch(dealerJobsProvider(dealerCode));
  final jobs = jobsAsync.valueOrNull ?? [];
  final recentJobs = jobs.take(10).toList();

  // Same dealerCode-at-query-level scoping as dealerAllPayoutsProvider —
  // the unfiltered scan that used to live here would have failed
  // PERMISSION_DENIED for staff sessions under the new rule. Reuses the
  // (dealerCode, createdAt DESC) index added in this commit.
  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('dealerCode', isEqualTo: dealerCode)
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snap) {
    final dealerPayouts = snap.docs
        .map((doc) => ReferralPayout.fromJson(doc.data()))
        .take(10)
        .toList();

    final events = <DealerActivityEvent>[
      ...recentJobs.map(_jobToActivity),
      ...dealerPayouts.map(_payoutToActivity),
    ];

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.take(15).toList();
  });
});
