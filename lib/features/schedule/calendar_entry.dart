// lib/features/schedule/calendar_entry.dart
//
// Date-specific schedule entries for the calendar view.
// These sit on top of (and override) the recurring ScheduleItem system.
// Lumina AI writes here; the calendar reads from here.

import 'package:flutter/material.dart';

enum CalendarEntryType { auto, user, holiday, autopilot }

/// Provenance labels for [CalendarEntry.sourceTag]. Additive — does not
/// change the priority/type system, just carries a hint that the night
/// composer uses to map an entry to one of the lower (3-6) tiers.
///
/// `null` means user-created (the entry was authored directly via the
/// calendar editor, not by an autopilot source).
class CalendarEntrySourceTag {
  static const gameDay = 'game_day';
  static const gameDayGroup = 'game_day_group';
  static const neighborhoodSync = 'neighborhood_sync';
  static const autopilot = 'autopilot';
}

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

  /// Provenance hint used by the night composer to disambiguate entries
  /// that share the same [CalendarEntryType.autopilot] type. Null for
  /// user-authored entries. See [CalendarEntrySourceTag] for valid values.
  final String? sourceTag;

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
    this.sourceTag,
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
    String? sourceTag,
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
        sourceTag: sourceTag ?? this.sourceTag,
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
      } catch (e) {
        debugPrint('Error in CalendarEntry.fromAiJson parsing color: $e');
      }
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
      sourceTag: json['sourceTag'] as String?,
    );
  }

  /// Serialize to Firestore-safe map.
  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'patternName': patternName,
        'color': color != null
            ? '#${color!.value.toRadixString(16).padLeft(8, '0').substring(2)}'
            : null,
        'onTime': onTime,
        'offTime': offTime,
        'brightness': brightness,
        'type': type.name,
        'autopilot': autopilot,
        'note': note,
        'sourceTag': sourceTag,
      };

  /// Deserialize from Firestore map.
  factory CalendarEntry.fromJson(Map<String, dynamic> json) {
    Color? color;
    final colorStr = json['color'] as String?;
    if (colorStr != null && colorStr.startsWith('#') && colorStr.length == 7) {
      try {
        color = Color(int.parse('FF${colorStr.substring(1)}', radix: 16));
      } catch (e) {
        debugPrint('Error in CalendarEntry.fromJson parsing color: $e');
      }
    }

    return CalendarEntry(
      dateKey: json['dateKey'] as String,
      patternName: json['patternName'] as String? ?? 'Custom',
      color: color,
      onTime: json['onTime'] as String?,
      offTime: json['offTime'] as String?,
      brightness: (json['brightness'] as num?)?.toInt() ?? 85,
      type: CalendarEntryType.values.firstWhere(
        (e) => e.name == json['type'],
        orElse: () => CalendarEntryType.user,
      ),
      autopilot: json['autopilot'] as bool? ?? false,
      note: json['note'] as String?,
      sourceTag: json['sourceTag'] as String?,
    );
  }

  /// Display-friendly on→off time string.
  String get timeRangeLabel {
    if (onTime == null) return '—';
    if (offTime == null) return onTime!;
    return '$onTime → $offTime';
  }
}
