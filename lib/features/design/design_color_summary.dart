// lib/features/design/design_color_summary.dart
//
// Roofline slice 3 — the COLOUR SUMMARY of a saved design, and the
// "variations base" a studio session starts from.
//
// "Variations of …" starts a new design from a saved one. Owner decisions
// 2026-11-05: variations are colour-only (no zone language until Parent
// Segment Stage 1, #108); the AI context gets ONLY the bus lengths and a
// colour summary of the saved design — never a controller id, a name, an
// address or an account identifier, because AI requests are disclosed to
// customers as shared with Anthropic; and a variation keeps the saved
// design's layout stamp so slice 2 can schedule it later.
//
// This file is the pure model: colours and shares, no names, no ids. The
// reader that derives it from a saved design (decoding the stored
// `composed_pattern` layer) is `designColorSummaryOf` in design_providers.dart.
// Pure Dart + `Color`: no Riverpod, no Firestore.

import 'dart:ui' show Color;

import 'package:nexgen_command/features/design/design_layout_stamp.dart';
import 'package:nexgen_command/features/design/design_models.dart';

/// One colour a design paints, with the share of its lights that carry it.
class DesignColorSwatch {
  /// `[r, g, b, w]`, as stored on the design.
  final List<int> rgbw;

  /// Fraction of the design's lights in this colour (0.0–1.0).
  final double share;

  const DesignColorSwatch({required this.rgbw, required this.share});

  /// The swatch as a screen colour. A pure-W light would otherwise read as
  /// black, so W is folded into the RGB as warmth (the preview's own rule).
  Color get color => colorFromRgbw(rgbw);

  @override
  String toString() => 'DesignColorSwatch($rgbw, ${(share * 100).round()}%)';
}

/// What a saved design is made of, colour-wise: the lit colours by share,
/// how much of it is unlit, and — when the design was composed by the AI
/// studio and its stored intent says so — which colour played which role.
class DesignColorSummary {
  /// Lit colours, largest share first. Empty for a design that paints nothing.
  final List<DesignColorSwatch> swatches;

  /// Fraction of the design's lights that are dark (0.0–1.0).
  final double unlitShare;

  /// The roles the AI studio's stored intent assigned, when there is one.
  /// Null fields fall back to the swatches by share.
  final Color? statedPrimary;
  final Color? statedSecondary;
  final Color? statedAccent;

  const DesignColorSummary({
    required this.swatches,
    this.unlitShare = 0,
    this.statedPrimary,
    this.statedSecondary,
    this.statedAccent,
  });

  static const empty = DesignColorSummary(swatches: []);

  bool get isEmpty => swatches.isEmpty && statedPrimary == null;

  /// The colour a variation starts from: the stated primary, else the colour
  /// most of the lights carry.
  Color? get primary =>
      statedPrimary ?? (swatches.isNotEmpty ? swatches[0].color : null);

  /// The second colour, by role or by share.
  Color? get secondary =>
      statedSecondary ?? (swatches.length > 1 ? swatches[1].color : null);

  /// The accent, by role or by share.
  Color? get accent =>
      statedAccent ?? (swatches.length > 2 ? swatches[2].color : null);

  /// The summary as lines for the AI context. Numbers only — no names, no
  /// identifiers. Shares are whole percentages.
  List<String> contextLines() {
    if (swatches.isEmpty) return const ['Colours: none lit'];
    final parts = swatches
        .map((s) => '[${s.rgbw.join(',')}] ${(s.share * 100).round()}%')
        .join(', ');
    return [
      'Colours by share of lights: $parts',
      'Unlit: ${(unlitShare * 100).round()}%',
    ];
  }

  @override
  String toString() =>
      'DesignColorSummary($swatches, unlit ${(unlitShare * 100).round()}%)';
}

/// The saved design a studio session is making variations of: the design
/// itself (for its name on screen and the layout it was composed over), its
/// colour summary, and its layout stamp — REQUIRED, because an unstamped
/// design gets no "Variations of" entry (owner decision 3).
class VariationBase {
  final CustomDesign design;
  final DesignColorSummary colors;
  final DesignLayoutStamp stamp;

  const VariationBase({
    required this.design,
    required this.colors,
    required this.stamp,
  });

  /// Bus index → LED count, from the stamp: what the variation is composed
  /// over and what it is stamped with when saved.
  Map<int, int> get busLengthsByChannel => {
        for (var i = 0; i < stamp.busLengths.length; i++) i: stamp.busLengths[i],
      };
}

/// `[r, g, b, (w)]` → a screen colour. W is folded in as warmth so a light
/// that is mostly W does not read as black (the same mix the design preview
/// draws with).
Color colorFromRgbw(List<int> rgbw) {
  if (rgbw.length < 3) return const Color(0xFF000000);
  final w = rgbw.length >= 4 ? rgbw[3].clamp(0, 255) : 0;
  int mix(int c, int warm) =>
      (c.clamp(0, 255) + warm * (w / 255.0) * 0.6).round().clamp(0, 255);
  return Color.fromARGB(255, mix(rgbw[0], 255), mix(rgbw[1], 235), mix(rgbw[2], 200));
}

/// A light whose every channel is below this reads as unlit (the paint
/// editor's base is `[10, 10, 12, 0]`).
const int kUnlitThreshold = 16;

bool isUnlitRgbw(List<int> rgbw) => rgbw.every((v) => v < kUnlitThreshold);
