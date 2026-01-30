/// Comprehensive WLED Effect Database
///
/// This database maps all WLED effects to rich metadata including:
/// - Whether the effect respects segment colors or overrides them
/// - Mood and vibe categorization
/// - Motion type and energy level
/// - Recommended speed/intensity ranges
///
/// CRITICAL: Effects marked as `respectsColors: false` will override the
/// user's chosen color palette with their own colors (e.g., rainbow effects).
/// These should ONLY be recommended when the user explicitly requests
/// rainbow/multicolor effects, NOT for themed patterns.

import 'package:flutter/material.dart';

/// Motion types for categorizing how effects animate
enum MotionType {
  /// No movement - static display
  static,

  /// Gentle pulsing/breathing - fades in and out
  pulsing,

  /// Smooth flowing motion - like water or waves
  flowing,

  /// Dots or segments moving in one direction
  chasing,

  /// Random sparkles or twinkles
  twinkling,

  /// Sudden bursts or flashes
  explosive,

  /// Scanning back and forth
  scanning,

  /// Dripping or falling motion
  dripping,

  /// Flickering like flames
  flickering,

  /// Bouncing motion
  bouncing,

  /// Morphing/color-shifting
  morphing,
}

/// Energy levels for mood matching
enum EnergyLevel {
  /// Very calm - meditation, sleep, relaxation
  veryLow,

  /// Calm - evening ambiance, romantic
  low,

  /// Moderate - everyday lighting, casual
  medium,

  /// Energetic - parties, celebrations
  high,

  /// Very energetic - raves, sports events
  veryHigh,

  /// Variable - effect has dynamic energy changes
  dynamic,
}

/// Mood categories for semantic matching
enum EffectMoodCategory {
  /// Calm, peaceful, relaxing
  calm,

  /// Romantic, intimate, warm
  romantic,

  /// Elegant, sophisticated, classy
  elegant,

  /// Festive, celebratory, party
  festive,

  /// Mysterious, dramatic, intense
  mysterious,

  /// Playful, fun, whimsical
  playful,

  /// Magical, enchanting, fairy-tale
  magical,

  /// Natural, organic, earthy
  natural,

  /// Modern, tech, futuristic
  modern,

  /// Cozy, warm, inviting
  cozy,
}

/// Vibe descriptors for fine-grained matching
enum EffectVibe {
  serene,
  dreamy,
  intimate,
  luxurious,
  joyful,
  exciting,
  spooky,
  whimsical,
  majestic,
  tranquil,
  vibrant,
  subtle,
  bold,
  gentle,
  dynamic,
  magical,
}

/// Comprehensive metadata for a single WLED effect
class EffectMetadata {
  /// WLED effect ID (fx value)
  final int id;

  /// Display name
  final String name;

  /// Human-readable description of the effect
  final String description;

  /// CRITICAL: Does this effect use the segment colors (col array)?
  /// If false, the effect generates its own colors (rainbow, palette-based)
  /// and will IGNORE any colors the user selects.
  final bool respectsColors;

  /// If respectsColors is false, what colors does this effect produce?
  /// Used to recommend these effects only when matching colors are requested.
  final List<String>? inherentColorDescription;

  /// Primary mood categories this effect fits
  final Set<EffectMoodCategory> moods;

  /// Vibe descriptors
  final Set<EffectVibe> vibes;

  /// How the effect moves
  final MotionType motionType;

  /// Energy level of the effect
  final EnergyLevel energyLevel;

  /// Minimum recommended speed (0-255)
  final int minSpeed;

  /// Maximum recommended speed (0-255)
  final int maxSpeed;

  /// Default recommended speed
  final int defaultSpeed;

  /// Minimum recommended intensity (0-255)
  final int minIntensity;

  /// Maximum recommended intensity (0-255)
  final int maxIntensity;

  /// Default recommended intensity
  final int defaultIntensity;

  /// Best for these occasions/contexts
  final Set<String> bestForOccasions;

  /// Avoid for these occasions (would feel wrong)
  final Set<String> avoidForOccasions;

  const EffectMetadata({
    required this.id,
    required this.name,
    required this.description,
    required this.respectsColors,
    this.inherentColorDescription,
    required this.moods,
    required this.vibes,
    required this.motionType,
    required this.energyLevel,
    this.minSpeed = 0,
    this.maxSpeed = 255,
    this.defaultSpeed = 128,
    this.minIntensity = 0,
    this.maxIntensity = 255,
    this.defaultIntensity = 128,
    this.bestForOccasions = const {},
    this.avoidForOccasions = const {},
  });

  /// Check if this effect is suitable for a given mood
  bool matchesMood(EffectMoodCategory mood) => moods.contains(mood);

  /// Check if this effect is suitable for given moods (any match)
  bool matchesAnyMood(Set<EffectMoodCategory> targetMoods) =>
      moods.intersection(targetMoods).isNotEmpty;

  /// Check if this effect has a specific vibe
  bool hasVibe(EffectVibe vibe) => vibes.contains(vibe);

  /// Get a speed value within the recommended range
  int clampSpeed(int speed) => speed.clamp(minSpeed, maxSpeed);

  /// Get an intensity value within the recommended range
  int clampIntensity(int intensity) => intensity.clamp(minIntensity, maxIntensity);
}

/// The comprehensive WLED effect database
///
/// This database includes all standard WLED effects with rich metadata.
/// Effects are categorized by:
/// - Whether they respect user colors (CRITICAL for themed lighting)
/// - Mood and vibe for semantic matching
/// - Motion type and energy level
/// - Recommended parameter ranges
class EffectDatabase {
  EffectDatabase._();

