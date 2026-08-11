// lib/features/schedule/calendar_entry_lease_manager.dart
//
// Item #61 Workstream B — 48-hour lease window for date-specific
// CalendarEntries into the 8-slot WLED timers.ins array.
//
// CalendarEntry is the storage form for date-specific overrides
// (Christmas, game days, anniversary). WLED's stock timer slots are
// weekday-recurring, with no native single-date field. This service
// bridges the gap: when a CalendarEntry's onTime is within the next
// 48 hours, allocate a timer slot + preset, build a single-day dow
// bitmask, and push it to the controller. After offTime passes,
// the periodic sweep writes a zeroed slot entry and releases the
// preset back to the pool.
//
// SCOPE OF THIS COMMIT
// --------------------
// - Service + models + provider with periodic sweep
// - WLED payload synthesis (Path A: inline from flat fields)
// - 48h window detection, slot/preset allocation, registry
//   persistence to SharedPreferences
// - Hooked into [CalendarScheduleNotifier.applyEntries] and
//   [CalendarScheduleNotifier.removeEntry] so every Lumina AI,
//   manual editor, and autopilot write surfaces a lease.
//
// EXPLICITLY DEFERRED
// -------------------
// - Eviction UX when [LeaseOutcome.noFreeSlots] is returned —
//   Prompt 4. For now, the entry is saved to Firestore and shown
//   on the calendar, but won't fire on the controller.
// - Coordination with [ScheduleSyncService] so ScheduleItem timers
//   and lease timers coexist in the same `timers.ins` array —
//   Prompt 5 wires this against a live controller.
// - ScheduleItem priority/pinned field to enable explicit eviction
//   ordering — Workstream A.
// - Past CalendarEntry cleanup (Firestore prune) — Prompt 6.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_lease_feature_flag.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/wled/wled_dow.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';
export 'package:nexgen_command/features/wled/wled_preset_ranges.dart'
    show kFirstLeasePresetId, kLastLeasePresetId;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart'
    show repoCanWriteCfg;
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart'
    show rgbToRgbw, WledService;
import 'package:nexgen_command/utils/async_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

/// Total timer slots in WLED's `timers.ins` array.
const int kWledMaxTimerSlots = 8;

/// Preset ID range reserved for lease-owned presets (26–41). Picked so the
/// existing ScheduleItem range (10–25, see [ScheduleSyncService]) and
/// system presets (1, 2) are untouched. 16 lease slots × 48h lifetime
/// >> any realistic dateKey-modulo-16 collision frequency.
///
/// The constants themselves now live in `wled_preset_ranges.dart` — the file
/// that documents the whole 1-250 allocation map — and are re-exported here so
/// existing importers are unaffected. They moved because a second reader
/// appeared: the base-boundary publisher classifies a timer's `macro` by which
/// range allocated it, and a private-to-this-file range would have forced a
/// duplicate table.
const int _kLeasePresetCount = kLastLeasePresetId - kFirstLeasePresetId + 1; // 16

const Duration kLeaseWindow = Duration(hours: 48);
const Duration _kSweepInterval = Duration(minutes: 5);

const String _kLeaseStorageKey = 'calendar_leases_v1';
const String _kLogPrefix = 'CalendarLease:';

// ─── Testable Ref indirection ────────────────────────────────────────────────
//
// Both providers exist solely so unit tests can override slot occupancy and
// the entry set without constructing the real [SchedulesNotifier] /
// [CalendarScheduleNotifier]. Production reads flow through the upstream
// providers untouched.

/// Slot demand from currently-enabled, non-evicted ScheduleItems.
///
/// Treats each enabled ScheduleItem as occupying one timer slot. Real
/// [ScheduleSyncService.buildCfgPayload] can consume 1–2 slots per
/// schedule when an OFF timer is configured, but the upstream loop caps
/// at 8 regardless. Treating each as 1 here is a conservative simplification
/// that matches the unit-test contract and gives leases the back end of
/// the slot range; over-allocation (counting fewer slots than reality)
/// would have the lease manager overwrite ScheduleItem slots, which is
/// strictly worse.
///
/// Excludes [ScheduleItem.isCurrentlyEvicted] items so the lease
/// manager's free-slot count agrees with what `buildCfgPayload`
/// actually writes (Item #61 Workstream B eviction filter must match
/// on both sides of the pipe — divergence would re-introduce silent
/// slot overwrites).
final calendarLeaseScheduleSlotDemandProvider = Provider<int>((ref) {
  final schedules = ref.watch(schedulesProvider);
  final demand =
      schedules.where((s) => s.enabled && !s.isCurrentlyEvicted).length;
  return demand.clamp(0, kWledMaxTimerSlots);
});

/// All CalendarEntries the sweep should consider for newly-imminent
/// promotion. Indirected for testability.
final calendarLeaseEntriesProvider = Provider<List<CalendarEntry>>((ref) {
  final map = ref.watch(calendarScheduleProvider);
  return map.values.toList(growable: false);
});

/// All current ScheduleItems — used by the sweep to detect items
/// whose `disabledUntil` has passed and needs clearing. Indirected
/// for testability.
final calendarLeaseSchedulesProvider = Provider<List<ScheduleItem>>((ref) {
  return ref.watch(schedulesProvider);
});

/// Callable that applies a ScheduleItem update through the canonical
/// notifier (which fires the debounced WLED sync). Indirected so tests
/// can replace this with a no-network fake without constructing the
/// real [SchedulesNotifier].
typedef ScheduleUpdaterFn = Future<void> Function(ScheduleItem item);

final calendarLeaseScheduleUpdaterProvider =
    Provider<ScheduleUpdaterFn>((ref) {
  return (item) async {
    await ref.read(schedulesProvider.notifier).update(item);
  };
});

/// Sync adapter over [calendarLeaseLiveWritesEnabledProvider] so the
/// manager can `.read()` a synchronous bool without AsyncValue
/// plumbing at every call site, and tests can `.overrideWithValue(...)`
/// without awaiting the upstream stream's first emission.
///
/// Production reads pass through to the stream provider; an initial
/// AsyncLoading state resolves to `false` (safe default).
@visibleForTesting
final calendarLeaseLiveWritesEnabledSyncProvider = Provider<bool>((ref) {
  return ref
      .watch(calendarLeaseLiveWritesEnabledProvider)
      .maybeWhen(data: (v) => v, orElse: () => false);
});

/// Callable that forces an immediate WLED re-sync, bypassing the
/// 800 ms debounce. Used by the sweep when soft-evicted items
/// re-enable so the freed-then-re-occupied slot reaches the
/// controller without waiting for the next mutation. Indirected for
/// testability.
typedef ScheduleSyncTriggerFn = Future<void> Function();

final calendarLeaseScheduleSyncTriggerProvider =
    Provider<ScheduleSyncTriggerFn>((ref) {
  return () async {
    await ref.read(schedulesProvider.notifier).runSyncNow();
  };
});

