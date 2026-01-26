import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';

/// Context modifiers that affect pattern selection within a theme.
enum EventContext {
  neutral, // Default - use primary pattern
  party, // High energy - chase, fireworks, fast movement
  elegant, // Sophisticated - breathe, slow twinkle, subtle
  romantic, // Soft - gentle breathe, slow glow
  celebration, // Medium energy - twinkle, sparkle
  staticSimple, // No movement - solid colors
}

/// Result of matching a query to an event theme with context.
class EventThemeMatch {
  final EventTheme theme;
  final EventContext context;

  const EventThemeMatch({
    required this.theme,
    required this.context,
  });

  /// Gets the appropriate pattern for this theme given the context.
  GradientPattern get pattern => theme.patternForContext(context);
}

/// Deterministic event theme library for consistent pattern matching.
///
/// This library ensures that:
/// - Same query = Same result (e.g., "wedding party" always returns identical pattern)
/// - Similar phrases map to the same theme (e.g., "let's have a wedding" -> "wedding")
/// - Different events get distinct, appropriate patterns
class EventThemeLibrary {
  /// Maps normalized query keywords to EventTheme objects.
  /// Keywords are lowercase, stemmed, and include common variations.
  static final Map<String, EventTheme> _themesByKeyword = {
    // Wedding themes
    'wedding': EventTheme.wedding,
    'wed': EventTheme.wedding,
    'marriage': EventTheme.wedding,
    'bride': EventTheme.wedding,
    'groom': EventTheme.wedding,
    'nuptial': EventTheme.wedding,
    'bridal': EventTheme.wedding,
    'matrimony': EventTheme.wedding,

    // Birthday themes
    'birthday': EventTheme.birthday,
    'bday': EventTheme.birthday,
    'birt': EventTheme.birthday,
    'celebration': EventTheme.birthday,

    // Baby shower
    'babyshower': EventTheme.babyShower,
    'baby': EventTheme.babyShower,
    'shower': EventTheme.babyShower,
    'infant': EventTheme.babyShower,
    'newborn': EventTheme.babyShower,

    // Anniversary
    'anniversary': EventTheme.anniversary,
    'anniv': EventTheme.anniversary,

    // Graduation
    'graduation': EventTheme.graduation,
    'grad': EventTheme.graduation,
    'graduate': EventTheme.graduation,
    'commencement': EventTheme.graduation,

    // Engagement
    'engagement': EventTheme.engagement,
    'engaged': EventTheme.engagement,
    'propose': EventTheme.engagement,
    'proposal': EventTheme.engagement,

    // Retirement
    'retirement': EventTheme.retirement,
    'retire': EventTheme.retirement,

    // Housewarming
    'housewarming': EventTheme.housewarming,
    'housewarm': EventTheme.housewarming,
    'newhome': EventTheme.housewarming,

    // Holiday (fall back to recommended patterns)
    'holiday': EventTheme.holiday,
    'holidays': EventTheme.holiday,

    // Party (generic celebration)
    'party': EventTheme.genericParty,
    'celebrate': EventTheme.genericParty,
    'celebration': EventTheme.genericParty,
  };

