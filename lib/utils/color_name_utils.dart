import 'package:flutter/painting.dart';

/// Returns an expressive color name for a given [Color] using HSL-based matching.
///
/// Examples: "Deep Navy", "Crimson", "Emerald", "Soft Lavender", "Bright Coral"
String richColorName(Color color) {
  return richColorNameFromRgb(color.red, color.green, color.blue);
}

/// Returns an expressive color name from raw RGB values.
String richColorNameFromRgb(int r, int g, int b) {
  // Special cases for near-white and near-black
  if (r > 240 && g > 240 && b > 240) return 'White';
  if (r < 15 && g < 15 && b < 15) return 'Black';

  final hsl = HSLColor.fromColor(Color.fromARGB(255, r, g, b));
  final hue = hsl.hue; // 0-360
  final sat = hsl.saturation; // 0-1
  final lit = hsl.lightness; // 0-1

  // Very low saturation = grayscale
  if (sat < 0.08) {
    if (lit > 0.85) return 'White';
    if (lit > 0.6) return 'Silver';
    if (lit > 0.35) return 'Gray';
    return 'Charcoal';
  }

  // Low saturation = muted tones
  if (sat < 0.2) {
    if (lit > 0.75) return 'Warm White';
    if (lit > 0.5) return 'Ash';
    return 'Slate';
  }

  // Find closest named color from lookup table
  double bestDist = double.infinity;
  String bestName = 'Custom';

  for (final entry in _namedColors) {
    final d = _hslDistance(hue, sat, lit, entry.hue, entry.sat, entry.lit);
    if (d < bestDist) {
      bestDist = d;
      bestName = entry.name;
    }
  }

  return bestName;
}

double _hslDistance(
  double h1, double s1, double l1,
  double h2, double s2, double l2,
) {
  // Hue is circular, so compute shortest angular distance
  double dh = (h1 - h2).abs();
  if (dh > 180) dh = 360 - dh;
  // Weight hue more heavily since it's the primary perceptual axis
  return (dh / 360) * 3.0 + (s1 - s2).abs() + (l1 - l2).abs() * 1.5;
}

class _NamedColor {
  final String name;
  final double hue;
  final double sat;
  final double lit;
  const _NamedColor(this.name, this.hue, this.sat, this.lit);
}

const _namedColors = [
  // Reds
  _NamedColor('Red', 0, 1.0, 0.50),
  _NamedColor('Crimson', 348, 0.85, 0.40),
  _NamedColor('Scarlet', 10, 0.90, 0.45),
  _NamedColor('Dark Red', 0, 0.80, 0.28),
  _NamedColor('Rose', 350, 0.70, 0.65),
  _NamedColor('Soft Pink', 340, 0.55, 0.78),
  _NamedColor('Pale Pink', 350, 0.45, 0.85),

  // Oranges
  _NamedColor('Orange', 30, 1.0, 0.50),
  _NamedColor('Bright Coral', 16, 0.85, 0.55),
  _NamedColor('Amber', 38, 0.90, 0.50),
  _NamedColor('Peach', 28, 0.70, 0.72),
  _NamedColor('Burnt Orange', 20, 0.80, 0.35),

  // Yellows
  _NamedColor('Yellow', 55, 1.0, 0.50),
  _NamedColor('Gold', 45, 0.90, 0.50),
  _NamedColor('Warm Gold', 42, 0.75, 0.45),
  _NamedColor('Lemon', 58, 0.85, 0.60),
  _NamedColor('Pale Yellow', 55, 0.60, 0.80),

  // Greens
  _NamedColor('Green', 120, 1.0, 0.40),
  _NamedColor('Emerald', 140, 0.80, 0.40),
  _NamedColor('Lime', 90, 0.85, 0.50),
  _NamedColor('Forest Green', 140, 0.65, 0.28),
  _NamedColor('Mint', 150, 0.55, 0.70),
  _NamedColor('Sage', 130, 0.30, 0.55),

  // Cyans
  _NamedColor('Cyan', 180, 1.0, 0.50),
  _NamedColor('Teal', 175, 0.70, 0.38),
  _NamedColor('Aqua', 185, 0.75, 0.60),
  _NamedColor('Turquoise', 170, 0.65, 0.50),

  // Blues
  _NamedColor('Blue', 220, 1.0, 0.50),
  _NamedColor('Deep Navy', 230, 0.80, 0.25),
  _NamedColor('Royal Blue', 225, 0.85, 0.45),
  _NamedColor('Sky Blue', 200, 0.70, 0.65),
  _NamedColor('Ice Blue', 200, 0.55, 0.78),
  _NamedColor('Electric Blue', 210, 1.0, 0.55),
  _NamedColor('Steel Blue', 210, 0.40, 0.45),

  // Purples
  _NamedColor('Purple', 280, 0.85, 0.45),
  _NamedColor('Deep Purple', 275, 0.80, 0.30),
  _NamedColor('Violet', 270, 0.75, 0.55),
  _NamedColor('Soft Lavender', 270, 0.50, 0.72),
  _NamedColor('Plum', 300, 0.50, 0.35),
  _NamedColor('Indigo', 260, 0.70, 0.38),

  // Pinks / Magentas
  _NamedColor('Magenta', 300, 1.0, 0.50),
  _NamedColor('Hot Pink', 330, 0.90, 0.55),
  _NamedColor('Fuchsia', 310, 0.85, 0.50),
  _NamedColor('Blush', 340, 0.45, 0.72),
];
