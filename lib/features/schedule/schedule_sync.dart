import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/solar_scheduling_feature_flag.dart';
import 'package:nexgen_command/features/wled/clock_health.dart'
    show ClockInfoSource;
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart'
    show repoCanWriteCfg;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart'
    show CfgWriteUnsupportedException, WledRepository;
import 'package:nexgen_command/features/wled/wled_service.dart' show WledService;

/// A real, ENABLED timer entry — not a disabled/padding stub, not a solar
/// sentinel: `en` is truthy (bool `true` or int `1`), `macro != 0`, `hour != 255`.
/// Shared by the readback comparator ([timersInsLanded]) and syncAll's
/// empty-armed guard so both agree on what "an armable timer" is.
@visibleForTesting
bool isRealEnabledTimer(Map<String, dynamic> t) {
  final en = t['en'];
  final enOn = en == true || en == 1;
  final macro = (t['macro'] is num) ? (t['macro'] as num).toInt() : 0;
  final hour = (t['hour'] is num) ? (t['hour'] as num).toInt() : -1;
  return enOn && macro != 0 && hour != 255;
}

/// CONTENT-match readback comparison for the schedule cfg write: does the
/// controller's timer table CONTAIN the real timers we sent, regardless of
/// position?
///
/// Bench-proven readback shape (WLED vid 2507300, SKIKBILY): the controller
/// echoes the enabled real entries + the two solar sentinel entries (hour:255)
/// and DROPS disabled padding stubs — so the array COMPACTS and sent-index ≠
/// readback-index. Per-index comparison is therefore invalid; we match by
/// content anywhere in the array.
///
/// Semantics:
/// - From [sent], consider only ENABLED REAL entries: `en==1 && macro!=0 &&
///   hour!=255` (this drops disabled/padding stubs and solar sentinels).
/// - Each such entry must have SOME entry in [readback] with `en==1` and
///   matching hour/min/macro/dow (order-independent).
/// - If [sent] has no real entries (schedule cleared), the write is confirmed
///   iff [readback] contains NO enabled NON-solar entries (hour!=255) — the
///   controller's real timers were cleared; its solar sentinels are ignored.
/// - `en` is normalized (bool/int → int); solar entries (hour==255) and any
///   readback entries that don't match a sent real entry are ignored.
///
/// Field-level, not raw-JSON equality: WLED returns extra keys (start/end/
/// mon/day) and reorders, so only the fields we control are compared.
@visibleForTesting
bool timersInsLanded(
  List<Map<String, dynamic>> sent,
  List<Map<String, dynamic>> readback,
) {
  int en(Object? v) => (v == true || v == 1) ? 1 : 0;
  int fld(Map<String, dynamic> m, String k) =>
      (m[k] is num) ? (m[k] as num).toInt() : -1;

  final sentReal = sent.where(isRealEnabledTimer).toList();

  if (sentReal.isEmpty) {
    // Cleared schedule: the controller must show no enabled non-solar timers.
    return !readback
        .any((r) => en(r['en']) == 1 && fld(r, 'hour') != 255);
  }

  // Every real timer we sent must appear somewhere in the readback (en==1,
  // matching controlled fields). Solar sentinels and unrelated readback entries
  // are ignored implicitly — they won't match a non-255 sent hour.
  for (final s in sentReal) {
    final present = readback.any((r) =>
        en(r['en']) == 1 &&
        fld(r, 'hour') == fld(s, 'hour') &&
        fld(r, 'min') == fld(s, 'min') &&
        fld(r, 'macro') == fld(s, 'macro') &&
        fld(r, 'dow') == fld(s, 'dow'));
    if (!present) return false;
  }
  return true;
}

/// Patient verification of a cfg write that hit the controller's post-commit
/// network stall (see [ScheduleSyncService._pushCfgWithVerify]). The write is
/// assumed to have COMMITTED; we wait for the controller to answer again and
/// confirm by readback — we do NOT re-POST into the blackout.
///
/// Flow: poll [liveness] every [pollInterval] for up to [maxWait]. On the first
/// live response, [readbackMatch]:
///   - true  → verified (success).
///   - false → the controller recovered but the timers aren't present: ONE
///     [rePost], wait [repostSettle], then [readbackMatch] once more → its result.
///   - null  → couldn't read yet (half-recovered / cfg fetch failed); keep polling.
/// Never answers within [maxWait] → false.
///
/// All waiting goes through [delay] so tests inject an instant clock (no real
/// 20s sleeps). Returns true iff the write is confirmed on the controller.
@visibleForTesting
Future<bool> verifyCfgAfterStall({
  required Future<bool> Function() liveness,
  required Future<bool?> Function() readbackMatch,
  required Future<bool> Function() rePost,
  required Future<void> Function(Duration) delay,
  void Function(Duration elapsed)? onPoll,
  Duration pollInterval = const Duration(seconds: 20),
  Duration maxWait = const Duration(minutes: 5),
  Duration repostSettle = const Duration(seconds: 10),
}) async {
  var waited = Duration.zero;
  while (waited < maxWait) {
    await delay(pollInterval);
    waited += pollInterval;
    onPoll?.call(waited);
    final alive = await liveness();
    if (!alive) continue; // still stalled — keep waiting
    final matched = await readbackMatch();
    if (matched == true) return true; // recovered + confirmed
    if (matched == null) continue; // half-recovered; try again next poll
    // Recovered but the timers are NOT present — one corrective re-POST, settle,
    // and re-verify. (In practice unreached: the bench proves the write always
    // commits, so the first post-recovery readback matches.)
    await rePost();
    await delay(repostSettle);
    return (await readbackMatch()) == true;
  }
  return false; // never recovered within maxWait
}

/// Outcome of the cfg push + verify (see [ScheduleSyncService._pushCfgWithVerify]).
enum _CfgPushOutcome {
  /// Timers confirmed on the controller (2xx + readback match, 2xx + unreadable,
  /// or verified after the post-commit stall).
  confirmed,

  /// 2xx but the readback content did NOT match what we sent — the controller
  /// stored different values (firmware incompatibility signal). A hard failure.
  mismatch,

