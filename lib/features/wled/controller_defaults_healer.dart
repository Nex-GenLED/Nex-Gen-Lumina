// lib/features/wled/controller_defaults_healer.dart
//
// CONTROLLER DEFAULTS SELF-HEAL (2.5.2) — on-connect remediation of the silent
// schedule-killers the clock-health evaluator (BUG-CLOCK-1, 8d27bb3) already
// DETECTS: a failed/unreachable NTP host, a UTC timezone, 0,0 coordinates —
// plus the color-gamma standard folded in from the prior gamma self-heal.
//
// Policy is HEAL-ONLY-BROKEN: a healthy controller receives ZERO writes. Each
// heal is its own SURGICAL /json/cfg POST (never one combined blob — the P0 cfg
// lesson: a broad cfg POST risks clobbering unrelated deliberate config). One
// evaluation per connect; silent on success; a debug line per heal; inert on
// failure (the next connect retries). Firmware impact: none — keys-only merge.
//
// Reboot: WLED only re-attempts NTP on boot, so an NTP host/enable heal is
// followed by a reboot (applyJson {'rb':true}). tz/coords/gamma/audioreactive
// never reboot — the audioreactive disable takes effect on the controller's
// next loop() iteration (see audioreactive_health.dart for the firmware proof).
//
// ORDER: (a) ntp-host → (b) tz → (c) coords → (d) audioreactive → (e) ON-preset
// master power → (f) GAMMA → (g) reboot. Gamma is deliberately the LAST cfg
// write: on WLED 0.15.1 a cfg POST omitting `light.gc` wipes colour gamma
// (audit/GAMMA_BUG.md), so a gamma heal placed before any other cfg write gets
// undone by it. normalizeWledCfgPayload makes that structurally impossible now;
// the ordering is kept as the second line of defence. Do not move (f) earlier.
//
// LAN-ONLY. Every heal needs /json/cfg — to READ the current value (heal-only-
// broken) and to WRITE the correction. The bridge can do neither: its dispatch
// maps only getState → /json/state and getInfo → /json/info, and routes
// applyConfig to /json/state where WLED discards it and returns 200.
//
// This class used to run one relay heal (a blind-assert of the NTP host on
// CLOCK_UNSET, the one signal derivable from info-time). It never worked, and
// it was actively harmful: the cfg write silently evaporated but reported
// success, so the healer marked ntpHostHealed and went on to send {'rb':true} —
// which DOES route correctly to /json/state. The useful write was dropped and
// the disruptive one landed, rebooting customers' controllers for nothing. Of
// the two relay writes, only the harmful one worked.
//
// Relay connects are now a no-op. That loses nothing real (the heal never
// landed) and restores the class's own stated policy: heal only what you can
// verify. Restoring relay heals requires a bridge `applyConfig`/`getCfg`
// command — a firmware change, and the bridge has no OTA.

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/audioreactive_health.dart';
import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';

// ── Constants (tunable) ──────────────────────────────────────────────────────

/// The NTP host we heal broken controllers to. The stock WLED default
/// ([kKnownBadNtpHost]) is unreachable on some customer networks; time.google.com
/// is confirmed reachable across the fleet.
const String kHealNtpHost = 'time.google.com';

/// The stock WLED default NTP host. Presence of this host (on a LAN controller
/// whose cfg we can read) is treated as unhealed even if the clock happens to
/// be set — it's the root cause of the fleet's NTP failures.
const String kKnownBadNtpHost = '0.wled.pool.ntp.org';

/// WLED `/json/state` `ps` when no preset is active (a manual/live look).
const int kWledNoActivePreset = -1;

/// WLED `cfg.def.ps` when no boot preset is configured.
const int kWledNoBootPreset = 0;

/// Settle between consecutive `psave` flash writes during the ON-preset heal.
/// Mirrors the schedule-sync post-psave settle: back-to-back saves can return
/// 2xx without persisting (bench-observed 2026-07-30, vid 2507300).
const Duration kPresetHealSettle = Duration(milliseconds: 900);

int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : null);

// ── Pure planners (no I/O — unit-tested directly) ────────────────────────────

/// True when the controller's NTP host should be healed to [kHealNtpHost].
///
/// Fires when the clock is unset (NTP never synced — current host unreachable
/// on this network) OR the readable host is the known-bad default pool. A null
/// [currentHost] (field absent) falls back to the clock-unset signal alone.
bool ntpHostNeedsHeal({required bool clockUnset, String? currentHost}) {
  if (clockUnset) return true;
  return currentHost == kKnownBadNtpHost;
}

