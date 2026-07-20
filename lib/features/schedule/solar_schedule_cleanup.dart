import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';

/// One-time, LAN-only remediation for the hour:24/25 solar-timer P0.
///
/// Solar-labeled schedules ('sunrise'/'sunset') were written to controllers as
/// WLED hour 24/25 — dead timers that never fire, and hour 24 actively fires
/// HOURLY (snapping lights off every hour on a solar-OFF boundary). Commit 2
/// stopped writing them; this closes the loop by re-syncing an affected user's
/// schedules ONCE so the padded 8-slot push overwrites any stale hour:24/25
/// timer already on the device with a disabled stub (the same slot-reclaim that
/// clears dow:0 orphans). See memory/project_solar_schedules_never_fire.

/// Terminal states of a cleanup evaluation.
enum SolarCleanupOutcome {
  /// Persistent flag already set — this account was cleaned before. No-op.
  alreadyDone,

  /// No solar schedules to clean. No-op, no flag written.
  noSolar,

  /// On a non-LAN transport (relay/mock). cfg writes can't reach the
  /// controller, so we defer WITHOUT setting the flag — retry next LAN launch.
  deferredOffLan,

  /// A LAN re-sync landed; stale solar timers reclaimed and the flag is set.
  cleaned,

  /// A LAN sync was attempted but didn't confirm (transient). Flag left unset
  /// so a later launch retries.
  syncFailed,
}

/// True when [label] is one of the two solar keywords the app (wrongly) maps to
/// WLED hour 24/25. Mirrors schedule_sync's `_isSolarLabel`.
bool _isSolar(String? label) {
  if (label == null) return false;
  final l = label.trim().toLowerCase();
  return l == 'sunrise' || l == 'sunset';
}

/// True when any schedule has a solar on/off boundary — the census predicate.
bool scheduleListHasSolar(List<ScheduleItem> schedules) =>
    schedules.any((s) => _isSolar(s.timeLabel) || _isSolar(s.offTimeLabel));

/// Runs the one-time cleanup if and only if it's needed and safe. Pure control
/// flow — all I/O is injected, so this is unit-testable without Firestore,
/// SharedPreferences, or a network.
///
/// Contract:
///   • [alreadyDone] true                → [SolarCleanupOutcome.alreadyDone]
///   • no solar schedules                → [SolarCleanupOutcome.noSolar]
///   • not [onLan]                        → [SolarCleanupOutcome.deferredOffLan]
///   • LAN sync succeeds                  → [markDone] called, `cleaned`
///   • LAN sync doesn't land              → flag left unset, `syncFailed`
///
/// [markDone] is invoked ONLY on a confirmed successful sync — never on a
/// deferral or failure — so the flag can't latch before the timers are cleared.
Future<SolarCleanupOutcome> runSolarScheduleCleanupIfNeeded({
  required bool alreadyDone,
  required List<ScheduleItem> schedules,
  required bool onLan,
  required Future<ScheduleSyncResult> Function() runSync,
  required Future<void> Function() markDone,
}) async {
  if (alreadyDone) return SolarCleanupOutcome.alreadyDone;
  if (!scheduleListHasSolar(schedules)) return SolarCleanupOutcome.noSolar;
  if (!onLan) return SolarCleanupOutcome.deferredOffLan;

  final result = await runSync();
  // `success` is true only when the /json/cfg timer push actually landed on
  // the LAN controller — exactly the moment the stale timers are reclaimed.
  // `deferredOffLan` (a race where the repo flipped off-LAN mid-sync) and any
  // failure leave the flag unset so a later LAN launch retries.
  if (result.success) {
    await markDone();
    return SolarCleanupOutcome.cleaned;
  }
  return SolarCleanupOutcome.syncFailed;
}