  /// The write was never confirmed — the controller never answered within the
  /// verification window, or a relay/webhook reported a plain failure.
  notConfirmed,
}

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

  /// GENERAL (clock) timer slots — WLED 0.15.1 `timers.ins` indices 0-7.
  /// (Was "total slots"; solar now uses the two dedicated slots below, so this
  /// is the general-timer capacity only.)
  static const int kMaxWledTimers = 8;

  /// WLED 0.15.1 dedicates the LAST TWO `timers.ins` slots to solar triggers:
  /// index 8 = SUNRISE, index 9 = SUNSET. `checkTimers()` special-cases them BY
  /// POSITION (timerHours[8]/[9] are ignored; the minute field is the offset in
  /// minutes). VERSION-SPECIFIC: a future fleet move to the post-0.15.1
  /// TH_SUNRISE/TH_SUNSET hour-sentinel refactor would change this encoding.
  static const int kWledSunriseSlot = 8;
  static const int kWledSunsetSlot = 9;

  /// Total slots WLED 0.15.1 reads from `timers.ins` (8 general + 2 solar).
  static const int kWledTotalTimerSlots = 10;

  /// The `hour` value WLED 0.15.1 serializes for a solar timer. `checkTimers()`
  /// keys solar off the SLOT INDEX (8/9), not this value, but we write 255 to
  /// match the firmware's own serialization. NOT 24/25 — the app's OLD broken
  /// encoding, where 24 = "fire hourly" and 25 = never matches the RTC.
  static const int kWledSolarHourMarker = 255;

  /// Max minute-offset magnitude WLED accepts for a sunrise/sunset timer.
  static const int kWledSolarOffsetLimit = 120;

  /// Disabled timer stub used to overwrite a vacated WLED slot. WLED merges
  /// `timers.ins` by index and never clears slots beyond the pushed array's
  /// length, so a shrinking schedule set would otherwise leave stale timers
  /// armed in the high slots (the dow:0 orphan-accumulation bug). Padding every
  /// pushed payload to exactly [kMaxWledTimers] entries with these stubs makes
  /// each sync authoritative over all 8 slots. `en:0` so a stub never fires.
  static const Map<String, dynamic> _disabledTimerStub = {
    // WLED reads `en` type-strictly as an INT — a JSON bool is silently stored
    // as 0. Curl-proven 2026-07-22 on vid 2507300 (`{"en":true}`→stored en:0;
    // `{"en":1}`→stored en:1). 0 = a reliably-disabled stub. DO NOT use a bool.
    'en': 0,
    'hour': 0,
    'min': 0,
    'macro': 0,
    'dow': 0,
  };

  /// Pad/truncate [ins] to exactly [kMaxWledTimers] entries. Real timers keep
  /// their order and values (so sunset hour:25 / sunrise hour:24 entries are
  /// untouched); unused slots become disabled stubs so a sync that dropped a
  /// schedule zeros the slot it vacated on the controller. Apply ONLY at the
  /// final push stage (syncAll / _buildMergedCfgPayload) — never inside
  /// buildCfgPayload, whose callers merge its real-timer list before padding.
  static List<Map<String, dynamic>> padTimersToMax(
      List<Map<String, dynamic>> ins) {
    final out = ins.length > kMaxWledTimers
        ? ins.sublist(0, kMaxWledTimers)
        : List<Map<String, dynamic>>.from(ins);
    while (out.length < kMaxWledTimers) {
      out.add(Map<String, dynamic>.from(_disabledTimerStub));
    }
    return out;
  }

  /// Split [armable] into the subset that fits WLED's [kMaxWledTimers]-slot
  /// timer table and a flag for whether any schedule overflowed. Mirrors
  /// [buildCfgPayload]'s ON-then-OFF slot consumption exactly so the caller can
  /// (a) surface a loud "slots full" warning and (b) count only schedules that
  /// actually armed — never overcounting a schedule that silently fell off the
  /// controller.
  static ({List<ScheduleItem> armed, bool overflowed}) splitByTimerCapacity(
      List<ScheduleItem> armable,
      {bool solarEnabled = false}) {
    final armed = <ScheduleItem>[];
    var slotsUsed = 0;
    var overflowed = false;
    for (final s in armable) {
      // Solar boundaries live in the dedicated slots 8/9, so they don't consume
      // a general slot when solar is enabled — count only the CLOCK boundaries.
      final onSolar = solarEnabled && _isSolarLabel(s.timeLabel);
      final offSolar = solarEnabled &&
          s.hasOffTime &&
          s.offTimeLabel != null &&
          _isSolarLabel(s.offTimeLabel!);
      // A clock ON needs a general slot; a solar ON does not. Only overflow on
      // a schedule that actually needs a general slot and has none left — a
      // solar-only schedule always fits (it uses slot 8/9).
      if (!onSolar && slotsUsed >= kMaxWledTimers) {
        overflowed = true;
        break;
      }
      if (!onSolar) slotsUsed += 1; // clock ON timer
      if (s.hasOffTime &&
          s.offTimeLabel != null &&
          !offSolar &&
          slotsUsed < kMaxWledTimers) {
        slotsUsed += 1; // clock OFF timer
      }
      armed.add(s);
    }
    return (armed: armed, overflowed: overflowed);
  }

  /// Encodes a single WLED 0.15.1 solar timer entry (for slot 8 or 9). The
  /// slot POSITION — not this map — is what makes it sunrise vs sunset; the map
  /// is identical either way. `hour:255` is the firmware's serialized marker;
  /// `min` is the offset in minutes (clamped to ±120), NOT a wall-clock minute.
  static Map<String, dynamic> buildSolarTimerEntry({
    required int offsetMinutes,
    required int macro,
    required int dow,
  }) {
    return <String, dynamic>{
      // WLED reads `en` as an INT; a JSON bool stores as 0 (disabled).
      // Curl-proven 2026-07-22 on vid 2507300. DO NOT change to a bool.
      'en': 1,
      'hour': kWledSolarHourMarker,
      'min': offsetMinutes.clamp(-kWledSolarOffsetLimit, kWledSolarOffsetLimit),
      'macro': macro,
      'dow': dow,
    };
  }

  /// Resolves the two solar slots (sunrise / sunset) across ALL schedules — the
  /// constraint is cross-schedule, so it cannot live in a per-schedule guard.
  /// WLED 0.15.1 has exactly ONE sunrise slot (8) and ONE sunset slot (9), so
  /// each holds at most one boundary (an ON or an OFF), first-wins. Additional
  /// sunrise/sunset boundaries are returned in [rejected] for a warning.
  ///
  /// Flexible pairing: a dusk-to-dawn schedule (ON at sunset, OFF at sunrise)
  /// fills BOTH slots by itself; the two are independently assignable.
  ({
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
    List<String> rejected,
  }) solarTimerSlots(List<ScheduleItem> schedules) {
    Map<String, dynamic>? sunrise;
    Map<String, dynamic>? sunset;
    final rejected = <String>[];

    void assign(bool isSunrise, Map<String, dynamic> entry, String who) {
      if (isSunrise) {
        if (sunrise == null) {
          sunrise = entry;
        } else {
          rejected.add(who);
        }
      } else {
        if (sunset == null) {
          sunset = entry;
        } else {
          rejected.add(who);
        }
      }
    }

    for (final s in schedules) {
      final dow = _computeDowMask(s.repeatDays);
      if (dow == 0) continue;
      final presetId = s.presetId ?? _presetForAction(s.actionLabel);

      // ON boundary (offset 0 — no offset UI yet; see PR bench-gate note).
      if (_isSolarLabel(s.timeLabel)) {
        final isSunrise = s.timeLabel.trim().toLowerCase() == 'sunrise';
        assign(
          isSunrise,
          buildSolarTimerEntry(offsetMinutes: 0, macro: presetId, dow: dow),
          '${s.actionLabel} (${s.timeLabel} ON)',
        );
      }
      // OFF boundary — macro 2 is the OFF preset (same convention as clock).
      if (s.hasOffTime &&
          s.offTimeLabel != null &&
          _isSolarLabel(s.offTimeLabel!)) {
        final isSunrise = s.offTimeLabel!.trim().toLowerCase() == 'sunrise';
        assign(
          isSunrise,
          buildSolarTimerEntry(offsetMinutes: 0, macro: 2, dow: dow),
          '${s.actionLabel} (${s.offTimeLabel} OFF)',
        );
      }
    }
    return (sunrise: sunrise, sunset: sunset, rejected: rejected);
  }

  /// Assembles the full 10-entry `timers.ins` for the solar-enabled path:
  /// [generalTimers] pad/truncate into slots 0-7, then slot 8 = [sunrise] and
  /// slot 9 = [sunset] (disabled stubs when absent, so a removed solar timer is
  /// reclaimed on the next push — same mechanism as the general slot reclaim).
  static List<Map<String, dynamic>> assembleSolarAwareIns(
    List<Map<String, dynamic>> generalTimers, {
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
  }) {
    final out = generalTimers.length > kMaxWledTimers
        ? generalTimers.sublist(0, kMaxWledTimers)
        : List<Map<String, dynamic>>.from(generalTimers);
    while (out.length < kMaxWledTimers) {
      out.add(Map<String, dynamic>.from(_disabledTimerStub));
    }
    out.add(sunrise != null
        ? Map<String, dynamic>.from(sunrise)
        : Map<String, dynamic>.from(_disabledTimerStub)); // slot 8
    out.add(sunset != null
        ? Map<String, dynamic>.from(sunset)
        : Map<String, dynamic>.from(_disabledTimerStub)); // slot 9
    return out; // exactly kWledTotalTimerSlots (10)
  }

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
  /// - dow: int - day of week bitmask. WLED firmware uses
  ///   Monday=bit 0 through Sunday=bit 6; 127 = daily. See
  ///   [wled_dow.dart] for the canonical conversion helpers.
  ///   (Item #72 — corrected 2026-05-19 from prior wrong Sun=bit 0
  ///   assumption that caused timers to fire one weekday late.)
  /// - start/end: for time ranges (optional)
  ///
  /// WLED supports up to 8 timers in the "ins" array.
  ///
  /// Each schedule with an on/off time generates TWO timers:
  /// 1. ON timer - triggers the pattern/action
  /// 2. OFF timer - turns lights off (if offTimeLabel is set)
  Map<String, dynamic> buildCfgPayload(
    List<ScheduleItem> schedules, {
    bool solarEnabled = false,
  }) {
    // Eviction (Item #61 Workstream B): items soft-evicted by a
    // CalendarEntry lease are filtered here so the freed slot is
    // genuinely free on the controller side. Re-enable is automatic —
    // the CalendarEntryLeaseManager periodic sweep clears the field
    // once disabledUntil passes.
    final enabled = schedules
        .where((s) => s.enabled && !s.isCurrentlyEvicted)
        .toList(growable: false);

    // SCHEDULE BOUNDARY INVARIANT — do not violate:
    // Each boundary of a recurring schedule (ON at sunset, OFF at sunrise) is an
    // INDEPENDENT entry in the controller's timers.ins[], fired by the WLED RTC.
    // A boundary MUST fire at its trigger time regardless of the currently-applied
    // design. A manual override changes applied state only; it must never void a
    // pending boundary. If schedule firing is ever moved off the controller RTC
    // into an in-app or server-side applier, each boundary must STILL be evaluated
    // independently at its trigger time — NEVER gate the OFF boundary on an "is the
    // schedule still the active design" check. Doing so reintroduces the
    // manual-override-survives-all-day bug that the RTC two-timer model avoids.
    final List<Map<String, dynamic>> timers = [];

    for (final s in enabled) {
      if (timers.length >= kMaxWledTimers) break;

      final dow = _computeDowMask(s.repeatDays);

      // Defense in depth (never emit a dead timer): an empty or
      // all-unrecognized repeatDays yields an all-zero WLED dow mask, which the
      // firmware reads as "no days" — the timer takes a slot but NEVER fires.
      // syncAll's arm-boundary guard already refuses these with a loud warning;
      // skip here too so NO path can write a dow:0 orphan. Policy: refuse, never
      // silently normalize to daily.
      if (dow == 0) {
        debugPrint('ScheduleSync: skipped dow:0 timer for "${s.actionLabel}" '
            '(repeatDays=${s.repeatDays})');
        continue;
      }

      final onSolar = _isSolarLabel(s.timeLabel);
      final offSolar = s.hasOffTime &&
          s.offTimeLabel != null &&
          _isSolarLabel(s.offTimeLabel!);

      if (!solarEnabled) {
        // FLAG OFF (production / default): solar never fires under the old
        // hour:24/25 encoding, so refuse the WHOLE schedule (a half-solar
        // schedule is still broken). syncAll's arm guard warns the user; this
        // covers the lease-manager path that bypasses those guards. See
        // memory/project_solar_schedules_never_fire.
        if (onSolar || offSolar) {
          debugPrint('ScheduleSync: skipped solar timer for "${s.actionLabel}" '
              '(on=${s.timeLabel} off=${s.offTimeLabel}) — solar disabled '
              '(solar_scheduling flag off / bench gate)');
          continue;
        }
      }
      // FLAG ON: a solar boundary is OMITTED from the general 0-7 timers here
      // and encoded into its dedicated slot 8/9 by [solarTimerSlots] +
      // [assembleSolarAwareIns]. The CLOCK boundary of a mixed schedule (e.g.
      // clock ON + sunrise OFF) still lands in slots 0-7 below.

      // Determine preset ID: use assigned presetId if available, else fall back to legacy behavior
      final presetId = s.presetId ?? _presetForAction(s.actionLabel);

      // ON timer (clock only — a solar ON is placed positionally at slot 8/9)
      if (!onSolar) {
        final onTimer = _buildTimerEntry(
          timeLabel: s.timeLabel,
          dow: dow,
          macro: presetId,
        );
        if (onTimer != null) {
          timers.add(onTimer);
        }
      }

      // OFF timer (clock only; if schedule has an off time)
      if (s.hasOffTime &&
          s.offTimeLabel != null &&
          !offSolar &&
          timers.length < kMaxWledTimers) {
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

    // Return the REAL timers only — deliberately UNPADDED. Callers that push
    // this to the controller (syncAll, CalendarEntryLeaseManager) merge in any
    // lease timers and THEN pad the combined array to kMaxWledTimers via
    // [padTimersToMax], so vacated slots get zeroed on the controller. Padding
    // here would corrupt that merge (stubs would land between real timers), and
    // the eviction/time-parse tests assert the exact real-timer count.
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
        // WLED cfg parser is type-strict: en MUST be a JSON INT (1/0). A bool is
        // silently stored as 0 (disabled). Curl-proven 2026-07-22 on vid 2507300
        // (`{"en":true}`→en:0; `{"en":1}`→en:1). DO NOT change to a bool.
        'en': 1,
        'hour': isSunrise ? 24 : 25, // 24=sunrise, 25=sunset
        'min': 0, // offset from sunrise/sunset
        'macro': macro,
        'dow': dow,
      };
    }

    // Handle specific time
    final parsed = _parseTimeLabel(timeLabel);
    if (parsed == null) {
      // Unparseable clock time. NEVER fall back to midnight — that armed a
      // phantom 00:00 timer. Return null so buildCfgPayload drops this entry;
      // syncAll's pre-arm guard surfaces a warning so the schedule is flagged
      // rather than silently firing at the wrong time.
      debugPrint(
          'ScheduleSync: unparseable time label "$timeLabel" — timer not built');
      return null;
    }
    return {
      // Type-strict INT (see the solar branch above). DO NOT change to a bool.
      'en': 1,
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
  ///
  /// Accepts a [Ref] (provider-side) rather than [WidgetRef] so the
  /// notifier-driven auto-sync can call this directly. Both ref types
  /// expose the same `.read()` surface used inside this method.
  Future<ScheduleSyncResult> syncAll(Ref ref, List<ScheduleItem> schedules) async {
    // Records the result so the schedule screen can show a status row.
    ScheduleSyncResult finish(ScheduleSyncResult result) {
      ref.read(lastScheduleSyncResultProvider.notifier).state = result;
      return result;
    }

    // Attempt one connection refresh before giving up — covers the case
    // where the app just resumed and the connectivity stream hasn't
    // re-evaluated yet.
    var repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      try {
        await ref.read(wledStateProvider.notifier).refreshConnection();
        await Future.delayed(const Duration(milliseconds: 800));
        repo = ref.read(wledRepositoryProvider);
      } catch (e) {
        debugPrint('ScheduleSync: Connection refresh failed: $e');
      }
    }
    if (repo == null) {
      return finish(ScheduleSyncResult(
        success: false,
        error: 'Controller not reachable. Make sure you are on '
            'the same WiFi as your controller.',
      ));
    }

    // Non-null binding for use inside the closures below — Dart's null
    // promotion of [repo] (a reassignable local) does not cross into the
    // psaveIfChanged closure, so capture it once here after the guard.
    final activeRepo = repo;

    // ── Solar scheduling gate (Option B, bench-gated) ─────────────────────
    // Correctly-encoded sunrise/sunset (WLED 0.15.1 positional slots 8/9) is
    // routed ONLY when the solar_scheduling flag is ON *and* the controller has
    // usable coordinates (0,0 / unset → the firmware can't compute sunrise or
    // sunset, so the timer would never fire). Every other state keeps the
    // a75f504 refuse. The coord fetch only runs when the flag is on, so the
    // production (flag-off) path adds zero overhead.
    final solarFlagOn = ref.read(solarSchedulingEnabledSyncProvider);
    bool solarCoordsUsable = false;
    if (solarFlagOn && activeRepo is ClockInfoSource) {
      try {
        final info = await (activeRepo as ClockInfoSource).fetchClockInfo();
        final lat = info?.latitude;
        final lon = info?.longitude;
        solarCoordsUsable =
            lat != null && lon != null && !(lat == 0 && lon == 0);
      } catch (_) {
        solarCoordsUsable = false;
      }
    }
    final solarEnabled = solarFlagOn && solarCoordsUsable;

    final enabled = schedules.where((s) => s.enabled).toList();

    // Step 1: Assign preset IDs and save presets to device
    final List<ScheduleItem> updatedSchedules = [];
    final List<String> presetErrors = [];

    // Tracks which preset IDs were actually psaved this sync. Used below to
    // refuse arming a runPattern timer macro that points at a preset that was
    // never saved (the silent-arm bug). A macro is only armed if its preset id
    // is in this set or maps to a legacy on/off/brightness preset.
    final Set<int> savedPresetIds = <int>{};

    // ── Idempotent-write + capture/restore scaffolding ──────────────────
    // ROOT CAUSE this guards against: every `savePreset` POSTs its inline
    // state to /json/state with `psave`, and on this firmware WLED APPLIES
    // that state to the live strip before snapshotting it (bench-confirmed on
    // 0.15.1: an OFF strip flips ON after `{on:true,bri:153,psave:5}`). The
    // old code re-`psave`d the whole 1–5 block on EVERY mutation, so the last
    // write (preset 5 = on/bri153, no color) left the strip solid-on whenever
    // a schedule was saved and the user navigated away.
    //
    // Two-part fix:
    //   1. Read the controller's current presets once and only `psave` a slot
    //      whose stored definition no longer matches what we want. A re-sync
    //      that changes nothing writes nothing → no live-output change.
    //   2. Capture live /json/state before the (now rare) writes; if any write
    //      happened, re-apply it afterward so the strip ends exactly where it
    //      started. The only non-applying save shape WLED offers here — a bare
    //      `{psave:N}` — can't define a *differing* preset, so capture/restore
    //      is the mechanism for the writes that must happen.
    // Preset defs come from the on-LAN HTTP service only (GET /presets.json);
    // for any other repo (cloud relay / mock) we treat presets as unknown and
    // fall back to writing — the capture/restore below still guards output.
    final Map<int, Map<String, dynamic>> existingPresets =
        activeRepo is WledService ? await activeRepo.fetchPresets() : const {};
    final Map<String, dynamic>? capturedLiveState = await activeRepo.getState();
    bool didWriteAnyPreset = false;

    // psave [state]→[id] ONLY when [isSatisfied] reports the slot's current
    // definition is wrong/absent. On skip the slot is already correct, so it
    // still counts as armable (added to savedPresetIds) — the empty-macro
    // guard below must not refuse a schedule whose preset we deliberately left
    // in place. On a real write, trip didWriteAnyPreset so the caller restores.
    Future<void> psaveIfChanged({
      required int id,
      required Map<String, dynamic> state,
      required String name,
      required bool Function(Map<String, dynamic> existingDef) isSatisfied,
    }) async {
      final existing = existingPresets[id];
      if (existing != null && isSatisfied(existing)) {
        savedPresetIds.add(id);
        return;
      }
      final ok = await activeRepo.savePreset(
        presetId: id,
        state: state,
        presetName: name,
      );
      if (ok) {
        didWriteAnyPreset = true;
        savedPresetIds.add(id);
      } else {
        presetErrors.add('Failed to save preset $id ($name)');
      }
    }

    // System presets — fixed definitions, so once present with the right name
    // they are never rewritten (this is what stops the every-sync storm).
    //   1 = On, 3/4/5 = Dim/Low/Medium brightness (referenced by
    //   _presetForAction; bri = round(pct*255/100): 20%→51, 40%→102, 60%→153).
    // `ib: true` on every ON-preset makes WLED PERSIST the root master on/bri
    // into the stored preset. Without it presets store SEGMENTS ONLY, so firing
    // an ON-timer from a master-off state loads the design but leaves the master
    // OFF → strip DARK. Bench-proven 2026-07-22 (vid 2507300): slot 250 (plain
    // psave) → segments-only, load from master-off leaves master off; slot 249
    // (psave + ib:true) → root {"on":true,"bri":255} persisted, load from
    // master-off → master TRUE. So the ON-timer asserts master power at fire
    // time via the preset itself. OFF preset 2 is intentionally left without ib
    // (its lights-off is via seg.on:false — see below).
    await psaveIfChanged(
      id: 1,
      state: {'on': true, 'bri': 200, 'ib': true},
      name: 'NGL On',
      isSatisfied: (d) => _presetNamed(d, 'NGL On'),
    );
    // Preset 2 = Off. OFF timers fire `macro: 2`; a slot left holding an ON
    // design (seen in the field — wrong-named/legacy writes) silently turns the
    // lights ON at the OFF boundary instead of off. Repair it whenever the
    // stored slot isn't actually off. We write seg.on:false explicitly so the
    // _presetIsOff check is stable on the next sync (this firmware stores
    // on-state per-segment, with no top-level `on` key).
    await psaveIfChanged(
      id: 2,
      state: {
        'on': false,
        'seg': [
          {'on': false}
        ],
      },
      name: 'NGL Off',
      isSatisfied: (d) => _presetNamed(d, 'NGL Off') && _presetIsOff(d),
    );
    await psaveIfChanged(
      id: 3,
      state: {'on': true, 'bri': 51, 'ib': true},
      name: 'NGL Dim',
      isSatisfied: (d) => _presetNamed(d, 'NGL Dim'),
    );
    await psaveIfChanged(
      id: 4,
      state: {'on': true, 'bri': 102, 'ib': true},
      name: 'NGL Low',
      isSatisfied: (d) => _presetNamed(d, 'NGL Low'),
    );
    await psaveIfChanged(
      id: 5,
      state: {'on': true, 'bri': 153, 'ib': true},
      name: 'NGL Medium',
      isSatisfied: (d) => _presetNamed(d, 'NGL Medium'),
    );

    int nextPresetId = _firstSchedulePresetId;

    for (final schedule in enabled) {
      // If this schedule uses audio reactivity, build a WLED payload with a
      // random audio-reactive effect from the controller. This can turn an
      // otherwise payload-less schedule into a payload-bearing one, so it MUST
      // run before the slot decision below.
      var effectiveSchedule = schedule;
      if (schedule.useAudioReactive == true) {
        final ip = ref.read(selectedDeviceIpProvider);
        if (ip != null) {
          final capAsync = ref.read(audioCapabilityProvider(ip));
          final cap = capAsync.valueOrNull;
          if (cap != null && cap.isSupported && cap.audioReactiveEffects.isNotEmpty) {
            final rng = math.Random();
            final randomFxId = cap.audioReactiveEffects[
                rng.nextInt(cap.audioReactiveEffects.length)];
            final audioPayload = <String, dynamic>{
              'on': true,
              'seg': [
                {
                  'fx': randomFxId,
                  'sx': 128,
                  'ix': 128,
                }
              ],
            };
            effectiveSchedule = schedule.copyWith(
              wledPayload: audioPayload,
            );
          }
        }
      }

      if (effectiveSchedule.hasWledPayload) {
        // Payload-bearing (pattern / audio-reactive): consume a per-schedule
        // preset slot in the 10–25 range and psave the design there.
        if (effectiveSchedule.presetId == null &&
            nextPresetId > _lastSchedulePresetId) {
          // Out of pattern-preset slots. Leave presetId untouched (null) so the
          // pattern partition below refuses to arm it and warns — never arm a
          // macro with no preset. Kept in updatedSchedules so the warning path
          // still sees it.
          updatedSchedules.add(effectiveSchedule);
          continue;
        }
        final presetId = effectiveSchedule.presetId ?? nextPresetId;
        if (effectiveSchedule.presetId == null) nextPresetId++;

        // Option A (2026-07-22): ALWAYS psave the schedule's design — no
        // idempotent skip. The old fx+first-color skip (_scheduleDesignMatches)
        // was structurally under-specified (ignored master on, bri, palette,
        // per-seg on, and every segment past seg[0]), so it silently left stale
        // presets un-repaired forever — bench: preset 10 held the right design
        // but master on:false, so the schedule fired DARK, and Sync kept skipping
        // the re-save. Drop the skip; the capture/restore below absorbs the
        // live-output cost, and the settle + patient verify absorb the flash cost.
        //
        // Guarantee the ON-preset is never saved dark: a pattern/audio schedule
        // is an ON action, so force on:true + an explicit bri into the saved
        // state (OFF actions are payload-less and arm preset 2, handled above —
        // never reach here — so this never disables an intended-off schedule).
        final rawPayload = effectiveSchedule.wledPayload!;
        final presetPayload = <String, dynamic>{
          ...rawPayload,
          'on': true,
          'bri': (rawPayload['bri'] as num?)?.toInt() ?? 255,
          // ib:true → WLED persists the root master on/bri (not just segments),
          // so firing this ON-preset from a master-off state powers the strip on.
          // Bench-proven (see the system-preset block above). normalizeWledPayload
          // preserves this top-level key, so it reaches the psave wire.
          'ib': true,
        };
        await psaveIfChanged(
          id: presetId,
          state: presetPayload,
          name: effectiveSchedule.actionLabel,
          isSatisfied: (_) => false, // always write — see Option A above
        );

        updatedSchedules.add(effectiveSchedule.copyWith(presetId: presetId));
      } else {
        // Payload-less legacy action (Turn On / Turn Off / Brightness): do NOT
        // consume a 10–25 preset slot. Clear any stale stored presetId (a 10+
        // id left over from the pre-fix era) so buildCfgPayload resolves the
        // macro via _presetForAction to a real legacy preset 1–5 — all psaved
        // above — instead of a never-saved 10+ slot.
        updatedSchedules.add(effectiveSchedule.copyWith(clearPresetId: true));
      }
    }

    // ── Restore live output (non-disruptive save) ────────────────────────
    // Every psave above APPLIED its inline state to the live strip (this
    // firmware has no non-applying save for a differing preset), and under the
    // always-psave policy that now happens on EVERY Sync. Re-apply the state we
    // captured BEFORE the batch so the strip ends EXACTLY where it started —
    // pressing Sync, or saving/editing a schedule, must NEVER turn the system on
    // or change the look. `transition:0` snaps it back with no visible fade.
    // This runs before the cfg write + settle, so it is the last thing to touch
    // live output. It never touches timers — the RTC owns the ON/OFF boundaries.
    if (didWriteAnyPreset && capturedLiveState != null) {
      final restore = <String, dynamic>{
        'transition': 0,
        if (capturedLiveState['on'] != null) 'on': capturedLiveState['on'],
        if (capturedLiveState['bri'] != null) 'bri': capturedLiveState['bri'],
        if (capturedLiveState['seg'] != null) 'seg': capturedLiveState['seg'],
      };
      // >1 key means we captured real state (on/bri/seg), not just transition.
      if (restore.length > 1) {
        final restored = await repo.applyJson(restore);
        if (!restored) {
          debugPrint(
              'ScheduleSync: live-state restore after preset writes failed');
        }
      }
    } else if (didWriteAnyPreset) {
      debugPrint('ScheduleSync: wrote presets but had no captured live state '
          'to restore — strip may reflect the last preset written');
    }

    // ── Defense-in-depth: never silently arm an empty macro ──────────────
    // A runPattern schedule whose design payload didn't persist as a preset
    // (e.g. a legacy entry saved with wledPayload:null) would otherwise arm an
    // ON-timer macro pointing at a preset that was never saved. WLED fires the
    // macro, the preset is missing, nothing happens — lights stay off and
    // never wake. That silent-arm is exactly how the bug stayed invisible.
    // Partition those out, warn loudly (surfaces via lastScheduleSyncResult →
    // _SyncStatusRow as "Synced with warnings"), and never arm them. Non-
    // pattern actions (Turn Off/On, Brightness) map to legacy presets and are
    // left untouched; audio-reactive items already had a payload built above.
    final List<ScheduleItem> armable = [];
    for (final s in updatedSchedules) {
      final isPatternAction = s.actionLabel.toLowerCase().startsWith('pattern');
      final presetSaved =
          s.presetId != null && savedPresetIds.contains(s.presetId);
      if (isPatternAction && !presetSaved) {
        presetErrors.add(
            '"${s.actionLabel}" has no saved design — not armed. Re-open the '
            'schedule and pick a pattern.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — no '
            'preset saved at id ${s.presetId}');
        continue;
      }

      // ── Never silently arm a timer pointing at the wrong time ──────────
      // A time label that doesn't resolve to a real clock time (or a solar
      // keyword) used to fall back to 00:00 and fire the macro at MIDNIGHT.
      // Refuse to arm such a schedule — surface a warning instead. Both
      // boundaries are checked together: a half-parseable schedule (good ON,
      // bad OFF) would otherwise turn lights ON and never OFF, so the whole
      // entry is left unarmed. Mirrors the dead-macro invariant above.
      final badLabels = <String>[
        if (!_isArmableTimeLabel(s.timeLabel)) s.timeLabel,
        if (s.hasOffTime &&
            s.offTimeLabel != null &&
            !_isArmableTimeLabel(s.offTimeLabel!))
          s.offTimeLabel!,
      ];
      if (badLabels.isNotEmpty) {
        presetErrors.add(
            '"${s.actionLabel}" has an unrecognized time '
            '(${badLabels.join(", ")}) — not armed. Re-open the schedule and '
            'set a valid time.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — '
            'unparseable time label(s): ${badLabels.join(", ")}');
        continue;
      }

      // ── Sunrise/sunset gate (refuse-and-warn unless solar is enabled) ──
      // When the solar_scheduling flag is ON *and* the controller has usable
      // coordinates, correctly-encoded solar (hour:255 at slot 8/9) is armed
      // downstream — so DON'T refuse here. Otherwise refuse-and-warn (the
      // a75f504 production behavior), distinguishing the two off states so the
      // user gets an actionable message. _isArmableTimeLabel treats solar as
      // valid, so the bad-time guard above does NOT catch this.
      final solarLabels = <String>[
        if (_isSolarLabel(s.timeLabel)) s.timeLabel,
        if (s.hasOffTime &&
            s.offTimeLabel != null &&
            _isSolarLabel(s.offTimeLabel!))
          s.offTimeLabel!,
      ];
      if (solarLabels.isNotEmpty && !solarEnabled) {
        final why = solarFlagOn
            ? 'needs your location set on the controller — sunrise/sunset '
                'can\'t be computed without it'
            : 'isn\'t supported yet — please set a specific time';
        presetErrors.add(
            '"${s.actionLabel}" uses sunrise/sunset timing, which $why.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — solar '
            'not enabled (flagOn=$solarFlagOn coordsUsable=$solarCoordsUsable; '
            '${solarLabels.join(", ")})');
        continue;
      }

      // ── Never arm a dead dow:0 timer ───────────────────────────────────
      // An empty or all-unrecognized repeatDays yields a zero WLED dow mask
      // ("no days"), so the timer would take a slot but never fire — the
      // silent dead-timer that accumulates until the 8-slot table is full.
      // Refuse-and-warn (policy: never silently normalize to daily); the
      // schedule stays saved in Firestore, it just isn't armed. Mirrors the
      // dead-macro / bad-time invariants above.
      if (_computeDowMask(s.repeatDays) == 0) {
        presetErrors.add(
            '"${s.actionLabel}" has no repeat days — not armed. Re-open the '
            'schedule and pick at least one day.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — '
            'repeatDays produced dow:0 (${s.repeatDays})');
        continue;
      }

      armable.add(s);
    }

    // ── Slot capacity: which armable schedules actually fit the 8-slot table ─
    // buildCfgPayload truncates at kMaxWledTimers; mirror its slot accounting
    // here so we (a) surface a loud warning when schedules overflow and (b)
    // count only the schedules that armed — never claim success for one that
    // silently fell off the controller.
    final capacity =
        splitByTimerCapacity(armable, solarEnabled: solarEnabled);
    final armedSchedules = capacity.armed;
    if (capacity.overflowed) {
      presetErrors.add(
          "Schedule saved but couldn't arm — controller timer slots are full "
          "(8/8). Delete an old schedule.");
      debugPrint('ScheduleSync: ${armable.length - armedSchedules.length} '
          'schedule(s) could not arm — WLED timer table full (8/8)');
    }

    // Step 2: Build and push timer configuration. Clock timers fill slots 0-7;
    // the array is padded so a vacated slot is overwritten with a disabled stub
    // (slot reclaim — clears dow:0 / stale timers). When solar is enabled the
    // push is a 10-entry array with the sunrise timer at slot 8 and sunset at
    // slot 9 (WLED 0.15.1 positional encoding); otherwise it's the 8-slot form.
    final built =
        buildCfgPayload(armedSchedules, solarEnabled: solarEnabled);
    final builtIns = ((built['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    final List<Map<String, dynamic>> ins;
    if (solarEnabled) {
      final solar = solarTimerSlots(armedSchedules);
      // Only one sunrise slot (8) and one sunset slot (9) exist — reject-and-
      // warn any additional solar boundary (cross-schedule constraint).
      for (final who in solar.rejected) {
        presetErrors.add(
            'Only one sunrise and one sunset schedule are supported per '
            'controller — "$who" was not armed.');
        debugPrint('ScheduleSync: solar slot already taken — dropped $who');
      }
      ins = assembleSolarAwareIns(builtIns,
          sunrise: solar.sunrise, sunset: solar.sunset);
    } else {
      ins = padTimersToMax(builtIns);
    }
    final payload = <String, dynamic>{
      'timers': {'ins': ins},
    };

    // Empty-armed guard: armedSchedules passed every arm check, so they MUST
    // have produced real timer entries. If the built payload has NONE (all
    // stubs), something in the build/reader dropped them (e.g. an enabled flag
    // that didn't survive the doc round-trip — the AI-doc class). The
    // content-match comparator would then trivially pass on an all-stub payload
    // and report a false green. Fail loudly; never POST a no-op that arms nothing.
    if (armedSchedules.isNotEmpty && !ins.any(isRealEnabledTimer)) {
      debugPrint('ScheduleSync: ABORT — ${armedSchedules.length} armable '
          'schedule(s) but the built payload has zero real timers (all stubs). '
          'Refusing to POST a no-op that would false-green.');
      return finish(ScheduleSyncResult(
        success: false,
        error: 'internal: enabled schedules produced no armable timers',
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      ));
    }

    // Arming is a /json/cfg write. The bridge cannot deliver one (it routes
    // everything but getState/getInfo to /json/state, where WLED discards cfg
    // keys and returns 200) — so off-LAN this used to report SUCCESS while the
    // timers never armed. Check before spending a command round-trip, and say
    // so plainly instead of claiming a save that didn't happen or an error that
    // didn't occur. Presets above already landed: they go via /json/state.
    if (!repoCanWriteCfg(repo)) {
      debugPrint('ScheduleSync: off-LAN — timers not armed (bridge cannot '
          'write /json/cfg); schedule saved, will arm on next LAN sync');
      return finish(ScheduleSyncResult.deferredOffLan(
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      ));
    }

    // Settle (point 1): the preset psaves above are flash writes. Give the
    // controller a beat to finish committing them before it must handle the cfg
    // flash-save, so the cfg POST doesn't queue behind an in-progress commit and
    // time out. Only when we actually wrote a preset this sync.
    if (didWriteAnyPreset) {
      await Future<void>.delayed(const Duration(milliseconds: 900));
    }

    try {
      // Single POST + patient verify through the controller's post-commit stall
      // (see _pushCfgWithVerify). Three terminal outcomes → three results.
      final outcome = await _pushCfgWithVerify(ref, repo, payload, ins);
      switch (outcome) {
        case _CfgPushOutcome.confirmed:
          return finish(ScheduleSyncResult(
            success: true,
            presetErrors: presetErrors,
            // Count only schedules that actually armed — never overcount a
            // schedule dropped for a full table / dow:0 / bad time.
            schedulesWithPresets: armedSchedules,
          ));
        case _CfgPushOutcome.mismatch:
          // 2xx but the controller stored different values — a firmware-
          // compatibility signal, not a transient. Surface it, don't warn-away.
          return finish(ScheduleSyncResult(
            success: false,
            error: kScheduleCfgFirmwareMismatch,
            presetErrors: presetErrors,
            schedulesWithPresets: updatedSchedules,
          ));
        case _CfgPushOutcome.notConfirmed:
          return finish(ScheduleSyncResult(
            success: false,
            error: kScheduleCfgWriteFailed,
            presetErrors: presetErrors,
            schedulesWithPresets: updatedSchedules,
          ));
      }
    } on CfgWriteUnsupportedException catch (e) {
      // Backstop — the supportsCfgWrites pre-flight above should already have
      // returned. Never let this reach the generic catch, which would dress a
      // known-unsupported transport up as "Exception: ..." in the user's face.
      debugPrint('ScheduleSync: cfg writes unsupported on this transport: $e');
      return finish(ScheduleSyncResult.deferredOffLan(
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      ));
    } catch (e) {
      debugPrint('ScheduleSync: Exception during sync: $e');
      return finish(ScheduleSyncResult(
        success: false,
        error: 'Exception: $e',
        presetErrors: presetErrors,
        schedulesWithPresets: updatedSchedules,
      ));
    }
  }

  /// Push the timer cfg ONCE, then VERIFY — modeling the bench-proven stall:
  /// the POST /json/cfg COMMITS the timers to flash, but the commit then freezes
  /// the controller's web server / WiFi for MINUTES (the LEDs keep running and
  /// it self-recovers — no crash, no power cycle). Re-POSTing into that blackout
  /// is harmful: the controller can't answer, and a duplicate write on recovery
  /// re-triggers the stall. So we do NOT retry the write — we wait for the
  /// controller to come back and confirm by readback.
  ///
  /// Returns true iff the timers are confirmed on the controller.
  /// - 2xx → immediate readback content-match. The 2xx is authoritative, so a
  ///   readback mismatch is warned, not failed.
  /// - timeout / connection error → assume the post-commit stall and enter
  ///   patient verification ([verifyCfgAfterStall]); NO re-POST unless the
  ///   controller recovers and the timers still aren't there.
  /// A [CfgWriteUnsupportedException] propagates out (→ deferredOffLan in
  /// syncAll). [ins] is the exact array we sent (post-normalize).
  Future<_CfgPushOutcome> _pushCfgWithVerify(
    Ref ref,
    WledRepository repo,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> ins,
  ) async {
    final ok = await repo.applyConfig(payload);
    if (ok) {
      // 2xx — the write reported success. Still readback-verify.
      final verified = await _readbackTimersLanded(repo, ins);
      if (verified == true) return _CfgPushOutcome.confirmed;
      if (verified == false) {
        // Content-match already tolerates echo compaction + solar sentinels, so
        // a genuine mismatch is a real defect (firmware stored our values wrong).
        debugPrint('ScheduleSync: cfg 2xx but readback CONTENT-MISMATCH — the '
            'controller stored different values; failing loudly');
        return _CfgPushOutcome.mismatch;
      }
      // verified == null: the readback couldn't be fetched. On this hardware a
      // null right after a 2xx means the controller is stalling on the
      // post-commit flash save (the GET returns an empty body). DO NOT trust the
      // 2xx — a disabled/rejected write (e.g. the bool-en bug) would slip through
      // green. Fall through to the patient verify-poll to wait for recovery and
      // content-match. A relay/webhook can't be polled, so THERE a 2xx is trusted.
      if (repo is! WledService) return _CfgPushOutcome.confirmed;
      debugPrint('ScheduleSync: cfg 2xx but readback unavailable (controller '
          'likely stalling) — verifying patiently, NOT trusting the 2xx');
    } else {
      // POST returned false. On the LAN service this is the post-commit stall:
      // the flash write landed, but the HTTP response never came back before the
      // web server froze. For a relay/webhook a false is a genuine failure with
      // no stall model — fail fast (no minutes-long polling of a webhook).
      if (repo is! WledService) return _CfgPushOutcome.notConfirmed;
      debugPrint('ScheduleSync: cfg POST returned false on LAN — assuming the '
          'post-commit network stall; NOT re-POSTing, verifying patiently');
    }

    // Patient verify-poll — reached on (applyConfig==false) OR (2xx + null
    // readback) on the LAN service. Wait for the controller to answer again,
    // then content-match; NO re-POST unless it recovers and still mismatches.
    final wledRepo = repo; // promoted to WledService by the guards above
    ref.read(lastScheduleSyncResultProvider.notifier).state =
        ScheduleSyncResult.verifying();

    final started = DateTime.now();
    final confirmed = await verifyCfgAfterStall(
      liveness: () => wledRepo.ping(),
      readbackMatch: () => _readbackTimersLanded(wledRepo, ins),
      rePost: () async {
        try {
          return await wledRepo.applyConfig(payload);
        } catch (_) {
          return false;
        }
      },
      delay: (d) => Future<void>.delayed(d),
    );
    final stalledFor = DateTime.now().difference(started).inSeconds;
    if (confirmed) {
      debugPrint('ScheduleSync: controller stalled ~${stalledFor}s after the cfg '
          'commit; write VERIFIED on recovery');
      return _CfgPushOutcome.confirmed;
    }
    debugPrint('ScheduleSync: controller did not confirm the cfg write within '
        'the ${stalledFor}s verification window');
    return _CfgPushOutcome.notConfirmed;
  }

  /// Readback content-match: does the controller's timer table CONTAIN the real
  /// timers we [sent]? true = confirmed, false = recovered-but-not-present,
  /// null = couldn't read (relay/mock, or fetch error / still stalled) →
  /// inconclusive, never a false negative. Uses [timersInsLanded] (content, not
  /// per-index — the controller compacts/reorders the array).
  Future<bool?> _readbackTimersLanded(
    WledRepository repo,
    List<Map<String, dynamic>> sent,
  ) async {
    if (repo is! WledService) return null; // cfg is not readable via the relay
    final actual = await repo.fetchTimerInstances();
    if (actual == null) return null;
    return timersInsLanded(sent, actual);
  }

  /// Legacy sync method for backward compatibility.
  /// Prefer using [syncAll] which returns detailed results.
  Future<bool> syncAllLegacy(Ref ref, List<ScheduleItem> schedules) async {
    final result = await syncAll(ref, schedules);
    return result.success;
  }

  // Helpers

  /// Parses a clock-time label into hour/minute for a WLED timer.
  ///
  /// Accepts both 12-hour ("7:05 PM", "12:00 AM") and bare 24-hour
  /// ("10:11", "23:30", "0:05") formats. Sunrise/sunset are resolved by
  /// [_buildTimerEntry] before this is reached; the keyword branch here is
  /// purely defensive and never arms a clock time.
  ///
  /// Returns `null` for a genuinely unrecognized label. Callers MUST treat
  /// null as "do not arm". The pre-fix behavior silently fell back to 00:00,
  /// so a bare malformed label (or an un-suffixed 24-hour time that didn't
  /// match the am/pm regex) armed a phantom MIDNIGHT timer with no warning.
  /// Never default an unparseable time to midnight.
  _ParsedTime? _parseTimeLabel(String label) {
    final l = label.trim().toLowerCase();
    // Sunrise/sunset are handled separately by _buildTimerEntry; defensive.
    if (l == 'sunrise' || l == 'sunset') {
      return const _ParsedTime(hour: 0, minute: 0);
    }
    // 12-hour: "7:05 PM" / "12:00 AM"
    final ampm = RegExp(r'^(\d{1,2}):(\d{2})\s*([ap]m)$', caseSensitive: false);
    final m = ampm.firstMatch(l);
    if (m != null) {
      var hh = int.tryParse(m.group(1)!) ?? -1;
      final mm = int.tryParse(m.group(2)!) ?? -1;
      final ap = m.group(3)!.toLowerCase();
      if (hh < 1 || hh > 12 || mm < 0 || mm > 59) return null;
      if (ap == 'pm' && hh != 12) hh += 12;
      if (ap == 'am' && hh == 12) hh = 0;
      return _ParsedTime(hour: hh, minute: mm);
    }
    // 24-hour: "10:11" / "23:30" / "0:05"
    final h24 = RegExp(r'^(\d{1,2}):(\d{2})$');
    final m24 = h24.firstMatch(l);
    if (m24 != null) {
      final hh = int.tryParse(m24.group(1)!);
      final mm = int.tryParse(m24.group(2)!);
      if (hh == null || mm == null || hh > 23 || mm > 59) return null;
      return _ParsedTime(hour: hh, minute: mm);
    }
    // Genuinely unparseable — do NOT default to midnight. Return null so the
    // caller leaves the schedule unarmed and flags it.
    return null;
  }

  /// True when [label] is a time WLED can actually arm: a solar keyword or a
  /// clock time [_parseTimeLabel] recognizes. Used by [syncAll] to refuse
  /// arming a timer that would otherwise silently fire at midnight.
  bool _isArmableTimeLabel(String label) {
    final l = label.trim().toLowerCase();
    if (l == 'sunrise' || l == 'sunset') return true;
    return _parseTimeLabel(label) != null;
  }

  /// True for the two solar keywords the app (wrongly) maps to WLED hour 24/25.
  /// Used by the Option-A refuse guards until solar is re-encoded correctly —
  /// see memory/project_solar_schedules_never_fire.
  static bool _isSolarLabel(String label) {
    final l = label.trim().toLowerCase();
    return l == 'sunrise' || l == 'sunset';
  }

  /// Compute the WLED dow bitmask for a list of weekday names.
  /// Delegates to the centralized [wledDowMaskForDayList] helper.
  /// See [wled_dow.dart] for the canonical Mon=bit 0..Sun=bit 6
  /// convention (Item #72 — corrected 2026-05-19).
  int _computeDowMask(List<String> days) => wledDowMaskForDayList(days);

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

  // ── Preset-idempotence helpers (used by syncAll) ──────────────────────
  // These read a stored preset definition (as returned by
  // [WledRepository.fetchPresets]) and decide whether it already matches what
  // we would write, so the sync can skip the psave (and its live-apply flash).

  /// True when the stored preset's name equals [name] (trimmed).
  static bool _presetNamed(Map<String, dynamic> def, String name) =>
      def['n'] is String && (def['n'] as String).trim() == name;

  /// True when the preset represents an OFF state. This firmware stores
  /// on-state per-segment (no top-level `on` key on saved presets), so a
  /// preset is "off" only when no segment is left on. Falls back to a
  /// top-level `on:false` for builds that do store it.
  static bool _presetIsOff(Map<String, dynamic> def) {
    final seg = def['seg'];
    if (seg is List) {
      for (final s in seg) {
        if (s is Map && s['on'] == true) return false;
      }
      return true;
    }
    return def['on'] == false;
  }
}

class _ParsedTime {
  final int hour;
  final int minute;
  const _ParsedTime({required this.hour, required this.minute});
}

final scheduleSyncServiceProvider = Provider<ScheduleSyncService>((ref) => const ScheduleSyncService());

/// Most recent result from [ScheduleSyncService.syncAll]. The schedule UI
/// reads this to render a sync status row (success/warning/offline).
/// `null` until the first sync attempt of this app session.
final lastScheduleSyncResultProvider =
    StateProvider<ScheduleSyncResult?>((ref) => null);

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

  /// Wall-clock time the sync attempt completed.
  /// Used by the schedule UI to show "last synced X ago".
  final DateTime syncedAt;

  /// The schedule was SAVED but its timers could not be armed because the app
  /// is off the home network: arming is a /json/cfg write, which the bridge
  /// cannot deliver (see [WledRepository.supportsCfgWrites]). This is NOT a
  /// failure — nothing broke and there is nothing to retry — so [success] is
  /// false (the timers genuinely did not arm) while the UI must present it as
  /// neutral information, not an error. It resolves itself the next time the
  /// user syncs on their home WiFi.
  final bool deferredOffLan;

  /// The sync was requested BEFORE the schedule stream hydrated from Firestore,
  /// so it was deferred rather than run against the empty pre-load state (which
  /// would push disabled-stub timers over the device's real ones and falsely
  /// report success on the 200). Like [deferredOffLan] this is NOT a failure and
  /// NOT success — nothing was written. It resolves itself: [SchedulesNotifier]
  /// re-runs the sync the instant the stream loads. Distinct from "hydrated with
  /// genuinely zero schedules", which DOES push (to clear the device).
  final bool deferredNotLoaded;

  /// Transient, interim state pushed to [lastScheduleSyncResultProvider] while
  /// we are VERIFYING a cfg write through the controller's post-commit network
  /// stall (see [ScheduleSyncService] cfg push). It is neither success nor
  /// failure — the write has committed and we're waiting for the controller to
  /// come back and confirm — so the UI shows the calm "Saving to controller —
  /// this can take a few minutes. Your lights keep working." copy instead of a
  /// red error. The terminal result (success / cfg-write-failed / deferred)
  /// replaces it when verification resolves. Never the awaited return of a sync.
  final bool verifying;

  ScheduleSyncResult({
    required this.success,
    this.error,
    this.presetErrors = const [],
    this.schedulesWithPresets = const [],
    this.deferredOffLan = false,
    this.deferredNotLoaded = false,
    this.verifying = false,
    DateTime? syncedAt,
  }) : syncedAt = syncedAt ?? DateTime.now();

  /// Saved to the cloud, but not armed on the controller — the user is off-LAN.
  factory ScheduleSyncResult.deferredOffLan({
    List<ScheduleItem> schedulesWithPresets = const [],
    List<String> presetErrors = const [],
  }) =>
      ScheduleSyncResult(
        success: false,
        deferredOffLan: true,
        error: kScheduleOffLanNotice,
        presetErrors: presetErrors,
        schedulesWithPresets: schedulesWithPresets,
      );

  /// Deferred because the schedule stream had not yet hydrated. No device write
  /// happened; [SchedulesNotifier] re-runs the sync once the stream loads.
  factory ScheduleSyncResult.notLoaded() => ScheduleSyncResult(
        success: false,
        deferredNotLoaded: true,
      );

  /// Interim "verifying the write through the controller's stall" state (see
  /// [verifying]). Pushed to the status provider while polling; never returned.
  factory ScheduleSyncResult.verifying() => ScheduleSyncResult(
        success: false,
        verifying: true,
      );

  /// Returns true if there were any preset-related errors.
  bool get hasPresetErrors => presetErrors.isNotEmpty;

  /// Returns a summary message suitable for user display.
  String get summaryMessage {
    if (verifying) return kScheduleCfgVerifying;
    if (deferredOffLan) return kScheduleOffLanNotice;
    if (deferredNotLoaded) return 'Loading your schedules…';
    if (!success) {
      return error ?? 'Sync failed';
    }
    if (hasPresetErrors) {
      return 'Synced with ${presetErrors.length} warning(s)';
    }
    return 'Successfully synced ${schedulesWithPresets.length} schedule(s)';
  }
}

/// User-facing copy for an off-LAN schedule save. Deliberately not phrased as a
/// failure: the schedule IS saved, it just can't reach the controller's timer
/// table from here.
const String kScheduleOffLanNotice =
    "Saved — your schedule will arm next time you're on your home WiFi.";

/// Interim copy shown while verifying the write through the controller's
/// post-commit stall. Not an error — the write committed and the controller
/// will answer once it recovers (the LEDs keep running meanwhile).
const String kScheduleCfgVerifying =
    'Saving to controller — this can take a few minutes. Your lights keep working.';

/// Terminal failure copy for the case where the controller never answered
/// within the verification window (didn't recover). Actionable and distinct
/// from the off-LAN notice: the user IS on the network, so the fix is to make
/// sure the controller is powered and on WiFi, then retry.
const String kScheduleCfgWriteFailed =
    'Couldn\'t confirm your schedule saved — the controller didn\'t respond. '
    'Check that it\'s powered and on WiFi, then press Sync again.';

/// Terminal failure copy for a 2xx write whose readback content did NOT match
/// what we sent — the controller accepted the POST but stored different values,
/// which points at a firmware incompatibility rather than a transient.
const String kScheduleCfgFirmwareMismatch =
    'Schedule saved but the controller reported different values — sync may be '
    'incompatible with this controller\'s firmware. Contact support if this '
    'repeats.';
