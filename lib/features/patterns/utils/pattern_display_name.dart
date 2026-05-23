/// Centralized pattern display-name resolver for Now Playing and any other
/// UI surface that renders a slug-style pattern identifier.
///
/// Replaces the old per-callsite logic:
///   - [_humanizePresetName] in display_pattern_providers.dart, which
///     title-cased every chunk and produced "Kc Royals Game Day" (note
///     the broken acronym).
///   - [_teamShortName] in lumina_brain.dart, which was only consulted
///     when LuminaBrain composed a pattern name internally.
///
/// Resolution order:
///   1. Empty/null-ish input → empty string.
///   2. Input already contains non-slug characters (spaces, punctuation,
///      etc.) → returned unchanged. We assume any already-humanized
///      label is properly cased.
///   3. Explicit slug overrides ([_slugOverrides]) — known patterns like
///      team Game Day variants, holidays, customer scenes.
///   4. Underscore split + acronym preservation ([_kAcronyms]) +
///      Title Case fallback for remaining chunks.
library;

import 'package:flutter/foundation.dart' show visibleForTesting;

/// Two- and three-letter chunks that should preserve uppercase when they
/// appear in a pattern slug. Explicit allowlist (per Item #88c spec):
/// rule-based "any 2-3 char chunk" would incorrectly uppercase "St", "Mr",
/// "Dr", etc. Add new entries when a new acronym pattern ships.
const Set<String> _kAcronyms = <String>{
  'KC', 'AI', 'NY', 'LA', 'SF', 'DC', 'US', 'UK',
  'CL', // Champions League prefix — added 2026-05-23 (Fix 3 Part 2)
  'NFL', 'NBA', 'MLB', 'NHL', 'MLS',
};

/// Maps a team's official name (with spaces, e.g. "Boston Red Sox") to the
/// preferred short form for UI display (e.g. "Red Sox"). Source of truth
/// moved here from lumina_brain.dart's private _teamShortName helper.
///
/// ~354 standard "City Mascot" team names are NOT in this map; they fall
/// through to [teamShortName]'s `.split(' ').last` default. Entries are
/// only needed when:
///   - League suffix removal (FC, SC, CF, CP)
///   - .last yields ambiguous/generic word (City, United, Lake, Club)
///   - City shared by rival clubs (Milan, Madrid)
///   - Multi-word nicknames (Red Sox, Blue Jays, Golden Knights)
const Map<String, String> _kTeamShortNames = <String, String>{
  // League suffixes — .last returns meaningless "FC"/"SC"/"CF"/"CP"
  'Atlanta United FC': 'Atlanta Utd',
  'Austin FC': 'Austin',
  'Bay FC': 'Bay',
  'Charlotte FC': 'Charlotte',
  'Chicago Fire FC': 'Fire',
  'Houston Dynamo FC': 'Dynamo',
  'Inter Miami CF': 'Inter Miami',
  'Los Angeles FC': 'LAFC',
  'Nashville SC': 'Nashville',
  'New York City FC': 'NYCFC',
  'NJ/NY Gotham FC': 'Gotham',
  'Orlando City SC': 'Orlando City',
  'Portland Thorns FC': 'Thorns',
  'Racing Louisville FC': 'Louisville',
  'San Diego Wave FC': 'Wave',
  'Seattle Reign FC': 'Reign',
  'St. Louis CITY SC': 'St. Louis City',
  'Angel City FC': 'Angel City',
  'Utah Royals FC': 'Utah Royals',
  'Celtic FC': 'Celtic',
  'Sporting CP': 'Sporting',
  // .last = "City"/"United"/"Lake"/"Club" — generic or ambiguous
  'Sporting Kansas City': 'Sporting KC',
  'Manchester City': 'Man City',
  'Manchester United': 'Man United',
  'Newcastle United': 'Newcastle',
  'Sheffield United': 'Sheffield Utd',
  'West Ham United': 'West Ham',
  'D.C. United': 'DC United',
  'Real Salt Lake': 'RSL',
  'Utah Hockey Club': 'Utah HC',
  // .last = "Milan"/"Madrid" — city shared by rival clubs
  'AC Milan': 'AC Milan',
  'Inter Milan': 'Inter',
  'Real Madrid': 'Real Madrid',
  'Atletico Madrid': 'Atletico',
  // Multi-word nicknames — .last drops a critical word
  'Boston Red Sox': 'Red Sox',
  'Chicago White Sox': 'White Sox',
  'Toronto Blue Jays': 'Blue Jays',
  'New York Red Bulls': 'Red Bulls',
  'Texas Tech Red Raiders': 'Red Raiders',
  'North Carolina Tar Heels': 'Tar Heels',
  'TCU Horned Frogs': 'Horned Frogs',
  'Vegas Golden Knights': 'Golden Knights',
  'Rutgers Scarlet Knights': 'Scarlet Knights',
  'Penn State Nittany Lions': 'Nittany Lions',
  'Arizona State Sun Devils': 'Sun Devils',
  'Paris Saint-Germain': 'PSG',
};

