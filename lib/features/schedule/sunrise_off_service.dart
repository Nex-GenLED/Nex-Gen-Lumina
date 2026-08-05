// lib/features/schedule/sunrise_off_service.dart
//
// GLOBAL SUNRISE-OFF — an opt-in, controller-resident WLED timer that sets
// MASTER OFF at sunrise every day, independent of any design, schedule or
// pattern, and fires with the app CLOSED.
//
// WHY THIS EXISTS
// ---------------
// Manual apply (Explore Patterns → Apply) writes /json/state only — it never
// arms an off-timer (apply_saved_design.dart: a single repo.applyJson). The
// only thing that used to promise "off at sunrise" was
// schedule_off_warning.dart, which is a SnackBar about a *different* object (an
// autopilot baseline schedule). Confirmed on hardware via /json/cfg: timers.ins
// held nothing but empty sentinels. This service closes that gap by arming a
// real firmware timer, so the OFF is owned by the controller, not the app.
//
// ENCODING — READ BEFORE CHANGING
// -------------------------------
// The sunrise trigger is POSITIONAL on WLED 0.15.1: `timers.ins[8]` IS sunrise
// (index 9 is sunset). `checkTimers()` special-cases those two slots; the
// `hour` field is IGNORED there and `min` is a signed OFFSET in minutes, not a
// wall-clock minute. `hour:255` is the firmware's own serialized marker and is
// what we write.
//
// It is NOT `hour:24`. In WLED, hour 24 means "fire HOURLY" (match on minute
// only) and hour 25 never matches the RTC at all. Writing hour:24 here would
// turn the customer's lights off 24 times a day, every day — that is the exact
// fleet bug a75f504 was shipped to remediate. See
// ScheduleSyncService.kWledSolarHourMarker and schedule_solar_encoding_test.
//
// SLOT + MACRO
// ------------
// Slot 8 (ScheduleSyncService.kWledSunriseSlot) is OUTSIDE the 8-slot general
// pool, so this collides with neither schedule timers nor P0-3 lease timers
// (macro 26-41) by construction. There is exactly one sunrise slot in the
// firmware, so "never two sunrise-off timers" is a hardware guarantee, not an
// app-side invariant we have to police.
//
// Macro 2 = the "NGL Off" preset, saved as {'on': false, 'ib': true, seg all
// off} (schedule_sync.dart). `ib` persists root on:false, so LOADING it kills
// master power regardless of what pattern is running. It is an ABSOLUTE state
// load, never a toggle — so if another timer also lands on sunrise, both
// resolve to "off". Idempotent; no power-back-on race.

import 'package:cloud_firestore/cloud_firestore.dart' show Timestamp;
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart'
    show CfgPushOutcome, ScheduleSyncService, pushCfgWithVerify;
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart'
    show repoCanWriteCfg;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart'
    show WledRepository;
import 'package:nexgen_command/features/wled/wled_service.dart' show WledService;

/// WLED preset that sets MASTER OFF ("NGL Off", saved by schedule sync).
/// Explicit off — never a toggle. Same macro the schedule OFF boundaries fire.
const int kSunriseOffMacro = 2;

/// Every day. WLED dow bitmask is Mon=bit0..Sun=bit6, so 127 = all seven.
const int kSunriseOffDow = 127;

/// Minute field on a solar timer is an OFFSET, not a wall clock. 0 = at
/// sunrise exactly. (Encoding supports ±120; there is no offset UI yet.)
const int kSunriseOffOffsetMinutes = 0;

/// The reserved slot-8 entry for the global sunrise-off, or null when the user
/// hasn't opted in. Consumed by `ScheduleSyncService.syncAll`, which MERGES it
/// into the sunrise slot so a schedule/lease sync can't stub-clobber it —
/// exactly how [calendarLeaseActiveTimersProvider] protects lease timers
/// (P0-3.2). Overridable in tests.
final globalSunriseOffTimerProvider = Provider<Map<String, dynamic>?>((ref) {
  if (!ref.watch(sunriseOffEnabledProvider)) return null;
  return buildSunriseOffTimerEntry();
});

