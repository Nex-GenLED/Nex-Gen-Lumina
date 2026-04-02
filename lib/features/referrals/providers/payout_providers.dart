import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/referrals/models/referral_reward.dart';
import 'package:nexgen_command/features/referrals/services/reward_calculation_service.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Pending payouts for the current dealer's territory
// ─────────────────────────────────────────────────────────────────────────────

final pendingPayoutsProvider = StreamProvider<List<ReferralPayout>>((ref) {
  // Determine dealer code from whichever session is active
  final salesSession = ref.watch(currentSalesSessionProvider);
  final installerSession = ref.watch(installerSessionProvider);
  final dealerCode = salesSession?.dealerCode ??
      installerSession?.dealer.dealerCode;

  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('status', isEqualTo: 'pending')
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) {
    final all = snap.docs
        .map((doc) => ReferralPayout.fromJson(doc.data()))
        .toList();
    // Client-side filter by dealer if we have a dealer code
    if (dealerCode != null) {
      // Payouts don't store dealerCode directly — we allow all
      // pending payouts visible to any active dealer/admin session
      return all;
    }
    return all;
  });
});

// ─────────────────────────────────────────────────────────────────────────────
// All payouts for a specific referrer (referrer's own view)
// ─────────────────────────────────────────────────────────────────────────────

final myPayoutsProvider =
    StreamProvider.family<List<ReferralPayout>, String>((ref, uid) {
  return FirebaseFirestore.instance
      .collection('referral_payouts')
      .where('referrerUid', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map((doc) => ReferralPayout.fromJson(doc.data())).toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// YTD GC total for display in referral dashboard
// ─────────────────────────────────────────────────────────────────────────────

final ytdGcTotalProvider =
    FutureProvider.family<double, String>((ref, uid) async {
  return RewardCalculationService().getYtdGcPayouts(uid);
});
