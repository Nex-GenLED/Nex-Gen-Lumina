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
// P0-3.2: lease-timer provider so syncAll can MERGE active lease timers
// (macro 26-41) and not stub-clobber them. Flag-gated → [] when leases inactive.
import 'package:nexgen_command/features/schedule/calendar_entry_lease_manager.dart'
    show calendarLeaseActiveTimersProvider;
// Global sunrise-off: a reserved slot-8 timer owned by a user profile toggle.
// syncAll MERGES it for the same reason it merges lease timers — otherwise the
// solar assembly stub-clobbers it on the next foreground sync.
import 'package:nexgen_command/features/schedule/sunrise_off_service.dart'
    show globalSunriseOffTimerProvider;
// Pure-Dart extractions (bench/ CLI imports these without dart:ui). Imported for
// internal use AND re-exported so existing importers of schedule_sync.dart still
// resolve timersInsLanded / isRealEnabledTimer.
import 'package:nexgen_command/features/schedule/timer_landing.dart';
export 'package:nexgen_command/features/schedule/timer_landing.dart'
    show isRealEnabledTimer, timersInsLanded;
import 'package:nexgen_command/features/schedule/cfg_payload_builder.dart' as cfg;

// isRealEnabledTimer + timersInsLanded moved to timer_landing.dart (pure Dart)
// and are re-exported above.

/// Patient verification of a cfg write that hit the controller's post-commit
/// network stall (see [ScheduleSyncService._pushCfgWithVerify]). The write is
/// assumed to have COMMITTED; we wait for the controller to answer again and
/// confirm by readback — we do NOT re-POST into the blackout.
///
/// Flow: poll [liveness] every [pollInterval] for up to [maxWait]. On the first
/// live response, [readbackMatch]:
///   - true  → verified (success).
///   - false → recovered but the timers appear ABSENT. RULE OUT the post-commit
///     readback RACE first: wait [repostSettle] and re-LOOK (no POST). Re-look
///     match → confirmed (the first readback raced the commit); re-look null →
///     keep polling; re-look STILL false → the genuine-drop remedy: ONE [rePost],
///     wait [repostSettle], [readbackMatch] once more → its result.
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

    // Recovered but the timers appear ABSENT. Before spending a WRITE, rule out
    // the post-commit readback RACE (bench 2026-07-23): the controller answered
    // liveness + this readback before its flash/config state settled, so a write
    // that already landed can read back as a transient mismatch. Re-POSTing here
    // is the wrong remedy — it re-triggers the stall and can turn a correct write
    // red. Wait and LOOK once more (no POST) first.
    await delay(repostSettle);
    final reLook = await readbackMatch();
    if (reLook == true) return true; // first readback raced the commit
    if (reLook == null) continue; // controller dipped again — keep polling, not red

    // Second look STILL mismatch → a GENUINE drop, not the race. NOW the
    // corrective re-POST, settle, and re-verify — the original remedy, unchanged.
    await rePost();
    await delay(repostSettle);
    return (await readbackMatch()) == true;
  }
  return false; // never recovered within maxWait
}

/// Resolve a 2xx cfg write's readback, tolerating the bench-proven post-commit
/// READBACK RACE with exactly ONE delayed re-look. On the heaviest syncs the
/// controller answers the POST (2xx) and the very next `/json/cfg` GET before its
/// flash/config state is fully consistent, so the first readback can report a
/// TRANSIENT mismatch even though the timers landed perfectly (proven on
/// 192.168.1.150, 2026-07-23 — curl seconds later matched the exact sent payload:
/// 12:52 macro:10 / 12:56 macro:2, en:1, dow:8).
///
/// - first readback true  → true  (confirmed; no wait)
/// - first readback null  → null  (unreadable — NOT a mismatch; caller decides,
///   e.g. falls through to the patient stall poll)
/// - first readback false → wait [retryDelay], read ONCE more:
///     true  → true  (the race resolved on the second look)
///     false → false (a GENUINE mismatch — the en:0 firmware class — hard-fail)
///     null  → null  (became unreadable; caller falls to the patient poll)
///
/// Exactly one retry — never a loop; the hard-fail stays reachable. All waiting
/// goes through [delay] so tests inject an instant clock. This is a TIMING
/// tolerance only; it does not touch the content comparison ([timersInsLanded]).
@visibleForTesting
Future<bool?> verify2xxReadbackWithRetry({
  required Future<bool?> Function() readbackMatch,
  required Future<void> Function(Duration) delay,
  Duration retryDelay = const Duration(seconds: 10),
}) async {
  final first = await readbackMatch();
  if (first != false) return first; // true (confirmed) or null (unreadable)
  await delay(retryDelay);
  return readbackMatch(); // second look is authoritative: true / false / null
}

