// lib/features/autopilot/autopilot_schedule_generator.dart
//
// Core schedule generation engine for Lumina Autopilot.
//
// Responsibilities:
//   1. Accepts the target week, user profile, protected user events, sporting
//      events, holidays, and optional weather forecast.
//   2. Computes per-day "available time slots" by subtracting protected blocks
//      from the schedulable evening window (sunset → preferred off time).
//   3. Fills each slot with the highest-priority event: game > holiday >
//      seasonal > weather > preferred white.
//   4. Returns a List<AutopilotEvent> ready for persistence.
//
// This class deliberately has NO Flutter/Riverpod dependencies so it can be
// unit-tested in isolation and called from any context.


import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:nexgen_command/models/autopilot_event.dart';
import 'package:nexgen_command/models/user_event.dart';
import 'package:nexgen_command/models/user_model.dart';
import 'package:uuid/uuid.dart';

// ---------------------------------------------------------------------------
// TimeSlot — contiguous available window within a day
// ---------------------------------------------------------------------------

class TimeSlot {
  final DateTime start;
  final DateTime end;

  const TimeSlot({required this.start, required this.end});

  Duration get duration => end.difference(start);

  bool get isViable => duration.inMinutes >= 30;

  @override
  String toString() =>
      'TimeSlot(${_fmt(start)} → ${_fmt(end)}, ${duration.inMinutes} min)';
}

// ---------------------------------------------------------------------------
// AutopilotScheduleGenerator
// ---------------------------------------------------------------------------

class AutopilotScheduleGenerator {
  static const _uuid = Uuid();

  /// Transition buffer kept on each side of a protected user block so that
  /// an autopilot event never runs right up to the edge of a user event.
  static const Duration _transitionBuffer = Duration(minutes: 5);

  // ── Public entry point ──────────────────────────────────────────────────

  /// Generate a full week of autopilot events (Monday → Sunday).
  ///
  /// [weekStart] must be a Monday at 00:00:00 local time.
  /// [weekEnd] must be the following Sunday at 23:59:59 local time.
  ///
  /// Returns a list of [AutopilotEvent] objects sorted by startTime.
  /// Returns an empty list on any unrecoverable error.
  Future<List<AutopilotEvent>> generateWeek({
    required DateTime weekStart,
    required DateTime weekEnd,
    required UserModel profile,
    required List<UserEvent> protectedBlocks,
    required List<GameEvent> sportingEvents,
    required List<HolidayEvent> holidays,
    WeatherForecast? weather,
    int weekGeneration = 0,
  }) async {
    assert(weekStart.weekday == DateTime.monday,
        'weekStart must be a Monday, got weekday=${weekStart.weekday}');

    final events = <AutopilotEvent>[];

    try {
      for (var dayOffset = 0; dayOffset < 7; dayOffset++) {
        final day = weekStart.add(Duration(days: dayOffset));

        // 1. Collect protected blocks for this day.
        final dayProtected = protectedBlocks
            .where((e) => e.isOnDay(day))
            .toList()
          ..sort((a, b) => a.startTime.compareTo(b.startTime));

        // 2. Compute available time slots for this day.
        final slots = _getAvailableSlots(
          day: day,
          profile: profile,
          protectedBlocks: dayProtected,
        );

        // 3. For each available slot, pick the best event.
        final dayGames =
            sportingEvents.where((g) => g.isOnDay(day)).toList()
              ..sort((a, b) => a.teamPriority.compareTo(b.teamPriority));

        final dayHolidays = holidays.where((h) => h.isOnDay(day)).toList();

        for (final slot in slots) {
          final event = _selectEventForSlot(
            slot: slot,
            day: day,
            games: dayGames,
            holidays: dayHolidays,
            weather: weather,
            profile: profile,
            weekGeneration: weekGeneration,
            weekOf: weekStart,
          );
          if (event != null) events.add(event);
        }
      }

      events.sort((a, b) => a.startTime.compareTo(b.startTime));
    } catch (e, st) {
      debugPrint('❌ AutopilotScheduleGenerator.generateWeek failed: $e\n$st');
    }

    debugPrint(
        '✅ AutopilotScheduleGenerator: generated ${events.length} events '
        'for week of ${weekStart.toLocal()}');
    return events;
  }

