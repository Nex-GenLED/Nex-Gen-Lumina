import 'dart:math';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';

/// How a team was matched.
enum TeamMatchType {
  exact,
  fuzzy,
  locationBoosted,
  myTeamBoosted,
  partial,
}

/// A single alternative candidate returned when confidence is low.
class TeamAlternative {
  final UnifiedTeamEntry team;
  final double confidence;
  final String reason;

  const TeamAlternative({
    required this.team,
    required this.confidence,
    required this.reason,
  });

  Map<String, dynamic> toJson() => {
        'name': team.officialName,
        'league': team.league,
        'confidence': confidence,
        'reason': reason,
      };
}

/// Result of resolving a team reference from natural language text.
class TeamResolverResult {
  final bool resolved;
  final UnifiedTeamEntry team;
  final double confidence;
  final String matchedAlias;
  final TeamMatchType matchType;
  final List<TeamAlternative> alternatives;

  const TeamResolverResult({
    required this.resolved,
    required this.team,
    required this.confidence,
    required this.matchedAlias,
    required this.matchType,
    this.alternatives = const [],
  });

  bool get isHighConfidence => confidence >= 0.8;

  Map<String, dynamic> toJson() {
    final primary = team.colors.isNotEmpty ? team.colors.first : null;
    final secondary = team.colors.length > 1 ? team.colors[1] : null;
    final accent = team.colors.length > 2 ? team.colors[2] : null;

    return {
      'resolved': resolved,
      'team': {
        'name': team.officialName,
        'league': team.league,
        'colors': {
          if (primary != null)
            'primary': {
              'name': primary.name,
              'rgb': [primary.r, primary.g, primary.b],
            },
          if (secondary != null)
            'secondary': {
              'name': secondary.name,
              'rgb': [secondary.r, secondary.g, secondary.b],
            },
          if (accent != null)
            'accent': {
              'name': accent.name,
              'rgb': [accent.r, accent.g, accent.b],
            },
        },
      },
      'confidence': confidence,
      'alternatives': alternatives.map((a) => a.toJson()).toList(),
    };
  }
}

// ---------------------------------------------------------------------------
// Internal scoring helper
// ---------------------------------------------------------------------------

class _ScoredCandidate {
  final UnifiedTeamEntry team;
  final String matchedAlias;
  double score; // higher is better, normalised to 0-1 at the end
  TeamMatchType matchType;

  _ScoredCandidate({
    required this.team,
    required this.matchedAlias,
    required this.score,
    required this.matchType,
  });
}

// ---------------------------------------------------------------------------
// TeamColorResolver – static utility class
// ---------------------------------------------------------------------------

/// Smart resolver that converts raw text into structured team color results.
///
/// Features:
/// - Exact alias lookup via [TeamColorDatabase.aliasIndex]
/// - Fuzzy matching using Levenshtein distance
/// - "My Teams" boost for user's saved teams
/// - Location-aware disambiguation using haversine distance
/// - Multi-word extraction (city + name combos)
class TeamColorResolver {
  TeamColorResolver._();

  // ── public API ──────────────────────────────────────────────────────────