/// A timezone heal: either a WLED tz enum index (`if.ntp.tz`) or, for a zone we
/// can't map, a manual UTC offset in seconds (`if.ntp.offset`, with tz forced
/// to UTC). WLED's tz field is an INDEX into a fixed firmware table, not an
/// offset — see [kWledTzByIana].
@immutable
class TzHeal {
  final int? tzIndex;
  final int? offsetSeconds;
  const TzHeal.index(int this.tzIndex) : offsetSeconds = null;
  const TzHeal.offset(int this.offsetSeconds) : tzIndex = null;
  bool get isIndex => tzIndex != null;

  @override
  bool operator ==(Object other) =>
      other is TzHeal &&
      other.tzIndex == tzIndex &&
      other.offsetSeconds == offsetSeconds;
  @override
  int get hashCode => Object.hash(tzIndex, offsetSeconds);
  @override
  String toString() =>
      isIndex ? 'TzHeal.index($tzIndex)' : 'TzHeal.offset($offsetSeconds)';
}

/// Resolve the timezone heal when [tzSuspect] (device UTC, phone not).
///
/// Prefers the WLED tz enum index for the user's IANA zone ([kWledTzByIana] —
/// the same mapping the installer uses); falls back to a manual [phoneOffset]
/// when the zone is null or unmapped. Returns null when not suspect (heal-only-
/// broken). NOTE: Dart exposes no reliable IANA name from the phone directly,
/// so the user's stored profile timezone is the canonical zone source here; the
/// offset fallback covers any unmapped zone.
TzHeal? tzHealFor({
  required bool tzSuspect,
  String? ianaTimezone,
  required Duration phoneOffset,
}) {
  if (!tzSuspect) return null;
  final idx = ianaTimezone == null ? null : kWledTzByIana[ianaTimezone];
  if (idx != null && idx != kWledTzUtc) return TzHeal.index(idx);
  return TzHeal.offset(phoneOffset.inSeconds);
}

/// A coordinate heal, rounded to 2 decimals.
@immutable
class CoordHeal {
  final double lat;
  final double lon;
  const CoordHeal(this.lat, this.lon);

  @override
  bool operator ==(Object other) =>
      other is CoordHeal && other.lat == lat && other.lon == lon;
  @override
  int get hashCode => Object.hash(lat, lon);
  @override
  String toString() => 'CoordHeal($lat, $lon)';
}

double _round2(double v) => (v * 100).roundToDouble() / 100;
bool _usable(double? v) => v != null && v != 0;

/// Resolve the coordinate heal when [locationUnset] (device at 0,0).
///
/// Source order: stored home (profile geocode) → phone position (already-
/// granted permission only; the caller resolves it lazily) → skip. Rounds to 2
/// decimals — solar math needs no more, and we don't put precise user location
/// on the device. Returns null to SKIP (clock-health's solar warning still
/// covers an un-healed 0,0).
CoordHeal? coordHealFor({
  required bool locationUnset,
  double? profileLat,
  double? profileLon,
  double? phoneLat,
  double? phoneLon,
}) {
  if (!locationUnset) return null;
  if (_usable(profileLat) && _usable(profileLon)) {
    return CoordHeal(_round2(profileLat!), _round2(profileLon!));
  }
  if (phoneLat != null && phoneLon != null) {
    return CoordHeal(_round2(phoneLat), _round2(phoneLon));
  }
  return null;
}

/// Whether to reboot NOW after an NTP-host heal, vs DEFER to the next natural
/// boot. A reboot re-runs WLED's boot sequence, so we only reboot when that
/// reproduces what the customer is already looking at. Otherwise DEFER — the
/// host/en write persists in cfg and takes effect on the next power cycle or
/// user reboot, whenever that is (keeps the healer stateless — no delayed-reboot
/// scheduling).
///
/// ── Why the lights-OFF rule flipped (was: "off → always safe") ──────────────
/// The original gate returned true for any off strip, on the reasoning that
/// "off → no visible disruption". That is the OPPOSITE of what WLED does. From
/// wled00/wled.cpp's boot sequence:
///
///     bri = 0;                                   // start black
///     if (turnOnAtBoot) bri = briS;              // ← comes up LIT at def.bri
///     if (bootPreset > 0) applyPreset(bootPreset, CALL_MODE_INIT);
///
/// and its own comment: "if turnOnAtBoot is false: strip is set to black … if a
/// bootup preset is set, it will fade to that preset if it has on:true set".
/// So an OFF strip comes back ON when `cfg.def.on` is true, AND a boot preset
/// can light it even when def.on is false. WLED ships turnOnAtBoot defaulting
/// to TRUE, so the old rule turned customers' lights on — and because the NTP
/// heal only fires on a clock-unset controller, no schedule would ever turn
/// them back off.
///
/// Rebooting must never turn a customer's lights on. An off strip is therefore
/// only safe when BOTH boot paths are known-quiet: [turnOnAtBoot] is explicitly
/// false AND no boot preset is configured. Anything unknown/null (relay, cfg
/// unreadable) defers — the same never-blind-reboot discipline as the rest of
/// the gate. Dealer-configured controllers (SOP §2.3: turn-on-after-power-up
/// OFF, boot preset 0) still qualify; controllers left at WLED's defaults don't.
bool shouldRebootAfterHostHeal({
  required bool deviceOn,
  int? activePresetId,
  int? bootPresetId,
  bool? turnOnAtBoot,
}) {
  if (!deviceOn) {
    // Off: safe ONLY if the boot sequence leaves it off — see above.
    return turnOnAtBoot == false && bootPresetId == kWledNoBootPreset;
  }
  // On: reboot only if the live look is exactly the configured boot preset, so
  // the boot sequence reproduces it.
  if (bootPresetId != null &&
      bootPresetId != kWledNoBootPreset &&
      activePresetId == bootPresetId) {
    return true;
  }
  return false; // on + non-boot / manual / unknown → defer to next natural boot
}