/// Count how many times the given ScheduleItem would fire during the
/// half-open window `[from, until)`, considering its repeatDays mask
/// and timeLabel. Counts ON events only.
///
/// Used by the eviction picker to annotate each item with "pauses N
/// fires" so the user chooses intentionally.
///
/// Edge convention: each calendar day where `appliesToDay(item, day)`
/// is true contributes one fire if the day intersects the window —
/// boundary precision (whether the time-of-day falls inside the
/// window on partial-boundary days) is intentionally NOT honored.
/// Good enough for UX annotation; precise simulation would require
/// resolving sunset/sunrise per day, which isn't worth the complexity
/// for a count label.
int fireCountDuringWindow({
  required ScheduleItem item,
  required DateTime from,
  required DateTime until,
}) {
  if (!from.isBefore(until)) return 0;
  final days = item.repeatDays.map((d) => d.toLowerCase()).toList();
  final daily = days.any((d) => d.contains('daily'));
  bool firesOn(int weekday) {
    if (daily) return true;
    // weekday: 1=Mon..7=Sun
    const labels = ['', 'mon', 'tue', 'wed', 'thu', 'fri', 'sat', 'sun'];
    final target = labels[weekday];
    return days.any((d) => d.startsWith(target));
  }

  // Iterate each calendar day touched by [from, until). Use the date
  // floor of `from` so a window starting at 14:00 still counts a fire
  // earlier the same day if applicable — UX annotation, not strict
  // simulation.
  var cursor = DateTime(from.year, from.month, from.day);
  final endFloor = DateTime(until.year, until.month, until.day);
  int count = 0;
  while (!cursor.isAfter(endFloor)) {
    if (firesOn(cursor.weekday)) count++;
    cursor = cursor.add(const Duration(days: 1));
  }
  return count;
}

// ─── Models ──────────────────────────────────────────────────────────────────

enum LeaseOutcome {
  /// Entry's onTime is more than 48 hours away. No lease needed yet —
  /// the periodic sweep will promote it when the window opens.
  outsideWindow,

  /// New lease created and slot allocated.
  leased,

  /// Existing lease for this dateKey updated in place (same slot,
  /// same preset, payload re-synthesized).
  updated,

  /// All 8 timer slots are occupied. Entry was still saved to Firestore
  /// and is visible on the calendar — only the WLED firing path is blocked.
  /// Eviction UX (Prompt 4) will surface a chooser here.
  noFreeSlots,

  /// Entry's onTime/offTime are null or unparseable — cannot build a
  /// timer entry. Caller decides whether to surface the error.
  invalidEntry,

  /// Entry's offTime already passed by the time the lease was attempted.
  /// Skip — nothing to fire.
  alreadyExpired,

  /// WLED preset write failed when live writes were enabled. The
  /// in-memory registry has been rolled back so the manager state
  /// stays consistent. Caller may surface a "couldn't save to
  /// controller" banner. Distinct from [noFreeSlots] — slot was
  /// available; the controller round-trip itself failed.
  ///
  /// Note: applyConfig (timer-slot push) failure AFTER a successful
  /// savePreset does NOT roll back the registry — the preset is
  /// orphaned on the controller; the next sweep retries the timer
  /// write. That path returns [leased] with the lease record
  /// populated.
  writeFailed,
}

/// P0-9 (part a) — the tri-state result of [CalendarEntryLeaseManager.activeLeaseTimers].
///
/// WHY A SEALED TYPE AND NOT A NULLABLE LIST: the defect being fixed is that two
/// semantically opposite situations shared one representation (`[]`). Encoding
/// "unknown" as `null` would be the same in-band signal one step removed — a
/// caller can still ignore it and reach for the list. A sealed hierarchy makes
/// Dart's exhaustiveness checking refuse to compile a caller that forgets the
/// loading case, so the conflation cannot silently reappear. That structural
/// guarantee is worth ~20 lines on a P0 whose entire cause was an implicit
/// encoding. Records (used elsewhere in this file for multi-value returns) were
/// the alternative but carry no such enforcement.
///
/// [LeaseLedgerEmpty] and [LeaseLedgerReady] are kept DISTINCT rather than
/// collapsed into `Ready(const [])` so the debug log can say which one it was —
/// "ledger empty" vs "ledger loading" is the first question asked when a lease
/// goes missing.
sealed class LeaseLedgerState {
  const LeaseLedgerState();

  /// The lease timers to merge. Empty for both [LeaseLedgerLoading] and
  /// [LeaseLedgerEmpty] — callers must NOT use this to distinguish them; switch
  /// on the type. Provided only so the merge site has a well-defined value on
  /// paths that never reach a write.
  List<Map<String, dynamic>> get timers => const [];
}

/// The ledger has not finished loading — the lease set is UNKNOWN, not empty.
/// A cfg write in this state would drop every live lease. Refuse instead.
class LeaseLedgerLoading extends LeaseLedgerState {
  const LeaseLedgerLoading();
}

/// The ledger is loaded and this account genuinely has no active leases.
/// Merging nothing is CORRECT here — a sync must still write (to clear the
/// device), exactly as a hydrated user with zero schedules still writes.
class LeaseLedgerEmpty extends LeaseLedgerState {
  const LeaseLedgerEmpty();
}

/// The ledger is loaded and holds [timers] (macro 26-41) that a schedule cfg
/// write MUST merge or it will stub-clobber them (P0-3.2).
class LeaseLedgerReady extends LeaseLedgerState {
  const LeaseLedgerReady(this.timers);

  @override
  final List<Map<String, dynamic>> timers;
}

class CalendarEntryLease {
  /// CalendarEntry.dateKey — `'YYYY-MM-DD'`. Used as the registry key.
  final String dateKey;

  /// WLED timers.ins position (0–7).
  final int slotIndex;

  /// WLED preset ID holding the synthesized payload (26–41).
  final int presetId;

  /// Wall clock at lease creation.
  final DateTime leasedAt;

  /// Wall clock when the lease should be released (entry's offTime as
  /// a real DateTime, with overnight wrap if offTime < onTime).
  final DateTime expiresAt;

  /// Synthesized WLED state payload (matches what
  /// [WledRepository.savePreset] expects).
  final Map<String, dynamic> wledPayload;

  /// Carried for diagnostic UI (eviction sheet, debug overlay).
  final String patternName;

  /// WLED timer hour, 0-23 (or 24=sunrise, 25=sunset). Pre-computed at
  /// lease creation so the timer-array build doesn't need to re-look-up
  /// the source entry.
  final int wledHour;

  /// WLED timer minute, 0-59.
  final int wledMin;

  /// WLED dow bitmask for the lease's single date. See [wled_dow.dart]
  /// for the canonical Mon=bit 0..Sun=bit 6 convention (Item #72).
  final int dowMask;

  const CalendarEntryLease({
    required this.dateKey,
    required this.slotIndex,
    required this.presetId,
    required this.leasedAt,
    required this.expiresAt,
    required this.wledPayload,
    required this.patternName,
    required this.wledHour,
    required this.wledMin,
    required this.dowMask,
  });

  CalendarEntryLease copyWith({
    int? slotIndex,
    int? presetId,
    DateTime? leasedAt,
    DateTime? expiresAt,
    Map<String, dynamic>? wledPayload,
    String? patternName,
    int? wledHour,
    int? wledMin,
    int? dowMask,
  }) =>
      CalendarEntryLease(
        dateKey: dateKey,
        slotIndex: slotIndex ?? this.slotIndex,
        presetId: presetId ?? this.presetId,
        leasedAt: leasedAt ?? this.leasedAt,
        expiresAt: expiresAt ?? this.expiresAt,
        wledPayload: wledPayload ?? this.wledPayload,
        patternName: patternName ?? this.patternName,
        wledHour: wledHour ?? this.wledHour,
        wledMin: wledMin ?? this.wledMin,
        dowMask: dowMask ?? this.dowMask,
      );

  Map<String, dynamic> toJson() => {
        'dateKey': dateKey,
        'slotIndex': slotIndex,
        'presetId': presetId,
        'leasedAt': leasedAt.toIso8601String(),
        'expiresAt': expiresAt.toIso8601String(),
        'wledPayload': wledPayload,
        'patternName': patternName,
        'wledHour': wledHour,
        'wledMin': wledMin,
        'dowMask': dowMask,
      };

