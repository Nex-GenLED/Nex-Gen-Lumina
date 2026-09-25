// lib/features/game_day/team_picker_sheet.dart
//
// "Add a Team" bottom sheet for the Game Day screen.
//
// Browses teams through Explore Designs' Sports folder tree
// (team_picker_folders.dart) — league → teams, with Soccer grouping its
// leagues exactly as Explore does — instead of one flat list per sport that
// lumped NFL and NCAA football together. Search stays flat and spans every
// league, so a partial name still finds a team without knowing its folder.
//
// Lived as a private class inside game_day_screen.dart until the folder
// browsing needed its own widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../app_colors.dart';
import '../../theme.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../sports_alerts/data/team_colors.dart';
import '../sports_alerts/models/sport_type.dart';
import '../wled/library_hierarchy_models.dart';
import '../wled/pattern_grid_widgets.dart' show LibraryNodeCard;
import 'game_day_providers.dart';
import 'team_picker_folders.dart';

/// Opens the team picker as a modal sheet on the branch navigator (the same
/// navigator the Game Day screen lives on).
void showTeamPickerSheet(BuildContext context,
    {required Set<String> existingTeamSlugs}) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: NexGenPalette.gunmetal,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.5,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => TeamPickerSheet(
        scrollController: scrollController,
        existingTeamSlugs: existingTeamSlugs,
      ),
    ),
  );
}

class TeamPickerSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;
  final Set<String> existingTeamSlugs;

  const TeamPickerSheet({
    super.key,
    required this.scrollController,
    required this.existingTeamSlugs,
  });

  @override
  ConsumerState<TeamPickerSheet> createState() => _TeamPickerSheetState();
}

class _TeamPickerSheetState extends ConsumerState<TeamPickerSheet> {
  final _searchController = TextEditingController();

  /// The folder being browsed. Starts at Explore's Sports root.
  String _folderId = GameDayTeamFolders.rootId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ref.read(gameDayTeamSearchProvider.notifier).state = '';
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool get _atRoot => _folderId == GameDayTeamFolders.rootId;

  void _openFolder(String id) => setState(() => _folderId = id);

  void _goUp() {
    final node = GameDayTeamFolders.node(_folderId);
    setState(() => _folderId = node?.parentId ?? GameDayTeamFolders.rootId);
  }

