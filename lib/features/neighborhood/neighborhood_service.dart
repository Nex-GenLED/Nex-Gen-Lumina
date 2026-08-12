import 'dart:convert';
import 'dart:math' show Random, cos, sin, sqrt, atan2, pi;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:shared_preferences/shared_preferences.dart';

import 'neighborhood_models.dart';
import 'package:nexgen_command/services/user_service.dart';

/// Outcome of a server-side ad-hoc fanout POST (Slice 1 Commit 2).
///
/// [rateLimited] is the ONLY state that suppresses the app-open broadcast
/// (reject = nothing fires). A plain failure ([ok] false, not rate-limited —
/// network/500/no-auth) lets the broadcast proceed so app-open members aren't
/// left dark.
class FanoutResult {
  final bool ok;
  final bool rateLimited;
  final int retryAfterMs;

  const FanoutResult({
    this.ok = false,
    this.rateLimited = false,
    this.retryAfterMs = 0,
  });

  const FanoutResult.failed()
      : ok = false,
        rateLimited = false,
        retryAfterMs = 0;

  /// PURE parser over the HTTP status + body from applySyncPattern. Exposed
  /// for testing. 200 + {ok:true} → ok; 200 + {reason:'rate_limited',
  /// retryAfterMs} → rateLimited; anything else → a plain (non-rate-limited)
  /// failure so the caller still broadcasts.
  factory FanoutResult.parse(int statusCode, String body) {
    if (statusCode != 200) return const FanoutResult(ok: false);
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        if (decoded['ok'] == true) return const FanoutResult(ok: true);
        if (decoded['reason'] == 'rate_limited') {
          final ra = decoded['retryAfterMs'];
          return FanoutResult(
            ok: false,
            rateLimited: true,
            retryAfterMs: ra is num ? ra.toInt() : 0,
          );
        }
      }
    } catch (_) {
      // Malformed body → treat as a plain failure (broadcast proceeds).
    }
    return const FanoutResult(ok: false);
  }
}