// ── Surgical cfg payloads (one field family each) ────────────────────────────

Map<String, dynamic> ntpHostHealPayload() => {
      'if': {
        'ntp': {'host': kHealNtpHost, 'en': true},
      },
    };

Map<String, dynamic> tzHealPayload(TzHeal heal) => heal.isIndex
    ? {
        'if': {
          'ntp': {'tz': heal.tzIndex},
        },
      }
    : {
        'if': {
          'ntp': {'tz': kWledTzUtc, 'offset': heal.offsetSeconds},
        },
      };

Map<String, dynamic> coordHealPayload(CoordHeal heal) => {
      'if': {
        'ntp': {'lt': heal.lat, 'ln': heal.lon},
      },
    };

// ── Orchestration ────────────────────────────────────────────────────────────

/// Injected inputs the healer needs that come from providers / platform, kept
/// out of the pure class so it stays unit-testable.
class ControllerHealContext {
  final double? profileLat;
  final double? profileLon;
  final String? ianaTimezone;

  /// Resolves the phone's position ONLY if location permission is already
  /// granted; returns null otherwise (never prompts).
  final Future<({double lat, double lon})?> Function() resolvePhonePosition;

  /// Phone wall-clock supplier (injected for deterministic tests).
  final DateTime Function() now;

  /// Phone UTC offset used for clock-health evaluation and the tz offset
  /// fallback. Injected (not derived from [now]) so tests are deterministic
  /// regardless of the machine timezone; the provider wires `now().timeZoneOffset`.
  final Duration phoneUtcOffset;

  const ControllerHealContext({
    required this.profileLat,
    required this.profileLon,
    required this.ianaTimezone,
    required this.resolvePhonePosition,
    required this.now,
    required this.phoneUtcOffset,
  });
}

/// What the healer did — surfaced for logging and asserted by tests.
class ControllerHealReport {
  bool reachable = true;
  bool ntpHostHealed = false;
  bool tzHealed = false;
  bool coordsHealed = false;
  bool gammaHealed = false;

  /// The AudioReactive usermod was found ON and disabled. Never triggers a
  /// reboot — the controller suspends the FFT task on its next loop().
  bool audioReactiveHealed = false;

  /// System ON preset slots (1/3/4/5) repaired to assert ROOT master power.
  /// Empty on a healthy controller — the heal is readback-gated.
  final List<int> onPresetsHealed = [];
  bool rebooted = false;

  /// The ntp-host heal was written but the reboot was DEFERRED to the next
  /// natural boot (lights were on a non-boot look). The cfg write persists.
  bool rebootDeferred = false;
  final List<String> log = [];

  bool get anyHealed =>
      ntpHostHealed ||
      tzHealed ||
      coordsHealed ||
      gammaHealed ||
      audioReactiveHealed ||
      onPresetsHealed.isNotEmpty;

  @override
  String toString() {
    final parts = <String>[
      if (ntpHostHealed) 'ntp-host',
      if (tzHealed) 'tz',
      if (coordsHealed) 'coords',
      if (gammaHealed) 'gamma',
      if (audioReactiveHealed) 'audioreactive',
      if (onPresetsHealed.isNotEmpty) 'on-presets${onPresetsHealed.join('/')}',
      if (rebooted) 'reboot',
      if (rebootDeferred) 'reboot-deferred',
    ];
    return parts.isEmpty ? 'no-op' : parts.join('+');
  }
}

/// Evaluates + heals one controller's defaults on connect. Constructed fresh
/// per connect by [controllerDefaultsHealerProvider]; unit-testable with a fake
/// repo + context.
class ControllerDefaultsHealer {
  final WledRepository repo;

  /// True when [repo] is a direct-LAN [WledService]. False (relay) makes [run]
  /// a no-op — cfg is neither readable nor writable over the bridge.
  final bool isLan;

