/// THE shape of a `/users/{uid}/favorites/{id}` document.
///
/// One collection had two schemas. The live security rule accepts exactly one
/// of them — a create must carry `pattern_name` (string) and `added_at`
/// (timestamp) — and that is the only schema that exists in production (every
/// doc there was written by the habit learner through
/// `UserService.addFavorite`). The other, camelCase shape (`name`,
/// `usageCount`, `lastUsed`, `wledPayload`, `autoAdded`) was written by the
/// favorite heart, "Save to Favorites" and the brand design generator, and was
/// REJECTED by that rule every time: no manual favorite has ever been saved
/// (explore-palette-save-to-device-audit-2026-09-20, S4).
///
/// Every writer now builds its document here, so the shape cannot fork again.
/// The rule was not touched.
///
/// ```
/// pattern_name  string     rule-required; immutable after create
/// added_at      timestamp  rule-required; immutable after create
/// pattern_data  string     jsonEncode(WLED payload) — see [decodeFavoritePayload]
/// usage_count   int
/// auto_added    bool
/// last_used     timestamp  optional; set once the favorite is used
/// ```
///
/// A PER-PIXEL (Static) favorite needs no extra field: its picture rides
/// inside `pattern_data`, as a `CustomDesign` under `lumina_design` — see
/// `favorite_design_payload.dart`. Anything that re-applies a favorite must go
/// through `applyFavoritePayloadWith`, which sends that through the chunked
/// spine; a raw `applyJson` of it is refused by size.
library;

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/services/user_service.dart';

export 'package:nexgen_command/features/favorites/favorite_payload_codec.dart';

const String kFavoritePatternName = 'pattern_name';
const String kFavoriteAddedAt = 'added_at';
const String kFavoritePatternData = 'pattern_data';
const String kFavoriteUsageCount = 'usage_count';
const String kFavoriteAutoAdded = 'auto_added';
const String kFavoriteLastUsed = 'last_used';

/// Name stored when the caller has none. The rule requires a string; an empty
/// one would pass it and then render as a blank card.
const String kFavoriteFallbackName = 'Favorite';

/// The document for a NEW favorite. [payload] is the WLED state to re-apply —
/// a real `/json/state` body, not a model's own JSON.
///
/// `pattern_data` is `jsonEncode`d: a WLED payload's `col: [[r,g,b,w]]` is an
/// array-of-arrays, which the native iOS Firestore codec aborts on (#84) and
/// [UserService.sanitizeForFirestore] refuses outright.
Map<String, dynamic> buildFavoriteCreateData({
  required String patternName,
  required Map<String, dynamic> payload,
  bool autoAdded = false,
}) {
  final name = patternName.trim();
  return UserService.sanitizeForFirestore({
    kFavoritePatternName: name.isEmpty ? kFavoriteFallbackName : name,
    kFavoriteAddedAt: FieldValue.serverTimestamp(),
    kFavoritePatternData: jsonEncode(payload),
    kFavoriteUsageCount: 0,
    kFavoriteAutoAdded: autoAdded,
  });
}

/// The update for a favorite that ALREADY exists (re-saving the same pattern).
///
/// Deliberately never carries `pattern_name` or `added_at`: the rule's update
/// clause requires both to be unchanged, and a fresh server timestamp is a
/// change — sending the create document again is denied.
Map<String, dynamic> buildFavoriteRefreshData({
  required Map<String, dynamic> payload,
}) =>
    {
      kFavoritePatternData: jsonEncode(payload),
      kFavoriteLastUsed: FieldValue.serverTimestamp(),
    };

/// The update recorded each time a favorite is applied.
Map<String, dynamic> buildFavoriteUsageData() => {
      kFavoriteUsageCount: FieldValue.increment(1),
      kFavoriteLastUsed: FieldValue.serverTimestamp(),
    };

/// Creates the favorite at [ref], or refreshes its stored look when it is
/// already there. Throws on failure — callers surface it; a swallowed error
/// here is how "saved" toasts came to sit on top of writes that never landed.
Future<void> writeFavorite(
  DocumentReference<Map<String, dynamic>> ref, {
  required String patternName,
  required Map<String, dynamic> payload,
  bool autoAdded = false,
}) async {
  final snap = await ref.get();
  if (snap.exists) {
    await ref.update(buildFavoriteRefreshData(payload: payload));
  } else {
    await ref.set(buildFavoriteCreateData(
      patternName: patternName,
      payload: payload,
      autoAdded: autoAdded,
    ));
  }
}
