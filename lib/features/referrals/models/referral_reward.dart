import 'package:cloud_firestore/cloud_firestore.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RewardTier
// ─────────────────────────────────────────────────────────────────────────────

class RewardTier {
  final double installValueMin;
  final double installValueMax;
  final double gcPayoutUsd;
  final double creditPayoutUsd;

  const RewardTier({
    required this.installValueMin,
    required this.installValueMax,
    required this.gcPayoutUsd,
    required this.creditPayoutUsd,
  });
}

// ─────────────────────────────────────────────────────────────────────────────
// RewardTiers — tier lookup table and GC cap
// ─────────────────────────────────────────────────────────────────────────────

class RewardTiers {
  static const double annualGcCap = 599.0;

  static const List<RewardTier> tiers = [
    RewardTier(installValueMin: 0,    installValueMax: 1499.99, gcPayoutUsd: 50,  creditPayoutUsd: 100),
    RewardTier(installValueMin: 1500, installValueMax: 2999.99, gcPayoutUsd: 100, creditPayoutUsd: 200),
    RewardTier(installValueMin: 3000, installValueMax: 4999.99, gcPayoutUsd: 150, creditPayoutUsd: 300),
    RewardTier(installValueMin: 5000, installValueMax: 7499.99, gcPayoutUsd: 200, creditPayoutUsd: 400),
    RewardTier(installValueMin: 7500, installValueMax: double.infinity, gcPayoutUsd: 250, creditPayoutUsd: 500),
  ];

