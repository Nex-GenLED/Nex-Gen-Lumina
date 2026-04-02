import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Dealer Dashboard Providers — all scoped to a single dealerCode
// ─────────────────────────────────────────────────────────────────────────────

/// Jobs for a specific dealer, ordered by most recently updated.
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

/// Pending referral payouts scoped to this dealer's jobs.
final dealerPendingPayoutsProvider =
    StreamProvider.family<List<ReferralPayout>, String>((ref, dealerCode) {
  final jobIds = ref
          .watch(dealerJobsProvider(dealerCode))
          .valueOrNull
          ?.map((j) => j.id)
          .toSet() ??
      {};

  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
    final all =
        snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList();
    if (jobIds.isEmpty) return <ReferralPayout>[];
    return all.where((p) => jobIds.contains(p.jobId)).toList();
  });
});

/// All payouts scoped to this dealer (all statuses). Used by the Payouts tab.
final dealerAllPayoutsProvider =
    StreamProvider.family<List<ReferralPayout>, String>((ref, dealerCode) {
  final jobIds = ref
          .watch(dealerJobsProvider(dealerCode))
          .valueOrNull
          ?.map((j) => j.id)
          .toSet() ??
      {};

  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
    final all =
        snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList();
    if (jobIds.isEmpty) return <ReferralPayout>[];
    return all.where((p) => jobIds.contains(p.jobId)).toList();
  });
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
  final jobIds = jobs.map((j) => j.id).toSet();
  final recentJobs = jobs.take(10).toList();

  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .orderBy('createdAt', descending: true)
      .limit(30)
      .snapshots()
      .map((snap) {
    final allPayouts =
        snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList();
    final dealerPayouts =
        allPayouts.where((p) => jobIds.contains(p.jobId)).take(10).toList();

    final events = <DealerActivityEvent>[
      ...recentJobs.map(_jobToActivity),
      ...dealerPayouts.map(_payoutToActivity),
    ];

    events.sort((a, b) => b.timestamp.compareTo(a.timestamp));
    return events.take(15).toList();
  });
});
