import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/golf_library_builder.dart';

/// Builds the sports hierarchy from existing SportsTeamsDatabase.
/// Bridges pro leagues and NCAA conferences into LibraryNode structure.
class SportsLibraryBuilder {
  /// Soccer parent folder ID
  static const String soccerFolderId = 'league_soccer';

  /// League folder IDs and display names
  static const Map<String, String> _leagueNames = {
    'NFL': 'NFL',
    'NBA': 'NBA',
    'MLB': 'MLB',
    'NHL': 'NHL',
    'MLS': 'MLS',
    'EPL': 'Premier League',
    'LA_LIGA': 'La Liga',
    'BUNDESLIGA': 'Bundesliga',
    'SERIE_A': 'Serie A',
    'WNBA': 'WNBA',
    'NWSL': 'NWSL',
    'CHAMPIONS_LEAGUE': 'Champions League',
    'FIFA_WORLD_CUP': 'FIFA World Cup 2026',
  };

  /// League sort order (top-level leagues under Sports)
  static const Map<String, int> _leagueSortOrder = {
    'NFL': 0,
    'NBA': 1,
    'MLB': 2,
    'NHL': 3,
    'WNBA': 5,
  };

  /// Sort order for soccer sub-leagues (under the Soccer parent folder)
  static const Map<String, int> _soccerSortOrder = {
    'MLS': 0,
    'EPL': 1,
    'LA_LIGA': 2,
    'BUNDESLIGA': 3,
    'SERIE_A': 4,
    'NWSL': 5,
    'CHAMPIONS_LEAGUE': 6,
    'FIFA_WORLD_CUP': 7,
  };

  /// Leagues nested under the Soccer parent folder
  static const Set<String> _soccerLeagues = {
    'MLS', 'EPL', 'LA_LIGA', 'BUNDESLIGA', 'SERIE_A', 'NWSL', 'CHAMPIONS_LEAGUE', 'FIFA_WORLD_CUP',
  };

  /// Build all league folder nodes
  static List<LibraryNode> getLeagueFolders() {
    final folders = <LibraryNode>[];

    // Soccer parent folder
    folders.add(const LibraryNode(
      id: soccerFolderId,
      name: 'Soccer',
      nodeType: LibraryNodeType.folder,
      parentId: LibraryCategoryIds.sports,
      sortOrder: 4,
      metadata: {'icon': 'soccer', 'isSoccerParent': true},
    ));

    for (final entry in _leagueNames.entries) {
      final leagueId = entry.key;
      final leagueName = entry.value;
      final isSoccer = _soccerLeagues.contains(leagueId);

      folders.add(LibraryNode(
        id: 'league_${leagueId.toLowerCase()}',
        name: leagueName,
        nodeType: LibraryNodeType.folder,
        parentId: isSoccer ? soccerFolderId : LibraryCategoryIds.sports,
        sortOrder: isSoccer
            ? (_soccerSortOrder[leagueId] ?? 99)
            : (_leagueSortOrder[leagueId] ?? 99),
        metadata: {'league': leagueId},
      ));
    }

    return folders;
  }

  /// Build all team palette nodes from SportsTeamsDatabase
  static List<LibraryNode> getTeamPaletteNodes() {
    final nodes = <LibraryNode>[];

    // Group teams by league
    final teamsByLeague = <String, List<SportsTeam>>{};
    for (final team in SportsTeamsDatabase.allTeams) {
      teamsByLeague.putIfAbsent(team.league, () => []).add(team);
    }

    // Create palette nodes for each team
    for (final entry in teamsByLeague.entries) {
      final league = entry.key;
      final teams = entry.value;
      final parentId = 'league_${league.toLowerCase()}';

      // Only create nodes for leagues we have folders for
      if (!_leagueNames.containsKey(league)) continue;

      for (var i = 0; i < teams.length; i++) {
        final team = teams[i];
        final teamId = _generateTeamId(league, team);

        nodes.add(LibraryNode(
          id: teamId,
          name: team.displayName,
          description: '${team.city} ${team.name}',
          nodeType: LibraryNodeType.palette,
          parentId: parentId,
          themeColors: team.colors,
          sortOrder: i,
          metadata: {
            'league': league,
            'city': team.city,
            'teamName': team.name,
            'nickname': team.nickname,
            'suggestedEffects': [12, 41, 0], // Theater Chase, Running, Solid
            'defaultSpeed': 85,
            'defaultIntensity': 180,
          },
        ));
      }
    }

    return nodes;
  }

  /// Generate a unique team ID
  static String _generateTeamId(String league, SportsTeam team) {
    final sanitizedName = team.name
        .toLowerCase()
        .replaceAll(' ', '_')
        .replaceAll("'", '')
        .replaceAll('-', '_');
    return 'team_${league.toLowerCase()}_$sanitizedName';
  }

