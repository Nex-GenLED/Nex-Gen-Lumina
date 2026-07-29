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
      _write(ref, buildSunriseOffTimerEntry());

  /// Disarm it (toggle OFF) by writing a disabled stub into the reserved slot,
  /// so the controller stops firing it. Same slot-reclaim mechanism the
  /// schedule path uses for vacated slots.
  Future<SunriseOffWriteResult> disarm(Ref ref) =>
      _write(ref, ScheduleSyncService.disabledTimerStub());

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
      Ref ref, Map<String, dynamic> slot8Entry) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      debugPrint('SunriseOff: no controller — not armed');
      return SunriseOffWriteResult.noController;
    }
    // Cfg writes are LAN-only. Say so plainly instead of claiming a save.
    if (!repoCanWriteCfg(repo)) {
      debugPrint('SunriseOff: off-LAN — cannot write /json/cfg; deferred');
      return SunriseOffWriteResult.deferredOffLan;
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
      case CfgPushOutcome.mismatch:
      case CfgPushOutcome.notConfirmed:
        debugPrint('SunriseOff: write NOT confirmed ($outcome)');
        return SunriseOffWriteResult.failed;
    }
  }

  /// Build the full 10-slot array: the controller's existing timers with ONLY
  /// the reserved sunrise slot replaced. When the current table can't be read
  /// (relay, fetch error) we fall back to stubs for the general slots rather
  /// than inventing timers — the next schedule sync re-asserts slots 0-7 from
  /// Firestore, which is the authoritative source for those.
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

    final out = <Map<String, dynamic>>[];
    for (var i = 0; i < ScheduleSyncService.kWledTotalTimerSlots; i++) {
      if (i == ScheduleSyncService.kWledSunriseSlot) {
        out.add(Map<String, dynamic>.from(slot8Entry));
      } else if (existing != null && i < existing.length) {
        out.add(Map<String, dynamic>.from(existing[i]));
      } else {
        out.add(ScheduleSyncService.disabledTimerStub());
      }
    }
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
