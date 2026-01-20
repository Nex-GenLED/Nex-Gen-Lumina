import 'package:flutter/material.dart';
import 'package:nexgen_command/data/sports_teams.dart';
import 'package:nexgen_command/theme.dart';

/// A chip that displays a team name with its colors as a gradient icon
class TeamChip extends StatelessWidget {
  final String teamName;
  final VoidCallback? onDeleted;
  final bool showDelete;

  const TeamChip({
    super.key,
    required this.teamName,
    this.onDeleted,
    this.showDelete = true,
  });

  @override
  Widget build(BuildContext context) {
    final team = SportsTeamsDatabase.getByName(teamName);
    final colors = team?.colors ?? [Colors.grey, Colors.grey];

    return InputChip(
      label: Text(teamName),
      avatar: _TeamColorIcon(colors: colors),
      onDeleted: showDelete ? onDeleted : null,
      deleteIconColor: Colors.white54,
    );
  }
}

/// Circular icon showing team colors as a gradient or split
class _TeamColorIcon extends StatelessWidget {
  final List<Color> colors;
  final double size;

  const _TeamColorIcon({required this.colors, this.size = 24});

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey,
        ),
      );
    }

    if (colors.length == 1) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.first,
        ),
      );
    }

    // Two or more colors - show as gradient
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: colors.take(2).toList(),
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        border: Border.all(color: Colors.white24, width: 1),
      ),
    );
  }
}

/// Autocomplete text field for selecting sports teams
class TeamAutocomplete extends StatefulWidget {
  final TextEditingController controller;
  final void Function(SportsTeam team) onTeamSelected;
  final String hintText;

  const TeamAutocomplete({
    super.key,
    required this.controller,
    required this.onTeamSelected,
    this.hintText = 'Search for a team...',
  });

  @override
  State<TeamAutocomplete> createState() => _TeamAutocompleteState();
}

class _TeamAutocompleteState extends State<TeamAutocomplete> {
  final LayerLink _layerLink = LayerLink();
  final FocusNode _focusNode = FocusNode();
  OverlayEntry? _overlayEntry;
  List<SportsTeam> _suggestions = [];

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onTextChanged);
    _focusNode.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onTextChanged);
    _focusNode.removeListener(_onFocusChanged);
    _focusNode.dispose();
    _removeOverlay();
    super.dispose();
  }

  void _onTextChanged() {
    final query = widget.controller.text.trim();
    if (query.length < 2) {
      _suggestions = [];
      _removeOverlay();
      return;
    }

    _suggestions = SportsTeamsDatabase.search(query).take(8).toList();
    if (_suggestions.isNotEmpty && _focusNode.hasFocus) {
      _showOverlay();
    } else {
      _removeOverlay();
    }
  }

  void _onFocusChanged() {
    if (!_focusNode.hasFocus) {
      _removeOverlay();
    } else if (_suggestions.isNotEmpty) {
      _showOverlay();
    }
  }

  void _showOverlay() {
    _removeOverlay();
    _overlayEntry = _createOverlayEntry();
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  OverlayEntry _createOverlayEntry() {
    final renderBox = context.findRenderObject() as RenderBox;
    final size = renderBox.size;

    return OverlayEntry(
      builder: (context) => Positioned(
        width: size.width,
        child: CompositedTransformFollower(
          link: _layerLink,
          showWhenUnlinked: false,
          offset: Offset(0, size.height + 4),
          child: Material(
            elevation: 8,
            borderRadius: BorderRadius.circular(12),
            color: NexGenPalette.gunmetal90,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 300),
              child: ListView.builder(
                padding: const EdgeInsets.symmetric(vertical: 8),
                shrinkWrap: true,
                itemCount: _suggestions.length,
                itemBuilder: (context, index) {
                  final team = _suggestions[index];
                  return _TeamSuggestionTile(
                    team: team,
                    onTap: () {
                      widget.onTeamSelected(team);
                      widget.controller.clear();
                      _removeOverlay();
                      _focusNode.unfocus();
                    },
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return CompositedTransformTarget(
      link: _layerLink,
      child: TextField(
        controller: widget.controller,
        focusNode: _focusNode,
        decoration: InputDecoration(
          hintText: widget.hintText,
          prefixIcon: const Icon(Icons.sports_outlined),
          suffixIcon: widget.controller.text.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    widget.controller.clear();
                    _removeOverlay();
                  },
                )
              : null,
        ),
        onSubmitted: (value) {
          // If there's exactly one suggestion, select it
          if (_suggestions.length == 1) {
            widget.onTeamSelected(_suggestions.first);
            widget.controller.clear();
          }
          _removeOverlay();
        },
      ),
    );
  }
}

/// Individual suggestion tile in the dropdown
class _TeamSuggestionTile extends StatelessWidget {
  final SportsTeam team;
  final VoidCallback onTap;

  const _TeamSuggestionTile({required this.team, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        child: Row(
          children: [
            // Team color icon
            _TeamColorIcon(colors: team.colors, size: 32),
            const SizedBox(width: 12),
            // Team name and league
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    team.displayName,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w500,
                        ),
                  ),
                  Text(
                    team.league,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textMedium,
                        ),
                  ),
                ],
              ),
            ),
            // Color swatches
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final color in team.colors.take(2))
                  Container(
                    width: 16,
                    height: 16,
                    margin: const EdgeInsets.only(left: 4),
                    decoration: BoxDecoration(
                      color: color,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white24),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Widget that displays selected teams with color chips and an autocomplete input
class TeamSelector extends StatelessWidget {
  final TextEditingController controller;
  final List<String> selectedTeams;
  final void Function(String teamName) onAddTeam;
  final void Function(String teamName) onRemoveTeam;

  const TeamSelector({
    super.key,
    required this.controller,
    required this.selectedTeams,
    required this.onAddTeam,
    required this.onRemoveTeam,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Selected teams as chips
        if (selectedTeams.isNotEmpty) ...[
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final teamName in selectedTeams)
                TeamChip(
                  teamName: teamName,
                  onDeleted: () => onRemoveTeam(teamName),
                ),
            ],
          ),
          const SizedBox(height: 12),
        ],
        // Autocomplete input
        TeamAutocomplete(
          controller: controller,
          hintText: 'Add team...',
          onTeamSelected: (team) {
            if (!selectedTeams.contains(team.displayName)) {
              onAddTeam(team.displayName);
            }
          },
        ),
      ],
    );
  }
}
