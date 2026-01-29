import 'package:flutter/foundation.dart';

/// Semantic pattern matcher that ensures consistency through query hashing.
///
/// **Key Innovation**: Instead of pre-defining hundreds of themes, we:
/// 1. Normalize and hash the semantic intent of queries
/// 2. Use the hash as a seed for deterministic AI responses
/// 3. Cache results so identical semantic queries always get identical results
///
/// This gives us:
/// - Infinite scalability (handles ANY query)
/// - Perfect consistency (same query = same result)
/// - Semantic awareness ("wedding party" vs "baby shower party" are different)
/// - Minimal maintenance (no need to define every possible scenario)
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
}