  /// Mapping from TeamColorDatabase league strings to our folder IDs.
  static const Map<String, String> _soccerLeagueFolderIds = {
    'EPL': 'league_epl',
    'La Liga': 'league_la_liga',
    'Bundesliga': 'league_bundesliga',
    'Serie A': 'league_serie_a',
    'Champions League': 'league_champions_league',
    'FIFA World Cup': 'league_fifa_world_cup',
  };

  /// Build palette nodes for international soccer teams from TeamColorDatabase.
  static List<LibraryNode> getInternationalSoccerNodes() {
    final nodes = <LibraryNode>[];
    final teamsByLeague = <String, List<UnifiedTeamEntry>>{};

    for (final team in TeamColorDatabase.allTeams) {
      if (_soccerLeagueFolderIds.containsKey(team.league)) {
        teamsByLeague.putIfAbsent(team.league, () => []).add(team);
      }
    }

    for (final entry in teamsByLeague.entries) {
      final league = entry.key;
      final teams = entry.value;
      final parentId = _soccerLeagueFolderIds[league]!;

      for (var i = 0; i < teams.length; i++) {
        final team = teams[i];
        final folderId = league.toLowerCase().replaceAll(' ', '_');

        nodes.add(LibraryNode(
          id: 'team_${folderId}_${team.id}',
          name: team.officialName,
          description: team.city,
          nodeType: LibraryNodeType.palette,
          parentId: parentId,
          themeColors: team.colors.map((c) => c.toColor()).toList(),
          sortOrder: i,
          metadata: {
            'league': team.league,
            'city': team.city,
            'teamName': team.officialName,
            // Surfaced for the Game Day Design-picker resolver's espn
            // fast-path. Only Champions League / FIFA `_intl` entries carry
            // an espnTeamId; EPL/La Liga/Bundesliga/Serie A rows omit it, so
            // this is null there and the key is simply absent (harmless).
            if (team.espnTeamId != null) 'espnTeamId': team.espnTeamId,
          },
        ));
      }
    }

    return nodes;
  }

  /// Build the complete sports hierarchy including pro leagues, NCAA, and golf
  static List<LibraryNode> buildFullSportsHierarchy() {
    final nodes = <LibraryNode>[];

    // Pro league folders
    nodes.addAll(getLeagueFolders());

    // Pro team palettes (domestic leagues via SportsTeamsDatabase)
    nodes.addAll(getTeamPaletteNodes());

    // International soccer teams (via TeamColorDatabase)
    nodes.addAll(getInternationalSoccerNodes());

    // NCAA folders and schools
    nodes.addAll(NcaaConferences.getNcaaFolders());
    nodes.addAll(NcaaConferences.getAllSchoolNodes());

    // Golf folders and themes
    nodes.addAll(GolfLibraryBuilder.buildFullGolfHierarchy());

    return nodes;
  }

  /// Get teams by league for display
  static List<LibraryNode> getTeamsForLeague(String leagueId) {
    final nodes = getTeamPaletteNodes();
    return nodes.where((n) => n.parentId == leagueId).toList()
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
  }

  /// Search teams across all leagues
  static List<LibraryNode> searchTeams(String query) {
    final lowercaseQuery = query.toLowerCase();
    final allTeams = getTeamPaletteNodes();

    return allTeams.where((node) {
      final name = node.name.toLowerCase();
      final teamName = (node.metadata?['teamName'] as String?)?.toLowerCase() ?? '';
      final city = (node.metadata?['city'] as String?)?.toLowerCase() ?? '';
      final nickname = (node.metadata?['nickname'] as String?)?.toLowerCase() ?? '';

      return name.contains(lowercaseQuery) ||
             teamName.contains(lowercaseQuery) ||
             city.contains(lowercaseQuery) ||
             nickname.contains(lowercaseQuery);
    }).toList();
  }

  /// Get the "My Teams" folder node
  /// This folder appears first in Game Day Fan Zone and shows the user's favorite teams
  static LibraryNode getMyTeamsFolder() {
    return const LibraryNode(
      id: PersonalizedFolderIds.myTeams,
      name: 'My Teams',
      description: 'Your favorite teams in one place',
      nodeType: LibraryNodeType.folder,
      parentId: LibraryCategoryIds.sports,
      sortOrder: -1, // Appears first (before NFL at 0)
      metadata: {'icon': 'favorite', 'isPersonalized': true},
    );
  }