  // ── Available slot computation ──────────────────────────────────────────

  /// Compute the list of contiguous available time slots for [day].
  ///
  /// The schedulable window starts at sunset (approximated or from profile)
  /// and ends at the user's preferred off time.  Protected blocks are
  /// subtracted with [_transitionBuffer] on each side.
  List<TimeSlot> _getAvailableSlots({
    required DateTime day,
    required UserModel profile,
    required List<UserEvent> protectedBlocks,
  }) {
    // --- Schedulable window start: sunset or preferred on time ---
    final windowStart = _schedulableStart(day, profile);
    // --- Schedulable window end: preferred off time ---
    final windowEnd = _schedulableEnd(day, profile);

    if (!windowEnd.isAfter(windowStart)) return [];

    // Build a list of blocked intervals (with buffers).
    final blocked = <_Interval>[];
    for (final userEvent in protectedBlocks) {
      // Clamp the block to within the schedulable window.
      final blockStart = userEvent.startTime
          .subtract(_transitionBuffer)
          .clamp(windowStart, windowEnd);
      final blockEnd = userEvent.endTime
          .add(_transitionBuffer)
          .clamp(windowStart, windowEnd);
      if (blockEnd.isAfter(blockStart)) {
        blocked.add(_Interval(blockStart, blockEnd));
      }
    }

    // Sort blocks chronologically.
    blocked.sort((a, b) => a.start.compareTo(b.start));

    // Compute gaps between the blocks.
    final slots = <TimeSlot>[];
    var cursor = windowStart;

    for (final block in blocked) {
      if (block.start.isAfter(cursor)) {
        final slot =
            TimeSlot(start: cursor, end: block.start);
        if (slot.isViable) slots.add(slot);
      }
      if (block.end.isAfter(cursor)) cursor = block.end;
    }

    // Remainder after all blocks.
    if (windowEnd.isAfter(cursor)) {
      final slot = TimeSlot(start: cursor, end: windowEnd);
      if (slot.isViable) slots.add(slot);
    }

    return slots;
  }

  // ── Event selection ─────────────────────────────────────────────────────

  /// Pick the highest-priority event for [slot].
  ///
  /// Priority: game > holiday > seasonal > weather > preferred white.
  AutopilotEvent? _selectEventForSlot({
    required TimeSlot slot,
    required DateTime day,
    required List<GameEvent> games,
    required List<HolidayEvent> holidays,
    required WeatherForecast? weather,
    required UserModel profile,
    required int weekGeneration,
    required DateTime weekOf,
  }) {
    // --- 1. Sporting event ---
    if (games.isNotEmpty) {
      final game = games.first; // already sorted by teamPriority
      return _buildGameEvent(
        slot: slot,
        game: game,
        profile: profile,
        weekGeneration: weekGeneration,
        weekOf: weekOf,
      );
    }

    // --- 2. Holiday ---
    if (holidays.isNotEmpty) {
      final holiday = holidays.first;
      return _buildHolidayEvent(
        slot: slot,
        holiday: holiday,
        profile: profile,
        weekGeneration: weekGeneration,
        weekOf: weekOf,
      );
    }

    // --- 3. Seasonal ---
    final seasonal = _buildSeasonalEvent(
      slot: slot,
      day: day,
      profile: profile,
      weekGeneration: weekGeneration,
      weekOf: weekOf,
    );
    if (seasonal != null) return seasonal;

    // --- 4. Weather (placeholder) ---
    // (weather integration reserved for future release)

    // --- 5. Preferred White (default fill) ---
    return _buildPreferredWhiteEvent(
      slot: slot,
      profile: profile,
      weekGeneration: weekGeneration,
      weekOf: weekOf,
    );
  }

  // ── Event builders ──────────────────────────────────────────────────────

