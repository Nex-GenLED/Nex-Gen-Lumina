// lib/widgets/team_priority_list.dart
//
// THE drag-to-reorder control for a user's Game Day team hierarchy.
//
// Rendered in two places — Edit Profile (where it has always lived) and the
// Game Day screen (where the ordering actually takes effect, and where users
// were never able to see or change it). One widget, so the two surfaces
// cannot drift in what they show; one write helper
// (`TeamRegistrationService.setTeamPriority`), so they cannot drift in what
// they store.
//
// The control is deliberately dumb: it owns no data and performs no write. It
// takes the ordered rows, and hands back the reordered rows. Each surface
// decides when to persist — Game Day writes immediately, Edit Profile folds
// the change into its existing Save button — but both persist the SAME two
// fields from the SAME derivation (`alignPriorityLists`).

import 'package:flutter/material.dart';

import '../data/sports_teams.dart';
import '../features/autopilot/team_priority.dart';
import '../theme.dart';

/// Reorderable list for team priority. Each row shows the team's gradient
/// color avatar + full display name (matching the chip styling used in the
/// Interests card) plus a numbered priority circle and drag handle.
///
/// The single styling means users see one consistent representation of each
/// team wherever the hierarchy appears — and the numbered circle plus the
/// "Primary" badge on row 1 make the thing the arbiter actually reads visible
/// at a glance.
class TeamPriorityList extends StatelessWidget {
  /// Rows in priority order, highest first.
  final List<TeamPriorityEntry> entries;

  /// Called with the full reordered list after a drag.
  final ValueChanged<List<TeamPriorityEntry>> onReorderEntries;

  const TeamPriorityList({
    super.key,
    required this.entries,
    required this.onReorderEntries,
  });

  @override
  Widget build(BuildContext context) {
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: entries.length,
      onReorder: (oldIndex, newIndex) {
        final reordered = List<TeamPriorityEntry>.from(entries);
        if (newIndex > oldIndex) newIndex--;
        final item = reordered.removeAt(oldIndex);
        reordered.insert(newIndex, item);
        onReorderEntries(reordered);
      },
      itemBuilder: (context, index) {
        final entry = entries[index];
        final team = SportsTeamsDatabase.getByName(entry.displayName);
        final colors = team?.colors ?? const [Colors.grey, Colors.grey];
        final displayName = team?.displayName ?? entry.displayName;

        return ListTile(
          // Keyed by slug where there is one: two legacy rows could in
          // principle share a display name, and a duplicate key throws.
          key: ValueKey(entry.slug ?? 'name:${entry.displayName}'),
          contentPadding: const EdgeInsets.symmetric(horizontal: 4),
          leading: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.drag_handle, color: Colors.grey),
              const SizedBox(width: 8),
              // Numbered priority circle — keeps the order index visible
              // and highlights the primary team in cyan.
              Container(
                width: 24,
                height: 24,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: index == 0
                      ? NexGenPalette.cyan
                      : Colors.grey.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: Text(
                  '${index + 1}',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: index == 0 ? Colors.black : Colors.white,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              // Team color gradient avatar — matches the TeamChip styling
              // used in the Interests card so the user sees one consistent
              // visual representation of the team.
              TeamGradientAvatar(colors: colors),
            ],
          ),
          title: Text(
            displayName,
            style: const TextStyle(fontWeight: FontWeight.w500),
          ),
          subtitle: team?.league != null
              ? Text(
                  team!.league,
                  style: TextStyle(
                    fontSize: 11,
                    color: NexGenPalette.textMedium,
                  ),
                )
              : null,
          trailing: index == 0
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'Primary',
                    style: TextStyle(fontSize: 11, color: NexGenPalette.cyan),
                  ),
                )
              : null,
        );
      },
    );
  }
}

/// Small circular gradient avatar showing a team's primary/secondary colors.
class TeamGradientAvatar extends StatelessWidget {
  static const double _size = 24;
  final List<Color> colors;

  const TeamGradientAvatar({super.key, required this.colors});

  @override
  Widget build(BuildContext context) {
    if (colors.isEmpty) {
      return Container(
        width: _size,
        height: _size,
        decoration: const BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.grey,
        ),
      );
    }
    if (colors.length == 1) {
      return Container(
        width: _size,
        height: _size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.first,
        ),
      );
    }
    return Container(
      width: _size,
      height: _size,
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