/// Whether the user has opted into the daily sunrise-off. Defaults FALSE for
/// every degraded state (loading, error, no profile) — this switches the
/// customer's lights off unattended, so it is never inferred.
final sunriseOffEnabledProvider = Provider<bool>((ref) {
  return ref.watch(currentUserProfileProvider).maybeWhen(
        data: (profile) => profile?.sunriseOffEnabled ?? false,
        orElse: () => false,
      );
});

/// The reserved sunrise-off timer entry. Delegates to the shared solar encoder
/// so this can never drift from the schedule path's encoding.
Map<String, dynamic> buildSunriseOffTimerEntry() =>
    ScheduleSyncService.buildSolarTimerEntry(
      offsetMinutes: kSunriseOffOffsetMinutes,
      macro: kSunriseOffMacro,
      dow: kSunriseOffDow,
    );

/// Outcome of arming/disarming the reserved slot.
enum SunriseOffWriteResult {
  /// Written and readback-verified on the controller.
  confirmed,

  /// The OFF preset (macro 2) could not be saved, so the timer was NOT written.
  /// Arming anyway would leave a timer pointing at a preset that doesn't exist:
  /// WLED fires the macro, nothing loads, the lights stay on — and the timer
  /// readback would still match, reporting a green that isn't real.
  presetSaveFailed,

  /// Controller unreachable — nothing was written.
  noController,

  /// Off-LAN. `/json/cfg` cannot be delivered through the bridge (it routes to
  /// /json/state, where WLED discards cfg keys and returns 200), so we refuse
  /// rather than report a save that never happened. Retry on LAN.
  deferredOffLan,

  /// The write was attempted but never verified (stall, mismatch, or failure).
  failed,
}

/// Arms / disarms the reserved sunrise slot directly on the controller.
///
/// Read-modify-write: the controller's current `timers.ins` is read, ONLY index
/// 8 is replaced, and the full array is pushed back. That preserves every
/// schedule timer (slots 0-7), every lease timer, and the sunset slot (9). The
/// write goes through the shared hardened [pushCfgWithVerify] — the same
/// verified path schedule sync and the lease writer use. Never fire-and-forget.
class SunriseOffService {
  const SunriseOffService();

  /// Arm the daily sunrise-off timer (toggle ON).
  Future<SunriseOffWriteResult> arm(Ref ref) =>
      _write(ref, buildSunriseOffTimerEntry(), ensureOffPreset: true);

  /// Disarm it (toggle OFF) by writing a disabled stub into the reserved slot,
  /// so the controller stops firing it. Same slot-reclaim mechanism the
  /// schedule path uses for vacated slots. No preset is needed to clear a slot,
  /// so the OFF-preset guarantee is skipped here.
  Future<SunriseOffWriteResult> disarm(Ref ref) =>
      _write(ref, ScheduleSyncService.disabledTimerStub(),
          ensureOffPreset: false);

  /// Test seam over the hardened cfg write+verify, mirroring the lease writer's
  /// `cfgPushFn`. Production delegates to the shared [pushCfgWithVerify].
  @visibleForTesting
  static Future<CfgPushOutcome> Function(
    WledRepository repo,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> ins,
  ) cfgPushFn = (repo, payload, ins) =>
      pushCfgWithVerify(repo: repo, payload: payload, ins: ins);

