// lib/features/schedule/calendar_entry_set.dart
//
// Scheduling V3 A1 — the structure that replaces `Map<String, CalendarEntry>`
// as the calendar's in-memory state.
//
// WHAT WAS WRONG. A date held exactly ONE dated entry, in state AND in
// Firestore: `next[e.dateKey] = e` (calendar_providers.dart:304) over a field
// that is itself a map keyed by date (user_service.dart:846). Two teams playing
// the same night, or a Game Day plus a holiday, could not coexist — the second
// write silently destroyed the first. audit/SCHEDULING_V3_AUDIT.md §2.2, and
// day_resolution.dart's own note: "a date still holds only ONE dated entry —
// A1 is unbuilt." This is A1.
//
// WHY IT STILL LOOKS LIKE A MAP. Roughly twenty call sites read this state, and
// most of them legitimately want one entry per date: conflict detection, the
// overload banner, the priority resolver, habit learning. Forcing all of them
// to reason about lists would be a large diff in subsystems this prompt is not
// changing. So the multi-entry truth is additive — [forDate] and [allEntries]
// are new, [primaries] is the old view, and callers opt in.
//
// PRIMARY = LAST WRITTEN, and that is not arbitrary: it reproduces exactly what
// `next[e.dateKey] = e` did (last writer wins) and it is what an old build sees
// after the storage change, because the primary is the entry that keeps the
// plain `YYYY-MM-DD` Firestore key. See `calendar_entry_storage.dart`.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';

/// Immutable multi-entry calendar state, grouped by `'YYYY-MM-DD'`.
///
/// Within a date, order is WRITE order — the last element is the primary. Entry
/// identity is `(dateKey, entryId)`; writing an entry whose `entryId` already
/// exists on that date REPLACES it in place rather than appending, which is
/// what keeps the weekly Game Day refresh idempotent.
class CalendarEntrySet {
  final Map<String, List<CalendarEntry>> _byDate;

  const CalendarEntrySet._(this._byDate);

  static const CalendarEntrySet empty =
      CalendarEntrySet._(<String, List<CalendarEntry>>{});

  /// Build from a flat list. Entries are grouped by their OWN `dateKey`, never
  /// by an external key — P1 confirmed all 159 production entries carry it.
  factory CalendarEntrySet.fromEntries(Iterable<CalendarEntry> entries) {
    final byDate = <String, List<CalendarEntry>>{};
    for (final e in entries) {
      final list = byDate.putIfAbsent(e.dateKey, () => <CalendarEntry>[]);
      final existing = list.indexWhere((x) => x.entryId == e.entryId);
      if (existing >= 0) {
        list[existing] = e;
      } else {
        list.add(e);
      }
    }
    return CalendarEntrySet._(byDate);
  }

  /// Adapter for the pre-V3 shape. Each value keeps its own `dateKey`.
  factory CalendarEntrySet.fromLegacyMap(Map<String, CalendarEntry> map) =>
      CalendarEntrySet.fromEntries(map.values);

  // ── Multi-entry reads (the new capability) ────────────────────────────────

  /// Every entry on [dateKey], in write order. Empty when the date is bare.
  ///
  /// This is what the timeline reads. It is the ONLY read that tells the truth
  /// about a date that holds more than one thing.
  List<CalendarEntry> forDate(String dateKey) =>
      List<CalendarEntry>.unmodifiable(
          _byDate[dateKey] ?? const <CalendarEntry>[]);

  /// How many entries cover [dateKey]. Drives the week cell's count badge.
  int countForDate(String dateKey) => _byDate[dateKey]?.length ?? 0;

  /// Every entry across every date, date-ascending then write order.
  List<CalendarEntry> get allEntries => [
        for (final k in sortedDateKeys) ..._byDate[k]!,
      ];

  List<String> get sortedDateKeys => _byDate.keys.toList()..sort();

  /// Look up one entry by its full identity.
  CalendarEntry? byId(String dateKey, String entryId) {
    for (final e in _byDate[dateKey] ?? const <CalendarEntry>[]) {
      if (e.entryId == entryId) return e;
    }
    return null;
  }

  // ── Single-entry view (what every un-migrated caller sees) ────────────────

  /// The primary entry for [dateKey] — the last written. Identical to what
  /// `map[dateKey]` returned before V3.
  CalendarEntry? operator [](String dateKey) {
    final list = _byDate[dateKey];
    return (list == null || list.isEmpty) ? null : list.last;
  }

  /// One entry per date — the pre-V3 view, for the subsystems that genuinely
  /// operate per-date (conflict detection, overload, priority, learning).
  ///
  /// ⚠️ LOSSY BY CONSTRUCTION. Anything reading this sees at most one entry per
  /// date and cannot know a second exists. That is a deliberate, documented
  /// narrowing for this prompt — NOT a parallel data path, because it is
  /// derived from the same store on every read and never written back.
  Map<String, CalendarEntry> get primaries => {
        for (final k in sortedDateKeys) k: _byDate[k]!.last,
      };

  Iterable<String> get keys => _byDate.keys;
  bool containsKey(String dateKey) => (_byDate[dateKey]?.isNotEmpty ?? false);
  bool get isEmpty => _byDate.values.every((l) => l.isEmpty);
  bool get isNotEmpty => !isEmpty;

  /// Total entries across all dates — NOT the number of dates covered.
  int get totalEntries =>
      _byDate.values.fold(0, (sum, list) => sum + list.length);

  // ── Mutations (all return a new set; this type is immutable) ──────────────

  /// Upsert by `(dateKey, entryId)`. An existing id is replaced in place so it
  /// keeps its position — a Game Day refresh must not reorder the night.
  CalendarEntrySet upsert(CalendarEntry entry) => upsertAll([entry]);

  CalendarEntrySet upsertAll(Iterable<CalendarEntry> entries) {
    final next = _mutableCopy();
    for (final e in entries) {
      final list = next.putIfAbsent(e.dateKey, () => <CalendarEntry>[]);
      final at = list.indexWhere((x) => x.entryId == e.entryId);
      if (at >= 0) {
        list[at] = e;
      } else {
        list.add(e);
      }
    }
    return CalendarEntrySet._(next);
  }

  /// Remove EVERY entry on [dateKey].
  ///
  /// This is what the pre-V3 `removeEntry(dateKey)` did, and the delete
  /// affordance that calls it is still labelled "Delete This Day". Callers that
  /// mean one row must use [removeEntryById].
  CalendarEntrySet removeDate(String dateKey) {
    final next = _mutableCopy()..remove(dateKey);
    return CalendarEntrySet._(next);
  }

  /// Remove exactly one entry. A date left with no entries is dropped, so
  /// [containsKey] stays honest.
  CalendarEntrySet removeEntryById(String dateKey, String entryId) {
    final next = _mutableCopy();
    final list = next[dateKey];
    if (list == null) return this;
    list.removeWhere((e) => e.entryId == entryId);
    if (list.isEmpty) next.remove(dateKey);
    return CalendarEntrySet._(next);
  }

  /// Drop every entry matching [test] — used to strip holiday defaults before
  /// a Firestore write.
  CalendarEntrySet where(bool Function(CalendarEntry) test) =>
      CalendarEntrySet.fromEntries(allEntries.where(test));

  Map<String, List<CalendarEntry>> _mutableCopy() => {
        for (final e in _byDate.entries) e.key: List<CalendarEntry>.from(e.value),
      };

  @override
  String toString() =>
      'CalendarEntrySet(${_byDate.length} dates, $totalEntries entries)';
}
