// lib/models/autopilot_event.dart
//
// Represents a single autopilot-generated lighting event stored in the
// dedicated Firestore subcollection /users/{uid}/autopilot_events/{eventId}.
//
// These events are NEVER user-created and can be freely replaced by weekly
// regeneration.  User-created protected events live in a separate subcollection
// (see user_event.dart).

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// Event type enum
// ---------------------------------------------------------------------------

enum AutopilotEventType {
  /// Covers a sporting event: pre-game ramp, active window, post-game wind-down.
  game,

  /// Matches a holiday from the user's holiday preferences.
  holiday,

  /// Seasonal palette (spring/summer/fall/winter) with no specific event.
  seasonal,

  /// User's Preferred White — default fill for evenings with no event.
  preferredWhite,

  /// Weather-influenced pattern (future integration).
  weather,
}

extension AutopilotEventTypeExt on AutopilotEventType {
  String get firestoreKey {
    switch (this) {
      case AutopilotEventType.game:
        return 'game';
      case AutopilotEventType.holiday:
        return 'holiday';
      case AutopilotEventType.seasonal:
        return 'seasonal';
      case AutopilotEventType.preferredWhite:
        return 'preferred_white';
      case AutopilotEventType.weather:
        return 'weather';
    }
  }

  static AutopilotEventType fromKey(String? key) {
    switch (key) {
      case 'game':
        return AutopilotEventType.game;
      case 'holiday':
        return AutopilotEventType.holiday;
      case 'seasonal':
        return AutopilotEventType.seasonal;
      case 'weather':
        return AutopilotEventType.weather;
      case 'preferred_white':
      default:
        return AutopilotEventType.preferredWhite;
    }
  }

  /// Human-readable label shown in calendar UI.
  String get displayLabel {
    switch (this) {
      case AutopilotEventType.game:
        return 'Game Day';
      case AutopilotEventType.holiday:
        return 'Holiday';
      case AutopilotEventType.seasonal:
        return 'Seasonal';
      case AutopilotEventType.preferredWhite:
        return 'Evening Glow';
      case AutopilotEventType.weather:
        return 'Weather';
    }
  }

  /// Icon used in calendar blocks.
  IconData get icon {
    switch (this) {
      case AutopilotEventType.game:
        return Icons.sports_football;
      case AutopilotEventType.holiday:
        return Icons.celebration;
      case AutopilotEventType.seasonal:
        return Icons.nature;
      case AutopilotEventType.preferredWhite:
        return Icons.wb_incandescent_outlined;
      case AutopilotEventType.weather:
        return Icons.cloud;
    }
  }

  /// Calendar block accent color (fallback — per-event colors take priority).
  Color get accentColor {
    switch (this) {
      case AutopilotEventType.game:
        return const Color(0xFF4CAF50);
      case AutopilotEventType.holiday:
        return const Color(0xFFE91E63);
      case AutopilotEventType.seasonal:
        return const Color(0xFFFF9800);
      case AutopilotEventType.preferredWhite:
        return const Color(0xFFFFF8E1);
      case AutopilotEventType.weather:
        return const Color(0xFF2196F3);
    }
  }
}

// ---------------------------------------------------------------------------
// AutopilotEvent model
// ---------------------------------------------------------------------------

class AutopilotEvent {
  final String id;

  /// The Monday that starts the week this event belongs to.
  final DateTime weekOf;

  /// Day of week: 1 = Monday … 7 = Sunday.
  final int dayOfWeek;

  /// Absolute start timestamp (local time).
  final DateTime startTime;

  /// Absolute end timestamp (local time).
  final DateTime endTime;

  /// Pattern library ID (null if no library pattern — e.g., Preferred White).
  final String? patternRef;

  /// Display name shown in the UI.
  final String patternName;

  /// Category of event that generated this slot.
  final AutopilotEventType eventType;

  /// Human-readable detail: e.g. "Chiefs vs Raiders", "Christmas Eve", "Warm White".
  final String sourceDetail;

  /// Autopilot events are never protected — only user events are.
  bool get isProtected => false;

  /// When this event was created by the generator.
  final DateTime generatedAt;

  /// Monotonically increasing counter: which Sunday 7PM run produced this event.
  final int weekGeneration;

