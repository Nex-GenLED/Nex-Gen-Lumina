import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/sales/models/sales_models.dart';

// ─────────────────────────────────────────────────────────────────────────────
// SalesJobService
//
// CRUD operations for sales jobs against the top-level `sales_jobs` collection.
// Replaces the inline FirebaseFirestore writes that previously lived in
// prospect_info_screen.dart and job_detail_screen.dart.
//
// Firestore path: sales_jobs/{jobId}
// ─────────────────────────────────────────────────────────────────────────────

class SalesJobService {
  final FirebaseFirestore _db;

  SalesJobService(this._db);

  CollectionReference<Map<String, dynamic>> _jobs() =>
      _db.collection('sales_jobs');

  /// Create a new job document.
  ///
  /// If [job] has an empty `id`, a new document ID is generated and assigned
  /// to the returned copy. Returns the persisted [SalesJob].
  Future<SalesJob> createJob(SalesJob job) async {
    final docRef = job.id.isEmpty ? _jobs().doc() : _jobs().doc(job.id);
    final created = job.id.isEmpty ? job.copyWith(id: docRef.id) : job;
    await docRef.set(created.toJson());
    return created;
  }

  /// Persist updates to an existing job.
  ///
  /// Uses `set` with `merge: true` so it is safe to call on a document that
  /// has not yet been written (matches the previous inline behavior in
  /// prospect_info_screen.dart). Bumps `updatedAt` to now.
  Future<void> updateJob(SalesJob job) async {
    final updated = job.copyWith(updatedAt: DateTime.now());
    await _jobs().doc(job.id).set(updated.toJson(), SetOptions(merge: true));
  }

