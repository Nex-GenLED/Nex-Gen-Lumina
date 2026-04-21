// Firestore /dealer_demo_codes seed document example:
// {
//   code: 'KC2026',
//   dealerCode: '01',
//   dealerName: 'Nex-Gen LED Kansas City',
//   market: 'Kansas City',
//   isActive: true,
//   usageCount: 0,
//   maxUses: null,
//   createdAt: <timestamp>,
//   expiresAt: null,
// }

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/dealer_demo_code.dart';

/// Validates dealer demo codes against Firestore.
class DemoCodeService {
  /// Validate a demo code against Firestore /dealer_demo_codes collection.
  /// Returns the [DealerDemoCode] if valid and active, null if invalid/expired.
  Future<DealerDemoCode?> validateCode(String code) async {
    final normalized = code.trim().toUpperCase();

    final snap = await FirebaseFirestore.instance
        .collection('dealer_demo_codes')
        .where('code', isEqualTo: normalized)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    if (snap.docs.isEmpty) {
      return null;
    }

    final data = snap.docs.first.data();
    final demoCode = DealerDemoCode.fromJson(data);

    // Check expiry
    if (demoCode.expiresAt != null &&
        demoCode.expiresAt!.isBefore(DateTime.now())) {
      return null;
    }

    // Check usage limit
    if (demoCode.maxUses != null &&
        demoCode.usageCount >= demoCode.maxUses!) {
      return null;
    }

    // Increment usage count (fire and forget)
    snap.docs.first.reference.update({
      'usageCount': FieldValue.increment(1),
    });

    return demoCode;
  }
}

final demoCodeServiceProvider = Provider<DemoCodeService>(
    (ref) => DemoCodeService());