  /// Resolve a team from raw text.
  ///
  /// Returns `null` if no plausible team is found.
  static TeamResolverResult? resolve(
    String query, {
    List<String>? userTeams,
    double? userLat,
    double? userLon,
    String? userLocation,
  }) {
    final normalized = _normalize(query);
    if (normalized.isEmpty) return null;

    // Check for "my team" / "my teams" / "our team" shortcut
    if (_isMyTeamPhrase(normalized)) {
      if (userTeams != null && userTeams.isNotEmpty) {
        final results = resolveMyTeams(userTeams);
        if (results.isNotEmpty) return results.first;
      }
      return null;
    }

    final candidates = <_ScoredCandidate>[];

    // Phase 1 – Exact alias match from index
    _addExactMatches(normalized, candidates);

    // Phase 2 – Multi-word extraction (e.g., "show me KC Royals colors")
    if (candidates.isEmpty) {
      _addMultiWordMatches(normalized, candidates);
    }

    // Phase 3 – Fuzzy matching
    if (candidates.isEmpty) {
      _addFuzzyMatches(normalized, candidates);
    }

    if (candidates.isEmpty) return null;

    // Phase 4 – "My Teams" boost
    if (userTeams != null && userTeams.isNotEmpty) {
      _applyMyTeamsBoost(candidates, userTeams);
    }

    // Phase 5 – Location disambiguation
    if (userLat != null && userLon != null) {
      _applyLocationBoost(candidates, userLat, userLon);
    } else if (userLocation != null && userLocation.isNotEmpty) {
      _applyLocationBoostFromName(candidates, userLocation);
    }

    // Phase 6 – Sort, normalise, build result
    candidates.sort((a, b) => b.score.compareTo(a.score));

    // Normalise top score to 1.0, scale others proportionally
    final maxScore = candidates.first.score;
    if (maxScore <= 0) return null;

    for (final c in candidates) {
      c.score = (c.score / maxScore).clamp(0.0, 1.0);
    }

    final best = candidates.first;
    final alts = candidates
        .skip(1)
        .where((c) => c.score >= 0.3)
        .take(3)
        .map((c) => TeamAlternative(
              team: c.team,
              confidence: double.parse(c.score.toStringAsFixed(2)),
              reason:
                  '${c.team.officialName} (${c.team.league})',
            ))
        .toList();

    return TeamResolverResult(
      resolved: true,
      team: best.team,
      confidence: double.parse(best.score.toStringAsFixed(2)),
      matchedAlias: best.matchedAlias,
      matchType: best.matchType,
      alternatives: alts,
    );
  }

  /// Resolve every team in the user's saved list.
  static List<TeamResolverResult> resolveMyTeams(List<String> userTeamNames) {
    final results = <TeamResolverResult>[];
    for (final name in userTeamNames) {
      final result = resolve(name);
      if (result != null) {
        results.add(TeamResolverResult(
          resolved: true,
          team: result.team,
          confidence: 1.0,
          matchedAlias: name,
          matchType: TeamMatchType.myTeamBoosted,
          alternatives: const [],
        ));
      }
    }
    return results;
  }

  // ── Phase 1: Exact alias match ────────────────────────────────────────

  static void _addExactMatches(
      String normalized, List<_ScoredCandidate> candidates) {
    final index = TeamColorDatabase.aliasIndex;

    // Try the full normalised string first
    if (index.containsKey(normalized)) {
      for (final team in index[normalized]!) {
        candidates.add(_ScoredCandidate(
          team: team,
          matchedAlias: normalized,
          score: 100.0 + normalized.length,
          matchType: TeamMatchType.exact,
        ));
      }
      return;
    }

    // Try individual words (longest first to prefer more-specific tokens)
    final words = normalized.split(RegExp(r'\s+'));
    final phrases = <String>[
      // 3-word phrases
      for (var i = 0; i < words.length - 2; i++)
        '${words[i]} ${words[i + 1]} ${words[i + 2]}',
      // 2-word phrases
      for (var i = 0; i < words.length - 1; i++)
        '${words[i]} ${words[i + 1]}',
      // single words
      ...words,
    ];

    for (final phrase in phrases) {
      if (index.containsKey(phrase)) {
        for (final team in index[phrase]!) {
          // Avoid duplicate teams
          if (candidates.any((c) => c.team.id == team.id)) continue;
          candidates.add(_ScoredCandidate(
            team: team,
            matchedAlias: phrase,
            score: 80.0 + phrase.length,
            matchType: TeamMatchType.exact,
          ));
        }
      }
    }
  }

  // ── Phase 2: Multi-word extraction ────────────────────────────────────

  static void _addMultiWordMatches(
      String normalized, List<_ScoredCandidate> candidates) {
    final allTeams = TeamColorDatabase.allTeams;

    for (final team in allTeams) {
      final officialLower = team.officialName.toLowerCase();
      final cityLower = team.city.toLowerCase();

      // Check if full official name appears in query
      if (normalized.contains(officialLower)) {
        candidates.add(_ScoredCandidate(
          team: team,
          matchedAlias: officialLower,
          score: 90.0 + officialLower.length,
          matchType: TeamMatchType.exact,
        ));
        continue;
      }

      // Check if city + any alias word appears
      if (normalized.contains(cityLower)) {
        for (final alias in team.aliases) {
          final aliasLower = alias.toLowerCase();
          // If the alias is just the city, skip (too ambiguous alone)
          if (aliasLower == cityLower) continue;
          if (normalized.contains(aliasLower)) {
            candidates.add(_ScoredCandidate(
              team: team,
              matchedAlias: '$cityLower $aliasLower',
              score: 75.0 + cityLower.length + aliasLower.length,
              matchType: TeamMatchType.partial,
            ));
            break;
          }
        }
      }
    }
  }

