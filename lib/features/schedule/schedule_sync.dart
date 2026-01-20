import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Service to map local schedules to WLED timer configuration and push in one batch.
class ScheduleSyncService {
  const ScheduleSyncService();

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
  Map<String, dynamic> buildCfgPayload(List<ScheduleItem> schedules) {
    final enabled = schedules.where((s) => s.enabled).toList(growable: false);
    final List<Map<String, dynamic>> timers = [];

    // Separate regular schedules from solar event schedules
    final regularSchedules = <ScheduleItem>[];
    final solarSchedules = <ScheduleItem>[];

    for (final s in enabled) {
      final tl = s.timeLabel.trim().toLowerCase();
      if (tl == 'sunrise' || tl == 'sunset') {
        solarSchedules.add(s);
      } else {
        regularSchedules.add(s);
      }
    }

    // Build timer entries - WLED expects exactly the fields it knows about
    // Regular timers first
    for (int i = 0; i < regularSchedules.length && timers.length < 8; i++) {
      final s = regularSchedules[i];
      final parsed = _parseTimeLabel(s.timeLabel);
      final dow = _computeDowMask(s.repeatDays);
      final macro = _presetForAction(s.actionLabel);

      timers.add({
        'en': true,
        'hour': parsed.hour,
        'min': parsed.minute,
        'macro': macro,
        'dow': dow,
      });
    }

    // Sunrise/sunset timers
    // WLED uses hour=24 for sunrise, hour=25 for sunset
    // min is the offset in minutes (-59 to +59)
    for (final s in solarSchedules) {
      if (timers.length >= 8) break;
      final tl = s.timeLabel.trim().toLowerCase();
      final dow = _computeDowMask(s.repeatDays);
      final macro = _presetForAction(s.actionLabel);

      final isSunrise = tl == 'sunrise';
      timers.add({
        'en': true,
        'hour': isSunrise ? 24 : 25, // 24=sunrise, 25=sunset
        'min': 0, // offset from sunrise/sunset
        'macro': macro,
        'dow': dow,
      });
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

  /// Pushes all schedules to the currently selected WLED device via /json/cfg.
  Future<bool> syncAll(WidgetRef ref, List<ScheduleItem> schedules) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      debugPrint('ScheduleSync: No WLED device selected');
      return false;
    }
    final payload = buildCfgPayload(schedules);
    debugPrint('ScheduleSync: pushing ${schedules.length} schedules to device');
    debugPrint('ScheduleSync: payload = $payload');

    try {
      final ok = await repo.applyConfig(payload);
      if (!ok) {
        debugPrint('ScheduleSync: applyConfig returned false');
      } else {
        debugPrint('ScheduleSync: Successfully synced schedules to device');
      }
      return ok;
    } catch (e) {
      debugPrint('ScheduleSync: Exception during sync: $e');
      return false;
    }
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
  /// - Preset 3+: Custom patterns/effects
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
    // Brightness changes - would need preset with desired brightness
    if (a.startsWith('brightness')) return 3;
    // Pattern execution - maps to preset 10+ (user-configured)
    if (a.startsWith('pattern') || a.contains('pattern')) return 10;
    // Default: trigger preset 1 (on)
    return 1;
  }
}

class _ParsedTime {
  final int hour;
  final int minute;
  const _ParsedTime({required this.hour, required this.minute});
}

final scheduleSyncServiceProvider = Provider<ScheduleSyncService>((ref) => const ScheduleSyncService());
