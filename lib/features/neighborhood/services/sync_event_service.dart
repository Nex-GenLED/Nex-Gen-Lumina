import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../models/sync_event.dart';

/// Firestore backend for Autopilot Sync Events and sessions.
///
/// Collection structure:
///   /neighborhoods/{groupId}/syncEvents/{eventId}
///   /neighborhoods/{groupId}/syncSessions/{sessionId}
///   /neighborhoods/{groupId}/members/{memberId}/consent (document)
class SyncEventService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  SyncEventService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  // ── Collection references ──────────────────────────────────────────

  CollectionReference _syncEventsCol(String groupId) =>
      _firestore.collection('neighborhoods').doc(groupId).collection('syncEvents');

  CollectionReference _syncSessionsCol(String groupId) =>
      _firestore.collection('neighborhoods').doc(groupId).collection('syncSessions');

  DocumentReference _consentDoc(String groupId, String memberId) =>
      _firestore
          .collection('neighborhoods')
          .doc(groupId)
          .collection('members')
          .doc(memberId)
          .collection('settings')
          .doc('syncConsent');

  // ── Sync Event CRUD ────────────────────────────────────────────────

  /// Create a new sync event in a group.
  Future<String> createSyncEvent(String groupId, SyncEvent event) async {
    final doc = _syncEventsCol(groupId).doc();
    final withId = event.copyWith(id: doc.id, createdBy: _uid ?? '');
    await doc.set(withId.toFirestore());
    debugPrint('[SyncEventService] Created sync event: ${doc.id}');
    return doc.id;
  }

  /// Update an existing sync event.
  Future<void> updateSyncEvent(String groupId, SyncEvent event) async {
    await _syncEventsCol(groupId).doc(event.id).update(event.toFirestore());
  }

  /// Delete a sync event and any associated pending sessions.
  Future<void> deleteSyncEvent(String groupId, String eventId) async {
    final batch = _firestore.batch();
    batch.delete(_syncEventsCol(groupId).doc(eventId));

    // Clean up pending sessions for this event
    final sessions = await _syncSessionsCol(groupId)
        .where('syncEventId', isEqualTo: eventId)
        .where('status', isEqualTo: 'pending')
        .get();
    for (final doc in sessions.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }

  /// Toggle enabled state of a sync event.
  Future<void> toggleSyncEvent(String groupId, String eventId) async {
    final doc = await _syncEventsCol(groupId).doc(eventId).get();
    if (!doc.exists) return;
    final current = (doc.data() as Map<String, dynamic>)['isEnabled'] ?? true;
    await doc.reference.update({'isEnabled': !current});
  }

  /// Get a single sync event.
  Future<SyncEvent?> getSyncEvent(String groupId, String eventId) async {
    final doc = await _syncEventsCol(groupId).doc(eventId).get();
    if (!doc.exists) return null;
    return SyncEvent.fromFirestore(doc);
  }

  /// Stream all sync events for a group.
  Stream<List<SyncEvent>> watchSyncEvents(String groupId) {
    return _syncEventsCol(groupId)
        .orderBy('createdAt', descending: true)
        .snapshots()
        .map((snap) => snap.docs.map(SyncEvent.fromFirestore).toList());
  }

  /// Get all enabled sync events for a group.
  Future<List<SyncEvent>> getEnabledSyncEvents(String groupId) async {
    final snap = await _syncEventsCol(groupId)
        .where('isEnabled', isEqualTo: true)
        .get();
    return snap.docs.map(SyncEvent.fromFirestore).toList();
  }

  /// Check for schedule conflicts between sync events.
  Future<SyncEvent?> findConflict(
    String groupId,
    DateTime startTime,
    Duration estimatedDuration,
    String? excludeEventId,
  ) async {
    final endTime = startTime.add(estimatedDuration);
    final events = await getEnabledSyncEvents(groupId);
    for (final event in events) {
      if (event.id == excludeEventId) continue;
      if (event.scheduledTime == null) continue;
      // Simple overlap check — assumes 3-hour window for game events
      final eventEnd = event.scheduledTime!.add(
        event.isGameDay
            ? const Duration(hours: 3)
            : estimatedDuration,
      );
      if (startTime.isBefore(eventEnd) &&
          endTime.isAfter(event.scheduledTime!)) {
        return event;
      }
    }
    return null;
  }

  // ── Sync Sessions ──────────────────────────────────────────────────

  /// Create a new session for a sync event.
  Future<String> createSession(
    String groupId,
    SyncEventSession session,
  ) async {
    final doc = _syncSessionsCol(groupId).doc();
    final withId = session.copyWith(id: doc.id);
    await doc.set(withId.toFirestore());
    debugPrint('[SyncEventService] Created session: ${doc.id}');
    return doc.id;
  }

  /// Update session state.
  Future<void> updateSession(
    String groupId,
    SyncEventSession session,
  ) async {
    await _syncSessionsCol(groupId).doc(session.id).update(
          session.toFirestore(),
        );
  }

  /// Mark a session as active.
  Future<void> activateSession(String groupId, String sessionId) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'status': SyncEventSessionStatus.active.toJson(),
    });
  }

  /// Mark a session as ending (30-second warning).
  Future<void> markSessionEnding(String groupId, String sessionId) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'status': SyncEventSessionStatus.ending.toJson(),
    });
  }

  /// Complete a session.
  Future<void> completeSession(String groupId, String sessionId) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'status': SyncEventSessionStatus.completed.toJson(),
      'endedAt': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Add a participant to an active session.
  Future<void> addParticipant(
    String groupId,
    String sessionId,
    String uid,
  ) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'activeParticipantUids': FieldValue.arrayUnion([uid]),
      'declinedUids': FieldValue.arrayRemove([uid]),
    });
  }

  /// Remove a participant ("Not tonight" opt-out for this session).
  Future<void> removeParticipant(
    String groupId,
    String sessionId,
    String uid,
  ) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'activeParticipantUids': FieldValue.arrayRemove([uid]),
      'declinedUids': FieldValue.arrayUnion([uid]),
    });
  }

  /// Set celebration state on a session.
  Future<void> setCelebrating(
    String groupId,
    String sessionId, {
    required bool celebrating,
  }) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'isCelebrating': celebrating,
      'celebrationStartedAt':
          celebrating ? Timestamp.fromDate(DateTime.now()) : null,
    });
  }

  /// Stream the active session for a group (if any).
  Stream<SyncEventSession?> watchActiveSession(String groupId) {
    return _syncSessionsCol(groupId)
        .where('status', whereIn: [
          SyncEventSessionStatus.active.toJson(),
          SyncEventSessionStatus.waitingForGameStart.toJson(),
          SyncEventSessionStatus.ending.toJson(),
        ])
        .limit(1)
        .snapshots()
        .map((snap) =>
            snap.docs.isEmpty ? null : SyncEventSession.fromFirestore(snap.docs.first));
  }

  /// Get active session for a group.
  Future<SyncEventSession?> getActiveSession(String groupId) async {
    final snap = await _syncSessionsCol(groupId)
        .where('status', whereIn: [
          SyncEventSessionStatus.active.toJson(),
          SyncEventSessionStatus.waitingForGameStart.toJson(),
        ])
        .limit(1)
        .get();
    if (snap.docs.isEmpty) return null;
    return SyncEventSession.fromFirestore(snap.docs.first);
  }

  /// Update session host (for failover).
  Future<void> updateSessionHost(
    String groupId,
    String sessionId,
    String newHostUid,
  ) async {
    await _syncSessionsCol(groupId).doc(sessionId).update({
      'hostUid': newHostUid,
    });
  }

  // ── Participation Consent ──────────────────────────────────────────

  /// Get a member's consent preferences.
  Future<SyncParticipationConsent?> getConsent(
    String groupId,
    String memberId,
  ) async {
    final doc = await _consentDoc(groupId, memberId).get();
    if (!doc.exists) return null;
    return SyncParticipationConsent.fromFirestore(doc);
  }

  /// Save or update a member's consent preferences.
  Future<void> saveConsent(
    String groupId,
    SyncParticipationConsent consent,
  ) async {
    await _consentDoc(groupId, consent.oderId).set(
      consent.toFirestore(),
      SetOptions(merge: true),
    );
  }

  /// Stream a member's consent preferences.
  Stream<SyncParticipationConsent?> watchConsent(
    String groupId,
    String memberId,
  ) {
    return _consentDoc(groupId, memberId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return SyncParticipationConsent.fromFirestore(doc);
    });
  }

  /// Get all members who have opted in to a specific category.
  Future<List<SyncParticipationConsent>> getOptedInMembers(
    String groupId,
    SyncEventCategory category,
    List<String> memberUids,
  ) async {
    final results = <SyncParticipationConsent>[];
    for (final uid in memberUids) {
      final consent = await getConsent(groupId, uid);
      if (consent != null && consent.isOptedInTo(category)) {
        results.add(consent);
      }
    }
    return results;
  }

  /// Toggle "Skip Next" for a specific event.
  Future<void> toggleSkipNextEvent(
    String groupId,
    String memberId,
    String eventId, {
    required bool skip,
  }) async {
    final consent = await getConsent(groupId, memberId);
    if (consent == null) return;
    final updated = List<String>.from(consent.skipNextEventIds);
    if (skip && !updated.contains(eventId)) {
      updated.add(eventId);
    } else if (!skip) {
      updated.remove(eventId);
    }
    await saveConsent(
      groupId,
      consent.copyWith(
        skipNextEventIds: updated,
        updatedAt: DateTime.now(),
      ),
    );
  }
}
