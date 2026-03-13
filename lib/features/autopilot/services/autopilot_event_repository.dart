// lib/features/autopilot/services/autopilot_event_repository.dart
//
// Firestore persistence layer for autopilot-generated events and
// user-created protected events.
//
// Collections
//   /users/{uid}/autopilot_events/{eventId}  — autopilot events (freely writable)
//   /users/{uid}/user_events/{eventId}        — protected user events (never touched by autopilot)
//
// All reads use Source.server to avoid stale cache data (per the Firestore fix
// already implemented in the project).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_schedule_generator.dart';
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/models/user_event.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// Repository
// ---------------------------------------------------------------------------

class AutopilotEventRepository {
  final FirebaseFirestore _db;
  static const _uuid = Uuid();

  AutopilotEventRepository({FirebaseFirestore? db})
      : _db = db ?? FirebaseFirestore.instance;

  // ── Collection references ────────────────────────────────────────────────

  CollectionReference<Map<String, dynamic>> _autopilotCol(String uid) =>
      _db.collection('users').doc(uid).collection('autopilot_events');

  CollectionReference<Map<String, dynamic>> _userEventsCol(String uid) =>
      _db.collection('users').doc(uid).collection('user_events');

  // ──────────────────────────────────────────────────────────────────────────
  // AUTOPILOT EVENTS
  // ──────────────────────────────────────────────────────────────────────────

  /// Fetch all autopilot events for the week starting on [weekOf] (a Monday).
  ///
  /// Uses Source.server to guarantee fresh data.
  Future<List<AutopilotEvent>> fetchWeekEvents(
      String uid, DateTime weekOf) async {
    try {
      final snap = await _autopilotCol(uid)
          .where('week_of',
              isEqualTo: Timestamp.fromDate(
                DateTime(weekOf.year, weekOf.month, weekOf.day),
              ))
          .get(const GetOptions(source: Source.server));

      return snap.docs
          .map((d) => AutopilotEvent.fromFirestore(d.data()))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.fetchWeekEvents: $e');
      return [];
    }
  }

  /// Delete all autopilot events for [weekOf] then write [events] in a batch.
  ///
  /// This is the "full replace" used by weekly regeneration.  User events in
  /// the separate subcollection are never touched.
  Future<bool> replaceWeekEvents(
      String uid, DateTime weekOf, List<AutopilotEvent> events) async {
    try {
      final weekStart =
          DateTime(weekOf.year, weekOf.month, weekOf.day);

      // 1. Delete existing autopilot events for this week.
      final existing = await _autopilotCol(uid)
          .where('week_of',
              isEqualTo: Timestamp.fromDate(weekStart))
          .get(const GetOptions(source: Source.server));

      final batch = _db.batch();
      for (final doc in existing.docs) {
        batch.delete(doc.reference);
      }

      // 2. Write new events.
      for (final event in events) {
        final ref = _autopilotCol(uid).doc(event.id);
        batch.set(ref, event.toFirestore());
      }

      await batch.commit();

      debugPrint(
          '✅ AutopilotEventRepository: replaced ${existing.docs.length} old '
          'events with ${events.length} new events for week of $weekStart');
      return true;
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.replaceWeekEvents: $e');
      return false;
    }
  }

  /// Write events for a brand-new user (initial generation).
  /// Equivalent to replaceWeekEvents but with a clearer intent at call sites.
  Future<bool> saveInitialWeekEvents(
      String uid, List<AutopilotEvent> events) async {
    if (events.isEmpty) return true;
    final weekOf = events.first.weekOf;
    return replaceWeekEvents(uid, weekOf, events);
  }

  /// Delete a single autopilot event (e.g., user removed it from the calendar).
  Future<void> deleteEvent(String uid, String eventId) async {
    try {
      await _autopilotCol(uid).doc(eventId).delete();
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.deleteEvent: $e');
    }
  }

