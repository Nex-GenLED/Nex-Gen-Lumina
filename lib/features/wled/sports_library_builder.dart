import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/golf_library_builder.dart';

/// Builds the sports hierarchy from existing SportsTeamsDatabase.
/// Bridges pro leagues and NCAA conferences into LibraryNode structure.
class SportsLibraryBuilder {
  /// League folder IDs and display names
  static const Map<String, String> _leagueNames = {
    'NFL': 'NFL',
    'NBA': 'NBA',
    'MLB': 'MLB',
    'NHL': 'NHL',
    'MLS': 'MLS',
    'WNBA': 'WNBA',
    'NWSL': 'NWSL',
  };

  /// League sort order
  static const Map<String, int> _leagueSortOrder = {
    'NFL': 0,
    'NBA': 1,
    'MLB': 2,
    'NHL': 3,
    'MLS': 4,
    'WNBA': 5,
    'NWSL': 6,
  };

  /// Build all league folder nodes
  static List<LibraryNode> getLeagueFolders() {
    final folders = <LibraryNode>[];

    for (final entry in _leagueNames.entries) {
      final leagueId = entry.key;
      final leagueName = entry.value;

      folders.add(LibraryNode(
        id: 'league_${leagueId.toLowerCase()}',
        name: leagueName,
        nodeType: LibraryNodeType.folder,
        parentId: LibraryCategoryIds.sports,
        sortOrder: _leagueSortOrder[leagueId] ?? 99,
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

  /// Build the complete sports hierarchy including pro leagues, NCAA, and golf
  static List<LibraryNode> buildFullSportsHierarchy() {
    final nodes = <LibraryNode>[];

    // Pro league folders
    nodes.addAll(getLeagueFolders());

    // Pro team palettes
    nodes.addAll(getTeamPaletteNodes());

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
}