  // ── Phase 3: Fuzzy matching ───────────────────────────────────────────

  static void _addFuzzyMatches(
      String normalized, List<_ScoredCandidate> candidates) {
    final words = normalized.split(RegExp(r'\s+'));
    final index = TeamColorDatabase.aliasIndex;

    for (final alias in index.keys) {
      // Skip very short aliases for fuzzy matching (too many false positives)
      if (alias.length < 3) continue;

      for (final word in words) {
        if (word.length < 3) continue;

        final maxDist = word.length <= 5 ? 1 : 2;
        final dist = _levenshteinDistance(word, alias);

        if (dist > 0 && dist <= maxDist) {
          for (final team in index[alias]!) {
            if (candidates.any((c) => c.team.id == team.id)) continue;
            // Score inversely proportional to distance
            final score = 60.0 - (dist * 15.0) + alias.length;
            candidates.add(_ScoredCandidate(
              team: team,
              matchedAlias: alias,
              score: score,
              matchType: TeamMatchType.fuzzy,
            ));
          }
        }
      }

      // Also try the full query against multi-word aliases
      if (alias.contains(' ') && normalized.length >= 4) {
        final dist = _levenshteinDistance(normalized, alias);
        final maxDist = alias.length <= 8 ? 2 : 3;
        if (dist > 0 && dist <= maxDist) {
          for (final team in index[alias]!) {
            if (candidates.any((c) => c.team.id == team.id)) continue;
            final score = 55.0 - (dist * 10.0) + alias.length;
            candidates.add(_ScoredCandidate(
              team: team,
              matchedAlias: alias,
              score: score,
              matchType: TeamMatchType.fuzzy,
            ));
          }
        }
      }
    }
  }

  // ── Phase 4: My Teams boost ───────────────────────────────────────────

  static void _applyMyTeamsBoost(
      List<_ScoredCandidate> candidates, List<String> userTeams) {
    final userTeamsLower = userTeams.map((t) => t.toLowerCase()).toSet();

    for (final c in candidates) {
      final officialLower = c.team.officialName.toLowerCase();
      final cityAndName =
          '${c.team.city} ${c.team.officialName.split(' ').last}'
              .toLowerCase();

      final isMyTeam = userTeamsLower.any((ut) =>
          officialLower.contains(ut) ||
          ut.contains(officialLower) ||
          c.team.aliases.any((a) => a.toLowerCase() == ut) ||
          cityAndName.contains(ut));

      if (isMyTeam) {
        c.score += 20.0;
        c.matchType = TeamMatchType.myTeamBoosted;
      }
    }
  }

  // ── Phase 5: Location disambiguation ─────────────────────────────────

  static void _applyLocationBoost(
      List<_ScoredCandidate> candidates, double userLat, double userLon) {
    for (final c in candidates) {
      final cityLower = c.team.city.toLowerCase();
      final coords = _cityCoordinates[cityLower];
      if (coords != null) {
        final distKm =
            _haversineDistance(userLat, userLon, coords.lat, coords.lon);
        // Boost teams within 150km significantly, decay after that
        if (distKm < 150) {
          c.score += 15.0;
          if (c.matchType != TeamMatchType.myTeamBoosted) {
            c.matchType = TeamMatchType.locationBoosted;
          }
        } else if (distKm < 400) {
          c.score += 5.0;
        }
      }
    }
  }

  static void _applyLocationBoostFromName(
      List<_ScoredCandidate> candidates, String userLocation) {
    final locLower = userLocation.toLowerCase();
    // Try to find coordinates for the user's location string
    for (final entry in _cityCoordinates.entries) {
      if (locLower.contains(entry.key) || entry.key.contains(locLower)) {
        _applyLocationBoost(
            candidates, entry.value.lat, entry.value.lon);
        return;
      }
    }
  }

