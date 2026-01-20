import 'package:flutter/material.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_nhl.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_mlb.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_soccer.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_other.dart';
import 'package:nexgen_command/features/patterns/sports_team_palettes_ncaa.dart';

/// Canonical theme palettes for consistent, deterministic lighting recommendations.
///
/// Each theme has:
/// - Official "canonical" colors that always appear as the primary recommendation
/// - Suggested WLED effects appropriate for the theme
/// - Style variations (subtle, bold, vintage, modern, playful)
/// - Metadata for UI display (icon, description)

/// Represents a single canonical theme with all its variations and metadata.
class CanonicalTheme {
  /// Unique identifier (lowercase, no spaces)
  final String id;

  /// Display name for UI
  final String displayName;

  /// Short description shown in UI
  final String description;

  /// Icon to display (Material Icons)
  final IconData icon;

  /// The official/canonical colors for this theme (always shown first)
  /// Using official color codes where applicable (e.g., US flag colors)
  final List<ThemeColor> canonicalColors;

  /// Suggested WLED effect IDs appropriate for this theme
  /// First effect is the "default" recommendation
  final List<int> suggestedEffects;

  /// Default speed for this theme (0-255)
  final int defaultSpeed;

  /// Default intensity for this theme (0-255)
  final int defaultIntensity;

  /// Default brightness for this theme (0-255)
  final int defaultBrightness;

  /// Style variations with adjusted palettes
  final Map<ThemeStyle, List<ThemeColor>> styleVariations;

  /// Related/alias search terms that map to this theme
  final List<String> aliases;

  /// Category for grouping (holiday, sports, mood, season)
  final ThemeCategory category;

  const CanonicalTheme({
    required this.id,
    required this.displayName,
    required this.description,
    required this.icon,
    required this.canonicalColors,
    required this.suggestedEffects,
    this.defaultSpeed = 128,
    this.defaultIntensity = 128,
    this.defaultBrightness = 200,
    this.styleVariations = const {},
    this.aliases = const [],
    required this.category,
  });

  /// Get RGB arrays for WLED payload (LED-optimized)
  List<List<int>> get canonicalRgb =>
      canonicalColors.map((c) => _optimizeForLed(c.color.red, c.color.green, c.color.blue)).toList();

  /// Get colors for a specific style, falling back to canonical (LED-optimized)
  List<List<int>> getRgbForStyle(ThemeStyle style) {
    final variation = styleVariations[style];
    if (variation != null && variation.isNotEmpty) {
      return variation.map((c) => _optimizeForLed(c.color.red, c.color.green, c.color.blue)).toList();
    }
    return canonicalRgb;
  }

