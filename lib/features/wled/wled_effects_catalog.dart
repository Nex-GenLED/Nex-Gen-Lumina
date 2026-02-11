/// Complete WLED effects catalog with metadata for all 180+ effects.
///
/// This catalog provides a centralized source of truth for all WLED effects,
/// organized by category for easy browsing in the UI.
library;

/// Describes how an effect handles colors.
enum ColorBehavior {
  /// Effect uses your selected colors as-is (solid, chase, wipe, etc.)
  usesSelectedColors,

  /// Effect animates/blends your selected colors (fade, breathe, gradient)
  blendsSelectedColors,

  /// Effect generates its own colors, ignoring your selection (rainbow, fire, etc.)
  generatesOwnColors,

  /// Effect uses a WLED palette instead of selected colors
  usesPalette,
}

/// User-friendly effect mood categories for the effect selector UI.
/// Named SelectorMood to avoid conflict with EffectMood in effect_mood_system.dart.
enum SelectorMood {
  calm,
  magical,
  party,
  flowing,
  dramatic,
  colorful,
}

/// Extension to provide display strings for SelectorMood
extension SelectorMoodDisplay on SelectorMood {
  String get displayName {
    switch (this) {
      case SelectorMood.calm:
        return 'Calm';
      case SelectorMood.magical:
        return 'Magical';
      case SelectorMood.party:
        return 'Party';
      case SelectorMood.flowing:
        return 'Flowing';
      case SelectorMood.dramatic:
        return 'Dramatic';
      case SelectorMood.colorful:
        return 'Colorful';
    }
  }

  String get icon {
    switch (this) {
      case SelectorMood.calm:
        return '〰';
      case SelectorMood.magical:
        return '✦';
      case SelectorMood.party:
        return '🎉';
      case SelectorMood.flowing:
        return '→';
      case SelectorMood.dramatic:
        return '☄';
      case SelectorMood.colorful:
        return '🌈';
    }
  }

  String get description {
    switch (this) {
      case SelectorMood.calm:
        return 'Relaxing, ambient effects';
      case SelectorMood.magical:
        return 'Twinkling, sparkling effects for celebrations';
      case SelectorMood.party:
        return 'High-energy, dynamic effects';
      case SelectorMood.flowing:
        return 'Smooth, sweeping motion';
      case SelectorMood.dramatic:
        return 'Bold, statement effects';
      case SelectorMood.colorful:
        return 'Auto-generated rainbow and color effects';
    }
  }
}

/// Extension to provide display strings for ColorBehavior
extension ColorBehaviorDisplay on ColorBehavior {
  String get displayName {
    switch (this) {
      case ColorBehavior.usesSelectedColors:
        return 'Uses Your Colors';
      case ColorBehavior.blendsSelectedColors:
        return 'Blends Your Colors';
      case ColorBehavior.generatesOwnColors:
        return 'Auto Colors';
      case ColorBehavior.usesPalette:
        return 'Uses Palette';
    }
  }

  String get shortName {
    switch (this) {
      case ColorBehavior.usesSelectedColors:
        return 'Your Colors';
      case ColorBehavior.blendsSelectedColors:
        return 'Blended';
      case ColorBehavior.generatesOwnColors:
        return 'Auto';
      case ColorBehavior.usesPalette:
        return 'Palette';
    }
  }

  String get description {
    switch (this) {
      case ColorBehavior.usesSelectedColors:
        return 'This effect displays exactly the colors you select';
      case ColorBehavior.blendsSelectedColors:
        return 'This effect smoothly transitions between your selected colors';
      case ColorBehavior.generatesOwnColors:
        return 'This effect generates its own colors (your selection is ignored)';
      case ColorBehavior.usesPalette:
        return 'This effect uses a WLED color palette';
    }
  }
}

/// Represents a single WLED effect with its metadata.
class WledEffect {
  final int id;
  final String name;
  final String category;
  final bool requires2D;
  final bool requiresAudio;
  final ColorBehavior colorBehavior;
  final bool usesColorLayout;