  /// Analyzes a user query and returns the best matching EventTheme with context.
  /// Returns null if no theme matches.
  ///
  /// Algorithm:
  /// 1. Normalize query (lowercase, remove punctuation)
  /// 2. Extract keywords (split on whitespace)
  /// 3. Check for direct keyword matches
  /// 4. Detect context modifiers (party, elegant, formal, fun, etc.)
  /// 5. Return theme with context modifier
  static EventThemeMatch? matchQuery(String query) {
    final normalized = _normalizeQuery(query);
    final words = normalized.split(RegExp(r'\s+'));

    EventTheme? matchedTheme;

    // Direct exact match
    for (final word in words) {
      if (_themesByKeyword.containsKey(word)) {
        matchedTheme = _themesByKeyword[word]!;
        break;
      }
    }

    // Partial word match (e.g., "weddings" matches "wedding")
    if (matchedTheme == null) {
      for (final word in words) {
        for (final keyword in _themesByKeyword.keys) {
          // Check if word starts with keyword or vice versa (minimum 4 chars overlap)
          if (word.length >= 4 && keyword.length >= 4) {
            if (word.startsWith(keyword) || keyword.startsWith(word)) {
              matchedTheme = _themesByKeyword[keyword]!;
              break;
            }
          }
        }
        if (matchedTheme != null) break;
      }
    }

    // Compound phrase detection (e.g., "baby shower party")
    if (matchedTheme == null) {
      final compoundPhrase = normalized.replaceAll(RegExp(r'\s+'), '');
      if (_themesByKeyword.containsKey(compoundPhrase)) {
        matchedTheme = _themesByKeyword[compoundPhrase]!;
      }
    }

    if (matchedTheme == null) return null;

    // Detect context modifiers
    final context = detectContext(normalized);

    return EventThemeMatch(
      theme: matchedTheme,
      context: context,
    );
  }

  /// Detects context modifiers in the query to select appropriate pattern variation.
  ///
  /// Modifiers control which pattern variant is selected within a theme:
  /// - party/fun/energetic → High-energy patterns (chase, fireworks, fast movement)
  /// - elegant/formal/classy → Sophisticated patterns (breathe, slow twinkle, subtle)
  /// - romantic/intimate → Soft patterns (gentle breathe, slow glow)
  /// - celebration/festive → Medium-energy patterns (twinkle, sparkle)
  /// - static/solid/simple → No-movement solid colors
  static EventContext detectContext(String normalized) {
    // Party/Fun context (high energy)
    if (normalized.contains('party') ||
        normalized.contains('fun') ||
        normalized.contains('energetic') ||
        normalized.contains('dance') ||
        normalized.contains('bash') ||
        normalized.contains('wild') ||
        normalized.contains('crazy')) {
      return EventContext.party;
    }

    // Elegant/Formal context (sophisticated, slow movement)
    if (normalized.contains('elegant') ||
        normalized.contains('formal') ||
        normalized.contains('classy') ||
        normalized.contains('sophisticated') ||
        normalized.contains('upscale') ||
        normalized.contains('fancy') ||
        normalized.contains('gala')) {
      return EventContext.elegant;
    }

    // Romantic/Intimate context (soft, gentle)
    if (normalized.contains('romantic') ||
        normalized.contains('intimate') ||
        normalized.contains('cozy') ||
        normalized.contains('date')) {
      return EventContext.romantic;
    }

    // Static/Simple context (no movement)
    if (normalized.contains('static') ||
        normalized.contains('solid') ||
        normalized.contains('simple') ||
        normalized.contains('still') ||
        normalized.contains('calm')) {
      return EventContext.staticSimple;
    }

    // Celebration/Festive context (medium energy)
    if (normalized.contains('celebrat') ||
        normalized.contains('festive') ||
        normalized.contains('special') ||
        normalized.contains('occasion')) {
      return EventContext.celebration;
    }

    // Default: neutral (use primary pattern)
    return EventContext.neutral;
  }

  /// Normalizes a query string for matching:
  /// - Lowercase
  /// - Remove punctuation
  /// - Trim whitespace
  static String _normalizeQuery(String query) {
    return query
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '') // Remove punctuation
        .replaceAll(RegExp(r'\s+'), ' ') // Normalize whitespace
        .trim();
  }

  /// Returns all available event themes for browsing.
  static List<EventTheme> get allThemes => [
        EventTheme.wedding,
        EventTheme.birthday,
        EventTheme.babyShower,
        EventTheme.anniversary,
        EventTheme.graduation,
        EventTheme.engagement,
        EventTheme.retirement,
        EventTheme.housewarming,
        EventTheme.genericParty,
      ];
}