  /// LAN baseUrl host / relay controllerIp — the target for the gamma raw-HTTP
  /// push (LAN only). Null skips gamma.
  final String? controllerIp;

  final ControllerHealContext ctx;
  final GammaSelfHealAction gammaAction;

  const ControllerDefaultsHealer({
    required this.repo,
    required this.isLan,
    required this.controllerIp,
    required this.ctx,
    required this.gammaAction,
  });

  Future<ControllerHealReport> run() async {
    final report = ControllerHealReport();

    // Relay: nothing here is deliverable — see the file header. Bail before any
    // read or write so a relay connect costs nothing and can never reboot.
    if (!isLan) {
      report.log.add('relay connect — cfg unreachable over the bridge; '
          'no heals evaluated');
      return report;
    }

    final source = repo;
    if (source is! ClockInfoSource) {
      report.reachable = false;
      return report;
    }

    ControllerClockInfo? info;
    try {
      info = await (source as ClockInfoSource).fetchClockInfo();
    } catch (e) {
      report.reachable = false;
      report.log.add('fetchClockInfo failed: $e');
      return report;
    }
    if (info == null) {
      report.reachable = false;
      return report;
    }

    final now = ctx.now();
    final health = evaluateClockHealth(
      device: info,
      phoneNow: now,
      phoneUtcOffset: ctx.phoneUtcOffset,
    );

    // (a) NTP host — heal when the clock never synced or the readable host is
    // the known-bad default pool.
    bool ntpRetryFieldChanged = false;
    if (ntpHostNeedsHeal(
        clockUnset: health.clockUnset, currentHost: info.ntpHost)) {
      if (await _post(ntpHostHealPayload(), 'ntp-host', report)) {
        report.ntpHostHealed = true;
        ntpRetryFieldChanged = true;
      }
    }

    // (b) timezone
    final tz = tzHealFor(
      tzSuspect: health.tzSuspect,
      ianaTimezone: ctx.ianaTimezone,
      phoneOffset: ctx.phoneUtcOffset,
    );
    if (tz != null) {
      if (await _post(tzHealPayload(tz), 'tz', report)) report.tzHealed = true;
    }

    // (c) coordinates — profile home → phone (granted only) → skip
    if (health.locationUnset) {
      double? phoneLat, phoneLon;
      if (!(_usable(ctx.profileLat) && _usable(ctx.profileLon))) {
        final phone = await ctx.resolvePhonePosition();
        phoneLat = phone?.lat;
        phoneLon = phone?.lon;
      }
      final coord = coordHealFor(
        locationUnset: true,
        profileLat: ctx.profileLat,
        profileLon: ctx.profileLon,
        phoneLat: phoneLat,
        phoneLon: phoneLon,
      );
      if (coord != null) {
        if (await _post(coordHealPayload(coord), 'coords', report)) {
          report.coordsHealed = true;
        }
      } else {
        report.log.add('coords 0,0 but no source (profile/phone) — skipped');
      }
    }

    // (d) AudioReactive usermod — the flash image ships it ENABLED with a mic
    // on GPIOs our hardware doesn't have; its I2S+FFT task starves the LED
    // show task and freezes effects. Own surgical POST, no reboot: the
    // controller suspends sound processing on its next loop() and the payload
    // omits the only reboot-requiring fields (mic type/pins).
    final arSource = repo;
    if (arSource is AudioReactiveConfigSource) {
      await _healAudioReactive(arSource as AudioReactiveConfigSource, report);
    }

    // (e) ON-preset master power — repair presets 1/3/4/5 that store segments
    // only (no root `on`), so a fired ON-timer powers the strip instead of
    // loading a design into a dark master. See _healOnPresetMasterPower.
    final presetSource = repo;
    if (presetSource is WledService) {
      await _healOnPresetMasterPower(presetSource, report);
    }

    // (f) gamma — DELIBERATELY LAST of the cfg writes, and before the reboot.
    //
    // ORDERING IS LOAD-BEARING. This used to run at step (d), BEFORE the
    // AudioReactive heal. On WLED 0.15.1 any cfg POST omitting `light.gc` wipes
    // colour gamma (audit/GAMMA_BUG.md), so the AR write at (d) destroyed the
    // gamma this step had just asserted — the healer undid its own work every
    // run where AR needed healing, then reported success.
    //
    // normalizeWledCfgPayload now makes that mechanically impossible, so this
    // move is belt-and-braces rather than the fix. It stays because "assert the
    // invariant after every write that could disturb it" is the correct shape
    // regardless, and it keeps the next cfg writer added above from reopening
    // the hole if the chokepoint is ever bypassed.
    //
    // Before the reboot, not after: (f) may POST {'rb':true}, and a cfg write
    // racing a reboot is not guaranteed to reach flash.
    final ip = controllerIp;
    if (ip != null && ip.isNotEmpty) {
      try {
        final g = await gammaAction(ip);
        // gammaHealed means VERIFIED healed, not "the POST returned 2xx".
        //
        // WledConfigPushResult.warning carries success:true, so the previous
        // `g.success && !g.noChange` test marked the heal successful on a
        // readback MISMATCH — asserting an outcome it had just failed to
        // confirm. That is the defect class this codebase keeps hitting, and it
        // is worth fixing independently of the gamma bug itself.
        //
        // Three outcomes, three different meanings — noChange FIRST because
        // skipped() also carries a warning ("already correct"), and a healthy
        // device must stay silent (heal-only-broken: zero writes, zero log).
        if (g.noChange) {
          // Device already correct — the healthy path. Nothing written, nothing
          // to say.
        } else if (g.success && g.warnings.isEmpty) {
          report.gammaHealed = true;
        } else if (g.success) {
          // Wrote, but the readback did not confirm it. Not a heal.
          report.log.add('gamma heal unverified: ${g.warnings.join('; ')}');
        } else {
          // Hard failure. Previously swallowed entirely — success:false simply
          // fell through and the run reported nothing at all.
          report.log.add('gamma heal failed: ${g.errorMessage ?? 'unknown'}');
        }
      } catch (e) {
        report.log.add('gamma heal failed: $e');
      }
    }

    // (g) reboot ONLY when an NTP-retry field (host/en) changed — never for
    // tz/coords/gamma/audioreactive. WLED re-attempts NTP only on boot. Gate on
    // device state so we don't reboot an actively-running non-boot look: defer
    // instead (the cfg write persists and applies on the next natural boot).
    if (ntpRetryFieldChanged) {
      final decision = await _decideReboot(info);
      if (decision.reboot) {
        try {
          report.rebooted = await repo.applyJson({'rb': true});
        } catch (e) {
          report.log.add('reboot failed: $e');
        }
      } else {
        report.rebootDeferred = true;
        report.log.add(
            'reboot deferred (${decision.reason}) — host/en persists in cfg, '
            'applies on next natural boot');
      }
    }

    // Best-effort readback-verify (skipped after a reboot since the device is
    // cycling). Advisory only — never flips success.
    if (report.anyHealed && !report.rebooted) {
      await _verify(source as ClockInfoSource, report);
    }

    return report;
  }