  AutopilotEvent _buildGameEvent({
    required TimeSlot slot,
    required GameEvent game,
    required UserModel profile,
    required int weekGeneration,
    required DateTime weekOf,
  }) {
    // Pre-game ramp: 45 min before tip-off (or slot start, whichever is later).
    final preGameStart = game.gameStart.subtract(const Duration(minutes: 45));
    final eventStart =
        preGameStart.isAfter(slot.start) ? preGameStart : slot.start;
    // Post-game wind-down: 20 min after estimated end.
    final postGameEnd = game.gameEnd.add(const Duration(minutes: 20));
    final eventEnd = postGameEnd.isBefore(slot.end) ? postGameEnd : slot.end;

    final teamColor = game.primaryColor;
    final teamColorHex = game.teamColorHex ?? '#4CAF50';

    // Build a simple solid team-color WLED payload.
    final wledPayload = _solidColorPayload(
      hex: teamColorHex,
      brightness: _vibeBrightness(profile.vibeLevel ?? 0.6),
      effectId: 65, // "Breathe" effect — good for game day
      speed: 60,
      intensity: 128,
    );

    return AutopilotEvent(
      id: _uuid.v4(),
      weekOf: weekOf,
      dayOfWeek: slot.start.weekday,
      startTime: eventStart.isAfter(slot.end) ? slot.start : eventStart,
      endTime: eventEnd.isBefore(slot.start) ? slot.end : eventEnd,
      patternName: '${game.teamName} Game Day',
      eventType: AutopilotEventType.game,
      sourceDetail: '${game.teamName} vs ${game.opponentName}',
      generatedAt: DateTime.now(),
      weekGeneration: weekGeneration,
      wledPayload: wledPayload,
      displayColor: teamColor ?? const Color(0xFF4CAF50),
      confidenceScore: 0.90 - (game.teamPriority * 0.05),
    );
  }

  AutopilotEvent _buildHolidayEvent({
    required TimeSlot slot,
    required HolidayEvent holiday,
    required UserModel profile,
    required int weekGeneration,
    required DateTime weekOf,
  }) {
    final patternName = holiday.suggestedPattern ?? '${holiday.name} Colors';
    final color = holiday.color ?? const Color(0xFFE91E63);
    final colorHex = _colorToHex(color);

    final wledPayload = _solidColorPayload(
      hex: colorHex,
      brightness: _vibeBrightness(profile.vibeLevel ?? 0.6),
      effectId: 11, // "Twinkle Up" — festive
      speed: 80,
      intensity: 180,
    );

    return AutopilotEvent(
      id: _uuid.v4(),
      weekOf: weekOf,
      dayOfWeek: slot.start.weekday,
      startTime: slot.start,
      endTime: slot.end,
      patternName: patternName,
      eventType: AutopilotEventType.holiday,
      sourceDetail: holiday.name,
      generatedAt: DateTime.now(),
      weekGeneration: weekGeneration,
      wledPayload: wledPayload,
      displayColor: color,
      confidenceScore: 0.88,
    );
  }

  AutopilotEvent? _buildSeasonalEvent({
    required TimeSlot slot,
    required DateTime day,
    required UserModel profile,
    required int weekGeneration,
    required DateTime weekOf,
  }) {
    final season = _currentSeason(day);
    if (season == null) return null;

    return AutopilotEvent(
      id: _uuid.v4(),
      weekOf: weekOf,
      dayOfWeek: slot.start.weekday,
      startTime: slot.start,
      endTime: slot.end,
      patternName: season.patternName,
      eventType: AutopilotEventType.seasonal,
      sourceDetail: season.label,
      generatedAt: DateTime.now(),
      weekGeneration: weekGeneration,
      wledPayload: _solidColorPayload(
        hex: season.colorHex,
        brightness: _vibeBrightness(profile.vibeLevel ?? 0.5),
        effectId: 0, // Solid — minimal, seasonal
        speed: 128,
        intensity: 128,
      ),
      displayColor: season.color,
      confidenceScore: 0.72,
    );
  }