  static CalendarEntryLease? fromJson(Map<String, dynamic> json) {
    try {
      return CalendarEntryLease(
        dateKey: json['dateKey'] as String,
        slotIndex: (json['slotIndex'] as num).toInt(),
        presetId: (json['presetId'] as num).toInt(),
        leasedAt: DateTime.parse(json['leasedAt'] as String),
        expiresAt: DateTime.parse(json['expiresAt'] as String),
        wledPayload: Map<String, dynamic>.from(
          json['wledPayload'] as Map,
        ),
        patternName: json['patternName'] as String,
        wledHour: (json['wledHour'] as num).toInt(),
        wledMin: (json['wledMin'] as num).toInt(),
        dowMask: (json['dowMask'] as num).toInt(),
      );
    } catch (e) {
      debugPrint('$_kLogPrefix fromJson rejected record: $e');
      return null;
    }
  }
}

class LeaseResult {
  final LeaseOutcome outcome;
  final CalendarEntryLease? lease;
  final String? errorMessage;

  const LeaseResult({
    required this.outcome,
    this.lease,
    this.errorMessage,
  });

  factory LeaseResult.outsideWindow() =>
      const LeaseResult(outcome: LeaseOutcome.outsideWindow);
  factory LeaseResult.leased(CalendarEntryLease lease) =>
      LeaseResult(outcome: LeaseOutcome.leased, lease: lease);
  factory LeaseResult.updated(CalendarEntryLease lease) =>
      LeaseResult(outcome: LeaseOutcome.updated, lease: lease);
  factory LeaseResult.noFreeSlots() =>
      const LeaseResult(outcome: LeaseOutcome.noFreeSlots);
  factory LeaseResult.invalidEntry(String reason) =>
      LeaseResult(outcome: LeaseOutcome.invalidEntry, errorMessage: reason);
  factory LeaseResult.alreadyExpired() =>
      const LeaseResult(outcome: LeaseOutcome.alreadyExpired);
  factory LeaseResult.writeFailed(String reason) =>
      LeaseResult(outcome: LeaseOutcome.writeFailed, errorMessage: reason);
}

// ─── Manager ─────────────────────────────────────────────────────────────────

class CalendarEntryLeaseManager {
  CalendarEntryLeaseManager(this._ref);

  final Ref _ref;

  /// In-memory registry. Keyed by CalendarEntry.dateKey.
  final Map<String, CalendarEntryLease> _activeLeases = {};

  /// Decision 8 — single manager-wide write lock prevents
  /// sweep-vs-create races. The 5-min sweep and the lease-on-create
  /// path both potentially mutate WLED's cfg.timers. Serializing
  /// them through this lock eliminates the brief window (~100 ms)
  /// where a re-enabled ScheduleItem and a new lease could both
  /// claim the same slot.
  ///
  /// WLED writes are infrequent enough that contention is a
  /// non-issue. Hand-rolled [AsyncLock] (commit 10345c1) used
  /// instead of the `synchronized` package to keep the dependency
  /// surface flat.
  final AsyncLock _wledWriteLock = AsyncLock();

  Future<void>? _initializeFuture;
  bool _initialized = false;

  /// Test hook — lets unit tests pin "now" without monkey-patching
  /// DateTime. Production always uses DateTime.now().
  @visibleForTesting
  DateTime Function() nowProvider = DateTime.now;

  /// Test seam over the hardened cfg write+verify. Production delegates to the
  /// shared [pushCfgWithVerify] (the SAME path schedule sync uses); tests
  /// override this to drive confirmed / mismatch / notConfirmed synchronously,
  /// without a live controller or the real-time stall poll.
  @visibleForTesting
  Future<CfgPushOutcome> Function(
    WledRepository repo,
    Map<String, dynamic> payload,
    List<Map<String, dynamic>> ins,
  ) cfgPushFn = (repo, payload, ins) =>
      pushCfgWithVerify(repo: repo, payload: payload, ins: ins);

  // ─── Public surface ──────────────────────────────────────────────

  /// Read-only view of active leases. UI consumers (eviction sheet,
  /// debug overlay) should treat this as a snapshot — call again to
  /// re-read.
  List<CalendarEntryLease> get activeLeases =>
      List.unmodifiable(_activeLeases.values);

  /// Compute when a lease for [entry] would expire (entry's offTime
  /// resolved to a real DateTime, with overnight wrap if offTime <
  /// onTime). Returns null when the entry's onTime/offTime are
  /// missing or unparseable. Used by the eviction picker to label
  /// the lease window.
  DateTime? computeLeaseExpiry(CalendarEntry entry) =>
      _computeExpiresAt(entry);

  /// Initialize on app start. Loads persisted leases, runs an initial
  /// sweep, scans current CalendarEntries for newly-imminent ones.
  ///
  /// Idempotent — repeated calls return the same Future. The provider
  /// fires this without awaiting; tests `await` it explicitly to make
  /// load timing deterministic.
  Future<void> initialize() {
    return _initializeFuture ??= _initializeImpl();
  }

  Future<void> _initializeImpl() async {
    debugPrint('$_kLogPrefix initialize START');
    try {
      await _loadFromPrefs();
    } catch (e) {
      debugPrint('$_kLogPrefix initialize: load failed — $e');
    }
    // Best-effort bootstrap of the feature-flag doc so the Firestore
    // console has something to edit on first install. Failure is
    // logged but never blocks initialize (e.g. offline at boot).
    try {
      await bootstrapCalendarLeaseFlagDoc();
    } catch (e) {
      debugPrint('$_kLogPrefix initialize: flag-doc bootstrap failed — $e');
    }
    _initialized = true;
    try {
      await sweepExpiredLeases();
    } catch (e) {
      debugPrint('$_kLogPrefix initialize: initial sweep failed — $e');
    }
    final initialLiveEnabledSnapshot = _readLiveWritesEnabled();
    debugPrint('$_kLogPrefix initialize END '
        '(loaded ${_activeLeases.length} leases, '
        'live writes initial snapshot = $initialLiveEnabledSnapshot — '
        'authoritative value will arrive via Firestore stream emission)');
  }

  /// Synchronous read of the feature flag. Defaults to false during
  /// the StreamProvider's loading window or any error — safe.
  bool _readLiveWritesEnabled() {
    try {
      return _ref.read(calendarLeaseLiveWritesEnabledSyncProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix _readLiveWritesEnabled threw — $e '
          '(defaulting to false)');
      return false;
    }
  }

  /// Tear down. Persists current state. Does NOT write to WLED.
  Future<void> dispose() async {
    try {
      await _saveToPrefs();
    } catch (e) {
      debugPrint('$_kLogPrefix dispose: persist failed — $e');
    }
  }

  /// Process a freshly-created or updated CalendarEntry. Idempotent
  /// against re-creation of the same dateKey — re-running on an
  /// already-leased entry updates the payload in place.
  Future<LeaseResult> handleEntryCreated(CalendarEntry entry) async {
    debugPrint(
        '$_kLogPrefix handleEntryCreated CALLED for ${entry.dateKey}');
    final result = await _handleEntryCreatedImpl(entry);
    debugPrint('$_kLogPrefix handleEntryCreated OUTCOME ${result.outcome} '
        'for ${entry.dateKey}');
    return result;
  }

