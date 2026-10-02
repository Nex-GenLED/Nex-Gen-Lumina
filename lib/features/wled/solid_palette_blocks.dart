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

// ─────────────────────────────────────────────────────────────────────────────
// Stored form (ChannelDesign.solid_layout)
// ─────────────────────────────────────────────────────────────────────────────

/// A [SolidLayout] as the snake_case name a saved design stores.
String solidLayoutToJson(SolidLayout layout) =>
    layout == SolidLayout.alternating ? 'alternating' : 'blocks';

/// Inverse of [solidLayoutToJson]. Absent or unrecognised reads as
/// [SolidLayout.blocks] — the only layout `toWledPayload` could emit before
/// the field existed, so every design saved earlier fires exactly as it did.
SolidLayout solidLayoutFromJson(Object? value) =>
    value == 'alternating' ? SolidLayout.alternating : SolidLayout.blocks;

// ─────────────────────────────────────────────────────────────────────────────
// The tuner's colour-layout card: what it shows for a selection
// ─────────────────────────────────────────────────────────────────────────────

/// What the tuner's colour-layout card shows for one selection — decided
/// here, in pure Dart, so every transition is unit-testable and the card
/// cannot drift from the rule.
///
/// THE RULE. The Static setup (Blocks | Alternating) belongs to the PALETTE:
/// it is live whenever picking Static would be substituted for this palette
/// ([isSolidPaletteSubstitution] with effect 0), whatever effect is being
/// previewed. It used to be gated on the SELECTED effect, so previewing Chase
/// or Glitter removed it — and with a motion filter hiding the Solid tile the
/// only way back was to close the card (field report, 2026-10-02). While
/// another effect is previewed the chips stay, unselected, and tapping one
/// selects Static in that layout. A preview never touches the remembered
/// layout or grouping, so returning to Static shows them again.
///
/// The "LEDs per color" row (`grp`) is Alternating's band width. Blocks lays
/// the palette out positionally and ignores it (see the file header), so the
/// row is hidden under Blocks. Every other colour-layout effect (Twinkle,
/// Glitter, Spots…) still takes its band width from `grp`, so the row stays
/// for them, and for them a tap keeps the effect.
class StaticSetupControls {
  const StaticSetupControls({
    required this.showCard,
    required this.showChips,
    required this.chipsActive,
    required this.showGrouping,
    required this.groupingReturnsToStatic,
    required this.showSpacingAndPreview,
  });

  /// Nothing — a brightness gradient has its own controls.
  static const StaticSetupControls none = StaticSetupControls(
    showCard: false,
    showChips: false,
    chipsActive: false,
    showGrouping: false,
    groupingReturnsToStatic: false,
    showSpacingAndPreview: false,
  );

  /// The whole card.
  final bool showCard;

  /// The Blocks | Alternating chips.
  final bool showChips;

  /// Static is the selected effect: the chosen chip is highlighted. Otherwise
  /// the chips show unselected and tapping one selects Static.
  final bool chipsActive;

  /// The 1–5 "LEDs per color" row.
  final bool showGrouping;

  /// Tapping a grouping number also selects Static: the row is on screen as
  /// Static setup (Alternating remembered) and the previewed effect does not
  /// use it.
  final bool groupingReturnsToStatic;

  /// The "Dark LEDs between" row and the dot-row preview. They describe the
  /// SELECTED effect, so they are shown only when it is one they describe.
  final bool showSpacingAndPreview;

  @override
  String toString() => 'StaticSetupControls(card:$showCard chips:$showChips '
      'active:$chipsActive grouping:$showGrouping '
      'groupingReturns:$groupingReturnsToStatic '
      'spacing+preview:$showSpacingAndPreview)';
}

/// The card's state for [effectId] (the selected effect) on a palette of
/// [colorCount] colours with [layout] remembered on the chip.
///
/// [effectUsesColorLayout] is the catalog's flag for [effectId]
/// (`WledEffect.usesColorLayout`): an effect whose band width is `grp`.
StaticSetupControls staticSetupControls({
  required int effectId,
  required int colorCount,
  required SolidLayout layout,
  bool isArchitectural = false,
  bool isBrightnessGradient = false,
  bool effectUsesColorLayout = false,
}) {
  if (isBrightnessGradient) return StaticSetupControls.none;
  final live = isSolidPaletteSubstitution(
    effectId: 0,
    colorCount: colorCount,
    isArchitectural: isArchitectural,
  );
  final isStatic = effectId == 0;
  final active = live && isStatic;
  // The rows below the chips describe the selected effect when it reads
  // `grp`: Static in either layout, a colour-layout effect, or an
  // architectural multi-colour Solid (its spacing IS the look).
  final describesSelected =
      active || effectUsesColorLayout || (isStatic && colorCount > 1);
  final showGrouping = active
      ? layout == SolidLayout.alternating
      : describesSelected || (live && layout == SolidLayout.alternating);
  return StaticSetupControls(
    showCard: live || describesSelected,
    showChips: live,
    chipsActive: active,
    showGrouping: showGrouping,
    groupingReturnsToStatic: showGrouping && !describesSelected,
    showSpacingAndPreview: describesSelected,
  );
}