/// One-off slug overrides not derivable from team data. Add Lumina-specific
/// pattern names here when a deterministic transform isn't possible.
const Map<String, String> _kExtraOverrides = <String, String>{
  'KC_Royals_Game_Day': 'KC Royals Game Day',
};

/// The three Lumina-canonical suffixes appended to a team name to form a
/// pattern slug. Generates 3 slug entries per team in [_kTeamShortNames].
const List<String> _kTeamPatternSuffixes = <String>[
  'Game_Day',
  'Twinkle',
  'Wave',
];

/// Built once at first call. Composed from [_kTeamShortNames] (38 teams ×
/// 3 suffixes = 114 entries) plus [_kExtraOverrides]. Lazily initialized
/// to keep startup work flat — first call to [displayNameFor] for a slug
/// not in the cache pays the build cost.
Map<String, String>? _slugOverridesCache;

Map<String, String> get _slugOverrides {
  final cached = _slugOverridesCache;
  if (cached != null) return cached;
  final built = <String, String>{};
  for (final entry in _kTeamShortNames.entries) {
    // Replace spaces with underscores. Punctuation (periods, slashes) is
    // left in place — slugs like 'D.C._United_Game_Day' would match if a
    // caller passes that exact form. Otherwise the title-case fallback
    // produces a serviceable display.
    final slugBase = entry.key.replaceAll(' ', '_');
    final shortName = entry.value;
    for (final suffix in _kTeamPatternSuffixes) {
      final humanSuffix = suffix.replaceAll('_', ' ');
      built['${slugBase}_$suffix'] = '$shortName $humanSuffix';
    }
  }
  built.addAll(_kExtraOverrides);
  return _slugOverridesCache = Map<String, String>.unmodifiable(built);
}

/// Slug-shape regex: characters that can appear in a snake-case identifier
/// without spaces or punctuation. If the input has anything else (a space,
/// a dash, an apostrophe, etc.) it's not a slug and we return it unchanged.
final RegExp _slugRegex = RegExp(r'^[A-Za-z0-9_]+$');

/// Resolve a pattern slug (or any pattern identifier) to a UI-ready
/// display name.
///
/// Examples:
///   displayNameFor('KC_Royals_Game_Day')         // 'KC Royals Game Day'
///   displayNameFor('Boston_Red_Sox_Twinkle')     // 'Red Sox Twinkle'
///   displayNameFor('St_Louis_Cardinals_Twinkle') // 'St Louis Cardinals Twinkle'
///   displayNameFor('warm_white')                 // 'Warm White'
///   displayNameFor('Already Named Properly')     // 'Already Named Properly'
///   displayNameFor('')                           // ''
String displayNameFor(String rawId) {
  if (rawId.isEmpty) return '';

  // Pure-slug path: matches the original behavior.
  if (_slugRegex.hasMatch(rawId)) {
    // Explicit override.
    final override = _slugOverrides[rawId];
    if (override != null) return override;
    // Underscore split + acronym preservation + title case.
    final chunks = rawId.split('_').where((c) => c.isNotEmpty);
    return chunks.map(_titleCaseOrAcronym).join(' ');
  }

  // Mixed-input path (Fix 3 Part 2, 2026-05-23): the input has a
  // space, hyphen, or other non-slug character. Pre-fix this returned
  // the input unchanged, which let label hints like "Nfl_bills Game
  // Day" leak the underscore through to Now Playing. Now we tokenize
  // on spaces and humanize any token that still contains underscores.
  //
  // - "Nfl_bills Game Day"    → "NFL Bills Game Day"
  // - "Pattern: warm_white"   → "Pattern: Warm White"
  // - "Already Clean Label"   → unchanged (no underscore chunks)
  // - "Tyler's House"         → unchanged (no underscore chunks)
  //
  // Tokens without underscores pass through verbatim so punctuation
  // (apostrophes, hyphens) and acronyms in their authored form aren't
  // mangled.
  final parts = rawId.split(' ').map((token) {
    if (token.isEmpty || !token.contains('_')) return token;
    final chunks = token.split('_').where((c) => c.isNotEmpty);
    return chunks.map(_titleCaseOrAcronym).join(' ');
  });
  return parts.join(' ');
}

String _titleCaseOrAcronym(String chunk) {
  if (chunk.isEmpty) return chunk;
  final upper = chunk.toUpperCase();
  if (_kAcronyms.contains(upper)) return upper;
  return chunk[0].toUpperCase() + chunk.substring(1).toLowerCase();
}

/// Resolve a team's official name (with spaces) to the preferred short
/// display form. Used by LuminaBrain when composing pattern names like
/// "$shortName Twinkle". Returns the input's last whitespace-separated
/// word as a fallback when no override is configured.
String teamShortName(String officialName) {
  if (officialName.isEmpty) return officialName;
  final override = _kTeamShortNames[officialName];
  if (override != null) return override;
  return officialName.split(' ').last;
}

@visibleForTesting
Map<String, String> get debugAllSlugOverridesForTest =>
    Map<String, String>.unmodifiable(_slugOverrides);

@visibleForTesting
Map<String, String> get debugTeamShortNamesForTest =>
    _kTeamShortNames;

@visibleForTesting
Set<String> get debugAcronymsForTest => _kAcronyms;
