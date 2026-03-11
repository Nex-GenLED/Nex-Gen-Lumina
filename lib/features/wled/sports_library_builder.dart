import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/data/team_color_database.dart';
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
}