  /// Optimize a color for LED display
  ///
  /// LEDs display colors differently than monitors. Key issues:
  /// 1. Reds with blue components appear pink/magenta
  /// 2. Blues with red components appear purple
  /// 3. Dark blues appear washed out - need to boost
  /// 4. White needs to stay pure
  ///
  /// This function cleans up colors to display as intended on LEDs.
  static List<int> _optimizeForLed(int r, int g, int b) {
    // ============ SPECIAL CASE: WHITE ============
    // Pure white or near-white should stay clean
    if (r > 240 && g > 240 && b > 240) {
      // Keep it as clean white - WLED will use W channel if available
      return [255, 255, 255];
    }

    // ============ SPECIAL CASE: DARK NAVY/BLUE ============
    // Dark navy blues (like Old Glory Blue 0x002868) don't display well
    // Boost them to a true visible blue
    if (b > 50 && r < 30 && g < 80 && b > r && b > g) {
      // This is a dark blue - boost it to be visible on LEDs
      // Scale up proportionally while keeping it blue-dominant
      final boostFactor = 255.0 / b;
      final newB = 255;
      final newG = (g * boostFactor * 0.3).round().clamp(0, 80); // Keep green low
      final newR = 0; // Remove any red to prevent purple
      return [newR, newG, newB];
    }

    // ============ RED-DOMINANT COLORS ============
    // Threshold for considering a channel "dominant"
    const dominantThreshold = 150;
    // Threshold for considering a channel as "noise" that should be removed
    const noiseThreshold = 50;

    // Detect if this is primarily a "red" color (high R, lower G and B)
    if (r > dominantThreshold && g < r * 0.6 && b < r * 0.6) {
      // This is a red-dominant color - remove blue noise that causes pink appearance
      // Keep some green if it's orange-ish, but remove blue
      final cleanB = 0; // Always remove blue from reds - it causes pink
      final cleanG = g > noiseThreshold ? g : 0;
      return [r, cleanG, cleanB];
    }

    // ============ ORANGE COLORS ============
    // Detect if this is primarily an "orange" color (high R, medium G, low B)
    if (r > dominantThreshold && g > 60 && g < 220 && b < noiseThreshold) {
      // Orange - ensure blue stays at zero
      return [r, g, 0];
    }

    // ============ BLUE-DOMINANT COLORS ============
    // Detect if this is primarily a "blue" color (B is highest, R and G are lower)
    if (b > 80 && b > r && b > g) {
      // Blue-dominant - remove red noise that causes purple appearance
      final cleanR = 0; // Remove red from blues
      // Keep some green for cyan/teal tones, otherwise remove
      final cleanG = (g > b * 0.5) ? g : (g > noiseThreshold ? (g * 0.5).round() : 0);
      // Boost blue if it's dark
      final boostB = b < 150 ? (b * 1.7).round().clamp(0, 255) : b;
      return [cleanR, cleanG, boostB];
    }

    // ============ GREEN-DOMINANT COLORS ============
    // Pure greens display well, but ensure they're clean
    if (g > dominantThreshold && r < g * 0.5 && b < g * 0.5) {
      return [0, g, 0]; // Pure green
    }

    // For other colors (purples, cyans, etc.), return as-is
    // These generally display well on LEDs
    return [r, g, b];
  }
}

/// A named color within a theme palette
class ThemeColor {
  final String name;
  final Color color;

  const ThemeColor(this.name, this.color);

  /// Create from hex value (0xFFRRGGBB format)
  /// Note: Not const because Color(hex) cannot be const with a parameter
  ThemeColor.hex(this.name, int hex) : color = Color(hex);
}

/// Style variations for palettes
enum ThemeStyle {
  classic,   // The canonical/default style
  subtle,    // Softer, muted tones
  bold,      // More saturated, higher contrast
  vintage,   // Retro/warm tones
  modern,    // Clean, contemporary colors
  playful,   // Bright, fun variations
}

/// Category for theme grouping
enum ThemeCategory {
  holiday,
  sports,
  mood,
  season,
  event,
}

/// Extension for style display names
extension ThemeStyleExt on ThemeStyle {
  String get displayName {
    switch (this) {
      case ThemeStyle.classic: return 'Classic';
      case ThemeStyle.subtle: return 'Subtle';
      case ThemeStyle.bold: return 'Bold';
      case ThemeStyle.vintage: return 'Vintage';
      case ThemeStyle.modern: return 'Modern';
      case ThemeStyle.playful: return 'Playful';
    }
  }

  String get description {
    switch (this) {
      case ThemeStyle.classic: return 'Traditional colors';
      case ThemeStyle.subtle: return 'Softer, muted tones';
      case ThemeStyle.bold: return 'Vivid & saturated';
      case ThemeStyle.vintage: return 'Warm, retro feel';
      case ThemeStyle.modern: return 'Clean & contemporary';
      case ThemeStyle.playful: return 'Bright & fun';
    }
  }
}

/// The canonical palette registry - single source of truth for all themes
class CanonicalPalettes {
  CanonicalPalettes._();

