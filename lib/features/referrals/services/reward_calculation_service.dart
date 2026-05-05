import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// RewardCalculationService
// ─────────────────────────────────────────────────────────────────────────────

class RewardCalculationService {

  /// Returns the year-to-date total GC payouts for a referrer.
  Future<double> getYtdGcPayouts(String referrerUid) async {
    final year = DateTime.now().year;
    final snapshot = await FirebaseFirestore.instance
        .collection('referral_payouts')
        .where('referrerUid', isEqualTo: referrerUid)
        .where('payoutYear', isEqualTo: year)
        .where('rewardType', isEqualTo: 'visaGiftCard')
        .where('status', whereIn: ['approved', 'fulfilled'])
        .get();
    double total = 0.0;
    for (final doc in snapshot.docs) {
      total += (doc.data()['rewardAmountUsd'] as num?)?.toDouble() ?? 0.0;
    }
    return total;
  }

  /// Core calculation method. Call when a job hits 'installed'.
  /// Returns a ReferralPayout ready to write to Firestore.
  /// Does NOT write to Firestore itself — caller does that.
  Future<ReferralPayout?> calculatePayout({
    required String referrerUid,
    required String referralDocId,
    required SalesJob job,
  }) async {
    final tier = RewardTiers.forInstallValue(job.totalPriceUsd);
    if (tier == null) return null;

    final ytdGc = await getYtdGcPayouts(referrerUid);
    final remainingGcAllowance = RewardTiers.annualGcCap - ytdGc;

    final bool gcCapReached = remainingGcAllowance < tier.gcPayoutUsd;
    final RewardType rewardType = gcCapReached
        ? RewardType.nexGenCredit
        : RewardType.visaGiftCard;
    final double rewardAmount = gcCapReached
        ? tier.creditPayoutUsd
        : tier.gcPayoutUsd;

    final id = FirebaseFirestore.instance
        .collection('referral_payouts')
        .doc()
        .id;

    return ReferralPayout(
      id: id,
      referrerUid: referrerUid,
      referralDocId: referralDocId,
      jobId: job.id,
      // Carry the dealer code from the linked sales_job so firestore.rules
      // can scope payout reads via hasStaffClaim() without dereferencing
      // the linked job on every rule eval.
      dealerCode: job.dealerCode,
      jobNumber: job.jobNumber,
      prospectName: job.prospect.fullName,
      installValueUsd: job.totalPriceUsd,
      tier: tier,
      rewardType: rewardType,
      rewardAmountUsd: rewardAmount,
      gcCapApplied: gcCapReached,
      status: RewardPayoutStatus.pending,
      createdAt: DateTime.now(),
      payoutYear: DateTime.now().year,
    );
  }
}

final rewardCalculationServiceProvider =
    Provider<RewardCalculationService>((ref) => RewardCalculationService());
