import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/audio/services/audio_capability_detector.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart'
    show repoCanWriteCfg;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart'
    show CfgWriteUnsupportedException;
import 'package:nexgen_command/features/wled/wled_service.dart' show WledService;

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

  /// Total timer slots WLED honors in `timers.ins`.
  static const int kMaxWledTimers = 8;

  /// Disabled timer stub used to overwrite a vacated WLED slot. WLED merges
  /// `timers.ins` by index and never clears slots beyond the pushed array's
  /// length, so a shrinking schedule set would otherwise leave stale timers
  /// armed in the high slots (the dow:0 orphan-accumulation bug). Padding every
  /// pushed payload to exactly [kMaxWledTimers] entries with these stubs makes
  /// each sync authoritative over all 8 slots. `en:0` so a stub never fires.
  static const Map<String, dynamic> _disabledTimerStub = {
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
      List<ScheduleItem> armable) {
    final armed = <ScheduleItem>[];
    var slotsUsed = 0;
    var overflowed = false;
    for (final s in armable) {
      if (slotsUsed >= kMaxWledTimers) {
        overflowed = true;
        break;
      }
      slotsUsed += 1; // ON timer
      if (s.hasOffTime &&
          s.offTimeLabel != null &&
          slotsUsed < kMaxWledTimers) {
        slotsUsed += 1; // OFF timer
      }
      armed.add(s);
    }
    return (armed: armed, overflowed: overflowed);
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
  Map<String, dynamic> buildCfgPayload(List<ScheduleItem> schedules) {
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

      // Solar (sunrise/sunset) refuse — Option A, see
      // memory/project_solar_schedules_never_fire. The app maps a solar label
      // to WLED hour 24/25, which WLED does NOT honor as sunrise/sunset: hour
      // 24 fires HOURLY and hour 25 never matches the RTC. So a solar boundary
      // is a dead timer at best and an hourly-snap-off at worst. Refuse the
      // WHOLE schedule (a half-solar schedule is still broken) so no solar
      // timer is written and existing ones get reclaimed by the padded push.
      // This is defense-in-depth: syncAll's arm guard warns the user; this
      // covers the lease-manager path that bypasses syncAll's guards.
      if (_isSolarLabel(s.timeLabel) ||
          (s.hasOffTime &&
              s.offTimeLabel != null &&
              _isSolarLabel(s.offTimeLabel!))) {
        debugPrint('ScheduleSync: skipped solar timer for "${s.actionLabel}" '
            '(on=${s.timeLabel} off=${s.offTimeLabel}) — hour 24/25 is not '
            'honored by WLED; refusing until solar is re-encoded');
        continue;
      }

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
      if (s.hasOffTime && s.offTimeLabel != null && timers.length < kMaxWledTimers) {
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
        'en': true,
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
    await psaveIfChanged(
      id: 1,
      state: {'on': true, 'bri': 200},
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
      state: {'on': true, 'bri': 51},
      name: 'NGL Dim',
      isSatisfied: (d) => _presetNamed(d, 'NGL Dim'),
    );
    await psaveIfChanged(
      id: 4,
      state: {'on': true, 'bri': 102},
      name: 'NGL Low',
      isSatisfied: (d) => _presetNamed(d, 'NGL Low'),
    );
    await psaveIfChanged(
      id: 5,
      state: {'on': true, 'bri': 153},
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

        // Idempotent: skip the psave when slot already holds this design, so a
        // re-sync of an unchanged pattern schedule writes nothing (no flash).
        // A genuinely new/changed design is the only case that writes — and
        // that single write is undone visually by the capture/restore below.
        final payload = effectiveSchedule.wledPayload!;
        await psaveIfChanged(
          id: presetId,
          state: payload,
          name: effectiveSchedule.actionLabel,
          isSatisfied: (d) => _scheduleDesignMatches(d, payload),
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

    // ── Restore live output ──────────────────────────────────────────────
    // Each psave above applied its inline state to the live strip (no
    // non-applying save exists on this firmware for a differing preset). If we
    // wrote at least one preset, re-apply the state captured before the batch
    // so the lights end exactly where they started — saving/editing a schedule
    // and navigating away must NOT turn the system on or change the look. A
    // sync that wrote nothing (all presets already current) skips this, so the
    // common path touches the strip zero times. This is purely a live-output
    // restore; it never touches timers, so the two-timer ON/OFF boundary
    // invariant is untouched — only the RTC fires boundaries.
    if (didWriteAnyPreset && capturedLiveState != null) {
      final restore = <String, dynamic>{
        if (capturedLiveState['on'] != null) 'on': capturedLiveState['on'],
        if (capturedLiveState['bri'] != null) 'bri': capturedLiveState['bri'],
        if (capturedLiveState['seg'] != null) 'seg': capturedLiveState['seg'],
      };
      if (restore.isNotEmpty) {
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

      // ── Sunrise/sunset not supported yet (refuse-and-warn) ─────────────
      // The app maps a solar label to WLED hour 24/25, which WLED never fires
      // as sunrise/sunset — hour 24 fires HOURLY (snapping lights off every
      // hour on a solar-OFF boundary) and hour 25 never matches. Refuse-and-
      // warn so the schedule surfaces instead of writing a dead/hourly timer;
      // _isArmableTimeLabel treats solar as valid, so the bad-time guard above
      // does NOT catch this. Restore solar as a bench-gated feature later
      // (Option B). Both boundaries checked together — a solar OFF is as bad
      // as a solar ON.
      final solarLabels = <String>[
        if (_isSolarLabel(s.timeLabel)) s.timeLabel,
        if (s.hasOffTime &&
            s.offTimeLabel != null &&
            _isSolarLabel(s.offTimeLabel!))
          s.offTimeLabel!,
      ];
      if (solarLabels.isNotEmpty) {
        presetErrors.add(
            '"${s.actionLabel}" uses sunrise/sunset timing, which isn\'t '
            'supported yet — please set a specific time.');
        debugPrint('ScheduleSync: refused to arm "${s.actionLabel}" — solar '
            'timing not supported (${solarLabels.join(", ")})');
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
    final capacity = splitByTimerCapacity(armable);
    final armedSchedules = capacity.armed;
    if (capacity.overflowed) {
      presetErrors.add(
          "Schedule saved but couldn't arm — controller timer slots are full "
          "(8/8). Delete an old schedule.");
      debugPrint('ScheduleSync: ${armable.length - armedSchedules.length} '
          'schedule(s) could not arm — WLED timer table full (8/8)');
    }

    // Step 2: Build and push timer configuration. Only armed schedules become
    // real timers; the payload is padded to all 8 slots so any slot a
    // now-removed schedule vacated is overwritten with a disabled stub (slot
    // reclaim — this is what clears the accumulated dow:0 orphans).
    final built = buildCfgPayload(armedSchedules);
    final builtIns = ((built['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    final payload = <String, dynamic>{
      'timers': {
        'ins': padTimersToMax(builtIns),
      },
    };

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

    try {
      final ok = await repo.applyConfig(payload);
      if (!ok) {
        return finish(ScheduleSyncResult(
          success: false,
          error: 'Failed to save timer configuration',
          presetErrors: presetErrors,
          schedulesWithPresets: updatedSchedules,
        ));
      }

      return finish(ScheduleSyncResult(
        success: true,
        presetErrors: presetErrors,
        // Count only schedules that actually armed — never overcount a
        // schedule dropped for a full table / dow:0 / bad time.
        schedulesWithPresets: armedSchedules,
      ));
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

  /// Best-effort match between a stored schedule preset and the [payload] we
  /// would write — compares the first segment's effect id and primary color.
  /// A false negative (treats a match as a mismatch) only costs one redundant
  /// write, which the capture/restore in syncAll renders invisible; it never
  /// produces a false positive that would leave a stale design armed.
  static bool _scheduleDesignMatches(
      Map<String, dynamic> def, Map<String, dynamic> payload) {
    try {
      final dSeg = def['seg'];
      final pSeg = payload['seg'];
      if (dSeg is! List || pSeg is! List || dSeg.isEmpty || pSeg.isEmpty) {
        return false;
      }
      final d0 = dSeg.first;
      final p0 = pSeg.first;
      if (d0 is! Map || p0 is! Map) return false;
      if (d0['fx'] != p0['fx']) return false;
      final dCol = d0['col'];
      final pCol = p0['col'];
      if (dCol is! List || pCol is! List || dCol.isEmpty || pCol.isEmpty) {
        return false;
      }
      return _sameColor(dCol.first, pCol.first);
    } catch (_) {
      return false;
    }
  }

  /// Compares two WLED color arrays on their R/G/B channels (ignoring a
  /// possibly-absent W channel and any normalization padding).
  static bool _sameColor(dynamic a, dynamic b) {
    if (a is! List || b is! List) return false;
    for (var i = 0; i < 3; i++) {
      final av = i < a.length && a[i] is num ? (a[i] as num).toInt() : 0;
      final bv = i < b.length && b[i] is num ? (b[i] as num).toInt() : 0;
      if (av != bv) return false;
    }
    return true;
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

  ScheduleSyncResult({
    required this.success,
    this.error,
    this.presetErrors = const [],
    this.schedulesWithPresets = const [],
    this.deferredOffLan = false,
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

  /// Returns true if there were any preset-related errors.
  bool get hasPresetErrors => presetErrors.isNotEmpty;

  /// Returns a summary message suitable for user display.
  String get summaryMessage {
    if (deferredOffLan) return kScheduleOffLanNotice;
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