  /// All registered canonical themes
  static final Map<String, CanonicalTheme> _themes = {
    // ============ HOLIDAYS ============

    '4th of july': CanonicalTheme(
      id: '4th_of_july',
      displayName: '4th of July',
      description: 'Official US patriotic colors',
      icon: Icons.flag,
      category: ThemeCategory.holiday,
      // LED-optimized patriotic colors (pure red, white, true blue)
      canonicalColors: [
        ThemeColor.hex('True Red', 0xFFFF0000),
        ThemeColor.hex('White', 0xFFFFFFFF),
        ThemeColor.hex('True Blue', 0xFF0000FF),
      ],
      suggestedEffects: [52, 12, 43, 2], // Fireworks, Theater Chase, Twinkle, Breathe
      defaultSpeed: 60, // Slower default for better visual effect
      defaultIntensity: 180,
      aliases: ['july 4th', 'independence day', 'patriotic', 'usa', 'america', 'american', 'memorial day', 'veterans day'],
      styleVariations: {
        ThemeStyle.subtle: [
          ThemeColor.hex('Soft Red', 0xFFD35F5F),
          ThemeColor.hex('Cream', 0xFFF5F5F0),
          ThemeColor.hex('Navy', 0xFF1E3A5F),
        ],
        ThemeStyle.bold: [
          ThemeColor.hex('Bright Red', 0xFFFF0000),
          ThemeColor.hex('Pure White', 0xFFFFFFFF),
          ThemeColor.hex('Electric Blue', 0xFF0000FF),
        ],
        ThemeStyle.vintage: [
          ThemeColor.hex('Brick Red', 0xFF8B3A3A),
          ThemeColor.hex('Antique White', 0xFFFAEBD7),
          ThemeColor.hex('Colonial Blue', 0xFF4169E1),
        ],
      },
    ),

    'christmas': CanonicalTheme(
      id: 'christmas',
      displayName: 'Christmas',
      description: 'Classic holiday red & green',
      icon: Icons.park,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Christmas Red', 0xFFFF0000),
        ThemeColor.hex('Christmas Green', 0xFF00FF00),
        ThemeColor.hex('Gold', 0xFFFFD700),
      ],
      suggestedEffects: [12, 41, 43, 2], // Theater Chase, Running, Twinkle, Breathe
      defaultSpeed: 80,
      defaultIntensity: 180,
      aliases: ['xmas', 'holiday', 'festive', 'candy cane'],
      styleVariations: {
        ThemeStyle.subtle: [
          ThemeColor.hex('Cranberry', 0xFFDC143C),
          ThemeColor.hex('Forest Green', 0xFF228B22),
          ThemeColor.hex('Champagne', 0xFFF7E7CE),
        ],
        ThemeStyle.bold: [
          ThemeColor.hex('Bright Red', 0xFFFF0000),
          ThemeColor.hex('Lime Green', 0xFF00FF00),
          ThemeColor.hex('Bright Gold', 0xFFFFD700),
        ],
        ThemeStyle.vintage: [
          ThemeColor.hex('Burgundy', 0xFF800020),
          ThemeColor.hex('Hunter Green', 0xFF355E3B),
          ThemeColor.hex('Antique Gold', 0xFFCFB53B),
        ],
        ThemeStyle.modern: [
          ThemeColor.hex('Rose', 0xFFE34234),
          ThemeColor.hex('Emerald', 0xFF50C878),
          ThemeColor.hex('Silver', 0xFFC0C0C0),
        ],
      },
    ),

