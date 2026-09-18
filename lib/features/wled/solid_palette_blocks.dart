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

// ─────────────────────────────────────────────────────────────────────────────
// Layout choice: Blocks vs Alternating
// ─────────────────────────────────────────────────────────────────────────────

/// How a multi-colour palette is laid out when the user picks Solid.
///
/// * [blocks] — fx 83 + `pal:5`: N contiguous positional blocks (thirds).
///   See the header of this file.
/// * [alternating] — repeating bands of `ledsPerColor` LEDs, cycling the
///   colours bulb-group by bulb-group. THE DEVICE TRUTH (WLED 0.15.1):
///     - 3 colours → **fx 84 `mode_tri_static_pattern`** (FX.cpp:2870):
///       `SEGCOLOR(0..2)` written directly, no palette, in runs of
///       `segSize = (intensity >> 5) + 1` VIRTUAL pixels. We send `ix:0` so
///       `segSize == 1`, and let WLED's grouping do the width.
///     - 2 colours → **fx 83 `mode_static_pattern`** with **`pal:0`**: lit run
///       `1 + sx` px of `color_from_palette(i, …)`, which at `pal 0` returns
///       `SEGCOLOR(0)` (FX_fcn.cpp:1173) — no positional mapping; unlit run
///       `1 + ix` px of `SEGCOLOR(1)`. We send `sx:0, ix:0` for 1 + 1.
///     - Width comes from **`grp`** in both cases: every virtual pixel is
///       expanded to `grouping` physical LEDs (`i = i * groupLength()`,
///       FX_fcn.cpp:831; `groupLength() = grouping + spacing`, FX.h:532). So
///       `grp = ledsPerColor` gives bands of exactly `ledsPerColor` LEDs, for
///       any width, with no fx-84 cap at 8.
///   Sending BOTH a band size (`ix`) AND `grp` multiplies them — bands of
///   N×N LEDs — which is what the Explore grid card used to do for N > 1.
enum SolidLayout { blocks, alternating }

/// The segment fields a layout needs. `null` means "leave the caller's value".
class SolidLayoutFields {
  final int fx;
  final int? pal;
  final int? sx;
  final int? ix;
  final int grp;
  const SolidLayoutFields({
    required this.fx,
    this.pal,
    this.sx,
    this.ix,
    required this.grp,
  });

  @override
  String toString() =>
      'SolidLayoutFields(fx:$fx pal:$pal sx:$sx ix:$ix grp:$grp)';
}

/// The wire fields for Solid + [colorCount] colours in [layout], with bands of
/// [ledsPerColor] LEDs for the alternating layout. One colour is plain Solid.
SolidLayoutFields solidLayoutFields({
  required SolidLayout layout,
  required int colorCount,
  required int ledsPerColor,
}) {
  final n = colorCount.clamp(1, 3);
  final grp = ledsPerColor.clamp(1, 255);
  if (n == 1) return const SolidLayoutFields(fx: 0, grp: 1);
  switch (layout) {
    case SolidLayout.blocks:
      // Positional blocks. sx/ix are irrelevant to the block layout itself
      // (see the lit/unlit note in the file header) — leave the caller's.
      return SolidLayoutFields(fx: 83, pal: 5, grp: grp);
    case SolidLayout.alternating:
      if (n >= 3) {
        return SolidLayoutFields(fx: 84, pal: 5, sx: 0, ix: 0, grp: grp);
      }
      return SolidLayoutFields(fx: 83, pal: 0, sx: 0, ix: 0, grp: grp);
  }
}

/// Which colour slot pixel [index] shows under the alternating layout with
/// bands of [ledsPerColor]: the device's `grp` expansion, cycling
/// [colorCount] slots. This is the `(i ~/ grp) % N` the dot row always drew —
/// now the ONLY case it is correct for.
int alternatingBandIndex(int index, int ledsPerColor, int colorCount) {
  final n = colorCount.clamp(1, 3);
  final w = ledsPerColor.clamp(1, 255);
  if (n == 1) return 0;
  return (index < 0 ? 0 : index) ~/ w % n;
}