  const WledEffect({
    required this.id,
    required this.name,
    required this.category,
    this.requires2D = false,
    this.requiresAudio = false,
    this.colorBehavior = ColorBehavior.usesSelectedColors,
    this.usesColorLayout = false,
  });

  /// Whether this effect respects the user's color selection
  bool get usesUserColors =>
      colorBehavior == ColorBehavior.usesSelectedColors ||
      colorBehavior == ColorBehavior.blendsSelectedColors;

  /// Whether this effect overrides/ignores user's color selection
  bool get overridesColors =>
      colorBehavior == ColorBehavior.generatesOwnColors ||
      colorBehavior == ColorBehavior.usesPalette;

  /// Get the user-friendly mood category for this effect (for selector UI)
  SelectorMood get selectorMood => WledEffectsCatalog.getSelectorMood(category);
}

/// Effect category definitions for UI organization.
class EffectCategory {
  final String name;
  final String icon;
  final String description;

  const EffectCategory({
    required this.name,
    required this.icon,
    required this.description,
  });
}

/// Complete WLED effects catalog.
class WledEffectsCatalog {
  WledEffectsCatalog._();

  /// All effect categories for UI display.
  static const List<EffectCategory> categories = [
    EffectCategory(name: 'Basic', icon: '○', description: 'Solid colors, fades, and blinks'),
    EffectCategory(name: 'Wipe', icon: '→', description: 'Color wipes and sweeps'),
    EffectCategory(name: 'Chase', icon: '»', description: 'Chasing patterns'),
    EffectCategory(name: 'Scanner', icon: '◇', description: 'Scanning and lighthouse effects'),
    EffectCategory(name: 'Sparkle', icon: '✦', description: 'Twinkling and sparkle effects'),
    EffectCategory(name: 'Meteor', icon: '☄', description: 'Meteor and comet trails'),
    EffectCategory(name: 'Fire', icon: '🔥', description: 'Fire and candle effects'),
    EffectCategory(name: 'Fireworks', icon: '✸', description: 'Fireworks explosions'),
    EffectCategory(name: 'Ripple', icon: '◎', description: 'Ripple effects'),
    EffectCategory(name: 'Rainbow', icon: '🌈', description: 'Rainbow color cycles'),
    EffectCategory(name: 'Strobe', icon: '⚡', description: 'Strobe and lightning'),
    EffectCategory(name: 'Ambient', icon: '〰', description: 'Calm ambient effects'),
    EffectCategory(name: 'Noise', icon: '≋', description: 'Perlin noise effects'),
    EffectCategory(name: 'Game', icon: '⬤', description: 'Bouncing balls, tetrix, popcorn'),
    EffectCategory(name: 'Holiday', icon: '🎃', description: 'Holiday-themed effects'),
    EffectCategory(name: '2D', icon: '🔲', description: '2D matrix effects'),
    EffectCategory(name: 'Audio', icon: '🎵', description: 'Audio-reactive effects'),
  ];