  /// Repairs system ON presets (1/3/4/5) that do not assert ROOT master power.
  ///
  /// WHY THIS BELONGS HERE AND NOT ONLY IN SCHEDULE SYNC: the sync-side
  /// predicate fix ([ScheduleSyncService.isNglOnPresetSatisfied]) only heals on
  /// the next schedule sync. A customer who never edits a schedule would stay
  /// broken indefinitely — their ON-timers keep firing DARK. Healing on CONNECT
  /// repairs the installed fleet without requiring any user action.
  ///
  /// HEAL-ONLY-BROKEN, readback-gated — matching this class's stated policy and
  /// the gamma heal's precedent: a healthy controller costs ONE GET
  /// (/presets.json) and ZERO writes.
  ///
  /// NO PERSISTED "already healed" MARKER — deliberate. A marker would make
  /// this run once per controller and then stop, but a preset can be clobbered
  /// later by any psave path, and this codebase already has a documented
  /// device-side revert phenomenon (gamma). A marker would suppress exactly the
  /// re-heal such a revert needs, and would desync from device truth. The
  /// readback IS the gate: it is cheaper than a marker, cannot go stale, and
  /// re-heals automatically if a preset regresses. (The gamma heal in this same
  /// class made the same choice for the same reason.)
  ///
  /// ABSENT presets are NOT created here: schedule sync owns creating them, and
  /// inventing a preset from a healer would mask an un-synced controller.
  ///
  /// `ib` is never asserted — it is a psave REQUEST flag, never stored back.
  Future<void> _healOnPresetMasterPower(
    WledService svc,
    ControllerHealReport report,
  ) async {
    // Two passes: heal, re-read, heal anything that did not land. A `psave` is
    // a FLASH write; back-to-back saves on this firmware can return 2xx and
    // still not persist — bench-observed 2026-07-30 (vid 2507300): preset 4
    // reported ok=true and read back with no root `on`. Trusting the 2xx alone
    // would report a heal that never happened.
    for (var pass = 0; pass < 2; pass++) {
      Map<int, Map<String, dynamic>> presets;
      try {
        // Tri-state: an UNREADABLE read is not an un-synced controller. The old
        // `presets.isEmpty` return could not tell them apart, so a corrupt
        // presets.json made the healer silently inert (P1-52).
        final read = await svc.readPresets();
        if (!read.isKnown) {
          report.log.add('on-preset heal SKIPPED — presets.json unreadable '
              '(${read.reason}); cannot tell a broken preset from a missing one');
          return;
        }
        presets = read.presets;
      } catch (e) {
        report.log.add('on-preset master-power: readPresets failed: $e');
        return;
      }
      if (presets.isEmpty) return; // genuinely un-synced — sync creates them

      // Live segment layout for the heal payload. Without it onPresetHealState
      // omits `seg` and the psave captures AMBIENT segment state — the exact
      // defect this heal is supposed to repair (audit/BASE_LADDER.md). A null
      // here degrades to a single-segment fallback, never to ambient capture.
      Map<String, dynamic>? liveState;
      try {
        liveState = await svc.getState();
      } catch (e) {
        report.log.add('on-preset heal: getState failed ($e); seg fallback');
        liveState = null;
      }

      final broken = <int>[];
      for (final entry in ScheduleSyncService.kOnPresetSpecs.entries) {
        final def = presets[entry.key];
        if (def == null) continue; // sync creates it; not ours to invent
        if (!ScheduleSyncService.isNglOnPresetSatisfied(def, entry.value.name)) {
          broken.add(entry.key);
        }
      }
      if (broken.isEmpty) {
        // Pass 0 → already healthy (zero writes). Pass 1 → the heal verified.
        return;
      }
      if (pass == 1) {
        report.log.add('on-preset heal: retrying $broken (first pass did not '
            'persist)');
      }

      for (final id in broken) {
        final spec = ScheduleSyncService.kOnPresetSpecs[id]!;
        try {
          await svc.savePreset(
            presetId: id,
            state: ScheduleSyncService.onPresetHealState(spec.bri, liveState),
            presetName: spec.name,
          );
          if (!report.onPresetsHealed.contains(id)) {
            report.onPresetsHealed.add(id);
          }
        } catch (e) {
          report.log.add('on-preset $id heal threw: $e');
        }
        // Settle between flash writes so the next psave is not issued while
        // the controller is still committing the previous one.
        await Future<void>.delayed(kPresetHealSettle);
      }
    }

    // Final readback — report only what ACTUALLY landed, so a heal that
    // silently failed is not reported as success.
    try {
      final after = await svc.fetchPresets();
      report.onPresetsHealed.removeWhere((id) {
        final def = after[id];
        final spec = ScheduleSyncService.kOnPresetSpecs[id];
        if (def == null || spec == null) return true;
        final landed =
            ScheduleSyncService.isNglOnPresetSatisfied(def, spec.name);
        if (!landed) {
          report.log.add('on-preset $id heal did NOT persist after 2 passes '
              '— next connect retries');
        }
        return !landed;
      });
    } catch (_) {
      // Verification unavailable — leave the optimistic list; next connect
      // re-evaluates from device truth anyway.
    }
  }

