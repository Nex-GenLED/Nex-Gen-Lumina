import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/referrals/services/reward_calculation_service.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';

class ReferralPipelineService {
  /// Given a prospect's UID, finds their referral doc on the referrer's
  /// subcollection and updates its status and job_id.
  Future<void> updateReferralStatus({
    required String prospectUid,
    required String newStatus,
    String? jobId,
  }) async {
    // 1. Read referrer_uid from users/{prospectUid}
    final prospectDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(prospectUid)
        .get();
    final referrerUid = prospectDoc.data()?['referrer_uid'] as String?;
    if (referrerUid == null) return; // not a referral, exit silently

    // 2. Find the referral doc where prospect_uid == prospectUid
    final query = await FirebaseFirestore.instance
        .collection('users')
        .doc(referrerUid)
        .collection('referrals')
        .where('prospect_uid', isEqualTo: prospectUid)
        .limit(1)
        .get();
    if (query.docs.isEmpty) return;

    // 3. Update status and optional job_id
    final update = <String, dynamic>{
      'status': newStatus,
      'status_updated_at': FieldValue.serverTimestamp(),
      if (jobId != null) 'job_id': jobId,
    };
    await query.docs.first.reference.update(update);

    // ── Payout creation on 'installed' ──────────────────────────
    // When a job reaches installed status, calculate and write a
    // ReferralPayout doc for dealer approval.
    if (newStatus == 'installed' && jobId != null) {
      try {
        final jobDoc = await FirebaseFirestore.instance
            .collection('sales_jobs')
            .doc(jobId)
            .get();
        if (jobDoc.exists) {
          final job = SalesJob.fromJson({...jobDoc.data()!, 'id': jobDoc.id});

          // Find the referral doc ID
          final referralQuery = await FirebaseFirestore.instance
              .collection('users')
              .doc(referrerUid)
              .collection('referrals')
              .where('job_id', isEqualTo: jobId)
              .limit(1)
              .get();
          final referralDocId = referralQuery.docs.isNotEmpty
              ? referralQuery.docs.first.id
              : '';

          // Calculate the payout
          final calcService = RewardCalculationService();
          final payout = await calcService.calculatePayout(
            referrerUid: referrerUid,
            referralDocId: referralDocId,
            job: job,
          );

          // Write payout doc to Firestore
          if (payout != null) {
            await FirebaseFirestore.instance
                .collection('referral_payouts')
                .doc(payout.id)
                .set(payout.toJson());
          }
        }
      } catch (e) {
        debugPrint('ReferralPipelineService: payout creation failed: $e');
      }
    }
  }
}

final referralPipelineServiceProvider =
    Provider<ReferralPipelineService>((ref) => ReferralPipelineService());

// ---------------------------------------------------------------------------
// Integration guide: call updateReferralStatus() as a fire-and-forget side
// effect at each pipeline stage. Each call should be wrapped in try/catch.
//
//   Estimate sent to customer  → status: "estimateSent"
//     (no screen exists yet — wire up when an estimate/quote flow is added)
//
//   Customer signs estimate    → status: "confirmed"
//     (no screen exists yet — wire up when a signature/acceptance flow is added)
//
//   Install begins (Day 1)    → status: "installing"
//     (no day-1 checklist exists yet — wire up when that checklist is added)
//
//   Install complete (Day 2)  → status: "installed", jobId: installationRef.id
//     ✅ Integrated in InstallerSetupWizard._completeSetup()
// ---------------------------------------------------------------------------
