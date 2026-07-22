import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/models/commercial/commercial_location.dart';
import 'package:nexgen_command/models/commercial/commercial_organization.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';

// =============================================================================
// Commercial Mode Detection
// =============================================================================

const String _commercialModeOverrideKey = 'commercial_mode_override';

/// Whether the user has commercial mode enabled in their profile AND has at
/// least one commercial location. Checked on app launch to decide routing.
final commercialModeEnabledProvider = FutureProvider<bool>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;

  // Check local override first (mode switcher)
  final prefs = await SharedPreferences.getInstance();
  final override = prefs.getBool(_commercialModeOverrideKey);
  if (override != null) return override;

  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) return false;

    final data = userDoc.data()!;

    // Firestore-side override (synced from setCommercialModeOverride on
    // another device). Honoured even when profile_type hasn't been set yet.
    final remoteOverride = data['commercial_mode_override'];
    if (remoteOverride is bool) return remoteOverride;

    final profileType = data['profile_type'] as String?;
    if (profileType != 'commercial') return false;

    // Verify at least one commercial location exists
    final locSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('commercial_locations')
        .limit(1)
        .get();

    return locSnap.docs.isNotEmpty;
  } catch (_) {
    return false;
  }
});

/// Whether the user has a commercial profile (even if currently in residential
/// mode). Used to show the "Switch to Commercial Mode" option.
final hasCommercialProfileProvider = FutureProvider<bool>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) return false;
    final data = userDoc.data()!;
    return data['commercial_profile'] != null ||
        data['profile_type'] == 'commercial';
  } catch (_) {
    return false;
  }
});

/// Whether the current commercial user manages multiple locations.
final isMultiLocationProvider = FutureProvider<bool>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return false;
  try {
    final locSnap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('commercial_locations')
        .get();
    return locSnap.docs.length > 1;
  } catch (_) {
    return false;
  }
});

/// The user's commercial role (highest across all locations).
final commercialUserRoleProvider = FutureProvider<CommercialRole?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) return null;
    final data = userDoc.data()!;
    final level = data['commercial_permission_level'] as String?;
    if (level == 'corporate_admin') return CommercialRole.corporateAdmin;
    if (level == 'store_manager') return CommercialRole.storeManager;

    // Check org ownership
    final orgId = data['organization_id'] as String?;
    if (orgId != null) {
      final orgDoc = await FirebaseFirestore.instance
          .collection('commercial_organizations')
          .doc(orgId)
          .get();
      if (orgDoc.exists && orgDoc.data()?['owner_id'] == uid) {
        return CommercialRole.corporateAdmin;
      }
    }

    return CommercialRole.storeStaff;
  } catch (_) {
    return null;
  }
});

/// The user's organization (null for single-location users without an org).
final commercialOrgProvider =
    FutureProvider<CommercialOrganization?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final userDoc = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .get();
    if (!userDoc.exists) return null;
    final orgId = userDoc.data()?['organization_id'] as String?;
    if (orgId == null) return null;

    final orgDoc = await FirebaseFirestore.instance
        .collection('commercial_organizations')
        .doc(orgId)
        .get();
    if (!orgDoc.exists) return null;
    return CommercialOrganization.fromJson(orgDoc.data()!);
  } catch (_) {
    return null;
  }
});

/// First commercial location for single-location users.
final primaryCommercialLocationProvider =
    FutureProvider<CommercialLocation?>((ref) async {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return null;
  try {
    final snap = await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('commercial_locations')
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return CommercialLocation.fromJson(snap.docs.first.data());
  } catch (_) {
    return null;
  }
});

// =============================================================================
// Mode Switching
// =============================================================================

/// Switch between commercial and residential mode. Persists locally AND to
/// Firestore so the choice follows the user across devices/sessions.
///
/// Local prefs are written first so the next launch reads the new mode even
/// if the Firestore write fails (offline, transient permission issue). The
/// Firestore mirror is best-effort — failures are logged but not surfaced.
Future<void> setCommercialModeOverride(bool commercial) async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_commercialModeOverrideKey, commercial);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'commercial_mode_override': commercial,
    }, SetOptions(merge: true));
  } catch (_) {
    // Local write already succeeded — silently tolerate Firestore failure.
  }
}

/// Clear the local mode override so the app uses the Firestore profile value.
/// Also clears the Firestore mirror so the residential default applies on
/// other devices.
Future<void> clearModeOverride() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_commercialModeOverrideKey);

  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return;
  try {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'commercial_mode_override': FieldValue.delete(),
    }, SetOptions(merge: true));
  } catch (_) {
    // Local clear already succeeded — silently tolerate Firestore failure.
  }
}
