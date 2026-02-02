import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Service to map local schedules to WLED timer configuration and push in one batch.
///
/// **Schedule Preset Architecture:**
/// - Presets 1-9: Reserved for system use (on, off, brightness levels)
/// - Presets 10-25: Available for user schedules (up to 16 unique scheduled patterns)
/// - Each schedule gets its own preset ID to avoid conflicts
///
/// When syncing schedules:
/// 1. Save each schedule's WLED payload as a preset on the device
/// 2. Create WLED timers that reference those preset IDs
/// 3. Push the timer configuration to the device
class ScheduleSyncService {
  const ScheduleSyncService();

  /// First available preset ID for user schedules
  static const int _firstSchedulePresetId = 10;

  /// Last available preset ID for user schedules
  static const int _lastSchedulePresetId = 25;

  /// Builds a WLED /json/cfg payload that sets the timer configuration.
  ///
  /// WLED Timer Format (from JSON API docs):
  /// POST /json/cfg with body: { "timers": { "ins": [...] } }
  ///
  /// Each timer object in "ins" array:
  /// - en: bool - timer enabled
  /// - hour: int 0-23 (or 24 for sunrise, 25 for sunset)
  /// - min: int 0-59 (or offset -59 to +59 for sunrise/sunset)
  /// - macro: int - preset ID to activate (1-250), 0 = off command
  /// - dow: int - day of week bitmask (bit 0=Sun, bit 6=Sat), 127=daily
  /// - start/end: for time ranges (optional)
  ///
  /// WLED supports up to 8 timers in the "ins" array.
  ///
  /// Each schedule with an on/off time generates TWO timers:
  /// 1. ON timer - triggers the pattern/action
  /// 2. OFF timer - turns lights off (if offTimeLabel is set)
  Map<String, dynamic> buildCfgPayload(List<ScheduleItem> schedules) {
    final enabled = schedules.where((s) => s.enabled).toList(growable: false);
    final List<Map<String, dynamic>> timers = [];

    for (final s in enabled) {
      if (timers.length >= 8) break;

      final dow = _computeDowMask(s.repeatDays);

      // Determine preset ID: use assigned presetId if available, else fall back to legacy behavior
      final presetId = s.presetId ?? _presetForAction(s.actionLabel);

      // ON timer
      final onTimer = _buildTimerEntry(
        timeLabel: s.timeLabel,
        dow: dow,
        macro: presetId,
      );
      if (onTimer != null) {
        timers.add(onTimer);
      }

      // OFF timer (if schedule has an off time)
      if (s.hasOffTime && s.offTimeLabel != null && timers.length < 8) {
        final offTimer = _buildTimerEntry(
          timeLabel: s.offTimeLabel!,
          dow: dow,
          macro: 2, // Preset 2 = off state (convention)
        );
        if (offTimer != null) {
          timers.add(offTimer);
        }
      }
    }

    debugPrint('ScheduleSync: Built ${timers.length} timer entries');
    for (int i = 0; i < timers.length; i++) {
      debugPrint('  Timer $i: ${timers[i]}');
    }

    // Return the cfg payload - only send configured timers, no padding needed
    return {
      'timers': {
        'ins': timers,
      },
    };
  }

  /// Builds a single timer entry from a time label.
  /// Returns null if the time label cannot be parsed.
  Map<String, dynamic>? _buildTimerEntry({
    required String timeLabel,
    required int dow,
    required int macro,
  }) {
    final tl = timeLabel.trim().toLowerCase();

    // Handle solar events (sunrise/sunset)
    if (tl == 'sunrise' || tl == 'sunset') {
      final isSunrise = tl == 'sunrise';
      return {
        'en': true,
        'hour': isSunrise ? 24 : 25, // 24=sunrise, 25=sunset
        'min': 0, // offset from sunrise/sunset
        'macro': macro,
        'dow': dow,
      };
    }

    // Handle specific time
    final parsed = _parseTimeLabel(timeLabel);
    return {
      'en': true,
      'hour': parsed.hour,
      'min': parsed.minute,
      'macro': macro,
      'dow': dow,
    };
  }

