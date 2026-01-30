import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';

/// Semantic pattern matcher that ensures consistency through query hashing
/// and provides deep semantic understanding of user queries.
///
/// **Key Innovation**: Instead of pre-defining hundreds of themes, we:
/// 1. Normalize and hash the semantic intent of queries
/// 2. Use the hash as a seed for deterministic AI responses
/// 3. Cache results so identical semantic queries always get identical results
/// 4. Extract rich semantic attributes (mood, vibe, energy, colors) for better matching
///
/// This gives us:
/// - Infinite scalability (handles ANY query)
/// - Perfect consistency (same query = same result)
/// - Semantic awareness ("wedding party" vs "baby shower party" are different)
/// - Rich attribute extraction for precise pattern matching
/// - Integration with EffectDatabase for color-respecting effect selection
class SemanticPatternMatcher {
  /// Cache of query -> pattern results (persists during app session)
  static final Map<String, Map<String, dynamic>> _patternCache = {};

  /// Extracts the semantic "theme" from a query.
  ///
  /// Examples:
  /// - "let's have a wedding party" -> "wedding"
  /// - "make it look like 4th of july" -> "4th of july"
  /// - "birthday bash" -> "birthday"
  /// - "chiefs game day" -> "chiefs"
  ///
  /// Returns null if no clear theme is detected.
  static String? extractTheme(String query) {
    final normalized = query.toLowerCase().trim();

    // Remove common filler words
    final cleaned = normalized
        .replaceAll(RegExp(r"\b(lets|let's|make|it|look|like|have|a|an|the|for|my|our)\b"), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    // Extract core theme words (nouns typically)
    // This is a simplified extraction - in production you'd use NLP
    final words = cleaned.split(' ');

    // Priority keywords that identify themes
    final themeKeywords = <String>[
      // Holidays
      'christmas', 'xmas', 'halloween', 'thanksgiving', 'easter', 'valentines',
      'stpatricks', 'newyears', 'fourthofjuly', '4thofjuly', 'memorialday',
      'laborday', 'mothersday', 'fathersday', 'mardigras', 'cincodemayo',

      // Occasions
      'wedding', 'birthday', 'graduation', 'babyshower', 'baby', 'shower',
      'anniversary', 'engagement', 'retirement', 'housewarming',

      // Sports teams - NFL
      'chiefs', 'cowboys', 'packers', 'patriots', 'steelers', 'eagles',
      'niners', '49ers', 'seahawks', 'broncos', 'raiders', 'chargers',
      'bills', 'dolphins', 'jets', 'ravens', 'bengals', 'browns',
      'texans', 'colts', 'jaguars', 'titans', 'bears', 'lions',
      'vikings', 'falcons', 'panthers', 'saints', 'buccaneers',
      'cardinals', 'rams', 'commanders', 'giants',
      // Sports teams - NBA
      'lakers', 'celtics', 'warriors', 'heat', 'bulls', 'knicks',
      'nets', 'mavericks', 'spurs', 'rockets', 'nuggets', 'suns',
      'bucks', 'sixers', 'raptors', 'clippers', 'thunder', 'grizzlies',
      'pelicans', 'timberwolves', 'blazers', 'jazz', 'kings', 'cavaliers',
      'pistons', 'pacers', 'hawks', 'hornets', 'magic', 'wizards',
      // Sports teams - MLB
      'royals', 'yankees', 'redsox', 'dodgers', 'cubs', 'astros',
      'cardinals', 'braves', 'phillies', 'mets', 'rangers', 'padres',
      'mariners', 'whitesox', 'tigers', 'twins', 'guardians', 'orioles',
      'bluejays', 'rays', 'athletics', 'angels', 'reds', 'brewers',
      'pirates', 'rockies', 'diamondbacks', 'marlins', 'nationals',
      // Sports teams - NHL
      'blackhawks', 'bruins', 'mapleleafs', 'canadiens', 'redwings',
      'penguins', 'flyers', 'avalanche', 'lightning', 'goldenknights',
      'capitals', 'oilers', 'flames', 'blues', 'stars', 'sharks',
      'ducks', 'kraken', 'wild', 'predators', 'hurricanes', 'devils',
      'islanders', 'sabres', 'senators', 'canucks',
      // Sports teams - MLS/Soccer
      'sportingkc', 'galaxy', 'lafc', 'sounders', 'atlantaunited',
      'intermiami',
      // College teams
      'jayhawks', 'wildcats', 'tigers', 'crimsontide', 'buckeyes',
      'wolverines', 'fightingirish', 'longhorns', 'bulldogs', 'sooners',

      // Seasons
      'winter', 'spring', 'summer', 'fall', 'autumn',

      // Moods
      'romantic', 'energetic', 'relaxing', 'elegant', 'cozy', 'peaceful',

      // Nature
      'sunset', 'sunrise', 'ocean', 'beach', 'forest', 'fire', 'rainbow',
      'stars', 'night', 'aurora', 'northern', 'lights',
    ];

    // Find the first theme keyword in the query
    for (final word in words) {
      if (themeKeywords.contains(word)) {
        return word;
      }
    }

    // Check for compound phrases
    final compound = words.join('');
    for (final keyword in themeKeywords) {
      if (compound.contains(keyword)) {
        return keyword;
      }
    }

    return null;
  }

  /// Extracts context modifiers from a query.
  ///
  /// Returns: 'party', 'elegant', 'romantic', 'celebration', 'simple', or null
  static String? extractContext(String query) {
    final normalized = query.toLowerCase();

    if (RegExp(r'\b(party|fun|bash|wild|crazy|energetic|dance)\b').hasMatch(normalized)) {
      return 'party';
    }
    if (RegExp(r'\b(elegant|formal|classy|sophisticated|upscale|fancy|gala)\b').hasMatch(normalized)) {
      return 'elegant';
    }
    if (RegExp(r'\b(romantic|intimate|cozy|date)\b').hasMatch(normalized)) {
      return 'romantic';
    }
    if (RegExp(r'\b(celebration|celebrat|festive|special)\b').hasMatch(normalized)) {
      return 'celebration';
    }
    if (RegExp(r'\b(simple|static|solid|still|calm)\b').hasMatch(normalized)) {
      return 'simple';
    }

    return null;
  }

  /// Creates a deterministic hash of a query for caching.
  ///
  /// The hash is based on:
  /// - The extracted theme (semantic core)
  /// - The extracted context (modifier)
  ///
  /// This ensures:
  /// - "wedding party" and "let's have a wedding party!" hash to the same value
  /// - "wedding" and "wedding party" hash to DIFFERENT values (different context)
  /// - "wedding party" and "baby shower party" hash to DIFFERENT values (different theme)
  static String createQueryHash(String query) {
    final theme = extractTheme(query) ?? 'generic';
    final context = extractContext(query) ?? 'neutral';

    final semanticKey = '$theme:$context';

    // Use Dart's built-in hashCode for deterministic hashing
    return semanticKey.hashCode.toRadixString(16).padLeft(8, '0');
  }

  /// Checks if we have a cached result for this query.
  static Map<String, dynamic>? getCachedPattern(String query) {
    final hash = createQueryHash(query);
    return _patternCache[hash];
  }

  /// Caches a pattern result for future identical queries.
  static void cachePattern(String query, Map<String, dynamic> pattern) {
    final hash = createQueryHash(query);
    _patternCache[hash] = pattern;
    debugPrint('📌 Cached pattern for hash $hash (theme: ${extractTheme(query)}, context: ${extractContext(query)})');
  }

  /// Gets the cache size (for debugging/monitoring).
  static int get cacheSize => _patternCache.length;

  /// Clears the pattern cache (useful for testing or memory management).
  static void clearCache() {
    _patternCache.clear();
    debugPrint('🗑️ Pattern cache cleared');
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // Enhanced Semantic Analysis
  // ═══════════════════════════════════════════════════════════════════════════

  /// Extracts the mood from a query.
  /// Returns a PatternMood that best matches the query intent.
  static PatternMood? extractMood(String query) {
    final normalized = query.toLowerCase();

    // Calm indicators
    if (RegExp(r'\b(calm|peaceful|relaxing|zen|serene|tranquil|soothing|quiet|gentle)\b').hasMatch(normalized)) {
      return PatternMood.calm;
    }
    // Romantic indicators
    if (RegExp(r'\b(romantic|love|valentine|intimate|date|anniversary|sensual|passionate)\b').hasMatch(normalized)) {
      return PatternMood.romantic;
    }
    // Elegant indicators
    if (RegExp(r'\b(elegant|classy|sophisticated|formal|upscale|luxury|refined|fancy|gala)\b').hasMatch(normalized)) {
      return PatternMood.elegant;
    }
    // Festive indicators
    if (RegExp(r'\b(festive|holiday|celebration|party|birthday|christmas|halloween|4th|fourth|thanksgiving|easter)\b').hasMatch(normalized)) {
      return PatternMood.festive;
    }
    // Mysterious indicators
    if (RegExp(r'\b(mysterious|spooky|haunted|eerie|dark|gothic|mystical|magical|enchanted)\b').hasMatch(normalized)) {
      return PatternMood.mysterious;
    }
    // Playful indicators
    if (RegExp(r'\b(playful|fun|silly|whimsical|crazy|wild|goofy|cheerful|bouncy)\b').hasMatch(normalized)) {
      return PatternMood.playful;
    }
    // Magical indicators
    if (RegExp(r'\b(magical|fairy|enchanted|sparkle|glitter|fantasy|dream|wonder)\b').hasMatch(normalized)) {
      return PatternMood.magical;
    }
    // Cozy indicators
    if (RegExp(r'\b(cozy|warm|comfortable|snug|homey|inviting|welcoming)\b').hasMatch(normalized)) {
      return PatternMood.cozy;
    }
    // Energetic indicators
    if (RegExp(r'\b(energetic|exciting|dynamic|fast|intense|power|strong|vibrant|bold)\b').hasMatch(normalized)) {
      return PatternMood.energetic;
    }
    // Dramatic indicators
    if (RegExp(r'\b(dramatic|bold|intense|striking|powerful|majestic|grand|epic)\b').hasMatch(normalized)) {
      return PatternMood.dramatic;
    }

    return null;
  }

  /// Extracts the vibe from a query.
  /// Returns a PatternVibe that best matches the query intent.
  static PatternVibe? extractVibe(String query) {
    final normalized = query.toLowerCase();

    // Serene
    if (RegExp(r'\b(serene|peaceful|zen|calm|tranquil)\b').hasMatch(normalized)) {
      return PatternVibe.serene;
    }
    // Dreamy
    if (RegExp(r'\b(dreamy|dream|soft|ethereal|floating|cloud)\b').hasMatch(normalized)) {
      return PatternVibe.dreamy;
    }
    // Intimate
    if (RegExp(r'\b(intimate|private|personal|close|cozy)\b').hasMatch(normalized)) {
      return PatternVibe.intimate;
    }
    // Luxurious
    if (RegExp(r'\b(luxurious|luxury|premium|high-end|opulent|lavish|rich)\b').hasMatch(normalized)) {
      return PatternVibe.luxurious;
    }
    // Joyful
    if (RegExp(r'\b(joyful|happy|cheerful|bright|sunny|optimistic|upbeat)\b').hasMatch(normalized)) {
      return PatternVibe.joyful;
    }
    // Exciting
    if (RegExp(r'\b(exciting|thrilling|pumped|hype|exhilarating|rush)\b').hasMatch(normalized)) {
      return PatternVibe.exciting;
    }
    // Spooky
    if (RegExp(r'\b(spooky|scary|creepy|haunted|eerie|horror|frightening)\b').hasMatch(normalized)) {
      return PatternVibe.spooky;
    }
    // Whimsical
    if (RegExp(r'\b(whimsical|quirky|playful|fantastical|fanciful|curious)\b').hasMatch(normalized)) {
      return PatternVibe.whimsical;
    }
    // Majestic
    if (RegExp(r'\b(majestic|grand|regal|royal|noble|stately|impressive)\b').hasMatch(normalized)) {
      return PatternVibe.majestic;
    }
    // Tranquil
    if (RegExp(r'\b(tranquil|still|quiet|restful|soothing|mellow)\b').hasMatch(normalized)) {
      return PatternVibe.tranquil;
    }
    // Vibrant
    if (RegExp(r'\b(vibrant|vivid|colorful|lively|energetic|dynamic)\b').hasMatch(normalized)) {
      return PatternVibe.vibrant;
    }
    // Subtle
    if (RegExp(r'\b(subtle|understated|minimal|simple|quiet|low-key|modest)\b').hasMatch(normalized)) {
      return PatternVibe.subtle;
    }
    // Bold
    if (RegExp(r'\b(bold|striking|dramatic|intense|powerful|strong)\b').hasMatch(normalized)) {
      return PatternVibe.bold;
    }
    // Gentle
    if (RegExp(r'\b(gentle|soft|tender|delicate|light|mild)\b').hasMatch(normalized)) {
      return PatternVibe.gentle;
    }
    // Dynamic
    if (RegExp(r'\b(dynamic|moving|flowing|active|animated|kinetic)\b').hasMatch(normalized)) {
      return PatternVibe.dynamic;
    }
    // Warm
    if (RegExp(r'\b(warm|cozy|toasty|comforting|inviting)\b').hasMatch(normalized)) {
      return PatternVibe.warm;
    }
    // Cool
    if (RegExp(r'\b(cool|crisp|fresh|refreshing|icy|frosty)\b').hasMatch(normalized)) {
      return PatternVibe.cool;
    }
    // Natural
    if (RegExp(r'\b(natural|organic|earthy|nature|forest|outdoor)\b').hasMatch(normalized)) {
      return PatternVibe.natural;
    }
    // Modern
    if (RegExp(r'\b(modern|contemporary|sleek|futuristic|tech|cyber|neon)\b').hasMatch(normalized)) {
      return PatternVibe.modern;
    }

    return null;
  }

  /// Extracts desired energy level from a query.
  static EnergyLevel? extractEnergyLevel(String query) {
    final normalized = query.toLowerCase();

    // Very low energy
    if (RegExp(r'\b(still|static|solid|frozen|motionless|fixed)\b').hasMatch(normalized)) {
      return EnergyLevel.veryLow;
    }
    // Low energy
    if (RegExp(r'\b(subtle|gentle|slow|calm|relaxing|peaceful|soft)\b').hasMatch(normalized)) {
      return EnergyLevel.low;
    }
    // Medium energy
    if (RegExp(r'\b(moderate|balanced|steady|flowing|smooth)\b').hasMatch(normalized)) {
      return EnergyLevel.medium;
    }
    // High energy
    if (RegExp(r'\b(fast|quick|energetic|lively|active|bright|bold)\b').hasMatch(normalized)) {
      return EnergyLevel.high;
    }
    // Very high energy
    if (RegExp(r'\b(intense|crazy|wild|extreme|powerful|explosive|maxed)\b').hasMatch(normalized)) {
      return EnergyLevel.veryHigh;
    }

    return null;
  }

  /// Extracts color preferences from a query.
  /// Returns a list of color suggestions based on keywords.
  static List<Color> extractColorPreferences(String query) {
    final normalized = query.toLowerCase();
    final colors = <Color>[];

    // Specific colors
    if (RegExp(r'\b(red|crimson|scarlet|ruby)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFFFF0000));
    }
    if (RegExp(r'\b(blue|azure|cobalt|navy|sapphire)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFF0000FF));
    }
    if (RegExp(r'\b(green|emerald|lime|forest|jade)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFF00FF00));
    }
    if (RegExp(r'\b(yellow|gold|golden|amber|sunshine)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFFFFFF00));
    }
    if (RegExp(r'\b(orange|tangerine|coral)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFFFFA500));
    }
    if (RegExp(r'\b(purple|violet|lavender|plum|magenta)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFF800080));
    }
    if (RegExp(r'\b(pink|rose|blush|fuchsia)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFFFFC0CB));
    }
    if (RegExp(r'\b(cyan|teal|aqua|turquoise)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFF00FFFF));
    }
    if (RegExp(r'\b(white|ivory|cream|pearl)\b').hasMatch(normalized)) {
      colors.add(const Color(0xFFFFFFFF));
    }

    // Themed color combinations
    if (RegExp(r'\b(christmas|xmas|holiday)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFFFF0000), const Color(0xFF00FF00), const Color(0xFFFFFFFF)]);
    }
    if (RegExp(r'\b(halloween|spooky)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFFFF6600), const Color(0xFF800080), const Color(0xFF00FF00)]);
    }
    if (RegExp(r'\b(valentine|romantic|love)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFFFF1493), const Color(0xFFFF69B4), const Color(0xFFFFFFFF)]);
    }
    if (RegExp(r'\b(patriotic|4th|july|america)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFFFF0000), const Color(0xFFFFFFFF), const Color(0xFF0000FF)]);
    }
    if (RegExp(r'\b(ocean|beach|water|sea)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFF0077BE), const Color(0xFF00CED1), const Color(0xFFADD8E6)]);
    }
    if (RegExp(r'\b(sunset|dusk)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFFFF4500), const Color(0xFFFF6347), const Color(0xFFFFD700)]);
    }
    if (RegExp(r'\b(forest|nature|earth)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFF228B22), const Color(0xFF8B4513), const Color(0xFF90EE90)]);
    }
    if (RegExp(r'\b(neon|cyber|futuristic)\b').hasMatch(normalized) && colors.isEmpty) {
      colors.addAll([const Color(0xFF00FFFF), const Color(0xFFFF00FF), const Color(0xFF00FF00)]);
    }

    return colors;
  }

  /// Extracts motion type preference from a query.
  static MotionType? extractMotionType(String query) {
    final normalized = query.toLowerCase();

    // No motion
    if (RegExp(r'\b(static|still|solid|fixed|no\s*motion)\b').hasMatch(normalized)) {
      return MotionType.static;
    }
    // Breathing/pulsing
    if (RegExp(r'\b(breathe|breathing|pulse|pulsing|throb|fade|fading)\b').hasMatch(normalized)) {
      return MotionType.pulsing;
    }
    // Flowing
    if (RegExp(r'\b(flow|flowing|smooth|glide|stream|wave|ripple|gradient)\b').hasMatch(normalized)) {
      return MotionType.flowing;
    }
    // Chasing
    if (RegExp(r'\b(chase|chasing|running|moving|travel|sweep)\b').hasMatch(normalized)) {
      return MotionType.chasing;
    }
    // Twinkling (includes random/scattered effects)
    if (RegExp(r'\b(twinkle|twinkling|sparkle|sparkling|glitter|shimmer|random|scattered|chaotic)\b').hasMatch(normalized)) {
      return MotionType.twinkling;
    }
    // Explosive/expanding
    if (RegExp(r'\b(expand|expanding|grow|spread|burst|explode|fire|flame)\b').hasMatch(normalized)) {
      return MotionType.explosive;
    }
    // Bouncing (mapped to scanning which is similar back-and-forth motion)
    if (RegExp(r'\b(bounce|bouncing|jump|hop|ping\s*pong)\b').hasMatch(normalized)) {
      return MotionType.scanning;
    }
    // Scanning
    if (RegExp(r'\b(scan|scanning|wipe|scroll)\b').hasMatch(normalized)) {
      return MotionType.scanning;
    }

    return null;
  }

  /// Comprehensive query analysis that extracts all semantic attributes.
  /// Returns a QueryAnalysis object with all extracted information.
  static QueryAnalysis analyzeQuery(String query) {
    return QueryAnalysis(
      originalQuery: query,
      theme: extractTheme(query),
      context: extractContext(query),
      mood: extractMood(query),
      vibe: extractVibe(query),
      energyLevel: extractEnergyLevel(query),
      motionType: extractMotionType(query),
      colorPreferences: extractColorPreferences(query),
      queryHash: createQueryHash(query),
    );
  }

  /// Suggests effect IDs based on extracted query attributes.
  /// Only returns color-respecting effects when colors are specified.
  static List<int> suggestEffects(QueryAnalysis analysis, {bool requireColorRespect = true}) {
    final suggestions = <int>[];

    // Map mood/vibe to effect categories
    EffectMoodCategory? targetMood;
    if (analysis.mood != null) {
      targetMood = _patternMoodToEffectMood(analysis.mood!);
    }

    // Map energy level
    EnergyLevel? targetEnergy = analysis.energyLevel;

    // Map motion type
    MotionType? targetMotion = analysis.motionType;

    // Get matching effects from database
    for (final effect in EffectDatabase.effects.values) {
      // Skip color-overriding effects if colors are specified
      if (requireColorRespect && analysis.colorPreferences.isNotEmpty && !effect.respectsColors) {
        continue;
      }

      bool matches = true;

      // Check mood match
      if (targetMood != null && !effect.moods.contains(targetMood)) {
        matches = false;
      }

      // Check energy level match (allow adjacent levels)
      if (targetEnergy != null) {
        final energyDiff = (effect.energyLevel.index - targetEnergy.index).abs();
        if (energyDiff > 1) matches = false;
      }

      // Check motion type match
      if (targetMotion != null && effect.motionType != targetMotion) {
        // Allow compatible motion types
        final compatible = _areMotionTypesCompatible(targetMotion, effect.motionType);
        if (!compatible) matches = false;
      }

      if (matches) {
        suggestions.add(effect.id);
      }
    }

    // Limit to top 5 suggestions
    return suggestions.take(5).toList();
  }

  /// Converts PatternMood to EffectMoodCategory
  static EffectMoodCategory? _patternMoodToEffectMood(PatternMood mood) {
    switch (mood) {
      case PatternMood.calm:
        return EffectMoodCategory.calm;
      case PatternMood.romantic:
        return EffectMoodCategory.romantic;
      case PatternMood.elegant:
        return EffectMoodCategory.elegant;
      case PatternMood.festive:
        return EffectMoodCategory.festive;
      case PatternMood.mysterious:
        return EffectMoodCategory.mysterious;
      case PatternMood.playful:
        return EffectMoodCategory.playful;
      case PatternMood.magical:
        return EffectMoodCategory.magical;
      case PatternMood.cozy:
        return EffectMoodCategory.calm;
      case PatternMood.energetic:
        return EffectMoodCategory.festive; // Map energetic to festive (high energy)
      case PatternMood.dramatic:
        return EffectMoodCategory.mysterious; // Map dramatic to mysterious (intense)
    }
  }

  /// Checks if two motion types are compatible (close enough in style)
  static bool _areMotionTypesCompatible(MotionType requested, MotionType actual) {
    // Define compatibility groups
    final flowingGroup = {MotionType.flowing, MotionType.pulsing};
    final chasingGroup = {MotionType.chasing, MotionType.scanning};
    final sparkleGroup = {MotionType.twinkling, MotionType.explosive};

    if (flowingGroup.contains(requested) && flowingGroup.contains(actual)) return true;
    if (chasingGroup.contains(requested) && chasingGroup.contains(actual)) return true;
    if (sparkleGroup.contains(requested) && sparkleGroup.contains(actual)) return true;

    return false;
  }
}

/// Comprehensive analysis result from semantic query processing.
class QueryAnalysis {
  final String originalQuery;
  final String? theme;
  final String? context;
  final PatternMood? mood;
  final PatternVibe? vibe;
  final EnergyLevel? energyLevel;
  final MotionType? motionType;
  final List<Color> colorPreferences;
  final String queryHash;

  const QueryAnalysis({
    required this.originalQuery,
    this.theme,
    this.context,
    this.mood,
    this.vibe,
    this.energyLevel,
    this.motionType,
    this.colorPreferences = const [],
    required this.queryHash,
  });

  /// Whether this query has specific color requests
  bool get hasColorPreferences => colorPreferences.isNotEmpty;

  /// Whether this query has mood/vibe specifications
  bool get hasMoodSpecification => mood != null || vibe != null;

  /// Whether this query has motion/energy specifications
  bool get hasMotionSpecification => motionType != null || energyLevel != null;

  /// Returns a summary string of the analysis
  String get summary {
    final parts = <String>[];
    if (theme != null) parts.add('theme: $theme');
    if (context != null) parts.add('context: $context');
    if (mood != null) parts.add('mood: ${mood!.name}');
    if (vibe != null) parts.add('vibe: ${vibe!.name}');
    if (energyLevel != null) parts.add('energy: ${energyLevel!.name}');
    if (motionType != null) parts.add('motion: ${motionType!.name}');
    if (colorPreferences.isNotEmpty) parts.add('colors: ${colorPreferences.length}');
    return parts.isEmpty ? 'generic query' : parts.join(', ');
  }

  @override
  String toString() => 'QueryAnalysis($summary)';
}
