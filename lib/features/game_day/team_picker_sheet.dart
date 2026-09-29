// lib/features/game_day/team_picker_sheet.dart
//
// THE Game Day team chooser — the only team-selection UI in the app.
//
// Browses teams through Explore Designs' Sports folder tree
// (team_picker_folders.dart): league → teams, with Soccer grouping its
// leagues exactly as Explore does, and college leagues seated beside their
// pro league (kGameDayPickerLeagueOrder). Search stays flat and spans every
// league. It replaced the flat per-sport chip pickers ("Football",
// "Basketball", …) that mixed NCAA and pro teams; every entry point — the
// Game Day screen's "Add a Team", the Neighborhood Game Day setup and the
// sync-event setup — now renders this widget, either as a sheet
// ([showGameDayTeamPickerSheet]) or embedded in a screen (`embedded: true`).
//
// Three commit modes:
//   • ADD (default): tapping a team adds it to Game Day (autopilot off) and
//     pops the sheet.
//   • PICK ([onTeamPicked] set): tapping a team hands it to the caller and
//     does nothing else — for screens that need ONE team for their own flow
//     (Neighborhood Game Day setup, sync-event setup).
//   • MULTI ([onTeamToggled] set): tapping toggles a team in or out of the
//     caller's selection, with a check on each chosen team and a "Done"
//     button — for the onboarding paths that collect several teams at once
//     (installer handoff "Favorite Teams", commercial "Your Teams").

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

/// A team chosen in PICK mode.
typedef GameDayTeamPicked = void Function(String slug, TeamColors team);

/// A team toggled in MULTI mode; [selected] is its new state.
typedef GameDayTeamToggled = void Function(
    String slug, TeamColors team, bool selected);

/// Opens the team picker as a modal sheet on the branch navigator (the same
/// navigator the Game Day screen lives on). ADD mode unless [onTeamPicked]
/// is given.
void showGameDayTeamPickerSheet(
  BuildContext context, {
  required Set<String> existingTeamSlugs,
  GameDayTeamPicked? onTeamPicked,
  GameDayTeamToggled? onTeamToggled,
  Set<String> selectedTeamSlugs = const {},
}) {
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
      builder: (_, scrollController) => GameDayTeamPickerSheet(
        scrollController: scrollController,
        existingTeamSlugs: existingTeamSlugs,
        onTeamPicked: onTeamPicked,
        onTeamToggled: onTeamToggled,
        selectedTeamSlugs: selectedTeamSlugs,
      ),
    ),
  );
}

class GameDayTeamPickerSheet extends ConsumerStatefulWidget {
  final ScrollController scrollController;

  /// Teams already on Game Day (ADD mode shows them checked and inert).
  final Set<String> existingTeamSlugs;

  /// PICK mode: hand the team to the caller instead of adding it.
  final GameDayTeamPicked? onTeamPicked;

  /// PICK mode: the caller's current choice, shown checked.
  final String? selectedTeamSlug;

  /// MULTI mode: toggle a team in or out of the caller's selection.
  final GameDayTeamToggled? onTeamToggled;

  /// MULTI mode: the caller's selection when the sheet opens.
  final Set<String> selectedTeamSlugs;

  /// True when hosted inside a screen rather than a bottom sheet: no drag
  /// handle, and the list keeps the screen's own bottom inset.
  final bool embedded;

  const GameDayTeamPickerSheet({
    super.key,
    required this.scrollController,
    required this.existingTeamSlugs,
    this.onTeamPicked,
    this.selectedTeamSlug,
    this.onTeamToggled,
    this.selectedTeamSlugs = const {},
    this.embedded = false,
  });

  @override
  ConsumerState<GameDayTeamPickerSheet> createState() =>
      _GameDayTeamPickerSheetState();
}

class _GameDayTeamPickerSheetState
    extends ConsumerState<GameDayTeamPickerSheet> {
  final _searchController = TextEditingController();

  /// The folder being browsed. Starts at Explore's Sports root.
  String _folderId = GameDayTeamFolders.rootId;

  /// MULTI mode's live selection. The sheet is its own route, so it cannot
  /// wait for the caller to rebuild it; it tracks the toggles itself and
  /// reports each one.
  late final Set<String> _toggled = {...widget.selectedTeamSlugs};

  bool get _multi => widget.onTeamToggled != null;

  void _toggle(String slug, TeamColors team) {
    final selected = !_toggled.contains(slug);
    setState(() => selected ? _toggled.add(slug) : _toggled.remove(slug));
    widget.onTeamToggled!(slug, team, selected);
  }

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
        if (!widget.embedded)
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
    final showBack = !(_atRoot || searching);
    final title = showBack
        ? GameDayTeamFolders.ancestry(_folderId)
            .map((n) => n.name)
            .join(' › ')
        : 'Choose a Team';
    return Padding(
      padding: EdgeInsets.only(left: showBack ? 8 : 20, right: 12),
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'Back',
              icon: const Icon(Icons.arrow_back_rounded),
              color: NexGenPalette.cyan,
              onPressed: _goUp,
            ),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: NexGenPalette.textHigh,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_multi && !widget.embedded)
            TextButton(
              key: const ValueKey('team-picker-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
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
    final pickMode = widget.onTeamPicked != null || _multi;
    final alreadyAdded = !pickMode && widget.existingTeamSlugs.contains(slug);
    final picked = _multi
        ? _toggled.contains(slug)
        : widget.onTeamPicked != null && widget.selectedTeamSlug == slug;
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
      trailing: alreadyAdded || picked
          ? Icon(Icons.check_circle,
              color: picked ? NexGenPalette.cyan : NexGenPalette.green,
              size: 20)
          : const Icon(Icons.add_circle_outline,
              color: NexGenPalette.cyan, size: 20),
      onTap: _multi
          ? () => _toggle(slug, team)
          : pickMode
              ? () => widget.onTeamPicked!(slug, team)
              : alreadyAdded
                  ? null
                  : () => _addTeam(context, ref, slug, team),
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