  /// Disables the AudioReactive usermod when it is found ON, then readback-
  /// verifies. Heal-only-broken: an already-false flag, a firmware build with
  /// no AudioReactive block, and an unreadable cfg all produce ZERO writes —
  /// only an explicit `true` warrants the POST, so a non-AR build never gets a
  /// `um` key written from nothing. Never reboots. Inert on failure (the next
  /// connect retries); the readback is advisory and never flips success.
  Future<void> _healAudioReactive(
    AudioReactiveConfigSource source,
    ControllerHealReport report,
  ) async {
    bool? enabled;
    try {
      enabled = await source.readAudioReactiveEnabled();
    } catch (e) {
      report.log.add('audioreactive read failed: $e');
      return;
    }
    if (!audioReactiveNeedsHeal(enabled)) return;

    if (!await _post(audioReactiveHealPayload(), 'audioreactive', report)) {
      return;
    }
    report.audioReactiveHealed = true;

    try {
      if (await source.readAudioReactiveEnabled() == true) {
        report.log.add('readback: audioreactive still enabled');
      }
    } catch (e) {
      report.log.add('audioreactive readback error: $e');
    }
  }

  /// Reads the live device state (on + active preset) and pairs it with the
  /// boot defaults already carried on [info] (cfg.def.ps / cfg.def.on, from the
  /// healer's one cfg read) to decide whether the post-NTP-heal reboot is safe
  /// now or should defer. Unreadable state → defer (never blind-reboot).
  Future<({bool reboot, String reason})> _decideReboot(
    ControllerClockInfo info,
  ) async {
    Map<String, dynamic>? state;
    try {
      state = await repo.getState();
    } catch (_) {
      // fall through to null handling
    }
    if (state == null) {
      return (reboot: false, reason: 'device state unreadable');
    }
    final on = state['on'] == true;
    final activePs = _asInt(state['ps']);
    final go = shouldRebootAfterHostHeal(
      deviceOn: on,
      activePresetId: activePs,
      bootPresetId: info.bootPresetId,
      turnOnAtBoot: info.turnOnAtBoot,
    );
    return (
      reboot: go,
      reason: 'on=$on activePs=$activePs bootPs=${info.bootPresetId} '
          'onAtBoot=${info.turnOnAtBoot}',
    );
  }

