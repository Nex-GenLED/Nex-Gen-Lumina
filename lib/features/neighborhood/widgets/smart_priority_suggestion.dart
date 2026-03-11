import 'package:flutter/material.dart';

import '../../../theme.dart';
import '../models/sync_event.dart';
import '../providers/sync_handoff_providers.dart';

/// Bottom sheet or dialog shown when a user creates or joins a new group.
///
/// Surfaces the priority decision only when needed (same duration type conflict)
/// and handles everything else with a friendly "Got it" confirmation.
class SmartPrioritySuggestionSheet extends StatelessWidget {
  final PrioritySuggestion suggestion;

  /// Called when the user acknowledges the suggestion (for automatic types).
  final VoidCallback? onAcknowledge;

  /// Called when the user picks a priority in a same-type conflict.
  /// The string is the group name they chose as higher priority.
  final ValueChanged<String>? onPriorityChosen;

  /// Name of the conflicting shortForm group (for same-type conflicts).
  final String? existingGroupName;

  /// Name of the new group being added.
  final String? newGroupName;

  const SmartPrioritySuggestionSheet({
    super.key,
    required this.suggestion,
    this.onAcknowledge,
    this.onPriorityChosen,
    this.existingGroupName,
    this.newGroupName,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        border: Border.all(
          color: NexGenPalette.accent.withOpacity(0.2),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Handle indicator
          Center(
            child: Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),

          // Icon
          _buildIcon(),
          const SizedBox(height: 16),

          // Title
          Text(
            _title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 12),

          // Message
          Text(
            suggestion.message,
            style: TextStyle(
              color: Colors.white.withOpacity(0.8),
              fontSize: 14,
              height: 1.5,
            ),
          ),
          const SizedBox(height: 24),

          // Action buttons
          _buildActions(context),

          // Bottom safe area
          SizedBox(height: MediaQuery.of(context).padding.bottom),
        ],
      ),
    );
  }

  Widget _buildIcon() {
    switch (suggestion.type) {
      case PrioritySuggestionType.gameDayAutomatic:
        return const _SuggestionIcon(
          icon: Icons.sports_football,
          color: Colors.orange,
        );
      case PrioritySuggestionType.holidayBackground:
        return const _SuggestionIcon(
          icon: Icons.celebration,
          color: Colors.green,
        );
      case PrioritySuggestionType.shortFormConflict:
        return const _SuggestionIcon(
          icon: Icons.swap_vert,
          color: Colors.amber,
        );
      case PrioritySuggestionType.none:
        return const SizedBox.shrink();
    }
  }

  String get _title {
    switch (suggestion.type) {
      case PrioritySuggestionType.gameDayAutomatic:
        return 'Automatic Game Day Priority';
      case PrioritySuggestionType.holidayBackground:
        return 'Holiday Group Added';
      case PrioritySuggestionType.shortFormConflict:
        return 'Priority Needed';
      case PrioritySuggestionType.none:
        return '';
    }
  }

  Widget _buildActions(BuildContext context) {
    switch (suggestion.type) {
      case PrioritySuggestionType.gameDayAutomatic:
      case PrioritySuggestionType.holidayBackground:
        return SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            onPressed: () {
              onAcknowledge?.call();
              Navigator.of(context).pop();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.accent,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text(
              'Got it',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
          ),
        );

      case PrioritySuggestionType.shortFormConflict:
        return Column(
          children: [
            // Existing group button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  onPriorityChosen?.call(existingGroupName ?? 'existing');
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexGenPalette.accent,
                  side: BorderSide(color: NexGenPalette.accent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  existingGroupName ?? 'Existing Group',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),
            // New group button
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () {
                  onPriorityChosen?.call(newGroupName ?? 'new');
                  Navigator.of(context).pop();
                },
                style: OutlinedButton.styleFrom(
                  foregroundColor: NexGenPalette.accent,
                  side: BorderSide(color: NexGenPalette.accent.withOpacity(0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: Text(
                  newGroupName ?? 'New Group',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
            ),
          ],
        );

      case PrioritySuggestionType.none:
        return const SizedBox.shrink();
    }
  }
}

class _SuggestionIcon extends StatelessWidget {
  final IconData icon;
  final Color color;

  const _SuggestionIcon({required this.icon, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withOpacity(0.3)),
      ),
      child: Icon(icon, color: color, size: 24),
    );
  }
}

/// Shows the smart priority suggestion bottom sheet.
///
/// Call this when a user creates or joins a new group. The suggestion
/// is computed from their existing groups' categories.
void showSmartPrioritySuggestion(
  BuildContext context, {
  required PrioritySuggestion suggestion,
  VoidCallback? onAcknowledge,
  ValueChanged<String>? onPriorityChosen,
  String? existingGroupName,
  String? newGroupName,
}) {
  if (suggestion.type == PrioritySuggestionType.none) return;

  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SmartPrioritySuggestionSheet(
      suggestion: suggestion,
      onAcknowledge: onAcknowledge,
      onPriorityChosen: onPriorityChosen,
      existingGroupName: existingGroupName,
      newGroupName: newGroupName,
    ),
  );
}