  /// Update a single autopilot event in-place (e.g., user tweaked time or pattern).
  Future<void> updateEvent(String uid, AutopilotEvent event) async {
    try {
      await _autopilotCol(uid)
          .doc(event.id)
          .set(event.toFirestore(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.updateEvent: $e');
    }
  }

  /// Stream of autopilot events for this week — for real-time calendar updates.
  Stream<List<AutopilotEvent>> streamWeekEvents(
      String uid, DateTime weekOf) {
    final weekStart =
        DateTime(weekOf.year, weekOf.month, weekOf.day);
    return _autopilotCol(uid)
        .where('week_of',
            isEqualTo: Timestamp.fromDate(weekStart))
        .snapshots()
        .map((snap) => snap.docs
            .map((d) => AutopilotEvent.fromFirestore(d.data()))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime)));
  }

  // ──────────────────────────────────────────────────────────────────────────
  // USER EVENTS (protected)
  // ──────────────────────────────────────────────────────────────────────────

  /// Fetch all protected user events for a given week.
  Future<List<UserEvent>> fetchUserEventsForWeek(
      String uid, DateTime weekStart, DateTime weekEnd) async {
    try {
      final snap = await _userEventsCol(uid)
          .where('start_time',
              isGreaterThanOrEqualTo: Timestamp.fromDate(weekStart))
          .where('start_time',
              isLessThanOrEqualTo: Timestamp.fromDate(weekEnd))
          .get(const GetOptions(source: Source.server));

      return snap.docs
          .map((d) => UserEvent.fromFirestore(d.data()))
          .toList()
        ..sort((a, b) => a.startTime.compareTo(b.startTime));
    } catch (e) {
      debugPrint(
          '❌ AutopilotEventRepository.fetchUserEventsForWeek: $e');
      return [];
    }
  }

  /// Stream of user events for the calendar view.
  Stream<List<UserEvent>> streamUserEvents(String uid) {
    return _userEventsCol(uid)
        .orderBy('start_time')
        .snapshots()
        .map((snap) =>
            snap.docs.map((d) => UserEvent.fromFirestore(d.data())).toList());
  }

  /// Add a new user-created protected event.
  Future<String?> addUserEvent(String uid, UserEvent event) async {
    try {
      final ref = _userEventsCol(uid).doc(event.id);
      await ref.set(event.toFirestore());
      return event.id;
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.addUserEvent: $e');
      return null;
    }
  }

  /// Delete a user event (removes protection — lets autopilot reclaim the slot).
  Future<void> deleteUserEvent(String uid, String eventId) async {
    try {
      await _userEventsCol(uid).doc(eventId).delete();
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.deleteUserEvent: $e');
    }
  }

