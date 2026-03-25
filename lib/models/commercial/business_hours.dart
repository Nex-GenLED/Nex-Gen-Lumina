import 'package:flutter/material.dart';

// ---------------------------------------------------------------------------
// DayOfWeek
// ---------------------------------------------------------------------------

/// Days of the week in ISO order (Monday = 1).
enum DayOfWeek {
  monday,
  tuesday,
  wednesday,
  thursday,
  friday,
  saturday,
  sunday,
}

extension DayOfWeekX on DayOfWeek {
  /// ISO weekday number (Monday = 1 … Sunday = 7).
  int get isoWeekday => index + 1;

  String get displayName {
    switch (this) {
      case DayOfWeek.monday:
        return 'Monday';
      case DayOfWeek.tuesday:
        return 'Tuesday';
      case DayOfWeek.wednesday:
        return 'Wednesday';
      case DayOfWeek.thursday:
        return 'Thursday';
      case DayOfWeek.friday:
        return 'Friday';
      case DayOfWeek.saturday:
        return 'Saturday';
      case DayOfWeek.sunday:
        return 'Sunday';
    }
  }

  String get shortName => displayName.substring(0, 3);
}

DayOfWeek dayOfWeekFromIso(int isoWeekday) {
  return DayOfWeek.values[(isoWeekday - 1).clamp(0, 6)];
}

DayOfWeek _parseDayOfWeek(String? value) {
  for (final d in DayOfWeek.values) {
    if (d.name == value) return d;
  }
  return DayOfWeek.monday;
}

// ---------------------------------------------------------------------------
// DaySchedule — hours for a single day
// ---------------------------------------------------------------------------

/// Schedule for a single day: open/closed flag plus open & close times.
/// Times are stored as "HH:mm" strings for Firestore compatibility.
class DaySchedule {
  final bool isOpen;
  final TimeOfDay openTime;
  final TimeOfDay closeTime;

  const DaySchedule({
    this.isOpen = false,
    this.openTime = const TimeOfDay(hour: 9, minute: 0),
    this.closeTime = const TimeOfDay(hour: 17, minute: 0),
  });

  factory DaySchedule.fromJson(Map<String, dynamic> json) {
    return DaySchedule(
      isOpen: (json['is_open'] as bool?) ?? false,
      openTime: _parseTimeOfDay(json['open_time'] as String?) ??
          const TimeOfDay(hour: 9, minute: 0),
      closeTime: _parseTimeOfDay(json['close_time'] as String?) ??
          const TimeOfDay(hour: 17, minute: 0),
    );
  }

  Map<String, dynamic> toJson() => {
        'is_open': isOpen,
        'open_time': _timeToString(openTime),
        'close_time': _timeToString(closeTime),
      };

  DaySchedule copyWith({
    bool? isOpen,
    TimeOfDay? openTime,
    TimeOfDay? closeTime,
  }) {
    return DaySchedule(
      isOpen: isOpen ?? this.isOpen,
      openTime: openTime ?? this.openTime,
      closeTime: closeTime ?? this.closeTime,
    );
  }

  /// Total open minutes on this day. Returns 0 if closed.
  int get openMinutes {
    if (!isOpen) return 0;
    final open = openTime.hour * 60 + openTime.minute;
    final close = closeTime.hour * 60 + closeTime.minute;
    if (close > open) return close - open;
    // Overnight span (e.g. 22:00 – 02:00).
    return (24 * 60 - open) + close;
  }

  // -- helpers ---------------------------------------------------------------