/// Outcome of the cfg push + verify (see [ScheduleSyncService._pushCfgWithVerify]).
enum CfgPushOutcome {
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

/// Shared hardened cfg-write-and-verify — the SINGLE implementation used by
/// both [ScheduleSyncService.syncAll] and the CalendarEntry lease writer
/// (calendar_entry_lease_manager.dart). Do NOT duplicate this logic.
///
/// Models the bench-proven post-commit stall: the POST /json/cfg COMMITS the
/// timers to flash, but the commit can freeze the controller's web server for
/// MINUTES (the LEDs keep running; it self-recovers — no crash, no power cycle).
/// Re-POSTing into that blackout is harmful, so we do NOT retry the write — we
/// wait for the controller to answer again and confirm by readback
/// ([timersInsLanded]: every real timer we sent must appear with en==1). [ins]
/// is the exact array sent (post-normalize). [onVerifying] fires once when the
/// patient poll begins (schedule UI status hook; the lease path passes null).
///
/// Returns:
/// - [CfgPushOutcome.confirmed]    timers verified present + enabled
/// - [CfgPushOutcome.mismatch]     2xx but readback content differs and PERSISTS
///                                 across the delayed re-look — the controller
///                                 stored different values (e.g. the bool-en
///                                 class that this very saga fixed)
/// - [CfgPushOutcome.notConfirmed] never confirmed within the window / relay
///                                 or webhook failure
Future<CfgPushOutcome> pushCfgWithVerify({
  required WledRepository repo,
  required Map<String, dynamic> payload,
  required List<Map<String, dynamic>> ins,
  void Function()? onVerifying,
  // Injectable clock — production uses real Future.delayed; tests pass an
  // instant delay so the readback-race retry and stall poll don't sleep.
  Future<void> Function(Duration)? delay,
}) async {
  final tick = delay ?? (d) => Future<void>.delayed(d);
  // Readback content-match: does the controller's timer table CONTAIN every
  // real timer we sent (en==1)? true=confirmed, false=recovered-but-absent,
  // null=unreadable (relay/mock, fetch error, or still stalled) → inconclusive.
  Future<bool?> readback() async {
    if (repo is! WledService) return null; // cfg is not readable via the relay
    final actual = await repo.fetchTimerInstances();
    if (actual == null) return null;
    return timersInsLanded(ins, actual);
  }

  final ok = await repo.applyConfig(payload);
  if (ok) {
    // 2xx — reported success. Still readback-verify, tolerating the post-commit
    // READBACK RACE (bench 2026-07-23: the GET can catch the controller mid-
    // commit; a re-look seconds later matched). One 10s-delayed re-look before
    // we ever go red. See [verify2xxReadbackWithRetry].
    final verified = await verify2xxReadbackWithRetry(
      readbackMatch: readback,
      delay: tick,
    );
    if (verified == true) return CfgPushOutcome.confirmed;
    if (verified == false) {
      // The race is ruled out by the delayed re-look, so a persisting mismatch
      // is a real defect (firmware stored our values wrong, e.g. the en:0 bool
      // class). Fail loudly.
      debugPrint('CfgVerify: cfg 2xx but readback CONTENT-MISMATCH persisted on '
          'the delayed re-look — the controller stored different values; '
          'failing loudly');
      return CfgPushOutcome.mismatch;
    }
    // verified == null: readback unavailable. On this hardware a null right
    // after a 2xx means the controller is stalling on the post-commit flash
    // save. DO NOT trust the 2xx — a disabled/rejected write (the bool-en bug)
    // would slip through green. Fall to the patient poll. A relay/webhook can't
    // be polled, so THERE a 2xx is trusted.
    if (repo is! WledService) return CfgPushOutcome.confirmed;
    debugPrint('CfgVerify: cfg 2xx but readback unavailable (controller likely '
        'stalling) — verifying patiently, NOT trusting the 2xx');
  } else {
    // POST returned false. On the LAN service this is the post-commit stall (the
    // flash write may have landed; the HTTP response never returned). For a
    // relay/webhook a false is a genuine failure with no stall model — fail fast.
    if (repo is! WledService) return CfgPushOutcome.notConfirmed;
    debugPrint('CfgVerify: cfg POST returned false on LAN — assuming the '
        'post-commit network stall; NOT re-POSTing, verifying patiently');
  }

  // Patient verify-poll — reached on (POST false) OR (2xx + null readback) on
  // the LAN service. Wait for the controller to answer again, then content-
  // match; NO re-POST unless it recovers and still genuinely mismatches.
  final wledRepo = repo; // promoted to WledService by the guards above
  onVerifying?.call();

  final started = DateTime.now();
  final confirmed = await verifyCfgAfterStall(
    liveness: () => wledRepo.ping(),
    readbackMatch: readback,
    rePost: () async {
      try {
        return await wledRepo.applyConfig(payload);
      } catch (_) {
        return false;
      }
    },
    delay: tick,
  );
  final stalledFor = DateTime.now().difference(started).inSeconds;
  if (confirmed) {
    debugPrint('CfgVerify: controller stalled ~${stalledFor}s after the cfg '
        'commit; write VERIFIED on recovery');
    return CfgPushOutcome.confirmed;
  }
  debugPrint('CfgVerify: controller did not confirm the cfg write within the '
      '${stalledFor}s verification window');
  return CfgPushOutcome.notConfirmed;
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

  /// WLED preset holding the master-OFF state. Every OFF boundary — clock,
  /// solar, and the global sunrise-off — fires `macro: kNglOffPresetId`.
  static const int kNglOffPresetId = 2;
  static const String kNglOffPresetName = 'NGL Off';

  /// THE definition of the OFF preset. Single source of truth: schedule sync
  /// seeds it here, and the sunrise-off writer (sunrise_off_service.dart)
  /// re-uses this exact builder before arming its timer, so the two can never
  /// drift into saving different "off" states under the same preset id.
  ///
  /// `ib: true` persists root `on:false` into the stored preset, so LOADING it
  /// kills master power regardless of what pattern is running. The per-segment
  /// off list covers the full strip because a preset load only touches segments
  /// present in the preset (bench-proven: a seg[0]-only OFF left seg1 lit).
  static Map<String, dynamic> buildNglOffPresetState(
          Map<String, dynamic>? liveState) =>
      <String, dynamic>{
        'on': false,
        'ib': true,
        'seg': _fullStripOffSegments(liveState),
      };

  /// Whether a stored preset def already IS a usable NGL Off. Requires the def
  /// to actually assert root `on:false` — a legacy segments-only preset 2 is
  /// NOT satisfying and gets re-saved. Shared so the sunrise-off writer applies
  /// the same bar before deciding to skip its psave.
  /// The system ON presets: slot → (name, brightness). Exposed so the
  /// on-connect defaults healer can repair them without re-deriving the
  /// definitions.
  ///
  /// ⚠️ These MUST stay in step with the four `psaveIfChanged` calls in
  /// [syncAll] (search 'NGL On'). Those literals are deliberately left inline
  /// here — rewriting the shipping sync path to consume this map is a
  /// refactor, and this change is scoped to the master-power defect. The drift
  /// risk is recorded in docs/BUGS_AND_DEBT.md.
  static const Map<int, ({String name, int bri})> kOnPresetSpecs = {
    1: (name: 'NGL On', bri: 200),
    3: (name: 'NGL Dim', bri: 51),
    4: (name: 'NGL Low', bri: 102),
    5: (name: 'NGL Medium', bri: 153),
  };

  /// The exact state a system ON preset must be psaved with. `ib: true` is what
  /// makes WLED persist the ROOT `on`/`bri` into the stored preset instead of
  /// segments only — without it the preset loads DARK from a master-off strip.
  static Map<String, dynamic> onPresetHealState(int bri) =>
      {'on': true, 'bri': bri, 'ib': true};

  /// An ON system preset (1/3/4/5) is satisfied only when it carries the right
  /// name AND asserts ROOT master power (`on: true`).
  ///
  /// WHY THE NAME ALONE WAS NOT ENOUGH (the defect this closes): the previous
  /// predicate was `_presetNamed(d, 'NGL On')`, so any preset merely CALLED
  /// "NGL On" satisfied it and [psaveIfChanged] skipped the write forever. On
  /// every controller commissioned before 9158c00 that preset already existed
  /// without root `on`, so the ib:true fix was inert on the entire installed
  /// fleet: the timer fires, loads macro:1, and the strip stays DARK.
  /// Bench-proven 2026-07-30 (vid 2507300): presets 1/3/4/5 read `on: ABSENT`,
  /// and `{"ps":1}` from a master-off strip left `on:false`.
  ///
  /// WHY `bri` IS DELIBERATELY NOT ASSERTED: a `psave` APPLIES its inline state
  /// live on this firmware, so every needless re-save is a visible disruption.
  /// Brightness drift (a user nudging the slider, a rounding difference) is
  /// cosmetic and must not trigger a re-save on every sync. Root `on` is the
  /// only field whose absence breaks scheduled firing, so it is the only field
  /// added. This mirrors [isNglOffPresetSatisfied], which likewise asserts the
  /// master-state field and not `bri`.
  ///
  /// `ib` is NOT asserted anywhere: it is a psave REQUEST flag, never stored —
  /// WLED does not write it back, so `ib` is absent on healthy presets too.
  static bool isNglOnPresetSatisfied(
          Map<String, dynamic> def, String expectedName) =>
      _presetNamed(def, expectedName) && def['on'] == true;

  static bool isNglOffPresetSatisfied(Map<String, dynamic> def) =>
      _presetNamed(def, kNglOffPresetName) &&
      def['on'] == false &&
      _presetIsOff(def);

  /// A fresh copy of the disabled-timer stub. Public so the sunrise-off writer
  /// (sunrise_off_service.dart) reclaims a vacated slot with the SAME stub the
  /// schedule path uses, instead of hand-rolling a second "disabled" shape.
  static Map<String, dynamic> disabledTimerStub() =>
      Map<String, dynamic>.from(_disabledTimerStub);

  /// Pad/truncate [ins] to exactly [kMaxWledTimers] entries. Real timers keep
  /// their order and values (so sunset hour:25 / sunrise hour:24 entries are
  /// untouched); unused slots become disabled stubs so a sync that dropped a
  /// schedule zeros the slot it vacated on the controller. Apply ONLY at the
  /// final push stage (syncAll / _buildMergedCfgPayload) — never inside
  /// buildCfgPayload, whose callers merge its real-timer list before padding.
  /// True when the assembled [ins] would ERASE the controller's timer table
  /// while arming nothing — an "all-stub clobber" — and must not be POSTed.
  ///
  /// BENCH-PROVEN 2026-08-03 on 192.168.1.150 (0.15.1, vid 2507300): pushing
  /// eight disabled stubs wiped a real clock timer AND a lease timer
  /// (macro 27) from slots 0-7. Only the slot-8 solar sentinel survived, and
  /// only because an 8-entry push doesn't reach it. **Lease timers live in
  /// GENERAL slots — macro 26-41 is a preset-id convention, not a slot
  /// reservation** — so an all-stub write destroys live lease automation.
  ///
  /// The condition is deliberately BOTH of:
  /// - [ins] contains no real enabled timer ([isRealEnabledTimer]: `en` truthy,
  ///   `macro != 0`, `hour != 255`) — so a payload carrying merged lease timers
  ///   still POSTs, which is what keeps an all-solar user's leases armed; and
  /// - [refusedCount] > 0 — enabled schedules existed and were ALL refused.
  ///
  /// The second conjunct is what preserves the legitimate CLEARING write. A
  /// user who deletes their last schedule has `refusedCount == 0`, so the
  /// padded all-stub payload still goes out and reclaims the vacated slots
  /// (the dow:0 accumulation fix — see [padTimersToMax]). "We had schedules and
  /// rejected them all" and "there are no schedules" produce byte-identical
  /// payloads; this flag is the only thing that tells them apart.
  ///
  /// "Carries nothing" deliberately uses [_carriesAnyEnabledEntry] and NOT
  /// [isRealEnabledTimer]: the latter excludes `hour == 255`, so a payload whose
  /// only content is the GLOBAL SUNRISE-OFF at slot 8 would look empty and be
  /// skipped — silently breaking the invariant that every sync re-asserts that
  /// slot rather than leaving it to luck (see syncAll's solar-assembly branch,
  /// and sunrise_off_preserve_test). Such a write asserts something real; it is
  /// not a clobber.
  @visibleForTesting
  static bool shouldSkipClobberingWrite({
    required List<Map<String, dynamic>> ins,
    required int refusedCount,
  }) =>
      refusedCount > 0 && !ins.any(_carriesAnyEnabledEntry);

  /// True when [t] is an enabled entry that does something — a clock timer, a
  /// lease, or a solar sentinel. Broader than [isRealEnabledTimer] on purpose:
  /// this asks "is there anything worth writing?", not "is this an armable
  /// clock timer?". A disabled padding stub (`en:0, macro:0`) is neither.
  static bool _carriesAnyEnabledEntry(Map<String, dynamic> t) {
    final en = t['en'];
    final enOn = en == true || en == 1;
    final macro = (t['macro'] is num) ? (t['macro'] as num).toInt() : 0;
    return enOn && macro != 0;
  }

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
      {bool solarEnabled = false, int maxSlots = kMaxWledTimers}) {
    // [maxSlots] is the GENERAL clock-slot budget available to schedules. It
    // defaults to the full table but syncAll passes `kMaxWledTimers - leaseCount`
    // so active lease timers (macro 26-41) keep their reserved slots — lease
    // priority (P0-3.2). Clamped to a sane range.
    final budget = maxSlots.clamp(0, kMaxWledTimers);
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
      if (!onSolar && slotsUsed >= budget) {
        overflowed = true;
        break;
      }
      if (!onSolar) slotsUsed += 1; // clock ON timer
      if (s.hasOffTime &&
          s.offTimeLabel != null &&
          !offSolar &&
          slotsUsed < budget) {
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
  /// [sunriseTaken] is set when the global sunrise-off owns slot 8. Schedule
  /// sunrise boundaries are then NOT assigned: an OFF boundary is redundant
  /// (identical macro 2 — superseded silently, same effect), and an ON boundary
  /// was already refused-and-warned in syncAll's arm guard, so it can't reach
  /// here. Sunset is unaffected, so a dusk-to-dawn schedule keeps its ON.
  ({
    Map<String, dynamic>? sunrise,
    Map<String, dynamic>? sunset,
    List<String> rejected,
  }) solarTimerSlots(List<ScheduleItem> schedules,
      {bool sunriseTaken = false}) {
    Map<String, dynamic>? sunrise;
    Map<String, dynamic>? sunset;
    final rejected = <String>[];

    void assign(bool isSunrise, Map<String, dynamic> entry, String who) {
      if (isSunrise) {
        // The global sunrise-off holds slot 8. Superseding a schedule's sunrise
        // OFF is a no-op in effect (both load macro 2 = master off), so this is
        // logged, not surfaced as a user-facing rejection.
        if (sunriseTaken) {
          debugPrint('ScheduleSync: sunrise slot owned by the global '
              'sunrise-off — superseded $who (same master-OFF effect)');
          return;
        }
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
  }) =>
      // Delegates to the pure-Dart builder (single source of truth — the bench/
      // CLI imports the SAME function). App path logs via debugPrint; the
      // extracted _buildTimerEntry / consts live in cfg_payload_builder.dart.
      cfg.buildCfgPayload(schedules,
          solarEnabled: solarEnabled, debug: debugPrint);

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

    // ── Global sunrise-off (reserved slot 8) ─────────────────────────────
    // Read like the lease timers below: if the user has opted in, this sync
    // MUST re-write the entry into the sunrise slot, or assembleSolarAwareIns
    // would stub-clobber a timer this sync doesn't own (the P0-3 clobber class,
    // new victim). Defensive: any read failure → treat as not enabled rather
    // than letting it break a schedule sync.
    Map<String, dynamic>? globalSunriseOff;
    try {
      globalSunriseOff = ref.read(globalSunriseOffTimerProvider);
    } catch (e) {
      debugPrint('ScheduleSync: sunrise-off read failed — $e '
          '(proceeding without it)');
      globalSunriseOff = null;
    }

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
      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL On'),
    );
    // Preset 2 = Off. OFF timers fire `macro: 2`. `ib` is required on BOTH
    // directions — ib persists WHATEVER master state is saved: ON presets
    // persist root on:true, the OFF preset persists root on:false. The earlier
    // no-ib decision guarded against the one dangerous case — an OFF preset
    // accidentally saved with on:true — but the correct symmetric fix is to
    // save it with on:false + ib so LOADING it deterministically KILLS master
    // power, regardless of how many segments the prior pattern left running.
    //
    // Bench-proven 2026-07-22 (vid 2507300): a 2-segment pattern then macro:2
    // with the OLD seg[0]-only preset turned seg0 off but left seg1 running and
    // master ON (strip lit). With root on:false + ib, the load kills master →
    // strip dark (direct ps load AND a curl timer both verified all-dark).
    //
    // Belt-and-braces: also write an off segment for EVERY live segment (WLED
    // only stores off-segs for segments that exist at save time), so a firmware
    // that ignored root `on` on load would still blank the whole strip. Non-
    // disruptive: this psave is apply-then-snapshot and rides the same
    // capture/restore below as every other psave. (bri:0 is intentionally NOT
    // used — WLED preserves the last on-brightness when master is off, so it
    // never persists; root on:false is the real kill.)
    //
    // isSatisfied requires the stored def to actually assert root on:false, not
    // merely be seg-off — this self-heals legacy segments-only preset 2 (no root
    // master state), forcing the ib re-save on the first Sync. (The ON presets
    // 1/3/4/5 previously skipped on NAME ONLY and shared this landmine — that
    // was post-main queue item #3 and is now CLOSED: they use
    // isNglOnPresetSatisfied, which asserts root on:true the same way this one
    // asserts root on:false.)
    await psaveIfChanged(
      id: kNglOffPresetId,
      state: buildNglOffPresetState(capturedLiveState),
      name: kNglOffPresetName,
      isSatisfied: isNglOffPresetSatisfied,
    );
    await psaveIfChanged(
      id: 3,
      state: {'on': true, 'bri': 51, 'ib': true},
      name: 'NGL Dim',
      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Dim'),
    );
    await psaveIfChanged(
      id: 4,
      state: {'on': true, 'bri': 102, 'ib': true},
      name: 'NGL Low',
      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Low'),
    );
    await psaveIfChanged(
      id: 5,
      state: {'on': true, 'bri': 153, 'ib': true},
      name: 'NGL Medium',
      isSatisfied: (d) => isNglOnPresetSatisfied(d, 'NGL Medium'),
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

    // ── Slot hygiene: purge orphaned schedule presets ────────────────────
    // A deleted schedule leaves its pattern preset stranded in the app-managed
    // range (10–25). A stale ScheduleItem.presetId or a hand-set macro could
    // still point a timer at one, firing a ghost pattern ("Evening Glow" from a
    // long-deleted schedule was still loadable on the bench). After the current
    // slot set is built, delete every managed-range preset the device still
    // holds that no current schedule owns (owned = psaved this sync →
    // savedPresetIds). Strictly bounded to 10–25, so lease slots (26/28/41) and
    // user presets are never touched. `pdel` is WLED's preset-delete verb —
    // POST {"pdel":N} to /json/state (verified-by-bench 2026-07-22 on .150: the
    // slot vanished from presets.json). On-LAN only; cloud/mock can't enumerate
    // or delete, and the guard mirrors the fetchPresets read above. pdel does
    // NOT apply live state, so it never trips didWriteAnyPreset / restore.
    if (activeRepo is WledService) {
      for (var id = _firstSchedulePresetId; id <= _lastSchedulePresetId; id++) {
        if (existingPresets.containsKey(id) && !savedPresetIds.contains(id)) {
          final deleted = await activeRepo.deletePreset(id);
          if (!deleted) {
            debugPrint('ScheduleSync: failed to delete orphaned preset $id');
          }
        }
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
    // ── All-stub clobber guard: count REFUSALS, not warnings ─────────────
    // Bench-proven 2026-08-03 (.150): an 8-entry all-stub push WIPES every
    // general timer in slots 0-7, lease timers included. If every schedule is
    // refused below, `armable` is empty, buildCfgPayload returns nothing, and
    // the payload degrades to pure stubs — a write that erases the controller's
    // timer table and arms nothing. See [shouldSkipClobberingWrite].
    //
    // Why a counter and NOT `presetErrors.isNotEmpty`: several warnings are
    // emitted WITHOUT dropping a schedule (slots-full overflow, a redundant
    // sunrise OFF superseded by the global one). Keying on the warning list
    // would refuse a legitimate CLEARING write and strand stale timers on the
    // controller forever — the exact dow:0 accumulation padTimersToMax exists
    // to fix.
    //
    // Only count refusals that would OTHERWISE HAVE ARMED. This loop, unlike
    // buildCfgPayload, does not filter on `enabled`/eviction — so without this
    // filter a single DISABLED solar schedule would block the clearing write
    // for a user who has switched everything off.
    var refusedCount = 0;
    void countRefusal(ScheduleItem s) {
      if (s.enabled && !s.isCurrentlyEvicted) refusedCount++;
    }
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
        countRefusal(s);
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
        countRefusal(s);
        continue;
      }

      // ── Global sunrise-off owns the single sunrise slot ────────────────
      // WLED has exactly ONE sunrise slot. A schedule that turns lights ON at
      // sunrise genuinely cannot arm while the global sunrise-off holds it —
      // and the two are semantically opposed (on and off at the same instant),
      // so silently dropping either would be a lie. Refuse-and-warn, matching
      // every other arm invariant. Checked BEFORE the generic solar gate so the
      // user gets the specific, actionable reason ("turn that setting off")
      // rather than the generic "sunrise/sunset isn't supported".
      //
      // A schedule whose sunrise boundary is an OFF is NOT refused here: it
      // still arms its other boundaries (a dusk-to-dawn schedule keeps its
      // sunset ON) and its redundant sunrise OFF is superseded by the identical
      // global one — see solarTimerSlots's `sunriseTaken`.
      if (globalSunriseOff != null &&
          s.timeLabel.trim().toLowerCase() == 'sunrise') {
        presetErrors.add(
            '"${s.actionLabel}" turns lights ON at sunrise, which conflicts '
            'with "Turn lights off at sunrise daily" — not armed. Turn that '
            'setting off, or give this schedule a different time.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — sunrise '
            'ON conflicts with the global sunrise-off (slot '
            '$kWledSunriseSlot)');
        countRefusal(s);
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
        countRefusal(s);
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
        countRefusal(s);
        continue;
      }

      armable.add(s);
    }

    // ── P0-3.2: preserve active lease timers (macro 26-41) ──────────────────
    // The lease manager arms near-term dated leases in the high timer slots.
    // syncAll MUST merge them into its cfg write — otherwise padTimersToMax
    // stub-clobbers them (defect d: preset survives, lease timer never does).
    // Source = the lease manager's own activeLeaseTimers() via a flag-gated
    // provider (single source of truth; reuses _buildLeaseTimersPayload — no
    // second merge impl). Returns [] when lease live-writes are off, so this is
    // a no-op on the existing schedule-only path. Defensive: any read failure →
    // schedule-only (never let a lease-read error break a schedule sync).
    List<Map<String, dynamic>> leaseTimers;
    try {
      leaseTimers = ref.read(calendarLeaseActiveTimersProvider);
    } catch (e) {
      debugPrint('ScheduleSync: lease-timer read failed — $e '
          '(proceeding schedule-only)');
      leaseTimers = const [];
    }
    final leaseCount = leaseTimers.length;

    // ── Slot capacity: which armable schedules actually fit the table ───────
    // buildCfgPayload truncates at kMaxWledTimers; mirror its slot accounting
    // here so we (a) surface a loud warning when schedules overflow and (b)
    // count only the schedules that armed — never claim success for one that
    // silently fell off the controller. LEASE-PRIORITY (P0-3.2): the general
    // budget is reduced by the active lease count so a schedule can never claim
    // a lease-reserved slot; overflow schedules surface the existing 8/8 warning.
    final capacity = splitByTimerCapacity(armable,
        solarEnabled: solarEnabled, maxSlots: kMaxWledTimers - leaseCount);
    final armedSchedules = capacity.armed;
    if (capacity.overflowed) {
      presetErrors.add(
          "Schedule saved but couldn't arm — controller timer slots are full "
          "(8/8). Delete an old schedule.");
      debugPrint('ScheduleSync: ${armable.length - armedSchedules.length} '
          'schedule(s) could not arm — WLED timer table full (8/8)');
    }

    // Step 2: Build and push timer configuration. Clock timers fill the general
    // slots; lease timers (macro 26-41) are MERGED in so the write preserves
    // them; the array is padded so a vacated slot is overwritten with a disabled
    // stub (slot reclaim — clears dow:0 / stale timers). When solar is enabled
    // the push is a 10-entry array with the sunrise timer at slot 8 and sunset
    // at slot 9 (WLED 0.15.1 positional encoding); otherwise it's the 8-slot form.
    final built =
        buildCfgPayload(armedSchedules, solarEnabled: solarEnabled);
    final builtIns = ((built['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    // scheduleIns = SCHEDULE-derived timers only (for the empty-armed guard —
    // preserved lease timers must NOT mask a schedules-produced-nothing bug).
    // ins = the MERGED array actually written (schedules + leases).
    final List<Map<String, dynamic>> scheduleIns;
    final List<Map<String, dynamic>> ins;
    // The 10-slot solar assembly is required whenever ANY dedicated slot has an
    // owner — solar schedules OR the global sunrise-off. Using it purely
    // because the sunrise-off is on is what makes slot 8 authoritative on every
    // sync, so the timer is re-asserted rather than left to luck.
    if (solarEnabled || globalSunriseOff != null) {
      final solar = solarEnabled
          ? solarTimerSlots(armedSchedules,
              sunriseTaken: globalSunriseOff != null)
          : (
              sunrise: null,
              sunset: null,
              rejected: const <String>[],
            );
      // Only one sunrise slot (8) and one sunset slot (9) exist — reject-and-
      // warn any additional solar boundary (cross-schedule constraint).
      for (final who in solar.rejected) {
        presetErrors.add(
            'Only one sunrise and one sunset schedule are supported per '
            'controller — "$who" was not armed.');
        debugPrint('ScheduleSync: solar slot already taken — dropped $who');
      }
      // Slot 8: the global sunrise-off outranks a schedule's solar sunrise.
      final sunriseSlot = globalSunriseOff ?? solar.sunrise;
      // scheduleIns deliberately EXCLUDES the sunrise-off (it passes
      // solar.sunrise, not sunriseSlot) so a preserved global timer can never
      // mask a "schedules produced nothing" bug in the empty-armed guard below
      // — the same reason lease timers are excluded from it.
      scheduleIns = assembleSolarAwareIns(builtIns,
          sunrise: solar.sunrise, sunset: solar.sunset);
      // Lease timers are CLOCK timers → merge into the general pool BEFORE solar
      // assembly (solar entries own the dedicated slots 8/9).
      ins = assembleSolarAwareIns([...builtIns, ...leaseTimers],
          sunrise: sunriseSlot, sunset: solar.sunset);
    } else {
      scheduleIns = builtIns;
      ins = padTimersToMax([...builtIns, ...leaseTimers]);
    }
    final payload = <String, dynamic>{
      'timers': {'ins': ins},
    };

    // Empty-armed guard: armedSchedules passed every arm check, so they MUST
    // have produced real timer entries. If the SCHEDULE-derived payload has NONE
    // (all stubs), something in the build/reader dropped them (e.g. an enabled
    // flag that didn't survive the doc round-trip — the AI-doc class). The
    // content-match comparator would then trivially pass and report a false
    // green. Checked on scheduleIns (NOT the merged ins) so preserved lease
    // timers can't mask the bug. Fail loudly; never POST a no-op that arms nothing.
    if (armedSchedules.isNotEmpty && !scheduleIns.any(isRealEnabledTimer)) {
      debugPrint('ScheduleSync: ABORT — ${armedSchedules.length} armable '
          'schedule(s) but the built payload has zero real timers (all stubs). '
          'Refusing to POST a no-op that would false-green.');
      return finish(ScheduleSyncResult(
        success: false,
        // Customer-facing. The old text ("internal: enabled schedules produced
        // no armable timers") leaked a developer assertion into a red banner
        // and named neither cause nor remedy.
        //
        // NOTE ON SCOPE: this guard does NOT fire for solar-only accounts —
        // solar schedules are refused upstream in the `armable` loop, so
        // `armedSchedules` is empty and the first conjunct is false. Those
        // users get the specific "uses sunrise/sunset timing…" presetErrors
        // message instead (now rendered, not counted). So this message must
        // NOT mention sunrise/sunset: reaching here means a schedule passed
        // every arm check and still produced no timer, which is an internal
        // inconsistency, not a user misconfiguration. Keep it honest about
        // that rather than guessing at a cause.
        error: 'Your schedules are saved but could not be armed on the '
            'controller. Try syncing again — if this keeps happening, '
            'contact support.',
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

    // ── All-stub clobber guard ───────────────────────────────────────────
    // Every enabled schedule was refused above, and no lease timer filled the
    // payload either, so `ins` is nothing but disabled stubs. POSTing it would
    // ERASE the controller's timer table (bench-proven: a real clock timer and
    // a lease at macro 27 both wiped) and arm nothing in their place — strictly
    // worse than doing nothing, because it destroys working automation this
    // sync never owned.
    //
    // Deliberately NOT a silent skip: a refusal that looks like a success is
    // the exact defect class this guard exists to prevent. success:false with a
    // message that says what happened, plus the per-schedule presetErrors that
    // say what to fix (both now rendered — see my_schedule_page).
    //
    // ORDER MATTERS — this MUST stay below the off-LAN check. Off-LAN no cfg
    // write is attempted at all, so there is nothing to clobber and
    // `deferredOffLan` is the truthful, non-alarming answer ("saved, will arm
    // on next LAN sync"). Running this guard first turned that neutral state
    // into a red failure for every off-LAN all-solar user — caught by
    // schedule_sync_off_lan_test.
    if (shouldSkipClobberingWrite(ins: ins, refusedCount: refusedCount)) {
      debugPrint('ScheduleSync: SKIPPED cfg write — $refusedCount enabled '
          'schedule(s) refused and no lease timers, so the payload was all '
          'stubs. POSTing it would clear the controller\'s timer table and arm '
          'nothing. Controller left unchanged.');
      return finish(ScheduleSyncResult(
        success: false,
        error: 'None of your schedules could be armed, so your controller was '
            'left unchanged. Check the warnings for what to fix.',
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
        case CfgPushOutcome.confirmed:
          return finish(ScheduleSyncResult(
            success: true,
            presetErrors: presetErrors,
            // Count only schedules that actually armed — never overcount a
            // schedule dropped for a full table / dow:0 / bad time.
            schedulesWithPresets: armedSchedules,
          ));
        case CfgPushOutcome.mismatch:
          // 2xx but the controller stored different values — a firmware-
          // compatibility signal, not a transient. Surface it, don't warn-away.
          return finish(ScheduleSyncResult(
            success: false,
            error: kScheduleCfgFirmwareMismatch,
            presetErrors: presetErrors,
            schedulesWithPresets: updatedSchedules,
          ));
        case CfgPushOutcome.notConfirmed:
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
  /// - 2xx → readback content-match, tolerating the post-commit READBACK RACE
  ///   with ONE delayed re-look ([verify2xxReadbackWithRetry]); a mismatch that
  ///   PERSISTS on the re-look fails loudly (firmware mismatch).
  /// - timeout / connection error → assume the post-commit stall and enter
  ///   patient verification ([verifyCfgAfterStall]); NO re-POST unless the
  ///   controller recovers and the timers still aren't there.
  /// A [CfgWriteUnsupportedException] propagates out (→ deferredOffLan in
  /// syncAll). [ins] is the exact array we sent (post-normalize).
  /// Thin wrapper over the shared [pushCfgWithVerify] that also surfaces the
  /// interim "verifying…" status on the schedule UI during the patient poll.
  /// See [pushCfgWithVerify] for the full stall / readback-race model.
  /// [ins] is the exact array we sent (post-normalize).
  Future<CfgPushOutcome> _pushCfgWithVerify(
    Ref ref,
    WledRepository repo,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> ins,
  ) {
    return pushCfgWithVerify(
      repo: repo,
      payload: payload,
      ins: ins,
      onVerifying: () =>
          ref.read(lastScheduleSyncResultProvider.notifier).state =
              ScheduleSyncResult.verifying(),
    );
  }

  /// Legacy sync method for backward compatibility.
  /// Prefer using [syncAll] which returns detailed results.
  Future<bool> syncAllLegacy(Ref ref, List<ScheduleItem> schedules) async {
    final result = await syncAll(ref, schedules);
    return result.success;
  }

  // Helpers

  // _parseTimeLabel moved to cfg_payload_builder.dart (pure Dart, as
  // parseTimeLabel); its only callers were _buildTimerEntry (also moved) and
  // _isArmableTimeLabel (now delegates below).

  /// True when [label] is a time WLED can actually arm: a solar keyword or a
  /// clock time [parseTimeLabel] recognizes. Used by [syncAll] to refuse
  /// arming a timer that would otherwise silently fire at midnight.
  bool _isArmableTimeLabel(String label) => cfg.isArmableTimeLabel(label);

  /// True for the two solar keywords the app (wrongly) maps to WLED hour 24/25.
  /// Used by the Option-A refuse guards until solar is re-encoded correctly —
  /// see memory/project_solar_schedules_never_fire.
  static bool _isSolarLabel(String label) => cfg.isSolarLabel(label);

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
  int _presetForAction(String actionLabel) => cfg.presetForAction(actionLabel);

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

  /// "All segments off" payload covering the full strip. A WLED preset load
  /// only touches segments present in the preset, so a single seg[0]:off leaves
  /// higher segments (multi-segment patterns) running — bench-proven the leak
  /// that left a 2-segment pattern's seg1 lit after an OFF timer. Mirror the
  /// controller's current segment layout — one {id, on:false} per live segment
  /// — so the OFF preset blanks every segment the device actually has. (WLED
  /// stores off-segs only for segments that exist at save time, so this must
  /// track the live layout, not a fixed guess.) Falls back to a single off
  /// segment when live state is unavailable (cloud/mock/getState failure).
  static List<Map<String, dynamic>> _fullStripOffSegments(
      Map<String, dynamic>? liveState) {
    final seg = liveState?['seg'];
    if (seg is List && seg.isNotEmpty) {
      final out = <Map<String, dynamic>>[];
      for (var i = 0; i < seg.length; i++) {
        final s = seg[i];
        final id = (s is Map && s['id'] is int) ? s['id'] as int : i;
        out.add({'id': id, 'on': false});
      }
      return out;
    }
    return [
      {'on': false}
    ];
  }

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

// _ParsedTime moved to cfg_payload_builder.dart (pure Dart, as ParsedTime).

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
