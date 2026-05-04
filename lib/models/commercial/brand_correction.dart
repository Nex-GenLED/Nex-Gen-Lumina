import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';

/// One installer- or customer-submitted color correction against a
/// /brand_library entry, persisted at /brand_library_corrections/{id}.
///
/// Lifecycle:
///   1. Submitted (status: 'pending') by anyone authenticated. The
///      Firestore rule pins `submitted_by` to the writer's uid.
///   2. Reviewed by a corporate user_role admin. Update transitions
///      status to 'approved' (and sets applied_to_library: true once the
///      brand_library entry has been updated) or 'rejected'.
///   3. Never deleted — corrections are an audit trail.
class BrandCorrection {
  /// Doc id, populated when reading from Firestore. Empty when the
  /// model is freshly constructed for a write.
  final String correctionId;

  /// Pointer to the affected /brand_library entry.
  final String brandId;

  /// Snapshot of the brand's display name at submission time. Stored
  /// rather than looked up so the moderation UI works even if the
  /// /brand_library entry is later renamed.
  final String companyName;

  /// Uid of the submitter. Pinned to request.auth.uid by the create rule.
  final String submittedBy;

  /// Dealer code of the submitter when the submission came from an
  /// installer flow. Empty string for non-installer submissions.
  final String dealerCode;

  /// The colors on the /brand_library entry at submission time.
  /// Captured to make the moderation diff stable even if the entry is
  /// updated by another correction in flight.
  final List<BrandColor> originalColors;

  /// The colors the submitter is proposing.
  final List<BrandColor> proposedColors;

  /// Free-form rationale ("Official brand guide shows different red
  /// shade", "Recent rebrand swapped primary/secondary", etc.).
  final String reason;

  /// When the submitter wrote the doc.
  final DateTime submittedAt;

  /// One of: 'pending', 'approved', 'rejected'. Defaults to 'pending'
  /// on a fresh submission.
  final String status;

  /// Uid of the corporate admin who reviewed. Null while pending.
  final String? reviewedBy;

  /// When the corporate admin reviewed. Null while pending.
  final DateTime? reviewedAt;

  /// True once the approved correction has been propagated into the
  /// /brand_library entry (the moderation UI sets this in the same
  /// update that transitions status to 'approved').
  final bool appliedToLibrary;

  const BrandCorrection({
    this.correctionId = '',
    required this.brandId,
    required this.companyName,
    required this.submittedBy,
    this.dealerCode = '',
    required this.originalColors,
    required this.proposedColors,
    required this.reason,
    required this.submittedAt,
    this.status = 'pending',
    this.reviewedBy,
    this.reviewedAt,
    this.appliedToLibrary = false,
  });

  factory BrandCorrection.fromJson(Map<String, dynamic> json) {
    return BrandCorrection(
      correctionId: (json['correction_id'] as String?) ?? '',
      brandId: (json['brand_id'] as String?) ?? '',
      companyName: (json['company_name'] as String?) ?? '',
      submittedBy: (json['submitted_by'] as String?) ?? '',
      dealerCode: (json['dealer_code'] as String?) ?? '',
      originalColors: (json['original_colors'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => BrandColor.fromJson(e))
              .toList() ??
          const [],
      proposedColors: (json['proposed_colors'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => BrandColor.fromJson(e))
              .toList() ??
          const [],
      reason: (json['reason'] as String?) ?? '',
      submittedAt:
          (json['submitted_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      status: (json['status'] as String?) ?? 'pending',
      reviewedBy: json['reviewed_by'] as String?,
      reviewedAt: (json['reviewed_at'] as Timestamp?)?.toDate(),
      appliedToLibrary: (json['applied_to_library'] as bool?) ?? false,
    );
  }

  factory BrandCorrection.fromFirestore(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic>
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    data['correction_id'] = doc.id;
    return BrandCorrection.fromJson(data);
  }

  /// Serializes to the snake_case shape the firestore rules check
  /// against. Note that `correction_id` is omitted on write — the doc
  /// id carries it.
  Map<String, dynamic> toJson() => {
        'brand_id': brandId,
        'company_name': companyName,
        'submitted_by': submittedBy,
        'dealer_code': dealerCode,
        'original_colors': originalColors.map((e) => e.toJson()).toList(),
        'proposed_colors': proposedColors.map((e) => e.toJson()).toList(),
        'reason': reason,
        'submitted_at': Timestamp.fromDate(submittedAt),
        'status': status,
        if (reviewedBy != null) 'reviewed_by': reviewedBy,
        if (reviewedAt != null) 'reviewed_at': Timestamp.fromDate(reviewedAt!),
        'applied_to_library': appliedToLibrary,
      };

  BrandCorrection copyWith({
    String? correctionId,
    String? brandId,
    String? companyName,
    String? submittedBy,
    String? dealerCode,
    List<BrandColor>? originalColors,
    List<BrandColor>? proposedColors,
    String? reason,
    DateTime? submittedAt,
    String? status,
    String? reviewedBy,
    DateTime? reviewedAt,
    bool? appliedToLibrary,
  }) {
    return BrandCorrection(
      correctionId: correctionId ?? this.correctionId,
      brandId: brandId ?? this.brandId,
      companyName: companyName ?? this.companyName,
      submittedBy: submittedBy ?? this.submittedBy,
      dealerCode: dealerCode ?? this.dealerCode,
      originalColors: originalColors ?? this.originalColors,
      proposedColors: proposedColors ?? this.proposedColors,
      reason: reason ?? this.reason,
      submittedAt: submittedAt ?? this.submittedAt,
      status: status ?? this.status,
      reviewedBy: reviewedBy ?? this.reviewedBy,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      appliedToLibrary: appliedToLibrary ?? this.appliedToLibrary,
    );
  }

  bool get isPending => status == 'pending';
  bool get isApproved => status == 'approved';
  bool get isRejected => status == 'rejected';
}
