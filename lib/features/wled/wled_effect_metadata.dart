/// Metadata for WLED effects to provide context-aware UI labels
/// and determine which parameters are relevant for each effect.
class WledEffectMetadata {
  /// Whether this effect uses the speed parameter
  final bool usesSpeed;

  /// Whether this effect uses the intensity parameter
  final bool usesIntensity;

  /// Context-aware label for the intensity slider (null = hide slider)
  final String? intensityLabel;

  const WledEffectMetadata({
    required this.usesSpeed,
    required this.usesIntensity,
    this.intensityLabel,
  });
}

/// Effect metadata map: Maps WLED effect IDs to their metadata.
/// This provides context-aware labels and parameter relevance for each effect.
const Map<int, WledEffectMetadata> kWledEffectMetadata = {
  // Effect ID 0: Solid - static color, no animation parameters needed
  0: WledEffectMetadata(
    usesSpeed: false,
    usesIntensity: false,
    intensityLabel: null, // Hide intensity slider for solid
  ),

  // Effect ID 1: Blink - simple on/off blinking
  1: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: false,
    intensityLabel: null,
  ),

  // Effect ID 2: Breathe - smooth breathing effect
  2: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Breathing Depth',
  ),

  // Effect ID 3: Wipe - color wipe across LEDs
  3: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Wipe Width',
  ),

  // Effect ID 6: Sweep - back and forth sweep
  6: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Sweep Width',
  ),

  // Effect ID 10: Scan - scanner effect
  10: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 11: Scan Dual - dual scanner
  11: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 12: Fade - smooth fade between colors
  12: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Transition Amount',
  ),

  // Effect ID 13: Theater Chase - theater marquee effect
  13: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 15: Running - running lights
  15: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 16: Saw - sawtooth pattern
  16: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 17: Twinkle - random twinkling
  17: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Twinkle Density',
  ),

  // Effect ID 18: Dissolve - random dissolve
  18: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Dissolve Amount',
  ),

  // Effect ID 20: Sparkle - bright sparkles
  20: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Sparkle Density',
  ),

  // Effect ID 21: Sparkle Dark - sparkles on dark background
  21: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Sparkle Density',
  ),

  // Effect ID 22: Sparkle+ - enhanced sparkle
  22: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Sparkle Density',
  ),

  // Effect ID 23: Strobe - strobe flash
  23: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Strobe Intensity',
  ),

  // Effect ID 25: Strobe Mega - mega strobe
  25: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Strobe Intensity',
  ),

  // Effect ID 27: Android - Android loading animation
  27: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 28: Chase - color chase
  28: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 31: Chase Flash - chase with flash
  31: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 37: Chase 2 - alternative chase
  37: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 40: Scanner - scanner beam
  40: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 41: Lighthouse - lighthouse beam
  41: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 44: Tetrix - tetris-like effect
  44: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 46: Gradient - gradient effect
  46: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Gradient Spread',
  ),

  // Effect ID 47: Loading - loading bar
  47: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Bar Width',
  ),

  // Effect ID 49: Fairy - fairy lights
  49: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Sparkle Density',
  ),

  // Effect ID 50: Two Dots - two moving dots
  50: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Dot Size',
  ),

  // Effect ID 51: Fairytwinkle - fairy twinkle
  51: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Twinkle Density',
  ),

  // Effect ID 52: Running Dual - dual running
  52: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 54: Chase 3 - third chase variant
  54: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Chase Width',
  ),

  // Effect ID 55: Tri Wipe - triangular wipe
  55: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Wipe Width',
  ),

  // Effect ID 56: Tri Fade - triangular fade
  56: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Fade Amount',
  ),

  // Effect ID 57: Lightning - lightning effect
  57: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Lightning Intensity',
  ),

  // Effect ID 58: ICU - ICU scanner
  58: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 59: Multi Comet - multiple comets
  59: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Tail Length',
  ),

  // Effect ID 60: Scanner Dual - dual scanner
  60: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Beam Width',
  ),

  // Effect ID 62: Oscillate - oscillating effect
  62: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Oscillation Amount',
  ),

  // Effect ID 76: Meteor - meteor effect
  76: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Tail Length',
  ),

  // Effect ID 77: Meteor Smooth - smooth meteor
  77: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Tail Length',
  ),

  // Effect ID 78: Railway - railway crossing
  78: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 82: Halloween Eyes - spooky eyes
  82: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Eye Size',
  ),

  // Effect ID 83: Solid Pattern - solid pattern
  83: WledEffectMetadata(
    usesSpeed: false,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 84: Solid Pattern Tri - triangular solid pattern
  84: WledEffectMetadata(
    usesSpeed: false,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 85: Spots - spot lights
  85: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Spot Size',
  ),

  // Effect ID 86: Spots Fade - fading spots
  86: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Spot Size',
  ),

  // Effect ID 87: Glitter - glitter effect
  87: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Glitter Density',
  ),

  // Effect ID 91: Bouncing Balls - bouncing balls physics
  91: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Ball Size',
  ),

  // Effect ID 95: Popcorn - popcorn effect
  95: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pop Density',
  ),

  // Effect ID 96: Drip - water drip effect
  96: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Drip Amount',
  ),

  // Effect ID 98: Percent - percentage bar
  98: WledEffectMetadata(
    usesSpeed: false,
    usesIntensity: true,
    intensityLabel: 'Percentage',
  ),

  // Effect ID 100: Heartbeat - heartbeat pulse
  100: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pulse Depth',
  ),

  // Effect ID 102: Candle Multi - multiple candles
  102: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Flicker Intensity',
  ),

  // Effect ID 103: Solid Glitter - solid with glitter
  103: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Glitter Density',
  ),

  // Effect ID 111: Chunchun - chunchun effect
  111: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),

  // Effect ID 112: Dancing Shadows - dancing shadow effect
  112: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Shadow Depth',
  ),

  // Effect ID 113: Washing Machine - washing machine effect
  113: WledEffectMetadata(
    usesSpeed: true,
    usesIntensity: true,
    intensityLabel: 'Pattern Size',
  ),
};

/// Get metadata for an effect, with fallback to default.
/// Returns metadata with context-aware intensity label or generic "Effect Strength".
WledEffectMetadata getEffectMetadata(int effectId) {
  return kWledEffectMetadata[effectId] ??
    const WledEffectMetadata(
      usesSpeed: true,
      usesIntensity: true,
      intensityLabel: 'Effect Strength', // Generic fallback
    );
}
