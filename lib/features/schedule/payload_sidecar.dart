// lib/features/schedule/payload_sidecar.dart
//
// +112 — the durable home of a dated entry's WLED payload (effect, palette,
// every colour), beside the entry itself.
//
// WHY A SIDECAR AND NOT ONLY AN INLINE FIELD. `users/{uid}.calendar_entries`
// is rewritten WHOLE by every build that saves the calendar
// (`UserService.saveCalendarEntries`). Builds 109–111 decode each row through
// `CalendarEntry.fromJson`, which reads known keys only, and re-encode through
// `toJson`, which emits known keys only — an inline `wledPayload` survives a
// read on those builds (unknown keys are ignored, never thrown on) but is
// DROPPED by their next write. The same build writes exactly three fields in
// that update — `calendar_entries`, `calendar_entry_scope`, `updated_at` — so
// a separate top-level field is never touched by them. That is the D1 scope
// sidecar's mechanism, reused here under its own field name.
//
// WHY A FINGERPRINT. An older build may REPLACE the row at a storage key with
// a different entry (Lumina writes a new primary for the date, say) and leave
// the sidecar row behind. Attaching a stale payload to an unrelated entry would
// light the wrong look on a night the customer re-planned, so a sidecar row is
// honoured only when its pattern name and colour still match the row it was
// written for.
//
// Shape (one row per storage key, same keys as `calendar_entries`):
//   calendar_entry_payload: {
//     "<YYYY-MM-DD>":             { "p": "<json string>", "n": "<patternName>", "col": "#rrggbb" | null },
//     "<YYYY-MM-DD>#<entryId>":   { ... }
//   }
// The payload is a JSON STRING, never a nested map: WLED `col` is an array of
// arrays, which Firestore refuses natively (#84).

import 'dart:convert';

import 'package:flutter/foundation.dart';

/// The user-document field that carries the payload sidecar.
const String kCalendarEntryPayloadField = 'calendar_entry_payload';

const String kPayloadJsonKey = 'p';
const String kPayloadNameKey = 'n';
const String kPayloadColorKey = 'col';

/// One sidecar row: the payload plus the fingerprint of the entry it belongs to.
@immutable
class PayloadSidecarRow {
  final Map<String, dynamic> payload;
  final String patternName;
  final String? colorHex;

  const PayloadSidecarRow({
    required this.payload,
    required this.patternName,
    required this.colorHex,
  });
}

/// Encode the rows that carry a payload. Rows without one are omitted, so a
/// cleared payload disappears on the next full write rather than lingering.
Map<String, dynamic> encodePayloadSidecar(Map<String, PayloadSidecarRow?> byKey) {
  final out = <String, dynamic>{};
  byKey.forEach((key, row) {
    if (row == null) return;
    out[key] = <String, dynamic>{
      kPayloadJsonKey: jsonEncode(row.payload),
      kPayloadNameKey: row.patternName,
      if (row.colorHex != null) kPayloadColorKey: row.colorHex,
    };
  });
  return out;
}

/// Decode one sidecar row for [key], or null when absent, malformed, or when
/// the fingerprint no longer matches the entry now stored under that key.
Map<String, dynamic>? decodePayloadSidecarEntry(
  dynamic sidecar,
  String key, {
  required String patternName,
  required String? colorHex,
}) {
  if (sidecar is! Map) return null;
  final raw = sidecar[key];
  if (raw is! Map) return null;
  final name = raw[kPayloadNameKey];
  if (name is! String || name != patternName) return null;
  final col = raw[kPayloadColorKey];
  final storedCol = col is String && col.isNotEmpty ? col : null;
  if (storedCol != colorHex) return null;
  final p = raw[kPayloadJsonKey];
  if (p is! String || p.isEmpty) return null;
  try {
    final decoded = jsonDecode(p);
    if (decoded is! Map) return null;
    return Map<String, dynamic>.from(decoded);
  } catch (e) {
    debugPrint('PayloadSidecar: unreadable payload for $key — $e');
    return null;
  }
}