  /// Complete list of all WLED effects (0-186).
  /// Skipped IDs: 48, 53, 114, 142, 151, 161, 169, 170, 171 (retired/unused).
  ///
  /// ColorBehavior classifications:
  /// - usesSelectedColors: Effect displays your colors exactly (solid, chase, wipe)
  /// - blendsSelectedColors: Effect animates/transitions between your colors (breathe, fade, gradient)
  /// - generatesOwnColors: Effect ignores your colors and generates its own (rainbow, fire, aurora)
  /// - usesPalette: Effect uses a WLED palette (palette, colorwaves, noise effects)
  static const List<WledEffect> allEffects = [
    // Basic effects
    WledEffect(id: 0, name: 'Solid', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 1, name: 'Blink', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 2, name: 'Breathe', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors),
    WledEffect(id: 5, name: 'Random Colors', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 7, name: 'Dynamic', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 8, name: 'Colorloop', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 12, name: 'Fade', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors),
    WledEffect(id: 18, name: 'Dissolve', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors),
    WledEffect(id: 19, name: 'Dissolve Rnd', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 26, name: 'Blink Rainbow', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 34, name: 'Colorful', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 35, name: 'Traffic Light', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 46, name: 'Gradient', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors, usesColorLayout: true),
    WledEffect(id: 47, name: 'Loading', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 56, name: 'Tri Fade', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors),
    WledEffect(id: 62, name: 'Oscillate', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 65, name: 'Palette', category: 'Basic', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 68, name: 'Bpm', category: 'Basic', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 83, name: 'Solid Pattern', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 84, name: 'Solid Pattern Tri', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 85, name: 'Spots', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 86, name: 'Spots Fade', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors, usesColorLayout: true),
    WledEffect(id: 98, name: 'Percent', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 100, name: 'Heartbeat', category: 'Basic', colorBehavior: ColorBehavior.blendsSelectedColors),
    WledEffect(id: 108, name: 'Sine', category: 'Basic', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 113, name: 'Washing Machine', category: 'Basic', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 117, name: 'Dynamic Smooth', category: 'Basic', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 128, name: 'Pixels', category: 'Basic', colorBehavior: ColorBehavior.usesPalette),

    // Wipe effects
    WledEffect(id: 3, name: 'Wipe', category: 'Wipe', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 4, name: 'Wipe Random', category: 'Wipe', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 6, name: 'Sweep', category: 'Wipe', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 36, name: 'Sweep Random', category: 'Wipe', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 55, name: 'Tri Wipe', category: 'Wipe', colorBehavior: ColorBehavior.usesSelectedColors),

    // Chase effects
    WledEffect(id: 13, name: 'Theater', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 14, name: 'Theater Rainbow', category: 'Chase', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 15, name: 'Running', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 16, name: 'Saw', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 27, name: 'Android', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 28, name: 'Chase', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 29, name: 'Chase Random', category: 'Chase', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 30, name: 'Chase Rainbow', category: 'Chase', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 31, name: 'Chase Flash', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 32, name: 'Chase Flash Rnd', category: 'Chase', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 37, name: 'Chase 2', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 50, name: 'Two Dots', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 52, name: 'Running Dual', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 54, name: 'Chase 3', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 64, name: 'Juggle', category: 'Chase', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 78, name: 'Railway', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 92, name: 'Sinelon', category: 'Chase', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 93, name: 'Sinelon Dual', category: 'Chase', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 94, name: 'Sinelon Rainbow', category: 'Chase', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 111, name: 'Chunchun', category: 'Chase', colorBehavior: ColorBehavior.usesSelectedColors),

    // Scanner effects
    WledEffect(id: 10, name: 'Scan', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 11, name: 'Scan Dual', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 40, name: 'Scanner', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 41, name: 'Lighthouse', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 58, name: 'ICU', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 60, name: 'Scanner Dual', category: 'Scanner', colorBehavior: ColorBehavior.usesSelectedColors),

    // Sparkle effects
    WledEffect(id: 17, name: 'Twinkle', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 20, name: 'Sparkle', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 21, name: 'Sparkle Dark', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 22, name: 'Sparkle+', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 49, name: 'Fairy', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 51, name: 'Fairytwinkle', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 74, name: 'Colortwinkles', category: 'Sparkle', colorBehavior: ColorBehavior.usesPalette, usesColorLayout: true),
    WledEffect(id: 80, name: 'Twinklefox', category: 'Sparkle', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 81, name: 'Twinklecat', category: 'Sparkle', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 87, name: 'Glitter', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 103, name: 'Solid Glitter', category: 'Sparkle', colorBehavior: ColorBehavior.usesSelectedColors, usesColorLayout: true),
    WledEffect(id: 106, name: 'Twinkleup', category: 'Sparkle', colorBehavior: ColorBehavior.usesPalette),

    // Meteor effects
    WledEffect(id: 59, name: 'Multi Comet', category: 'Meteor', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 76, name: 'Meteor', category: 'Meteor', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 77, name: 'Meteor Smooth', category: 'Meteor', colorBehavior: ColorBehavior.usesSelectedColors),

    // Fire effects - These generate their own warm/fire colors
    WledEffect(id: 45, name: 'Fire Flicker', category: 'Fire', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 66, name: 'Fire 2012', category: 'Fire', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 88, name: 'Candle', category: 'Fire', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 102, name: 'Candle Multi', category: 'Fire', colorBehavior: ColorBehavior.usesSelectedColors),

    // Fireworks effects
    WledEffect(id: 42, name: 'Fireworks', category: 'Fireworks', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 89, name: 'Fireworks Starburst', category: 'Fireworks', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 90, name: 'Fireworks 1D', category: 'Fireworks', colorBehavior: ColorBehavior.usesPalette),

    // Ripple effects
    WledEffect(id: 79, name: 'Ripple', category: 'Ripple', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 99, name: 'Ripple Rainbow', category: 'Ripple', colorBehavior: ColorBehavior.generatesOwnColors),

    // Rainbow effects - All generate rainbow colors
    WledEffect(id: 9, name: 'Rainbow', category: 'Rainbow', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 33, name: 'Rainbow Runner', category: 'Rainbow', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 63, name: 'Pride 2015', category: 'Rainbow', colorBehavior: ColorBehavior.generatesOwnColors),

    // Strobe effects
    WledEffect(id: 23, name: 'Strobe', category: 'Strobe', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 24, name: 'Strobe Rainbow', category: 'Strobe', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 25, name: 'Strobe Mega', category: 'Strobe', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 57, name: 'Lightning', category: 'Strobe', colorBehavior: ColorBehavior.usesSelectedColors),

    // Ambient effects - Many generate their own colors or use palettes
    WledEffect(id: 38, name: 'Aurora', category: 'Ambient', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 39, name: 'Stream', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 43, name: 'Rain', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 61, name: 'Stream 2', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 67, name: 'Colorwaves', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 75, name: 'Lake', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 96, name: 'Drip', category: 'Ambient', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 97, name: 'Plasma', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 101, name: 'Pacifica', category: 'Ambient', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 104, name: 'Sunrise', category: 'Ambient', colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 105, name: 'Phased', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 110, name: 'Flow', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 112, name: 'Dancing Shadows', category: 'Ambient', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 115, name: 'Blends', category: 'Ambient', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 116, name: 'TV Simulator', category: 'Ambient', colorBehavior: ColorBehavior.generatesOwnColors),

    // Noise effects - All use palettes
    WledEffect(id: 69, name: 'Fill Noise', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 70, name: 'Noise 1', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 71, name: 'Noise 2', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 72, name: 'Noise 3', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 73, name: 'Noise 4', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 107, name: 'Noise Pal', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 109, name: 'Phased Noise', category: 'Noise', colorBehavior: ColorBehavior.usesPalette),

    // Game effects
    WledEffect(id: 44, name: 'Tetrix', category: 'Game', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 91, name: 'Bouncing Balls', category: 'Game', colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 95, name: 'Popcorn', category: 'Game', colorBehavior: ColorBehavior.usesSelectedColors),

    // Holiday effects
    WledEffect(id: 82, name: 'Halloween Eyes', category: 'Holiday', colorBehavior: ColorBehavior.usesSelectedColors),

    // 2D effects (require 2D matrix) - Mixed color behaviors
    WledEffect(id: 118, name: 'Spaceships', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 119, name: 'Crazy Bees', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 120, name: 'Ghost Rider', category: '2D', requires2D: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 121, name: 'Blobs', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 122, name: 'Scrolling Text', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesSelectedColors),
    WledEffect(id: 123, name: 'Drift Rose', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 124, name: 'Distortion Waves', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 125, name: 'Soap', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 126, name: 'Octopus', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 127, name: 'Waving Cell', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 146, name: 'Noise2D', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 149, name: 'Firenoise', category: '2D', requires2D: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 150, name: 'Squared Swirl', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 152, name: 'DNA', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 153, name: 'Matrix', category: '2D', requires2D: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 154, name: 'Metaballs', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 162, name: 'Pulser', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 164, name: 'Drift', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 166, name: 'Sun Radiation', category: '2D', requires2D: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 167, name: 'Colored Bursts', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 168, name: 'Julia', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 172, name: 'Game Of Life', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 173, name: 'Tartan', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 174, name: 'Polar Lights', category: '2D', requires2D: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 176, name: 'Lissajous', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 177, name: 'Frizzles', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 178, name: 'Plasma Ball', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 179, name: 'Flow Stripe', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 180, name: 'Hiphotic', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 181, name: 'Sindots', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 182, name: 'DNA Spiral', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 183, name: 'Black Hole', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 184, name: 'Wavesins', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 186, name: 'Akemi', category: '2D', requires2D: true, colorBehavior: ColorBehavior.usesPalette),

    // Audio reactive effects - Most use palettes
    WledEffect(id: 129, name: 'Pixelwave', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 130, name: 'Juggles', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 131, name: 'Matripix', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 132, name: 'Gravimeter', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 133, name: 'Plasmoid', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 134, name: 'Puddles', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 135, name: 'Midnoise', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 136, name: 'Noisemeter', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 137, name: 'Freqwave', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 138, name: 'Freqmatrix', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 139, name: 'GEQ', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 140, name: 'Waterfall', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 141, name: 'Freqpixels', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 143, name: 'Noisefire', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.generatesOwnColors),
    WledEffect(id: 144, name: 'Puddlepeak', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 145, name: 'Noisemove', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 147, name: 'Perlin Move', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 148, name: 'Ripple Peak', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 155, name: 'Freqmap', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 156, name: 'Gravcenter', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 157, name: 'Gravcentric', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 158, name: 'Gravfreq', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 159, name: 'DJ Light', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 160, name: 'Funky Plank', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 163, name: 'Blurz', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 165, name: 'Waverly', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 175, name: 'Swirl', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
    WledEffect(id: 185, name: 'Rocktaves', category: 'Audio', requiresAudio: true, colorBehavior: ColorBehavior.usesPalette),
  ];

  /// Map of effect ID to effect for quick lookup.
  static final Map<int, WledEffect> _effectsById = {
    for (final e in allEffects) e.id: e,
  };

  /// Get effect by ID. Returns null if not found.
  static WledEffect? getById(int id) => _effectsById[id];

  /// Get effect name by ID. Returns 'Effect #id' if not found.
  static String getName(int id) => _effectsById[id]?.name ?? 'Effect #$id';

  /// Get all effects in a specific category.
  static List<WledEffect> getByCategory(String category) {
    return allEffects.where((e) => e.category == category).toList();
  }

  /// Get effects grouped by category (for UI display).
  static Map<String, List<WledEffect>> get effectsByCategory {
    final result = <String, List<WledEffect>>{};
    for (final category in categories) {
      final effects = getByCategory(category.name);
      if (effects.isNotEmpty) {
        result[category.name] = effects;
      }
    }
    return result;
  }

  /// Get only 1D effects (excludes 2D and audio-reactive).
  static List<WledEffect> get standardEffects {
    return allEffects.where((e) => !e.requires2D && !e.requiresAudio).toList();
  }

  /// Get all effect IDs suitable for pattern generation (excludes 2D/audio).
  static List<int> get standardEffectIds {
    return standardEffects.map((e) => e.id).toList();
  }

  /// Curated list of popular effects for AI pattern generation.
  /// These effects work well with custom color palettes.
  static const List<int> curatedEffectIds = [
    0,   // Solid
    1,   // Blink
    2,   // Breathe
    3,   // Wipe
    4,   // Wipe Random
    6,   // Sweep
    10,  // Scan
    11,  // Scan Dual
    12,  // Fade
    13,  // Theater
    15,  // Running
    17,  // Twinkle
    20,  // Sparkle
    21,  // Sparkle Dark
    22,  // Sparkle+
    28,  // Chase
    29,  // Chase Random
    38,  // Aurora
    40,  // Scanner
    41,  // Lighthouse
    42,  // Fireworks
    43,  // Rain
    45,  // Fire Flicker
    49,  // Fairy
    51,  // Fairytwinkle
    57,  // Lightning
    59,  // Multi Comet
    64,  // Juggle
    66,  // Fire 2012
    67,  // Colorwaves
    74,  // Colortwinkles
    75,  // Lake
    76,  // Meteor
    77,  // Meteor Smooth
    79,  // Ripple
    80,  // Twinklefox
    81,  // Twinklecat
    87,  // Glitter
    88,  // Candle
    89,  // Fireworks Starburst
    90,  // Fireworks 1D
    91,  // Bouncing Balls
    95,  // Popcorn
    96,  // Drip
    97,  // Plasma
    101, // Pacifica
    102, // Candle Multi
    103, // Solid Glitter
    104, // Sunrise
    110, // Flow
    112, // Dancing Shadows
    115, // Blends
  ];

  /// Rainbow/multicolor effects that override custom palettes.
  static const List<int> rainbowEffectIds = [
    9,   // Rainbow
    14,  // Theater Rainbow
    24,  // Strobe Rainbow
    26,  // Blink Rainbow
    30,  // Chase Rainbow
    33,  // Rainbow Runner
    63,  // Pride 2015
    94,  // Sinelon Rainbow
    99,  // Ripple Rainbow
  ];

  /// Effect-specific speed multipliers.
  /// Some effects run too fast at default speeds and need adjustment.
  /// Value < 1.0 = slower, > 1.0 = faster.
  static const Map<int, double> speedMultipliers = {
    // Very fast effects - need significant slowdown
    15: 0.4,  // Running
    76: 0.35, // Meteor
    77: 0.35, // Meteor Smooth
    79: 0.4,  // Ripple
    99: 0.4,  // Ripple Rainbow

    // Fast effects - need moderate slowdown
    10: 0.5,  // Scan
    11: 0.5,  // Scan Dual
    13: 0.5,  // Theater
    14: 0.5,  // Theater Rainbow
    17: 0.5,  // Twinkle
    28: 0.5,  // Chase
    29: 0.5,  // Chase Random
    30: 0.5,  // Chase Rainbow
    40: 0.5,  // Scanner
    64: 0.5,  // Juggle
    80: 0.5,  // Twinklefox
    81: 0.5,  // Twinklecat
    92: 0.5,  // Sinelon
    93: 0.5,  // Sinelon Dual
    94: 0.5,  // Sinelon Rainbow

    // Slightly fast effects - minor adjustment
    3: 0.6,   // Wipe
    4: 0.6,   // Wipe Random
    6: 0.6,   // Sweep
    20: 0.6,  // Sparkle
    21: 0.6,  // Sparkle Dark
    22: 0.6,  // Sparkle+
    36: 0.6,  // Sweep Random
    42: 0.6,  // Fireworks
    49: 0.6,  // Fairy
    51: 0.6,  // Fairytwinkle
    55: 0.6,  // Tri Wipe
    74: 0.6,  // Colortwinkles
    87: 0.6,  // Glitter
    89: 0.6,  // Fireworks Starburst
    90: 0.6,  // Fireworks 1D

    // Medium adjustment
    110: 0.7, // Flow
    67: 0.7,  // Colorwaves
    97: 0.7,  // Plasma
    101: 0.7, // Pacifica
  };

  /// Get adjusted speed for an effect.
  /// Takes a base speed (0-255) and returns the adjusted value.
  static int getAdjustedSpeed(int effectId, int baseSpeed) {
    final multiplier = speedMultipliers[effectId] ?? 1.0;
    return (baseSpeed * multiplier).round().clamp(1, 255);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Color Behavior Filtering
  // ─────────────────────────────────────────────────────────────────────────

  /// Get all effects that use the user's selected colors.
  static List<WledEffect> get effectsUsingSelectedColors {
    return allEffects
        .where((e) => e.colorBehavior == ColorBehavior.usesSelectedColors)
        .toList();
  }

  /// Get all effects that blend/animate the user's selected colors.
  static List<WledEffect> get effectsBlendingColors {
    return allEffects
        .where((e) => e.colorBehavior == ColorBehavior.blendsSelectedColors)
        .toList();
  }

  /// Get all effects that generate their own colors (ignoring user selection).
  static List<WledEffect> get effectsGeneratingOwnColors {
    return allEffects
        .where((e) => e.colorBehavior == ColorBehavior.generatesOwnColors)
        .toList();
  }

  /// Get all effects that use WLED palettes.
  static List<WledEffect> get effectsUsingPalette {
    return allEffects
        .where((e) => e.colorBehavior == ColorBehavior.usesPalette)
        .toList();
  }

  /// Get all effects that respect user's color selection (uses or blends).
  static List<WledEffect> get effectsRespectingUserColors {
    return allEffects.where((e) => e.usesUserColors).toList();
  }

  /// Get all effects that override/ignore user's color selection.
  static List<WledEffect> get effectsOverridingColors {
    return allEffects.where((e) => e.overridesColors).toList();
  }

  /// Get effects by color behavior.
  static List<WledEffect> getByColorBehavior(ColorBehavior behavior) {
    return allEffects.where((e) => e.colorBehavior == behavior).toList();
  }

  /// Get color behavior for an effect ID. Returns null if not found.
  static ColorBehavior? getColorBehavior(int id) => _effectsById[id]?.colorBehavior;

  /// Check if an effect uses the user's selected colors.
  static bool usesUserColors(int id) => _effectsById[id]?.usesUserColors ?? true;

  /// Check if an effect overrides/ignores user's color selection.
  static bool overridesUserColors(int id) => _effectsById[id]?.overridesColors ?? false;

  /// Get effects grouped by color behavior (for UI display).
  static Map<ColorBehavior, List<WledEffect>> get effectsByColorBehavior {
    final result = <ColorBehavior, List<WledEffect>>{};
    for (final behavior in ColorBehavior.values) {
      final effects = getByColorBehavior(behavior);
      if (effects.isNotEmpty) {
        result[behavior] = effects;
      }
    }
    return result;
  }

  /// Get standard effects (non-2D, non-audio) grouped by color behavior.
  static Map<ColorBehavior, List<WledEffect>> get standardEffectsByColorBehavior {
    final result = <ColorBehavior, List<WledEffect>>{};
    for (final behavior in ColorBehavior.values) {
      final effects = standardEffects
          .where((e) => e.colorBehavior == behavior)
          .toList();
      if (effects.isNotEmpty) {
        result[behavior] = effects;
      }
    }
    return result;
  }

  // ─────────────────────────────────────────────────────────────────────────
  // Effect Selector Mood Categories
  // ─────────────────────────────────────────────────────────────────────────

  /// Map WLED category to user-friendly selector mood.
  static SelectorMood getSelectorMood(String wledCategory) {
    switch (wledCategory) {
      case 'Basic':
      case 'Ambient':
        return SelectorMood.calm;
      case 'Sparkle':
      case 'Holiday':
        return SelectorMood.magical;
      case 'Chase':
      case 'Strobe':
      case 'Fireworks':
      case 'Game':
        return SelectorMood.party;
      case 'Wipe':
      case 'Scanner':
        return SelectorMood.flowing;
      case 'Meteor':
      case 'Fire':
        return SelectorMood.dramatic;
      case 'Rainbow':
      case 'Noise':
      case 'Ripple':
        return SelectorMood.colorful;
      default:
        return SelectorMood.calm;
    }
  }

  /// Get standard effects grouped by selector mood, sorted alphabetically within each.
  static Map<SelectorMood, List<WledEffect>> get effectsBySelectorMood {
    final result = <SelectorMood, List<WledEffect>>{};
    for (final mood in SelectorMood.values) {
      final effects = standardEffects
          .where((e) => getSelectorMood(e.category) == mood)
          .toList()
        ..sort((a, b) => a.name.compareTo(b.name));
      if (effects.isNotEmpty) {
        result[mood] = effects;
      }
    }
    return result;
  }

  /// Get selector mood for an effect ID.
  static SelectorMood? getSelectorMoodById(int id) {
    final effect = _effectsById[id];
    return effect != null ? getSelectorMood(effect.category) : null;
  }

  /// Check if an effect uses color layout (LED grouping).
  static bool effectUsesColorLayout(int id) => _effectsById[id]?.usesColorLayout ?? false;
}