  /// Convert an autopilot event into a protected user event.
  ///
  /// This is called when the user edits an autopilot block in the calendar.
  /// The original autopilot event is deleted; a new UserEvent is created
  /// with `convertedFromAutopilot = true`.
  Future<UserEvent?> convertToUserEvent(
      String uid, AutopilotEvent autopilotEvent,
      {String? newPatternName,
      Map<String, dynamic>? newPatternData}) async {
    try {
      final userEvent = UserEvent(
        id: _uuid.v4(),
        startTime: autopilotEvent.startTime,
        endTime: autopilotEvent.endTime,
        patternName: newPatternName ?? autopilotEvent.patternName,
        patternData: newPatternData ?? autopilotEvent.wledPayload,
        createdAt: DateTime.now(),
        convertedFromAutopilot: true,
        sourceAutopilotEventId: autopilotEvent.id,
      );

      final batch = _db.batch();
      // Remove the autopilot event.
      batch.delete(_autopilotCol(uid).doc(autopilotEvent.id));
      // Create the protected user event.
      batch.set(_userEventsCol(uid).doc(userEvent.id), userEvent.toFirestore());
      await batch.commit();

      return userEvent;
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.convertToUserEvent: $e');
      return null;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CHANGE DETECTION
  // ──────────────────────────────────────────────────────────────────────────

  /// Compare newly generated events against what's already persisted.
  ///
  /// Returns only the events that are genuinely different (new, changed time,
  /// or changed pattern) so the batch write is minimal.
  Future<({List<AutopilotEvent> toWrite, List<String> toDelete})>
      computeDiff(
    String uid,
    DateTime weekOf,
    List<AutopilotEvent> newEvents,
  ) async {
    final existing = await fetchWeekEvents(uid, weekOf);

    // Index existing events by sourceDetail + dayOfWeek for comparison.
    final existingIndex = <String, AutopilotEvent>{};
    for (final e in existing) {
      existingIndex['${e.dayOfWeek}:${e.sourceDetail}'] = e;
    }

    final newIndex = <String, AutopilotEvent>{};
    for (final e in newEvents) {
      newIndex['${e.dayOfWeek}:${e.sourceDetail}'] = e;
    }

    final toWrite = <AutopilotEvent>[];
    final toDelete = <String>[];

    // Find events to write (new or changed).
    for (final entry in newIndex.entries) {
      final existing_ = existingIndex[entry.key];
      if (existing_ == null) {
        toWrite.add(entry.value); // New event
      } else {
        // Changed if time or pattern differs.
        final timeChanged =
            entry.value.startTime != existing_.startTime ||
                entry.value.endTime != existing_.endTime;
        final patternChanged =
            entry.value.patternName != existing_.patternName;
        if (timeChanged || patternChanged) {
          toWrite.add(entry.value); // Updated event
          toDelete.add(existing_.id); // Remove old
        }
      }
    }

    // Find events to delete (no longer in new generation).
    for (final entry in existingIndex.entries) {
      if (!newIndex.containsKey(entry.key)) {
        toDelete.add(entry.value.id);
      }
    }

    return (toWrite: toWrite, toDelete: toDelete);
  }

  /// Apply a diff result to Firestore in a single batch.
  Future<bool> applyDiff(
    String uid,
    ({List<AutopilotEvent> toWrite, List<String> toDelete}) diff,
  ) async {
    if (diff.toWrite.isEmpty && diff.toDelete.isEmpty) {
      debugPrint('✅ AutopilotEventRepository.applyDiff: nothing changed');
      return true;
    }

    try {
      final batch = _db.batch();

      for (final id in diff.toDelete) {
        batch.delete(_autopilotCol(uid).doc(id));
      }
      for (final event in diff.toWrite) {
        batch.set(_autopilotCol(uid).doc(event.id), event.toFirestore());
      }

      await batch.commit();
      debugPrint(
          '✅ AutopilotEventRepository.applyDiff: wrote ${diff.toWrite.length}, '
          'deleted ${diff.toDelete.length}');
      return true;
    } catch (e) {
      debugPrint('❌ AutopilotEventRepository.applyDiff: $e');
      return false;
    }
  }

  // ──────────────────────────────────────────────────────────────────────────
  // FULL ORCHESTRATION HELPERS
  // ──────────────────────────────────────────────────────────────────────────

  /// Run the full weekly regeneration pipeline:
  ///   1. Fetch protected user events for the target week.
  ///   2. Generate new autopilot events (via [AutopilotScheduleGenerator]).
  ///   3. Compute diff vs existing autopilot events.
  ///   4. Apply the diff.
  ///
  /// Pass [sportingEvents], [holidays], and [weather] pre-fetched by the
  /// calling service so this method stays pure (testable).
  Future<List<AutopilotEvent>> runWeeklyRegeneration({
    required String uid,
    required UserModel profile,
    required List<GameEvent> sportingEvents,
    required List<HolidayEvent> holidays,
    WeatherForecast? weather,
    int weekGeneration = 0,
  }) async {
    final weekStart = upcomingWeekStart(DateTime.now());
    final weekEnd = weekEndFor(weekStart);

    debugPrint(
        '🔄 AutopilotEventRepository: regenerating week of $weekStart');

    // 1. Fetch protected user events.
    final protected =
        await fetchUserEventsForWeek(uid, weekStart, weekEnd);
    debugPrint('🔒 Protected user events: ${protected.length}');

    // 2. Generate.
    final generator = AutopilotScheduleGenerator();
    final newEvents = await generator.generateWeek(
      weekStart: weekStart,
      weekEnd: weekEnd,
      profile: profile,
      protectedBlocks: protected,
      sportingEvents: sportingEvents,
      holidays: holidays,
      weather: weather,
      weekGeneration: weekGeneration,
    );

    // 3. Diff.
    final diff = await computeDiff(uid, weekStart, newEvents);

    // 4. Apply.
    await applyDiff(uid, diff);

    // Return the full new event list for notifications / UI.
    return newEvents;
  }
}

// ---------------------------------------------------------------------------
// Riverpod provider
// ---------------------------------------------------------------------------

final autopilotEventRepositoryProvider =
    Provider<AutopilotEventRepository>((ref) {
  return AutopilotEventRepository();
});