  Future<SunriseOffWriteResult> _write(
      Ref ref, Map<String, dynamic> slot8Entry,
      {required bool ensureOffPreset}) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      debugPrint('SunriseOff: no controller — not armed');
      return SunriseOffWriteResult.noController;
    }
    // Cfg writes are LAN-only. Say so plainly instead of claiming a save.
    //
    // Checked BEFORE the preset save (which DOES work off-LAN via /json/state)
    // so a controller we can't arm never gets an orphaned preset written to it.
    // Ordering lifted verbatim from the P0-3 lease writer
    // (calendar_entry_lease_manager.dart) — same hazard, same sequence.
    if (!repoCanWriteCfg(repo)) {
      debugPrint('SunriseOff: off-LAN — cannot write /json/cfg; deferred');
      return SunriseOffWriteResult.deferredOffLan;
    }

    // The timer fires `macro: 2`. If that preset isn't on the controller, WLED
    // loads nothing and the lights stay on — a silent no-op that still reads
    // back as a perfectly armed timer. Guarantee it exists BEFORE arming, and
    // abort rather than write a timer pointing at nothing.
    if (ensureOffPreset && !await _ensureOffPresetSaved(repo)) {
      debugPrint('SunriseOff: NGL Off preset (${ScheduleSyncService
          .kNglOffPresetId}) could not be saved — ABORTING the timer write');
      return SunriseOffWriteResult.presetSaveFailed;
    }

    final ins = await _readModifyWrite(repo, slot8Entry);
    final outcome = await cfgPushFn(
      repo,
      <String, dynamic>{
        'timers': {'ins': ins}
      },
      ins,
    );
    switch (outcome) {
      case CfgPushOutcome.confirmed:
        debugPrint('SunriseOff: slot ${ScheduleSyncService.kWledSunriseSlot} '
            'written + verified (macro ${slot8Entry['macro']}, '
            'en ${slot8Entry['en']})');
        return SunriseOffWriteResult.confirmed;
      // solarMismatch is reachable here and IS a failure for this writer: the
      // global sunrise-off IS the slot-8 solar row, so "clock timers fine, only
      // the solar row is wrong" means precisely the thing we just tried to write
      // did not land. The schedule path distinguishes the two because it also
      // owns clock timers; this path owns nothing else.
      case CfgPushOutcome.solarMismatch:
      case CfgPushOutcome.mismatch:
      case CfgPushOutcome.notConfirmed:
        debugPrint('SunriseOff: write NOT confirmed ($outcome)');
        return SunriseOffWriteResult.failed;
    }
  }

  /// Guarantee the controller holds a usable NGL Off preset (macro 2).
  ///
  /// The definition comes from [ScheduleSyncService.buildNglOffPresetState] —
  /// the SAME builder schedule sync seeds with — so the two paths can never
  /// save divergent "off" states under preset 2.
  ///
  /// Skips the psave when a satisfying preset is already stored. That matters:
  /// `savePreset` posts `{...state, psave: id}` to /json/state, so it APPLIES
  /// the state as well as storing it — a needless save would blink the strip
  /// off. When the preset is missing, unsatisfying, or unreadable we save
  /// anyway: an unnecessary save is recoverable, a missing OFF preset is the
  /// silent failure this whole guard exists to prevent.
  Future<bool> _ensureOffPresetSaved(WledRepository repo) async {
    if (repo is WledService) {
      try {
        final presets = await repo.fetchPresets();
        final def = presets[ScheduleSyncService.kNglOffPresetId];
        if (def != null && ScheduleSyncService.isNglOffPresetSatisfied(def)) {
          return true; // already correct — don't disturb the lights
        }
      } catch (e) {
        debugPrint('SunriseOff: preset readback failed — $e (saving anyway)');
      }
    }

    // Live state drives the per-segment off list — WLED stores off-segs only
    // for segments that exist at save time, so this must track the real layout.
    Map<String, dynamic>? live;
    try {
      live = await repo.getState();
    } catch (e) {
      debugPrint('SunriseOff: getState failed — $e (falling back to 1 seg)');
    }

    final ok = await repo.savePreset(
      presetId: ScheduleSyncService.kNglOffPresetId,
      state: ScheduleSyncService.buildNglOffPresetState(live),
      presetName: ScheduleSyncService.kNglOffPresetName,
    );
    debugPrint('SunriseOff: NGL Off preset save → $ok');
    return ok;
  }

  /// Classify a `timers.ins` response WITHOUT assuming array index == firmware
  /// slot index.
  ///
  /// WLED COMPACTS `ins` when serializing: it omits any timer that is entirely
  /// empty (`macro == 0 && hour == 0 && min == 0`). Verified on 192.168.1.150
  /// (0.15.1 / vid 2507300, 2026-07-29): a controller with 8 empty general
  /// slots and 2 solar slots returns just TWO entries — so `ins[0]` there is
  /// firmware slot 8, not slot 0. Indexing the response positionally copies the
  /// solar entries into general slots and loses the sunrise slot entirely.
  ///
  /// The reliable discriminator is the solar marker: a clock timer's `hour` is
  /// 0-23, and only the sunrise/sunset slots serialize `hour: 255`. So the
  /// FIRST 255-entry is sunrise (slot 8), the SECOND is sunset (slot 9), and
  /// everything else is a general timer in slot order. This holds whether the
  /// firmware returns a compacted array or a full positional 10 — in the full
  /// case the general entries already occupy 0-7 and the two 255s trail them.
  @visibleForTesting
  static ({
    List<Map<String, dynamic>> general,
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
  }) partitionTimerIns(List<Map<String, dynamic>>? ins) {
    final general = <Map<String, dynamic>>[];
    final solar = <Map<String, dynamic>>[];
    for (final t in ins ?? const <Map<String, dynamic>>[]) {
      final hour = (t['hour'] as num?)?.toInt();
      if (hour == ScheduleSyncService.kWledSolarHourMarker) {
        solar.add(t);
      } else if (general.length < ScheduleSyncService.kMaxWledTimers) {
        general.add(t);
      }
    }
    return (
      general: general,
      sunrise: solar.isNotEmpty ? solar[0] : null,
      sunset: solar.length > 1 ? solar[1] : null,
    );
  }

  /// Build the full 10-slot array to push: the controller's existing timers
  /// with ONLY the reserved sunrise slot replaced.
  ///
  /// Always emits exactly [ScheduleSyncService.kWledTotalTimerSlots] entries in
  /// firmware-slot order, so the write is positionally unambiguous no matter
  /// what shape the read came back in. When the table can't be read (relay,
  /// fetch error) the general slots become stubs rather than invented timers —
  /// the next schedule sync re-asserts 0-7 from Firestore, which owns them.
  Future<List<Map<String, dynamic>>> _readModifyWrite(
      WledRepository repo, Map<String, dynamic> slot8Entry) async {
    List<Map<String, dynamic>>? existing;
    if (repo is WledService) {
      try {
        existing = await repo.fetchTimerInstances();
      } catch (e) {
        debugPrint('SunriseOff: could not read existing timers — $e');
      }
    }
    if (existing == null) {
      debugPrint('SunriseOff: existing timer table unreadable — writing '
          'stubs for slots 0-7 (next schedule sync re-asserts them)');
    }

    final parts = partitionTimerIns(existing);
    final out = <Map<String, dynamic>>[];
    // Slots 0-7: preserved general timers, padded with stubs.
    for (var i = 0; i < ScheduleSyncService.kMaxWledTimers; i++) {
      out.add(i < parts.general.length
          ? Map<String, dynamic>.from(parts.general[i])
          : ScheduleSyncService.disabledTimerStub());
    }
    // Slot 8: ours. Slot 9: the controller's existing sunset, preserved.
    out.add(Map<String, dynamic>.from(slot8Entry));
    out.add(parts.sunset != null
        ? Map<String, dynamic>.from(parts.sunset!)
        : ScheduleSyncService.disabledTimerStub());
    return out;
  }
}

