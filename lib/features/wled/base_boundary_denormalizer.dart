// lib/features/wled/base_boundary_denormalizer.dart
//
// Publish the controller's DEVICE-RESIDENT TIMER ROWS so a server-side planner
// can treat them as fixed points.
//
// THE GAP
// -------
// A device base ON row and a cloud Game Day fire act on the same house with no
// arbitration, and the device timer wins by default because nothing
// server-side knows it exists. No server code reads `timers.ins` — every
// reference in `functions/src` is a comment, and `gameDayPlanning.ts:405` says
// why: the rows live behind `/json/cfg`, which is LAN-only, so there is no
// off-LAN read.
//
// The consequence is not rare. The collision window for an evening game is
// [first pitch − 30 min, final] — roughly 18:40–22:10 for a 19:10 start — and
// three of the four accounts with a base layer have an ON boundary inside it.
// Evening base-ON boundaries and evening first pitches occupy the same hours by
// nature: people light their house around sunset, and baseball starts around
// sunset. From the customer's seat, a base row firing mid-game is *the design
// dying mid-game*.
//
// WHAT THIS FILE DOES, AND DOES NOT
// ---------------------------------
// It publishes INPUTS. It does not arbitrate. Deciding what a planner should do
// when a base row lands inside a fire window is the compositor's job and is
// deliberately not here — but the compositor cannot even be written until the
// boundaries are visible, because option (a) (have the planner disable the
// conflicting row) is dead on the same LAN constraint: disabling a row is a
// `/json/cfg` write the bridge cannot deliver, and a disable that lands without
// its restore silently destroys the customer's everyday schedule.
//
// WHY IT COSTS NOTHING TO READ
// ----------------------------
// `timers.ins` comes straight from the `/json/cfg` fetch the defaults healer
// already performs on every connect (`ControllerClockInfo.timerRows`). No new
// device I/O, no new dependency, no new permission.
//
// THE NULL-VS-EMPTY DISCIPLINE — the same one participation uses
// -------------------------------------------------------------
// A null row list means "we could not see the timer table" and publishes
// NOTHING, leaving whatever is already stored. An empty list means "we read it
// and there are no armed rows" and IS published, because "this house has no
// base layer" is a real, actionable answer. Collapsing the two would let an
// unreadable cfg tell the planner a house has no boundaries, which is precisely
// the state in which it would plan straight through one.

import 'package:flutter/foundation.dart';

import 'package:nexgen_command/features/schedule/timer_landing.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/wled_preset_ranges.dart';

/// Firestore field names. snake_case, matching the surrounding controller-doc
/// convention (`controller_ips`, `participating_channels`, `display_name`).
const String kBaseBoundariesField = 'base_boundaries';

/// How many `timers.ins` slots were actually read. Provenance, and the direct
/// analogue of `participating_channels_device_ids`: it records the SHAPE the
/// answer was computed against, so a reader can tell a genuinely-empty table
/// from a truncated read that happened to parse.
const String kBaseBoundariesSlotsReadField = 'base_boundaries_slots_read';

/// Self-describing weekday convention, written alongside every publish.
///
/// WLED's `dow` bitmask is **Monday = bit 0** through Sunday = bit 6 — verified
/// empirically against firmware 0.14+ on 2026-05-19, and the app's own mapping
/// (`wled_dow.dart`) is correct. This codebase has already shipped the other
/// convention once: Lumina previously assumed Sunday = bit 0 from out-of-date
/// WLED docs, and every non-Daily schedule fired a day late for months, hidden
/// because Daily (127) is convention-agnostic.
///
/// The planner that will read these rows does not exist yet and will be written
/// by someone who cannot see the device. Thirty bytes per document is cheap
/// insurance against them re-deriving the wrong answer.
const String kBaseBoundariesDowBit0Field = 'base_boundaries_dow_bit0';
const String kBaseBoundariesDowBit0Value = 'monday';

/// True when the published row indices ARE device slot indices.
///
/// See [extractBaseBoundaries] — a `/json/cfg` readback is COMPACTED, so
/// normally they are not, and a reader must not treat `index` as a slot.
const String kBaseBoundariesIndicesAreSlotsField =
    'base_boundaries_indices_are_slots';