  Future<LeaseResult> _handleEntryCreatedImpl(CalendarEntry entry) async {
    // Holiday entries are bundled defaults; user/autopilot/auto can lease.
    if (entry.type == CalendarEntryType.holiday) {
      return LeaseResult.outsideWindow();
    }

    if (entry.onTime == null ||
        entry.onTime!.isEmpty ||
        entry.offTime == null ||
        entry.offTime!.isEmpty) {
      return LeaseResult.invalidEntry('onTime or offTime missing');
    }

    final expiresAt = _computeExpiresAt(entry);
    final onAt = _computeOnAt(entry);
    if (expiresAt == null || onAt == null) {
      return LeaseResult.invalidEntry('onTime or offTime unparseable');
    }

    final now = nowProvider();
    if (!expiresAt.isAfter(now)) {
      return LeaseResult.alreadyExpired();
    }

    if (!_isWithinLeaseWindow(entry)) {
      return LeaseResult.outsideWindow();
    }

    final payload = _synthesizeWledPayload(entry);
    final onHm = _timeStringToWledHourMin(entry.onTime);
    if (onHm == null) {
      // Already validated above via _computeOnAt, but defensive null
      // guard satisfies the analyzer.
      return LeaseResult.invalidEntry('onTime unparseable');
    }
    final dowMask = _singleDateDowMask(entry.dateKey);

    // Update path — existing lease for this dateKey. Keep its slot +
    // preset (avoids slot churn on payload edits) and refresh fields.
    final existing = _activeLeases[entry.dateKey];
    if (existing != null) {
      final updated = existing.copyWith(
        expiresAt: expiresAt,
        wledPayload: payload,
        patternName: entry.patternName,
        wledHour: onHm.hour,
        wledMin: onHm.min,
        dowMask: dowMask,
      );
      _activeLeases[entry.dateKey] = updated;
      await _saveToPrefs();
      final attempt = await _writeLeaseToWled(updated);
      if (attempt == _WriteAttempt.savePresetFailed) {
        // Rollback — preset write failed, lease never reached controller. The
        // prior preset+timer are untouched on the device, so restore the prior
        // lease record: the manager's view stays accurate.
        _activeLeases[entry.dateKey] = existing;
        await _saveToPrefs();
        debugPrint('$_kLogPrefix update rolled back for ${entry.dateKey} '
            '— savePreset failed');
        return LeaseResult.writeFailed(
            'savePreset failed for preset ${updated.presetId}');
      }
      if (attempt == _WriteAttempt.cfgWriteFailed) {
        // The updated preset was saved but its timer write was NOT verified.
        // Don't restore `existing` (its timer may also be gone) and don't keep
        // `updated` (unverified) — DROP the record so the next sweep re-promotes
        // and re-arms this dateKey cleanly. Registry must reflect verified-armed
        // only.
        _activeLeases.remove(entry.dateKey);
        await _saveToPrefs();
        debugPrint('$_kLogPrefix update DROPPED for ${entry.dateKey} — cfg '
            'write not verified; will re-arm on next sweep');
        return LeaseResult.writeFailed(
            'cfg write not verified for slot ${updated.slotIndex}');
      }
      debugPrint('$_kLogPrefix updated ${entry.dateKey} '
          '(slot=${updated.slotIndex}, preset=${updated.presetId})');
      return LeaseResult.updated(updated);
    }

    final slotIndex = _allocateFreeSlotIndex();
    if (slotIndex == null) {
      return LeaseResult.noFreeSlots();
    }

    final presetId = _allocatePresetId(entry.dateKey);
    if (presetId < 0) {
      // Defensive — slot was free but no preset was: registry inconsistency.
      return LeaseResult.noFreeSlots();
    }

    final lease = CalendarEntryLease(
      dateKey: entry.dateKey,
      slotIndex: slotIndex,
      presetId: presetId,
      leasedAt: now,
      expiresAt: expiresAt,
      wledPayload: payload,
      patternName: entry.patternName,
      wledHour: onHm.hour,
      wledMin: onHm.min,
      dowMask: dowMask,
    );
    _activeLeases[entry.dateKey] = lease;
    await _saveToPrefs();
    final attempt = await _writeLeaseToWled(lease);
    if (attempt == _WriteAttempt.savePresetFailed ||
        attempt == _WriteAttempt.cfgWriteFailed) {
      // savePreset failed (nothing on device) OR the timer write was not
      // verified (preset orphaned, timer absent). Either way the lease is NOT
      // armed — remove it so the registry never claims armed, and the next
      // sweep re-promotes and re-arms it. Promotion skips registered dateKeys
      // (:759), so a KEPT record would never re-arm — the days-of-presets /
      // zero-timers silent-failure bug this hardening exists to kill.
      _activeLeases.remove(entry.dateKey);
      await _saveToPrefs();
      final reason = attempt == _WriteAttempt.savePresetFailed
          ? 'savePreset failed for preset $presetId'
          : 'cfg write not verified for slot $slotIndex';
      debugPrint('$_kLogPrefix lease rolled back for ${entry.dateKey} — $reason');
      return LeaseResult.writeFailed(reason);
    }
    // success | noRepo | cfgUnsupported | flagOff — keep the lease in registry.
    // The last three are DEFERRED (not failures): no controller traffic
    // happened, so the record is retained for a later on-LAN/flag-on retry.
    // (cfgWriteFailed is handled above — it rolls back.)
    debugPrint('$_kLogPrefix leased ${entry.dateKey} '
        '(slot=$slotIndex, preset=$presetId, '
        'expires=${expiresAt.toIso8601String()})');
    return LeaseResult.leased(lease);
  }

  /// Apply soft eviction by setting `disabledUntil` on the chosen
  /// ScheduleItem, then retry lease creation for the pending entry.
  ///
  /// Sequence:
  ///   1. Update the ScheduleItem via the canonical notifier (which
  ///      fires the debounced WLED sync — the freed slot reaches the
  ///      controller without explicit coordination because
  ///      [ScheduleSyncService.buildCfgPayload] honors
  ///      `isCurrentlyEvicted`).
  ///   2. Re-call [handleEntryCreated] for the entry. The slot-demand
  ///      provider now reports one fewer slot, so allocation succeeds.
  ///
  /// Idempotent — calling twice with the same arguments produces the
  /// same end state. If [itemToEvict.disabledUntil] is already ≥
  /// [evictUntil], the update is a no-op shape (the notifier still
  /// records the write, but the device-side state is unchanged).
  ///
  /// If the eviction succeeds but the re-attempted lease still fails
  /// for an unrelated reason (e.g. invalidEntry surfaced by re-read,
  /// preset pool exhausted), the eviction is NOT rolled back. The
  /// recurring schedule stays paused per the user's explicit pick;
  /// the failure outcome is returned so the caller can surface a
  /// banner. A rolled-back eviction would silently re-enable a
  /// schedule the user just told us to pause — strictly worse UX.
  Future<LeaseResult> applyEvictionAndLease({
    required CalendarEntry entry,
    required ScheduleItem itemToEvict,
    required DateTime evictUntil,
  }) async {
    final ScheduleUpdaterFn updater;
    try {
      updater = _ref.read(calendarLeaseScheduleUpdaterProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix applyEvictionAndLease: '
          'updater lookup failed — $e');
      return LeaseResult.invalidEntry('schedule updater unavailable');
    }
    try {
      await updater(itemToEvict.copyWith(disabledUntil: evictUntil));
    } catch (e) {
      debugPrint(
          '$_kLogPrefix applyEvictionAndLease: schedule update failed — $e');
      return LeaseResult.invalidEntry('eviction write failed');
    }
    // Now retry the lease. The slot-demand provider re-reads
    // schedulesProvider through Riverpod reactivity, so the freed
    // slot is visible to _allocateFreeSlotIndex.
    return handleEntryCreated(entry);
  }

  /// Release any active lease for [dateKey].
  Future<void> handleEntryDeleted(String dateKey) async {
    final lease = _activeLeases.remove(dateKey);
    if (lease == null) return;
    await _saveToPrefs();
    await _writeZeroedSlot(lease.slotIndex);
    debugPrint('$_kLogPrefix released $dateKey (slot=${lease.slotIndex})');
  }

