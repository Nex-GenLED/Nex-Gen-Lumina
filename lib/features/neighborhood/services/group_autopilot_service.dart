import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/services/user_service.dart';

import '../models/group_game_day_autopilot.dart';

/// Firestore service for Group Game Day Autopilot.
///
/// Collection structure:
///   `/neighborhoods/{groupId}/game_day_autopilot/config`  — autopilot config
///   `/neighborhoods/{groupId}/members/{userId}`            — `groupAutopilotOptIn` field
class GroupAutopilotService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  GroupAutopilotService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── Document references ──────────────────────────────────────────

  DocumentReference _configDoc(String groupId) => _firestore
      .collection('neighborhoods')
      .doc(groupId)
      .collection('game_day_autopilot')
      .doc('config');

  DocumentReference _memberDoc(String groupId, String userId) => _firestore
      .collection('neighborhoods')
      .doc(groupId)
      .collection('members')
      .doc(userId);

  // ── Host: Set Group Autopilot ────────────────────────────────────

  /// Host writes the group autopilot config, computing activeMemberIds
  /// from all members who have `groupAutopilotOptIn == true`.
  Future<void> setGroupAutopilot(
    String groupId,
    GroupGameDayAutopilot config,
  ) async {
    final optedIn = await getOptedInMemberIds(groupId);
    final updated = config.copyWith(
      activeMemberIds: optedIn,
      updatedAt: DateTime.now(),
    );
    await _configDoc(groupId)
        .set(UserService.sanitizeForFirestore(updated.toFirestore()));
    debugPrint(
      '[GroupAutopilotService] Set group autopilot for $groupId '
      '(${optedIn.length} opted-in members)',
    );
  }

  /// Disable group autopilot entirely (host or when host opts out).
  Future<void> disableGroupAutopilot(String groupId) async {
    final doc = await _configDoc(groupId).get();
    if (!doc.exists) return;
    await _configDoc(groupId).update({
      'enabled': false,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });
    debugPrint('[GroupAutopilotService] Disabled group autopilot for $groupId');
  }

  /// Delete the group autopilot config entirely.
  Future<void> deleteGroupAutopilot(String groupId) async {
    await _configDoc(groupId).delete();
  }

  // ── Read / Watch ─────────────────────────────────────────────────

  /// Get the current group autopilot config (one-shot).
  Future<GroupGameDayAutopilot?> getGroupAutopilot(String groupId) async {
    final doc = await _configDoc(groupId).get();
    if (!doc.exists) return null;
    return GroupGameDayAutopilot.fromFirestore(doc);
  }

  /// Stream the group autopilot config for real-time UI updates.
  Stream<GroupGameDayAutopilot?> watchGroupAutopilot(String groupId) {
    return _configDoc(groupId).snapshots().map((snap) {
      if (!snap.exists) return null;
      return GroupGameDayAutopilot.fromFirestore(snap);
    });
  }

  // ── Member Opt-In / Opt-Out ──────────────────────────────────────

  /// Set the current user's group autopilot opt-in status.
  Future<void> setOptIn(String groupId, bool optIn) async {
    final uid = _uid;
    if (uid == null) return;
    await setMemberOptIn(groupId, uid, optIn);
  }

  /// Set a specific member's group autopilot opt-in status.
  /// Only the member themselves should call this (enforced by security rules).
  Future<void> setMemberOptIn(
    String groupId,
    String userId,
    bool optIn,
  ) async {
    await _memberDoc(groupId, userId).update({
      'groupAutopilotOptIn': optIn,
    });

    // Update activeMemberIds in the config document
    final config = await getGroupAutopilot(groupId);
    if (config == null || !config.enabled) return;

    final currentIds = List<String>.from(config.activeMemberIds);
    if (optIn && !currentIds.contains(userId)) {
      currentIds.add(userId);
    } else if (!optIn) {
      currentIds.remove(userId);
    }

    await _configDoc(groupId).update({
      'activeMemberIds': currentIds,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    debugPrint(
      '[GroupAutopilotService] Member $userId opt-${optIn ? 'in' : 'out'} '
      'for group $groupId (${currentIds.length} active)',
    );

    // If the host opts out, cancel the entire group autopilot
    if (!optIn && config.hostUserId == userId) {
      debugPrint(
        '[GroupAutopilotService] Host opted out — cancelling group autopilot',
      );
      await disableGroupAutopilot(groupId);
    }
  }

  /// Get the opt-in status for a specific member.
  Future<bool> getMemberOptIn(String groupId, String userId) async {
    final doc = await _memberDoc(groupId, userId).get();
    if (!doc.exists) return true; // Default to opted in
    final data = doc.data() as Map<String, dynamic>;
    return data['groupAutopilotOptIn'] ?? true;
  }

  /// Get all opted-in member IDs for a group.
  /// Always re-fetch this before broadcasting — a member may have opted out
  /// after the session was configured.
  Future<List<String>> getOptedInMemberIds(String groupId) async {
    final snap = await _firestore
        .collection('neighborhoods')
        .doc(groupId)
        .collection('members')
        .where('groupAutopilotOptIn', isNotEqualTo: false)
        .get();

    return snap.docs.map((d) => d.id).toList();
  }

  /// Refresh the activeMemberIds in the config from current member states.
  /// Call this before any broadcast to ensure accuracy.
  Future<List<String>> refreshActiveMemberIds(String groupId) async {
    final config = await getGroupAutopilot(groupId);
    if (config == null || !config.enabled) return [];

    final optedIn = await getOptedInMemberIds(groupId);
    if (optedIn.isEmpty) {
      debugPrint(
        '[GroupAutopilotService] All members opted out — '
        'cancelling broadcast silently',
      );
      return [];
    }

    await _configDoc(groupId).update({
      'activeMemberIds': optedIn,
      'updatedAt': Timestamp.fromDate(DateTime.now()),
    });

    return optedIn;
  }
}