  @override
  Widget build(BuildContext context) {
    final query = ref.watch(gameDayTeamSearchProvider);
    final searching = query.trim().isNotEmpty;

    return Column(
      children: [
        // Handle bar
        Padding(
          padding: const EdgeInsets.only(top: 12, bottom: 8),
          child: Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: NexGenPalette.textMedium.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ),

        _buildHeader(searching),
        const SizedBox(height: 12),

        // Search bar — spans every league regardless of the open folder.
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: TextField(
            controller: _searchController,
            onChanged: (v) =>
                ref.read(gameDayTeamSearchProvider.notifier).state = v,
            decoration: InputDecoration(
              hintText: 'Search all teams...',
              prefixIcon: const Icon(Icons.search, size: 20),
              suffixIcon: _searchController.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      onPressed: () {
                        _searchController.clear();
                        ref.read(gameDayTeamSearchProvider.notifier).state =
                            '';
                      },
                    )
                  : null,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
        const SizedBox(height: 8),

        Expanded(
          child: searching ? _buildSearchResults() : _buildFolderContents(),
        ),
      ],
    );
  }

  /// Title row: "Choose a Team" at the root, otherwise a back arrow and the
  /// folder's breadcrumb (e.g. "Soccer › MLS"). While searching the title
  /// stays put so results read as global, not as the open folder's.
  Widget _buildHeader(bool searching) {
    if (_atRoot || searching) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 20),
        child: Align(
          alignment: Alignment.centerLeft,
          child: Text(
            'Choose a Team',
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w700,
              color: NexGenPalette.textHigh,
            ),
          ),
        ),
      );
    }
    final crumbs = GameDayTeamFolders.ancestry(_folderId)
        .map((n) => n.name)
        .join(' › ');
    return Padding(
      padding: const EdgeInsets.only(left: 8, right: 20),
      child: Row(
        children: [
          IconButton(
            tooltip: 'Back',
            icon: const Icon(Icons.arrow_back_rounded),
            color: NexGenPalette.cyan,
            onPressed: _goUp,
          ),
          Expanded(
            child: Text(
              crumbs,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: NexGenPalette.textHigh,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  EdgeInsets get _listPadding =>
      // Bottom padding clears the persistent GlassDockNavBar (shell-injected
      // inset) so the last rows aren't hidden behind it and can be tapped.
      EdgeInsets.fromLTRB(16, 0, 16, navBarTotalHeight(context) + 16);

  /// The open folder: its sub-folders (root, Soccer) or its teams (a league).
  Widget _buildFolderContents() {
    final folders = GameDayTeamFolders.childFolders(_folderId);
    if (folders.isNotEmpty) {
      return ListView.builder(
        // Keyed per folder so opening one starts at the top instead of
        // inheriting the previous list's scroll offset.
        key: ValueKey('folders_$_folderId'),
        controller: widget.scrollController,
        padding: _listPadding,
        itemCount: folders.length,
        itemBuilder: (context, index) => _FolderRow(
          node: folders[index],
          onTap: () => _openFolder(folders[index].id),
        ),
      );
    }
    final teams = GameDayTeamFolders.teamsIn(_folderId);
    return ListView.builder(
      key: ValueKey('teams_$_folderId'),
      controller: widget.scrollController,
      padding: _listPadding,
      itemCount: teams.length,
      itemBuilder: (context, index) =>
          _teamRow(teams[index], showLeague: false),
    );
  }

  /// Flat, cross-league results for the current query.
  Widget _buildSearchResults() {
    final teams = ref.watch(gameDayFilteredTeamsProvider);
    if (teams.isEmpty) {
      return const Center(
        child: Text(
          'No teams match',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
      );
    }
    return ListView.builder(
      key: const ValueKey('search_results'),
      controller: widget.scrollController,
      padding: _listPadding,
      itemCount: teams.length,
      itemBuilder: (context, index) =>
          _teamRow(teams[index], showLeague: true),
    );
  }

  Widget _teamRow(MapEntry<String, TeamColors> entry,
      {required bool showLeague}) {
    final slug = entry.key;
    final team = entry.value;
    final alreadyAdded = widget.existingTeamSlugs.contains(slug);
    // Search results come from every league, so name the league on each row;
    // inside a league folder it would just repeat the breadcrumb.
    final leagueName =
        GameDayTeamFolders.node(gameDayLeagueFolderId(team.sport))?.name ??
            team.sport.displayName;

    return ListTile(
      key: ValueKey('team_$slug'),
      leading: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: team.primary,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: team.secondary,
              shape: BoxShape.circle,
            ),
          ),
        ],
      ),
      title: Text(
        team.teamName,
        style: TextStyle(
          color: alreadyAdded
              ? NexGenPalette.textMedium
              : NexGenPalette.textHigh,
        ),
      ),
      subtitle: showLeague
          ? Text(
              leagueName,
              style: const TextStyle(
                fontSize: 12,
                color: NexGenPalette.textMedium,
              ),
            )
          : null,
      trailing: alreadyAdded
          ? const Icon(Icons.check_circle, color: NexGenPalette.green, size: 20)
          : const Icon(Icons.add_circle_outline,
              color: NexGenPalette.cyan, size: 20),
      onTap: alreadyAdded ? null : () => _addTeam(context, ref, slug, team),
    );
  }

  Future<void> _addTeam(BuildContext context, WidgetRef ref, String slug,
      TeamColors team) async {
    // Capture messenger before any awaits — context may be unmounted by the
    // time the future resolves if the bottom sheet is dismissed mid-flight.
    final messenger = ScaffoldMessenger.of(context);
    try {
      debugPrint('[GameDay] Adding team: $slug (${team.teamName})');
      // Add the team with autopilot OFF — user must explicitly opt in
      // via the Autopilot toggle on the team card.
      await ref
          .read(gameDayAutopilotNotifierProvider.notifier)
          .toggleAutopilot(teamSlug: slug, enabled: false);

      if (!context.mounted) return;
      Navigator.pop(context);
      messenger.showSnackBar(
        SnackBar(
          content: Text('${team.teamName} added to Game Day!'),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e, st) {
      debugPrint('[GameDay] Failed to add team $slug: $e\n$st');
      if (!context.mounted) return;
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not add ${team.teamName}: $e'),
          backgroundColor: Colors.red.shade700,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }
}

/// One league (or grouping) folder row, styled with the same icon and accent
/// Explore Designs gives that folder.
class _FolderRow extends StatelessWidget {
  final LibraryNode node;
  final VoidCallback onTap;

  const _FolderRow({required this.node, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final accent = LibraryNodeCard.folderThemeColor(node);
    final teamCount = GameDayTeamFolders.teamsIn(node.id).length;
    final subFolders = GameDayTeamFolders.childFolders(node.id).length;
    final subtitle = teamCount > 0
        ? '$teamCount teams'
        : '$subFolders leagues';

    return ListTile(
      key: ValueKey('folder_${node.id}'),
      leading: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: accent.withValues(alpha: 0.45)),
        ),
        child: Icon(LibraryNodeCard.iconForNode(node), color: accent, size: 22),
      ),
      title: Text(
        node.name,
        style: const TextStyle(
          color: NexGenPalette.textHigh,
          fontWeight: FontWeight.w600,
        ),
      ),
      subtitle: Text(
        subtitle,
        style: const TextStyle(fontSize: 12, color: NexGenPalette.textMedium),
      ),
      trailing: Icon(Icons.chevron_right_rounded,
          color: accent.withValues(alpha: 0.8)),
      onTap: onTap,
    );
  }
}