  /// Periodic sweep. Removes expired leases, promotes newly-imminent
  /// entries. Safe to call concurrently with [handleEntryCreated] —
  /// registry mutations are synchronous and ordered.
  Future<void> sweepExpiredLeases() async {
    final now = nowProvider();
    debugPrint(
        '$_kLogPrefix sweep START (registry size = ${_activeLeases.length})');
    final expiredKeys = <String>[];
    for (final entry in _activeLeases.entries) {
      if (!entry.value.expiresAt.isAfter(now)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final lease = _activeLeases.remove(key);
      if (lease != null) {
        // `_writeZeroedSlot` checks the feature flag internally and
        // short-circuits when off. The registry mutation above runs
        // regardless so the manager's view stays consistent across
        // app sessions even when live writes are disabled.
        await _writeZeroedSlot(lease.slotIndex);
        debugPrint('$_kLogPrefix swept-expired $key (slot=${lease.slotIndex})');
      }
    }

    if (expiredKeys.isNotEmpty) {
      await _saveToPrefs();
    }

    // Clear `disabledUntil` on any ScheduleItem whose soft-eviction
    // expiry just passed. Triggers a re-sync so the freed item
    // reaches the controller without waiting for the next user-driven
    // mutation. Performs the update via the testable updater fn so
    // tests can verify the call without constructing the real
    // SchedulesNotifier.
    int evictionsCleared = 0;
    try {
      final schedules = _ref.read(calendarLeaseSchedulesProvider);
      final updater = _ref.read(calendarLeaseScheduleUpdaterProvider);
      for (final item in schedules) {
        final until = item.disabledUntil;
        if (until == null) continue;
        if (until.isAfter(now)) continue;
        // Expired — clear the field so it doesn't accumulate stale
        // historical values.
        try {
          await updater(item.copyWith(clearDisabledUntil: true));
          evictionsCleared++;
          debugPrint(
              '$_kLogPrefix swept-reenabled ${item.id} (was disabledUntil=$until)');
        } catch (e) {
          debugPrint(
              '$_kLogPrefix sweep: re-enable failed for ${item.id} — $e');
        }
      }
    } catch (e) {
      debugPrint('$_kLogPrefix sweep: re-enable scan failed — $e');
    }

    // If any item was re-enabled, force an immediate WLED sync so the
    // controller picks up the restored timer entry. Updates above
    // already trigger the debounced auto-sync, but the sync-now call
    // collapses the 800 ms wait to zero, important for users editing
    // schedules on the My Schedule page during the sweep tick.
    if (evictionsCleared > 0) {
      try {
        final trigger = _ref.read(calendarLeaseScheduleSyncTriggerProvider);
        await trigger();
      } catch (e) {
        debugPrint('$_kLogPrefix sweep: sync trigger failed — $e');
      }
    }

    // Promote entries that have entered the window since last sweep.
    // Read via the testable provider so unit tests can override.
    List<CalendarEntry> allEntries;
    try {
      allEntries = _ref.read(calendarLeaseEntriesProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix sweep: entries lookup failed — $e');
      debugPrint('$_kLogPrefix sweep END (expired=${expiredKeys.length}, '
          'promoted=0, evictions cleared=$evictionsCleared)');
      return;
    }

    int promoted = 0;
    for (final entry in allEntries) {
      if (_activeLeases.containsKey(entry.dateKey)) continue;
      if (entry.type == CalendarEntryType.holiday) continue;
      if (!_isWithinLeaseWindow(entry)) continue;
      // Best-effort promotion — failure surfaces in debug logs only;
      // the sweep itself must not throw.
      try {
        final r = await handleEntryCreated(entry);
        if (r.outcome == LeaseOutcome.leased ||
            r.outcome == LeaseOutcome.updated) {
          promoted++;
        }
      } catch (e) {
        debugPrint(
            '$_kLogPrefix sweep: promotion failed for ${entry.dateKey} — $e');
      }
    }
    debugPrint('$_kLogPrefix sweep END (expired=${expiredKeys.length}, '
        'promoted=$promoted, evictions cleared=$evictionsCleared)');
  }

  // ─── Window detection ───────────────────────────────────────────

  bool _isWithinLeaseWindow(CalendarEntry entry) {
    final expiresAt = _computeExpiresAt(entry);
    final onAt = _computeOnAt(entry);
    if (expiresAt == null || onAt == null) return false;

    final now = nowProvider();
    if (!expiresAt.isAfter(now)) return false; // already over

    final ahead = now.add(kLeaseWindow);
    return onAt.isBefore(ahead);
  }

  /// Compute the moment the lease should expire.
  ///
  /// Sentinel times (Sunrise/Sunset) use rough approximations
  /// (sunrise → 06:00, sunset → 18:00) for window math. The actual
  /// fire time on WLED is firmware-driven, so the approximation only
  /// affects when WE consider the lease expired — being conservatively
  /// late releasing a slot is harmless; being early would clear an
  /// active timer.
  DateTime? _computeExpiresAt(CalendarEntry entry) {
    final dt = DateTime.tryParse(entry.dateKey);
    if (dt == null) return null;
    final onHm = _timeStringToWledHourMin(entry.onTime);
    final offHm = _timeStringToWledHourMin(entry.offTime);
    if (onHm == null || offHm == null) return null;

    final onAt = _hmToDateTime(dt, onHm);
    var offAt = _hmToDateTime(dt, offHm);
    if (!offAt.isAfter(onAt)) {
      offAt = offAt.add(const Duration(days: 1));
    }
    return offAt;
  }

  DateTime? _computeOnAt(CalendarEntry entry) {
    final dt = DateTime.tryParse(entry.dateKey);
    if (dt == null) return null;
    final onHm = _timeStringToWledHourMin(entry.onTime);
    if (onHm == null) return null;
    return _hmToDateTime(dt, onHm);
  }

  DateTime _hmToDateTime(DateTime date, ({int hour, int min}) hm) {
    // Sentinel hours → reasonable approximations for window math.
    final h = hm.hour == 24 ? 6 : (hm.hour == 25 ? 18 : hm.hour);
    return DateTime(date.year, date.month, date.day, h, hm.min);
  }

  // ─── Slot + preset allocation ───────────────────────────────────

  /// Allocate the next free timer-slot index in [0, 8). Returns null
  /// when ScheduleItem demand + existing leases fill all 8 slots.
  int? _allocateFreeSlotIndex() {
    int scheduleDemand;
    try {
      scheduleDemand = _ref.read(calendarLeaseScheduleSlotDemandProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix slot-demand lookup failed: $e');
      scheduleDemand = 0;
    }
    final occupiedByLeases = <int>{
      for (final l in _activeLeases.values) l.slotIndex,
    };
    for (int i = scheduleDemand; i < kWledMaxTimerSlots; i++) {
      if (!occupiedByLeases.contains(i)) return i;
    }
    return null;
  }

  /// Allocate a preset ID in [26, 41]. dateKey-hash modulo with linear
  /// probe on collision. Returns -1 only when all 16 are taken — a
  /// state which the 48 h lifetime + 16-day-apart-collision math makes
  /// effectively impossible in production. Test 'preset ID allocation'
  /// asserts a graceful failure (no infinite loop) for that edge.
  int _allocatePresetId(String dateKey) {
    final taken = <int>{
      for (final l in _activeLeases.values)
        if (l.dateKey != dateKey) l.presetId,
    };
    final start = dateKey.hashCode.abs() % _kLeasePresetCount;
    for (int offset = 0; offset < _kLeasePresetCount; offset++) {
      final candidate =
          kFirstLeasePresetId + ((start + offset) % _kLeasePresetCount);
      if (!taken.contains(candidate)) return candidate;
    }
    return -1;
  }

  // ─── Payload synthesis ──────────────────────────────────────────

  /// PATH A: build the WLED state inline from CalendarEntry's flat
  /// fields. Mirrors [_writeAsScheduleItem] in calendar_providers.dart
  /// (RecurringIntent → ScheduleItem path) so the on-device behavior
  /// of a date-specific override matches its recurring sibling.
  ///
  /// Limitations: no effect-name lookup against device presets (would
  /// need fetchPresetNames + a known-pattern table). Named patterns
  /// render as solid color + brightness; pattern motion is forfeited
  /// in exchange for shipping Workstream B without Item #58.
  Map<String, dynamic> _synthesizeWledPayload(CalendarEntry entry) {
    final isOff = entry.patternName.toLowerCase() == 'off' ||
        (entry.color == null && entry.brightness == 0);
    if (isOff) {
      return <String, dynamic>{
        'on': false,
        'bri': 0,
        // Sibling instance of the missing-ib defect: without ib, psave
        // stores segments only, so loading this off-lease from a master-on
        // strip would NOT kill master power. ib persists root on:false.
        // Mirrors the schedule OFF preset (schedule_sync.dart).
        'ib': true,
      };
    }

    final color = entry.color ?? const Color(0xFFFFFFFF);
    // Mirror calendar_providers.dart:275-277 — new normalized Color API.
    final r = (color.r * 255).round();
    final g = (color.g * 255).round();
    final b = (color.b * 255).round();
    final colRgbw = rgbToRgbw(r, g, b, forceZeroWhite: true);
    final bri = (entry.brightness.clamp(0, 100) * 255 / 100).round();

    return <String, dynamic>{
      'on': true,
      'bri': bri,
      // ib makes WLED persist the root master on/bri into the psaved preset
      // (not just segments), so when the lease timer loads this macro from a
      // master-off strip the master powers ON. Without ib the preset is
      // segments-only and fires DARK — bench-proven on-device (preset 29 had
      // only ['mainseg','seg','n']). Mirrors the schedule pattern-preset ib
      // post-9158c00 (schedule_sync.dart).
      'ib': true,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'col': [colRgbw],
        },
      ],
    };
  }

  // ─── Time parsing ───────────────────────────────────────────────

  /// Parse a CalendarEntry time string to WLED's (hour, min) tuple.
  /// Accepts `'HH:MM'` (24-hour) or case-insensitive `'Sunrise'` /
  /// `'Sunset'` (mapped to hour 24 / 25 per WLED convention).
  ///
  /// Returns null for malformed input.
  @visibleForTesting
  ({int hour, int min})? timeStringToWledHourMinForTest(String? time) =>
      _timeStringToWledHourMin(time);

  ({int hour, int min})? _timeStringToWledHourMin(String? time) {
    if (time == null || time.isEmpty) return null;
    final lower = time.trim().toLowerCase();
    if (lower == 'sunrise') return (hour: 24, min: 0);
    if (lower == 'sunset') return (hour: 25, min: 0);
    final m = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(time.trim());
    if (m == null) return null;
    final h = int.tryParse(m.group(1)!);
    final mm = int.tryParse(m.group(2)!);
    if (h == null || mm == null) return null;
    if (h < 0 || h > 23) return null;
    if (mm < 0 || mm > 59) return null;
    return (hour: h, min: mm);
  }

  // ─── Single-date dow ────────────────────────────────────────────

  /// Compute the WLED dow bitmask for a single calendar date.
  /// Delegates to the centralized [wledDowMaskForWeekday] helper which
  /// encodes the correct Mon=bit 0 convention. Returns 0 when dateKey
  /// doesn't parse — caller must validate dateKey separately.
  ///
  /// Fixed 2026-05-19 (Item #72) — previously assumed Sun=bit 0 which
  /// caused every non-Daily timer to fire one weekday late on the
  /// controller.
  @visibleForTesting
  int singleDateDowMaskForTest(String dateKey) =>
      _singleDateDowMask(dateKey);

  int _singleDateDowMask(String dateKey) {
    final dt = DateTime.tryParse(dateKey);
    if (dt == null) return 0;
    return wledDowMaskForWeekday(dt.weekday);
  }

  // ─── WLED writes ────────────────────────────────────────────────

  /// Diagnostic readback of a single lease's timer slot, logged on BOTH the
  /// success and failure paths so the next bench run tells us definitively
  /// whether the timer landed. Reads /json/cfg once and reports the entry whose
  /// macro == the lease preset id (en/hour/min/dow), or ABSENT. WledService
  /// only — the relay can't read cfg. Best-effort; never throws.
  Future<void> _logLeaseReadback(
      WledRepository repo, CalendarEntryLease lease) async {
    if (repo is! WledService) return;
    try {
      final actual = await repo.fetchTimerInstances();
      Map<String, dynamic>? mine;
      if (actual != null) {
        for (final t in actual) {
          if (t['macro'] is num &&
              (t['macro'] as num).toInt() == lease.presetId) {
            mine = t;
            break;
          }
        }
      }
      if (mine == null) {
        debugPrint('$_kLogPrefix READBACK ${lease.dateKey} '
            'slot=${lease.slotIndex} macro=${lease.presetId} → ABSENT '
            '(timer did not land)');
      } else {
        debugPrint('$_kLogPrefix READBACK ${lease.dateKey} '
            'slot=${lease.slotIndex} macro=${lease.presetId} → '
            'en=${mine['en']} hour=${mine['hour']} min=${mine['min']} '
            'dow=${mine['dow']}');
      }
    } catch (e) {
      debugPrint('$_kLogPrefix READBACK ${lease.dateKey} — fetch failed: $e');
    }
  }

  /// Push a single lease to WLED: save its preset, then write the
  /// merged cfg.timers payload (ScheduleItems + leases) with the
  /// new entry's slot in place.
  ///
  /// Gated by the [calendarLeaseLiveWritesEnabledProvider] feature
  /// flag — when off, returns [_WriteAttempt.flagOff] without
  /// touching the controller. Serialized through [_wledWriteLock]
  /// against [_writeZeroedSlot] and [sweepExpiredLeases].
  Future<_WriteAttempt> _writeLeaseToWled(CalendarEntryLease lease) async {
    final liveEnabled = _readLiveWritesEnabled();
    if (!liveEnabled) {
      debugPrint(
        '$_kLogPrefix live writes DISABLED via feature flag — would '
        'write lease ${lease.dateKey} (slot=${lease.slotIndex}, '
        'preset=${lease.presetId}) but skipping actual /json/cfg + '
        '/json/state writes',
      );
      return _WriteAttempt.flagOff;
    }
    return _wledWriteLock.synchronized(() async {
      final repo = _readRepo();
      if (repo == null) {
        debugPrint(
          '$_kLogPrefix _writeLeaseToWled: no repo — lease ${lease.dateKey} '
          'registered but device not updated. Next sweep retries.',
        );
        return _WriteAttempt.noRepo;
      }
      // Arming needs /json/cfg, which the bridge cannot deliver. Check before
      // savePreset (which DOES work off-LAN via /json/state) so we don't strand
      // an orphaned preset on the controller for a timer we can't write.
      if (!repoCanWriteCfg(repo)) {
        debugPrint(
          '$_kLogPrefix off-LAN — lease ${lease.dateKey} not armed (bridge '
          'cannot write /json/cfg). Lease kept; next on-LAN sweep arms it.',
        );
        return _WriteAttempt.cfgUnsupported;
      }
      try {
        final presetOk = await repo.savePreset(
          presetId: lease.presetId,
          state: lease.wledPayload,
          presetName: 'Lease ${lease.dateKey}',
        );
        if (!presetOk) {
          debugPrint(
            '$_kLogPrefix savePreset failed for lease ${lease.dateKey} '
            'preset=${lease.presetId} — aborting timer write',
          );
          return _WriteAttempt.savePresetFailed;
        }
        // Route the timer write through the SAME hardened path the schedule
        // sync uses (readback-verified, stall-patient) instead of the old
        // fire-and-forget applyConfig whose dropped return value made a failed
        // or 2xx-but-stalled write indistinguishable from success — the silent
        // failure behind days of lease presets with ZERO matching timers.
        final mergedPayload = _buildMergedCfgPayload();
        final mergedIns = ((mergedPayload['timers'] as Map)['ins'] as List)
            .cast<Map<String, dynamic>>();
        final outcome = await cfgPushFn(repo, mergedPayload, mergedIns);
        // Diagnostic: dump the lease's own timer slot exactly as the controller
        // stored it (or ABSENT) on BOTH outcomes, so the next bench run tells us
        // definitively whether the timer landed.
        await _logLeaseReadback(repo, lease);
        if (outcome != CfgPushOutcome.confirmed) {
          debugPrint(
            '$_kLogPrefix cfg write NOT CONFIRMED ($outcome) for lease '
            '${lease.dateKey} (slot=${lease.slotIndex}, preset=${lease.presetId}) '
            '— timer not verified on controller; rolling back registration so '
            'the next sweep re-arms it (registry must not claim armed).',
          );
          return _WriteAttempt.cfgWriteFailed;
        }
        debugPrint(
          '$_kLogPrefix WROTE+VERIFIED lease ${lease.dateKey} on controller '
          '(slot=${lease.slotIndex}, preset=${lease.presetId})',
        );
        return _WriteAttempt.success;
      } catch (e) {
        debugPrint('$_kLogPrefix _writeLeaseToWled exception: $e');
        // Treat as savePreset failure for rollback purposes — we
        // don't know which stage failed, but the conservative choice
        // is to assume the controller state is inconsistent and
        // roll back the in-memory record. The next sweep + retry
        // will re-attempt.
        return _WriteAttempt.savePresetFailed;
      }
    });
  }

  /// Defensive zero-write on lease expiry / deletion. Re-sends the
  /// merged timers payload WITHOUT the removed lease so any stale
  /// entry the firmware retained gets cleared.
  ///
  /// Gated by the [calendarLeaseLiveWritesEnabledProvider] feature
  /// flag — when off, returns true without touching the controller.
  /// Serialized through [_wledWriteLock].
  Future<bool> _writeZeroedSlot(int slotIndex) async {
    final liveEnabled = _readLiveWritesEnabled();
    if (!liveEnabled) {
      debugPrint(
        '$_kLogPrefix live writes DISABLED via feature flag — would '
        'zero-write slot $slotIndex but skipping actual /json/cfg',
      );
      return true;
    }
    return _wledWriteLock.synchronized(() async {
      final repo = _readRepo();
      if (repo == null) {
        debugPrint(
          '$_kLogPrefix _writeZeroedSlot: no repo — slot $slotIndex '
          'not cleared. Next sweep retries.',
        );
        return false;
      }
      if (!repoCanWriteCfg(repo)) {
        debugPrint(
          '$_kLogPrefix _writeZeroedSlot: off-LAN — slot $slotIndex not '
          'cleared (bridge cannot write /json/cfg). Next on-LAN sweep clears it.',
        );
        return false;
      }
      try {
        final ok = await repo.applyConfig(_buildMergedCfgPayload());
        if (!ok) {
          debugPrint('$_kLogPrefix _writeZeroedSlot: applyConfig failed '
              'for slot $slotIndex');
        }
        return ok;
      } catch (e) {
        debugPrint('$_kLogPrefix _writeZeroedSlot exception: $e');
        return false;
      }
    });
  }

  /// Build a /json/cfg payload from the active lease registry.
  ///
  /// Lease records carry hour/min/dowMask directly so this is purely a
  /// registry transform — no upstream provider read, no missing-entry
  /// race.
  ///
  /// IMPORTANT: this returns ONLY the lease-derived timers. Use
  /// [_buildMergedCfgPayload] for the full payload that includes
  /// ScheduleItem-derived timers — that's what's pushed to the
  /// controller in production.
  Map<String, dynamic> _buildLeaseTimersPayload() {
    final List<Map<String, dynamic>> ins = [];
    for (final lease in _activeLeases.values) {
      // Defense in depth: a dowMask of 0 (unparseable dateKey) would arm a
      // timer that never fires. Skip it — never write a dead dow:0 lease timer.
      if (lease.dowMask == 0) {
        debugPrint('$_kLogPrefix skipped dow:0 lease ${lease.dateKey} '
            '(would never fire)');
        continue;
      }
      ins.add({
        // WLED reads timer `en` TYPE-STRICT as an int — a JSON bool is
        // silently stored as 0 (disabled), so a bool-`en` lease timer arms
        // but never fires. Mirror the proven schedule path
        // (schedule_sync.dart clock timer `'en': 1`). Curl-proven in the
        // en saga (727ef0b); this lease writer predated that scrutiny.
        'en': 1,
        'hour': lease.wledHour,
        'min': lease.wledMin,
        'macro': lease.presetId,
        'dow': lease.dowMask,
      });
    }
    return {
      'timers': {
        'ins': ins,
      },
    };
  }

  /// Public view of the active lease timers (macro 26-41), for the schedule sync
  /// to MERGE so a schedule cfg write preserves leases instead of stub-clobbering
  /// them (P0-3.2). Reuses the SAME [_buildLeaseTimersPayload] the lease
  /// manager's own merged write uses — single source of truth, no second merge
  /// implementation.
  ///
  /// P0-9 (part a): returns a TRI-STATE, not a bare list. The bare list conflated
  /// "this account has no leases" (merging nothing is correct) with "the ledger
  /// hasn't loaded yet" (merging nothing DESTROYS live automation) — both were
  /// `[]`. [initialize] is fire-and-forget from
  /// [calendarEntryLeaseManagerProvider], so a schedule sync can and does race
  /// the prefs load; the merged cfg write then omits every live lease and the
  /// controller's timer table is overwritten without them. `_initialized` already
  /// tracked exactly this and was read only by a `@visibleForTesting` getter.
  ///
  /// Callers MUST switch exhaustively — that is the point of the sealed type. A
  /// [LeaseLedgerLoading] means "unknown"; the only safe response is to not
  /// write cfg at all.
  LeaseLedgerState activeLeaseTimers() {
    if (!_initialized) return const LeaseLedgerLoading();
    final ins = ((_buildLeaseTimersPayload()['timers'] as Map)['ins'] as List)
        .cast<Map<String, dynamic>>();
    return ins.isEmpty ? const LeaseLedgerEmpty() : LeaseLedgerReady(ins);
  }

  /// Build the full cfg.timers.ins payload merging:
  ///   1. ScheduleItem-driven timers (enabled, non-evicted) from
  ///      [ScheduleSyncService.buildCfgPayload]
  ///   2. Lease-driven timers from [_buildLeaseTimersPayload]
  ///
  /// Slot non-collision is guaranteed by [_allocateFreeSlotIndex]
  /// which counts ScheduleItem demand before allocating. This method
  /// just renders the merged view.
  ///
  /// WLED honors only the first 8 entries in `ins`. If schedule
  /// demand + lease count > 8 in production state drift (e.g., user
  /// added schedules after a lease was allocated), entries beyond
  /// the 8th silently fall off the controller — not handled here;
  /// the slot-allocation logic upstream prevents it under normal
  /// flows.
  Map<String, dynamic> _buildMergedCfgPayload() {
    List<ScheduleItem> schedules;
    try {
      schedules = _ref.read(calendarLeaseSchedulesProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix _buildMergedCfgPayload: schedules read '
          'failed — $e (falling back to lease-only payload)');
      final leaseOnly =
          (_buildLeaseTimersPayload()['timers'] as Map)['ins'] as List;
      return {
        'timers': {
          'ins': ScheduleSyncService.padTimersToMax(
              leaseOnly.cast<Map<String, dynamic>>()),
        },
      };
    }
    const scheduleSync = ScheduleSyncService();
    final schedulePayload = scheduleSync.buildCfgPayload(schedules);
    final schedTimers =
        (schedulePayload['timers'] as Map?)?['ins'] as List? ?? const [];
    final leasePayload = _buildLeaseTimersPayload();
    final leaseTimers =
        (leasePayload['timers'] as Map?)?['ins'] as List? ?? const [];
    // Pad the FINAL merged array to all 8 slots so a shrinking schedule/lease
    // set zeros the slots it vacated on the controller (slot reclaim — clears
    // accumulated dow:0 orphans). This is the only pad point for the lease
    // path; buildCfgPayload stays unpadded so the merge above is correct.
    return {
      'timers': {
        'ins': ScheduleSyncService.padTimersToMax(
            [...schedTimers, ...leaseTimers].cast<Map<String, dynamic>>()),
      },
    };
  }

  WledRepository? _readRepo() {
    try {
      return _ref.read(wledRepositoryProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix _readRepo failed: $e');
      return null;
    }
  }

  // ─── Persistence ────────────────────────────────────────────────

  Future<void> _loadFromPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kLeaseStorageKey);
      if (raw == null || raw.isEmpty) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) {
        debugPrint(
            '$_kLogPrefix _loadFromPrefs: unexpected shape ${decoded.runtimeType}');
        return;
      }
      for (final item in decoded) {
        if (item is! Map) continue;
        final lease = CalendarEntryLease.fromJson(
          Map<String, dynamic>.from(item),
        );
        if (lease != null) {
          _activeLeases[lease.dateKey] = lease;
        }
      }
      debugPrint(
          '$_kLogPrefix _loadFromPrefs: restored ${_activeLeases.length} leases');
    } catch (e) {
      debugPrint(
          '$_kLogPrefix _loadFromPrefs: parse failed, starting empty — $e');
    }
  }

  Future<void> _saveToPrefs() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final encoded = jsonEncode(
        _activeLeases.values.map((l) => l.toJson()).toList(),
      );
      await prefs.setString(_kLeaseStorageKey, encoded);
    } catch (e) {
      debugPrint('$_kLogPrefix _saveToPrefs failed: $e');
    }
  }

  // ─── Test surface ───────────────────────────────────────────────

  /// Test-only allocator surface. Production callers use
  /// [handleEntryCreated] which composes allocation + payload synthesis
  /// + WLED write.
  @visibleForTesting
  int? allocateFreeSlotIndexForTest() => _allocateFreeSlotIndex();

  @visibleForTesting
  int allocatePresetIdForTest(String dateKey) => _allocatePresetId(dateKey);

  @visibleForTesting
  Map<String, dynamic> synthesizeWledPayloadForTest(CalendarEntry entry) =>
      _synthesizeWledPayload(entry);

  @visibleForTesting
  bool isWithinLeaseWindowForTest(CalendarEntry entry) =>
      _isWithinLeaseWindow(entry);

  @visibleForTesting
  Map<String, dynamic> buildLeaseTimersPayloadForTest() =>
      _buildLeaseTimersPayload();

  /// Inject a lease directly into the registry (test-only). Bypasses
  /// allocation and WLED writes — used by persistence-roundtrip tests.
  @visibleForTesting
  void injectLeaseForTest(CalendarEntryLease lease) {
    _activeLeases[lease.dateKey] = lease;
  }

  @visibleForTesting
  bool get isInitializedForTest => _initialized;
}

