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
///
/// `auto_added` is always false (#164): a favorite is only ever the customer's
/// explicit choice. The field stays because documents from before the cap
/// carry `true` (the habit learner wrote them) and readers tell them apart.
Map<String, dynamic> buildFavoriteCreateData({
  required String patternName,
  required Map<String, dynamic> payload,
}) {
  final name = patternName.trim();
  return UserService.sanitizeForFirestore({
    kFavoritePatternName: name.isEmpty ? kFavoriteFallbackName : name,
    kFavoriteAddedAt: FieldValue.serverTimestamp(),
    kFavoritePatternData: jsonEncode(payload),
    kFavoriteUsageCount: 0,
    kFavoriteAutoAdded: false,
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

/// The most favorites an account keeps (#164, owner decision 2026-10-02). The
/// two reserved white tiles on Home are not documents and do not count.
const int kMaxFavorites = 2;

/// What a customer is told when a new favorite would go over [kMaxFavorites].
const String kFavoritesFullMessage =
    'You can keep 2 favorites. Remove one to add another.';

/// Thrown by [writeFavorite] when creating a favorite would go over
/// [kMaxFavorites]. Nothing was written. Callers show [kFavoritesFullMessage]
/// and offer to replace one ([replaceFavoriteDoc]).
class FavoritesFullException implements Exception {
  /// How many favorites the account holds now.
  final int count;
  const FavoritesFullException(this.count);

  @override
  String toString() => kFavoritesFullMessage;
}

/// Creates the favorite at [ref], or refreshes its stored look when it is
/// already there. Throws on failure — callers surface it; a swallowed error
/// here is how "saved" toasts came to sit on top of writes that never landed.
///
/// THE CAP (#164). A NEW favorite is refused with [FavoritesFullException]
/// once the account holds [kMaxFavorites]; refreshing one that exists is not
/// an add and is never refused. Every favorite is the customer's explicit
/// choice: nothing writes here on its own (the habit learner's automatic
/// favorites are gone).
Future<void> writeFavorite(
  DocumentReference<Map<String, dynamic>> ref, {
  required String patternName,
  required Map<String, dynamic> payload,
}) async {
  final snap = await ref.get();
  if (snap.exists) {
    await ref.update(buildFavoriteRefreshData(payload: payload));
    return;
  }
  final count = (await ref.parent.get()).size;
  if (count >= kMaxFavorites) throw FavoritesFullException(count);
  await ref.set(buildFavoriteCreateData(
    patternName: patternName,
    payload: payload,
  ));
}

/// Replaces the favorite [replaceId] with a new one at [ref], in ONE batch:
/// both land or neither does, so a full list never ends up one short or one
/// over. Replacing keeps the count where it was, so it is allowed even on an
/// account that holds more than [kMaxFavorites] from before the cap.
Future<void> replaceFavoriteDoc(
  DocumentReference<Map<String, dynamic>> ref, {
  required String replaceId,
  required String patternName,
  required Map<String, dynamic> payload,
}) async {
  if (replaceId == ref.id) {
    await ref.update(buildFavoriteRefreshData(payload: payload));
    return;
  }
  final batch = ref.firestore.batch();
  batch.delete(ref.parent.doc(replaceId));
  batch.set(
      ref, buildFavoriteCreateData(patternName: patternName, payload: payload));
  await batch.commit();
}
