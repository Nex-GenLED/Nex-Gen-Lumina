import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/referrals/models/ambassador_tier.dart';

class AmbassadorTierData {
  const AmbassadorTierData({
    required this.tier,
    required this.installCount,
    required this.progressToNextTier,
    required this.installsToNextTier,
  });

  final AmbassadorTier tier;
  final int installCount;
  final double progressToNextTier;
  final int? installsToNextTier;
}

/// Streams the user's ambassador tier computed from referrals with
/// status "installed" or "paid".
final ambassadorTierProvider = StreamProvider<AmbassadorTierData>((ref) {
  final user = ref.watch(authStateProvider).asData?.value;
  if (user == null) {
    return Stream.value(const AmbassadorTierData(
      tier: AmbassadorTier.bronze,
      installCount: 0,
      progressToNextTier: 0.0,
      installsToNextTier: 3,
    ));
  }

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('referrals')
      .where('status', whereIn: ['installed', 'paid'])
      .snapshots()
      .map((snap) {
        final count = snap.docs.length;
        final tier = AmbassadorTierX.fromInstallCount(count);
        final nextThreshold = tier.nextThreshold;

        double progress;
        int? remaining;
        if (nextThreshold == null) {
          // Platinum — max tier
          progress = 1.0;
          remaining = null;
        } else {
          final rangeSize = nextThreshold - tier.threshold;
          final withinRange = count - tier.threshold;
          progress = rangeSize > 0 ? withinRange / rangeSize : 0.0;
          remaining = nextThreshold - count;
        }

        return AmbassadorTierData(
          tier: tier,
          installCount: count,
          progressToNextTier: progress,
          installsToNextTier: remaining,
        );
      });
});
