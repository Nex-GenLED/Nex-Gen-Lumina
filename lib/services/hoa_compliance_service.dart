import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/user_model.dart';

/// Service for enforcing HOA compliance rules on autopilot schedules.
///
/// Handles:
/// - Quiet hours enforcement (no light changes during specified times)
/// - Seasonal color windows (colors only allowed during defined periods)
/// - Brightness limits during late hours
/// - Vibe level restrictions
class HoaComplianceService {
  final Ref _ref;

  HoaComplianceService(this._ref);

  /// Check if a light change is allowed at the given time.
  ///
  /// Returns true if the time falls outside quiet hours.
  bool isTimeAllowed(DateTime time, UserModel profile) {
    // If HOA compliance is not enabled, all times are allowed
    if (profile.hoaComplianceEnabled != true) {
      return true;
    }

    return !_isInQuietHours(time, profile);
  }

  /// Check if the current time falls within quiet hours.
  bool _isInQuietHours(DateTime time, UserModel profile) {
    final startMinutes = profile.quietHoursStartMinutes ?? (23 * 60); // Default 11 PM
    final endMinutes = profile.quietHoursEndMinutes ?? (6 * 60); // Default 6 AM

    final currentMinutes = time.hour * 60 + time.minute;

    // Handle overnight quiet hours (e.g., 11 PM to 6 AM)
    if (startMinutes > endMinutes) {
      // Quiet hours span midnight
      return currentMinutes >= startMinutes || currentMinutes < endMinutes;
    } else {
      // Quiet hours are within the same day
      return currentMinutes >= startMinutes && currentMinutes < endMinutes;
    }
  }

  /// Get the next allowed time after the given time.
  ///
  /// If the time is in quiet hours, returns the end of quiet hours.
  /// Otherwise, returns the original time.
  DateTime getNextAllowedTime(DateTime time, UserModel profile) {
    if (isTimeAllowed(time, profile)) {
      return time;
    }

    final endMinutes = profile.quietHoursEndMinutes ?? (6 * 60);
    final endHour = endMinutes ~/ 60;
    final endMinute = endMinutes % 60;

    // If we're after midnight but before quiet hours end
    if (time.hour < endHour || (time.hour == endHour && time.minute < endMinute)) {
      return DateTime(time.year, time.month, time.day, endHour, endMinute);
    }

    // Otherwise, quiet hours end tomorrow morning
    final tomorrow = time.add(const Duration(days: 1));
    return DateTime(tomorrow.year, tomorrow.month, tomorrow.day, endHour, endMinute);
  }

  /// Check if colored patterns are allowed on the given date.
  ///
  /// If HOA compliance is enabled and seasonal color windows are defined,
  /// colors are only allowed during those windows.
  bool areColorsAllowed(DateTime date, UserModel profile) {
    // If HOA compliance is not enabled, colors are always allowed
    if (profile.hoaComplianceEnabled != true) {
      return true;
    }

    // If no seasonal windows defined, colors are always allowed
    if (profile.seasonalColorWindows.isEmpty) {
      return true;
    }

    // Check if date falls within any seasonal window
    for (final window in profile.seasonalColorWindows) {
      if (_isDateInWindow(date, window)) {
        return true;
      }
    }

    // Date is outside all color windows
    return false;
  }

  /// Check if a date falls within a seasonal color window.
  bool _isDateInWindow(DateTime date, SeasonalColorWindow window) {
    final dateMonthDay = date.month * 100 + date.day;
    final startMonthDay = window.startMonth * 100 + window.startDay;
    final endMonthDay = window.endMonth * 100 + window.endDay;

    // Handle windows that span year boundary (e.g., Oct 15 - Jan 5)
    if (startMonthDay > endMonthDay) {
      // Window spans year boundary
      return dateMonthDay >= startMonthDay || dateMonthDay <= endMonthDay;
    } else {
      // Window is within same year
      return dateMonthDay >= startMonthDay && dateMonthDay <= endMonthDay;
    }
  }

  /// Get the maximum allowed brightness for a given time.
  ///
  /// Returns a value between 0 and 255.
  /// Late night hours may have reduced maximum brightness.
  int getMaxBrightness(DateTime time, UserModel profile) {
    // If HOA compliance is not enabled, full brightness allowed
    if (profile.hoaComplianceEnabled != true) {
      return 255;
    }

    final hour = time.hour;

    // Late night reduction (10 PM - 6 AM)
    if (hour >= 22 || hour < 6) {
      return 180; // ~70% brightness
    }

    // Evening reduction (9 PM - 10 PM)
    if (hour >= 21) {
      return 220; // ~86% brightness
    }

    return 255;
  }