  /// Lightweight status-only update.
  ///
  /// Writes only the `status` and `updatedAt` fields — does not touch any
  /// other field on the job document.
  Future<void> updateStatus(String jobId, SalesJobStatus status) async {
    await _jobs().doc(jobId).update({
      'status': status.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Delete a job document.
  Future<void> deleteJob(String jobId) async {
    await _jobs().doc(jobId).delete();
  }

  /// Atomically mark an estimate as signed by the customer.
  ///
  /// Writes `status: estimateSigned`, `customerSignatureUrl`,
  /// `estimateSignedAt`, and `updatedAt` in a single Firestore update.
  /// Used by the customer signature screen so the inline write that
  /// previously lived there is no longer needed.
  Future<void> markEstimateSigned(String jobId, String signatureUrl) async {
    final now = DateTime.now();
    await _jobs().doc(jobId).update({
      'status': SalesJobStatus.estimateSigned.name,
      'customerSignatureUrl': signatureUrl,
      'estimateSignedAt': Timestamp.fromDate(now),
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Atomically mark Day 2 (install) as complete.
  ///
  /// Writes `status: installComplete`, `day2CompletedAt: now`,
  /// `day2TechUid`, and `updatedAt` in a single Firestore update so the
  /// job moves out of every active queue atomically.
  ///
  /// Note: this does NOT touch [SalesJob.linkedUserId] — that's set
  /// separately during the wrap-up screen's customer-account step via
  /// [linkToInstall]. The wrap-up flow may call this method without
  /// having created an account first (when the installer skips Step 3),
  /// so don't make linkage a precondition.
  Future<void> markDay2Complete(String jobId, String techUid) async {
    final now = DateTime.now();
    await _jobs().doc(jobId).update({
      'status': SalesJobStatus.installComplete.name,
      'day2CompletedAt': Timestamp.fromDate(now),
      // TODO: replace with Firebase Auth UID when installer auth migrates
      'day2TechUid': techUid,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Record that the 50% deposit has been collected. Snapshots the
  /// deposit amount on the job so retroactive total-price edits can't
  /// change the historical record.
  ///
  /// Gates Day 1 scheduling — see day1_queue_screen.dart.
  Future<void> markDepositCollected({
    required String jobId,
    required String byUid,
    required double depositAmount,
  }) async {
    final now = DateTime.now();
    await _jobs().doc(jobId).update({
      'depositCollected': true,
      'depositCollectedAt': Timestamp.fromDate(now),
      'depositCollectedBy': byUid,
      'depositAmount': depositAmount,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Record that the final balance has been collected and flip the
  /// job to the terminal `completePaid` state. Filters the job out of
  /// active queues; only historical lists will surface it.
  Future<void> markFinalPaymentCollected({
    required String jobId,
    required String byUid,
  }) async {
    final now = DateTime.now();
    await _jobs().doc(jobId).update({
      'finalPaymentCollected': true,
      'finalPaymentCollectedAt': Timestamp.fromDate(now),
      'finalPaymentCollectedBy': byUid,
      'status': SalesJobStatus.completePaid.name,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Queue a payment-due reminder to be dispatched server-side.
  ///
  /// Writes to /email_notifications (the same Cloud-Function-driven
  /// queue [DemoLeadService] uses for new-lead emails) with type
  /// 'payment_reminder'. The Cloud Function consumes the doc, sends
  /// FCM/SMS/email through whatever channel is configured for the
  /// customer, and flips `processed: true`. Until the Cloud Function
  /// handler is in place, the doc just accumulates as a queue.
  Future<void> queuePaymentReminder({
    required String jobId,
    String? customerUid,
    required String customerName,
    required String customerEmail,
    required String customerPhone,
    required double amount,
  }) async {
    await _db.collection('email_notifications').add({
      'type': 'payment_reminder',
      'jobId': jobId,
      if (customerUid != null) 'customerUid': customerUid,
      'customerName': customerName,
      'customerEmail': customerEmail,
      'customerPhone': customerPhone,
      'amount': amount,
      'title': 'Your installation is complete!',
      'body': 'Thank you for choosing Nex-Gen LED. '
          'Your final balance of \$${amount.toStringAsFixed(2)} is now due. '
          'Please contact your installer to arrange payment.',
      'createdAt': FieldValue.serverTimestamp(),
      'processed': false,
    });
  }

  /// Atomically mark Day 1 (electrician pre-wire) as complete.
  ///
  /// Writes `status: prewireComplete`, `day1CompletedAt: now`,
  /// `day1TechUid`, and `updatedAt` in a single Firestore update so the
  /// job moves into the Day 2 queue atomically.
  ///
  /// Note on [techUid]: installers authenticate via 4-digit PIN, not
  /// Firebase Auth, so the value passed here is currently
  /// `InstallerInfo.fullPin`. The field name preserves Firebase-UID
  /// terminology in case installer auth migrates to Firebase Auth later.
  Future<void> markDay1Complete(String jobId, String techUid) async {
    final now = DateTime.now();
    await _jobs().doc(jobId).update({
      'status': SalesJobStatus.prewireComplete.name,
      'day1CompletedAt': Timestamp.fromDate(now),
      // TODO: replace with Firebase Auth UID when installer auth migrates
      'day1TechUid': techUid,
      'updatedAt': Timestamp.fromDate(now),
    });
  }

  /// Link a completed install to a created user account.
  ///
  /// Sets `linkedUserId`, flips the job's status to
  /// [SalesJobStatus.installComplete], and bumps `updatedAt`. Use this
  /// when the customer account is created **after** the install is
  /// already finished — for the typical wrap-up flow where account
  /// creation happens before the final close-job step, use
  /// [setLinkedUserId] instead so the status stays where it is.
  Future<void> linkToInstall(String jobId, String newUserUid) async {
    await _jobs().doc(jobId).update({
      'linkedUserId': newUserUid,
      'status': SalesJobStatus.installComplete.name,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Set [SalesJob.linkedUserId] without touching status. Used by the
  /// Day 2 wrap-up flow when the customer account is created at Step 3
  /// but the final `installComplete` transition happens at Step 4 via
  /// [markDay2Complete].
  Future<void> setLinkedUserId(String jobId, String newUserUid) async {
    await _jobs().doc(jobId).update({
      'linkedUserId': newUserUid,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Persist a freshly-generated [EstimateBreakdown] onto the job
  /// document. Also bumps `updatedAt` and copies `subtotalRetail` into
  /// `totalPriceUsd` so the existing job-list cards (which read
  /// `totalPriceUsd`) display the new total without further changes.
  Future<void> saveEstimateBreakdown(
    String jobId,
    EstimateBreakdown breakdown,
  ) async {
    await _jobs().doc(jobId).update({
      'estimateBreakdown': breakdown.toJson(),
      'totalPriceUsd': breakdown.subtotalRetail,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
  }
}

// ── Provider ─────────────────────────────────────────────────────────────────

final salesJobServiceProvider = Provider<SalesJobService>(
  (ref) => SalesJobService(FirebaseFirestore.instance),
);