  Future<bool> _post(
    Map<String, dynamic> payload,
    String label,
    ControllerHealReport report,
  ) async {
    try {
      final ok = await repo.applyConfig(payload);
      if (!ok) {
        report.log.add('$label POST returned false');
        return false;
      }
      return true;
    } catch (e) {
      report.log.add('$label POST error: $e');
      return false;
    }
  }

  Future<void> _verify(
    ClockInfoSource source,
    ControllerHealReport report,
  ) async {
    try {
      final after = await source.fetchClockInfo();
      if (after == null) return;
      if (report.ntpHostHealed &&
          after.ntpHost != null &&
          after.ntpHost != kHealNtpHost) {
        report.log.add('readback: ntp host still ${after.ntpHost}');
      }
      if (report.coordsHealed &&
          after.latitude == 0 &&
          after.longitude == 0) {
        report.log.add('readback: coords still 0,0');
      }
    } catch (e) {
      report.log.add('readback error: $e');
    }
  }
}

// ── Connect-lifecycle predicate ──────────────────────────────────────────────

String? _endpointKey(WledRepository? repo) {
  if (repo is WledService) return 'lan:${repo.baseUrl}';
  if (repo is CloudRelayRepository) {
    return 'relay:${repo.controllerId}:${repo.controllerIp}';
  }
  return null;
}

/// True when a [wledRepositoryProvider] transition is a NEW controller connect
/// that warrants a heal — [next] reaches a clock-readable endpoint (LAN
/// WledService or relay CloudRelayRepository) different from [prev]'s. Guards
/// the [WledNotifier] listener so the frequent provider rebuilds that reuse the
/// same endpoint (connectivity/profile churn emits a fresh instance) don't
/// re-fire the evaluation. Pure — unit-testable.
bool shouldHealOnConnect(WledRepository? previous, WledRepository? next) {
  final nextKey = _endpointKey(next);
  if (nextKey == null) return false;
  return _endpointKey(previous) != nextKey;
}

// ── Providers ────────────────────────────────────────────────────────────────

/// The device write a gamma heal performs. Injected so tests observe/stub it
/// without HTTP. Default delegates to [pushGammaConfig] (readback → skip when
/// already correct, else POST + verify).
typedef GammaSelfHealAction = Future<WledConfigPushResult> Function(String ip);

/// Test seam for the gamma half of the healer.
final gammaSelfHealActionProvider = Provider<GammaSelfHealAction>(
  (ref) => (ip) => pushGammaConfig(ip),
);

// ── Gamma watchdog ─────────────────────────────────────────────────────────

/// Low-frequency cadence for [GammaWatchdog]. The connect-time heal fires ONCE
/// per connect; a mid-session device-side gamma revert (cfg.light.gc dropping
/// to default — suspected firmware/flash behavior on 0.15.1, see
/// project_gamma_revert_open_seg_gc_phantom) would otherwise go uncorrected
/// until the next reconnect. Two minutes catches a revert quickly while keeping
/// the readback traffic negligible.
const Duration kGammaWatchdogInterval = Duration(minutes: 2);

/// Hard floor on the watchdog cadence. Below this, the periodic readbacks (and,
/// on a persistently-reverting board, the corrective writes) would themselves
/// become the flash churn we're guarding against. Any shorter interval is
/// clamped up to this.
const Duration kGammaWatchdogMinInterval = Duration(seconds: 60);

/// Periodic, READBACK-GATED re-assert of the color-gamma standard.
///
/// Closes the gap the once-per-connect heal leaves: a gamma revert that happens
/// mid-session isn't corrected until reconnect. It does so WITHOUT adding flash
/// wear — every tick is a [GammaSelfHealAction] (default [pushGammaConfig]),
/// which READS `/json/cfg` and SKIPS when gamma is already correct. So:
///   • healthy board  → every tick is a GET, ZERO cfg writes;
///   • a real revert  → exactly ONE corrective cfg write, then back to skips.
///
/// LAN-only (relay/mock ticks no-op — the bridge can't read/write cfg) and
/// reentrancy-guarded so a slow network can't stack ticks.
class GammaWatchdog {
  GammaWatchdog({
    required GammaSelfHealAction action,
    required String? Function() lanIp,
    Duration interval = kGammaWatchdogInterval,
  })  : _action = action,
        _lanIp = lanIp,
        _interval = interval < kGammaWatchdogMinInterval
            ? kGammaWatchdogMinInterval
            : interval;

  final GammaSelfHealAction _action;
  final String? Function() _lanIp;
  final Duration _interval;

