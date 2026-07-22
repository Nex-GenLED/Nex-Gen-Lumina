import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';

// ─────────────────────────────────────────────────────────────────────────────
// DealerPricingService
//
// Reads per-dealer estimate pricing from Firestore at:
//   dealers/{dealerCode}/pricing/current
//
// If no pricing document exists for the dealer, falls back to
// [DealerPricing.defaults] so the Estimate Wizard always has working
// numbers. When a dealer eventually sets their pricing in Firestore the
// loader picks it up automatically — no code change required.
// ─────────────────────────────────────────────────────────────────────────────

class DealerPricingService {
  final FirebaseFirestore _db;

  DealerPricingService(this._db);

  DocumentReference<Map<String, dynamic>> _pricingDoc(String dealerCode) =>
      _db.collection('dealers').doc(dealerCode).collection('pricing').doc('current');

  DocumentReference<Map<String, dynamic>> get _networkDefaultsDoc =>
      _db.collection('app_config').doc('pricing_defaults');

  /// Load the current pricing for [dealerCode] using a 3-tier fallback:
  ///   1. dealers/{dealerCode}/pricing/current   (dealer-specific)
  ///   2. app_config/pricing_defaults             (network-wide defaults
  ///                                               managed via the
  ///                                               Corporate Admin tab)
  ///   3. [DealerPricing.defaults]                (hardcoded last resort)
  ///
  /// Any error reading either Firestore doc cleanly degrades to the
  /// next tier so the Estimate Wizard always has working numbers.
  Future<DealerPricing> getPricing(String dealerCode) async {
    // Tier 1 — dealer-specific pricing
    if (dealerCode.isNotEmpty) {
      try {
        final snap = await _pricingDoc(dealerCode).get();
        if (snap.exists) {
          final data = snap.data();
          if (data != null) return DealerPricing.fromJson(data);
        }
      } catch (_) {
        // Fall through to tier 2.
      }
    }

    // Tier 2 — network-wide defaults from app_config/pricing_defaults
    try {
      final snap = await _networkDefaultsDoc.get();
      if (snap.exists) {
        final data = snap.data();
        if (data != null) return DealerPricing.fromJson(data);
      }
    } catch (_) {
      // Fall through to tier 3.
    }

    // Tier 3 — hardcoded fallback
    return DealerPricing.defaults();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Providers
// ─────────────────────────────────────────────────────────────────────────────

final dealerPricingServiceProvider = Provider<DealerPricingService>(
  (ref) => DealerPricingService(FirebaseFirestore.instance),
);

/// Reads the current sales session for the active dealer code, fetches
/// that dealer's pricing, and exposes it as an [AsyncValue]. Returns
/// [DealerPricing.defaults] when no session is active.
final dealerPricingProvider = FutureProvider<DealerPricing>((ref) async {
  final session = ref.watch(currentSalesSessionProvider);
  if (session == null) return DealerPricing.defaults();
  final service = ref.watch(dealerPricingServiceProvider);
  return service.getPricing(session.dealerCode);
});
