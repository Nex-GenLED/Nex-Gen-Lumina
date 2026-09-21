/// How the Welcome Home geofence finds a favorite.
///
/// Geofence stores the chosen action by NAME (`geofences/welcome_home`
/// `action_name`) and resolves it against `/users/{uid}/favorites` when the
/// trigger fires. Both halves used to key on the camelCase `name` field — a
/// shape the live rule rejected on every write, so no stored favorite has ever
/// had it: the picker listed no favorites and the trigger matched none.
///
/// Both halves now read the canonical document (see `favorite_doc.dart`):
/// the name is `pattern_name`, the look is `pattern_data` (a jsonEncoded WLED
/// payload). Keeping the picker and the trigger in one file is the point — the
/// name the picker offers must be the name the trigger queries.
library;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';

/// Scenes the trigger can apply with no favorite behind them (keyword-matched
/// by `GeofenceMonitor._applyFallback`).
const List<String> kGeofenceBuiltInActions = [
  'Turn On Warm White',
  'Start Party Mode',
  'Relax',
  'Turn Off',
];

/// The favorite names the picker offers, in document order.
///
/// De-duplicated: habit-learned favorites are written with `.add()`, so two
/// documents can share a `pattern_name`, and a dropdown asserts on duplicate
/// item values.
List<String> geofenceFavoriteNames(Iterable<Map<String, dynamic>> docs) {
  final seen = <String>{};
  final names = <String>[];
  for (final data in docs) {
    final raw = data[kFavoritePatternName];
    if (raw is! String) continue;
    final name = raw.trim();
    if (name.isEmpty || !seen.add(name)) continue;
    names.add(name);
  }
  return names;
}

/// Every choice the picker shows: favorites first, then the built-in scenes a
/// favorite doesn't already name, then [saved] if it is in neither.
///
/// [saved] is kept because a dropdown's value must be exactly one of its
/// items: an account whose stored action is a built-in ("Relax"), or a
/// favorite since deleted, must still open onto a valid selection.
List<String> geofenceActionChoices({
  required List<String> favoriteNames,
  String? saved,
}) {
  final choices = <String>[...favoriteNames];
  for (final builtIn in kGeofenceBuiltInActions) {
    if (!choices.contains(builtIn)) choices.add(builtIn);
  }
  if (saved != null && saved.isNotEmpty && !choices.contains(saved)) {
    choices.add(saved);
  }
  return choices;
}

/// The WLED payload of the favorite named [actionName], or null when the user
/// has no such favorite (the caller then falls back to a built-in scene).
///
/// Not limited to one document: names can repeat (see
/// [geofenceFavoriteNames]), and a match whose payload is empty or unparseable
/// must not shadow a usable one. Throws on a Firestore failure — the caller
/// decides what a failed lookup means.
Future<Map<String, dynamic>?> lookupGeofenceFavoritePayload(
  FirebaseFirestore firestore, {
  required String uid,
  required String actionName,
}) async {
  final snap = await firestore
      .collection('users')
      .doc(uid)
      .collection('favorites')
      .where(kFavoritePatternName, isEqualTo: actionName)
      .get();
  for (final doc in snap.docs) {
    final payload = decodeFavoritePayload(doc.data()[kFavoritePatternData]);
    if (payload.isNotEmpty) return payload;
  }
  return null;
}