  Timer? _timer;
  bool _inFlight = false;

  /// Effective (floored) cadence — exposed so the ≥60s guard is assertable.
  Duration get interval => _interval;

  /// Corrective cfg WRITES driven so far. Readback skips are NOT counted, so a
  /// healthy board leaves this at 0 no matter how many ticks elapse.
  int correctiveWrites = 0;

  /// Readback-gated passes performed (writes + skips). Diagnostic only.
  int ticks = 0;

  void start() {
    stop();
    _timer = Timer.periodic(_interval, (_) => unawaited(tickOnce()));
  }

  /// One readback-gated pass. No-ops when not on a LAN endpoint. Called by the
  /// periodic timer and directly by tests.
  Future<void> tickOnce() async {
    if (_inFlight) return;
    final ip = _lanIp();
    if (ip == null || ip.isEmpty) return; // relay / mock / offline → no work
    _inFlight = true;
    try {
      ticks++;
      // pushGammaConfig reads cfg first and returns noChange when already
      // correct — the readback gate is what keeps the healthy case write-free.
      final result = await _action(ip);
      if (result.success && !result.noChange) correctiveWrites++;
    } catch (_) {
      // Best-effort — the next tick retries.
    } finally {
      _inFlight = false;
    }
  }

  void stop() {
    _timer?.cancel();
    _timer = null;
  }
}

/// A [GammaWatchdog] bound to the currently-connected LAN controller. The
/// [WledNotifier] owns its lifecycle (start on build, stop on dispose); the
/// per-tick LAN-ip lookup re-resolves the live repo so a single instance rides
/// endpoint changes (relay/mock ticks simply no-op).
final gammaWatchdogProvider = Provider<GammaWatchdog>((ref) {
  final action = ref.read(gammaSelfHealActionProvider);
  return GammaWatchdog(
    action: action,
    lanIp: () {
      final repo = ref.read(wledRepositoryProvider);
      if (repo is WledService) return Uri.tryParse(repo.baseUrl)?.host;
      return null; // only a LAN WledService can read/write cfg gamma
    },
  );
});

/// Phone wall-clock supplier (overridable in tests for deterministic clock
/// health).
final healerPhoneNowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

/// Resolves the phone position ONLY if location permission is already granted —
/// never prompts (constraint). Overridable in tests.
final healerPhonePositionProvider =
    Provider<Future<({double lat, double lon})?> Function()>(
  (ref) => _resolvePhonePositionIfPermitted,
);

Future<({double lat, double lon})?> _resolvePhonePositionIfPermitted() async {
  try {
    final perm = await Geolocator.checkPermission();
    if (perm != LocationPermission.always &&
        perm != LocationPermission.whileInUse) {
      return null; // never prompt for a background heal
    }
    final pos = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.low,
        timeLimit: Duration(seconds: 5),
      ),
    );
    return (lat: pos.latitude, lon: pos.longitude);
  } catch (e) {
    debugPrint('[Healer] phone position unavailable: $e');
    return null;
  }
}

/// Returns a callable that runs the on-connect controller-defaults heal for the
/// currently-connected controller. Fired imperatively by the [WledNotifier]
/// connect listener (see [shouldHealOnConnect]) so no widget has to watch it.
final controllerDefaultsHealerProvider =
    Provider<Future<ControllerHealReport> Function()>((ref) {
  return () async {
    final repo = ref.read(wledRepositoryProvider);
    // Demo/mock repos aren't a ClockInfoSource; run() short-circuits on that.
    if (repo == null) {
      return ControllerHealReport()..reachable = false;
    }

    final isLan = repo is WledService;
    String? ip;
    if (repo is WledService) {
      ip = Uri.tryParse(repo.baseUrl)?.host;
    } else if (repo is CloudRelayRepository) {
      ip = repo.controllerIp;
    }

    final profile = ref.read(currentUserProfileProvider).valueOrNull;
    final nowFn = ref.read(healerPhoneNowProvider);
    final ctx = ControllerHealContext(
      profileLat: profile?.latitude,
      profileLon: profile?.longitude,
      ianaTimezone: profile?.timeZone,
      resolvePhonePosition: ref.read(healerPhonePositionProvider),
      now: nowFn,
      phoneUtcOffset: nowFn().timeZoneOffset,
    );

    final healer = ControllerDefaultsHealer(
      repo: repo,
      isLan: isLan,
      controllerIp: ip,
      ctx: ctx,
      gammaAction: ref.read(gammaSelfHealActionProvider),
    );

    final report = await healer.run();
    if (report.anyHealed || report.rebooted) {
      debugPrint('[Healer] $report on ${ip ?? "(unknown)"}'
          '${report.log.isEmpty ? '' : ' — ${report.log.join('; ')}'}');
    }
    return report;
  };
});
