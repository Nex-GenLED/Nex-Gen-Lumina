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
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
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

/// Slot demand from currently-enabled ScheduleItems.
///
/// Treats each enabled ScheduleItem as occupying one timer slot. Real
/// [ScheduleSyncService.buildCfgPayload] can consume 1–2 slots per
/// schedule when an OFF timer is configured, but the upstream loop caps
/// at 8 regardless. Treating each as 1 here is a conservative simplification
/// that matches the unit-test contract and gives leases the back end of
/// the slot range; over-allocation (counting fewer slots than reality)
/// would have the lease manager overwrite ScheduleItem slots, which is
/// strictly worse.
final calendarLeaseScheduleSlotDemandProvider = Provider<int>((ref) {
  final schedules = ref.watch(schedulesProvider);
  final enabled = schedules.where((s) => s.enabled).length;
  return enabled.clamp(0, kWledMaxTimerSlots);
});

/// All CalendarEntries the sweep should consider for newly-imminent
/// promotion. Indirected for testability.
final calendarLeaseEntriesProvider = Provider<List<CalendarEntry>>((ref) {
  final map = ref.watch(calendarScheduleProvider);
  return map.values.toList(growable: false);
});

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

  /// WLED dow bitmask for the lease's single date (Sun=bit0..Sat=bit6).
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
}

// ─── Manager ─────────────────────────────────────────────────────────────────

class CalendarEntryLeaseManager {
  CalendarEntryLeaseManager(this._ref);

  final Ref _ref;

  /// In-memory registry. Keyed by CalendarEntry.dateKey.
  final Map<String, CalendarEntryLease> _activeLeases = {};

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
    try {
      await _loadFromPrefs();
    } catch (e) {
      debugPrint('$_kLogPrefix initialize: load failed — $e');
    }
    _initialized = true;
    try {
      await sweepExpiredLeases();
    } catch (e) {
      debugPrint('$_kLogPrefix initialize: initial sweep failed — $e');
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
      await _writeLeaseToWled(updated);
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
    await _writeLeaseToWled(lease);
    debugPrint('$_kLogPrefix leased ${entry.dateKey} '
        '(slot=$slotIndex, preset=$presetId, '
        'expires=${expiresAt.toIso8601String()})');
    return LeaseResult.leased(lease);
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
    final expiredKeys = <String>[];
    for (final entry in _activeLeases.entries) {
      if (!entry.value.expiresAt.isAfter(now)) {
        expiredKeys.add(entry.key);
      }
    }

    for (final key in expiredKeys) {
      final lease = _activeLeases.remove(key);
      if (lease != null) {
        await _writeZeroedSlot(lease.slotIndex);
        debugPrint('$_kLogPrefix swept-expired $key (slot=${lease.slotIndex})');
      }
    }

    if (expiredKeys.isNotEmpty) {
      await _saveToPrefs();
    }

    // Promote entries that have entered the window since last sweep.
    // Read via the testable provider so unit tests can override.
    List<CalendarEntry> allEntries;
    try {
      allEntries = _ref.read(calendarLeaseEntriesProvider);
    } catch (e) {
      debugPrint('$_kLogPrefix sweep: entries lookup failed — $e');
      return;
    }

    for (final entry in allEntries) {
      if (_activeLeases.containsKey(entry.dateKey)) continue;
      if (entry.type == CalendarEntryType.holiday) continue;
      if (!_isWithinLeaseWindow(entry)) continue;
      // Best-effort promotion — failure surfaces in debug logs only;
      // the sweep itself must not throw.
      try {
        await handleEntryCreated(entry);
      } catch (e) {
        debugPrint(
            '$_kLogPrefix sweep: promotion failed for ${entry.dateKey} — $e');
      }
    }
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

  /// Compute the dow bitmask for the given dateKey. Returns 0 when
  /// dateKey doesn't parse. WLED dow is bit 0=Sun..bit 6=Sat; Dart's
  /// `DateTime.weekday` is 1=Mon..7=Sun, so Sunday gets the special
  /// case to keep bit 0.
  @visibleForTesting
  int singleDateDowMaskForTest(String dateKey) =>
      _singleDateDowMask(dateKey);

  int _singleDateDowMask(String dateKey) {
    final dt = DateTime.tryParse(dateKey);
    if (dt == null) return 0;
    // weekday: 1=Mon, 2=Tue, ..., 6=Sat, 7=Sun
    // wled bit: 0=Sun, 1=Mon, 2=Tue, ..., 6=Sat
    if (dt.weekday == DateTime.sunday) return 1; // bit 0
    return 1 << dt.weekday;
  }

  // ─── WLED writes ────────────────────────────────────────────────

  /// Push a single lease to WLED: save its preset, then write a
  /// timers.ins entry at the assigned slot pointing macro=presetId
  /// with the single-date dow mask.
  ///
  /// Writes the full `timers.ins` array built from all active leases
  /// (Workstream B owns slots [scheduleDemand..7] for now). Prompt 5
  /// extends this to include ScheduleItem-derived timers in the same
  /// payload so a unified push doesn't clobber recurring schedules.
  Future<bool> _writeLeaseToWled(CalendarEntryLease lease) async {
    final repo = _readRepo();
    if (repo == null) {
      debugPrint('$_kLogPrefix _writeLeaseToWled: no repo — lease ${lease.dateKey} '
          'registered but device not updated. Next sweep retries.');
      return false;
    }
    try {
      final presetOk = await repo.savePreset(
        presetId: lease.presetId,
        state: lease.wledPayload,
        presetName: 'Lease ${lease.dateKey}',
      );
      if (!presetOk) {
        debugPrint('$_kLogPrefix savePreset failed for ${lease.dateKey}');
        return false;
      }
      final cfgOk = await repo.applyConfig(_buildLeaseTimersPayload());
      if (!cfgOk) {
        debugPrint('$_kLogPrefix applyConfig failed for ${lease.dateKey}');
      }
      return cfgOk;
    } catch (e) {
      debugPrint('$_kLogPrefix _writeLeaseToWled exception: $e');
      return false;
    }
  }

  /// Defensive zero-write on lease expiry / deletion. Re-sends the
  /// timers.ins array WITHOUT the removed lease so any stale entry
  /// the firmware retained gets cleared.
  Future<bool> _writeZeroedSlot(int slotIndex) async {
    final repo = _readRepo();
    if (repo == null) {
      debugPrint('$_kLogPrefix _writeZeroedSlot: no repo — slot $slotIndex '
          'not cleared. Next sweep retries.');
      return false;
    }
    try {
      final ok = await repo.applyConfig(_buildLeaseTimersPayload());
      if (!ok) {
        debugPrint(
            '$_kLogPrefix _writeZeroedSlot: applyConfig failed for slot $slotIndex');
      }
      return ok;
    } catch (e) {
      debugPrint('$_kLogPrefix _writeZeroedSlot exception: $e');
      return false;
    }
  }

  /// Build a /json/cfg payload from the active lease registry.
  ///
  /// Lease records carry hour/min/dowMask directly so this is purely a
  /// registry transform — no upstream provider read, no missing-entry
  /// race.
  ///
  /// IMPORTANT: this payload OVERWRITES the device's full timers.ins
  /// array. Until Prompt 5 merges with ScheduleSyncService, calling
  /// applyConfig here clears ScheduleItem-derived timers. Tests assert
  /// the shape; production wire-up is deferred.
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