/// WLED 0.15.1 dedicates `timers.ins[8]` to SUNRISE and `[9]` to SUNSET —
/// `checkTimers()` special-cases them BY POSITION.
///
/// **That is true of the array we SEND, not of the array we READ BACK.** See
/// [extractBaseBoundaries].
const int kSunriseSlotIndex = 8;
const int kSunsetSlotIndex = 9;

/// How many slots WLED holds. A readback of exactly this length is the only
/// case in which nothing was compacted away and index == slot.
const int kWledTotalTimerSlots = 10;

/// The `kind` tags emitted per row.
const String kBoundaryKindClock = 'clock';
const String kBoundaryKindSunrise = 'sunrise';
const String kBoundaryKindSunset = 'sunset';

/// A solar row whose DIRECTION could not be determined from the wire. See
/// [extractBaseBoundaries] — with a single 255-row in a compacted readback,
/// sunrise vs sunset is genuinely undecidable, and guessing puts a planner in
/// the wrong half of the day.
const String kBoundaryKindSolarUnknown = 'solar';

/// One armed row from the controller's timer table.
///
/// Field-by-field this is what the device holds, not an interpretation of it.
/// The one thing added is [role] — see [wledPresetRole] for why the app has to
/// supply it.
@immutable
class BaseBoundaryRow {
  /// Position in the `timers.ins` array **as read back**.
  ///
  /// NOT the device slot index unless
  /// [kBaseBoundariesIndicesAreSlotsField] is true — WLED compacts the
  /// readback. Provenance/debug only; nothing about when a row fires depends
  /// on it.
  final int index;

  /// `clock`, `sunrise`, `sunset`, or `solar` (direction undecidable).
  /// Derived from the row's CONTENT (`hour == 255`), not its position.
  final String kind;

  /// Wall-clock hour 0-23 on a clock row. On a solar row this is WLED's
  /// serialized marker (255) and is **not** an hour — which is why [toJson]
  /// does not emit an `hour` key for solar rows.
  final int hour;

  /// Wall-clock minute on a clock row; the SIGNED offset in minutes from the
  /// solar event on a solar row. Two different quantities in one device field —
  /// [toJson] emits them under two different keys so no reader can confuse
  /// them.
  final int minute;

  /// Weekday bitmask, Monday = bit 0. See [kBaseBoundariesDowBit0Field].
  final int dow;

  /// The WLED preset id this row loads.
  final int macro;

  /// Which allocator owns [macro] — `system_on`, `system_off`, `schedule`,
  /// `lease`, `user_pattern`, `unknown`.
  final String role;

  const BaseBoundaryRow({
    required this.index,
    required this.kind,
    required this.hour,
    required this.minute,
    required this.dow,
    required this.macro,
    required this.role,
  });

  bool get isSolar => kind != kBoundaryKindClock;

  /// The wire shape. Keys are snake_case and deliberately asymmetric between
  /// clock and solar rows: a clock row carries `hour`/`minute`, a solar row
  /// carries `offset_minutes` and no hour at all. A planner that reads `minute`
  /// off a solar row gets **nothing** rather than a plausible wrong number —
  /// which is the failure this project has already paid for once, in the
  /// UTC-vs-local mixup that had the base row landing on the wrong side of the
  /// design fire.
  Map<String, Object?> toJson() => <String, Object?>{
        'index': index,
        'kind': kind,
        'macro': macro,
        'role': role,
        'dow': dow,
        if (!isSolar) 'hour': hour,
        if (!isSolar) 'minute': minute,
        if (isSolar) 'offset_minutes': minute,
      };

  @override
  bool operator ==(Object other) =>
      other is BaseBoundaryRow &&
      other.index == index &&
      other.kind == kind &&
      other.hour == hour &&
      other.minute == minute &&
      other.dow == dow &&
      other.macro == macro &&
      other.role == role;

  @override
  int get hashCode => Object.hash(index, kind, hour, minute, dow, macro, role);

  @override
  String toString() => isSolar
      ? '$kind[$index](${minute >= 0 ? '+' : ''}$minute min, macro:$macro/$role, '
          'dow:$dow)'
      : 'clock[$index](${hour.toString().padLeft(2, '0')}:'
          '${minute.toString().padLeft(2, '0')}, macro:$macro/$role, dow:$dow)';
}

