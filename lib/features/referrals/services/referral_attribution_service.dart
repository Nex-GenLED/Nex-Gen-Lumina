import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class ReferralAttributionService {
  /// Validates a referral code and returns the referring user's UID, or null.
  Future<String?> validateCode(String code) async {
    final normalized = code.trim().toUpperCase();
    if (normalized.isEmpty) return null;
    final doc = await FirebaseFirestore.instance
        .collection('referral_codes')
        .doc(normalized)
        .get();
    if (!doc.exists) return null;
    return doc.data()?['uid'] as String?;
  }

  /// Called after prospect account is created. Writes referral doc to
  /// the referring user's subcollection and updates the reverse lookup.
  Future<void> attributeReferral({
    required String referrerUid,
    required String prospectUid,
    required String prospectName,
  }) async {
    final batch = FirebaseFirestore.instance.batch();

    // Write referral doc to referrer's subcollection
    final refDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(referrerUid)
        .collection('referrals')
        .doc();
    batch.set(refDoc, {
      'name': prospectName,
      'status': 'lead',
      'created_at': FieldValue.serverTimestamp(),
      'status_updated_at': FieldValue.serverTimestamp(),
      'prospect_uid': prospectUid,
      'job_id': null,
    });

    // Write referrer_uid to prospect's user doc for downstream lookup
    final prospectDoc = FirebaseFirestore.instance
        .collection('users')
        .doc(prospectUid);
    batch.update(prospectDoc, {'referrer_uid': referrerUid});

    await batch.commit();
  }
}

final referralAttributionServiceProvider =
    Provider<ReferralAttributionService>((ref) => ReferralAttributionService());
