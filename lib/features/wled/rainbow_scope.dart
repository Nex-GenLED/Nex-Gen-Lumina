/// Where rainbow effects are allowed to appear, and what they must send.
///
/// THE LEAK. `WledEffectsCatalog.topPickIds` carried `9 // Rainbow`, and the
/// "All" / "Any Color" filters return every rainbow-family effect for every
/// palette. Top picks are the DEFAULT list on every palette's effect selector,
/// so a Rainbow tile sat on every card in the library, unscoped. It is now
/// visible only for rainbow-scoped nodes ([isRainbowLibraryNode]).
///
/// THE COLOURS. On WLED 0.15.1 (the pinned firmware) a rainbow effect does
/// NOT ignore the palette: `Segment::color_wheel` (FX_fcn.cpp:1145) is
///
///     if (palette) return color_from_palette(pos, false, true, 0);
///
/// so with the app's derived `pal:4` ("Color Gradient" of the user's three
/// `col[]` slots) a "Rainbow" renders a scrolling gradient of the CARD's
/// colours — and a card whose swatch is the six-colour spectrum sends only
/// `take(3)` = red, orange, yellow. Only at **`pal:0`** does `color_wheel`
/// fall through to its hue wheel: red → magenta → blue → cyan → green →
/// yellow → red, the full 360° of hue in three 85-step sectors. So a genuine
/// rainbow card must send `pal:0` for rainbow-family effects
/// ([rainbowPaletteOverride]); everything else keeps the derived palette.
library;

import 'dart:ui' show Color;

import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// The spectrum a Rainbow card shows in its swatch and previews: red through
/// violet, in hue order. Six stops, not three, because the *preview* should
/// look like what `color_wheel` renders even though `col[]` can only carry
/// three of them (which is exactly why the device gets `pal:0`, not these).
const List<Color> kRainbowSpectrum = [
  Color(0xFFFF0000), // red
  Color(0xFFFF8C00), // orange
  Color(0xFFFFFF00), // yellow
  Color(0xFF00FF00), // green
  Color(0xFF0000FF), // blue
  Color(0xFF8B00FF), // violet
];

/// A node explicitly tagged `metadata: {'rainbow': true}` — the primary,
/// placement-independent signal — or one that is, or sits directly inside,
/// the Nature & Outdoors > Rainbow folder.
///
/// The folder arm exists so a card dropped into that folder later is scoped
/// without anyone remembering the tag. It names [NatureFolderIds.rainbow]; it
/// used to name a `cat_rainbow` ROOT, which no longer exists (relocated
/// 2026-09-19). Nothing else in the rainbow logic knows where the folder is.
bool isRainbowLibraryNode(LibraryNode? node) {
  if (node == null) return false;
  return node.metadata?['rainbow'] == true ||
      node.id == NatureFolderIds.rainbow ||
      node.parentId == NatureFolderIds.rainbow;
}

/// Whether [effectId] is a rainbow-family effect: the catalog's registry of
/// palette-overriding rainbow ids, or anything in its 'Rainbow' category.
bool isRainbowEffectId(int effectId) {
  if (WledEffectsCatalog.rainbowEffectIds.contains(effectId)) return true;
  return WledEffectsCatalog.getById(effectId)?.category == 'Rainbow';
}

/// The effect list a palette's selector may show. Rainbow-family effects are
/// dropped unless [rainbowScope] (the node is rainbow-scoped).
List<WledEffect> scopeRainbowEffects(
  List<WledEffect> effects, {
  required bool rainbowScope,
}) {
  if (rainbowScope) return effects;
  return effects.where((e) => !isRainbowEffectId(e.id)).toList();
}

/// `pal:0` for a rainbow-family effect applied from a Rainbow card — the hue
/// wheel, the full spectrum. `null` (keep the derived palette) otherwise.
int? rainbowPaletteOverride({
  required int effectId,
  required bool rainbowScope,
}) {
  return rainbowScope && isRainbowEffectId(effectId) ? 0 : null;
}
