/// How a multi-colour palette lays out on the strip when the user picks the
/// **Solid** effect — the ONE shared answer for both the preview and the
/// apply path, so the two cannot disagree again.
///
/// THE DEVICE TRUTH (WLED 0.15.1, the fleet's pinned firmware — read from the
/// firmware source, not inferred from app code, and bench-verified 2026-06-01
/// on a 128-LED segment; see memory/project_blocks_boundary_blend_fix):
///
/// Solid (fx 0) shows `col[0]` only. So every apply path that lets a user pair
/// Solid with a multi-colour palette substitutes **fx 83 "Solid Pattern"** and
/// sends **`pal:5` "Colors Only"** (`WledEffectsCatalog.paletteForEffect(83)`).
/// What fx 83 + pal 5 then renders is NOT bulb-by-bulb alternation:
///
///   * `loadPalette` case 5 (FX_fcn.cpp) builds a 16-entry palette from the
///     colour slots IN ORDER — three colours: `[c0×5, c1×5, c2×5, c0×1]`;
///     two colours: `[c0×8, c1×8]`.
///   * `mode_static_pattern` (FX.cpp) colours each lit pixel with
///     `color_from_palette(i, mapping: true, …)`, and `mapping` maps the
///     pixel's POSITION along the segment onto that palette:
///     `paletteIndex = (i*255)/(virtualLength()-1)`.
///
/// So the segment is divided into **N contiguous blocks, one per colour, in
/// `col[]` order** — thirds for three colours, halves for two. The customer
/// reports of "the roofline shows red, then white, then blue" are this. The
/// old previews cycled `colors[i % N]` per bulb and showed something the
/// hardware never does.
///
/// Known second-order terms the preview deliberately does not model:
///   * boundary blend — `ColorFromPalette(…, LINEARBLEND)` smears roughly one
///     palette entry (~1/15 of the strip) at each internal boundary;
///   * fx 83's lit/unlit banding — lit = `1 + sx` px, unlit = `1 + ix` px of
///     `col[1]`. With the tuner defaults (sx = ix = 128) every segment up to
///     129 LEDs is entirely "lit" and the blocks are exactly equal; on a
///     longer segment the middle block grows. Still contiguous, still in
///     order — never alternating.
///
/// WLED has three colour slots (`take(3)` everywhere), so N is at most 3.
///
/// Pure Dart on purpose: no Flutter, so it is unit-testable and importable by
/// the painter, the dot-row preview and the payload builder alike.
library;

/// Whether picking [effectId] with [colorCount] palette colours will be sent
/// to the device as fx 83 + pal 5 (positional blocks) instead of as-is.
///
/// Mirrors `ColorwayEffectSelectorPage._effectiveEffectId` exactly — that
/// method now delegates here. Architectural palettes keep effect 0: their
/// spacing comes from `grp`/`spc`, not from multi-colour distribution.
bool isSolidPaletteSubstitution({
  required int effectId,
  required int colorCount,
  bool isArchitectural = false,
}) {
  return effectId == 0 && colorCount > 1 && !isArchitectural;
}

/// The effect id that actually reaches the wire for a Solid selection.
int effectiveSolidEffectId({
  required int effectId,
  required int colorCount,
  bool isArchitectural = false,
}) {
  return isSolidPaletteSubstitution(
    effectId: effectId,
    colorCount: colorCount,
    isArchitectural: isArchitectural,
  )
      ? 83
      : effectId;
}

/// Which colour slot pixel [index] of a [pixelCount]-pixel strip shows under
/// fx 83 + pal 5 with [colorCount] colours: contiguous equal blocks in slot
/// order. `colorCount` is clamped to WLED's three slots; a single colour is
/// always slot 0.
///
/// Equivalent to the firmware's positional palette lookup with the wrap
/// entry cut off (`scale8(…, 240)`, the default `paletteBlend == 0`), which
/// is what makes three colours land at exact thirds rather than 5/5/6.
int solidPaletteBlockIndex(int index, int pixelCount, int colorCount) {
  final n = colorCount.clamp(1, 3);
  if (n == 1 || pixelCount <= 1) return 0;
  final i = index.clamp(0, pixelCount - 1);
  return ((i * n) ~/ pixelCount).clamp(0, n - 1);
}
