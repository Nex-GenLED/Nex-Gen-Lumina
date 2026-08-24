// lib/features/schedule/calendar_entry_storage.dart
//
// Scheduling V3 A1 — the Firestore codec for `users/{uid}.calendar_entries`.
//
// PURE. No Firestore, no Flutter. `UserService` calls these; the tests call
// these; there is one definition of the wire shape.
//
// ── THE SHAPE, AND WHY ────────────────────────────────────────────────────────
//
// Before V3 the field was a map keyed by `'YYYY-MM-DD'`, one entry per date.
// P1 read the real fleet (audit/SCHEDULE_V3_P2.md): 29 users, 11 with entries,
// 159 entries, every key a plain date, and — decisively — **every value carries
// `dateKey` inside it, 159/159**.
//
// The new shape keeps the plain key for a date's PRIMARY entry and suffixes
// every additional one:
//
//     "2026-05-31"              → the primary        (unchanged, byte-for-byte)
//     "2026-05-31#gd_royals"    → an additional entry
//     "2026-05-31#gd_chiefs"    → another
//
// WHY NOT A NESTED LIST. `{"2026-05-31": [ {...}, {...} ]}` is the obvious
// shape and it is the wrong one, for three reasons:
//
//   1. An OLD build round-trips this field through its own state map on every
//      save. Given composite keys it rewrites them verbatim and the extra
//      entries SURVIVE. Given a list it would hand `CalendarEntry.fromJson` a
//      List, throw, log "Skipping corrupt calendar entry", and the next save
//      would erase every multi-entry date in the account.
//   2. No migration. Existing plain-keyed documents are already valid new-shape
//      documents — there is nothing to repair, and 159 live rows stay untouched.
//   3. It keeps arrays-of-maps out of a Firestore write path, well clear of the
//      #84 nested-array class.
//
// ── WHAT AN OLD BUILD DOES ────────────────────────────────────────────────────
//
// `UserService.loadCalendarEntries` keys its result by the RAW map key, so an
// old build puts `"2026-05-31#gd_royals"` in its state under that literal
// string. Every lookup it performs is `entries[todayKey]` with a plain date, so
// the composite rows are never found and never rendered: the old build shows
// exactly one entry per date, which is precisely its pre-V3 behaviour. It
// degrades by IGNORING, not by breaking, and not — as first assumed — by
// showing the newest of several.
//
// ── THE ONE ACCEPTED COST ─────────────────────────────────────────────────────
//
// An old build's `toJson` has no `channels` / `endMode` / `estimatedEnd` /
// `hardCapAt`, so any entry it rewrites loses them. Accepted: all four are
// display-only in this prompt, so the loss is labels, not behaviour. It stays
// safe only while `hardCapAt` is never load-bearing — see the field's own
// doc comment, and the Policy B gates in audit/SCHEDULE_V3_P2.md.

import 'package:nexgen_command/features/schedule/calendar_entry.dart';
import 'package:nexgen_command/features/schedule/calendar_entry_set.dart';

/// Separates the date from the entry id in a composite storage key.
///
/// `#` is safe: a dateKey is validated `^\d{4}-\d{2}-\d{2}$` on the way in
/// (`CalendarEntry.fromAiJson`), and Firestore map keys may not contain `/` or
/// `.` — `#` has neither problem.
const String kCalendarStorageKeySeparator = '#';

/// Encode a set into the `calendar_entries` field.
///
/// The primary (last-written) entry on each date takes the plain date key; the
/// rest are suffixed with their `entryId`. Callers strip holidays first —
/// those are local defaults and have never been persisted.
Map<String, Map<String, dynamic>> encodeCalendarEntries(CalendarEntrySet set) {
  final out = <String, Map<String, dynamic>>{};
  for (final dateKey in set.sortedDateKeys) {
    final list = set.forDate(dateKey);
    if (list.isEmpty) continue;
    for (var i = 0; i < list.length; i++) {
      final entry = list[i];
      final isPrimary = i == list.length - 1;
      final key = isPrimary
          ? dateKey
          : '$dateKey$kCalendarStorageKeySeparator${entry.entryId}';
      out[key] = entry.toJson();
    }
  }
  return out;
}

/// Decode the `calendar_entries` field.
///
/// Grouping uses the VALUE's `dateKey`, never the map key — P1 proved it is
/// present on every production entry, and it is the field an old build cannot
/// corrupt because it round-trips it. The key's date prefix is only a fallback
/// for a value that somehow lacks one.
///
/// ORDER IS RECONSTRUCTED, NOT READ. Firestore map iteration order is not
/// guaranteed, so "primary last" cannot be inferred from arrival order. The
/// plain-keyed entry is placed LAST and the composite ones before it in
/// key-sorted order — deterministic, and a round-trip through
/// [encodeCalendarEntries] reproduces it exactly.
///
/// [onCorrupt] receives a reason for each rejected row; the row is skipped
/// rather than throwing, matching the pre-V3 loader's behaviour.
CalendarEntrySet decodeCalendarEntries(
  Map<String, dynamic> raw, {
  void Function(String key, Object error)? onCorrupt,
}) {
  // dateKey -> (composite entries by storage key, primary)
  final composites = <String, Map<String, CalendarEntry>>{};
  final primaries = <String, CalendarEntry>{};

  for (final mapEntry in raw.entries) {
    final key = mapEntry.key;
    final value = mapEntry.value;
    if (value is! Map) {
      onCorrupt?.call(key, 'value is ${value.runtimeType}, not a Map');
      continue;
    }
    final json = Map<String, dynamic>.from(value);

    final sep = key.indexOf(kCalendarStorageKeySeparator);
    final keyDate = sep >= 0 ? key.substring(0, sep) : key;
    final keyEntryId = sep >= 0 ? key.substring(sep + 1) : null;

    // The value owns its date. Fall back to the key only if it doesn't.
    json['dateKey'] ??= keyDate;
    // A composite key's suffix IS the id; trust it over a stale stored value so
    // the key and the entry can never disagree about identity.
    if (keyEntryId != null && keyEntryId.isNotEmpty) {
      json['entryId'] = keyEntryId;
    }

    final CalendarEntry entry;
    try {
      entry = CalendarEntry.fromJson(json);
    } catch (e) {
      onCorrupt?.call(key, e);
      continue;
    }

    if (keyEntryId == null) {
      primaries[entry.dateKey] = entry;
    } else {
      composites.putIfAbsent(entry.dateKey, () => <String, CalendarEntry>{})[key] =
          entry;
    }
  }

  final ordered = <CalendarEntry>[];
  final dates = <String>{...composites.keys, ...primaries.keys}.toList()..sort();
  for (final date in dates) {
    final extras = composites[date];
    if (extras != null) {
      final sortedKeys = extras.keys.toList()..sort();
      for (final k in sortedKeys) {
        ordered.add(extras[k]!);
      }
    }
    final primary = primaries[date];
    if (primary != null) ordered.add(primary);
  }

  return CalendarEntrySet.fromEntries(ordered);
}
