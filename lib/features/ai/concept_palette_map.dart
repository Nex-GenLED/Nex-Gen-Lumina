import 'package:flutter/material.dart';

import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

/// A single color with a descriptive name.
class NamedColor {
  final String name;
  final Color color;
  const NamedColor(this.name, this.color);
}

/// A curated palette tied to a concept (mood, nature, season, activity).
class ConceptPalette {
  final String conceptId;
  final String displayName;
  final List<NamedColor> colors;
  final Set<String> keywords;
  final PatternMood? suggestedMood;
  final EnergyLevel? suggestedEnergy;

  const ConceptPalette({
    required this.conceptId,
    required this.displayName,
    required this.colors,
    required this.keywords,
    this.suggestedMood,
    this.suggestedEnergy,
  });

  /// Convenience: extract just the Color objects.
  List<Color> get colorValues => colors.map((c) => c.color).toList();

  /// Convenience: extract just the names.
  List<String> get colorNames => colors.map((c) => c.name).toList();
}

// ---------------------------------------------------------------------------
// Palette catalog
// ---------------------------------------------------------------------------

/// 30+ concept-to-color palettes for the LuminaDefaultsEngine.
///
/// These cover moods, nature, seasons, activities, and abstract themes
/// that are NOT already in [EventThemeLibrary] (events/holidays) or
/// [SportsTeamsDatabase] (teams). The [SemanticPatternMatcher] has raw
/// color combos for christmas/halloween/ocean/sunset/etc but they lack
/// descriptive names and curated variety — this file fills that gap.
class ConceptPaletteMap {
  ConceptPaletteMap._();

  // =========================================================================
  // Moods (8)
  // =========================================================================

