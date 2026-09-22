/// A PER-PIXEL favorite — the Pattern Editor's Static mode, hearted.
///
/// A favorite's `pattern_data` has always been "the WLED payload to re-apply",
/// sent as ONE message. A Static look is one entry per LED: 5.4 KB for a single
/// 290-LED channel, ~11 KB for two — and `applyJson` refuses anything over
/// [kMaxApplyPayloadBytes] (4 KB; WLED itself rejects ~6 KB). So a Static
/// favorite could be stored and never re-applied, which is why the heart used
/// to decline in Static mode.
///
/// It now stores the look the way My Designs does, and applies it the way My
/// Designs does:
///
/// ```
/// pattern_data = jsonEncode({
///   on, bri, seg:[{fx:0, pal:0, col:[…≤3]}],   // a SUMMARY — see below
///   lumina_design: { …CustomDesign… },          // the picture itself
/// })
/// ```
///
/// * **`lumina_design`** is [CustomDesign.toFirestore] — the SAME map a My
///   Designs save writes, read back by the SAME [CustomDesign.fromFirestoreData]
///   — minus the two `Timestamp` fields, which JSON cannot carry and a favorite
///   does not need (it has `added_at`). No second per-pixel shape exists.
///   [applyFavoritePayloadWith] routes it through the chunked per-pixel spine.
///
/// * The design rides INSIDE the payload rather than in a sibling document
///   field on purpose: the payload is the thing that travels. Applying a
///   favorite logs it to `pattern_usage`, the habit learner copies that logged
///   payload verbatim into auto-added favorites, and the geofence trigger reads
///   `pattern_data` on its own. A sibling field would be dropped at the first
///   of those hops and leave a favorite that looks saved and lights nothing.
///
/// * The top-level `on`/`bri`/`seg` is a SUMMARY, not the look: it is what the
///   My Favorites card reads its gradient from and what usage analytics reads
///   `fx`/`col` from, both unchanged. A consumer that does not know about
///   `lumina_design` and POSTs the map raw gets an honest refusal (the map is
///   over the 4 KB ceiling for any real install) or, on a very small one, a
///   solid first colour — never a silent success with dark lights.
library;

import 'package:nexgen_command/features/design/design_models.dart';

/// Key, inside a favorite's payload, holding the per-pixel [CustomDesign].
const String kFavoriteDesignKey = 'lumina_design';

/// Thrown by a favorite's payload builder when the pattern cannot be stored
/// right now. [message] is written for the user; the heart shows it verbatim
/// instead of a bare "Failed to save favorite".
class FavoriteNotSavable implements Exception {
  final String message;
  const FavoriteNotSavable(this.message);

  @override
  String toString() => 'FavoriteNotSavable: $message';
}

/// The payload a PER-PIXEL favorite stores. [design] is the design a My Designs
/// save of the same pattern would store (`customDesignFromEditablePattern`).
Map<String, dynamic> buildPerPixelFavoritePayload(CustomDesign design) {
  final data = design.toFirestore()
    // Timestamps are not JSON; the reader defaults both.
    ..remove('created_at')
    ..remove('updated_at');
  return <String, dynamic>{
    'on': true,
    'bri': design.brightness.clamp(1, 255),
    'seg': [
      {'fx': 0, 'pal': 0, 'col': _summaryColors(design)},
    ],
    kFavoriteDesignKey: data,
  };
}

/// The per-pixel design inside a favorite's [payload], or null when it is an
/// ordinary single-message favorite. Never throws: a design that will not
/// parse reads as "not a per-pixel favorite", and the caller's single-message
/// path then refuses it by size rather than lighting something wrong.
CustomDesign? perPixelDesignOfFavorite(Map<String, dynamic> payload) {
  final raw = payload[kFavoriteDesignKey];
  if (raw is! Map) return null;
  try {
    final design =
        CustomDesign.fromFirestoreData('', Map<String, dynamic>.from(raw));
    return design.isPositional ? design : null;
  } catch (_) {
    return null;
  }
}

/// Up to three distinct colours, in the order the first lit channel shows
/// them — what the My Favorites card draws its gradient from.
List<List<int>> _summaryColors(CustomDesign design) {
  final out = <List<int>>[];
  final seen = <String>{};
  for (final ch in design.channels) {
    if (!ch.included) continue;
    for (final g in ch.colorGroups) {
      final c = g.color;
      if (c.length < 3) continue;
      final rgbw = [c[0], c[1], c[2], c.length >= 4 ? c[3] : 0];
      if (seen.add(rgbw.join(','))) out.add(rgbw);
      if (out.length == 3) return out;
    }
  }
  return out.isEmpty
      ? const [
          [0, 0, 0, 0]
        ]
      : out;
}
