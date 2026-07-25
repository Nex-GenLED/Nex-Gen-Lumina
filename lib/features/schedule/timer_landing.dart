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
