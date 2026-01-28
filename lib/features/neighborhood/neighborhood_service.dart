import 'dart:math' show Random, cos, sin, sqrt, atan2, pi;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'neighborhood_models.dart';

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

  String? get _currentUid => _auth.currentUser?.uid;

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
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final inviteCode = _generateInviteCode();
    final now = DateTime.now();

    final docRef = _neighborhoodsRef.doc();
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

    await docRef.set(group.toFirestore());

    // Add creator as first member
    final member = NeighborhoodMember(
      oderId: uid,
      displayName: displayName ?? 'My Home',
      positionIndex: 0,
      lastSeen: now,
      isOnline: true,
    );
    await docRef.collection('members').doc(uid).set(member.toFirestore());

    debugPrint('Created neighborhood group: ${group.name} (${group.inviteCode})');
    return group;
  }

  /// Joins an existing group using an invite code.
  Future<NeighborhoodGroup?> joinGroup(String inviteCode, {String? displayName}) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    // Find group by invite code
    final query = await _neighborhoodsRef
        .where('inviteCode', isEqualTo: inviteCode.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) {
      debugPrint('No group found with invite code: $inviteCode');
      return null;
    }

    final doc = query.docs.first;
    final group = NeighborhoodGroup.fromFirestore(doc);

    // Check if already a member
    if (group.memberUids.contains(uid)) {
      debugPrint('Already a member of group: ${group.name}');
      return group;
    }

    // Add user to member list
    await doc.reference.update({
      'memberUids': FieldValue.arrayUnion([uid]),
    });

    // Get current member count for position
    final membersSnapshot = await doc.reference.collection('members').get();
    final positionIndex = membersSnapshot.docs.length;

    // Add member document
    final member = NeighborhoodMember(
      oderId: uid,
      displayName: displayName ?? 'Home #${positionIndex + 1}',
      positionIndex: positionIndex,
      lastSeen: DateTime.now(),
      isOnline: true,
    );
    await doc.reference.collection('members').doc(uid).set(member.toFirestore());

    debugPrint('Joined neighborhood group: ${group.name}');
    return group.copyWith(memberUids: [...group.memberUids, uid]);
  }

  /// Leaves a neighborhood group.
  Future<void> leaveGroup(String groupId) async {
    final uid = _currentUid;
    if (uid == null) throw Exception('User not authenticated');

    final docRef = _neighborhoodsRef.doc(groupId);
    final doc = await docRef.get();

    if (!doc.exists) return;

    final group = NeighborhoodGroup.fromFirestore(doc);

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

    debugPrint('Left neighborhood group: ${group.name}');
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

  /// Updates a member's configuration.
  Future<void> updateMember(String groupId, NeighborhoodMember member) async {
    await _neighborhoodsRef
        .doc(groupId)
        .collection('members')
        .doc(member.oderId)
        .update(member.toFirestore());
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
  Future<void> stopSync(String groupId) async {
    await _neighborhoodsRef.doc(groupId).update({
      'isActive': false,
      'activePatternId': null,
      'activePatternName': null,
    });

    debugPrint('Stopped sync for group: $groupId');
  }

  /// Stream of the latest sync command for a group.
  Stream<SyncCommand?> watchLatestCommand(String groupId) {
    return _neighborhoodsRef
        .doc(groupId)
        .collection('commands')
        .orderBy('startTimestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) return null;
      return SyncCommand.fromFirestore(snapshot.docs.first);
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

    await docRef.set(newSchedule.toFirestore());
    debugPrint('Created schedule: ${newSchedule.patternName}');
    return newSchedule;
  }

  /// Updates an existing schedule.
  Future<void> updateSchedule(SyncSchedule schedule) async {
    await _neighborhoodsRef
        .doc(schedule.groupId)
        .collection('schedules')
        .doc(schedule.id)
        .update(schedule.toFirestore());
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

    // Query public groups within bounding box
    final query = await _neighborhoodsRef
        .where('isPublic', isEqualTo: true)
        .where('latitude', isGreaterThanOrEqualTo: latitude - latDelta)
        .where('latitude', isLessThanOrEqualTo: latitude + latDelta)
        .get();

    // Filter by longitude and calculate actual distance
    final results = <NeighborhoodGroup>[];
    for (final doc in query.docs) {
      final group = NeighborhoodGroup.fromFirestore(doc);
      if (group.longitude == null) continue;

      // Check longitude bounds
      if (group.longitude! < longitude - lngDelta ||
          group.longitude! > longitude + lngDelta) {
        continue;
      }

      // Calculate actual distance using Haversine
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
    debugPrint('Set group public: $isPublic');
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