  /// Returns the matching tier for a given install value.
  /// Returns null if value is 0 or negative.
  static RewardTier? forInstallValue(double installValueUsd) {
    if (installValueUsd <= 0) return null;
    for (final t in tiers) {
      if (installValueUsd >= t.installValueMin &&
          installValueUsd <= t.installValueMax) {
        return t;
      }
    }
    return null;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// RewardType
// ─────────────────────────────────────────────────────────────────────────────

enum RewardType { visaGiftCard, nexGenCredit }

extension RewardTypeX on RewardType {
  String get label => const {
    RewardType.visaGiftCard: 'Visa Gift Card',
    RewardType.nexGenCredit: 'Nex-Gen Credit',
  }[this]!;

  String get description => const {
    RewardType.visaGiftCard: 'Physical or digital Visa gift card',
    RewardType.nexGenCredit: 'Credit toward Nex-Gen equipment or installation',
  }[this]!;
}

// ─────────────────────────────────────────────────────────────────────────────
// RewardPayoutStatus
// ─────────────────────────────────────────────────────────────────────────────

enum RewardPayoutStatus { pending, approved, fulfilled, gcCapReached }

extension RewardPayoutStatusX on RewardPayoutStatus {
  String get label => const {
    RewardPayoutStatus.pending: 'Pending approval',
    RewardPayoutStatus.approved: 'Approved',
    RewardPayoutStatus.fulfilled: 'Fulfilled',
    RewardPayoutStatus.gcCapReached: 'GC cap reached — credit issued',
  }[this]!;

  static RewardPayoutStatus fromString(String s) =>
      RewardPayoutStatus.values.firstWhere(
        (e) => e.name == s,
        orElse: () => RewardPayoutStatus.pending,
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// ReferralPayout
// ─────────────────────────────────────────────────────────────────────────────

class ReferralPayout {
  final String id;
  final String referrerUid;
  final String referralDocId;
  final String jobId;
  final String jobNumber;
  final String prospectName;
  final double installValueUsd;
  final RewardTier tier;
  final RewardType rewardType;
  final double rewardAmountUsd;
  final bool gcCapApplied;
  final RewardPayoutStatus status;
  final String? approvedByUid;
  final String? fulfillmentNote;
  final DateTime createdAt;
  final DateTime? approvedAt;
  final DateTime? fulfilledAt;
  final int payoutYear;

  const ReferralPayout({
    required this.id,
    required this.referrerUid,
    required this.referralDocId,
    required this.jobId,
    required this.jobNumber,
    required this.prospectName,
    required this.installValueUsd,
    required this.tier,
    required this.rewardType,
    required this.rewardAmountUsd,
    required this.gcCapApplied,
    required this.status,
    this.approvedByUid,
    this.fulfillmentNote,
    required this.createdAt,
    this.approvedAt,
    this.fulfilledAt,
    required this.payoutYear,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'referrerUid': referrerUid,
    'referralDocId': referralDocId,
    'jobId': jobId,
    'jobNumber': jobNumber,
    'prospectName': prospectName,
    'installValueUsd': installValueUsd,
    'tierMin': tier.installValueMin,
    'tierMax': tier.installValueMax,
    'gcPayoutUsd': tier.gcPayoutUsd,
    'creditPayoutUsd': tier.creditPayoutUsd,
    'rewardType': rewardType.name,
    'rewardAmountUsd': rewardAmountUsd,
    'gcCapApplied': gcCapApplied,
    'status': status.name,
    'approvedByUid': approvedByUid,
    'fulfillmentNote': fulfillmentNote,
    'createdAt': Timestamp.fromDate(createdAt),
    'approvedAt': approvedAt != null ? Timestamp.fromDate(approvedAt!) : null,
    'fulfilledAt': fulfilledAt != null ? Timestamp.fromDate(fulfilledAt!) : null,
    'payoutYear': payoutYear,
  };

  factory ReferralPayout.fromJson(Map<String, dynamic> j) {
    final tier = RewardTier(
      installValueMin: (j['tierMin'] as num).toDouble(),
      installValueMax: (j['tierMax'] as num?)?.toDouble() ?? double.infinity,
      gcPayoutUsd: (j['gcPayoutUsd'] as num).toDouble(),
      creditPayoutUsd: (j['creditPayoutUsd'] as num).toDouble(),
    );
    return ReferralPayout(
      id: j['id'] ?? '',
      referrerUid: j['referrerUid'] ?? '',
      referralDocId: j['referralDocId'] ?? '',
      jobId: j['jobId'] ?? '',
      jobNumber: j['jobNumber'] ?? '',
      prospectName: j['prospectName'] ?? '',
      installValueUsd: (j['installValueUsd'] as num).toDouble(),
      tier: tier,
      rewardType: RewardType.values.byName(j['rewardType'] ?? 'nexGenCredit'),
      rewardAmountUsd: (j['rewardAmountUsd'] as num).toDouble(),
      gcCapApplied: j['gcCapApplied'] ?? false,
      status: RewardPayoutStatusX.fromString(j['status'] ?? 'pending'),
      approvedByUid: j['approvedByUid'],
      fulfillmentNote: j['fulfillmentNote'],
      createdAt: (j['createdAt'] as Timestamp).toDate(),
      approvedAt: (j['approvedAt'] as Timestamp?)?.toDate(),
      fulfilledAt: (j['fulfilledAt'] as Timestamp?)?.toDate(),
      payoutYear: j['payoutYear'] ?? DateTime.now().year,
    );
  }

  ReferralPayout copyWith({
    RewardPayoutStatus? status,
    String? approvedByUid,
    String? fulfillmentNote,
    DateTime? approvedAt,
    DateTime? fulfilledAt,
  }) => ReferralPayout(
    id: id,
    referrerUid: referrerUid,
    referralDocId: referralDocId,
    jobId: jobId,
    jobNumber: jobNumber,
    prospectName: prospectName,
    installValueUsd: installValueUsd,
    tier: tier,
    rewardType: rewardType,
    rewardAmountUsd: rewardAmountUsd,
    gcCapApplied: gcCapApplied,
    payoutYear: payoutYear,
    createdAt: createdAt,
    status: status ?? this.status,
    approvedByUid: approvedByUid ?? this.approvedByUid,
    fulfillmentNote: fulfillmentNote ?? this.fulfillmentNote,
    approvedAt: approvedAt ?? this.approvedAt,
    fulfilledAt: fulfilledAt ?? this.fulfilledAt,
  );
}
