// Keyword lists and scoring weights for intent classification.
//
// Separated from [CommandIntentClassifier] so signal data is easy to tune
// without touching classifier logic.

// ---------------------------------------------------------------------------
// Signal entry
// ---------------------------------------------------------------------------

/// A weighted keyword or regex pattern that signals intent.
class SignalEntry {
  /// The keyword or phrase to match (case-insensitive).
  final String keyword;

  /// Score contribution when matched (higher = stronger signal).
  final double weight;

  /// If true, [keyword] is treated as a regex pattern rather than a
  /// literal substring.
  final bool isRegex;

  const SignalEntry(this.keyword, this.weight, {this.isRegex = false});
}

// ---------------------------------------------------------------------------
// Adjustment signals
// ---------------------------------------------------------------------------

/// Words/patterns that indicate the user wants to MODIFY the current lighting
/// state rather than start fresh.
const List<SignalEntry> adjustmentSignals = [
  // --- Relative modifiers (strongest adjustment signals) ---
  SignalEntry('brighter', 0.85),
  SignalEntry('dimmer', 0.85),
  SignalEntry('slower', 0.85),
  SignalEntry('faster', 0.85),
  SignalEntry('warmer', 0.80),
  SignalEntry('cooler', 0.80),
  SignalEntry('softer', 0.75),
  SignalEntry('bolder', 0.75),
  SignalEntry('more vibrant', 0.80),
  SignalEntry('less vibrant', 0.80),
  SignalEntry('more saturated', 0.75),
  SignalEntry('less saturated', 0.75),
  SignalEntry('more intense', 0.75),
  SignalEntry('less intense', 0.75),

  // --- "more/less" prefix (regex) ---
  SignalEntry(r'\bmore\b', 0.65, isRegex: true),
  SignalEntry(r'\bless\b', 0.65, isRegex: true),
  SignalEntry(r'\ba little\b', 0.70, isRegex: true),
  SignalEntry(r'\ba lot\b', 0.65, isRegex: true),
  SignalEntry(r'\bslightly\b', 0.70, isRegex: true),
  SignalEntry(r'\bmuch\b', 0.50, isRegex: true),

  // --- Additive language ---
  SignalEntry('add some', 0.80),
  SignalEntry('add a', 0.75),
  SignalEntry('include', 0.60),
  SignalEntry('also', 0.55),
  SignalEntry('plus', 0.55),
  SignalEntry('with some', 0.70),
  SignalEntry('throw in', 0.70),
  SignalEntry('mix in', 0.75),
  SignalEntry('sprinkle', 0.65),

  // --- Explicit parameter targets ---
  SignalEntry('set brightness', 0.90),
  SignalEntry('set speed', 0.90),
  SignalEntry('brightness to', 0.90),
  SignalEntry('speed to', 0.85),
  SignalEntry('dim to', 0.90),
  SignalEntry(r'\b\d{1,3}\s*%', 0.70, isRegex: true), // "50%", "30 %"
  SignalEntry('half brightness', 0.85),
  SignalEntry('full brightness', 0.85),

  // --- Explicit keep/preserve ---
  SignalEntry('keep the', 0.90),
  SignalEntry('same colors', 0.90),
  SignalEntry('same palette', 0.90),
  SignalEntry('same effect', 0.85),
  SignalEntry("don't change", 0.90),
  SignalEntry('leave the', 0.80),
  SignalEntry('just change', 0.85),
  SignalEntry('just make', 0.75),
  SignalEntry('only change', 0.85),
  SignalEntry('but keep', 0.90),
  SignalEntry('but make', 0.70),

  // --- Undo/revert ---
  SignalEntry('undo', 0.95),
  SignalEntry('go back', 0.90),
  SignalEntry('revert', 0.90),
  SignalEntry('previous', 0.80),
  SignalEntry('before', 0.50),
  SignalEntry('redo', 0.85),

  // --- Standalone effect names (tweaking, not resetting) ---
  SignalEntry('make it chase', 0.70),
  SignalEntry('add twinkle', 0.75),
  SignalEntry('add sparkle', 0.75),
  SignalEntry('make it breathe', 0.70),
  SignalEntry('make it pulse', 0.70),
  SignalEntry('make it static', 0.70),
  SignalEntry('make it flow', 0.70),
  SignalEntry('stop moving', 0.80),
  SignalEntry('no movement', 0.80),

  // --- Directional tweaks ---
  SignalEntry('turn up', 0.75),
  SignalEntry('turn down', 0.75),
  SignalEntry('bump up', 0.75),
  SignalEntry('bump down', 0.75),
  SignalEntry('crank up', 0.70),
  SignalEntry('crank down', 0.70),
  SignalEntry('dial down', 0.70),
  SignalEntry('dial up', 0.70),
  SignalEntry('tone down', 0.75),
  SignalEntry('tone it down', 0.75),
];

// ---------------------------------------------------------------------------
// New-scene signals
// ---------------------------------------------------------------------------

