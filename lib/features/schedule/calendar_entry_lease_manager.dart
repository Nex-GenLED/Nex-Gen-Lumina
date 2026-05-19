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
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/utils/async_lock.dart';
import 'package:shared_preferences/shared_preferences.dart';

// ─── Constants ────────────────────────────────────────────────────────────────

/// Total timer slots in WLED's `timers.ins` array.
const int kWledMaxTimerSlots = 8;

/// Preset ID range reserved for lease-owned presets. Picked so the
/// existing ScheduleItem range (10–25, see [ScheduleSyncService]) and
/// system presets (1, 2) are untouched. 16 lease slots × 48h lifetime
/// >> any realistic dateKey-modulo-16 collision frequency.
const int kFirstLeasePresetId = 26;
const int kLastLeasePresetId = 41;
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
    final liveEnabled = _readLiveWritesEnabled();
    debugPrint('$_kLogPrefix initialize END '
        '(loaded ${_activeLeases.length} leases, live writes = $liveEnabled)');
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
        // Rollback — preset write failed, lease never reached controller.
        // Restore the prior lease record so the manager's view of the
        // controller stays accurate.
        _activeLeases[entry.dateKey] = existing;
        await _saveToPrefs();
        debugPrint('$_kLogPrefix update rolled back for ${entry.dateKey} '
            '— savePreset failed');
        return LeaseResult.writeFailed(
            'savePreset failed for preset ${updated.presetId}');
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
    if (attempt == _WriteAttempt.savePresetFailed) {
      // Rollback — preset write failed before timer write was attempted.
      _activeLeases.remove(entry.dateKey);
      await _saveToPrefs();
      debugPrint('$_kLogPrefix lease rolled back for ${entry.dateKey} '
          '— savePreset failed');
      return LeaseResult.writeFailed(
          'savePreset failed for preset $presetId');
    }
    // success | applyConfigFailed | noRepo | flagOff — keep the lease
    // in registry. applyConfigFailed: orphan preset on controller; the
    // periodic sweep retries.
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
        final cfgOk = await repo.applyConfig(_buildMergedCfgPayload());
        if (!cfgOk) {
          debugPrint(
            '$_kLogPrefix applyConfig failed for lease ${lease.dateKey} '
            '— preset ${lease.presetId} still exists on controller but '
            'timer slot not set. Logged for cleanup sweep retry.',
          );
          return _WriteAttempt.applyConfigFailed;
        }
        debugPrint(
          '$_kLogPrefix WROTE lease ${lease.dateKey} to controller '
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
      ins.add({
        'en': true,
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
      return _buildLeaseTimersPayload();
    }
    const scheduleSync = ScheduleSyncService();
    final schedulePayload = scheduleSync.buildCfgPayload(schedules);
    final schedTimers =
        (schedulePayload['timers'] as Map?)?['ins'] as List? ?? const [];
    final leasePayload = _buildLeaseTimersPayload();
    final leaseTimers =
        (leasePayload['timers'] as Map?)?['ins'] as List? ?? const [];
    return {
      'timers': {
        'ins': [...schedTimers, ...leaseTimers],
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

/// Internal result type from [CalendarEntryLeaseManager._writeLeaseToWled].
/// Differentiates rollback-required failures (savePreset) from
/// orphan-preset failures (applyConfig) and skip paths
/// (flagOff/noRepo).
enum _WriteAttempt {
  /// savePreset + applyConfig both succeeded — lease landed on the
  /// controller; in-memory registry stays in place.
  success,

  /// savePreset failed — preset never reached the controller. The
  /// caller MUST roll back the in-memory registry so it stays
  /// consistent with the device.
  savePresetFailed,

  /// savePreset succeeded but applyConfig failed — preset is now
  /// orphaned on the controller (timer slot doesn't point to it).
  /// Caller should NOT roll back; the periodic sweep retries the
  /// timer write.
  applyConfigFailed,

  /// No WLED repository available (offline / no controller selected).
  /// Caller keeps the lease in registry — next sweep retries.
  noRepo,

  /// Feature flag is off — no controller traffic occurred. Caller
  /// keeps the lease in registry for when the flag flips.
  flagOff,
}

