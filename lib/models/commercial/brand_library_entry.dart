import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/brand_signature.dart';

/// Read-only Flutter model for a single document in the global
/// /brand_library collection. Documents are seeded by
/// scripts/seed_brand_library.js and refined by approved
/// /brand_library_corrections.
///
/// Schema is enforced by the seed script's snake_case shape (see
/// scripts/seed_brand_library.js).
class BrandLibraryEntry {
  /// Stable URL-safe identifier (also the Firestore doc id).
  /// e.g. "state-farm", "mcdonalds", "home-depot".
  final String brandId;

  /// Canonical company name, used for display.
  final String companyName;

  /// Lowercased terms for arrayContains queries from the brand-search UI.
  /// e.g. ["state farm", "statefarm", "state", "farm"].
  final List<String> searchTerms;

  /// Lowercase, no spaces. One of: 'restaurant', 'insurance', 'bank',
  /// 'retail', 'realestate', 'fitness', 'hotel', 'healthcare', 'salon',
  /// 'auto'. Drives signature defaults on the seed side.
  final String industry;

  /// Brand colors using the canonical [BrandColor] model. Always at least
  /// one entry; first entry has role_tag 'primary'.
  final List<BrandColor> colors;

  /// Lighting signature derived from industry + dominant color warmth.
  final BrandSignature signature;

  /// Origin of trust for this entry. One of:
  ///   - 'nex-gen-manual'        — corporate-curated, hex codes verified
  ///   - 'brandfetch-claimed'    — Brandfetch profile with claimed: true
  /// Other values may appear in the future for additional sources.
  final String verifiedBy;

  /// When the entry was last seeded or refreshed by corporate. May be null
  /// during the brief window before the server timestamp resolves.
  final DateTime? lastVerified;

  /// Number of installer-submitted corrections that have been approved
  /// against this entry.
  final int correctionCount;

  /// Lifecycle marker. Currently always 'verified' — reserved for future
  /// states like 'deprecated' if a brand is retired.
  final String status;

  const BrandLibraryEntry({
    required this.brandId,
    required this.companyName,
    required this.searchTerms,
    required this.industry,
    required this.colors,
    required this.signature,
    required this.verifiedBy,
    this.lastVerified,
    this.correctionCount = 0,
    this.status = 'verified',
  });

  factory BrandLibraryEntry.fromJson(Map<String, dynamic> json) {
    return BrandLibraryEntry(
      brandId: (json['brand_id'] as String?) ?? '',
      companyName: (json['company_name'] as String?) ?? '',
      searchTerms: (json['search_terms'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      industry: (json['industry'] as String?) ?? '',
      colors: (json['colors'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => BrandColor.fromJson(e))
              .toList() ??
          const [],
      signature: json['signature'] is Map<String, dynamic>
          ? BrandSignature.fromJson(json['signature'] as Map<String, dynamic>)
          : const BrandSignature(),
      verifiedBy: (json['verified_by'] as String?) ?? 'unknown',
      lastVerified: (json['last_verified'] as Timestamp?)?.toDate(),
      correctionCount: (json['correction_count'] as num?)?.toInt() ?? 0,
      status: (json['status'] as String?) ?? 'verified',
    );
  }

  /// Constructs an entry from a Firestore [DocumentSnapshot]. Falls back
  /// to the document id for `brand_id` if the field isn't present in the
  /// data (legacy seed docs may not have it; doc id is canonical).
  factory BrandLibraryEntry.fromFirestore(DocumentSnapshot<Object?> doc) {
    final raw = doc.data();
    final data = raw is Map<String, dynamic>
        ? Map<String, dynamic>.from(raw)
        : <String, dynamic>{};
    if (data['brand_id'] == null || (data['brand_id'] as String).isEmpty) {
      data['brand_id'] = doc.id;
    }
    return BrandLibraryEntry.fromJson(data);
  }

  Map<String, dynamic> toJson() => {
        'brand_id': brandId,
        'company_name': companyName,
        'search_terms': searchTerms,
        'industry': industry,
        'colors': colors.map((e) => e.toJson()).toList(),
        'signature': signature.toJson(),
        'verified_by': verifiedBy,
        if (lastVerified != null) 'last_verified': Timestamp.fromDate(lastVerified!),
        'correction_count': correctionCount,
        'status': status,
      };

  /// Convenience accessor for the primary brand color (role_tag 'primary')
  /// or the first color if none is explicitly tagged.
  BrandColor? get primaryColor {
    for (final c in colors) {
      if (c.roleTag.toLowerCase() == 'primary') return c;
    }
    return colors.isNotEmpty ? colors.first : null;
  }
}