  static TimeOfDay? _parseTimeOfDay(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _timeToString(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
}

// ---------------------------------------------------------------------------
// BusinessHours — full weekly schedule with buffers
// ---------------------------------------------------------------------------

/// Weekly operating hours with pre-open buffer and post-close wind-down.
class BusinessHours {
  final Map<DayOfWeek, DaySchedule> weeklySchedule;
  final int preOpenBufferMinutes;
  final int postCloseWindDownMinutes;

  const BusinessHours({
    this.weeklySchedule = const {},
    this.preOpenBufferMinutes = 30,
    this.postCloseWindDownMinutes = 15,
  });

  factory BusinessHours.fromJson(Map<String, dynamic> json) {
    final schedMap = <DayOfWeek, DaySchedule>{};
    final raw = json['weekly_schedule'] as Map<String, dynamic>?;
    if (raw != null) {
      for (final entry in raw.entries) {
        final day = _parseDayOfWeek(entry.key);
        schedMap[day] =
            DaySchedule.fromJson(entry.value as Map<String, dynamic>);
      }
    }
    return BusinessHours(
      weeklySchedule: schedMap,
      preOpenBufferMinutes:
          (json['pre_open_buffer_minutes'] as num?)?.toInt() ?? 30,
      postCloseWindDownMinutes:
          (json['post_close_wind_down_minutes'] as num?)?.toInt() ?? 15,
    );
  }

  Map<String, dynamic> toJson() => {
        'weekly_schedule':
            weeklySchedule.map((k, v) => MapEntry(k.name, v.toJson())),
        'pre_open_buffer_minutes': preOpenBufferMinutes,
        'post_close_wind_down_minutes': postCloseWindDownMinutes,
      };

  BusinessHours copyWith({
    Map<DayOfWeek, DaySchedule>? weeklySchedule,
    int? preOpenBufferMinutes,
    int? postCloseWindDownMinutes,
  }) {
    return BusinessHours(
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      preOpenBufferMinutes:
          preOpenBufferMinutes ?? this.preOpenBufferMinutes,
      postCloseWindDownMinutes:
          postCloseWindDownMinutes ?? this.postCloseWindDownMinutes,
    );
  }

  // -- runtime helpers -------------------------------------------------------

  /// The [DaySchedule] for today.
  DaySchedule? get todaySchedule {
    final today = dayOfWeekFromIso(DateTime.now().weekday);
    return weeklySchedule[today];
  }

  /// Whether the business is currently within its open hours (ignoring
  /// holidays — use [BusinessHoursService.isBusinessOpen] for the full check).
  bool isCurrentlyOpen() {
    final sched = todaySchedule;
    if (sched == null || !sched.isOpen) return false;
    final now = DateTime.now();
    final nowMin = now.hour * 60 + now.minute;
    final openMin = sched.openTime.hour * 60 + sched.openTime.minute;
    final closeMin = sched.closeTime.hour * 60 + sched.closeTime.minute;
    if (closeMin > openMin) {
      return nowMin >= openMin && nowMin < closeMin;
    }
    // Overnight span.
    return nowMin >= openMin || nowMin < closeMin;
  }

  /// Next opening [DateTime] from now. Scans up to 7 days ahead.
  DateTime? nextOpenTime() {
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final target = now.add(Duration(days: i));
      final day = dayOfWeekFromIso(target.weekday);
      final sched = weeklySchedule[day];
      if (sched == null || !sched.isOpen) continue;
      final candidate = DateTime(
        target.year,
        target.month,
        target.day,
        sched.openTime.hour,
        sched.openTime.minute,
      );
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }

  /// Next closing [DateTime] from now. Scans up to 7 days ahead.
  DateTime? nextCloseTime() {
    final now = DateTime.now();
    for (var i = 0; i < 7; i++) {
      final target = now.add(Duration(days: i));
      final day = dayOfWeekFromIso(target.weekday);
      final sched = weeklySchedule[day];
      if (sched == null || !sched.isOpen) continue;
      var candidate = DateTime(
        target.year,
        target.month,
        target.day,
        sched.closeTime.hour,
        sched.closeTime.minute,
      );
      // If close is before open, the close is on the next calendar day.
      final openMin = sched.openTime.hour * 60 + sched.openTime.minute;
      final closeMin = sched.closeTime.hour * 60 + sched.closeTime.minute;
      if (closeMin <= openMin) {
        candidate = candidate.add(const Duration(days: 1));
      }
      if (candidate.isAfter(now)) return candidate;
    }
    return null;
  }
}
