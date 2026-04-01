import 'dart:math' show Random;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../sports_alerts/models/sport_type.dart';
import 'game_day_crew_models.dart';

/// Firestore CRUD for Game Day Crews.
///
/// Collection: `/game_day_crews/{crewId}`
///
/// Only the host can mutate crew settings (design, live scoring, autopilot).
/// Members can only join or leave.
class GameDayCrewService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  GameDayCrewService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  CollectionReference<Map<String, dynamic>> get _crewsRef =>
      _firestore.collection('game_day_crews');

  String? get _currentUid => _auth.currentUser?.uid;

  // ─────────────────────────────────────────────────────────────────────────────
  // Create / Join / Leave
  // ─────────────────────────────────────────────────────────────────────────────

  /// Creates a new Game Day Crew from the user's existing personal config.
  Future<GameDayCrew> createCrew({
    required String teamSlug,
    required String teamName,
    required String sport,
    required String hostDisplayName,
    required String espnTeamId,
    required int primaryColorValue,
    required int secondaryColorValue,
    Map<String, dynamic>? designPayload,
    String designName = 'Team Colors (Solid)',
    int effectId = 0,
    int speed = 128,
    int intensity = 128,
    int brightness = 200,
    bool liveScoring = false,
    bool autopilotEnabled = true,
  }) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('Not authenticated');

    final inviteCode = _generateInviteCode();
    final now = DateTime.now();
    final docRef = _crewsRef.doc();

    final crew = GameDayCrew(
      id: docRef.id,
      teamSlug: teamSlug,
      teamName: teamName,
      sport: _parseSport(sport),
      hostUid: uid,
      hostDisplayName: hostDisplayName,
      inviteCode: inviteCode,
      liveScoring: liveScoring,
      autopilotEnabled: autopilotEnabled,
      designPayload: designPayload,
      designName: designName,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      primaryColorValue: primaryColorValue,
      secondaryColorValue: secondaryColorValue,
      espnTeamId: espnTeamId,
      memberUids: [uid],
      createdAt: now,
      updatedAt: now,
    );

    await docRef.set(crew.toFirestore());
    return crew;
  }

  /// Join an existing crew by invite code.
  Future<GameDayCrew?> joinCrew(String inviteCode) async {
    final uid = _currentUid;
    if (uid == null) throw StateError('Not authenticated');

    final query = await _crewsRef
        .where('invite_code', isEqualTo: inviteCode.toUpperCase())
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;

    final doc = query.docs.first;
    final crew = GameDayCrew.fromFirestore(doc);

    if (crew.memberUids.contains(uid)) return crew; // Already a member.

    await doc.reference.update({
      'member_uids': FieldValue.arrayUnion([uid]),
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });

    return crew.copyWith(
      memberUids: [...crew.memberUids, uid],
      updatedAt: DateTime.now(),
    );
  }

  /// Leave a crew. If the host leaves, the crew is dissolved.
  Future<void> leaveCrew(String crewId) async {
    final uid = _currentUid;
    if (uid == null) return;

    final doc = await _crewsRef.doc(crewId).get();
    if (!doc.exists) return;

    final crew = GameDayCrew.fromFirestore(doc);

    if (crew.isHost(uid)) {
      // Host leaves → dissolve the crew.
      await _crewsRef.doc(crewId).delete();
    } else {
      await _crewsRef.doc(crewId).update({
        'member_uids': FieldValue.arrayRemove([uid]),
        'updated_at': Timestamp.fromDate(DateTime.now()),
      });
    }
  }

  /// Dissolve (delete) a crew. Host only.
  Future<void> dissolveCrew(String crewId) async {
    final uid = _currentUid;
    if (uid == null) return;

    final doc = await _crewsRef.doc(crewId).get();
    if (!doc.exists) return;

    final crew = GameDayCrew.fromFirestore(doc);
    if (!crew.isHost(uid)) return; // Only host can dissolve.

    await _crewsRef.doc(crewId).delete();
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Host-Only Mutations
  // ─────────────────────────────────────────────────────────────────────────────

  /// Update the crew's design. Pushes to all members.
  Future<void> updateDesign(
    String crewId, {
    required Map<String, dynamic>? designPayload,
    required String designName,
    required int effectId,
    int speed = 128,
    int intensity = 128,
    int brightness = 200,
  }) async {
    await _crewsRef.doc(crewId).update({
      'design_payload': designPayload,
      'design_name': designName,
      'effect_id': effectId,
      'speed': speed,
      'intensity': intensity,
      'brightness': brightness,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Toggle live scoring for the entire crew.
  Future<void> setLiveScoring(String crewId, bool enabled) async {
    await _crewsRef.doc(crewId).update({
      'live_scoring': enabled,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Toggle autopilot for the entire crew.
  Future<void> setAutopilot(String crewId, bool enabled) async {
    await _crewsRef.doc(crewId).update({
      'autopilot_enabled': enabled,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
  }

  /// Regenerate the invite code.
  Future<String> regenerateInviteCode(String crewId) async {
    final code = _generateInviteCode();
    await _crewsRef.doc(crewId).update({
      'invite_code': code,
      'updated_at': Timestamp.fromDate(DateTime.now()),
    });
    return code;
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Reads / Streams
  // ─────────────────────────────────────────────────────────────────────────────

  /// Stream all crews the current user belongs to.
  Stream<List<GameDayCrew>> watchUserCrews() {
    final uid = _currentUid;
    if (uid == null) return Stream.value([]);

    return _crewsRef
        .where('member_uids', arrayContains: uid)
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => GameDayCrew.fromFirestore(d)).toList());
  }

  /// Stream a single crew by ID.
  Stream<GameDayCrew?> watchCrew(String crewId) {
    return _crewsRef.doc(crewId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return GameDayCrew.fromFirestore(doc);
    });
  }

  /// Find a crew for a specific team that the user is in.
  Future<GameDayCrew?> getCrewForTeam(String teamSlug) async {
    final uid = _currentUid;
    if (uid == null) return null;

    final query = await _crewsRef
        .where('member_uids', arrayContains: uid)
        .where('team_slug', isEqualTo: teamSlug)
        .limit(1)
        .get();

    if (query.docs.isEmpty) return null;
    return GameDayCrew.fromFirestore(query.docs.first);
  }

  // ─────────────────────────────────────────────────────────────────────────────
  // Helpers
  // ─────────────────────────────────────────────────────────────────────────────

  static String _generateInviteCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
    final rng = Random.secure();
    return List.generate(6, (_) => chars[rng.nextInt(chars.length)]).join();
  }

  static SportType _parseSport(String value) {
    return SportType.values.firstWhere(
      (e) => e.name == value || e.toJson() == value,
      orElse: () => SportType.nfl,
    );
  }
}
