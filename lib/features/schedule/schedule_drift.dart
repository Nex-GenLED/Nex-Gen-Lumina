// Build 127 — DRIFT DETECTION: is every enabled schedule still on the lights?
//
// At every LAN launch the on-connect healer already reads the controller's
// timer table (`ControllerClockInfo.timerRows`, the base_boundaries read).
// This file compares that read with the account's enabled schedules: for
// each, the controller must hold a schedule-role ON row at the schedule's on
// time and weekday mask (timer_table_ownership.dart, `deviceOnRowFor`). A
// schedule whose row is absent or different — a time mismatch, an older
// version of the schedule, a missing row — is DRIFTED. The schedules notifier
// then records the `drifted` status (My Schedule row + Home chip, with Retry)
// and lets the bounded automatic re-sync (slice B, +126) repair it inside
// its daytime window.
//
// What this does NOT judge: sunrise/sunset ON schedules (no clock on time to
// match; their sun row is shared and position-less on the wire), OFF rows
// (an OFF without its ON is the half the ownership keep already refuses to
// create), and schedules with no repeat days or an unparseable time (the
// sync refuses those itself and says so).

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart'
    as cfg;
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/timer_table_ownership.dart';

/// A drift read older than this is ignored: the table may have been
/// rewritten many times since, and a stale verdict would send a re-sync at
/// a controller that is fine.
const Duration kDriftReadMaxAge = Duration(hours: 36);

/// One read of the controller's timer table, as the healer made it.
class DeviceTimerRead {
  /// The rows as read back (compacted: armed rows and the sun placeholder).
  final List<Map<String, dynamic>> rows;

  /// When the read was made (phone clock).
  final DateTime at;

  /// The controller the rows came from, when known.
  final String? controllerId;

  const DeviceTimerRead({
    required this.rows,
    required this.at,
    this.controllerId,
  });
}

/// The last timer-table read of the connected controller, or null before the
/// healer has read one this session. Set by the on-connect healer's provider;
/// read by [SchedulesNotifier] to detect drift.
final deviceTimerReadProvider = StateProvider<DeviceTimerRead?>((_) => null);

/// True when [s] is one drift detection can judge: enabled, not evicted, a
/// clock on time the sync can arm, at least one repeat day, and an action
/// whose ON row has a known macro role.
bool driftJudges(ScheduleItem s) {
  if (!s.enabled || s.isCurrentlyEvicted) return false;
  if (cfg.isSolarLabel(s.timeLabel)) return false;
  if (cfg.parseTimeLabel(s.timeLabel) == null) return false;
  if (cfg.computeDowMask(s.repeatDays) == 0) return false;
  return scheduleOnRoles(s).isNotEmpty;
}

/// The enabled schedules whose ON row the controller does not hold at the
/// schedule's on time and weekday mask with a schedule-role macro.
List<ScheduleItem> driftedSchedules({
  required List<ScheduleItem> schedules,
  required List<Map<String, dynamic>> rows,
}) {
  final armed = [for (final r in rows) if (_enabled(r)) r];
  return [
    for (final s in schedules)
      if (driftJudges(s) && deviceOnRowFor(s, armed) == null) s,
  ];
}

bool _enabled(Map<String, dynamic> r) => r['en'] == true || r['en'] == 1;

/// Whether a read is worth comparing: fresh enough, and not older than the
/// last sync that rewrote the table ([lastSyncAt], when known).
bool driftReadUsable(DeviceTimerRead read,
    {required DateTime now, DateTime? lastSyncAt}) {
  if (now.difference(read.at) > kDriftReadMaxAge) return false;
  if (lastSyncAt != null && !read.at.isAfter(lastSyncAt)) return false;
  return true;
}