  /// Check if an effect type is allowed based on vibe level and HOA rules.
  ///
  /// Energetic effects (fast animations, flashing) may be restricted
  /// when HOA compliance is enabled and vibe level is low.
  bool isEffectAllowed(int effectId, UserModel profile) {
    // If HOA compliance is not enabled, all effects allowed
    if (profile.hoaComplianceEnabled != true) {
      return true;
    }

    final vibeLevel = profile.vibeLevel ?? 0.5;

    // Restrict flashy/animated effects if vibe level is subtle
    if (vibeLevel < 0.3) {
      // Only allow static and very subtle effects
      const subtleEffects = [0, 1, 63]; // Solid, Blink, Candle
      return subtleEffects.contains(effectId);
    }

    if (vibeLevel < 0.5) {
      // Restrict very flashy effects
      const restrictedEffects = [
        74, // Fireworks
        108, // Halloween Eyes
        73, // Fire Flicker
      ];
      return !restrictedEffects.contains(effectId);
    }

    return true;
  }

  /// Get a compliant alternative for a restricted pattern.
  ///
  /// If colors are not allowed, returns architectural white.
  /// If effect is not allowed, returns a solid color pattern.
  Map<String, dynamic> getCompliantPattern(
    Map<String, dynamic> originalPayload,
    DateTime scheduledTime,
    UserModel profile,
  ) {
    final payload = Map<String, dynamic>.from(originalPayload);

    // Check color restrictions
    if (!areColorsAllowed(scheduledTime, profile)) {
      // Replace with architectural white
      if (payload.containsKey('seg')) {
        final segments = payload['seg'] as List;
        for (var i = 0; i < segments.length; i++) {
          final seg = Map<String, dynamic>.from(segments[i] as Map);
          seg['col'] = [
            [255, 250, 244] // Warm white
          ];
          segments[i] = seg;
        }
      }
    }

    // Check brightness restrictions
    final maxBri = getMaxBrightness(scheduledTime, profile);
    if (payload.containsKey('bri')) {
      final currentBri = payload['bri'] as int;
      if (currentBri > maxBri) {
        payload['bri'] = maxBri;
      }
    }

    // Check effect restrictions
    if (payload.containsKey('seg')) {
      final segments = payload['seg'] as List;
      for (var i = 0; i < segments.length; i++) {
        final seg = Map<String, dynamic>.from(segments[i] as Map);
        if (seg.containsKey('fx')) {
          final effectId = seg['fx'] as int;
          if (!isEffectAllowed(effectId, profile)) {
            seg['fx'] = 0; // Fall back to solid
          }
        }
        segments[i] = seg;
      }
    }

    return payload;
  }

  /// Generate a summary of HOA compliance status for display.
  HoaComplianceStatus getComplianceStatus(UserModel profile) {
    if (profile.hoaComplianceEnabled != true) {
      return HoaComplianceStatus(
        isEnabled: false,
        quietHoursDescription: 'Not enforced',
        colorRestrictionsDescription: 'Colors allowed year-round',
        currentlyInQuietHours: false,
        colorsCurrentlyAllowed: true,
      );
    }

    final now = DateTime.now();
    final inQuietHours = _isInQuietHours(now, profile);
    final colorsAllowed = areColorsAllowed(now, profile);

    // Format quiet hours
    final startMinutes = profile.quietHoursStartMinutes ?? (23 * 60);
    final endMinutes = profile.quietHoursEndMinutes ?? (6 * 60);
    final startTime = TimeOfDay(hour: startMinutes ~/ 60, minute: startMinutes % 60);
    final endTime = TimeOfDay(hour: endMinutes ~/ 60, minute: endMinutes % 60);
    final quietHoursStr = '${_formatTime(startTime)} - ${_formatTime(endTime)}';

    // Format color restrictions
    String colorRestrictionsStr;
    if (profile.seasonalColorWindows.isEmpty) {
      colorRestrictionsStr = 'Colors allowed year-round';
    } else {
      final windowStrs = profile.seasonalColorWindows
          .map((w) => '${_monthName(w.startMonth)} ${w.startDay} - ${_monthName(w.endMonth)} ${w.endDay}')
          .join(', ');
      colorRestrictionsStr = 'Colors allowed: $windowStrs';
    }

    return HoaComplianceStatus(
      isEnabled: true,
      quietHoursDescription: quietHoursStr,
      colorRestrictionsDescription: colorRestrictionsStr,
      currentlyInQuietHours: inQuietHours,
      colorsCurrentlyAllowed: colorsAllowed,
    );
  }

  String _formatTime(TimeOfDay time) {
    final hour = time.hourOfPeriod == 0 ? 12 : time.hourOfPeriod;
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.period == DayPeriod.am ? 'AM' : 'PM';
    return '$hour:$minute $period';
  }

  String _monthName(int month) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    if (month < 1 || month > 12) return '?';
    return months[month - 1];
  }
}

/// Status summary for HOA compliance display.
class HoaComplianceStatus {
  final bool isEnabled;
  final String quietHoursDescription;
  final String colorRestrictionsDescription;
  final bool currentlyInQuietHours;
  final bool colorsCurrentlyAllowed;

  const HoaComplianceStatus({
    required this.isEnabled,
    required this.quietHoursDescription,
    required this.colorRestrictionsDescription,
    required this.currentlyInQuietHours,
    required this.colorsCurrentlyAllowed,
  });
}

/// Provider for the HOA compliance service.
final hoaComplianceServiceProvider = Provider<HoaComplianceService>(
  (ref) => HoaComplianceService(ref),
);
