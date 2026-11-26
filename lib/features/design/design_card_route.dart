// lib/features/design/design_card_route.dart
//
// Build 132 — which screen a saved design opens on from My Designs.
//
// The card page (`ColorwayEffectSelectorPage.forDesign`) is the live tuner an
// Explore card opens: effect, speed, intensity and spacing, with Apply and
// "Save to design". Until build 131 only a design saved from the Pattern Editor
// opened it; every other saved design opened the detail screen, even a plain
// effect the card page shows perfectly well.
//
// The card page reads ONE look — the first included channel's effect, speed,
// intensity and spacing — and its "Save to design" writes that one look back
// to EVERY included channel. So it may only open a design whose channels
// already share one look; anything else would be flattened by a save.

import 'package:nexgen_command/features/design/design_models.dart';

/// True when [design] has at least one included channel and every included
/// channel shows the same look.
///
/// Compared, exactly as stored:
///   * colours — each colour group's colour values (RGB or RGBW, as stored)
///     and its own brightness, in order. NOT the LEDs a group covers: in an
///     effect design a group is a colour slot, and Now Playing writes each
///     one across its whole channel, so two channels of different lengths
///     would otherwise never match;
///   * effect, speed, intensity, direction (`reverse`), grouping, spacing;
///   * the Solid layout (Blocks | Alternating) — only when the effect is
///     Solid (fx 0), the one case where it changes what is sent.
///
/// Not compared: channel name, LED count, and channels left out of the
/// design (`included: false`), which are never sent.
bool channelsShareOneLook(CustomDesign design) {
  final included = [
    for (final c in design.channels)
      if (c.included) c,
  ];
  if (included.isEmpty) return false;
  final first = included.first;
  for (final c in included.skip(1)) {
    if (!_sameLook(first, c)) return false;
  }
  return true;
}

/// Whether a saved design opens on the card page rather than the detail
/// screen.
///
/// The card page when ALL of these hold:
///   * not positional — not painted, not a per-pixel picture
///     ([CustomDesign.isPositional]);
///   * not an AI design ([CustomDesign.composedPattern] is null; such a
///     design is positional anyway, stated here so the rule reads whole);
///   * every included channel shares one look ([channelsShareOneLook]);
///   * the look is an effect (fx ≠ 0) — or the design was saved from the
///     Pattern Editor ([kPatternEditorDesignTag]), whose Static patterns have
///     opened the card page since item C and still do.
///
/// Everything else — channels that differ, painted, AI, a Solid colour —
/// keeps the detail screen.
bool designOpensOnCardPage(CustomDesign design) {
  if (design.isPositional || design.composedPattern != null) return false;
  if (!channelsShareOneLook(design)) return false;
  final fx = design.channels.firstWhere((c) => c.included).effectId;
  return fx != 0 || design.tags.contains(kPatternEditorDesignTag);
}

bool _sameLook(ChannelDesign a, ChannelDesign b) {
  if (a.effectId != b.effectId ||
      a.speed != b.speed ||
      a.intensity != b.intensity ||
      a.reverse != b.reverse ||
      a.grouping != b.grouping ||
      a.spacing != b.spacing) {
    return false;
  }
  if (a.effectId == 0 && a.solidLayout != b.solidLayout) return false;
  if (a.colorGroups.length != b.colorGroups.length) return false;
  for (var i = 0; i < a.colorGroups.length; i++) {
    final ga = a.colorGroups[i];
    final gb = b.colorGroups[i];
    if (ga.bri != gb.bri || !_sameValues(ga.color, gb.color)) return false;
  }
  return true;
}

bool _sameValues(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