// ─── Provider ────────────────────────────────────────────────────────────────

final calendarEntryLeaseManagerProvider =
    Provider<CalendarEntryLeaseManager>((ref) {
  final manager = CalendarEntryLeaseManager(ref);

  // Fire-and-forget. Repeated reads return the cached Future; tests
  // that need deterministic load order `await manager.initialize()`
  // explicitly.
  // ignore: unawaited_futures
  manager.initialize();

  final sweepTimer = Timer.periodic(
    _kSweepInterval,
    (_) => manager.sweepExpiredLeases(),
  );

  ref.onDispose(() {
    sweepTimer.cancel();
    // ignore: unawaited_futures
    manager.dispose();
  });

  return manager;
});

/// Active lease timers (macro 26-41) for the SCHEDULE sync to merge so a
/// schedule cfg write preserves them (P0-3.2 clobber fix). Flag-gated: resolves
/// [LeaseLedgerEmpty] when lease live-writes are OFF — the lease manager never
/// armed lease timers on the controller, so there is nothing to preserve, and
/// the manager is NOT instantiated (the short-circuit runs before reading it).
/// This keeps existing schedule-sync tests (flag defaults false) behaving
/// exactly as before: syncAll sees no lease timers and its path is unchanged.
///
/// P0-9 (part a): the flag is read from the STREAM provider, not from
/// [calendarLeaseLiveWritesEnabledSyncProvider], deliberately. That sync adapter
/// collapses `AsyncLoading` to `false` — correct for its own callers (never WRITE
/// when unsure) but wrong here, where `false` would mean "no leases to preserve"
/// and license the clobbering write. During the flag's loading window the lease
/// set is UNKNOWN, so this resolves [LeaseLedgerLoading] and the sync refuses.
/// Same defect as the ledger race, one level up.
///
/// A stream ERROR resolves loading-safe too. In practice the stream's own catch
/// yields `false` as DATA rather than surfacing an error, so that branch is
/// near-unreachable; it is written conservatively rather than left to chance.
final calendarLeaseActiveTimersProvider = Provider<LeaseLedgerState>((ref) {
  return ref.watch(calendarLeaseLiveWritesEnabledProvider).when(
        loading: () => const LeaseLedgerLoading(),
        error: (_, __) => const LeaseLedgerLoading(),
        data: (enabled) {
          if (!enabled) return const LeaseLedgerEmpty();
          return ref.watch(calendarEntryLeaseManagerProvider).activeLeaseTimers();
        },
      );
});