  static const _cozy = ConceptPalette(
    conceptId: 'cozy',
    displayName: 'Cozy Cabin',
    keywords: {'cozy', 'cabin', 'snug', 'homey', 'hygge', 'warm and cozy'},
    suggestedMood: PatternMood.cozy,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Amber Glow', Color(0xFFFFB347)),
      NamedColor('Candlelight', Color(0xFFFFD89B)),
      NamedColor('Burnt Sienna', Color(0xFFCC5500)),
      NamedColor('Soft Linen', Color(0xFFFFF4E0)),
    ],
  );

  static const _romanticBlush = ConceptPalette(
    conceptId: 'romantic-blush',
    displayName: 'Romantic Blush',
    keywords: {'romantic', 'blush', 'love', 'intimate', 'date night'},
    suggestedMood: PatternMood.romantic,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Rose Petal', Color(0xFFFF6B8A)),
      NamedColor('Blush Pink', Color(0xFFFFB6C1)),
      NamedColor('Champagne', Color(0xFFF7E7CE)),
      NamedColor('Soft Mauve', Color(0xFFD4A5A5)),
      NamedColor('Pearl White', Color(0xFFFFF5EE)),
    ],
  );

  static const _zen = ConceptPalette(
    conceptId: 'zen',
    displayName: 'Zen Garden',
    keywords: {'zen', 'meditation', 'mindful', 'peaceful', 'serene', 'tranquil'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Sage Green', Color(0xFF87AE73)),
      NamedColor('Stone Gray', Color(0xFFB8B8AA)),
      NamedColor('Bamboo', Color(0xFFD4C5A9)),
      NamedColor('Still Water', Color(0xFF7FAABD)),
    ],
  );

  static const _dreamy = ConceptPalette(
    conceptId: 'dreamy',
    displayName: 'Dreamy Pastel',
    keywords: {'dreamy', 'dream', 'soft', 'pastel', 'cloud', 'floating'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Cloud Lilac', Color(0xFFC8A2C8)),
      NamedColor('Sky Rose', Color(0xFFF4C2C2)),
      NamedColor('Powder Blue', Color(0xFFB0E0E6)),
      NamedColor('Vanilla Cream', Color(0xFFFFF8DC)),
      NamedColor('Mint Mist', Color(0xFFB2F0D1)),
    ],
  );

  static const _sultry = ConceptPalette(
    conceptId: 'sultry',
    displayName: 'Sultry Night',
    keywords: {'sultry', 'sensual', 'seductive', 'lounge'},
    suggestedMood: PatternMood.romantic,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Deep Wine', Color(0xFF722F37)),
      NamedColor('Burgundy Velvet', Color(0xFF800020)),
      NamedColor('Smoky Rose', Color(0xFFC08081)),
      NamedColor('Dark Plum', Color(0xFF4B0033)),
    ],
  );

  static const _ethereal = ConceptPalette(
    conceptId: 'ethereal',
    displayName: 'Ethereal Glow',
    keywords: {'ethereal', 'angelic', 'heavenly', 'otherworldly'},
    suggestedMood: PatternMood.magical,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Moonbeam', Color(0xFFF0EDE5)),
      NamedColor('Ice Lavender', Color(0xFFE6E6FA)),
      NamedColor('Starlight Silver', Color(0xFFD0D0E0)),
      NamedColor('Opal White', Color(0xFFF8F4FF)),
      NamedColor('Pale Aqua', Color(0xFFBFE6E2)),
    ],
  );

  static const _mysterious = ConceptPalette(
    conceptId: 'mysterious',
    displayName: 'Mysterious Depths',
    keywords: {'mysterious', 'enigma', 'gothic', 'dark', 'moody'},
    suggestedMood: PatternMood.mysterious,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Midnight Purple', Color(0xFF2E0854)),
      NamedColor('Dark Emerald', Color(0xFF004B49)),
      NamedColor('Obsidian Blue', Color(0xFF0D1B2A)),
      NamedColor('Blood Moon', Color(0xFF8B0000)),
    ],
  );

  static const _vintage = ConceptPalette(
    conceptId: 'vintage',
    displayName: 'Vintage Charm',
    keywords: {'vintage', 'retro', 'antique', 'nostalgic', 'classic'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Dusty Rose', Color(0xFFDCAE96)),
      NamedColor('Antique Gold', Color(0xFFCDA434)),
      NamedColor('Faded Olive', Color(0xFF8B8B6A)),
      NamedColor('Parchment', Color(0xFFF1E9D2)),
      NamedColor('Worn Copper', Color(0xFFB87333)),
    ],
  );

  // =========================================================================
  // Nature (8)
  // =========================================================================

  static const _auroraBorealis = ConceptPalette(
    conceptId: 'aurora-borealis',
    displayName: 'Aurora Borealis',
    keywords: {'aurora', 'borealis', 'northern lights', 'arctic glow'},
    suggestedMood: PatternMood.magical,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Emerald Wave', Color(0xFF00FF87)),
      NamedColor('Cosmic Teal', Color(0xFF00CED1)),
      NamedColor('Violet Arc', Color(0xFF8B5CF6)),
      NamedColor('Arctic Blue', Color(0xFF00B4D8)),
      NamedColor('Solar Pink', Color(0xFFFF6B9D)),
    ],
  );

  static const _deepSea = ConceptPalette(
    conceptId: 'deep-sea',
    displayName: 'Deep Sea',
    keywords: {'deep sea', 'underwater', 'abyss', 'marine', 'aquatic'},
    suggestedMood: PatternMood.mysterious,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Abyssal Blue', Color(0xFF003B5C)),
      NamedColor('Bioluminescent', Color(0xFF00FFCC)),
      NamedColor('Deep Teal', Color(0xFF014D4E)),
      NamedColor('Jellyfish Glow', Color(0xFF7B68EE)),
    ],
  );

  static const _mountainMist = ConceptPalette(
    conceptId: 'mountain-mist',
    displayName: 'Mountain Mist',
    keywords: {'mountain', 'mist', 'fog', 'alpine', 'summit'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Slate Peak', Color(0xFF708090)),
      NamedColor('Cloud Cover', Color(0xFFC8D0D4)),
      NamedColor('Pine Shadow', Color(0xFF4A6741)),
      NamedColor('Morning Frost', Color(0xFFE8EDF0)),
    ],
  );

  static const _lavenderField = ConceptPalette(
    conceptId: 'lavender-field',
    displayName: 'Lavender Field',
    keywords: {'lavender', 'provence', 'herb garden', 'floral'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('French Lavender', Color(0xFF967BB6)),
      NamedColor('Wild Heather', Color(0xFFC8A2C8)),
      NamedColor('Pale Wisteria', Color(0xFFD8BFD8)),
      NamedColor('Herb Green', Color(0xFF6B8E23)),
      NamedColor('Provence Sun', Color(0xFFF5DEB3)),
    ],
  );

  static const _tropicalReef = ConceptPalette(
    conceptId: 'tropical-reef',
    displayName: 'Tropical Reef',
    keywords: {'tropical', 'reef', 'coral', 'island', 'caribbean', 'paradise'},
    suggestedMood: PatternMood.playful,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Coral Reef', Color(0xFFFF7F50)),
      NamedColor('Turquoise Lagoon', Color(0xFF40E0D0)),
      NamedColor('Tropical Lime', Color(0xFF32CD32)),
      NamedColor('Sea Foam', Color(0xFF98FB98)),
      NamedColor('Sunshine Yellow', Color(0xFFFFD700)),
    ],
  );

  static const _cherryBlossom = ConceptPalette(
    conceptId: 'cherry-blossom',
    displayName: 'Cherry Blossom',
    keywords: {'cherry blossom', 'sakura', 'hanami', 'blossom'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Sakura Pink', Color(0xFFFFB7C5)),
      NamedColor('Petal White', Color(0xFFFFF0F5)),
      NamedColor('Branch Brown', Color(0xFF8B7355)),
      NamedColor('Blossom Blush', Color(0xFFFF9EAA)),
    ],
  );

  static const _thunderstorm = ConceptPalette(
    conceptId: 'thunderstorm',
    displayName: 'Thunderstorm',
    keywords: {'thunderstorm', 'storm', 'lightning', 'thunder', 'tempest'},
    suggestedMood: PatternMood.dramatic,
    suggestedEnergy: EnergyLevel.high,
    colors: [
      NamedColor('Storm Cloud', Color(0xFF2C3E50)),
      NamedColor('Lightning Flash', Color(0xFFF0E68C)),
      NamedColor('Electric Blue', Color(0xFF7DF9FF)),
      NamedColor('Thunder Gray', Color(0xFF4A4A4A)),
    ],
  );

  static const _desertSandstone = ConceptPalette(
    conceptId: 'desert-sandstone',
    displayName: 'Desert Sandstone',
    keywords: {'desert', 'sand', 'sandstone', 'sahara', 'dune', 'arid'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Sandstone', Color(0xFFD2B48C)),
      NamedColor('Terracotta', Color(0xFFE2725B)),
      NamedColor('Desert Sun', Color(0xFFF4A460)),
      NamedColor('Canyon Red', Color(0xFFB5651D)),
      NamedColor('Sage Brush', Color(0xFFBDB76B)),
    ],
  );

  // =========================================================================
  // Seasons (5)
  // =========================================================================

  static const _springBloom = ConceptPalette(
    conceptId: 'spring-bloom',
    displayName: 'Spring Bloom',
    keywords: {'spring', 'bloom', 'blossom', 'renewal', 'fresh'},
    suggestedMood: PatternMood.playful,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Tulip Pink', Color(0xFFFF69B4)),
      NamedColor('Daffodil Yellow', Color(0xFFFFEB3B)),
      NamedColor('Fresh Leaf', Color(0xFF7CB342)),
      NamedColor('Sky Blue', Color(0xFF87CEEB)),
      NamedColor('Crocus Violet', Color(0xFF9C27B0)),
    ],
  );

  static const _summerCitrus = ConceptPalette(
    conceptId: 'summer-citrus',
    displayName: 'Summer Citrus',
    keywords: {'summer', 'citrus', 'lemon', 'lime', 'tropical summer'},
    suggestedMood: PatternMood.energetic,
    suggestedEnergy: EnergyLevel.high,
    colors: [
      NamedColor('Lemon Zest', Color(0xFFFFF44F)),
      NamedColor('Tangerine', Color(0xFFFF9966)),
      NamedColor('Lime Juice', Color(0xFFADFF2F)),
      NamedColor('Grapefruit', Color(0xFFFF6B6B)),
      NamedColor('Mint Fresh', Color(0xFF00E5A0)),
    ],
  );

  static const _autumnHarvest = ConceptPalette(
    conceptId: 'autumn-harvest',
    displayName: 'Autumn Harvest',
    keywords: {'autumn', 'fall', 'harvest', 'pumpkin', 'foliage', 'leaves'},
    suggestedMood: PatternMood.cozy,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Maple Red', Color(0xFFC0392B)),
      NamedColor('Pumpkin Orange', Color(0xFFFF8C00)),
      NamedColor('Golden Leaf', Color(0xFFDAA520)),
      NamedColor('Forest Brown', Color(0xFF5D4037)),
      NamedColor('Harvest Gold', Color(0xFFF5C518)),
    ],
  );

  static const _winterFrost = ConceptPalette(
    conceptId: 'winter-frost',
    displayName: 'Winter Frost',
    keywords: {'winter', 'frost', 'icy', 'frozen', 'snow', 'cold'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Ice Crystal', Color(0xFFE0F7FA)),
      NamedColor('Glacier Blue', Color(0xFF80DEEA)),
      NamedColor('Frost White', Color(0xFFF5F5F5)),
      NamedColor('Silver Ice', Color(0xFFC0C0C0)),
      NamedColor('Winter Violet', Color(0xFF9FA8DA)),
    ],
  );

  static const _midsummer = ConceptPalette(
    conceptId: 'midsummer',
    displayName: 'Midsummer Night',
    keywords: {'midsummer', 'solstice', 'june night', 'warm night'},
    suggestedMood: PatternMood.magical,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Firefly Gold', Color(0xFFFFD54F)),
      NamedColor('Twilight Navy', Color(0xFF1A237E)),
      NamedColor('Meadow Green', Color(0xFF66BB6A)),
      NamedColor('Warm Dusk', Color(0xFFFF8A65)),
    ],
  );

  // =========================================================================
  // Time-of-day (3)
  // =========================================================================

  static const _goldenHour = ConceptPalette(
    conceptId: 'golden-hour',
    displayName: 'Golden Hour',
    keywords: {'golden hour', 'golden', 'magic hour', 'warm glow'},
    suggestedMood: PatternMood.romantic,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Honey Gold', Color(0xFFFFB300)),
      NamedColor('Amber Light', Color(0xFFFFCA28)),
      NamedColor('Peach Horizon', Color(0xFFFFAB91)),
      NamedColor('Rose Gold', Color(0xFFB76E79)),
    ],
  );

  static const _midnight = ConceptPalette(
    conceptId: 'midnight',
    displayName: 'Midnight Blues',
    keywords: {'midnight', 'late night', 'witching hour', 'after dark'},
    suggestedMood: PatternMood.mysterious,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Midnight Blue', Color(0xFF191970)),
      NamedColor('Deep Indigo', Color(0xFF240046)),
      NamedColor('Starlight', Color(0xFFE8E8F0)),
      NamedColor('Moon Glow', Color(0xFFC9D1D9)),
    ],
  );

  static const _twilight = ConceptPalette(
    conceptId: 'twilight',
    displayName: 'Twilight Sky',
    keywords: {'twilight', 'dusk', 'evening sky', 'blue hour'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Dusk Purple', Color(0xFF6A5ACD)),
      NamedColor('Horizon Pink', Color(0xFFFF7EB3)),
      NamedColor('Evening Blue', Color(0xFF4169E1)),
      NamedColor('Fading Orange', Color(0xFFFF8C42)),
      NamedColor('Night Sky', Color(0xFF2C3E50)),
    ],
  );

  // =========================================================================
  // Activities (6)
  // =========================================================================

  static const _movieNight = ConceptPalette(
    conceptId: 'movie-night',
    displayName: 'Movie Night',
    keywords: {'movie', 'cinema', 'film', 'theater', 'popcorn', 'movie night'},
    suggestedMood: PatternMood.cozy,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Screen Blue', Color(0xFF1A237E)),
      NamedColor('Dim Amber', Color(0xFFFFB74D)),
      NamedColor('Velvet Red', Color(0xFF8B0000)),
      NamedColor('Soft Charcoal', Color(0xFF37474F)),
    ],
  );

  static const _dinnerParty = ConceptPalette(
    conceptId: 'dinner-party',
    displayName: 'Dinner Party',
    keywords: {'dinner', 'supper', 'dinner party', 'table setting', 'feast'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.low,
    colors: [
      NamedColor('Candlelit Amber', Color(0xFFFFCC80)),
      NamedColor('Burgundy Wine', Color(0xFF6D1B2A)),
      NamedColor('Ivory Linen', Color(0xFFFFF8E1)),
      NamedColor('Aged Gold', Color(0xFFBFA95F)),
    ],
  );

  static const _reading = ConceptPalette(
    conceptId: 'reading',
    displayName: 'Reading Nook',
    keywords: {'reading', 'study', 'focus', 'concentrate', 'homework', 'book'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Warm White', Color(0xFFFFF4E0)),
      NamedColor('Parchment', Color(0xFFF5E6CC)),
      NamedColor('Soft Amber', Color(0xFFFFE0B2)),
    ],
  );

  static const _gaming = ConceptPalette(
    conceptId: 'gaming',
    displayName: 'Game Room',
    keywords: {'gaming', 'game', 'gamer', 'esports', 'video game', 'game room'},
    suggestedMood: PatternMood.energetic,
    suggestedEnergy: EnergyLevel.high,
    colors: [
      NamedColor('Neon Cyan', Color(0xFF00F0FF)),
      NamedColor('Electric Purple', Color(0xFF7C4DFF)),
      NamedColor('Toxic Green', Color(0xFF39FF14)),
      NamedColor('Hot Magenta', Color(0xFFFF00FF)),
      NamedColor('Void Black', Color(0xFF0D0D0D)),
    ],
  );

  static const _yoga = ConceptPalette(
    conceptId: 'yoga',
    displayName: 'Yoga Flow',
    keywords: {'yoga', 'stretch', 'pilates', 'namaste', 'breathwork'},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Lotus Pink', Color(0xFFF8BBD0)),
      NamedColor('Earth Tone', Color(0xFFBCAAA4)),
      NamedColor('Chakra Indigo', Color(0xFF5C6BC0)),
      NamedColor('Serenity Blue', Color(0xFF81D4FA)),
    ],
  );

  static const _cocktailHour = ConceptPalette(
    conceptId: 'cocktail-hour',
    displayName: 'Cocktail Hour',
    keywords: {'cocktail', 'happy hour', 'drinks', 'bar', 'mixology'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Champagne Gold', Color(0xFFF7E7CE)),
      NamedColor('Mojito Green', Color(0xFF66BB6A)),
      NamedColor('Rosé Blush', Color(0xFFFF8A80)),
      NamedColor('Aperol Orange', Color(0xFFFF6D00)),
      NamedColor('Gin Blue', Color(0xFF80CBC4)),
    ],
  );

  // =========================================================================
  // Abstract (3)
  // =========================================================================

  static const _minimalist = ConceptPalette(
    conceptId: 'minimalist',
    displayName: 'Minimalist',
    keywords: {'minimalist', 'minimal', 'simple', 'clean', 'understated'},
    suggestedMood: PatternMood.elegant,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Pure White', Color(0xFFFFFFFF)),
      NamedColor('Warm Gray', Color(0xFFBDBDBD)),
      NamedColor('Soft Black', Color(0xFF424242)),
    ],
  );

  static const _neonNights = ConceptPalette(
    conceptId: 'neon-nights',
    displayName: 'Neon Nights',
    keywords: {'neon', 'cyberpunk', 'synthwave', 'retrowave', 'vaporwave', 'cyber'},
    suggestedMood: PatternMood.energetic,
    suggestedEnergy: EnergyLevel.high,
    colors: [
      NamedColor('Hot Pink Neon', Color(0xFFFF1493)),
      NamedColor('Electric Blue', Color(0xFF00BFFF)),
      NamedColor('Acid Green', Color(0xFF39FF14)),
      NamedColor('UV Purple', Color(0xFF9400D3)),
      NamedColor('Laser Red', Color(0xFFFF073A)),
    ],
  );

  static const _bohemian = ConceptPalette(
    conceptId: 'bohemian',
    displayName: 'Bohemian',
    keywords: {'bohemian', 'boho', 'eclectic', 'free spirit', 'wanderlust'},
    suggestedMood: PatternMood.playful,
    suggestedEnergy: EnergyLevel.medium,
    colors: [
      NamedColor('Terracotta', Color(0xFFE07A5F)),
      NamedColor('Mustard Gold', Color(0xFFE6B422)),
      NamedColor('Teal Dream', Color(0xFF3D8B8B)),
      NamedColor('Burnt Coral', Color(0xFFCD5C5C)),
      NamedColor('Sage', Color(0xFF81C784)),
    ],
  );

  // =========================================================================
  // Warm white fallback
  // =========================================================================

  static const _warmWhiteFallback = ConceptPalette(
    conceptId: 'warm-white',
    displayName: 'Warm White',
    keywords: {},
    suggestedMood: PatternMood.calm,
    suggestedEnergy: EnergyLevel.veryLow,
    colors: [
      NamedColor('Warm White', Color(0xFFFFF4E0)),
      NamedColor('Soft Amber', Color(0xFFFFE0B2)),
      NamedColor('Natural White', Color(0xFFFFFAF0)),
    ],
  );

  // =========================================================================
  // Master list
  // =========================================================================

  /// All 33 concept palettes.
  static const List<ConceptPalette> allPalettes = [
    // Moods
    _cozy, _romanticBlush, _zen, _dreamy, _sultry, _ethereal,
    _mysterious, _vintage,
    // Nature
    _auroraBorealis, _deepSea, _mountainMist, _lavenderField,
    _tropicalReef, _cherryBlossom, _thunderstorm, _desertSandstone,
    // Seasons
    _springBloom, _summerCitrus, _autumnHarvest, _winterFrost, _midsummer,
    // Time-of-day
    _goldenHour, _midnight, _twilight,
    // Activities
    _movieNight, _dinnerParty, _reading, _gaming, _yoga, _cocktailHour,
    // Abstract
    _minimalist, _neonNights, _bohemian,
  ];

  /// Safe fallback when no concept matches.
  static ConceptPalette get warmWhiteFallback => _warmWhiteFallback;

  // =========================================================================
  // Lookup
  // =========================================================================

  /// Find the best matching palette for a query string.
  ///
  /// Returns `null` if no concept palette matches. Checks multi-word keywords
  /// first (longer = more specific), then single-word keywords.
  static ConceptPalette? findForQuery(String query) {
    final normalized = query.toLowerCase().trim();

    // First pass: multi-word keyword match (more specific → higher priority)
    ConceptPalette? best;
    int bestLen = 0;
    for (final palette in allPalettes) {
      for (final kw in palette.keywords) {
        if (kw.contains(' ') && normalized.contains(kw) && kw.length > bestLen) {
          best = palette;
          bestLen = kw.length;
        }
      }
    }
    if (best != null) return best;

    // Second pass: single-word keyword match against word boundaries
    final words = normalized.split(RegExp(r'\s+'));
    for (final palette in allPalettes) {
      for (final kw in palette.keywords) {
        if (!kw.contains(' ') && words.contains(kw)) {
          return palette;
        }
      }
    }

    return null;
  }

  /// Find a palette appropriate for a given mood.
  ///
  /// Returns the first palette whose [suggestedMood] matches.
  static ConceptPalette? findForMood(PatternMood mood) {
    for (final palette in allPalettes) {
      if (palette.suggestedMood == mood) return palette;
    }
    return null;
  }
}
