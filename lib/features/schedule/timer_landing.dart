// Pure-Dart (no flutter / dart:ui) readback comparator for the schedule cfg
// write, extracted from schedule_sync.dart so the bench/ CLI asserts landing
// with the ACTUAL comparator. schedule_sync.dart re-exports these, so existing
// importers are unaffected.

/// True when a timer entry is a "real, enabled, armable" timer — NOT a disabled
/// padding stub and NOT a solar sentinel: `en` is truthy (bool `true` or int
/// `1`), `macro != 0`, `hour != 255`. Shared by the readback comparator
/// ([timersInsLanded]), syncAll's empty-armed guard, and the bench/ CLI — a
/// genuine shared internal API (not test-only), so no @visibleForTesting.
bool isRealEnabledTimer(Map<String, dynamic> t) {
  final en = t['en'];
  final enOn = en == true || en == 1;
  final macro = (t['macro'] is num) ? (t['macro'] as num).toInt() : 0;
  final hour = (t['hour'] is num) ? (t['hour'] as num).toInt() : -1;
  return enOn && macro != 0 && hour != 255;
}

/// The `hour` value WLED serializes for a solar (sunrise/sunset) timer slot.
/// Not a clock hour — a marker. See [solarTimersLanded].
const int kSolarHourMarker = 255;

/// A solar row as it appears on the wire, paired to the slot that owns it.
class SolarTimerRow {
  /// `true` = sunrise (sent slot 8), `false` = sunset (sent slot 9).
  final bool isSunrise;

  /// `en` normalized to int (WLED reads it type-strictly; a JSON bool stores 0).
  final int en;

  /// Offset in MINUTES from the solar event, **signed**, −120..+120.
  /// This is NOT a wall-clock minute — see [solarTimersLanded] note 3.
  final int offsetMinutes;
  final int macro;
  final int dow;

  const SolarTimerRow({
    required this.isSunrise,
    required this.en,
    required this.offsetMinutes,
    required this.macro,
    required this.dow,
  });

  @override
  String toString() =>
      '${isSunrise ? "sunrise" : "sunset"}(en:$en off:$offsetMinutes '
      'macro:$macro dow:$dow)';
}

/// Normalizes WLED's `min` byte for a solar slot into a SIGNED offset.
///
/// The offset range is −120..+120. If the firmware round-trips it through an
/// unsigned byte, `-30` comes back as `226` (256 − 30). This folds anything
/// above 127 back into negative territory so the comparator sees what was sent.
///
/// **Bench-verify the sign round-trip before trusting an offset** — the app
/// hardcodes offset 0 today, which is precisely why a sign bug here would stay
/// invisible until the first non-zero offset ships.
int normalizeSolarOffset(int raw) => raw > 127 ? raw - 256 : raw;

/// Index of the sunrise slot in a SENT `timers.ins` array (`assembleSolarAwareIns`).
const int kSentSunriseSlot = 8;

/// Index of the sunset slot in a SENT `timers.ins` array.
const int kSentSunsetSlot = 9;

int _fld(Map<String, dynamic> m, String k) =>
    (m[k] is num) ? (m[k] as num).toInt() : -1;

SolarTimerRow _row(Map<String, dynamic> t, {required bool isSunrise}) =>
    SolarTimerRow(
      isSunrise: isSunrise,
      en: (t['en'] == true || t['en'] == 1) ? 1 : 0,
      offsetMinutes: normalizeSolarOffset(_fld(t, 'min')),
      macro: _fld(t, 'macro'),
      dow: _fld(t, 'dow'),
    );

/// SENT-side extraction — **POSITIONAL, by array index**.
///
/// `assembleSolarAwareIns` always emits exactly 10 entries with slot 8 =
/// sunrise and slot 9 = sunset, so on this side the identity of a row is its
/// index. Returns only the ENABLED slots; a disabled slot is an absent solar
/// timer and WLED will drop it from the readback.
///
/// **This must NOT be read ordinally.** Doing so mis-labels the common
/// "sunset ON, clock OFF" shape — sunrise disabled, sunset enabled — as a lone
/// *sunrise*, which then fails to match its own readback. Bench-confirmed
/// 2026-08-05: that configuration returns a single 255-row.
List<SolarTimerRow> extractSentSolarRows(List<Map<String, dynamic>> ins) {
  final out = <SolarTimerRow>[];
  if (ins.length <= kSentSunriseSlot) return out; // 8-slot push: no solar
  for (final slot in const [kSentSunriseSlot, kSentSunsetSlot]) {
    if (slot >= ins.length) continue;
    final t = ins[slot];
    if (_fld(t, 'hour') != kSolarHourMarker) continue;
    final r = _row(t, isSunrise: slot == kSentSunriseSlot);
    if (r.en == 1) out.add(r);
  }
  return out;
}

/// READBACK-side extraction — **ORDINAL, by order of the 255-markers**.
///
/// WLED compacts the readback: it echoes the enabled real entries plus the
/// solar sentinels and DROPS disabled padding stubs, so the 255-entries TRAIL
/// the general ones and their array index is NOT 8/9. When BOTH slots are
/// armed the order is preserved — first 255 = sunrise, second = sunset
/// (sunrise_off_service.dart:257-261, hardware-confirmed).
///
/// When only ONE 255-row comes back its identity is genuinely undecidable from
/// the wire alone; [solarTimersLanded] resolves that against how many rows were
/// SENT rather than guessing here.
List<Map<String, dynamic>> extractReadbackSolarEntries(
    List<Map<String, dynamic>> ins) {
  final out = <Map<String, dynamic>>[];
  for (final t in ins) {
    if (_fld(t, 'hour') == kSolarHourMarker) out.add(t);
    if (out.length == 2) break; // only two solar slots exist
  }
  return out;
}