/// Represents a complete event theme with multiple pattern variations.
/// Each theme has 3-5 distinct patterns to provide variety within consistency.
///
/// Pattern organization:
/// - Index 0: Neutral/Default (elegant, medium movement)
/// - Index 1: Party/Fun (high energy, chase/fireworks)
/// - Index 2: Elegant/Formal (slow, sophisticated)
/// - Index 3: Static/Simple (no movement)
/// - Index 4+: Additional variations
class EventTheme {
  final String id;
  final String name;
  final String description;
  final List<GradientPattern> patterns;

  const EventTheme({
    required this.id,
    required this.name,
    required this.description,
    required this.patterns,
  });

  /// Primary pattern (always returned for neutral context)
  GradientPattern get primaryPattern => patterns.first;

  /// Returns a pattern by index (for variations)
  GradientPattern pattern(int index) => patterns[index % patterns.length];

  /// Selects the most appropriate pattern based on context modifiers.
  GradientPattern patternForContext(EventContext context) {
    switch (context) {
      case EventContext.neutral:
        return patterns[0]; // Primary pattern

      case EventContext.party:
        // Prefer high-energy patterns (chase, fireworks, fast)
        // Look for patterns with high speed or energetic effects
        final party = patterns.firstWhere(
          (p) => p.speed > 120 || p.effectId == 52 || p.effectId == 12 || p.effectId == 41,
          orElse: () => patterns.length > 1 ? patterns[1] : patterns[0],
        );
        return party;

      case EventContext.elegant:
        // Prefer sophisticated patterns (breathe, slow twinkle)
        final elegant = patterns.firstWhere(
          (p) => p.effectId == 2 || p.effectId == 43 || (p.speed < 80 && !p.isStatic),
          orElse: () => patterns.length > 2 ? patterns[2] : patterns[0],
        );
        return elegant;

      case EventContext.romantic:
        // Prefer soft breathe or gentle glow
        final romantic = patterns.firstWhere(
          (p) => p.effectId == 2 || (p.speed < 60 && !p.isStatic),
          orElse: () => patterns.length > 2 ? patterns[2] : patterns[0],
        );
        return romantic;

      case EventContext.celebration:
        // Medium energy - twinkle, sparkle, moderate speed
        final celebration = patterns.firstWhere(
          (p) => p.effectId == 43 || p.effectId == 72 || (p.speed >= 80 && p.speed <= 140),
          orElse: () => patterns.length > 1 ? patterns[1] : patterns[0],
        );
        return celebration;

      case EventContext.staticSimple:
        // Solid, no movement
        final staticPattern = patterns.firstWhere(
          (p) => p.isStatic || p.effectId == 0,
          orElse: () => patterns.length > 3 ? patterns[3] : patterns[0],
        );
        return staticPattern;
    }
  }