  /// Find teams that match the user's saved team names.
  /// Matches against team name, city, nickname, and display name.
  /// Returns LibraryNode palettes with parentId changed to My Teams folder.
  static List<LibraryNode> getMyTeamsPalettes(List<String> userTeamNames) {
    if (userTeamNames.isEmpty) return [];

    final allTeams = getTeamPaletteNodes();
    final ncaaTeams = NcaaConferences.getAllSchoolNodes();
    final allSportsNodes = [...allTeams, ...ncaaTeams];
    final matchedTeams = <LibraryNode>[];

    for (var i = 0; i < userTeamNames.length; i++) {
      final userTeam = userTeamNames[i].toLowerCase().trim();
      if (userTeam.isEmpty) continue;

      // Find best match for this user team
      LibraryNode? bestMatch;
      int bestScore = 0;

      for (final node in allSportsNodes) {
        if (!node.isPalette) continue;

        final nodeName = node.name.toLowerCase();
        final teamName = (node.metadata?['teamName'] as String?)?.toLowerCase() ?? '';
        final city = (node.metadata?['city'] as String?)?.toLowerCase() ?? '';
        final nickname = (node.metadata?['nickname'] as String?)?.toLowerCase() ?? '';
        final schoolName = (node.metadata?['schoolName'] as String?)?.toLowerCase() ?? '';

        int score = 0;

        // Exact matches get highest score
        if (nodeName == userTeam || teamName == userTeam || nickname == userTeam) {
          score = 100;
        } else if (schoolName == userTeam) {
          score = 100;
        }
        // City + team name combo (e.g., "Kansas City Chiefs")
        else if ('$city $teamName'.trim() == userTeam) {
          score = 95;
        }
        // Partial matches
        else if (nodeName.contains(userTeam) || userTeam.contains(nodeName)) {
          score = 70;
        } else if (teamName.contains(userTeam) || userTeam.contains(teamName)) {
          score = 60;
        } else if (city.contains(userTeam) || userTeam.contains(city)) {
          score = 50;
        } else if (nickname.contains(userTeam) || userTeam.contains(nickname)) {
          score = 40;
        } else if (schoolName.contains(userTeam) || userTeam.contains(schoolName)) {
          score = 40;
        }

        if (score > bestScore) {
          bestScore = score;
          bestMatch = node;
        }
      }

      // Only add if we found a reasonable match
      if (bestMatch != null && bestScore >= 40) {
        // Create a copy with parentId pointing to My Teams folder
        // and sortOrder based on user's priority order
        matchedTeams.add(bestMatch.copyWith(
          parentId: PersonalizedFolderIds.myTeams,
          sortOrder: i,
        ));
      }
    }

    return matchedTeams;
  }

  /// Check if any teams match the user's list (for determining if My Teams should show)
  static bool hasMatchingTeams(List<String> userTeamNames) {
    return getMyTeamsPalettes(userTeamNames).isNotEmpty;
  }

  // ──────────────────────────────────────────────────────────────────────
  // Game Day Design-picker resolver
  //
  // The Game Day "Design" picker needs to land on a team's real catalog
  // leaf node so the existing leaf→ColorwayEffectSelector path fires. The
  // picker previously minted `team_<config.teamSlug>` from the kTeamColors
  // key namespace, which only coincidentally equals the catalog node id for
  // single-name domestic teams (Royals, Bills) and never matches for
  // international soccer (`team_champions_league_cl_ac_milan`), MLS
  // (city-strip: `team_mls_united_fc`), or NCAA — those landed on an empty
  // "no items found" folder.
  //
  // espnTeamId covers only ~2 of the selectable leagues (Champions League +
  // FIFA) on BOTH sides, so it cannot be the primary key without regressing
  // the working domestic teams. Name matching is the reliable join: the
  // display name is present on both sides for every league.
  // ──────────────────────────────────────────────────────────────────────

  /// Resolve a Game Day team (display [teamName] + [sport], with an optional
  /// [espnTeamId]) to the real catalog leaf node id.
  ///
  /// Returns null when no catalog team matches — callers must surface an
  /// honest "couldn't find that team's designs" message rather than navigate
  /// into an empty folder or onto the wrong team.
  ///
  /// Precedence:
  ///   1. ESPN id exact match (only Champions League / FIFA carry espn ids on
  ///      both sides; harmless elsewhere since catalog espn is absent there).
  ///   2. Exact normalized-name match, sport-disambiguated.
  ///   3. Fuzzy name fallback via [getMyTeamsPalettes] (last resort).
  static String? resolveTeamNodeId({
    required String teamName,
    required SportType sport,
    String? espnTeamId,
  }) {
    final leaves = <LibraryNode>[
      ...getTeamPaletteNodes(),
      ...getInternationalSoccerNodes(),
      ...NcaaConferences.getAllSchoolNodes(),
    ];

    // 1. ESPN fast-path.
    final espn = espnTeamId?.trim() ?? '';
    if (espn.isNotEmpty) {
      final espnMatches = leaves
          .where((n) => (n.metadata?['espnTeamId'] as String?) == espn)
          .toList();
      final pool = _preferSport(espnMatches, sport);
      if (pool.isNotEmpty) return pool.first.id;
    }

    // 2. Exact normalized-name match (PRIMARY), sport-disambiguated.
    // Match against EVERY name form the catalog node exposes — display name,
    // the city-stripped team name, and "city + teamName" — so MLS clubs whose
    // official name doesn't start with the city (e.g. "FC Cincinnati", whose
    // display name is "Cincinnati FC Cincinnati" but whose teamName is
    // "FC Cincinnati") still match. All comparisons are EXACT normalized
    // equality, so this cannot resolve a different team.
    final target = _normalizeTeamName(teamName);
    if (target.isNotEmpty) {
      final nameMatches =
          leaves.where((n) => _nodeNameForms(n).contains(target)).toList();
      final pool = _preferSport(nameMatches, sport);
      if (pool.isNotEmpty) return pool.first.id;
    }

    // No safe match. Return null rather than risk the wrong team — an
    // unbounded fuzzy match (e.g. getMyTeamsPalettes' >=40 partial score)
    // can return a false positive, so callers surface an honest message.
    return null;
  }