final sunriseOffServiceProvider =
    Provider<SunriseOffService>((ref) => const SunriseOffService());

/// Drives the user-facing toggle: persist the preference, then arm or disarm
/// the reserved slot on the controller.
///
/// Order matters. The profile write happens FIRST so the preference survives a
/// failed/off-LAN controller write and the timer is re-asserted by the next
/// schedule sync (which merges [globalSunriseOffTimerProvider]). Returning the
/// write result lets the UI tell the user the difference between "on and armed"
/// and "on, but we couldn't reach your controller yet".
class SunriseOffController {
  final Ref _ref;
  const SunriseOffController(this._ref);

  Future<SunriseOffWriteResult> setEnabled(bool enabled) async {
    final profile = _ref.read(currentUserProfileProvider).maybeWhen(
          data: (p) => p,
          orElse: () => null,
        );
    if (profile == null) return SunriseOffWriteResult.failed;

    if (profile.sunriseOffEnabled != enabled) {
      await _ref.read(userServiceProvider).updateUserProfile(
        profile.id,
        <String, dynamic>{
          'sunrise_off_enabled': enabled,
          // MUST be a Timestamp — UserModel.fromJson does a non-null
          // `as Timestamp` cast, so an ISO string here breaks profile parsing.
          'updated_at': Timestamp.fromDate(DateTime.now()),
        },
      );
    }

    final svc = _ref.read(sunriseOffServiceProvider);
    // Re-arming is safe: one reserved slot, absolute overwrite, never a
    // duplicate.
    return enabled ? svc.arm(_ref) : svc.disarm(_ref);
  }
}

final sunriseOffControllerProvider =
    Provider<SunriseOffController>((ref) => SunriseOffController(ref));
