// lib/features/game_day/team_picker_folders.dart
//
// The Game Day team picker's folder tree — Explore Designs' Sports tree,
// not a second one.
//
// Explore Designs organises sports as `cat_sports` → league folders (NFL,
// NBA, MLB, NHL, Soccer → {MLS, NWSL, Champions League, FIFA World Cup, …},
// WNBA, NCAA Football, NCAA Basketball) → teams, as [LibraryNode]s built by
// [SportsLibraryBuilder] and [NcaaConferences]. The picker reuses those
// folder nodes VERBATIM — same ids, names, parents and sort order — so the
// two surfaces can never drift apart, and drops only the folders that hold
// no Game Day sport (EPL, La Liga, Bundesliga, Serie A, the NCAA conference
// sub-folders, golf, "My Teams").
//
// What is NOT reused is the leaf level. Game Day teams are the
// [kTeamColors] table (keyed by slug, carrying the ESPN id live scoring
// needs); Explore's leaves come from a different table without ESPN ids for
// most leagues, and the forward join (`SportsLibraryBuilder.resolveTeamNodeId`)
// is deliberately allowed to return null. So each folder is populated from
// kTeamColors by sport, through [gameDayLeagueFolderId] — the inverse of the
// league tokens `SportsLibraryBuilder` stores on its leaves.

import 'package:nexgen_command/data/ncaa_conferences.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';
import 'package:nexgen_command/features/sports_alerts/models/sport_type.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/sports_library_builder.dart';

/// The Explore Designs folder a Game Day sport's teams live in.
String gameDayLeagueFolderId(SportType sport) => switch (sport) {
      SportType.nfl => LeagueFolderIds.nfl,
      SportType.nba => LeagueFolderIds.nba,
      SportType.wnba => LeagueFolderIds.wnba,
      SportType.mlb => LeagueFolderIds.mlb,
      SportType.nhl => LeagueFolderIds.nhl,
      SportType.mls => LeagueFolderIds.mls,
      SportType.nwsl => LeagueFolderIds.nwsl,
      SportType.fifa => LeagueFolderIds.fifaWorldCup,
      SportType.championsLeague => LeagueFolderIds.championsLeague,
      SportType.ncaaFB => LeagueFolderIds.ncaaFootball,
      SportType.ncaaMB => LeagueFolderIds.ncaaBasketball,
    };

/// The picker's root order, by Explore folder id.
///
/// This is the ONE place the picker intentionally differs from Explore
/// Designs: Explore lists NCAA Football and NCAA Basketball last (after
/// WNBA); the picker seats each college league beside its pro league, so a
/// fan of one football team finds both football folders together. Folder
/// identity, naming and every deeper level still come from Explore.
const List<String> kGameDayPickerLeagueOrder = [
  LeagueFolderIds.nfl,
  LeagueFolderIds.ncaaFootball,
  LeagueFolderIds.nba,
  LeagueFolderIds.ncaaBasketball,
  LeagueFolderIds.mlb,
  LeagueFolderIds.nhl,
  LeagueFolderIds.soccer,
  LeagueFolderIds.wnba,
];

/// Read-only view of the Explore Sports folders that hold Game Day teams.
class GameDayTeamFolders {
  GameDayTeamFolders._();

  /// The picker's root: Explore's Sports category.
  static const String rootId = LibraryCategoryIds.sports;

  static final Map<String, LibraryNode> _byId = _build();

  static Map<String, LibraryNode> _build() {
    final wanted = <String>{
      for (final sport in SportType.values) gameDayLeagueFolderId(sport),
      SportsLibraryBuilder.soccerFolderId,
    };
    final nodes = <LibraryNode>[
      ...SportsLibraryBuilder.getLeagueFolders(),
      ...NcaaConferences.getNcaaFolders(),
    ];
    return {
      for (final n in nodes)
        if (n.isFolder && wanted.contains(n.id)) n.id: n,
    };
  }

  /// Every folder the picker can show, in no particular order.
  static Iterable<LibraryNode> get all => _byId.values;

  /// A folder by its Explore id, or null when the picker does not show it.
  static LibraryNode? node(String id) => _byId[id];

  /// The folders directly under [parentId].
  ///
  /// At the root the order is [kGameDayPickerLeagueOrder]; everywhere else
  /// (Soccer's leagues) it is Explore's own sort order.
  static List<LibraryNode> childFolders(String parentId) {
    final folders = _byId.values.where((n) => n.parentId == parentId).toList();
    if (parentId == rootId) {
      int rank(LibraryNode n) {
        final i = kGameDayPickerLeagueOrder.indexOf(n.id);
        return i < 0 ? kGameDayPickerLeagueOrder.length + n.sortOrder : i;
      }

      folders.sort((a, b) => rank(a).compareTo(rank(b)));
    } else {
      folders.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    }
    return folders;
  }

  /// The Game Day sport whose teams live in [folderId], or null for a
  /// grouping folder such as Soccer.
  static SportType? sportFor(String folderId) {
    for (final sport in SportType.values) {
      if (gameDayLeagueFolderId(sport) == folderId) return sport;
    }
    return null;
  }

  /// The Game Day teams in [folderId], alphabetical by team name. Empty for
  /// a grouping folder.
  static List<MapEntry<String, TeamColors>> teamsIn(String folderId) {
    final sport = sportFor(folderId);
    if (sport == null) return const [];
    return kTeamColors.entries.where((e) => e.value.sport == sport).toList()
      ..sort((a, b) => a.value.teamName.compareTo(b.value.teamName));
  }

  /// Root → … → [folderId], for a breadcrumb. Excludes the root itself.
  static List<LibraryNode> ancestry(String folderId) {
    final chain = <LibraryNode>[];
    var current = _byId[folderId];
    while (current != null) {
      chain.insert(0, current);
      final parent = current.parentId;
      current = parent == null ? null : _byId[parent];
    }
    return chain;
  }
}