/// Readback comparator for SOLAR rows — the blind spot [timersInsLanded] leaves.
///
/// [isRealEnabledTimer] excludes `hour == 255`, so every solar row is dropped
/// from BOTH sides of [timersInsLanded]. Without this function a solar row
/// verifies clean whether it landed correctly, landed wrong, or never landed at
/// all — structurally the same defect as P0-8 (out-of-range bounds accepted
/// verbatim, so a sent-vs-readback comparison could not see them).
///
/// Semantics:
/// 1. SENT side is read **POSITIONALLY** (slot 8/9, [extractSentSolarRows]);
///    READBACK side is read **ORDINALLY** ([extractReadbackSolarEntries]). The
///    two sides genuinely use different rules — that asymmetry is the whole
///    subtlety, and conflating them produces false mismatches.
/// 2. `en`, `macro`, `dow` compared as for general timers.
/// 3. `min` compared as a **SIGNED offset**, via [normalizeSolarOffset].
/// 4. `hour == 255` identifies a solar row on the readback side.
/// 5. A sent solar row with `en == 0` is a disabled/absent slot and is NOT
///    required to appear (WLED drops it, exactly like a general stub).
///
/// **Count-driven pairing** resolves the one-row ambiguity without guessing:
///
/// | sent (enabled) | readback 255-rows | rule |
/// |---|---|---|
/// | 0 | any | true — nothing solar was claimed |
/// | 1 | 1 | content-match; identity is unambiguous because there is exactly one candidate |
/// | 2 | 2 | ordinal pairing — first = sunrise, second = sunset. **Catches a swap.** |
/// | n | < n | false — a slot we armed is missing |
/// | 1 | 2 | the sent row must content-match one of them; the extra is not ours |
///
/// The `1 → 1` case matters in production: "on at sunset, off at a clock time"
/// arms sunset ONLY, so slot 8 is a disabled stub and the readback carries a
/// single 255-row. Bench-confirmed 2026-08-05. Reading that ordinally would
/// label it *sunrise* and fail a perfectly good write.
bool solarTimersLanded(
  List<Map<String, dynamic>> sent,
  List<Map<String, dynamic>> readback,
) {
  final sentSolar = extractSentSolarRows(sent);
  if (sentSolar.isEmpty) return true; // nothing solar claimed; nothing to check

  final backEntries = extractReadbackSolarEntries(readback);
  if (backEntries.length < sentSolar.length) return false; // a slot is missing

  bool same(SolarTimerRow s, Map<String, dynamic> b) =>
      ((b['en'] == true || b['en'] == 1) ? 1 : 0) == s.en &&
      _fld(b, 'macro') == s.macro &&
      _fld(b, 'dow') == s.dow &&
      normalizeSolarOffset(_fld(b, 'min')) == s.offsetMinutes;

  if (sentSolar.length == 2) {
    // Both armed → order is preserved on the wire, so pair ordinally. This is
    // what makes a sunrise/sunset SWAP detectable.
    return same(sentSolar[0], backEntries[0]) &&
        same(sentSolar[1], backEntries[1]);
  }

  // Exactly one armed → identity cannot be read off the wire, but there is only
  // one thing it can be. Content-match against any returned solar row.
  return backEntries.any((b) => same(sentSolar.single, b));
}

/// CONTENT-match readback comparison for the schedule cfg write: does the
/// controller's timer table CONTAIN the real timers we sent, regardless of
/// position?
///
/// Bench-proven readback shape (WLED vid 2507300, SKIKBILY): the controller
/// echoes the enabled real entries + the two solar sentinel entries (hour:255)
/// and DROPS disabled padding stubs — so the array COMPACTS and sent-index ≠
/// readback-index. Per-index comparison is therefore invalid; we match by
/// content anywhere in the array.
///
/// Semantics:
/// - From [sent], consider only ENABLED REAL entries: `en==1 && macro!=0 &&
///   hour!=255` (this drops disabled/padding stubs and solar sentinels).
/// - Each such entry must have SOME entry in [readback] with `en==1` and
///   matching hour/min/macro/dow (order-independent).
/// - If [sent] has no real entries (schedule cleared), the write is confirmed
///   iff [readback] contains NO enabled NON-solar entries (hour!=255) — the
///   controller's real timers were cleared; its solar sentinels are ignored.
/// - `en` is normalized (bool/int → int); solar entries (hour==255) and any
///   readback entries that don't match a sent real entry are ignored.
///
/// Field-level, not raw-JSON equality: WLED returns extra keys (start/end/
/// mon/day) and reorders, so only the fields we control are compared.
bool timersInsLanded(
  List<Map<String, dynamic>> sent,
  List<Map<String, dynamic>> readback,
) {
  int en(Object? v) => (v == true || v == 1) ? 1 : 0;
  int fld(Map<String, dynamic> m, String k) =>
      (m[k] is num) ? (m[k] as num).toInt() : -1;

  final sentReal = sent.where(isRealEnabledTimer).toList();

  if (sentReal.isEmpty) {
    // Cleared schedule: the controller must show no enabled non-solar timers.
    return !readback.any((r) => en(r['en']) == 1 && fld(r, 'hour') != 255);
  }

  // Every real timer we sent must appear somewhere in the readback (en==1,
  // matching controlled fields). Solar sentinels and unrelated readback entries
  // are ignored implicitly — they won't match a non-255 sent hour.
  for (final s in sentReal) {
    final present = readback.any((r) =>
        en(r['en']) == 1 &&
        fld(r, 'hour') == fld(s, 'hour') &&
        fld(r, 'min') == fld(s, 'min') &&
        fld(r, 'macro') == fld(s, 'macro') &&
        fld(r, 'dow') == fld(s, 'dow'));
    if (!present) return false;
  }
  return true;
}
