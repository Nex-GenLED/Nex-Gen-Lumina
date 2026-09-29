// lib/features/favorites/favorite_brightness.dart
//
// A favourite does not change how bright the house is — unless the customer
// saved it WITH a brightness on purpose (+110 E1, owner item B).
//
// WHY. Nearly every stored favourite carries `bri`, and nobody chose it:
//   • Explore's "Save… → Favorites" and the Favorites picker hand back the
//     design at `kHandedBackDesignBrightness` (255);
//   • the reserved whites carry `WhitePreset.toWledPayload`'s 220;
//   • the Pattern Editor heart stored its slider's starting 255;
//   • habit-learner favourites copy whatever the logged payload held.
// Applying one sent that level, so tapping a favourite jumped the house to
// 100 % — the surprise the foundation removed from Explore's Apply (P10).
//
// THE RULE. At apply time `bri` is dropped, unless the payload carries
// [kFavoriteBrightnessStatedKey]. Only a writer that knows the customer set a
// level adds that marker (today: the Pattern Editor heart, after the
// BRIGHTNESS slider was moved). Stored documents are NOT migrated or
// rewritten: an old favourite simply has no marker, so it applies at the
// house's own level.
//
// Pure Dart.

import 'package:nexgen_command/features/favorites/favorite_design_payload.dart'
    show kFavoriteDesignKey;

/// Marker inside a favourite's payload: its `bri` is a level the customer
/// chose. App-private; never sent to a controller.
const String kFavoriteBrightnessStatedKey = 'lumina_bri_stated';

/// True when [payload]'s brightness was chosen by the customer.
bool favoriteStatesBrightness(Map<String, dynamic> payload) =>
    payload[kFavoriteBrightnessStatedKey] == true;

/// [payload] with the marker set — for a writer that knows the level is the
/// customer's.
Map<String, dynamic> markFavoriteBrightnessStated(
        Map<String, dynamic> payload) =>
    <String, dynamic>{...payload, kFavoriteBrightnessStatedKey: true};

/// What applying a favourite sends: [stored] minus `bri` (unless stated) and
/// minus the app-private keys, which no controller should ever see.
///
/// The per-pixel design ([kFavoriteDesignKey]) is removed here too: it is
/// read from the STORED payload before this runs, and never belongs on the
/// wire.
Map<String, dynamic> favoritePayloadForApply(Map<String, dynamic> stored) {
  final keepBri = favoriteStatesBrightness(stored);
  return <String, dynamic>{
    for (final e in stored.entries)
      if (e.key != kFavoriteBrightnessStatedKey &&
          e.key != kFavoriteDesignKey &&
          !(e.key == 'bri' && !keepBri))
        e.key: e.value,
  };
}