  AutopilotEvent _buildPreferredWhiteEvent({
    required TimeSlot slot,
    required UserModel profile,
    required int weekGeneration,
    required DateTime weekOf,
  }) {
    // Use preferred white payload if available, otherwise a warm white default.
    final payload = _buildPreferredWhitePayload(profile);

    return AutopilotEvent(
      id: _uuid.v4(),
      weekOf: weekOf,
      dayOfWeek: slot.start.weekday,
      startTime: slot.start,
      endTime: slot.end,
      patternName: 'Evening Glow',
      eventType: AutopilotEventType.preferredWhite,
      sourceDetail: 'Warm White',
      generatedAt: DateTime.now(),
      weekGeneration: weekGeneration,
      wledPayload: payload,
      displayColor: const Color(0xFFFFF3E0),
      confidenceScore: 0.60,
    );
  }

  // ── Schedulable window helpers ───────────────────────────────────────────

  /// Returns the start of the schedulable window for [day].
  ///
  /// Approximates sunset as 18:00 local time.  When proper sunrise/sunset
  /// data is integrated, replace this with the computed value for the user's
  /// lat/lng.
  DateTime _schedulableStart(DateTime day, UserModel profile) {
    // Approximate sunset: 18:00 in winter, 20:00 in summer.
    final month = day.month;
    int sunsetHour;
    if (month >= 3 && month <= 5) {
      sunsetHour = 19; // Spring
    } else if (month >= 6 && month <= 8) {
      sunsetHour = 20; // Summer
    } else if (month >= 9 && month <= 11) {
      sunsetHour = 18; // Fall
    } else {
      sunsetHour = 17; // Winter
    }
    return DateTime(day.year, day.month, day.day, sunsetHour, 0, 0);
  }

  /// Returns the end of the schedulable window for [day].
  ///
  /// Uses the user's preferred off time (encoded as minutes past midnight
  /// on quiet_hours_start), or sensible weekday/weekend defaults.
  DateTime _schedulableEnd(DateTime day, UserModel profile) {
    final isWeekend =
        day.weekday == DateTime.friday ||
        day.weekday == DateTime.saturday ||
        day.weekday == DateTime.sunday;

    // If user has HOA quiet hours configured, respect them.
    if (profile.hoaComplianceEnabled == true &&
        profile.quietHoursStartMinutes != null) {
      final qStart = profile.quietHoursStartMinutes!;
      final h = qStart ~/ 60;
      final m = qStart % 60;
      return DateTime(day.year, day.month, day.day, h, m, 0);
    }

    // Defaults: 10:30 PM weeknights, 11:30 PM weekends.
    return isWeekend
        ? DateTime(day.year, day.month, day.day, 23, 30, 0)
        : DateTime(day.year, day.month, day.day, 22, 30, 0);
  }

  // ── WLED payload builders ────────────────────────────────────────────────

