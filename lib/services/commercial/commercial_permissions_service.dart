// ---------------------------------------------------------------------------
// REQUIRED FIRESTORE SECURITY RULES
// ---------------------------------------------------------------------------
//
// The rules below enforce role-based access for the commercial collections.
// Apply these in the Firebase Console under Firestore → Rules.
//
// match /organizations/{orgId} {
//   // Only the org owner or a corporateAdmin can read/write the org document.
//   allow read: if request.auth != null
//     && (resource.data.owner_id == request.auth.uid
//         || isOrgAdmin(request.auth.uid, orgId));
//   allow write: if request.auth != null
//     && (resource.data.owner_id == request.auth.uid
//         || isOrgAdmin(request.auth.uid, orgId));
//
//   match /locations/{locationId} {
//     // Any assigned manager (any role) can read their own location.
//     allow read: if request.auth != null
//       && (isAssignedToLocation(request.auth.uid, locationId)
//           || isOrgAdmin(request.auth.uid, orgId)
//           || isRegionalManager(request.auth.uid, orgId));
//
//     // Only storeManager+ can write to their location.
//     allow write: if request.auth != null
//       && (hasLocationRole(request.auth.uid, locationId, ['storeManager', 'regionalManager', 'corporateAdmin'])
//           || isOrgAdmin(request.auth.uid, orgId));
//
//     match /channelConfigs/{channelId} {
//       allow read, write: if request.auth != null
//         && hasLocationRole(request.auth.uid, locationId, ['storeManager', 'regionalManager', 'corporateAdmin']);
//     }
//
//     match /schedule {
//       // Locked schedules can only be written by corporateAdmin.
//       allow read: if request.auth != null
//         && isAssignedToLocation(request.auth.uid, locationId);
//       allow write: if request.auth != null
//         && (!resource.data.is_locked_by_corporate
//             || isOrgAdmin(request.auth.uid, orgId));
//     }
//
//     match /teamsConfig {
//       allow read, write: if request.auth != null
//         && hasLocationRole(request.auth.uid, locationId, ['storeManager', 'regionalManager', 'corporateAdmin']);
//     }
//
//     match /businessHours {
//       allow read: if request.auth != null
//         && isAssignedToLocation(request.auth.uid, locationId);
//       allow write: if request.auth != null
//         && hasLocationRole(request.auth.uid, locationId, ['storeManager', 'regionalManager', 'corporateAdmin']);
//     }
//   }
//
//   match /brandProfile {
//     allow read: if request.auth != null
//       && isAssignedToOrg(request.auth.uid, orgId);
//     allow write: if request.auth != null
//       && isOrgAdmin(request.auth.uid, orgId);
//   }
// }
//
// match /campaigns/{campaignId} {
//   allow read: if request.auth != null;
//   allow write: if request.auth != null
//     && isOrgAdmin(request.auth.uid, resource.data.org_id);
// }
//
// // Helper functions (implement as Firestore rules helper functions):
// // - isOrgAdmin(uid, orgId): checks if uid has corporateAdmin role in any
// //   location under orgId, or is the org owner.
// // - isRegionalManager(uid, orgId): checks if uid has regionalManager role.
// // - isAssignedToLocation(uid, locationId): checks if uid appears in
// //   the location's managers array.
// // - hasLocationRole(uid, locationId, roles): checks if uid has one of the
// //   specified roles at the location.
// // - isAssignedToOrg(uid, orgId): checks if uid appears in any location
// //   under the org.
// ---------------------------------------------------------------------------

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/models/commercial/commercial_location.dart';
import 'package:nexgen_command/models/commercial/commercial_role.dart';

/// Service that resolves the current user's commercial role and evaluates
/// permissions against the [CommercialRole] permission map.
///
/// Integrates with Firebase Auth for user identity and Firestore for
/// location manager assignments.
class CommercialPermissionsService {
  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  CommercialPermissionsService({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db = db ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  /// The currently authenticated user's UID, or `null`.
  String? get _currentUid => _auth.currentUser?.uid;

  /// Returns the [CommercialRole] the current user holds at [locationId].
  ///
  /// Falls back to [CommercialRole.storeStaff] if no assignment is found.
  /// Returns `null` if no user is signed in.
  Future<CommercialRole?> getCurrentUserRole(String locationId) async {
    final uid = _currentUid;
    if (uid == null) return null;

    try {
      final location = await _fetchLocation(locationId);
      if (location == null) return null;

      // Check if user is the org owner (implicit corporateAdmin).
      final orgSnap = await _db
          .collection('organizations')
          .doc(location.orgId)
          .get();
      if (orgSnap.exists) {
        final ownerId = orgSnap.data()?['owner_id'] as String?;
        if (ownerId == uid) return CommercialRole.corporateAdmin;
      }

      return location.roleForUser(uid) ?? CommercialRole.storeStaff;
    } catch (e) {
      debugPrint('CommercialPermissionsService: getCurrentUserRole error: $e');
      return null;
    }
  }

  /// Whether [role] has the named [permission].
  bool hasPermission(CommercialRole role, String permission) {
    return role.hasPermission(permission);
  }

  /// Whether the current user can edit the schedule / channels at [locationId].
  Future<bool> canEditLocation(String locationId) async {
    final role = await getCurrentUserRole(locationId);
    if (role == null) return false;
    return role.hasPermission('canEditOwnSchedule');
  }

  /// Whether the current user can push schedules to all locations.
  Future<bool> canPushToAll() async {
    final uid = _currentUid;
    if (uid == null) return false;

    try {
      // Check all orgs where this user is the owner.
      final orgs = await _db
          .collection('organizations')
          .where('owner_id', isEqualTo: uid)
          .get();
      if (orgs.docs.isNotEmpty) return true;

      // Otherwise, need corporateAdmin role at any location.
      // This is a broad check — in production, scope to the org in context.
      return false;
    } catch (e) {
      debugPrint('CommercialPermissionsService: canPushToAll error: $e');
      return false;
    }
  }

  /// Whether the current user can unlock a corporate-locked schedule at
  /// [locationId].
  Future<bool> canUnlock(String locationId) async {
    final role = await getCurrentUserRole(locationId);
    if (role == null) return false;
    return role.hasPermission('canApplyCorporateLock');
  }

  // ── Helpers ────────────────────────────────────────────────────────────

  Future<CommercialLocation?> _fetchLocation(String locationId) async {
    try {
      // Locations are nested: /organizations/{orgId}/locations/{locationId}.
      // Since we don't know the orgId, do a collection-group query.
      final snap = await _db
          .collectionGroup('locations')
          .where('location_id', isEqualTo: locationId)
          .limit(1)
          .get();
      if (snap.docs.isEmpty) return null;
      return CommercialLocation.fromJson(snap.docs.first.data());
    } catch (e) {
      debugPrint('CommercialPermissionsService: _fetchLocation error: $e');
      return null;
    }
  }
}