  /// All normalized name forms a leaf node can be matched against.
  static Set<String> _nodeNameForms(LibraryNode n) {
    final meta = n.metadata;
    final teamName = meta?['teamName'] as String?;
    final city = meta?['city'] as String?;
    return <String>{
      _normalizeTeamName(n.name),
      if (teamName != null) _normalizeTeamName(teamName),
      if (city != null && teamName != null)
        _normalizeTeamName('$city $teamName'),
    }..removeWhere((s) => s.isEmpty);
  }

  /// Restrict [nodes] to those whose sport/league matches [sport] when any
  /// do; otherwise return [nodes] unchanged. This is the REQUIRED tiebreak
  /// for same-named teams across sports (NCAA football vs basketball share a
  /// school name; a European club appears under both its domestic-league and
  /// Champions League nodes). Picking the sport-correct node keeps downstream
  /// live-scoring keyed off the right sport.
  static List<LibraryNode> _preferSport(
      List<LibraryNode> nodes, SportType sport) {
    if (nodes.length <= 1) return nodes;
    final sportMatched =
        nodes.where((n) => _nodeMatchesSport(n, sport)).toList();
    return sportMatched.isNotEmpty ? sportMatched : nodes;
  }

  static bool _nodeMatchesSport(LibraryNode n, SportType sport) {
    final meta = n.metadata;
    switch (sport) {
      case SportType.ncaaFB:
        return meta?['sport'] == 'football';
      case SportType.ncaaMB:
        return meta?['sport'] == 'basketball';
      default:
        return (meta?['league'] as String?) == _leagueTokenForSport(sport);
    }
  }

  /// Maps a [SportType] to the `metadata['league']` token the catalog stores
  /// on domestic ([getTeamPaletteNodes]) and international
  /// ([getInternationalSoccerNodes]) leaf nodes. NCAA is disambiguated via
  /// `metadata['sport']` instead, so it returns null here.
  static String? _leagueTokenForSport(SportType sport) {
    switch (sport) {
      case SportType.nfl:
        return 'NFL';
      case SportType.nba:
        return 'NBA';
      case SportType.wnba:
        return 'WNBA';
      case SportType.mlb:
        return 'MLB';
      case SportType.nhl:
        return 'NHL';
      case SportType.mls:
        return 'MLS';
      case SportType.nwsl:
        return 'NWSL';
      case SportType.fifa:
        return 'FIFA World Cup';
      case SportType.championsLeague:
        return 'Champions League';
      case SportType.ncaaFB:
      case SportType.ncaaMB:
        return null;
    }
  }

  /// Normalize a team display name for exact equality: lowercase, fold Latin
  /// diacritics (so "CF Montréal" matches "CF Montreal"), strip all
  /// punctuation/apostrophes to spaces, collapse whitespace. Symmetric across
  /// config side (`config.teamName`) and catalog side (node name forms).
  static String _normalizeTeamName(String s) {
    final folded = _foldDiacritics(s.toLowerCase());
    final stripped = folded.replaceAll(RegExp(r'[^a-z0-9]+'), ' ');
    return stripped.trim().replaceAll(RegExp(r'\s+'), ' ');
  }

  static String _foldDiacritics(String s) {
    const from = 'àáâãäåçèéêëìíîïñòóôõöùúûüýÿ';
    const to = 'aaaaaaceeeeiiiinooooouuuuyy';
    final buf = StringBuffer();
    for (final ch in s.split('')) {
      final idx = from.indexOf(ch);
      buf.write(idx >= 0 ? to[idx] : ch);
    }
    return buf.toString();
  }
}