  // ── "My team" phrase detection ────────────────────────────────────────

  static bool _isMyTeamPhrase(String normalized) {
    const phrases = [
      'my team',
      'my teams',
      'our team',
      'our teams',
      'my favorite team',
      'my favourite team',
    ];
    return phrases.any((p) => normalized == p || normalized.startsWith('$p '));
  }

  // ── Text normalisation ────────────────────────────────────────────────

  static String _normalize(String text) {
    return text
        .toLowerCase()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  // ── Levenshtein distance ──────────────────────────────────────────────

  /// Standard Levenshtein distance with early-termination optimisation.
  static int _levenshteinDistance(String a, String b) {
    if (a == b) return 0;
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;

    // Use the shorter string as the "column" for memory efficiency
    if (a.length > b.length) {
      final temp = a;
      a = b;
      b = temp;
    }

    final m = a.length;
    final n = b.length;

    var prev = List<int>.generate(m + 1, (i) => i);
    var curr = List<int>.filled(m + 1, 0);

    for (var j = 1; j <= n; j++) {
      curr[0] = j;
      for (var i = 1; i <= m; i++) {
        final cost = a[i - 1] == b[j - 1] ? 0 : 1;
        curr[i] = [
          prev[i] + 1, // deletion
          curr[i - 1] + 1, // insertion
          prev[i - 1] + cost, // substitution
        ].reduce(min);
      }
      final temp = prev;
      prev = curr;
      curr = temp;
    }

    return prev[m];
  }

  // ── Haversine distance (km) ───────────────────────────────────────────

  static double _haversineDistance(
      double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0; // Earth radius km
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_degToRad(lat1)) *
            cos(_degToRad(lat2)) *
            sin(dLon / 2) *
            sin(dLon / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return r * c;
  }

  static double _degToRad(double deg) => deg * (pi / 180.0);

  // ── City coordinate database ──────────────────────────────────────────

  static const Map<String, _LatLon> _cityCoordinates = {
    // NFL / NBA / MLB / NHL cities
    'kansas city': _LatLon(39.0997, -94.5786),
    'new york': _LatLon(40.7128, -74.0060),
    'brooklyn': _LatLon(40.6782, -73.9442),
    'los angeles': _LatLon(34.0522, -118.2437),
    'chicago': _LatLon(41.8781, -87.6298),
    'boston': _LatLon(42.3601, -71.0589),
    'philadelphia': _LatLon(39.9526, -75.1652),
    'dallas': _LatLon(32.7767, -96.7970),
    'houston': _LatLon(29.7604, -95.3698),
    'san francisco': _LatLon(37.7749, -122.4194),
    'miami': _LatLon(25.7617, -80.1918),
    'denver': _LatLon(39.7392, -104.9903),
    'seattle': _LatLon(47.6062, -122.3321),
    'atlanta': _LatLon(33.7490, -84.3880),
    'phoenix': _LatLon(33.4484, -112.0740),
    'detroit': _LatLon(42.3314, -83.0458),
    'minneapolis': _LatLon(44.9778, -93.2650),
    'minnesota': _LatLon(44.9778, -93.2650),
    'tampa bay': _LatLon(27.9506, -82.4572),
    'tampa': _LatLon(27.9506, -82.4572),
    'pittsburgh': _LatLon(40.4406, -79.9959),
    'cleveland': _LatLon(41.4993, -81.6944),
    'baltimore': _LatLon(39.2904, -76.6122),
    'indianapolis': _LatLon(39.7684, -86.1581),
    'indiana': _LatLon(39.7684, -86.1581),
    'cincinnati': _LatLon(39.1031, -84.5120),
    'las vegas': _LatLon(36.1699, -115.1398),
    'green bay': _LatLon(44.5133, -88.0133),
    'jacksonville': _LatLon(30.3322, -81.6557),
    'tennessee': _LatLon(36.1627, -86.7816),
    'nashville': _LatLon(36.1627, -86.7816),
    'new orleans': _LatLon(29.9511, -90.0715),
    'carolina': _LatLon(35.2271, -80.8431),
    'charlotte': _LatLon(35.2271, -80.8431),
    'arizona': _LatLon(33.4484, -112.0740),
    'new england': _LatLon(42.3601, -71.0589),
    'washington': _LatLon(38.9072, -77.0369),
    'buffalo': _LatLon(42.8864, -78.8784),
    'sacramento': _LatLon(38.5816, -121.4944),
    'san antonio': _LatLon(29.4241, -98.4936),
    'orlando': _LatLon(28.5383, -81.3792),
    'portland': _LatLon(45.5051, -122.6750),
    'memphis': _LatLon(35.1495, -90.0490),
    'oklahoma city': _LatLon(35.4676, -97.5164),
    'salt lake city': _LatLon(40.7608, -111.8910),
    'utah': _LatLon(40.7608, -111.8910),
    'milwaukee': _LatLon(43.0389, -87.9065),
    'st. louis': _LatLon(38.6270, -90.1994),
    'st louis': _LatLon(38.6270, -90.1994),
    'san diego': _LatLon(32.7157, -117.1611),
    'san jose': _LatLon(37.3382, -121.8863),
    'anaheim': _LatLon(33.8366, -117.9143),
    'golden state': _LatLon(37.7749, -122.4194),
    'colorado': _LatLon(39.7392, -104.9903),
    'columbus': _LatLon(39.9612, -82.9988),
    'raleigh': _LatLon(35.7796, -78.6382),
    'austin': _LatLon(30.2672, -97.7431),
    // Canadian cities
    'toronto': _LatLon(43.6532, -79.3832),
    'montreal': _LatLon(45.5017, -73.5673),
    'ottawa': _LatLon(45.4215, -75.6972),
    'vancouver': _LatLon(49.2827, -123.1207),
    'winnipeg': _LatLon(49.8951, -97.1384),
    'edmonton': _LatLon(53.5461, -113.4938),
    'calgary': _LatLon(51.0447, -114.0719),
    // International soccer cities
    'london': _LatLon(51.5074, -0.1278),
    'manchester': _LatLon(53.4808, -2.2426),
    'liverpool': _LatLon(53.4084, -2.9916),
    'birmingham': _LatLon(52.4862, -1.8904),
    'madrid': _LatLon(40.4168, -3.7038),
    'barcelona': _LatLon(41.3874, 2.1686),
    'seville': _LatLon(37.3891, -5.9845),
    'munich': _LatLon(48.1351, 11.5820),
    'dortmund': _LatLon(51.5136, 7.4653),
    'berlin': _LatLon(52.5200, 13.4050),
    'milan': _LatLon(45.4642, 9.1900),
    'rome': _LatLon(41.9028, 12.4964),
    'naples': _LatLon(40.8518, 14.2681),
    'turin': _LatLon(45.0703, 7.6869),
  };
}

/// Simple lat/lon pair.
class _LatLon {
  final double lat;
  final double lon;
  const _LatLon(this.lat, this.lon);
}

// ---------------------------------------------------------------------------
// Riverpod integration
// ---------------------------------------------------------------------------

/// Service wrapper that holds user context for the resolver.
class TeamColorResolverService {
  final List<String> userTeams;
  final double? userLat;
  final double? userLon;
  final String? userLocation;

  const TeamColorResolverService({
    this.userTeams = const [],
    this.userLat,
    this.userLon,
    this.userLocation,
  });

  /// Resolve a team query using the pre-loaded user context.
  TeamResolverResult? resolve(String query) {
    return TeamColorResolver.resolve(
      query,
      userTeams: userTeams,
      userLat: userLat,
      userLon: userLon,
      userLocation: userLocation,
    );
  }

  /// Resolve the user's saved "My Teams".
  List<TeamResolverResult> resolveMyTeams() {
    return TeamColorResolver.resolveMyTeams(userTeams);
  }
}

/// Riverpod provider that pre-loads user context for the resolver.
final teamColorResolverProvider = Provider<TeamColorResolverService>((ref) {
  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );

  return TeamColorResolverService(
    userTeams: profile?.sportsTeams ?? const [],
    userLocation: profile?.location,
  );
});
