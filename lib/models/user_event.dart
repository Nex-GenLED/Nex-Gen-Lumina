// lib/models/user_event.dart
//
// Represents a user-created, protected lighting event stored in the
// dedicated Firestore subcollection /users/{uid}/user_events/{eventId}.
//
// These events are NEVER modified, moved, or deleted by autopilot.
// Autopilot schedules around them precisely, leaving a 5-minute
// transition buffer on each side.
//
// Editing an autopilot event in the calendar converts it to a UserEvent,
// marking it as protected from future regeneration.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

class UserEvent {
  final String id;

  /// Absolute start timestamp (local time).
  final DateTime startTime;

  /// Absolute end timestamp (local time).
  final DateTime endTime;

  /// Display name shown in calendar.
  final String patternName;

  /// Full WLED JSON payload (null if event is "lights off").
  final Map<String, dynamic>? patternData;

  /// Optional note shown in the event detail card.
  final String? note;

  /// When the user created this event.
  final DateTime createdAt;

  /// If true, this was originally an autopilot event that the user edited.
  final bool convertedFromAutopilot;

  /// ID of the autopilot event this was converted from (for audit trail).
  final String? sourceAutopilotEventId;

  /// User events are always protected.
  bool get isProtected => true;

  const UserEvent({
    required this.id,
    required this.startTime,
    required this.endTime,
    required this.patternName,
    this.patternData,
    this.note,
    required this.createdAt,
    this.convertedFromAutopilot = false,
    this.sourceAutopilotEventId,
  });

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'start_time': Timestamp.fromDate(startTime),
        'end_time': Timestamp.fromDate(endTime),
        'pattern_name': patternName,
        if (patternData != null) 'pattern_data': patternData,
        if (note != null) 'note': note,
        'created_at': Timestamp.fromDate(createdAt),
        'is_protected': true,
        'converted_from_autopilot': convertedFromAutopilot,
        if (sourceAutopilotEventId != null)
          'source_autopilot_event_id': sourceAutopilotEventId,
      };

  factory UserEvent.fromFirestore(Map<String, dynamic> data) => UserEvent(
        id: data['id'] as String? ?? '',
        startTime: (data['start_time'] as Timestamp).toDate(),
        endTime: (data['end_time'] as Timestamp).toDate(),
        patternName: data['pattern_name'] as String? ?? 'My Event',
        patternData: data['pattern_data'] as Map<String, dynamic>?,
        note: data['note'] as String?,
        createdAt: (data['created_at'] as Timestamp).toDate(),
        convertedFromAutopilot:
            (data['converted_from_autopilot'] as bool?) ?? false,
        sourceAutopilotEventId:
            data['source_autopilot_event_id'] as String?,
      );

  UserEvent copyWith({
    String? patternName,
    DateTime? startTime,
    DateTime? endTime,
    Map<String, dynamic>? patternData,
    String? note,
  }) =>
      UserEvent(
        id: id,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        patternName: patternName ?? this.patternName,
        patternData: patternData ?? this.patternData,
        note: note ?? this.note,
        createdAt: createdAt,
        convertedFromAutopilot: convertedFromAutopilot,
        sourceAutopilotEventId: sourceAutopilotEventId,
      );

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// True if this event falls on [day] (by date, ignoring time).
  bool isOnDay(DateTime day) {
    final start = startTime;
    final end = endTime;
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    // Overlaps if event starts before day end AND ends after day start.
    return start.isBefore(dayEnd) && end.isAfter(dayStart);
  }

  Duration get duration => endTime.difference(startTime);

  @override
  String toString() =>
      'UserEvent($patternName, ${startTime.toLocal()} → ${endTime.toLocal()})';
}

// ---------------------------------------------------------------------------
// Lightweight game/holiday inputs for AutopilotScheduleGenerator
// ---------------------------------------------------------------------------

/// A sporting event fetched from ESPN or the user's sports schedule.
class GameEvent {
  final String teamName;
  final String opponentName;
  final DateTime gameStart;

  /// Estimated game end (default 3 hours if unknown).
  final DateTime gameEnd;

  /// Hex color string for the team's primary color (e.g. '#E31837').
  final String? teamColorHex;

  /// Hex color string for the team's secondary color.
  final String? teamColorSecondaryHex;

  /// The team's rank in the user's sportsTeamPriority list (0 = highest).
  final int teamPriority;

  const GameEvent({
    required this.teamName,
    required this.opponentName,
    required this.gameStart,
    required this.gameEnd,
    this.teamColorHex,
    this.teamColorSecondaryHex,
    this.teamPriority = 0,
  });

  /// True if this game falls on [day] (by date).
  bool isOnDay(DateTime day) {
    final dayStart = DateTime(day.year, day.month, day.day);
    final dayEnd = dayStart.add(const Duration(days: 1));
    return gameStart.isBefore(dayEnd) && gameEnd.isAfter(dayStart);
  }

  Color? get primaryColor {
    final hex = teamColorHex;
    if (hex == null || hex.length < 7) return null;
    try {
      return Color(int.parse('FF${hex.replaceFirst('#', '')}', radix: 16));
    } catch (_) {
      return null;
    }
  }

  @override
  String toString() => 'GameEvent($teamName vs $opponentName @ $gameStart)';
}

/// A holiday event occurring during the generation window.
class HolidayEvent {
  final String name;
  final DateTime date;

  /// Suggested palette color for the holiday (nullable for fallback).
  final Color? color;

  /// Suggested pattern name (nullable — generator picks if omitted).
  final String? suggestedPattern;

  const HolidayEvent({
    required this.name,
    required this.date,
    this.color,
    this.suggestedPattern,
  });

  bool isOnDay(DateTime day) =>
      date.year == day.year && date.month == day.month && date.day == day.day;

  @override
  String toString() => 'HolidayEvent($name, $date)';
}

/// Minimal weather forecast stub — extend when weather API integration lands.
class WeatherForecast {
  /// Keyed by date string 'YYYY-MM-DD'.
  final Map<String, WeatherDay> byDay;

  const WeatherForecast({required this.byDay});

  WeatherDay? forDay(DateTime day) {
    final key =
        '${day.year}-${day.month.toString().padLeft(2, '0')}-${day.day.toString().padLeft(2, '0')}';
    return byDay[key];
  }
}

class WeatherDay {
  final String condition; // 'clear', 'cloudy', 'rain', 'snow'
  final double tempHighF;
  final double tempLowF;

  const WeatherDay({
    required this.condition,
    required this.tempHighF,
    required this.tempLowF,
  });
}
