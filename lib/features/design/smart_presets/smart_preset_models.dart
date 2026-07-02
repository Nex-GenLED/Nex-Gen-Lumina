import 'package:flutter/material.dart';

/// Design Studio Slice 3 — map-driven smart presets (the first customer-facing
/// consumer of the pixel map). Human-picked, zero AI round-trip: pick a base +
/// accent color and the accent lands exactly on the mapped features.
///
/// Presets are CODE-DEFINED here (user-created presets are Slice 4+). The set
/// is extensible — add a [SmartPresetKind] + a [kSmartPresets] entry + a case
/// in the compile logic.
enum SmartPresetKind {
  /// Accent on every corner feature (±spread around the corner pixels).
  cornerAccents,

  /// Accent on the peak family (peakUp / peak / peakDown).
  peakHighlights,

  /// Accent on ALL non-run features; runs stay base.
  featureOutline,
}

/// A code-defined smart preset: base color everywhere + accent on the feature
/// set selected by [kind]. Mirrors the shape/spirit of `WhitePreset`.
@immutable
class SmartPreset {
  final String id;
  final SmartPresetKind kind;
  final String name;
  final String description;

  /// Brand-sensible defaults for the pickers (RGBW).
  final List<int> defaultBase;
  final List<int> defaultAccent;

  final IconData icon;

  const SmartPreset({
    required this.id,
    required this.kind,
    required this.name,
    required this.description,
    required this.defaultBase,
    required this.defaultAccent,
    required this.icon,
  });

  Color get baseSwatch =>
      Color.fromARGB(255, defaultBase[0], defaultBase[1], defaultBase[2]);
  Color get accentSwatch =>
      Color.fromARGB(255, defaultAccent[0], defaultAccent[1], defaultAccent[2]);
}

/// The built-in smart presets (start with three; extensible).
const List<SmartPreset> kSmartPresets = [
  SmartPreset(
    id: 'corner_accents',
    kind: SmartPresetKind.cornerAccents,
    name: 'Corner Accents',
    description: 'Warm white home with a pop of color on every corner.',
    defaultBase: [255, 147, 41, 200], // warm white
    defaultAccent: [0, 229, 255, 0], // cyan
    icon: Icons.turn_right,
  ),
  SmartPreset(
    id: 'peak_highlights',
    kind: SmartPresetKind.peakHighlights,
    name: 'Peak Highlights',
    description: 'Highlight every roof peak against a soft base.',
    defaultBase: [255, 197, 143, 220], // soft white
    defaultAccent: [255, 170, 0, 0], // amber/gold
    icon: Icons.change_history,
  ),
  SmartPreset(
    id: 'feature_outline',
    kind: SmartPresetKind.featureOutline,
    name: 'Feature Outline',
    description: 'Trace the architecture — accent on every corner, peak, and '
        'column; runs stay base.',
    defaultBase: [40, 40, 60, 0], // dim blue base
    defaultAccent: [0, 229, 255, 0], // cyan
    icon: Icons.architecture,
  ),
];

/// A small curated palette for the base/accent pickers (brand-sensible, RGBW).
const List<({String name, List<int> rgbw})> kSmartPresetPalette = [
  (name: 'Warm White', rgbw: [255, 147, 41, 200]),
  (name: 'Soft White', rgbw: [255, 197, 143, 220]),
  (name: 'Cool White', rgbw: [180, 200, 255, 245]),
  (name: 'Cyan', rgbw: [0, 229, 255, 0]),
  (name: 'Amber', rgbw: [255, 170, 0, 0]),
  (name: 'Red', rgbw: [255, 0, 0, 0]),
  (name: 'Green', rgbw: [0, 255, 0, 0]),
  (name: 'Blue', rgbw: [0, 60, 255, 0]),
  (name: 'Purple', rgbw: [160, 0, 255, 0]),
  (name: 'Pink', rgbw: [255, 40, 150, 0]),
  (name: 'Dim', rgbw: [30, 30, 40, 0]),
];