  /// All effects indexed by ID
  static const Map<int, EffectMetadata> effects = {
    // ═══════════════════════════════════════════════════════════════════════
    // STATIC / SOLID EFFECTS (respect colors)
    // ═══════════════════════════════════════════════════════════════════════
    0: EffectMetadata(
      id: 0,
      name: 'Solid',
      description: 'Static solid color with no animation',
      respectsColors: true,
      moods: {EffectMoodCategory.calm, EffectMoodCategory.elegant, EffectMoodCategory.cozy},
      vibes: {EffectVibe.serene, EffectVibe.subtle, EffectVibe.tranquil},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 0,
      defaultIntensity: 128,
      bestForOccasions: {'relaxation', 'everyday', 'ambient', 'work'},
      avoidForOccasions: {'party', 'celebration', 'sports'},
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // PULSING / BREATHING EFFECTS (respect colors)
    // ═══════════════════════════════════════════════════════════════════════
    1: EffectMetadata(
      id: 1,
      name: 'Blink',
      description: 'Simple on/off blinking',
      respectsColors: true,
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.medium,
      minSpeed: 20,
      maxSpeed: 200,
      defaultSpeed: 100,
      defaultIntensity: 128,
      bestForOccasions: {'alerts', 'attention'},
      avoidForOccasions: {'relaxation', 'romantic', 'sleep'},
    ),

    2: EffectMetadata(
      id: 2,
      name: 'Breathe',
      description: 'Smooth fade in and out like breathing',
      respectsColors: true,
      moods: {EffectMoodCategory.calm, EffectMoodCategory.romantic, EffectMoodCategory.mysterious, EffectMoodCategory.cozy},
      vibes: {EffectVibe.serene, EffectVibe.gentle, EffectVibe.dreamy, EffectVibe.intimate},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.low,
      minSpeed: 20,
      maxSpeed: 150,
      defaultSpeed: 60,
      defaultIntensity: 128,
      bestForOccasions: {'romantic', 'relaxation', 'meditation', 'evening', 'date-night'},
      avoidForOccasions: {'party', 'sports', 'high-energy'},
    ),

    3: EffectMetadata(
      id: 3,
      name: 'Wipe',
      description: 'Color wipes across the strip',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.elegant},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      minSpeed: 30,
      maxSpeed: 200,
      defaultSpeed: 100,
      defaultIntensity: 128,
      bestForOccasions: {'transition', 'reveal'},
    ),

    4: EffectMetadata(
      id: 4,
      name: 'Wipe Random',
      description: 'Color wipes with random colors',
      respectsColors: false,
      inherentColorDescription: ['random colors'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    5: EffectMetadata(
      id: 5,
      name: 'Random Colors',
      description: 'Random color changes',
      respectsColors: false,
      inherentColorDescription: ['random colors'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    6: EffectMetadata(
      id: 6,
      name: 'Sweep',
      description: 'Sweeping motion across the strip',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.elegant},
      vibes: {EffectVibe.dynamic, EffectVibe.subtle},
      motionType: MotionType.scanning,
      energyLevel: EnergyLevel.medium,
      minSpeed: 30,
      maxSpeed: 180,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    7: EffectMetadata(
      id: 7,
      name: 'Dynamic',
      description: 'Dynamic color changes',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.vibrant},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    8: EffectMetadata(
      id: 8,
      name: 'Colorloop',
      description: 'Smooth color cycling through hues',
      respectsColors: false,
      inherentColorDescription: ['full spectrum', 'rainbow cycling'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.magical},
      vibes: {EffectVibe.dreamy, EffectVibe.whimsical},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
      avoidForOccasions: {'themed', 'holiday', 'sports-team'},
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // RAINBOW EFFECTS (DO NOT respect colors - use only when rainbow requested)
    // ═══════════════════════════════════════════════════════════════════════
    9: EffectMetadata(
      id: 9,
      name: 'Rainbow',
      description: 'Classic rainbow gradient - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow', 'full spectrum', 'ROYGBIV'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.magical, EffectMoodCategory.festive},
      vibes: {EffectVibe.vibrant, EffectVibe.joyful, EffectVibe.whimsical},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 128,
      bestForOccasions: {'pride', 'rainbow-request', 'multicolor'},
      avoidForOccasions: {'christmas', 'halloween', '4th-of-july', 'sports-team', 'wedding', 'romantic'},
    ),

    10: EffectMetadata(
      id: 10,
      name: 'Rainbow Cycle',
      description: 'Moving rainbow - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow', 'full spectrum cycling'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.magical, EffectMoodCategory.festive},
      vibes: {EffectVibe.vibrant, EffectVibe.joyful, EffectVibe.dynamic},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 128,
      bestForOccasions: {'pride', 'rainbow-request', 'multicolor'},
      avoidForOccasions: {'christmas', 'halloween', '4th-of-july', 'sports-team', 'wedding', 'romantic'},
    ),

    11: EffectMetadata(
      id: 11,
      name: 'Scan',
      description: 'Single pixel scanning back and forth',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.scanning,
      energyLevel: EnergyLevel.low,
      minSpeed: 30,
      maxSpeed: 180,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    12: EffectMetadata(
      id: 12,
      name: 'Fade',
      description: 'Smooth color transitions',
      respectsColors: true,
      moods: {EffectMoodCategory.calm, EffectMoodCategory.elegant, EffectMoodCategory.romantic},
      vibes: {EffectVibe.serene, EffectVibe.gentle, EffectVibe.dreamy},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.low,
      minSpeed: 20,
      maxSpeed: 120,
      defaultSpeed: 60,
      defaultIntensity: 128,
      bestForOccasions: {'relaxation', 'ambient', 'evening'},
    ),

    13: EffectMetadata(
      id: 13,
      name: 'Theater',
      description: 'Theater-style chase lights',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful, EffectMoodCategory.elegant},
      vibes: {EffectVibe.joyful, EffectVibe.vibrant, EffectVibe.majestic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      minSpeed: 40,
      maxSpeed: 180,
      defaultSpeed: 100,
      defaultIntensity: 180,
      bestForOccasions: {'christmas', 'holiday', 'celebration', 'party'},
    ),

    14: EffectMetadata(
      id: 14,
      name: 'Theater Rainbow',
      description: 'Theater chase with rainbow - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow theater chase'],
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.joyful, EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
      bestForOccasions: {'pride', 'rainbow-request'},
      avoidForOccasions: {'themed', 'holiday', 'sports-team'},
    ),

    15: EffectMetadata(
      id: 15,
      name: 'Running',
      description: 'Smooth running lights',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful, EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic, EffectVibe.vibrant, EffectVibe.exciting},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      minSpeed: 60,
      maxSpeed: 220,
      defaultSpeed: 150,
      defaultIntensity: 200,
      bestForOccasions: {'party', 'sports', 'celebration', 'game-day'},
    ),

    16: EffectMetadata(
      id: 16,
      name: 'Saw',
      description: 'Sawtooth wave pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    17: EffectMetadata(
      id: 17,
      name: 'Twinkle',
      description: 'Random twinkling pixels',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive, EffectMoodCategory.elegant, EffectMoodCategory.romantic},
      vibes: {EffectVibe.magical, EffectVibe.dreamy, EffectVibe.whimsical, EffectVibe.subtle},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      minSpeed: 40,
      maxSpeed: 150,
      defaultSpeed: 80,
      minIntensity: 100,
      maxIntensity: 220,
      defaultIntensity: 180,
      bestForOccasions: {'christmas', 'holiday', 'magical', 'wedding', 'romantic', 'evening'},
    ),

    18: EffectMetadata(
      id: 18,
      name: 'Dissolve',
      description: 'Pixels dissolve randomly',
      respectsColors: true,
      moods: {EffectMoodCategory.mysterious, EffectMoodCategory.magical},
      vibes: {EffectVibe.dreamy, EffectVibe.subtle},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    19: EffectMetadata(
      id: 19,
      name: 'Dissolve Random',
      description: 'Dissolve with random colors',
      respectsColors: false,
      inherentColorDescription: ['random colors'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    20: EffectMetadata(
      id: 20,
      name: 'Sparkle',
      description: 'Bright sparkles on background',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive, EffectMoodCategory.elegant},
      vibes: {EffectVibe.magical, EffectVibe.joyful, EffectVibe.vibrant},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      minSpeed: 50,
      maxSpeed: 180,
      defaultSpeed: 100,
      defaultIntensity: 200,
      bestForOccasions: {'celebration', 'holiday', 'party', 'new-years'},
    ),

    21: EffectMetadata(
      id: 21,
      name: 'Sparkle Dark',
      description: 'Sparkles on dark background',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.magical, EffectVibe.subtle, EffectVibe.dreamy},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 100,
      defaultIntensity: 200,
      bestForOccasions: {'night', 'starry', 'magical'},
    ),

    22: EffectMetadata(
      id: 22,
      name: 'Sparkle+',
      description: 'Enhanced sparkle effect',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive},
      vibes: {EffectVibe.magical, EffectVibe.vibrant},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 200,
    ),

    23: EffectMetadata(
      id: 23,
      name: 'Strobe',
      description: 'Fast strobe effect',
      respectsColors: true,
      moods: {EffectMoodCategory.festive},
      vibes: {EffectVibe.exciting, EffectVibe.bold, EffectVibe.dynamic},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.veryHigh,
      minSpeed: 100,
      maxSpeed: 255,
      defaultSpeed: 200,
      defaultIntensity: 255,
      bestForOccasions: {'rave', 'dance', 'high-energy'},
      avoidForOccasions: {'relaxation', 'romantic', 'everyday', 'work'},
    ),

    24: EffectMetadata(
      id: 24,
      name: 'Strobe Rainbow',
      description: 'Rainbow strobe - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow strobe'],
      moods: {EffectMoodCategory.festive},
      vibes: {EffectVibe.exciting, EffectVibe.dynamic},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.veryHigh,
      defaultSpeed: 200,
      defaultIntensity: 255,
      avoidForOccasions: {'themed', 'relaxation'},
    ),

    25: EffectMetadata(
      id: 25,
      name: 'Strobe Mega',
      description: 'Intense strobe effect',
      respectsColors: true,
      moods: {EffectMoodCategory.festive},
      vibes: {EffectVibe.exciting, EffectVibe.bold},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.veryHigh,
      defaultSpeed: 220,
      defaultIntensity: 255,
      avoidForOccasions: {'relaxation', 'romantic', 'work'},
    ),

    26: EffectMetadata(
      id: 26,
      name: 'Blink Rainbow',
      description: 'Blinking rainbow - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow blink'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    27: EffectMetadata(
      id: 27,
      name: 'Android',
      description: 'Android-style loading animation',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    28: EffectMetadata(
      id: 28,
      name: 'Chase',
      description: 'Classic chase effect',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful, EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic, EffectVibe.exciting, EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      minSpeed: 80,
      maxSpeed: 220,
      defaultSpeed: 150,
      defaultIntensity: 200,
      bestForOccasions: {'sports', 'party', 'game-day', 'celebration'},
    ),

    29: EffectMetadata(
      id: 29,
      name: 'Chase Random',
      description: 'Chase with random colors',
      respectsColors: false,
      inherentColorDescription: ['random color chase'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
    ),

    30: EffectMetadata(
      id: 30,
      name: 'Chase Rainbow',
      description: 'Chase with rainbow - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow chase'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.vibrant, EffectVibe.dynamic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
      bestForOccasions: {'pride', 'rainbow-request'},
      avoidForOccasions: {'themed', 'holiday', 'sports-team'},
    ),

    31: EffectMetadata(
      id: 31,
      name: 'Chase Flash',
      description: 'Chase with flash accent',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.exciting, EffectVibe.dynamic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
    ),

    32: EffectMetadata(
      id: 32,
      name: 'Chase Flash Random',
      description: 'Chase flash with random colors',
      respectsColors: false,
      inherentColorDescription: ['random flash chase'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
    ),

    33: EffectMetadata(
      id: 33,
      name: 'Chase Rainbow White',
      description: 'Rainbow chase with white - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow with white'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
    ),

    34: EffectMetadata(
      id: 34,
      name: 'Colorful',
      description: 'Colorful shifting pattern - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['shifting multicolor'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.vibrant, EffectVibe.joyful},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    35: EffectMetadata(
      id: 35,
      name: 'Traffic Light',
      description: 'Red, yellow, green sequence - USES SPECIFIC COLORS',
      respectsColors: false,
      inherentColorDescription: ['red', 'yellow', 'green'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.whimsical},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
    ),

    36: EffectMetadata(
      id: 36,
      name: 'Sweep Random',
      description: 'Sweep with random colors',
      respectsColors: false,
      inherentColorDescription: ['random sweep'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.scanning,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    37: EffectMetadata(
      id: 37,
      name: 'Candle',
      description: 'Flickering candle flame effect',
      respectsColors: true,
      moods: {EffectMoodCategory.cozy, EffectMoodCategory.romantic, EffectMoodCategory.calm},
      vibes: {EffectVibe.intimate, EffectVibe.tranquil, EffectVibe.gentle},
      motionType: MotionType.flickering,
      energyLevel: EnergyLevel.low,
      minSpeed: 30,
      maxSpeed: 100,
      defaultSpeed: 60,
      defaultIntensity: 180,
      bestForOccasions: {'romantic', 'cozy', 'dinner', 'autumn', 'halloween', 'thanksgiving'},
    ),

    38: EffectMetadata(
      id: 38,
      name: 'Fire',
      description: 'Realistic fire simulation',
      respectsColors: true,
      moods: {EffectMoodCategory.cozy, EffectMoodCategory.mysterious, EffectMoodCategory.natural},
      vibes: {EffectVibe.intimate, EffectVibe.bold, EffectVibe.dynamic},
      motionType: MotionType.flickering,
      energyLevel: EnergyLevel.medium,
      minSpeed: 40,
      maxSpeed: 150,
      defaultSpeed: 80,
      defaultIntensity: 200,
      bestForOccasions: {'halloween', 'autumn', 'cozy', 'cabin'},
    ),

    39: EffectMetadata(
      id: 39,
      name: 'Fireworks',
      description: 'Exploding fireworks simulation',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.magical, EffectMoodCategory.playful},
      vibes: {EffectVibe.exciting, EffectVibe.joyful, EffectVibe.majestic},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.high,
      minSpeed: 80,
      maxSpeed: 200,
      defaultSpeed: 150,
      defaultIntensity: 220,
      bestForOccasions: {'4th-of-july', 'new-years', 'celebration', 'party', 'independence-day'},
    ),

    40: EffectMetadata(
      id: 40,
      name: 'Scanner',
      description: 'Scanning beam effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.dynamic, EffectVibe.subtle},
      motionType: MotionType.scanning,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 128,
    ),

    41: EffectMetadata(
      id: 41,
      name: 'Running Dual',
      description: 'Dual running lights',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic, EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      minSpeed: 80,
      maxSpeed: 220,
      defaultSpeed: 150,
      defaultIntensity: 200,
      bestForOccasions: {'sports', 'party', 'game-day'},
    ),

    42: EffectMetadata(
      id: 42,
      name: 'Halloween',
      description: 'Spooky Halloween effect',
      respectsColors: true,
      moods: {EffectMoodCategory.mysterious, EffectMoodCategory.playful},
      vibes: {EffectVibe.spooky, EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 180,
      bestForOccasions: {'halloween', 'spooky', 'october'},
    ),

    43: EffectMetadata(
      id: 43,
      name: 'Tricolor Chase',
      description: 'Three color chase pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 120,
      defaultIntensity: 180,
      bestForOccasions: {'holiday', 'celebration', 'patriotic'},
    ),

    44: EffectMetadata(
      id: 44,
      name: 'Tricolor Wipe',
      description: 'Three color wipe pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    45: EffectMetadata(
      id: 45,
      name: 'Tricolor Fade',
      description: 'Three color fade pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.elegant, EffectMoodCategory.calm},
      vibes: {EffectVibe.gentle, EffectVibe.subtle},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
    ),

    46: EffectMetadata(
      id: 46,
      name: 'Lightning',
      description: 'Lightning flash simulation',
      respectsColors: true,
      moods: {EffectMoodCategory.mysterious, EffectMoodCategory.festive},
      vibes: {EffectVibe.bold, EffectVibe.exciting, EffectVibe.spooky},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.dynamic,
      defaultSpeed: 100,
      defaultIntensity: 255,
      bestForOccasions: {'halloween', 'storm', 'dramatic'},
    ),

    47: EffectMetadata(
      id: 47,
      name: 'ICU',
      description: 'Scanning ICU effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.scanning,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    48: EffectMetadata(
      id: 48,
      name: 'Multi Comet',
      description: 'Multiple comets moving together',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.mysterious, EffectMoodCategory.festive},
      vibes: {EffectVibe.majestic, EffectVibe.dreamy, EffectVibe.dynamic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 120,
      defaultIntensity: 180,
      bestForOccasions: {'night', 'magical', 'starry'},
    ),

    49: EffectMetadata(
      id: 49,
      name: 'Fairy',
      description: 'Delicate fairy lights effect',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.romantic, EffectMoodCategory.elegant},
      vibes: {EffectVibe.magical, EffectVibe.dreamy, EffectVibe.whimsical, EffectVibe.gentle},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      minSpeed: 30,
      maxSpeed: 100,
      defaultSpeed: 60,
      defaultIntensity: 150,
      bestForOccasions: {'wedding', 'romantic', 'garden', 'magical', 'evening'},
    ),

    50: EffectMetadata(
      id: 50,
      name: 'Fairy Twinkle',
      description: 'Twinkling fairy effect',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.romantic},
      vibes: {EffectVibe.magical, EffectVibe.dreamy, EffectVibe.subtle},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
    ),

    51: EffectMetadata(
      id: 51,
      name: 'Running Tri',
      description: 'Running triple color effect',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.vibrant},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 200,
    ),

    52: EffectMetadata(
      id: 52,
      name: 'Fireworks Starburst',
      description: 'Starburst fireworks pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.magical},
      vibes: {EffectVibe.exciting, EffectVibe.majestic},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.high,
      minSpeed: 100,
      maxSpeed: 220,
      defaultSpeed: 150,
      defaultIntensity: 220,
      bestForOccasions: {'4th-of-july', 'new-years', 'celebration'},
    ),

    53: EffectMetadata(
      id: 53,
      name: 'Fireworks 1D',
      description: 'One-dimensional fireworks',
      respectsColors: true,
      moods: {EffectMoodCategory.festive},
      vibes: {EffectVibe.exciting, EffectVibe.joyful},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 220,
    ),

    54: EffectMetadata(
      id: 54,
      name: 'Bouncing Balls',
      description: 'Bouncing ball simulation',
      respectsColors: true,
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.whimsical, EffectVibe.joyful, EffectVibe.dynamic},
      motionType: MotionType.bouncing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
      bestForOccasions: {'kids', 'playful', 'fun'},
    ),

    55: EffectMetadata(
      id: 55,
      name: 'Sinelon',
      description: 'Sine wave pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    56: EffectMetadata(
      id: 56,
      name: 'Sinelon Dual',
      description: 'Dual sine wave',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.elegant},
      vibes: {EffectVibe.subtle, EffectVibe.gentle},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    57: EffectMetadata(
      id: 57,
      name: 'Sinelon Rainbow',
      description: 'Rainbow sine wave - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow sine'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    58: EffectMetadata(
      id: 58,
      name: 'Popcorn',
      description: 'Popping effect like popcorn',
      respectsColors: true,
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.whimsical, EffectVibe.joyful},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    59: EffectMetadata(
      id: 59,
      name: 'Drip',
      description: 'Dripping water effect',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.mysterious, EffectMoodCategory.calm},
      vibes: {EffectVibe.tranquil, EffectVibe.gentle},
      motionType: MotionType.dripping,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
      bestForOccasions: {'relaxation', 'water', 'rain'},
    ),

    60: EffectMetadata(
      id: 60,
      name: 'Plasma',
      description: 'Plasma effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    61: EffectMetadata(
      id: 61,
      name: 'Percent',
      description: 'Progress bar style effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 0,
      defaultIntensity: 128,
    ),

    62: EffectMetadata(
      id: 62,
      name: 'Ripple Rainbow',
      description: 'Rainbow ripples - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['rainbow ripple'],
      moods: {EffectMoodCategory.playful, EffectMoodCategory.magical},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    63: EffectMetadata(
      id: 63,
      name: 'Pride 2015',
      description: 'Pride rainbow effect - OVERRIDES USER COLORS',
      respectsColors: false,
      inherentColorDescription: ['pride rainbow', 'LGBTQ colors'],
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.vibrant, EffectVibe.joyful},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 128,
      bestForOccasions: {'pride', 'rainbow-request'},
      avoidForOccasions: {'themed', 'holiday', 'sports-team'},
    ),

    64: EffectMetadata(
      id: 64,
      name: 'Juggle',
      description: 'Juggling lights effect',
      respectsColors: true,
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.bouncing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    65: EffectMetadata(
      id: 65,
      name: 'Palette',
      description: 'Uses palette colors',
      respectsColors: false,
      inherentColorDescription: ['palette-based'],
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    66: EffectMetadata(
      id: 66,
      name: 'Fire 2012',
      description: 'Classic fire simulation',
      respectsColors: true,
      moods: {EffectMoodCategory.cozy, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.intimate, EffectVibe.bold},
      motionType: MotionType.flickering,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 200,
    ),

    67: EffectMetadata(
      id: 67,
      name: 'Colorwaves',
      description: 'Flowing color waves',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm, EffectMoodCategory.modern},
      vibes: {EffectVibe.tranquil, EffectVibe.dynamic, EffectVibe.gentle},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
      bestForOccasions: {'ocean', 'relaxation', 'ambient'},
    ),

    68: EffectMetadata(
      id: 68,
      name: 'BPM',
      description: 'Beat per minute pulsing',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic, EffectVibe.exciting},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 120,
      defaultIntensity: 200,
      bestForOccasions: {'party', 'music', 'dance'},
    ),

    69: EffectMetadata(
      id: 69,
      name: 'Fill Noise',
      description: 'Noise-based filling',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    70: EffectMetadata(
      id: 70,
      name: 'Noise 1',
      description: 'Perlin noise pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    71: EffectMetadata(
      id: 71,
      name: 'Noise 2',
      description: 'Variant noise pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    72: EffectMetadata(
      id: 72,
      name: 'Noise 3',
      description: 'Another noise variant',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    73: EffectMetadata(
      id: 73,
      name: 'Noise 4',
      description: 'Fourth noise variant',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    74: EffectMetadata(
      id: 74,
      name: 'Colortwinkles',
      description: 'Twinkling with color changes',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive},
      vibes: {EffectVibe.magical, EffectVibe.joyful},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 180,
    ),

    75: EffectMetadata(
      id: 75,
      name: 'Lake',
      description: 'Peaceful lake reflections',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm},
      vibes: {EffectVibe.tranquil, EffectVibe.serene},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 40,
      defaultIntensity: 128,
      bestForOccasions: {'relaxation', 'nature', 'water'},
    ),

    76: EffectMetadata(
      id: 76,
      name: 'Meteor',
      description: 'Falling meteor trail',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.mysterious, EffectMoodCategory.festive},
      vibes: {EffectVibe.majestic, EffectVibe.dreamy, EffectVibe.dynamic},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      minSpeed: 60,
      maxSpeed: 180,
      defaultSpeed: 120,
      defaultIntensity: 200,
      bestForOccasions: {'night', 'magical', 'shooting-star', 'space'},
    ),

    77: EffectMetadata(
      id: 77,
      name: 'Meteor Smooth',
      description: 'Smooth meteor trail',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.elegant},
      vibes: {EffectVibe.majestic, EffectVibe.gentle},
      motionType: MotionType.chasing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    78: EffectMetadata(
      id: 78,
      name: 'Railway',
      description: 'Railway crossing lights',
      respectsColors: true,
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 200,
    ),

    79: EffectMetadata(
      id: 79,
      name: 'Ripple',
      description: 'Rippling water effect',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm, EffectMoodCategory.magical},
      vibes: {EffectVibe.tranquil, EffectVibe.gentle, EffectVibe.dreamy},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 150,
      bestForOccasions: {'relaxation', 'water', 'zen'},
    ),

    80: EffectMetadata(
      id: 80,
      name: 'Twinklefox',
      description: 'Fox-inspired twinkle',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive, EffectMoodCategory.elegant},
      vibes: {EffectVibe.magical, EffectVibe.subtle, EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      minSpeed: 30,
      maxSpeed: 120,
      defaultSpeed: 70,
      defaultIntensity: 180,
      bestForOccasions: {'christmas', 'holiday', 'magical', 'winter'},
    ),

    81: EffectMetadata(
      id: 81,
      name: 'Twinklecat',
      description: 'Cat-inspired twinkle',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.playful},
      vibes: {EffectVibe.magical, EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 70,
      defaultIntensity: 180,
    ),

    82: EffectMetadata(
      id: 82,
      name: 'Halloween Eyes',
      description: 'Spooky blinking eyes',
      respectsColors: true,
      moods: {EffectMoodCategory.mysterious, EffectMoodCategory.playful},
      vibes: {EffectVibe.spooky, EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
      bestForOccasions: {'halloween', 'spooky'},
    ),

    83: EffectMetadata(
      id: 83,
      name: 'Solid Pattern',
      description: 'Solid pattern segments',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.elegant},
      vibes: {EffectVibe.subtle, EffectVibe.bold},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 0,
      defaultIntensity: 128,
    ),

    84: EffectMetadata(
      id: 84,
      name: 'Solid Pattern Tri',
      description: 'Three-color solid pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.modern},
      vibes: {EffectVibe.bold, EffectVibe.vibrant},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 0,
      defaultIntensity: 128,
      bestForOccasions: {'patriotic', 'holiday', 'team-colors'},
    ),

    85: EffectMetadata(
      id: 85,
      name: 'Spots',
      description: 'Spotlights effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.elegant},
      vibes: {EffectVibe.subtle, EffectVibe.luxurious},
      motionType: MotionType.static,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 150,
    ),

    86: EffectMetadata(
      id: 86,
      name: 'Spots Fade',
      description: 'Fading spotlights',
      respectsColors: true,
      moods: {EffectMoodCategory.elegant, EffectMoodCategory.calm},
      vibes: {EffectVibe.subtle, EffectVibe.gentle},
      motionType: MotionType.pulsing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 50,
      defaultIntensity: 150,
    ),

    87: EffectMetadata(
      id: 87,
      name: 'Glitter',
      description: 'Sparkling glitter effect',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive, EffectMoodCategory.elegant},
      vibes: {EffectVibe.magical, EffectVibe.luxurious, EffectVibe.joyful},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      minSpeed: 50,
      maxSpeed: 150,
      defaultSpeed: 100,
      defaultIntensity: 200,
      bestForOccasions: {'celebration', 'new-years', 'party', 'glamour'},
    ),

    88: EffectMetadata(
      id: 88,
      name: 'Candle Multi',
      description: 'Multiple candle flames',
      respectsColors: true,
      moods: {EffectMoodCategory.cozy, EffectMoodCategory.romantic},
      vibes: {EffectVibe.intimate, EffectVibe.tranquil},
      motionType: MotionType.flickering,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 180,
    ),

    89: EffectMetadata(
      id: 89,
      name: 'Solid Glitter',
      description: 'Solid color with glitter overlay',
      respectsColors: true,
      moods: {EffectMoodCategory.elegant, EffectMoodCategory.festive},
      vibes: {EffectVibe.luxurious, EffectVibe.magical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 150,
    ),

    90: EffectMetadata(
      id: 90,
      name: 'Sunrise',
      description: 'Simulated sunrise',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm, EffectMoodCategory.cozy},
      vibes: {EffectVibe.tranquil, EffectVibe.gentle, EffectVibe.serene},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.veryLow,
      minSpeed: 10,
      maxSpeed: 60,
      defaultSpeed: 30,
      defaultIntensity: 128,
      bestForOccasions: {'morning', 'wake-up', 'alarm'},
    ),

    91: EffectMetadata(
      id: 91,
      name: 'Phased',
      description: 'Phased color shifting',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.subtle, EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    92: EffectMetadata(
      id: 92,
      name: 'Twinkleup',
      description: 'Upward twinkling',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.festive},
      vibes: {EffectVibe.magical, EffectVibe.joyful},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 180,
    ),

    93: EffectMetadata(
      id: 93,
      name: 'Noise Pal',
      description: 'Noise with palette',
      respectsColors: false,
      inherentColorDescription: ['palette-based noise'],
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    94: EffectMetadata(
      id: 94,
      name: 'Sine',
      description: 'Sine wave pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.calm},
      vibes: {EffectVibe.gentle, EffectVibe.subtle},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
    ),

    95: EffectMetadata(
      id: 95,
      name: 'Flow',
      description: 'Flowing colors effect',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm, EffectMoodCategory.modern},
      vibes: {EffectVibe.tranquil, EffectVibe.gentle, EffectVibe.dreamy},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      minSpeed: 40,
      maxSpeed: 120,
      defaultSpeed: 80,
      defaultIntensity: 150,
      bestForOccasions: {'ocean', 'relaxation', 'ambient', 'water'},
    ),

    96: EffectMetadata(
      id: 96,
      name: 'Chunchun',
      description: 'Chunchun pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    97: EffectMetadata(
      id: 97,
      name: 'Dancing Shadows',
      description: 'Shadows moving about',
      respectsColors: true,
      moods: {EffectMoodCategory.mysterious, EffectMoodCategory.magical},
      vibes: {EffectVibe.spooky, EffectVibe.dreamy},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
      bestForOccasions: {'halloween', 'mysterious'},
    ),

    98: EffectMetadata(
      id: 98,
      name: 'Washing Machine',
      description: 'Washing motion pattern',
      respectsColors: true,
      moods: {EffectMoodCategory.playful},
      vibes: {EffectVibe.whimsical, EffectVibe.dynamic},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // AUDIO REACTIVE EFFECTS (may need audio input)
    // ═══════════════════════════════════════════════════════════════════════
    99: EffectMetadata(
      id: 99,
      name: 'Blends',
      description: 'Blending colors',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.calm},
      vibes: {EffectVibe.gentle, EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
    ),

    100: EffectMetadata(
      id: 100,
      name: 'TV Simulator',
      description: 'Simulates TV ambient light',
      respectsColors: false,
      inherentColorDescription: ['random TV colors'],
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.dynamic,
      defaultSpeed: 80,
      defaultIntensity: 150,
    ),

    101: EffectMetadata(
      id: 101,
      name: 'Dynamic Smooth',
      description: 'Smooth dynamic changes',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.calm},
      vibes: {EffectVibe.gentle, EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // 2D EFFECTS (for matrix/panel setups - respect colors by default)
    // ═══════════════════════════════════════════════════════════════════════
    102: EffectMetadata(
      id: 102,
      name: 'Pixels',
      description: '2D pixel effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.playful},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.twinkling,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    103: EffectMetadata(
      id: 103,
      name: 'Pixelwave',
      description: '2D pixel wave',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.magical},
      vibes: {EffectVibe.dynamic, EffectVibe.dreamy},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    104: EffectMetadata(
      id: 104,
      name: 'Juggles',
      description: '2D juggling effect',
      respectsColors: true,
      moods: {EffectMoodCategory.playful, EffectMoodCategory.festive},
      vibes: {EffectVibe.dynamic, EffectVibe.whimsical},
      motionType: MotionType.bouncing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    105: EffectMetadata(
      id: 105,
      name: 'Matripix',
      description: 'Matrix pixel effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    106: EffectMetadata(
      id: 106,
      name: 'Gravimeter',
      description: 'Gravity meter visualization',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic},
      motionType: MotionType.bouncing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    107: EffectMetadata(
      id: 107,
      name: 'Plasmoid',
      description: 'Plasma ball effect',
      respectsColors: true,
      moods: {EffectMoodCategory.modern, EffectMoodCategory.magical},
      vibes: {EffectVibe.dynamic, EffectVibe.bold},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    108: EffectMetadata(
      id: 108,
      name: 'Puddles',
      description: 'Puddle ripples',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm},
      vibes: {EffectVibe.tranquil, EffectVibe.gentle},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 60,
      defaultIntensity: 128,
    ),

    109: EffectMetadata(
      id: 109,
      name: 'Midnoise',
      description: 'Mid-frequency noise',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.subtle},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.low,
      defaultSpeed: 80,
      defaultIntensity: 128,
    ),

    110: EffectMetadata(
      id: 110,
      name: 'Noisemeter',
      description: 'Noise level visualization',
      respectsColors: true,
      moods: {EffectMoodCategory.modern},
      vibes: {EffectVibe.dynamic},
      motionType: MotionType.morphing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 150,
    ),

    // ═══════════════════════════════════════════════════════════════════════
    // CUSTOM LUMINA EFFECTS (1000+ range)
    // ═══════════════════════════════════════════════════════════════════════
    1001: EffectMetadata(
      id: 1001,
      name: 'Rising Tide',
      description: 'Lumina custom: colors rise up from bottom',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.natural},
      vibes: {EffectVibe.majestic, EffectVibe.dynamic},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    1002: EffectMetadata(
      id: 1002,
      name: 'Falling Tide',
      description: 'Lumina custom: colors fall from top',
      respectsColors: true,
      moods: {EffectMoodCategory.magical, EffectMoodCategory.mysterious},
      vibes: {EffectVibe.majestic, EffectVibe.dynamic},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 100,
      defaultIntensity: 180,
    ),

    1003: EffectMetadata(
      id: 1003,
      name: 'Pulse Burst',
      description: 'Lumina custom: explosive color pulses',
      respectsColors: true,
      moods: {EffectMoodCategory.festive, EffectMoodCategory.playful},
      vibes: {EffectVibe.exciting, EffectVibe.bold},
      motionType: MotionType.explosive,
      energyLevel: EnergyLevel.high,
      defaultSpeed: 150,
      defaultIntensity: 220,
    ),

    1005: EffectMetadata(
      id: 1005,
      name: 'Grand Reveal',
      description: 'Lumina custom: dramatic reveal effect',
      respectsColors: true,
      moods: {EffectMoodCategory.elegant, EffectMoodCategory.festive},
      vibes: {EffectVibe.majestic, EffectVibe.luxurious},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.medium,
      defaultSpeed: 80,
      defaultIntensity: 200,
      bestForOccasions: {'reveal', 'special-moment', 'wedding'},
    ),

    1007: EffectMetadata(
      id: 1007,
      name: 'Ocean Swell',
      description: 'Lumina custom: gentle ocean wave motion',
      respectsColors: true,
      moods: {EffectMoodCategory.natural, EffectMoodCategory.calm},
      vibes: {EffectVibe.tranquil, EffectVibe.serene},
      motionType: MotionType.flowing,
      energyLevel: EnergyLevel.veryLow,
      defaultSpeed: 50,
      defaultIntensity: 128,
      bestForOccasions: {'relaxation', 'ocean', 'sleep'},
    ),
  };

  /// Get effect by ID
  static EffectMetadata? getEffect(int id) => effects[id];

  /// Get all effects that respect user colors
  static List<EffectMetadata> getColorRespectingEffects() {
    return effects.values.where((e) => e.respectsColors).toList();
  }

  /// Get all effects that override colors (rainbow, palette-based)
  static List<EffectMetadata> getColorOverridingEffects() {
    return effects.values.where((e) => !e.respectsColors).toList();
  }

  /// Get effects matching a mood
  static List<EffectMetadata> getEffectsForMood(EffectMoodCategory mood) {
    return effects.values.where((e) => e.moods.contains(mood)).toList();
  }

  /// Get effects matching any of the moods
  static List<EffectMetadata> getEffectsForAnyMood(Set<EffectMoodCategory> moods) {
    return effects.values.where((e) => e.moods.intersection(moods).isNotEmpty).toList();
  }

  /// Get effects matching a motion type
  static List<EffectMetadata> getEffectsForMotionType(MotionType motion) {
    return effects.values.where((e) => e.motionType == motion).toList();
  }

  /// Get effects within an energy level range
  static List<EffectMetadata> getEffectsForEnergyRange(EnergyLevel min, EnergyLevel max) {
    final minIndex = EnergyLevel.values.indexOf(min);
    final maxIndex = EnergyLevel.values.indexOf(max);
    return effects.values.where((e) {
      final level = EnergyLevel.values.indexOf(e.energyLevel);
      return level >= minIndex && level <= maxIndex;
    }).toList();
  }

  /// Get effects good for a specific occasion
  static List<EffectMetadata> getEffectsForOccasion(String occasion) {
    return effects.values.where((e) => e.bestForOccasions.contains(occasion)).toList();
  }

  /// Get color-respecting effects that match mood and energy criteria
  static List<EffectMetadata> findMatchingEffects({
    Set<EffectMoodCategory>? moods,
    Set<EffectVibe>? vibes,
    MotionType? motionType,
    EnergyLevel? minEnergy,
    EnergyLevel? maxEnergy,
    String? occasion,
    bool requireColorRespect = true,
  }) {
    return effects.values.where((e) {
      // Color respect check
      if (requireColorRespect && !e.respectsColors) return false;

      // Mood check
      if (moods != null && moods.isNotEmpty) {
        if (e.moods.intersection(moods).isEmpty) return false;
      }

      // Vibe check
      if (vibes != null && vibes.isNotEmpty) {
        if (e.vibes.intersection(vibes).isEmpty) return false;
      }

      // Motion type check
      if (motionType != null && e.motionType != motionType) return false;

      // Energy range check
      if (minEnergy != null) {
        final level = EnergyLevel.values.indexOf(e.energyLevel);
        final minLevel = EnergyLevel.values.indexOf(minEnergy);
        if (level < minLevel) return false;
      }
      if (maxEnergy != null) {
        final level = EnergyLevel.values.indexOf(e.energyLevel);
        final maxLevel = EnergyLevel.values.indexOf(maxEnergy);
        if (level > maxLevel) return false;
      }

      // Occasion check
      if (occasion != null) {
        if (e.avoidForOccasions.contains(occasion)) return false;
      }

      return true;
    }).toList();
  }

  /// Check if an effect should be avoided for a given occasion/theme
  static bool shouldAvoidEffect(int effectId, String occasion) {
    final effect = effects[effectId];
    if (effect == null) return false;
    return effect.avoidForOccasions.contains(occasion);
  }

  /// Check if an effect respects user colors
  static bool effectRespectsColors(int effectId) {
    final effect = effects[effectId];
    return effect?.respectsColors ?? true;
  }

  /// Get recommended effects for common scenarios
  static List<int> getRecommendedEffectIds({
    required String scenario,
    bool colorRespectRequired = true,
  }) {
    switch (scenario.toLowerCase()) {
      case 'christmas':
      case 'holiday':
        return [13, 17, 80, 43, 49].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'halloween':
      case 'spooky':
        return [17, 42, 37, 82, 46].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'party':
      case 'celebration':
        return [39, 28, 15, 20, 87].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case '4th-of-july':
      case 'independence-day':
      case 'patriotic':
        return [39, 52, 43, 84].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'romantic':
      case 'date-night':
        return [2, 37, 49, 17, 12].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'relaxation':
      case 'calm':
        return [0, 2, 95, 75, 79].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'sports':
      case 'game-day':
        return [28, 15, 41, 39, 20].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'wedding':
      case 'elegant':
        return [2, 17, 49, 87, 1005].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();

      case 'rainbow':
      case 'pride':
      case 'multicolor':
        // These can include non-color-respecting effects
        return [9, 10, 63, 30, 14];

      default:
        // Default to safe, color-respecting effects
        return [0, 2, 17, 13, 28].where((id) {
          if (!colorRespectRequired) return true;
          return effects[id]?.respectsColors ?? false;
        }).toList();
    }
  }
}