/// Words/patterns that indicate the user wants a completely FRESH scene
/// with new colors, effect, and parameters.
const List<SignalEntry> newSceneSignals = [
  // --- Named concepts with strong visual identity ---
  SignalEntry('party mode', 0.90),
  SignalEntry('date night', 0.85),
  SignalEntry('movie night', 0.80),
  SignalEntry('game day', 0.85),
  SignalEntry('game night', 0.80),
  SignalEntry('dinner party', 0.80),
  SignalEntry('cocktail hour', 0.80),
  SignalEntry('yoga', 0.75),
  SignalEntry('meditation', 0.75),
  SignalEntry('reading mode', 0.75),
  SignalEntry('bedtime', 0.70),
  SignalEntry('wake up', 0.65),

  // --- Nature / atmosphere concepts ---
  SignalEntry('sunset', 0.85),
  SignalEntry('sunrise', 0.80),
  SignalEntry('ocean', 0.85),
  SignalEntry('aurora', 0.85),
  SignalEntry('northern lights', 0.85),
  SignalEntry('tropical', 0.80),
  SignalEntry('forest', 0.75),
  SignalEntry('desert', 0.75),
  SignalEntry('thunderstorm', 0.80),
  SignalEntry('starry', 0.75),
  SignalEntry('moonlight', 0.75),
  SignalEntry('campfire', 0.80),
  SignalEntry('lava', 0.80),
  SignalEntry('underwater', 0.80),
  SignalEntry('deep sea', 0.80),
  SignalEntry('cherry blossom', 0.85),
  SignalEntry('lavender field', 0.80),

  // --- Holiday / event themes ---
  SignalEntry('christmas', 0.95),
  SignalEntry('halloween', 0.95),
  SignalEntry('valentine', 0.90),
  SignalEntry("st patrick", 0.90),
  SignalEntry('fourth of july', 0.90),
  SignalEntry('4th of july', 0.90),
  SignalEntry('independence day', 0.90),
  SignalEntry('easter', 0.85),
  SignalEntry('hanukkah', 0.90),
  SignalEntry('diwali', 0.85),
  SignalEntry('new year', 0.85),
  SignalEntry('thanksgiving', 0.85),
  SignalEntry('mardi gras', 0.90),
  SignalEntry('pride', 0.80),
  SignalEntry('winter wonderland', 0.90),
  SignalEntry('fireworks', 0.80),
  SignalEntry('patriotic', 0.85),
  SignalEntry('spooky', 0.80),
  SignalEntry('festive', 0.70),
  SignalEntry('holiday', 0.65),

  // --- Explicit fresh start ---
  SignalEntry('something different', 0.90),
  SignalEntry('something new', 0.85),
  SignalEntry('change it up', 0.85),
  SignalEntry('start over', 0.90),
  SignalEntry('new scene', 0.95),
  SignalEntry('new look', 0.85),
  SignalEntry('switch to', 0.80),
  SignalEntry('show me', 0.60),
  SignalEntry('give me', 0.55),
  SignalEntry('set the mood', 0.70),
  SignalEntry('surprise me', 0.80),
  SignalEntry('try something', 0.70),
  SignalEntry('how about', 0.55),

  // --- Mood concepts with strong palette associations ---
  SignalEntry('cozy', 0.70),
  SignalEntry('romantic', 0.70),
  SignalEntry('zen', 0.70),
  SignalEntry('dreamy', 0.70),
  SignalEntry('mysterious', 0.65),
  SignalEntry('ethereal', 0.70),
  SignalEntry('bohemian', 0.70),
  SignalEntry('vintage', 0.65),
  SignalEntry('neon', 0.70),
  SignalEntry('cyberpunk', 0.75),
  SignalEntry('vaporwave', 0.80),
  SignalEntry('retro', 0.65),
  SignalEntry('minimalist', 0.65),

  // --- Season-based ---
  SignalEntry('spring', 0.60),
  SignalEntry('summer', 0.60),
  SignalEntry('autumn', 0.65),
  SignalEntry('fall colors', 0.75),
  SignalEntry('winter', 0.60),

  // --- Descriptive scene requests ---
  SignalEntry('make my house look like', 0.95),
  SignalEntry('make it look like', 0.85),
  SignalEntry('turn my house into', 0.90),
  SignalEntry('transform', 0.65),
  SignalEntry('theme', 0.55),
];

// ---------------------------------------------------------------------------
// Ambiguity boosters
// ---------------------------------------------------------------------------

/// Patterns that push toward AMBIGUOUS when present alongside other signals.
/// These are phrases that could reasonably go either way.
const List<SignalEntry> ambiguitySignals = [
  SignalEntry('something warm', 0.70),
  SignalEntry('something cool', 0.70),
  SignalEntry('something fun', 0.65),
  SignalEntry('something calm', 0.65),
  SignalEntry('something bright', 0.60),
  SignalEntry('change the mood', 0.75),
  SignalEntry('change the vibe', 0.75),
  SignalEntry('different vibe', 0.70),
  SignalEntry('different mood', 0.70),
  SignalEntry('more festive', 0.65),
  SignalEntry('more relaxing', 0.65),
  SignalEntry('more dramatic', 0.65),
  SignalEntry('more romantic', 0.65),
  SignalEntry('more playful', 0.65),
  SignalEntry('make it feel', 0.60),
];

// ---------------------------------------------------------------------------
// Scoring thresholds
// ---------------------------------------------------------------------------

/// Minimum gap between adjustment and new-scene scores required for a
/// confident classification.  If `|adj - new| < kAmbiguityGap`, the result
/// is [CommandClassification.ambiguous].
const double kAmbiguityGap = 0.25;

/// Minimum score on either side required to classify at all.  Below this,
/// the command is treated as ambiguous since we have no strong signal.
const double kMinConfidenceThreshold = 0.30;

/// Bonus applied when the user has an active lighting scene running.
/// An active scene makes "adjustment" more likely for borderline inputs.
const double kActiveSceneAdjustmentBonus = 0.15;

/// Bonus applied when input matches a user's saved favorite/scene name.
const double kFavoriteMatchBonus = 0.40;

/// Bonus for single-color-word input when current scene has multiple colors.
/// E.g., saying "blue" when current scene has red+green+blue — ambiguous.
const double kSingleColorAmbiguityBonus = 0.35;
