// lib/features/schedule/calendar_entry.dart
//
// Date-specific schedule entries for the calendar view.
// These sit on top of (and override) the recurring ScheduleItem system.
// Lumina AI writes here; the calendar reads from here.

import 'package:flutter/material.dart';

enum CalendarEntryType { auto, user, holiday }

class CalendarEntry {
  final String dateKey;       // 'YYYY-MM-DD'
  final String patternName;
  final Color? color;
  final String? onTime;       // '18:00' (24-hr)
  final String? offTime;      // '23:30' (24-hr)
  final int brightness;       // 0–100
  final CalendarEntryType type;
  final bool autopilot;
  final String? note;

  const CalendarEntry({
    required this.dateKey,
    required this.patternName,
    this.color,
    this.onTime,
    this.offTime,
    this.brightness = 85,
    this.type = CalendarEntryType.auto,
    this.autopilot = true,
    this.note,
  });

  CalendarEntry copyWith({
    String? patternName,
    Color? color,
    String? onTime,
    String? offTime,
    int? brightness,
    CalendarEntryType? type,
    bool? autopilot,
    String? note,
  }) =>
      CalendarEntry(
        dateKey: dateKey,
        patternName: patternName ?? this.patternName,
        color: color ?? this.color,
        onTime: onTime ?? this.onTime,
        offTime: offTime ?? this.offTime,
        brightness: brightness ?? this.brightness,
        type: type ?? this.type,
        autopilot: autopilot ?? this.autopilot,
        note: note ?? this.note,
      );

  /// Parse one change entry from Lumina AI JSON.
  static CalendarEntry? fromAiJson(Map<String, dynamic> json) {
    final dateKey = json['date'] as String?;
    if (dateKey == null || dateKey.isEmpty) return null;

    Color? color;
    final colorStr = json['color'] as String?;
    if (colorStr != null && colorStr.startsWith('#') && colorStr.length == 7) {
      try {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } catch (_) {}
    }

    final brightness = (json['brightness'] as num?)?.toInt() ?? 85;
    // 'Off' pattern → color null, brightness 0
    final isOff = (json['pattern'] as String?)?.toLowerCase() == 'off' ||
        (colorStr == null && brightness == 0);

    return CalendarEntry(
      dateKey: dateKey,
      patternName: isOff ? 'Off' : (json['pattern'] as String? ?? 'Custom'),
      color: isOff ? null : color,
      onTime: isOff ? null : json['onTime'] as String?,
      offTime: isOff ? null : json['offTime'] as String?,
      brightness: isOff ? 0 : brightness,
      type: CalendarEntryType.user,
      autopilot: false,
      note: json['note'] as String?,
    );
  }

  /// Display-friendly on→off time string.
  String get timeRangeLabel {
    if (onTime == null) return '—';
    if (offTime == null) return onTime!;
    return '$onTime → $offTime';
  }
}