  // === WEDDING THEMES ===
  // Pattern order: [0] Neutral, [1] Party, [2] Elegant, [3] Static
  static const wedding = EventTheme(
    id: 'wedding',
    name: 'Wedding',
    description: 'Elegant and romantic wedding celebration',
    patterns: [
      // [0] Neutral - Gentle breathe, medium elegance
      GradientPattern(
        name: 'Wedding Elegance',
        subtitle: 'Soft Champagne & White Breathe',
        colors: [
          Color(0xFFF7E7CE), // Champagne gold
          Color(0xFFFFFAFA), // Soft white
          Color(0xFFFFE4E1), // Misty rose
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 50,
        intensity: 120,
        brightness: 220,
      ),
      // [1] Party - Celebration sparkle with movement
      GradientPattern(
        name: 'Wedding Party',
        subtitle: 'Rose Gold & White Sparkle',
        colors: [
          Color(0xFFB76E79), // Rose gold
          Color(0xFFFFFFFF), // White
          Color(0xFFFFD700), // Gold
        ],
        effectId: 72,
        effectName: 'Sparkle',
        direction: 'none',
        isStatic: false,
        speed: 140,
        intensity: 200,
        brightness: 240,
      ),
      // [2] Elegant/Romantic - Very slow, sophisticated
      GradientPattern(
        name: 'Wedding Romance',
        subtitle: 'Champagne Candle Glow',
        colors: [
          Color(0xFFF7E7CE), // Champagne
          Color(0xFFFFE4E1), // Misty rose
          Color(0xFFFFFAFA), // Soft white
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 30,
        intensity: 90,
        brightness: 200,
      ),
      // [3] Static - Pure elegance, no movement
      GradientPattern(
        name: 'Wedding Classic',
        subtitle: 'Pure White & Champagne',
        colors: [
          Color(0xFFFFFFFF), // Pure white
          Color(0xFFF7E7CE), // Champagne gold
        ],
        effectId: 0,
        effectName: 'Solid',
        direction: 'none',
        isStatic: true,
        brightness: 240,
      ),
    ],
  );

  // === BIRTHDAY THEMES ===
  // Pattern order: [0] Neutral, [1] Party, [2] Elegant, [3] Static
  static const birthday = EventTheme(
    id: 'birthday',
    name: 'Birthday',
    description: 'Fun and festive birthday party',
    patterns: [
      // [0] Neutral - Medium energy celebration
      GradientPattern(
        name: 'Birthday Celebration',
        subtitle: 'Colorful Twinkle',
        colors: [
          Color(0xFFFF69B4), // Hot pink
          Color(0xFF00CED1), // Dark turquoise
          Color(0xFFFFD700), // Gold
          Color(0xFF9370DB), // Purple
        ],
        effectId: 43,
        effectName: 'Twinkle',
        direction: 'alternating',
        isStatic: false,
        speed: 100,
        intensity: 180,
        brightness: 240,
      ),
      // [1] Party - High energy fireworks/chase
      GradientPattern(
        name: 'Birthday Bash',
        subtitle: 'Rainbow Confetti Fireworks',
        colors: [
          Color(0xFFFF1493), // Deep pink
          Color(0xFF00FFFF), // Cyan
          Color(0xFFFFD700), // Gold
          Color(0xFF9370DB), // Medium purple
        ],
        effectId: 52,
        effectName: 'Fireworks',
        direction: 'center-out',
        isStatic: false,
        speed: 180,
        intensity: 240,
        brightness: 255,
      ),
      // [2] Elegant - Candle flicker
      GradientPattern(
        name: 'Birthday Candles',
        subtitle: 'Warm Candle Glow',
        colors: [
          Color(0xFFFFD700), // Gold
          Color(0xFFFF8C00), // Dark orange
          Color(0xFFFFB347), // Warm amber
        ],
        effectId: 37,
        effectName: 'Candle',
        direction: 'none',
        isStatic: false,
        speed: 70,
        intensity: 160,
        brightness: 220,
      ),
      // [3] Static - Colorful solid
      GradientPattern(
        name: 'Birthday Colors',
        subtitle: 'Festive Color Display',
        colors: [
          Color(0xFFFF69B4), // Hot pink
          Color(0xFF00CED1), // Turquoise
          Color(0xFFFFD700), // Gold
        ],
        effectId: 0,
        effectName: 'Solid',
        direction: 'none',
        isStatic: true,
        brightness: 255,
      ),
    ],
  );

  // === BABY SHOWER THEMES ===
  // Pattern order: [0] Neutral, [1] Party, [2] Elegant, [3] Static
  static const babyShower = EventTheme(
    id: 'babyshower',
    name: 'Baby Shower',
    description: 'Gentle pastel celebration for new arrivals',
    patterns: [
      // [0] Neutral - Gentle breathe
      GradientPattern(
        name: 'Baby Shower Pastels',
        subtitle: 'Soft Pink, Blue & Yellow Breathe',
        colors: [
          Color(0xFFFFB6D9), // Baby pink
          Color(0xFFADD8E6), // Light blue
          Color(0xFFFDFD96), // Pastel yellow
          Color(0xFFE6E6FA), // Lavender
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 55,
        intensity: 130,
        brightness: 210,
      ),
      // [1] Party - Playful twinkle with movement
      GradientPattern(
        name: 'Baby Shower Party',
        subtitle: 'Playful Pastel Twinkle',
        colors: [
          Color(0xFFFFB6D9), // Baby pink
          Color(0xFFADD8E6), // Light blue
          Color(0xFFFDFD96), // Pastel yellow
        ],
        effectId: 43,
        effectName: 'Twinkle',
        direction: 'alternating',
        isStatic: false,
        speed: 90,
        intensity: 170,
        brightness: 220,
      ),
      // [2] Elegant - Very gentle, slow breathe
      GradientPattern(
        name: 'Baby Dreams',
        subtitle: 'Gentle Lullaby Glow',
        colors: [
          Color(0xFFFFB6D9), // Baby pink
          Color(0xFFADD8E6), // Light blue
          Color(0xFFFFFFFF), // White
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 35,
        intensity: 100,
        brightness: 180,
      ),
      // [3] Static - Soft solid pastels
      GradientPattern(
        name: 'Nursery Glow',
        subtitle: 'Soft Pastel Light',
        colors: [
          Color(0xFFFFB6D9), // Baby pink
          Color(0xFFADD8E6), // Light blue
          Color(0xFFFFF5EE), // Seashell
        ],
        effectId: 0,
        effectName: 'Solid',
        direction: 'none',
        isStatic: true,
        brightness: 200,
      ),
    ],
  );

  // === ANNIVERSARY THEMES ===
  static const anniversary = EventTheme(
    id: 'anniversary',
    name: 'Anniversary',
    description: 'Romantic celebration of love',
    patterns: [
      GradientPattern(
        name: 'Anniversary Romance',
        subtitle: 'Deep Red & Rose Gold',
        colors: [
          Color(0xFF8B0000), // Dark red
          Color(0xFFB76E79), // Rose gold
          Color(0xFFFFE4E1), // Misty rose
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 45,
        intensity: 140,
        brightness: 200,
      ),
      GradientPattern(
        name: 'Love & Light',
        subtitle: 'Ruby Red Sparkle',
        colors: [
          Color(0xFFE0115F), // Ruby
          Color(0xFFFF69B4), // Hot pink
          Color(0xFFFFD700), // Gold
        ],
        effectId: 72,
        effectName: 'Sparkle',
        direction: 'none',
        isStatic: false,
        speed: 80,
        intensity: 160,
        brightness: 210,
      ),
    ],
  );

  // === GRADUATION THEMES ===
  static const graduation = EventTheme(
    id: 'graduation',
    name: 'Graduation',
    description: 'Achievement celebration',
    patterns: [
      GradientPattern(
        name: 'Graduation Pride',
        subtitle: 'School Colors Flow',
        colors: [
          Color(0xFF000080), // Navy blue
          Color(0xFFFFD700), // Gold
          Color(0xFFFFFFFF), // White
        ],
        effectId: 41, // Running - uses segment colors (Flow is palette-based)
        effectName: 'Running',
        direction: 'right',
        isStatic: false,
        speed: 100,
        intensity: 180,
        brightness: 230,
      ),
      GradientPattern(
        name: 'Achievement Glow',
        subtitle: 'Gold & White Chase',
        colors: [
          Color(0xFFFFD700), // Gold
          Color(0xFFFFFFFF), // White
        ],
        effectId: 12,
        effectName: 'Theater Chase',
        direction: 'right',
        isStatic: false,
        speed: 110,
        intensity: 190,
        brightness: 240,
      ),
    ],
  );

  // === ENGAGEMENT THEMES ===
  static const engagement = EventTheme(
    id: 'engagement',
    name: 'Engagement',
    description: 'Celebratory engagement party',
    patterns: [
      GradientPattern(
        name: 'Engagement Sparkle',
        subtitle: 'Diamond White & Rose Gold',
        colors: [
          Color(0xFFFFFFFF), // Diamond white
          Color(0xFFB76E79), // Rose gold
          Color(0xFFFFE4E1), // Misty rose
        ],
        effectId: 72,
        effectName: 'Sparkle',
        direction: 'none',
        isStatic: false,
        speed: 90,
        intensity: 180,
        brightness: 230,
      ),
      GradientPattern(
        name: 'Ring Glow',
        subtitle: 'Romantic Pink & Gold',
        colors: [
          Color(0xFFFF69B4), // Hot pink
          Color(0xFFFFD700), // Gold
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 55,
        intensity: 150,
        brightness: 210,
      ),
    ],
  );

  // === RETIREMENT THEMES ===
  static const retirement = EventTheme(
    id: 'retirement',
    name: 'Retirement',
    description: 'Celebration of a career well done',
    patterns: [
      GradientPattern(
        name: 'Retirement Gold',
        subtitle: 'Golden Years Glow',
        colors: [
          Color(0xFFFFD700), // Gold
          Color(0xFFDAA520), // Goldenrod
          Color(0xFFF5F5DC), // Beige
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 50,
        intensity: 130,
        brightness: 210,
      ),
      GradientPattern(
        name: 'Relaxation Mode',
        subtitle: 'Warm Amber Solid',
        colors: [
          Color(0xFFFFB347), // Warm amber
          Color(0xFFFFE4B5), // Moccasin
        ],
        effectId: 0,
        effectName: 'Solid',
        direction: 'none',
        isStatic: true,
        brightness: 190,
      ),
    ],
  );

  // === HOUSEWARMING THEMES ===
  static const housewarming = EventTheme(
    id: 'housewarming',
    name: 'Housewarming',
    description: 'Welcome to your new home',
    patterns: [
      GradientPattern(
        name: 'Home Sweet Home',
        subtitle: 'Warm Welcome Glow',
        colors: [
          Color(0xFFFFB347), // Warm amber
          Color(0xFFFFF8DC), // Cornsilk
          Color(0xFFFFE4B5), // Moccasin
        ],
        effectId: 2,
        effectName: 'Breathe',
        direction: 'none',
        isStatic: false,
        speed: 60,
        intensity: 140,
        brightness: 220,
      ),
      GradientPattern(
        name: 'New Beginnings',
        subtitle: 'Fresh White & Gold',
        colors: [
          Color(0xFFFFFFFF), // White
          Color(0xFFFFD700), // Gold
        ],
        effectId: 43,
        effectName: 'Twinkle',
        direction: 'alternating',
        isStatic: false,
        speed: 70,
        intensity: 150,
        brightness: 230,
      ),
    ],
  );

  // === HOLIDAY (Generic) ===
  static const holiday = EventTheme(
    id: 'holiday',
    name: 'Holiday',
    description: 'General holiday celebration',
    patterns: [
      GradientPattern(
        name: 'Holiday Cheer',
        subtitle: 'Festive Multicolor',
        colors: [
          Color(0xFFFF0000), // Red
          Color(0xFF00FF00), // Green
          Color(0xFFFFD700), // Gold
        ],
        effectId: 43,
        effectName: 'Twinkle',
        direction: 'alternating',
        isStatic: false,
        speed: 80,
        intensity: 180,
        brightness: 230,
      ),
    ],
  );

  // === GENERIC PARTY ===
  static const genericParty = EventTheme(
    id: 'party',
    name: 'Party',
    description: 'Fun celebration',
    patterns: [
      GradientPattern(
        name: 'Party Time',
        subtitle: 'Vibrant Fireworks',
        colors: [
          Color(0xFFFF1493), // Deep pink
          Color(0xFF00FFFF), // Cyan
          Color(0xFF9370DB), // Medium purple
          Color(0xFFFFD700), // Gold
        ],
        effectId: 52,
        effectName: 'Fireworks',
        direction: 'center-out',
        isStatic: false,
        speed: 180,
        intensity: 240,
        brightness: 255,
      ),
      GradientPattern(
        name: 'Dance Party',
        subtitle: 'Neon Chase',
        colors: [
          Color(0xFFFF00FF), // Magenta
          Color(0xFF00FFFF), // Cyan
          Color(0xFFFFFF00), // Yellow
        ],
        effectId: 41,
        effectName: 'Running',
        direction: 'right',
        isStatic: false,
        speed: 200,
        intensity: 255,
        brightness: 255,
      ),
    ],
  );
}
