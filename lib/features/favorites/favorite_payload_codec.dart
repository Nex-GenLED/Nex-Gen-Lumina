import 'dart:convert';

/// Decodes a favorite's stored pattern payload, tolerating every shape that
/// has ever been written to `/users/{uid}/favorites`:
///
/// * **String** — the payload `jsonEncode`d. This is the shape of every
///   favorite in production: a WLED payload holds arrays-of-arrays
///   (`col: [[r,g,b,w]]`), which Firestore's native iOS codec aborts on (#84),
///   so it is stored as an opaque string.
/// * **Map** — a raw map, from before the encode fix.
///
/// Returns `{}` for null / empty / unparseable input — never throws. Pure
/// (`dart:convert` only) so both favorites models can share it without an
/// import cycle.
Map<String, dynamic> decodeFavoritePayload(dynamic raw) {
  if (raw is String) {
    if (raw.isEmpty) return <String, dynamic>{};
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map) return Map<String, dynamic>.from(decoded);
    } catch (_) {
      return <String, dynamic>{};
    }
    return <String, dynamic>{};
  }
  if (raw is Map) return Map<String, dynamic>.from(raw);
  return <String, dynamic>{};
}
