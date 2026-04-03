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
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/dealer_demo_code.dart';

/// Validates dealer demo codes against Firestore.
class DemoCodeService {
  /// Validate a demo code against Firestore /dealer_demo_codes collection.
  /// Returns the [DealerDemoCode] if valid and active, null if invalid/expired.
  Future<DealerDemoCode?> validateCode(String code) async {
    final normalized = code.trim().toUpperCase();
    print('🔍 DEMO: Validating code: "$normalized"');

    final snap = await FirebaseFirestore.instance
        .collection('dealer_demo_codes')
        .where('code', isEqualTo: normalized)
        .where('isActive', isEqualTo: true)
        .limit(1)
        .get();

    print('🔍 DEMO: Query returned ${snap.docs.length} docs');

    if (snap.docs.isEmpty) {
      print('🔍 DEMO: No matching documents found');
      return null;
    }

    final data = snap.docs.first.data();
    print('🔍 DEMO: Found doc: $data');

    late final DealerDemoCode demoCode;
    try {
      demoCode = DealerDemoCode.fromJson(data);
      print('🔍 DEMO: Parsed OK — market="${demoCode.market}"');
    } catch (e, st) {
      print('🔍 DEMO: fromJson FAILED: $e');
      print('🔍 DEMO: Stack: $st');
      rethrow;
    }

    // Check expiry
    if (demoCode.expiresAt != null &&
        demoCode.expiresAt!.isBefore(DateTime.now())) {
      print('🔍 DEMO: Code expired');
      return null;
    }

    // Check usage limit
    if (demoCode.maxUses != null &&
        demoCode.usageCount >= demoCode.maxUses!) {
      print('🔍 DEMO: Usage limit reached');
      return null;
    }

    print('🔍 DEMO: Code valid — returning DealerDemoCode');

    // Increment usage count (fire and forget)
    snap.docs.first.reference.update({
      'usageCount': FieldValue.increment(1),
    });

    return demoCode;
  }
}

final demoCodeServiceProvider = Provider<DemoCodeService>(
    (ref) => DemoCodeService());