    'halloween': CanonicalTheme(
      id: 'halloween',
      displayName: 'Halloween',
      description: 'Spooky orange & purple',
      icon: Icons.nights_stay,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Pumpkin Orange', 0xFFFF8C00),
        ThemeColor.hex('Witch Purple', 0xFF800080),
        ThemeColor.hex('Slime Green', 0xFF00FF00),
      ],
      suggestedEffects: [43, 52, 37, 70], // Twinkle, Fireworks, Candle, Twinkle
      defaultSpeed: 70,
      defaultIntensity: 150,
      aliases: ['spooky', 'haunted', 'scary', 'trick or treat', 'october'],
      styleVariations: {
        ThemeStyle.subtle: [
          ThemeColor.hex('Soft Orange', 0xFFE59866),
          ThemeColor.hex('Lavender', 0xFFB19CD9),
        ],
        ThemeStyle.bold: [
          ThemeColor.hex('Electric Orange', 0xFFFF5F00),
          ThemeColor.hex('Deep Purple', 0xFF4B0082),
          ThemeColor.hex('Neon Green', 0xFF39FF14),
        ],
      },
    ),

    'valentines': CanonicalTheme(
      id: 'valentines',
      displayName: "Valentine's Day",
      description: 'Romantic pinks & reds',
      icon: Icons.favorite,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Hot Pink', 0xFFFF69B4),
        ThemeColor.hex('True Red', 0xFFFF0000),
        ThemeColor.hex('Blush Pink', 0xFFFFB6C1),
      ],
      suggestedEffects: [2, 0, 13, 70], // Breathe, Solid, Fade, Twinkle
      defaultSpeed: 50,
      defaultIntensity: 128,
      aliases: ['valentine', 'romance', 'romantic', 'love', 'heart'],
      styleVariations: {
        ThemeStyle.subtle: [
          ThemeColor.hex('Dusty Rose', 0xFFDCAE96),
          ThemeColor.hex('Soft Pink', 0xFFFFD1DC),
        ],
        ThemeStyle.bold: [
          ThemeColor.hex('Magenta', 0xFFFF00FF),
          ThemeColor.hex('Crimson', 0xFFDC143C),
        ],
      },
    ),

    'st patricks': CanonicalTheme(
      id: 'st_patricks',
      displayName: "St. Patrick's Day",
      description: 'Lucky Irish greens',
      icon: Icons.eco,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Shamrock Green', 0xFF00FF00),
        ThemeColor.hex('Kelly Green', 0xFF4CBB17),
        ThemeColor.hex('Gold', 0xFFFFD700),
      ],
      suggestedEffects: [2, 41, 70, 0], // Breathe, Running, Twinkle, Solid
      defaultSpeed: 80,
      defaultIntensity: 150,
      aliases: ['st patrick', 'irish', 'shamrock', 'leprechaun', 'march'],
      styleVariations: {
        ThemeStyle.subtle: [
          ThemeColor.hex('Sage', 0xFF9DC183),
          ThemeColor.hex('Mint', 0xFF98FF98),
        ],
        ThemeStyle.bold: [
          ThemeColor.hex('Neon Green', 0xFF39FF14),
          ThemeColor.hex('Emerald', 0xFF50C878),
        ],
      },
    ),

    'easter': CanonicalTheme(
      id: 'easter',
      displayName: 'Easter',
      description: 'Soft spring pastels',
      icon: Icons.egg,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Easter Pink', 0xFFFFB6C1),
        ThemeColor.hex('Easter Blue', 0xFFADD8E6),
        ThemeColor.hex('Easter Yellow', 0xFFFFFACD),
        ThemeColor.hex('Easter Lavender', 0xFFE6E6FA),
      ],
      suggestedEffects: [2, 13, 70, 0], // Breathe, Fade, Twinkle, Solid
      defaultSpeed: 60,
      defaultIntensity: 128,
      aliases: ['spring holiday', 'pastel', 'bunny'],
    ),

    'thanksgiving': CanonicalTheme(
      id: 'thanksgiving',
      displayName: 'Thanksgiving',
      description: 'Warm autumn harvest',
      icon: Icons.restaurant,
      category: ThemeCategory.holiday,
      canonicalColors: [
        ThemeColor.hex('Pumpkin', 0xFFFF7518),
        ThemeColor.hex('Harvest Gold', 0xFFDA9100),
        ThemeColor.hex('Cranberry', 0xFF9F000F),
        ThemeColor.hex('Brown', 0xFF8B4513),
      ],
      suggestedEffects: [37, 2, 0, 13], // Candle, Breathe, Solid, Fade
      defaultSpeed: 60,
      defaultIntensity: 150,
      aliases: ['harvest', 'autumn holiday', 'fall holiday', 'turkey day'],
    ),

    // ============ SPORTS TEAMS ============
    // Sports teams are loaded from dedicated palette files via _allSportsTeams getter

    // ============ MOODS ============

    'romantic': CanonicalTheme(
      id: 'romantic',
      displayName: 'Romantic',
      description: 'Soft, warm ambiance',
      icon: Icons.favorite_border,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Soft Pink', 0xFFFFB6C1),
        ThemeColor.hex('Rose', 0xFFFF6B6B),
        ThemeColor.hex('Warm White', 0xFFFFF8DC),
      ],
      suggestedEffects: [2, 0, 37, 13], // Breathe, Solid, Candle, Fade
      defaultSpeed: 50,
      defaultIntensity: 128,
      defaultBrightness: 150,
      aliases: ['romance', 'love', 'intimate', 'date night'],
    ),

    'relaxing': CanonicalTheme(
      id: 'relaxing',
      displayName: 'Relaxing',
      description: 'Calm, soothing tones',
      icon: Icons.spa,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Warm Amber', 0xFFFFB347),
        ThemeColor.hex('Soft White', 0xFFFFF8DC),
      ],
      suggestedEffects: [0, 2, 13], // Solid, Breathe, Fade
      defaultSpeed: 40,
      defaultIntensity: 100,
      defaultBrightness: 150,
      aliases: ['relax', 'calm', 'chill', 'peaceful', 'zen', 'meditation'],
    ),

    'party': CanonicalTheme(
      id: 'party',
      displayName: 'Party',
      description: 'Energetic & colorful',
      icon: Icons.celebration,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Hot Pink', 0xFFFF69B4),
        ThemeColor.hex('Electric Blue', 0xFF00FFFF),
        ThemeColor.hex('Lime', 0xFF32CD32),
        ThemeColor.hex('Purple', 0xFF9400D3),
      ],
      suggestedEffects: [52, 43, 72, 41], // Fireworks, Twinkle, Sparkle, Running
      defaultSpeed: 100, // Moderate base speed - effect multipliers will adjust
      defaultIntensity: 200,
      aliases: ['celebration', 'fun', 'disco', 'dance', 'rave'],
    ),

    'rainbow': CanonicalTheme(
      id: 'rainbow',
      displayName: 'Rainbow',
      description: 'Full spectrum colors',
      icon: Icons.looks,
      category: ThemeCategory.mood,
      canonicalColors: [
        // Rainbow colors (note: these will be overridden by rainbow effects)
        ThemeColor.hex('Red', 0xFFFF0000),
        ThemeColor.hex('Orange', 0xFFFF8C00),
        ThemeColor.hex('Yellow', 0xFFFFFF00),
        ThemeColor.hex('Green', 0xFF00FF00),
        ThemeColor.hex('Blue', 0xFF0000FF),
        ThemeColor.hex('Purple', 0xFF8B00FF),
      ],
      // Rainbow effects that cycle through the full color spectrum
      suggestedEffects: [9, 10, 66, 96], // Rainbow, Rainbow Cycle, Chase Rainbow, Ripple Rainbow
      defaultSpeed: 128,
      defaultIntensity: 200,
      aliases: ['multicolor', 'multi-color', 'spectrum', 'colorful', 'all colors', 'pride colors'],
    ),

    'ocean': CanonicalTheme(
      id: 'ocean',
      displayName: 'Ocean',
      description: 'Calming sea colors',
      icon: Icons.waves,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Deep Sea', 0xFF006994),
        ThemeColor.hex('Turquoise', 0xFF40E0D0),
        ThemeColor.hex('Seafoam', 0xFF98FF98),
      ],
      suggestedEffects: [110, 2, 95, 13], // Flow, Breathe, Ripple, Fade
      defaultSpeed: 70,
      defaultIntensity: 140,
      aliases: ['sea', 'beach', 'coastal', 'underwater', 'aqua', 'marine'],
    ),

    'sunset': CanonicalTheme(
      id: 'sunset',
      displayName: 'Sunset',
      description: 'Warm evening glow',
      icon: Icons.wb_twilight,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Sunset Orange', 0xFFFF6B35),
        ThemeColor.hex('Coral Pink', 0xFFFF7F7F),
        ThemeColor.hex('Golden', 0xFFFFD700),
        ThemeColor.hex('Purple Dusk', 0xFF8B5CF6),
      ],
      suggestedEffects: [2, 110, 13, 0], // Breathe, Flow, Fade, Solid
      defaultSpeed: 60,
      defaultIntensity: 150,
      aliases: ['dusk', 'twilight', 'golden hour', 'evening'],
    ),

    'neon': CanonicalTheme(
      id: 'neon',
      displayName: 'Neon',
      description: 'Vibrant electric glow',
      icon: Icons.flash_on,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Neon Pink', 0xFFFF10F0),
        ThemeColor.hex('Electric Blue', 0xFF00FFFF),
        ThemeColor.hex('Neon Green', 0xFF39FF14),
      ],
      suggestedEffects: [65, 41, 72, 1], // Chase, Running, Sparkle, Blink
      defaultSpeed: 120, // Energetic but controlled - effect multipliers will adjust
      defaultIntensity: 220,
      aliases: ['electric', 'cyberpunk', 'synthwave', 'retro'],
    ),

    'elegant': CanonicalTheme(
      id: 'elegant',
      displayName: 'Elegant',
      description: 'Sophisticated & refined',
      icon: Icons.diamond,
      category: ThemeCategory.mood,
      canonicalColors: [
        ThemeColor.hex('Warm White', 0xFFFFF8E7),
        ThemeColor.hex('Champagne Gold', 0xFFF7E7CE),
        ThemeColor.hex('Pearl', 0xFFF0EAD6),
      ],
      suggestedEffects: [0, 2, 13, 37], // Solid, Breathe, Fade, Candle
      defaultSpeed: 40,
      defaultIntensity: 100,
      defaultBrightness: 180,
      aliases: ['sophisticated', 'classy', 'fancy', 'upscale', 'refined'],
    ),

    // ============ SEASONS ============

    'spring': CanonicalTheme(
      id: 'spring',
      displayName: 'Spring',
      description: 'Fresh blooming colors',
      icon: Icons.local_florist,
      category: ThemeCategory.season,
      canonicalColors: [
        ThemeColor.hex('Cherry Blossom', 0xFFFFB7C5),
        ThemeColor.hex('Fresh Green', 0xFF90EE90),
        ThemeColor.hex('Sky Blue', 0xFF87CEEB),
        ThemeColor.hex('Lavender', 0xFFE6E6FA),
      ],
      suggestedEffects: [2, 70, 13, 0], // Breathe, Twinkle, Fade, Solid
      defaultSpeed: 70,
      defaultIntensity: 140,
      aliases: ['springtime', 'bloom', 'april', 'may'],
    ),

    'summer': CanonicalTheme(
      id: 'summer',
      displayName: 'Summer',
      description: 'Bright sunny vibes',
      icon: Icons.wb_sunny,
      category: ThemeCategory.season,
      canonicalColors: [
        ThemeColor.hex('Sunshine Yellow', 0xFFFFD700),
        ThemeColor.hex('Tropical Orange', 0xFFFF8C00),
        ThemeColor.hex('Palm Green', 0xFF32CD32),
        ThemeColor.hex('Ocean Blue', 0xFF00CED1),
      ],
      suggestedEffects: [110, 41, 72, 0], // Flow, Running, Sparkle, Solid
      defaultSpeed: 100,
      defaultIntensity: 180,
      aliases: ['summertime', 'tropical', 'beach', 'june', 'july', 'august'],
    ),

    'autumn': CanonicalTheme(
      id: 'autumn',
      displayName: 'Autumn',
      description: 'Warm fall foliage',
      icon: Icons.park,
      category: ThemeCategory.season,
      canonicalColors: [
        ThemeColor.hex('Burnt Orange', 0xFFCC5500),
        ThemeColor.hex('Maple Red', 0xFFB22222),
        ThemeColor.hex('Golden Yellow', 0xFFDAA520),
        ThemeColor.hex('Brown', 0xFF8B4513),
      ],
      suggestedEffects: [37, 2, 13, 70], // Candle, Breathe, Fade, Twinkle
      defaultSpeed: 60,
      defaultIntensity: 150,
      aliases: ['fall', 'harvest', 'october', 'november', 'leaves'],
    ),

    'winter': CanonicalTheme(
      id: 'winter',
      displayName: 'Winter',
      description: 'Cool icy tones',
      icon: Icons.ac_unit,
      category: ThemeCategory.season,
      canonicalColors: [
        ThemeColor.hex('Ice Blue', 0xFFAFEEEE),
        ThemeColor.hex('Snow White', 0xFFFFFAFA),
        ThemeColor.hex('Frost', 0xFFE0FFFF),
        ThemeColor.hex('Silver', 0xFFC0C0C0),
      ],
      suggestedEffects: [70, 72, 2, 0], // Twinkle, Sparkle, Breathe, Solid
      defaultSpeed: 60,
      defaultIntensity: 140,
      aliases: ['wintertime', 'snow', 'frost', 'ice', 'december', 'january', 'february'],
    ),
  };

  /// All sports team themes from dedicated files
  static Map<String, CanonicalTheme>? _sportsTeamsCache;

  static Map<String, CanonicalTheme> get _allSportsTeams {
    if (_sportsTeamsCache != null) return _sportsTeamsCache!;

    _sportsTeamsCache = {
      // NFL Teams
      ...SportsTeamPalettes.nflTeams,
      // NBA Teams
      ...SportsTeamPalettes.nbaTeams,
      // NHL Teams
      ...NhlTeamPalettes.nhlTeams,
      // MLB Teams
      ...MlbTeamPalettes.mlbTeams,
      // MLS Teams
      ...SoccerTeamPalettes.mlsTeams,
      // NWSL Teams
      ...SoccerTeamPalettes.nwslTeams,
      // UFL Teams
      ...OtherLeaguesPalettes.uflTeams,
      // WNBA Teams
      ...OtherLeaguesPalettes.wnbaTeams,
      // NCAA Football Teams
      ...NcaaTeamPalettes.ncaaFootballTeams,
    };

    return _sportsTeamsCache!;
  }

  /// Combined themes map (base + sports)
  static Map<String, CanonicalTheme>? _allThemesCache;

  static Map<String, CanonicalTheme> get _allThemes {
    if (_allThemesCache != null) return _allThemesCache!;

    _allThemesCache = {
      ..._themes,
      ..._allSportsTeams,
    };

    return _allThemesCache!;
  }

  /// Get all registered themes
  static List<CanonicalTheme> get allThemes => _allThemes.values.toList();

  /// Get themes by category
  static List<CanonicalTheme> getByCategory(ThemeCategory category) =>
      _allThemes.values.where((t) => t.category == category).toList();

  /// Find a theme by exact ID or alias match
  static CanonicalTheme? findTheme(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return null;

    final themes = _allThemes;

    // 1. Exact ID match
    if (themes.containsKey(q)) {
      return themes[q];
    }

    // 2. Check aliases for exact match
    for (final theme in themes.values) {
      if (theme.aliases.contains(q)) {
        return theme;
      }
    }

    // 3. Partial match on ID
    for (final entry in themes.entries) {
      if (q.contains(entry.key) || entry.key.contains(q)) {
        return entry.value;
      }
    }

    // 4. Partial match on aliases
    for (final theme in themes.values) {
      for (final alias in theme.aliases) {
        if (q.contains(alias) || alias.contains(q)) {
          return theme;
        }
      }
    }

    return null;
  }

  /// Find multiple themes that match a query (for search suggestions)
  static List<CanonicalTheme> searchThemes(String query, {int limit = 5}) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [];

    final themes = _allThemes;

    // Score-based matching
    final scores = <CanonicalTheme, int>{};

    for (final theme in themes.values) {
      int score = 0;

      // Exact ID match = highest score
      if (theme.id == q) score += 100;

      // ID contains query
      if (theme.id.contains(q)) score += 50;

      // Display name contains query
      if (theme.displayName.toLowerCase().contains(q)) score += 40;

      // Exact alias match
      if (theme.aliases.contains(q)) score += 80;

      // Alias contains query
      for (final alias in theme.aliases) {
        if (alias.contains(q)) score += 30;
        if (q.contains(alias)) score += 25;
      }

      if (score > 0) {
        scores[theme] = score;
      }
    }

    // Sort by score descending
    final sorted = scores.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    return sorted.take(limit).map((e) => e.key).toList();
  }

  /// Get the canonical palette for a query, with optional style variation
  static CanonicalPaletteResult? getPalette(String query, {ThemeStyle style = ThemeStyle.classic}) {
    final theme = findTheme(query);
    if (theme == null) return null;

    return CanonicalPaletteResult(
      theme: theme,
      colors: style == ThemeStyle.classic ? theme.canonicalRgb : theme.getRgbForStyle(style),
      style: style,
      suggestedEffectId: theme.suggestedEffects.isNotEmpty ? theme.suggestedEffects.first : 0,
    );
  }
}

/// Result from palette lookup
class CanonicalPaletteResult {
  final CanonicalTheme theme;
  final List<List<int>> colors;
  final ThemeStyle style;
  final int suggestedEffectId;

  const CanonicalPaletteResult({
    required this.theme,
    required this.colors,
    required this.style,
    required this.suggestedEffectId,
  });
}