int _fld(Map<String, dynamic> t, String k) =>
    (t[k] is num) ? (t[k] as num).toInt() : 0;

/// Turn a raw `timers.ins` array into the armed rows a planner must respect.
///
/// Returns **null** when [ins] is null — the timer table was unreadable, which
/// is not the same as empty (see the file header). Returns `[]` when the table
/// was read and holds nothing armed.
///
/// Filtering uses [carriesAnyEnabledEntry], the SAME predicate the schedule
/// sync's all-stub clobber guard uses to decide whether a payload contains
/// anything worth writing. That is deliberate: a row the clobber guard counts
/// as real content is, by definition, a boundary the planner has to know about.
/// Disabled padding stubs (`en:0, macro:0`) are not boundaries and are dropped.
///
/// Note it is broader than `isRealEnabledTimer`, which excludes `hour == 255` —
/// solar rows ARE boundaries, and on a sunset-driven house they may be the only
/// ones.
///
/// ── WHY CLASSIFICATION IS BY CONTENT, NOT BY POSITION ───────────────────────
///
/// WLED dedicates slot 8 to sunrise and slot 9 to sunset, and `checkTimers()`
/// keys off those POSITIONS. It is therefore very tempting to classify a
/// readback row by its array index. **That is wrong, and it was wrong in the
/// first cut of this function.**
///
/// A `/json/cfg` readback is COMPACTED: WLED echoes the armed entries and drops
/// the disabled padding stubs, so the 255-markers trail the general rows and
/// their index is NOT 8/9 (`timer_landing.dart` documents this hardware-
/// confirmed, and `extractReadbackSolarEntries` already reads them ordinally
/// for the same reason). BENCH-CONFIRMED 2026-08-11 on `.150`: a 10-entry push
/// with the sentinel at slot 8 reads back as **four** entries with the sentinel
/// at **index 3**. Classifying by index published it as a CLOCK row at hour
/// 255 — a boundary at an impossible time, which is precisely the
/// plausible-wrong-number failure the split `hour`/`offset_minutes` keys exist
/// to prevent.
///
/// So: `hour == 255` identifies a solar row, wherever it sits.
///
/// ── AND WHY DIRECTION IS SOMETIMES REFUSED ──────────────────────────────────
///
/// Order is preserved on the wire, so when BOTH solar slots are armed the first
/// 255-row is sunrise and the second is sunset. When only ONE comes back its
/// identity is **genuinely undecidable from the wire** — the common
/// "on at sunset, off at a clock time" shape arms slot 9 only and returns a
/// lone 255-row that looks identical to a lone sunrise. The schedule-sync
/// comparator resolves this against what it had just SENT; a cold read on
/// connect has no sent side, so there is nothing to resolve it against.
///
/// Such a row is published as [kBoundaryKindSolarUnknown]. A planner told
/// "solar, direction unknown" can widen or refuse; a planner told "sunrise"
/// when it is sunset plans in the wrong half of the day.
List<BaseBoundaryRow>? extractBaseBoundaries(List<Map<String, dynamic>>? ins) {
  if (ins == null) return null;

  // Armed rows only, paired with their readback position.
  final armed = <(int, Map<String, dynamic>)>[];
  for (var i = 0; i < ins.length; i++) {
    if (carriesAnyEnabledEntry(ins[i])) armed.add((i, ins[i]));
  }

  // Ordinal solar identification — see the doc comment above.
  final solarIndices = <int>[
    for (final (i, t) in armed)
      if (_fld(t, 'hour') == kSolarHourMarker) i
  ];
  final directionKnown = solarIndices.length == 2;

  final rows = <BaseBoundaryRow>[];
  for (final (i, t) in armed) {
    final isSolar = _fld(t, 'hour') == kSolarHourMarker;
    final String kind;
    if (!isSolar) {
      kind = kBoundaryKindClock;
    } else if (directionKnown) {
      kind = i == solarIndices.first
          ? kBoundaryKindSunrise
          : kBoundaryKindSunset;
    } else {
      kind = kBoundaryKindSolarUnknown;
    }

    final rawMin = _fld(t, 'min');
    final macro = _fld(t, 'macro');
    rows.add(BaseBoundaryRow(
      index: i,
      kind: kind,
      hour: _fld(t, 'hour'),
      // A solar offset round-trips through an unsigned byte, so −30 comes back
      // as 226. normalizeSolarOffset folds it back; clock minutes are untouched.
      minute: isSolar ? normalizeSolarOffset(rawMin) : rawMin,
      dow: _fld(t, 'dow'),
      macro: macro,
      role: wledPresetRole(macro),
    ));
  }
  return rows;
}