  Map<String, dynamic> _solidColorPayload({
    required String hex,
    required int brightness,
    int effectId = 0,
    int speed = 128,
    int intensity = 128,
  }) {
    final rgb = _hexToRgb(hex);
    return {
      'on': true,
      'bri': brightness.clamp(0, 255),
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'pal': 0,
          'col': [
            [rgb[0], rgb[1], rgb[2], 0]
          ],
        }
      ],
    };
  }

  Map<String, dynamic> _buildPreferredWhitePayload(UserModel profile) {
    final stored = profile.preferredWhitePrimary;
    if (stored != null && stored.isNotEmpty) {
      // Wrap the stored preferred white WLED payload in a standard envelope.
      return {
        'on': true,
        'bri': _vibeBrightness(profile.vibeLevel ?? 0.5),
        'seg': stored['seg'] ?? [
          {
            'fx': 0,
            'sx': 128,
            'ix': 128,
            'pal': 0,
            'col': [
              [255, 223, 186, 200] // Default warm white RGBW
            ],
          }
        ],
      };
    }

    // Fallback: warm white RGBW
    return {
      'on': true,
      'bri': _vibeBrightness(profile.vibeLevel ?? 0.5),
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'col': [
            [255, 223, 186, 200]
          ],
        }
      ],
    };
  }

  // ── Utility helpers ──────────────────────────────────────────────────────

  int _vibeBrightness(double vibeLevel) {
    // 0.0 (subtle) → 100 bri, 1.0 (bold) → 230 bri
    return (100 + (vibeLevel * 130)).round().clamp(80, 255);
  }

  List<int> _hexToRgb(String hex) {
    final h = hex.replaceFirst('#', '');
    if (h.length < 6) return [255, 255, 255];
    try {
      return [
        int.parse(h.substring(0, 2), radix: 16),
        int.parse(h.substring(2, 4), radix: 16),
        int.parse(h.substring(4, 6), radix: 16),
      ];
    } catch (_) {
      return [255, 255, 255];
    }
  }

  String _colorToHex(Color color) {
    final r = (color.r * 255.0).round().clamp(0, 255);
    final g = (color.g * 255.0).round().clamp(0, 255);
    final b = (color.b * 255.0).round().clamp(0, 255);
    return '#${r.toRadixString(16).padLeft(2, '0')}'
        '${g.toRadixString(16).padLeft(2, '0')}'
        '${b.toRadixString(16).padLeft(2, '0')}';
  }

  _SeasonInfo? _currentSeason(DateTime day) {
    final month = day.month;
    if (month == 12 || month <= 2) {
      return _SeasonInfo(
        label: 'Winter',
        patternName: 'Winter Blues',
        colorHex: '#1A6BAD',
        color: const Color(0xFF1A6BAD),
      );
    } else if (month <= 5) {
      return _SeasonInfo(
        label: 'Spring',
        patternName: 'Spring Bloom',
        colorHex: '#66BB6A',
        color: const Color(0xFF66BB6A),
      );
    } else if (month <= 8) {
      return _SeasonInfo(
        label: 'Summer',
        patternName: 'Summer Glow',
        colorHex: '#FFA726',
        color: const Color(0xFFFFA726),
      );
    } else if (month <= 11) {
      return _SeasonInfo(
        label: 'Fall',
        patternName: 'Autumn Ember',
        colorHex: '#BF360C',
        color: const Color(0xFFBF360C),
      );
    }
    return null;
  }
}

// ── Internal helpers ─────────────────────────────────────────────────────────

class _Interval {
  final DateTime start;
  final DateTime end;
  const _Interval(this.start, this.end);
}

class _SeasonInfo {
  final String label;
  final String patternName;
  final String colorHex;
  final Color color;
  const _SeasonInfo({
    required this.label,
    required this.patternName,
    required this.colorHex,
    required this.color,
  });
}

String _fmt(DateTime dt) =>
    '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';

extension _DateTimeClamp on DateTime {
  DateTime clamp(DateTime min, DateTime max) {
    if (isBefore(min)) return min;
    if (isAfter(max)) return max;
    return this;
  }
}

// ── Static helpers used by the repository ───────────────────────────────────

/// Returns the Monday at 00:00:00 local time that starts the upcoming week.
///
/// If [from] is already a Monday and it's before [cutoffHour] local time,
/// returns the NEXT Monday (so we never generate for a partial week).
DateTime upcomingWeekStart(DateTime from) {
  // Advance to the next Monday.
  int daysUntilMonday = (DateTime.monday - from.weekday + 7) % 7;
  // If today IS Monday, use next Monday (never generate for a partial week).
  if (daysUntilMonday == 0) daysUntilMonday = 7;
  final monday = DateTime(from.year, from.month, from.day)
      .add(Duration(days: daysUntilMonday));
  return monday;
}

/// Returns the Sunday at 23:59:59 local time that ends the week starting
/// on [monday].
DateTime weekEndFor(DateTime monday) =>
    monday
        .add(const Duration(days: 6))
        .copyWith(hour: 23, minute: 59, second: 59, millisecond: 999);