/// Service for managing neighborhood sync groups in Firestore.
class NeighborhoodService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  NeighborhoodService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _neighborhoodsRef =>
      _firestore.collection('neighborhoods');

  /// F-3 public projection — the ONLY cross-tenant-readable view of a crew.
  /// See [publishPublicProjection] for the shape and why it is narrow.
  CollectionReference<Map<String, dynamic>> get _publicProjectionRef =>
      _firestore.collection('neighborhood_public');

  String? get _currentUid => _auth.currentUser?.uid;

  /// Cloud Functions base URL (matches sync_event_background_worker.dart).
  static const String _functionsBaseUrl =
      'https://us-central1-icrt6menwsv2d8all8oijs021b06s5.cloudfunctions.net';

  /// Read the current user's own controller doc ids from
  /// users/{uid}/controllers, for denormalizing onto the member doc
  /// (NeighborhoodMember.controllerId, Slice 1). Best-effort: returns an
  /// empty list on any failure — the server fanout then falls back to a live
  /// controllers read, so an empty list never breaks delivery.
  Future<List<String>> _ownControllerIds() async {
    final uid = _currentUid;
    if (uid == null) return const [];
    try {
      final snap = await _firestore
          .collection('users')
          .doc(uid)
          .collection('controllers')
          .get();
      return snap.docs.map((d) => d.id).toList();
    } catch (e) {
      debugPrint('NeighborhoodService: _ownControllerIds failed: $e');
      return const [];
    }
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Group Management
  // ─────────────────────────────────────────────────────────────────────────────

  /// Creates a new neighborhood group and adds the creator as the first member.
  Future<NeighborhoodGroup> createGroup(
    String name, {
    String? displayName,
    String? description,
    String? streetName,
    String? city,
    bool isPublic = false,
    double? latitude,
    double? longitude,
  }) async {
    debugPrint('🏘️ [NeighborhoodService] createGroup START');
    final uid = _currentUid;
    debugPrint('🏘️ [NeighborhoodService] uid=$uid');
    if (uid == null) {
      debugPrint('🏘️ [NeighborhoodService] ABORT: not authenticated');
      throw Exception('User not authenticated');
    }

    final inviteCode = _generateInviteCode();
    final now = DateTime.now();

    final docRef = _neighborhoodsRef.doc();
    debugPrint('🏘️ [NeighborhoodService] Writing to: neighborhoods/${docRef.id}');
    debugPrint('🏘️ [NeighborhoodService] inviteCode=$inviteCode');

    final group = NeighborhoodGroup(
      id: docRef.id,
      name: name,
      description: description,
      streetName: streetName,
      city: city,
      isPublic: isPublic,
      inviteCode: inviteCode,
      creatorUid: uid,
      createdAt: now,
      memberUids: [uid],
      isActive: false,
      latitude: latitude,
      longitude: longitude,
    );

    final groupPayload = UserService.sanitizeForFirestore(group.toFirestore());
    debugPrint('🏘️ [NeighborhoodService] Group doc payload keys: ${groupPayload.keys.toList()}');
    debugPrint('🏘️ [NeighborhoodService] creatorUid in payload: ${groupPayload['creatorUid']}');
    debugPrint('🏘️ [NeighborhoodService] memberUids in payload: ${groupPayload['memberUids']}');

    try {
      await docRef.set(groupPayload);
      debugPrint('🏘️ [NeighborhoodService] Group doc write SUCCESS');
    } catch (e, st) {
      debugPrint('🏘️ [NeighborhoodService] Group doc write FAILED: $e');
      debugPrint('🏘️ [NeighborhoodService] Stack: $st');
      rethrow;
    }

    // Add creator as first member. Denormalize the creator's own controller
    // ids onto the member doc (Slice 1) so the server fanout can resolve
    // targets without a per-member cross-collection read.
    final member = NeighborhoodMember(
      oderId: uid,
      displayName: displayName ?? 'My Home',
      positionIndex: 0,
      lastSeen: now,
      isOnline: true,
      controllerId: await _ownControllerIds(),
    );
    try {
      await docRef.collection('members').doc(uid).set(UserService.sanitizeForFirestore(member.toFirestore()));
      debugPrint('🏘️ [NeighborhoodService] Member doc write SUCCESS');
    } catch (e, st) {
      debugPrint('🏘️ [NeighborhoodService] Member doc write FAILED: $e');
      debugPrint('🏘️ [NeighborhoodService] Stack: $st');
      // Roll back the group doc so we don't leave a half-created group
      try {
        await docRef.delete();
        debugPrint('🏘️ [NeighborhoodService] Rolled back group doc');
      } catch (_) {}
      rethrow;
    }

    // F-3: a crew created as public needs its discovery projection, or it is
    // flagged public and listed nowhere. Best-effort — a projection failure
    // must not roll back a successfully created group.
    if (group.isPublic) {
      try {
        await publishPublicProjection(group);
      } catch (e) {
        debugPrint('🏘️ [NeighborhoodService] projection publish failed: $e');
      }
    }

    debugPrint('🏘️ Created neighborhood group: ${group.name} (${group.inviteCode})');
    return group;
  }

  /// Joins an existing group using an invite code.
  Future<NeighborhoodGroup?> joinGroup(String inviteCode, {String? displayName}) =>
      _callJoin(inviteCode: inviteCode, displayName: displayName);

  /// Joins a PUBLIC crew discovered through [findNearbyGroups].
  ///
  /// Discovery results come from the `/neighborhood_public` projection, which
  /// deliberately carries no invite code — so a public join is identified by
  /// group id and authorized by the group's own `isPublic` flag, server-side.
  Future<NeighborhoodGroup?> joinPublicGroup(String groupId,
          {String? displayName}) =>
      _callJoin(groupId: groupId, displayName: displayName);

  /// F-3: joining is a SERVER operation now.
  ///
  /// This used to be a client transaction — query `/neighborhoods` by invite
  /// code, append our own uid to `memberUids`, write our own member doc. All
  /// three steps are denied to clients after F-3: the group read is
  /// membership-scoped, and self-insertion into `memberUids` is refused. The
  /// `joinNeighborhood` callable validates the code with the admin SDK and
  /// writes both docs in one batch.
  ///
  /// ⚠️ CONTRACT — the null-vs-throw distinction is load-bearing and predates
  /// this change (commit 002b0b7). The UI branches on it: a null WITHOUT an
  /// error means "that code matched nothing", and the rejoin shortcut drops its
  /// saved entry only in that case; any other failure must PRESERVE the error so
  /// a real outage is not mistaken for a bad code and silently discarded. So:
  ///   • callable `not-found`  → return null   (no such code / no such group)
  ///   • anything else         → rethrow       (auth, rate limit, full, network)
  Future<NeighborhoodGroup?> _callJoin({
    String? inviteCode,
    String? groupId,
    String? displayName,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    try {
      final callable = FirebaseFunctions.instanceFor(region: 'us-central1')
          .httpsCallable('joinNeighborhood');
      final result = await callable.call<Map<String, dynamic>>({
        if (inviteCode != null) 'inviteCode': inviteCode,
        if (groupId != null) 'groupId': groupId,
        if (displayName != null && displayName.trim().isNotEmpty)
          'displayName': displayName.trim(),
        // Denormalized so the server-side fanout (SYNC-1) can resolve this
        // member's controllers without a cross-collection read.
        'controllerId': await _ownControllerIds(),
      });

      final data = Map<String, dynamic>.from(result.data);
      final groupData = data['group'];
      if (groupData is! Map) {
        debugPrint('joinNeighborhood: malformed response, no group');
        return null;
      }
      final group = _groupFromCallable(Map<String, dynamic>.from(groupData));
      debugPrint('Joined neighborhood group: ${group.name} '
          '(alreadyMember=${data['alreadyMember'] == true})');
      return group;
    } on FirebaseFunctionsException catch (e) {
      // The ONLY code that means "nothing matched". Everything else is a real
      // failure and must reach the caller with its error intact.
      if (e.code == 'not-found') {
        debugPrint('No crew found for that invite code');
        return null;
      }
      debugPrint('joinNeighborhood failed: ${e.code} ${e.message}');
      rethrow;
    }
  }

  /// Rebuilds a [NeighborhoodGroup] from the callable's JSON. The callable
  /// returns `createdAtMs` rather than a Timestamp because callable responses
  /// are plain JSON.
  NeighborhoodGroup _groupFromCallable(Map<String, dynamic> g) {
    return NeighborhoodGroup(
      id: g['id'] as String? ?? '',
      name: g['name'] as String? ?? '',
      description: g['description'] as String?,
      streetName: g['streetName'] as String?,
      city: g['city'] as String?,
      isPublic: g['isPublic'] == true,
      inviteCode: g['inviteCode'] as String? ?? '',
      creatorUid: g['creatorUid'] as String? ?? '',
      createdAt: g['createdAtMs'] is int
          ? DateTime.fromMillisecondsSinceEpoch(g['createdAtMs'] as int)
          : DateTime.now(),
      memberUids: (g['memberUids'] as List?)?.whereType<String>().toList() ?? [],
      isActive: g['isActive'] == true,
      activePatternId: g['activePatternId'] as String?,
      activePatternName: g['activePatternName'] as String?,
      activeSyncType: SyncTypeExtension.fromJson(g['activeSyncType'] as String?),
      latitude: (g['latitude'] as num?)?.toDouble(),
      longitude: (g['longitude'] as num?)?.toDouble(),
    );
  }

  /// Leaves a neighborhood group.
  ///
  /// If a sync session is active, the user is gracefully disconnected
  /// (their lights hold their last state rather than turning off).
  /// If the leaving user is the host and no ownership transfer was done,
  /// the group is dissolved for all members.
  Future<void> leaveGroup(String groupId) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final group = NeighborhoodGroup.fromFirestore(doc);

    // If sync is active, mark this member offline so the engine
    // stops sending commands — lights hold their last state.
    if (group.isActive) {
      try {
        await docRef.collection('members').doc(uid).update({
          'isOnline': false,
          'participationStatus': MemberParticipationStatus.optedOut.name,
        });
      } catch (_) {
        // Member doc may already be gone — that's fine.
      }
    }

    // Remove from member list
    await docRef.update({
      'memberUids': FieldValue.arrayRemove([uid]),
    });

    // Remove member document
    await docRef.collection('members').doc(uid).delete();

    // If creator leaves and no other members, delete the group
    if (group.creatorUid == uid && group.memberUids.length <= 1) {
      await deleteGroup(groupId);
    }

    // Clear any handoff state for this user. Finding 5.1 from sync
    // audit — leaving a group mid-handoff would otherwise leave orphaned
    // state that causes silent resume failures.
    try {
      await _firestore
          .collection('users')
          .doc(uid)
          .collection('handoff')
          .doc('current')
          .delete();
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('sync_handoff_state');
    } catch (e) {
      debugPrint('Failed to clear handoff state on leave: $e');
      // Non-fatal — continue with leave-group completion.
    }

    debugPrint('Left neighborhood group: ${group.name}');
  }

  /// Dissolves a group entirely (host leaving without transferring ownership).
  ///
  /// Removes all members, commands, schedules, and the group document.
  /// Returns the list of member UIDs that were in the group (excluding the host)
  /// so the caller can send notifications.
  Future<List<String>> dissolveGroup(String groupId) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();
    if (!doc.exists) return [];

    final group = NeighborhoodGroup.fromFirestore(doc);
    final otherMembers = group.memberUids.where((id) => id != uid).toList();

    // Stop any active sync first
    if (group.isActive) {
      await stopSync(groupId);
    }

    // Delete all sub-collections
    final membersSnapshot = await docRef.collection('members').get();
    for (final memberDoc in membersSnapshot.docs) {
      await memberDoc.reference.delete();
    }

    final commandsSnapshot = await docRef.collection('commands').get();
    for (final commandDoc in commandsSnapshot.docs) {
      await commandDoc.reference.delete();
    }

    final schedulesSnapshot = await docRef.collection('schedules').get();
    for (final scheduleDoc in schedulesSnapshot.docs) {
      await scheduleDoc.reference.delete();
    }

    // Delete group document
    await docRef.delete();

    debugPrint('Dissolved neighborhood group: ${group.name}');
    return otherMembers;
  }

  /// Transfers group ownership to another member.
  Future<void> transferOwnership(String groupId, String newOwnerUid) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();
    if (!doc.exists) throw Exception('Group not found');

    final group = NeighborhoodGroup.fromFirestore(doc);
    if (group.creatorUid != uid) {
      throw Exception('Only the current host can transfer ownership');
    }

    if (!group.memberUids.contains(newOwnerUid)) {
      throw Exception('New owner must be a member of the group');
    }

    await docRef.update({'creatorUid': newOwnerUid});
    debugPrint('Transferred ownership of ${group.name} to $newOwnerUid');
  }

  /// Deletes a neighborhood group (creator only).
  Future<void> deleteGroup(String groupId) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final group = NeighborhoodGroup.fromFirestore(doc);

    // Only creator can delete
    if (group.creatorUid != uid) {
      throw Exception('Only the group creator can delete this group');
    }

    // Delete all members
    final membersSnapshot = await docRef.collection('members').get();
    for (final memberDoc in membersSnapshot.docs) {
      await memberDoc.reference.delete();
    }

    // Delete all commands
    final commandsSnapshot = await docRef.collection('commands').get();
    for (final commandDoc in commandsSnapshot.docs) {
      await commandDoc.reference.delete();
    }

    // Delete group
    await docRef.delete();

    debugPrint('Deleted neighborhood group: ${group.name}');
  }

  /// Regenerates the invite code for a group (creator only).
  Future<String> regenerateInviteCode(String groupId) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();

    if (!doc.exists) throw Exception('Group not found');

    final group = NeighborhoodGroup.fromFirestore(doc);
    if (group.creatorUid != uid) {
      throw Exception('Only the group creator can regenerate the invite code');
    }

    final newCode = _generateInviteCode();
    await docRef.update({'inviteCode': newCode});

    debugPrint('Regenerated invite code for ${group.name}: $newCode');
    return newCode;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Member Management
  // ─────────────────────────────────────────────────────────────────────────────

  /// Updates a member's configuration. When updating the CURRENT user's own
  /// member doc, refresh the denormalized controllerId[] from their controllers
  /// (Slice 1). For another member's doc (creator moderation), leave
  /// controllerId as-passed — a client can't read another user's controllers,
  /// and the server fanout falls back to a live read anyway.
  Future<void> updateMember(String groupId, NeighborhoodMember member) async {
    var toWrite = member;
    if (member.oderId == _currentUid) {
      toWrite = member.copyWith(controllerId: await _ownControllerIds());
    }
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(toWrite.oderId)
        .update(toWrite.toFirestore());
  }

  /// Slice 1 (flag-gated, default OFF): server-side ad-hoc fanout. POSTs the
  /// shared WLED [payload] to the applySyncPattern Cloud Function, which fans
  /// it out to every consenting crew member's own command queue so members
  /// whose app is closed get it via their bridge. Returns a [FanoutResult]:
  /// the caller suppresses its own broadcast ONLY on [FanoutResult.rateLimited]
  /// (reject = nothing fires); a plain failure (network/500/no-auth) returns a
  /// non-rate-limited result so the broadcast still proceeds.
  Future<FanoutResult> fanoutAdHocSync({
    required String groupId,
    required Map<String, dynamic> payload,
  }) async {
    final uid = _currentUid;
    if (uid == null) return const FanoutResult.failed();
    String? token;
    try {
      token = await _auth.currentUser?.getIdToken();
    } catch (e) {
      debugPrint('NeighborhoodService.fanoutAdHocSync: idToken failed: $e');
    }
    if (token == null) return const FanoutResult.failed();
    try {
      final resp = await http
          .post(
            Uri.parse('$_functionsBaseUrl/applySyncPattern'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $token',
            },
            body: jsonEncode({
              'data': {
                'groupId': groupId,
                'payload': payload,
                'initiatorUid': uid,
                'source': 'sync_fanout',
                // ONLY the ad-hoc caller sets this — gates server fanout so the
                // background self-apply callers (which omit it) stay self-only.
                'fanout': true,
              },
            }),
          )
          .timeout(const Duration(seconds: 10));
      final result = FanoutResult.parse(resp.statusCode, resp.body);
      if (!result.ok) {
        debugPrint('NeighborhoodService.fanoutAdHocSync: '
            'HTTP ${resp.statusCode} ${resp.body}');
      }
      return result;
    } catch (e) {
      debugPrint('NeighborhoodService.fanoutAdHocSync error: $e');
      return const FanoutResult.failed();
    }
  }

  /// Updates the position index for a member.
  Future<void> updateMemberPosition(String groupId, String oderId, int newPosition) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(oderId)
        .update({'positionIndex': newPosition});
  }

  /// Reorders all members' positions (after drag-and-drop).
  Future<void> reorderMembers(String groupId, List<String> orderedMemberIds) async {
    final batch = _firestore.batch();
    final membersRef = _neighborhoodsRef.doc(groupId).collection('members');

    for (int i = 0; i < orderedMemberIds.length; i++) {
      batch.update(membersRef.doc(orderedMemberIds[i]), {'positionIndex': i});
    }

    await batch.commit();
    debugPrint('Reordered ${orderedMemberIds.length} members');
  }

  /// Updates the current user's online status and last seen time.
  Future<void> updatePresence(String groupId, {bool isOnline = true}) async {
    final uid = _currentUid;
    if (uid == null) return;

    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .update({
      'isOnline': isOnline,
      'lastSeen': Timestamp.fromDate(DateTime.now()),
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Streams
  // ─────────────────────────────────────────────────────────────────────────────

  /// Stream of all groups the current user is a member of.
  Stream<List<NeighborhoodGroup>> watchUserGroups() {
    final uid = _currentUid;
    if (uid == null) return Stream.value([]);

    return _neighborhoodsRef
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => NeighborhoodGroup.fromFirestore(doc)).toList());
  }

  /// Stream of a single group.
  Stream<NeighborhoodGroup?> watchGroup(String groupId) {
    return _neighborhoodsRef.doc(groupId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return NeighborhoodGroup.fromFirestore(doc);
    });
  }

  /// Stream of members in a group, ordered by position.
  Stream<List<NeighborhoodMember>> watchMembers(String groupId) {
    return _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .orderBy('positionIndex')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => NeighborhoodMember.fromFirestore(doc)).toList());
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Sync Commands
  // ─────────────────────────────────────────────────────────────────────────────

  /// Broadcasts a sync command to all members.
  Future<void> broadcastSyncCommand(SyncCommand command) async {
    final docRef = _neighborhoodsRef
        .doc(command.groupId)
        .collection('commands')
        .doc();

    await docRef.set({
      ...command.toFirestore(),
      'id': docRef.id,
    });

    // Update group's active state
    await _neighborhoodsRef.doc(command.groupId).update({
      'isActive': true,
      'activePatternName': command.patternName,
    });

    debugPrint('Broadcast sync command: ${command.patternName ?? "Pattern"}');
  }

  /// Stops the current sync (clears active pattern).
  ///
  /// Legacy single-flag stop — preserved for autopilot session-manager
  /// teardown (sync_session_manager.dart:331). The user-driven two-tier
  /// stop now routes through [selfLeaveSync] (member) or [endGroupSync]
  /// (owner).
  Future<void> stopSync(String groupId) async {
    await _neighborhoodsRef.doc(groupId).update({
      'isActive': false,
      'activePatternId': null,
      'activePatternName': null,
    });

    debugPrint('Stopped sync for group: $groupId');
  }

  /// Member self-leave — flips ONLY the caller's own
  /// `/neighborhoods/{groupId}/members/{uid}.isParticipating` to false.
  /// Does NOT touch `g.isActive` or any other member's doc. The
  /// asymmetric trigger (syncEngineControllerProvider) sees own flag
  /// false → this member tears down only; other members are unaffected.
  ///
  /// Scoped self-write — permitted by the existing rule at
  /// firestore.rules:1252 (request.auth.uid == memberUid).
  Future<void> selfLeaveSync(String groupId) async {
    final uid = _currentUid;
    if (uid == null) return;
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(uid)
        .update({'isParticipating': false});
    // Broadcast a SELF-targeted teardown command on the same /commands channel
    // propagation uses, so this member's listener reliably reverts (the
    // flag-trigger was unreliable — its `|| hasActiveGroup` term kept the
    // leaver mounted while the group stayed active). targetMemberUid scopes it
    // to the leaver so the rest of the group keeps running. NOT deleting the
    // design command here — other members still need it.
    await writeTeardownCommand(groupId, targetMemberUid: uid);
    debugPrint('Self-left sync for group: $groupId (uid=$uid)');
  }

  /// Writes an explicit teardown ("revert now") command to
  /// `/neighborhoods/{groupId}/commands`. This is the positive signal the
  /// member's command listener acts on — replacing reliance on the
  /// unreliable local flag-trigger. [targetMemberUid] null = all members
  /// revert (owner End Group); non-null = only that member (self-leave).
  ///
  /// startTimestamp is `now`, so the orderBy-desc `watchLatestCommand` query
  /// returns THIS command as the latest — superseding any lingering design
  /// command so a fireImmediately/resume replay re-applies the TEARDOWN, not
  /// the ended pattern (the defect-#2 re-arm loop).
  @visibleForTesting
  Future<void> writeTeardownCommand(
    String groupId, {
    String? targetMemberUid,
  }) async {
    final docRef =
        _neighborhoodsRef.doc(groupId).collection('commands').doc();
    final command = SyncCommand.teardown(
      groupId: groupId,
      startTimestamp: DateTime.now(),
      targetMemberUid: targetMemberUid,
    );
    await docRef.set({
      ...command.toFirestore(),
      'id': docRef.id,
    });
  }

  /// Deletes all command docs for a group. Used by [endGroupSync] to purge
  /// lingering design commands so they can never be replayed to re-light a
  /// member after the group ends (defect #2). Owner-permitted (same access
  /// the dissolve/delete paths already exercise).
  Future<void> _clearGroupCommands(String groupId) async {
    final commands =
        await _neighborhoodsRef.doc(groupId).collection('commands').get();
    await Future.wait(commands.docs.map((d) => d.reference.delete()));
  }

  /// Owner-only end-of-group. Fans the per-member `isParticipating=false`
  /// clear across every member, then (only on full per-member success)
  /// clears the group doc's `isActive`/`activePatternId`/`activePatternName`.
  ///
  /// Per-member writes are PER-MEMBER (not a single atomic batch) so a
  /// single failed write is captured rather than rolling back all member
  /// writes. If ANY member write fails, the method throws
  /// [EndGroupSyncPartialFailure] with the failing UIDs and the group
  /// doc is LEFT untouched — so the session stays "active" and the owner
  /// is prompted to retry. Owner cross-member writes are permitted by the
  /// existing rule at firestore.rules:1253 (creatorUid == request.auth.uid).
  ///
  /// Caller MUST handle [EndGroupSyncPartialFailure] and surface it.
  Future<void> endGroupSync(
    String groupId,
    List<String> memberUids,
  ) async {
    final failures = <String, Object>{};

    await Future.wait(memberUids.map((uid) async {
      try {
        await writeMemberStopFlag(groupId, uid);
      } catch (e) {
        failures[uid] = e;
      }
    }));

    if (failures.isNotEmpty) {
      debugPrint(
        'endGroupSync partial failure for group $groupId: '
        '${failures.length}/${memberUids.length} member writes failed',
      );
      throw EndGroupSyncPartialFailure(groupId: groupId, failures: failures);
    }

    // Purge lingering design commands, then broadcast a single GLOBAL teardown
    // command (targetMemberUid: null → every member reverts). This is the
    // positive "revert now" signal on the proven command channel; the purge +
    // teardown-as-latest closes the defect-#2 replay loop (a resuming member
    // replays the TEARDOWN, never the ended pattern).
    await _clearGroupCommands(groupId);
    await writeTeardownCommand(groupId);

    await _neighborhoodsRef.doc(groupId).update({
      'isActive': false,
      'activePatternId': null,
      'activePatternName': null,
    });
    debugPrint(
        'endGroupSync complete for group $groupId (cleared ${memberUids.length} member flags)');
  }

  /// Per-member stop-flag write. Extracted for test override — subclass
  /// and override to inject a failure on a specific UID without standing
  /// up a custom Firestore mock that fails one path.
  @visibleForTesting
  Future<void> writeMemberStopFlag(String groupId, String memberUid) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberUid)
        .update({'isParticipating': false});
  }

  /// Stream of the latest sync command for a group.
  ///
  /// The parse is guarded: a single unparseable command doc is mapped to
  /// `null` (treated as "no command") rather than throwing out of `.map`,
  /// which would error-terminate the whole stream and permanently kill the
  /// listener until an app relaunch (#52 dead-listener class). A genuine
  /// Firestore stream error (permission / disconnect) is still allowed to
  /// surface so the engine can detect it and re-subscribe.
  Stream<SyncCommand?> watchLatestCommand(String groupId) {
    return _neighborhoodsRef
        .doc(groupId)
        .collection('commands')
        .orderBy('startTimestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      final doc = snapshot.docs.first;
      try {
        return SyncCommand.fromFirestore(doc);
      } catch (e) {
        debugPrint(
          'watchLatestCommand: skipping unparseable command doc '
          '${doc.id} in group $groupId (stream kept alive): $e',
        );
        return null;
      }
    });
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Schedule Management
  // ─────────────────────────────────────────────────────────────────────────────

  /// Creates a new sync schedule for a group.
  Future<SyncSchedule> createSchedule(SyncSchedule schedule) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef
        .doc(schedule.groupId)
        .collection('schedules')
        .doc();

    final newSchedule = schedule.copyWith(
      id: docRef.id,
      createdBy: uid,
      createdAt: DateTime.now(),
    );

    await docRef.set(UserService.sanitizeForFirestore(newSchedule.toFirestore()));
    debugPrint('Created schedule: ${newSchedule.patternName}');
    return newSchedule;
  }

  /// Updates an existing schedule.
  Future<void> updateSchedule(SyncSchedule schedule) async {
    await _neighborhoodsRef
        .doc(schedule.groupId)
        .collection('schedules')
        .doc(schedule.id)
        .update(UserService.sanitizeForFirestore(schedule.toFirestore()));
    debugPrint('Updated schedule: ${schedule.patternName}');
  }

  /// Deletes a schedule.
  Future<void> deleteSchedule(String groupId, String scheduleId) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('schedules')
        .doc(scheduleId)
        .delete();
    debugPrint('Deleted schedule: $scheduleId');
  }

  /// Toggles a schedule's active state.
  Future<void> toggleScheduleActive(String groupId, String scheduleId, bool isActive) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('schedules')
        .doc(scheduleId)
        .update({'isActive': isActive});
    debugPrint('Schedule $scheduleId active: $isActive');
  }

  /// Stream of all schedules for a group.
  Stream<List<SyncSchedule>> watchSchedules(String groupId) {
    return _neighborhoodsRef
        .doc(groupId)
        .collection('schedules')
        .orderBy('startDate')
        .snapshots()
        .map((snapshot) =>
            snapshot.docs.map((doc) => SyncSchedule.fromFirestore(doc)).toList());
  }

  /// Gets all schedules for a group (one-time fetch).
  Future<List<SyncSchedule>> getSchedules(String groupId) async {
    final snapshot = await _neighborhoodsRef
        .doc(groupId)
        .collection('schedules')
        .orderBy('startDate')
        .get();
    return snapshot.docs.map((doc) => SyncSchedule.fromFirestore(doc)).toList();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Member Participation Controls
  // ─────────────────────────────────────────────────────────────────────────────

  /// Pauses sync participation for a member (runs their own pattern).
  Future<void> pauseMemberSync(String groupId, String memberId) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({'participationStatus': MemberParticipationStatus.paused.name});
    debugPrint('Paused sync for member: $memberId');
  }

  /// Resumes sync participation for a member.
  Future<void> resumeMemberSync(String groupId, String memberId) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({'participationStatus': MemberParticipationStatus.active.name});
    debugPrint('Resumed sync for member: $memberId');
  }

  /// Opts a member out of a specific scheduled event.
  Future<void> optOutOfSchedule(String groupId, String memberId, String scheduleId) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({
      'optedOutScheduleIds': FieldValue.arrayUnion([scheduleId]),
    });
    debugPrint('Member $memberId opted out of schedule: $scheduleId');
  }

  /// Opts a member back in to a specific scheduled event.
  Future<void> optInToSchedule(String groupId, String memberId, String scheduleId) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({
      'optedOutScheduleIds': FieldValue.arrayRemove([scheduleId]),
    });
    debugPrint('Member $memberId opted in to schedule: $scheduleId');
  }

  /// Sets a member's overall participation status.
  Future<void> setMemberParticipationStatus(
    String groupId,
    String memberId,
    MemberParticipationStatus status,
  ) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(memberId)
        .update({'participationStatus': status.name});
    debugPrint('Set member $memberId status: ${status.name}');
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Find Nearby Groups (Public Groups)
  // ─────────────────────────────────────────────────────────────────────────────

  /// Finds public groups near a given location.
  /// Uses a simple bounding box query (not true geo-distance).
  /// For accurate distance calculation, results should be filtered client-side.
  Future<List<NeighborhoodGroup>> findNearbyGroups({
    required double latitude,
    required double longitude,
    double radiusKm = 10.0,
  }) async {
    // Approximate degrees for radius (1 degree ~= 111km at equator)
    final latDelta = radiusKm / 111.0;
    final lngDelta = radiusKm / (111.0 * cos(latitude * pi / 180.0));

    // F-3: discovery reads the PUBLIC PROJECTION, never /neighborhoods.
    //
    // This query used to run against the full group docs, which is why the
    // group read rule had to be open to every authenticated token — and that
    // open read is what exposed `streetName`, exact coordinates and
    // `inviteCode` fleet-wide. The projection carries only what discovery
    // actually needs, and its coordinates are COARSE (2dp ≈ 1.1 km), so a
    // result set locates a neighborhood rather than a house.
    final query = await _publicProjectionRef
        .where('isPublic', isEqualTo: true)
        .where('latCoarse', isGreaterThanOrEqualTo: latitude - latDelta)
        .where('latCoarse', isLessThanOrEqualTo: latitude + latDelta)
        .get();

    // Filter by longitude and calculate actual distance
    final results = <NeighborhoodGroup>[];
    for (final doc in query.docs) {
      final group = _groupFromProjection(doc);
      if (group.longitude == null) continue;

      // Check longitude bounds
      if (group.longitude! < longitude - lngDelta ||
          group.longitude! > longitude + lngDelta) {
        continue;
      }

      // Distance is computed from the coarse pair, so it is accurate to about
      // a kilometre. That is the right resolution for "crews near me" and is
      // the deliberate cost of not publishing exact coordinates.
      final distance = _calculateDistanceKm(
        latitude,
        longitude,
        group.latitude!,
        group.longitude!,
      );

      if (distance <= radiusKm) {
        results.add(group);
      }
    }

    debugPrint('Found ${results.length} nearby public groups');
    return results;
  }

  /// Calculates the distance between two coordinates using Haversine formula.
  double _calculateDistanceKm(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const earthRadiusKm = 6371.0;

    final dLat = _degreesToRadians(lat2 - lat1);
    final dLon = _degreesToRadians(lon2 - lon1);

    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degreesToRadians(lat1)) *
            cos(_degreesToRadians(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);

    final c = 2 * atan2(sqrt(a), sqrt(1 - a));

    return earthRadiusKm * c;
  }

  double _degreesToRadians(double degrees) {
    return degrees * pi / 180.0;
  }

  /// Updates a group's location (for Find Nearby feature).
  Future<void> updateGroupLocation(
    String groupId, {
    required double latitude,
    required double longitude,
  }) async {
    await _neighborhoodsRef.doc(groupId).update({
      'latitude': latitude,
      'longitude': longitude,
    });
    debugPrint('Updated group location: $latitude, $longitude');
  }

  /// Updates a group's public visibility.
  Future<void> setGroupPublic(String groupId, bool isPublic) async {
    await _neighborhoodsRef.doc(groupId).update({'isPublic': isPublic});
    // F-3: the projection IS the listing. Publishing/removing it is what makes
    // a crew discoverable, so the flag and the projection move together.
    if (isPublic) {
      final doc = await _neighborhoodsRef.doc(groupId).get();
      if (doc.exists) {
        await publishPublicProjection(NeighborhoodGroup.fromFirestore(doc));
      }
    } else {
      await removePublicProjection(groupId);
    }
    debugPrint('Set group public: $isPublic');
  }

  /// Coarsens a coordinate to 2 decimal places (~1.1 km).
  ///
  /// This is the privacy boundary of the whole discovery feature: proximity
  /// search needs SOME geography to be cross-tenant readable, and 2dp names a
  /// neighborhood without naming a house. The rules enforce the projection's
  /// SHAPE (no `latitude`/`longitude` keys at all), but only this function
  /// decides the PRECISION — so if it is ever loosened, the rule will not
  /// catch it. Keep them in sync.
  static double? coarsenCoordinate(double? value) {
    if (value == null) return null;
    return (value * 100).roundToDouble() / 100;
  }

  /// Writes the public projection for [group].
  ///
  /// Deliberately narrow: name, description, member count, coarse coordinates.
  /// NEVER `inviteCode` (a credential), `streetName`, exact coordinates, or
  /// `memberUids`. The rule at `/neighborhood_public/{groupId}` rejects a write
  /// carrying any of those, so a future edit to this method fails loudly
  /// instead of leaking.
  Future<void> publishPublicProjection(NeighborhoodGroup group) async {
    final lat = coarsenCoordinate(group.latitude);
    final lon = coarsenCoordinate(group.longitude);
    if (lat == null || lon == null) {
      // Without coordinates the crew cannot appear in a proximity search, and
      // publishing a coordinate-less row would just be an unsearchable name.
      debugPrint('Skipping public projection for ${group.id}: no coordinates');
      return;
    }
    await _publicProjectionRef.doc(group.id).set({
      'groupId': group.id,
      'name': group.name,
      'description': group.description,
      'memberCount': group.memberUids.length,
      'isPublic': true,
      'latCoarse': lat,
      'lonCoarse': lon,
      'updatedAt': FieldValue.serverTimestamp(),
    });
    debugPrint('Published public projection for ${group.id}');
  }

  /// Removes the public projection — how a crew goes unlisted again.
  Future<void> removePublicProjection(String groupId) async {
    await _publicProjectionRef.doc(groupId).delete();
  }

  /// Rebuilds a display-only [NeighborhoodGroup] from a projection doc.
  ///
  /// The unavailable fields are filled with safe blanks — `inviteCode` is empty
  /// because the projection genuinely has none, which is why joining from
  /// discovery goes through [joinPublicGroup] (by id) rather than by code.
  NeighborhoodGroup _groupFromProjection(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    return NeighborhoodGroup(
      id: doc.id,
      name: d['name'] as String? ?? '',
      description: d['description'] as String?,
      streetName: null,
      city: null,
      isPublic: true,
      inviteCode: '',
      creatorUid: '',
      createdAt: DateTime.now(),
      // memberCount drives the "N homes" label; the uids themselves are not
      // published, so synthesize a list of the right LENGTH with no identities.
      memberUids: List<String>.filled(
        (d['memberCount'] as num?)?.toInt() ?? 0,
        '',
      ),
      latitude: (d['latCoarse'] as num?)?.toDouble(),
      longitude: (d['lonCoarse'] as num?)?.toDouble(),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Utilities
  // ─────────────────────────────────────────────────────────────────────────────

  /// Generates a 6-character invite code.
  String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // Omit confusing chars
    final random = Random();
    return List.generate(6, (_) => chars[random.nextInt(chars.length)]).join();
  }

  /// Gets a group by ID (one-time fetch).
  Future<NeighborhoodGroup?> getGroup(String groupId) async {
    final doc = await _neighborhoodsRef.doc(groupId).get();
    if (!doc.exists) return null;
    return NeighborhoodGroup.fromFirestore(doc);
  }

  /// Gets all members of a group (one-time fetch).
  Future<List<NeighborhoodMember>> getMembers(String groupId) async {
    final snapshot = await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .orderBy('positionIndex')
        .get();
    return snapshot.docs.map((doc) => NeighborhoodMember.fromFirestore(doc)).toList();
  }
}

/// Thrown when [NeighborhoodService.endGroupSync] could not clear every
/// member's `isParticipating` flag. The group doc is LEFT untouched so
/// the session stays "active" — the owner can retry. UI must surface
/// this rather than swallow.
class EndGroupSyncPartialFailure implements Exception {
  EndGroupSyncPartialFailure({
    required this.groupId,
    required this.failures,
  });

  final String groupId;

  /// memberUid → underlying error.
  final Map<String, Object> failures;

  @override
  String toString() =>
      'EndGroupSyncPartialFailure(groupId=$groupId, '
      'failedMemberCount=${failures.length}, '
      'failedUids=${failures.keys.toList()})';
}