/// Should this row set be published?
///
/// Same contract as `shouldPublishParticipation`, and the same honest limit:
/// [lastPublished] comes from a PROCESS-LIFETIME memo, never from Firestore.
/// So the first publish of every app session goes out regardless of whether
/// anything changed. That is the deliberate self-heal — it repairs a lost write
/// with no read-back — and it is why `base_boundaries_publish_count` exists to
/// make the rate auditable.
///
/// An EMPTY row list is publishable: "this controller has no armed timers" is a
/// real answer and must not be confused with "unknown", which is expressed by
/// not publishing at all.
bool shouldPublishBaseBoundaries({
  required List<BaseBoundaryRow> rows,
  required List<BaseBoundaryRow>? lastPublished,
}) {
  if (lastPublished == null) return true;
  if (lastPublished.length != rows.length) return true;
  for (var i = 0; i < rows.length; i++) {
    if (lastPublished[i] != rows[i]) return true;
  }
  return false;
}

/// What the app writes. Pure — no Firestore types — so the shape is testable in
/// one place. The caller stamps `_at` / history via [stampFactFamily].
@visibleForTesting
Map<String, Object?> buildBaseBoundariesDoc({
  required List<BaseBoundaryRow> rows,
  required int slotsRead,
}) {
  return <String, Object?>{
    kBaseBoundariesField: rows.map((r) => r.toJson()).toList(),
    kBaseBoundariesSlotsReadField: slotsRead,
    kBaseBoundariesDowBit0Field: kBaseBoundariesDowBit0Value,
    // Only a full-length readback proves nothing was compacted away. Anything
    // shorter means WLED dropped stubs and every row's `index` shifted, so a
    // reader must not treat it as a device slot.
    kBaseBoundariesIndicesAreSlotsField: slotsRead == kWledTotalTimerSlots,
  };
}

/// Process-lifetime memo of what has already been published, keyed by
/// controller id. Not persisted — see [shouldPublishBaseBoundaries].
@visibleForTesting
final Map<String, List<BaseBoundaryRow>> publishedBaseBoundariesMemo =
    <String, List<BaseBoundaryRow>>{};

/// Clears the memo. Tests only.
@visibleForTesting
void resetBaseBoundariesMemo() => publishedBaseBoundariesMemo.clear();

/// Record a publish in the memo.
@visibleForTesting
void rememberPublishedBaseBoundaries(
  String controllerId,
  List<BaseBoundaryRow> rows,
) {
  publishedBaseBoundariesMemo[controllerId] =
      List<BaseBoundaryRow>.from(rows);
}

/// Build this family's contribution to a publish, or [PreparedFacts.none].
///
/// [rows] null ⇒ the timer table was unreadable ⇒ contribute nothing and leave
/// whatever is stored. That is not a failure; it is the only correct response
/// to not having looked.
PreparedFacts prepareBaseBoundaryFacts({
  required String controllerId,
  required List<BaseBoundaryRow>? rows,
  required int slotsRead,
  required String source,
}) {
  if (rows == null) return PreparedFacts.none;

  final last = publishedBaseBoundariesMemo[controllerId];
  if (!shouldPublishBaseBoundaries(rows: rows, lastPublished: last)) {
    return PreparedFacts.none;
  }

  final fields = buildBaseBoundariesDoc(rows: rows, slotsRead: slotsRead);
  stampFactFamily(
    fields,
    field: kBaseBoundariesField,
    source: source,
    previous: last?.map((r) => r.toJson()).toList(),
    previousKnown: last != null,
  );

  final snapshot = List<BaseBoundaryRow>.from(rows);
  return PreparedFacts(
    fields,
    () => rememberPublishedBaseBoundaries(controllerId, snapshot),
  );
}