  /// Full WLED JSON payload ready to apply to the device.
  final Map<String, dynamic>? wledPayload;

  /// Primary display color for the calendar block (ARGB).
  final Color? displayColor;

  /// Confidence score (0.0–1.0) from the generator — used for sorting.
  final double confidenceScore;

  const AutopilotEvent({
    required this.id,
    required this.weekOf,
    required this.dayOfWeek,
    required this.startTime,
    required this.endTime,
    this.patternRef,
    required this.patternName,
    required this.eventType,
    required this.sourceDetail,
    required this.generatedAt,
    required this.weekGeneration,
    this.wledPayload,
    this.displayColor,
    this.confidenceScore = 0.6,
  });

  // ── Serialization ──────────────────────────────────────────────────────────

  Map<String, dynamic> toFirestore() => {
        'id': id,
        'week_of': Timestamp.fromDate(weekOf),
        'day_of_week': dayOfWeek,
        'start_time': Timestamp.fromDate(startTime),
        'end_time': Timestamp.fromDate(endTime),
        'pattern_ref': patternRef,
        'pattern_name': patternName,
        'event_type': eventType.firestoreKey,
        'source_detail': sourceDetail,
        'is_protected': false,
        'generated_at': Timestamp.fromDate(generatedAt),
        'week_generation': weekGeneration,
        if (wledPayload != null) 'wled_payload': jsonEncode(wledPayload),
        // ignore: deprecated_member_use
        if (displayColor != null) 'display_color': displayColor!.value,
        'confidence_score': confidenceScore,
      };

  factory AutopilotEvent.fromFirestore(Map<String, dynamic> data) {
    Color? color;
    final colorVal = data['display_color'] as int?;
    if (colorVal != null) color = Color(colorVal);

    return AutopilotEvent(
      id: data['id'] as String? ?? '',
      weekOf: (data['week_of'] as Timestamp).toDate(),
      dayOfWeek: (data['day_of_week'] as num).toInt(),
      startTime: (data['start_time'] as Timestamp).toDate(),
      endTime: (data['end_time'] as Timestamp).toDate(),
      patternRef: data['pattern_ref'] as String?,
      patternName: data['pattern_name'] as String? ?? 'Untitled',
      eventType: AutopilotEventTypeExt.fromKey(data['event_type'] as String?),
      sourceDetail: data['source_detail'] as String? ?? '',
      generatedAt: (data['generated_at'] as Timestamp).toDate(),
      weekGeneration: (data['week_generation'] as num?)?.toInt() ?? 0,
      wledPayload: data['wled_payload'] is String
          ? (jsonDecode(data['wled_payload'] as String) as Map<String, dynamic>?)
          : data['wled_payload'] as Map<String, dynamic>?,
      displayColor: color,
      confidenceScore: (data['confidence_score'] as num?)?.toDouble() ?? 0.6,
    );
  }

  AutopilotEvent copyWith({
    String? patternName,
    DateTime? startTime,
    DateTime? endTime,
    AutopilotEventType? eventType,
    String? sourceDetail,
    Map<String, dynamic>? wledPayload,
    Color? displayColor,
    double? confidenceScore,
  }) =>
      AutopilotEvent(
        id: id,
        weekOf: weekOf,
        dayOfWeek: dayOfWeek,
        startTime: startTime ?? this.startTime,
        endTime: endTime ?? this.endTime,
        patternRef: patternRef,
        patternName: patternName ?? this.patternName,
        eventType: eventType ?? this.eventType,
        sourceDetail: sourceDetail ?? this.sourceDetail,
        generatedAt: generatedAt,
        weekGeneration: weekGeneration,
        wledPayload: wledPayload ?? this.wledPayload,
        displayColor: displayColor ?? this.displayColor,
        confidenceScore: confidenceScore ?? this.confidenceScore,
      );

  // ── Helpers ────────────────────────────────────────────────────────────────

  /// True if this event is currently active (startTime <= now < endTime).
  bool get isActiveNow {
    final now = DateTime.now();
    return !now.isBefore(startTime) && now.isBefore(endTime);
  }

  /// Duration of the event.
  Duration get duration => endTime.difference(startTime);

  @override
  String toString() =>
      'AutopilotEvent($patternName, $eventType, '
      '${startTime.toLocal()} → ${endTime.toLocal()})';
}
