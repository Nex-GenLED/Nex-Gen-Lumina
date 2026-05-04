import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/models/commercial/brand_correction.dart';
import 'package:nexgen_command/models/commercial/brand_library_entry.dart';
import 'package:nexgen_command/models/commercial/commercial_brand_profile.dart';

/// Riverpod providers for the Commercial Brand Profile feature. Reads
/// from the global /brand_library + /brand_library_corrections
/// collections and the per-user /users/{uid}/brand_profile/brand
/// document. All schemas are snake_case to match the project convention
/// and the seed script in scripts/seed_brand_library.js.

// ─── Brand library search ──────────────────────────────────────────────────

/// Streams brand-library entries matching a search query, used by the
/// "Find Brand" search added to BrandIdentityScreen in Part 4.
///
/// Uses an `arrayContains` query against the seeded `search_terms` field,
/// which holds lowercase variants of the company name (full string,
/// no-spaces, and per-word splits ≥ 3 chars). The query is the lowercased
/// trimmed user input — exact match against any one term is enough to
/// surface the brand.
///
/// Returns up to 10 results to keep the dropdown legible. Empty query
/// short-circuits to an empty list so the UI can render a "no query yet"
/// state without hitting Firestore.
final brandSearchProvider =
    StreamProvider.family<List<BrandLibraryEntry>, String>((ref, query) {
  final lower = query.toLowerCase().trim();
  if (lower.isEmpty) return Stream.value(const []);

  return FirebaseFirestore.instance
      .collection('brand_library')
      .where('search_terms', arrayContains: lower)
      .limit(10)
      .snapshots()
      .map((snap) =>
          snap.docs.map(BrandLibraryEntry.fromFirestore).toList(growable: false));
});

/// Single library entry by id, for the Brand tab on the commercial home
/// screen and for resolving a [CommercialBrandProfile.brandLibraryId]
/// back to the source-of-truth library doc.
final brandLibraryEntryProvider =
    StreamProvider.family<BrandLibraryEntry?, String>((ref, brandId) {
  if (brandId.trim().isEmpty) return Stream.value(null);
  return FirebaseFirestore.instance
      .collection('brand_library')
      .doc(brandId)
      .snapshots()
      .map((doc) => doc.exists ? BrandLibraryEntry.fromFirestore(doc) : null);
});

// ─── Per-user brand profile ────────────────────────────────────────────────

/// The current user's [CommercialBrandProfile], persisted at
/// /users/{uid}/brand_profile/brand.
///
/// Returns `null` while unauthenticated or before the profile is created
/// (residential users, or commercial users who haven't completed brand
/// setup yet). Watches the doc so saves from BrandSetupScreen reflect
/// immediately on the Brand tab.
final commercialBrandProfileProvider =
    StreamProvider<CommercialBrandProfile?>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(null);

  return FirebaseFirestore.instance
      .collection('users')
      .doc(user.uid)
      .collection('brand_profile')
      .doc('brand')
      .snapshots()
      .map((doc) =>
          doc.exists ? CommercialBrandProfile.fromFirestore(doc) : null);
});

// ─── Corporate moderation ──────────────────────────────────────────────────

/// Pending brand-library corrections, ordered newest-first. Read by the
/// Brand Correction Review screen (Part 4, admin-only). The collection
/// rule allows the submitter and corporate user_role admins to read
/// individual docs; this collection-wide listener will surface only the
/// admin's docs unless the rule is widened — kept this way so non-admins
/// can't enumerate other installers' submissions.
final pendingBrandCorrectionsProvider =
    StreamProvider<List<BrandCorrection>>((ref) {
  return FirebaseFirestore.instance
      .collection('brand_library_corrections')
      .where('status', isEqualTo: 'pending')
      .orderBy('submitted_at', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map(BrandCorrection.fromFirestore).toList(growable: false));
});

/// Streams the current user's own correction submissions (any status)
/// so installers can see what they've submitted and whether corporate
/// has reviewed it.
final myBrandCorrectionsProvider =
    StreamProvider<List<BrandCorrection>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);

  return FirebaseFirestore.instance
      .collection('brand_library_corrections')
      .where('submitted_by', isEqualTo: user.uid)
      .orderBy('submitted_at', descending: true)
      .snapshots()
      .map((snap) =>
          snap.docs.map(BrandCorrection.fromFirestore).toList(growable: false));
});

// ─── Transient selection state ─────────────────────────────────────────────

/// The brand-library entry the user has tentatively picked during the
/// "Find Brand" flow in BrandIdentityScreen. Null when the user is
/// entering a brand manually with no library match.
///
/// Reset to null when the wizard completes or the user clears the
/// selection — this is purely transient UI state, not persisted.
final selectedBrandProvider = StateProvider<BrandLibraryEntry?>((ref) => null);