/// Internal result type from [CalendarEntryLeaseManager._writeLeaseToWled].
/// Differentiates rollback-required failures (savePreset, cfgWriteFailed) from
/// deferred skip paths (flagOff/noRepo/cfgUnsupported).
enum _WriteAttempt {
  /// savePreset + the VERIFIED cfg write both succeeded — lease landed on the
  /// controller (timer confirmed present + enabled via the hardened path).
  success,

  /// savePreset failed — preset never reached the controller. The
  /// caller MUST roll back the in-memory registry so it stays
  /// consistent with the device.
  savePresetFailed,

  /// savePreset succeeded but the cfg TIMER write was NOT verified on the
  /// controller (mismatch, or never confirmed within the hardened path's
  /// window). The preset is orphaned and the timer is absent, so the lease is
  /// NOT armed — the caller MUST roll back the registration so the entry is
  /// re-promoted and re-armed on the next sweep. A KEPT record would never
  /// re-arm (promotion skips registered dateKeys, :759) — that was the
  /// days-of-presets / zero-timers silent-failure bug. Replaces the old
  /// fire-and-forget `applyConfigFailed` that silently kept the lease.
  cfgWriteFailed,

  /// No WLED repository available (offline / no controller selected).
  /// Caller keeps the lease in registry — next sweep retries.
  noRepo,

  /// The connected transport cannot write /json/cfg at all — the user is
  /// off-LAN and arming goes through the bridge, which only relays live state.
  /// Detected BEFORE savePreset so nothing is orphaned on the controller.
  /// Not a failure and nothing to roll back: the lease stays in the registry
  /// and the next sweep arms it once the user is back on their home WiFi.
  cfgUnsupported,

  /// Feature flag is off — no controller traffic occurred. Caller
  /// keeps the lease in registry for when the flag flips.
  flagOff,
}