  /// Pushes all schedules to the currently selected WLED device.
  ///
  /// This method performs two critical steps:
  /// 1. **Save Presets**: For each schedule with a WLED payload, save that
  ///    payload as a preset on the device. This ensures the timer has
  ///    actual lighting state to load when it triggers.
  /// 2. **Sync Timers**: Push the timer configuration to /json/cfg so
  ///    the device knows when to trigger each preset.
  ///
  /// Returns a [ScheduleSyncResult] with details about the sync operation.
  Future<ScheduleSyncResult> syncAll(WidgetRef ref, List<ScheduleItem> schedules) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      debugPrint('ScheduleSync: No WLED device selected');
      return ScheduleSyncResult(
        success: false,
        error: 'No WLED device selected',
      );
    }

    final enabled = schedules.where((s) => s.enabled).toList();
    debugPrint('ScheduleSync: Syncing ${enabled.length} enabled schedules');

    // Step 1: Assign preset IDs and save presets to device
    final List<ScheduleItem> updatedSchedules = [];
    final List<String> presetErrors = [];
    int nextPresetId = _firstSchedulePresetId;

    for (final schedule in enabled) {
      if (nextPresetId > _lastSchedulePresetId) {
        debugPrint('ScheduleSync: Maximum preset limit reached (${_lastSchedulePresetId - _firstSchedulePresetId + 1} schedules)');
        break;
      }

      // Assign preset ID if schedule has a WLED payload
      final presetId = schedule.presetId ?? nextPresetId;
      if (schedule.presetId == null) nextPresetId++;

      if (schedule.hasWledPayload) {
        // Save the WLED payload as a preset on the device
        debugPrint('ScheduleSync: Saving preset $presetId for "${schedule.actionLabel}"');
        final saved = await repo.savePreset(
          presetId: presetId,
          state: schedule.wledPayload!,
          presetName: schedule.actionLabel,
        );

        if (!saved) {
          presetErrors.add('Failed to save preset for "${schedule.actionLabel}"');
          debugPrint('ScheduleSync: ❌ Failed to save preset $presetId');
        } else {
          debugPrint('ScheduleSync: ✅ Saved preset $presetId');
        }
      }

      updatedSchedules.add(schedule.copyWith(presetId: presetId));
    }

    // Step 2: Build and push timer configuration
    final payload = buildCfgPayload(updatedSchedules);
    debugPrint('ScheduleSync: Timer payload = $payload');

    try {
      final ok = await repo.applyConfig(payload);
      if (!ok) {
        debugPrint('ScheduleSync: applyConfig returned false');
        return ScheduleSyncResult(
          success: false,
          error: 'Failed to save timer configuration',
          presetErrors: presetErrors,
          schedulesWithPresets: updatedSchedules,
        );
      }

      debugPrint('ScheduleSync: ✅ Successfully synced schedules to device');
      return ScheduleSyncResult(
        success: true,
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      );
    } catch (e) {
      debugPrint('ScheduleSync: Exception during sync: $e');
      return ScheduleSyncResult(
        success: false,
        error: 'Exception: $e',
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      );
    }
  }

  /// Legacy sync method for backward compatibility.
  /// Prefer using [syncAll] which returns detailed results.
  Future<bool> syncAllLegacy(WidgetRef ref, List<ScheduleItem> schedules) async {
    final result = await syncAll(ref, schedules);
    return result.success;
  }

  // Helpers

  _ParsedTime _parseTimeLabel(String label) {
    final l = label.trim().toLowerCase();
    // Sunrise/sunset are handled separately; return midnight as fallback
    if (l == 'sunrise' || l == 'sunset') {
      return const _ParsedTime(hour: 0, minute: 0);
    }
    // Expect formats like "7:05 PM" or "12:00 AM"
    final reg = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
    final m = reg.firstMatch(label.trim());
    if (m != null) {
      var hh = int.tryParse(m.group(1)!) ?? 0;
      final mm = int.tryParse(m.group(2)!) ?? 0;
      final ap = m.group(3)!.toLowerCase();
      if (ap == 'pm' && hh != 12) hh += 12;
      if (ap == 'am' && hh == 12) hh = 0;
      return _ParsedTime(hour: hh.clamp(0, 23), minute: mm.clamp(0, 59));
    }
    // Fallback to midnight
    return const _ParsedTime(hour: 0, minute: 0);
  }

  int _computeDowMask(List<String> days) {
    if (days.any((d) => d.toLowerCase().contains('daily'))) return 127;
    int mask = 0;
    for (final d in days) {
      switch (d.toLowerCase()) {
        case 'sun':
        case 'sunday':
          mask |= 1; // bit0
          break;
        case 'mon':
        case 'monday':
          mask |= 2; // bit1
          break;
        case 'tue':
        case 'tues':
        case 'tuesday':
          mask |= 4; // bit2
          break;
        case 'wed':
        case 'wednesday':
          mask |= 8; // bit3
          break;
        case 'thu':
        case 'thurs':
        case 'thursday':
          mask |= 16; // bit4
          break;
        case 'fri':
        case 'friday':
          mask |= 32; // bit5
          break;
        case 'sat':
        case 'saturday':
          mask |= 64; // bit6
          break;
      }
    }
    return mask;
  }

  /// Maps an action label to a WLED preset ID.
  ///
  /// WLED timers trigger presets (saved states). The user must have these
  /// presets configured on their device:
  /// - Preset 1: "On" state (default brightness/color)
  /// - Preset 2: "Off" state
  /// - Preset 3: "Dim" state (20% brightness) - for night mode / brightness rules
  /// - Preset 4: "Low" state (40% brightness)
  /// - Preset 5: "Medium" state (60% brightness)
  /// - Preset 10+: Custom patterns/effects
  ///
  /// For now we use simple conventions. Future improvement: let users
  /// select which preset to trigger per schedule item.
  int _presetForAction(String actionLabel) {
    final a = actionLabel.toLowerCase();
    // "Turn Off" triggers preset that sets on=false
    // WLED doesn't have a built-in "off" preset, so we use preset 2
    // which users should configure as an "off" state
    if (a.contains('turn off') || a.contains('off')) return 2;
    // "Turn On" triggers preset 1 (default on state)
    if (a.contains('turn on') || a.contains('on')) return 1;

    // Brightness level presets (parse percentage from label)
    // "Brightness: 20%" → preset 3 (dim)
    // "Brightness: 40%" → preset 4 (low)
    // "Brightness: 60%" → preset 5 (medium)
    // Higher values → preset 1 (full on)
    if (a.startsWith('brightness')) {
      final percentMatch = RegExp(r'(\d+)%?').firstMatch(a);
      if (percentMatch != null) {
        final percent = int.tryParse(percentMatch.group(1)!) ?? 50;
        if (percent <= 25) return 3;      // Dim preset (20%)
        if (percent <= 45) return 4;      // Low preset (40%)
        if (percent <= 70) return 5;      // Medium preset (60%)
        return 1;                          // Full on for high brightness
      }
      return 3; // Default to dim preset if no percentage found
    }

    // Pattern execution - maps to preset 10+ (user-configured)
    if (a.startsWith('pattern') || a.contains('pattern')) return 10;
    // Default: trigger preset 1 (on)
    return 1;
  }

  /// Extracts brightness percentage from an action label.
  /// Returns null if the label doesn't contain a brightness percentage.
  int? extractBrightnessPercent(String actionLabel) {
    final a = actionLabel.toLowerCase();
    if (!a.startsWith('brightness')) return null;

    final percentMatch = RegExp(r'(\d+)%?').firstMatch(a);
    if (percentMatch != null) {
      return int.tryParse(percentMatch.group(1)!);
    }
    return null;
  }
}

class _ParsedTime {
  final int hour;
  final int minute;
  const _ParsedTime({required this.hour, required this.minute});
}

final scheduleSyncServiceProvider = Provider<ScheduleSyncService>((ref) => const ScheduleSyncService());

/// Result of a schedule sync operation.
class ScheduleSyncResult {
  /// Whether the overall sync was successful.
  final bool success;

  /// Error message if sync failed.
  final String? error;

  /// List of errors encountered while saving individual presets.
  final List<String> presetErrors;

  /// Schedules with their assigned preset IDs.
  /// Can be used to update the stored schedules with their preset assignments.
  final List<ScheduleItem> schedulesWithPresets;

  const ScheduleSyncResult({
    required this.success,
    this.error,
    this.presetErrors = const [],
    this.schedulesWithPresets = const [],
  });

  /// Returns true if there were any preset-related errors.
  bool get hasPresetErrors => presetErrors.isNotEmpty;

  /// Returns a summary message suitable for user display.
  String get summaryMessage {
    if (!success) {
      return error ?? 'Sync failed';
    }
    if (hasPresetErrors) {
      return 'Synced with ${presetErrors.length} warning(s)';
    }
    return 'Successfully synced ${schedulesWithPresets.length} schedule(s)';
  }
}
