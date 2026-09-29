import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/theme.dart';

/// A widget that displays smart suggestions as dismissible cards
class SmartSuggestionsList extends ConsumerWidget {
  final Function(SmartSuggestion)? onSuggestionAction;
  final int maxSuggestions;

  /// Whether the host can act on a suggestion. A card whose kind the host
  /// cannot act on shows no action button (row 77: "Add", "Action" and the
  /// like used to do nothing at all). Null = every card is actionable.
  final bool Function(SmartSuggestion)? isActionable;

  const SmartSuggestionsList({
    super.key,
    this.onSuggestionAction,
    this.maxSuggestions = 5,
    this.isActionable,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestionsAsync = ref.watch(activeSuggestionsProvider);

    return suggestionsAsync.when(
      data: (suggestions) {
        if (suggestions.isEmpty) {
          return const SizedBox.shrink();
        }

        final displaySuggestions = suggestions.take(maxSuggestions).toList();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.lightbulb_outline_rounded,
                    color: NexGenPalette.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Suggestions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: NexGenPalette.textPrimary,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const Spacer(),
                  Text(
                    '${displaySuggestions.length}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: NexGenPalette.textSecondary,
                        ),
                  ),
                ],
              ),
            ),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: displaySuggestions.length,
              separatorBuilder: (context, index) => const SizedBox(height: 12),
              itemBuilder: (context, index) {
                final suggestion = displaySuggestions[index];
                final actionable =
                    isActionable == null || isActionable!(suggestion);
                return _SuggestionCard(
                  suggestion: suggestion,
                  onAction: onSuggestionAction != null && actionable
                      ? () => onSuggestionAction!(suggestion)
                      : null,
                );
              },
            ),
          ],
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (error, stack) => const SizedBox.shrink(),
    );
  }
}

class _SuggestionCard extends ConsumerWidget {
  final SmartSuggestion suggestion;
  final VoidCallback? onAction;

  const _SuggestionCard({
    required this.suggestion,
    this.onAction,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Dismissible(
      key: Key(suggestion.id),
      direction: DismissDirection.endToStart,
      background: Container(
        decoration: BoxDecoration(
          color: Colors.red.shade900.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.red,
        ),
      ),
      // Row 78: the dismissal is saved FIRST, and the card goes — and says so
      // — only when it was. The write used to be fired and forgotten with its
      // error swallowed, and "Suggestion dismissed" showed regardless; a card
      // that failed to dismiss came straight back.
      confirmDismiss: (direction) => _dismiss(context, ref),
      onDismissed: (direction) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('Suggestion dismissed'),
            backgroundColor: NexGenPalette.cardBackground,
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Card(
        color: _getCardColor(suggestion.type),
        elevation: 2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: _getBorderColor(suggestion.type),
            width: 1.5,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header with icon and priority
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: _getIconBackgroundColor(suggestion.type),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(
                      _getIconForType(suggestion.type),
                      color: _getIconColor(suggestion.type),
                      size: 20,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      suggestion.title,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                            color: NexGenPalette.textPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                    ),
                  ),
                  if (suggestion.priority >= 0.8)
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.amber.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.priority_high_rounded,
                            size: 14,
                            color: Colors.amber,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            'High',
                            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: Colors.amber,
                                  fontSize: 11,
                                ),
                          ),
                        ],
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              // Description
              Text(
                suggestion.description,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textSecondary,
                    ),
              ),
              const SizedBox(height: 16),
              // Actions
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    key: ValueKey('suggestion-dismiss-${suggestion.id}'),
                    onPressed: () => _dismiss(context, ref),
                    child: Text(
                      'Dismiss',
                      style: TextStyle(color: NexGenPalette.textSecondary),
                    ),
                  ),
                  if (onAction != null) ...[
                    const SizedBox(width: 8),
                    ElevatedButton.icon(
                      key: ValueKey('suggestion-action-${suggestion.id}'),
                      onPressed: onAction,
                      icon: Icon(_getActionIcon(suggestion.type), size: 18),
                      label: Text(_getActionLabel(suggestion.type)),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _getIconColor(suggestion.type),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Saves the dismissal and says so when it did not land. Returns whether it
  /// did (the swipe's `confirmDismiss`).
  Future<bool> _dismiss(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final ok = await ref
        .read(suggestionsNotifierProvider.notifier)
        .dismissSuggestion(suggestion.id);
    if (!ok) {
      messenger.showSnackBar(SnackBar(
        content: const Text("Couldn't dismiss that suggestion — try again."),
        backgroundColor: Colors.orange.shade800,
        behavior: SnackBarBehavior.floating,
      ));
    }
    return ok;
  }

  Color _getCardColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return NexGenPalette.cardBackground;
      case SuggestionType.applyPattern:
        return NexGenPalette.primary.withValues(alpha: 0.05);
      case SuggestionType.eventReminder:
        return Colors.purple.shade900.withValues(alpha: 0.1);
      case SuggestionType.favorite:
        return Colors.amber.shade900.withValues(alpha: 0.1);
      default:
        return NexGenPalette.cardBackground;
    }
  }

  Color _getBorderColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return NexGenPalette.primary.withValues(alpha: 0.3);
      case SuggestionType.applyPattern:
        return NexGenPalette.primary.withValues(alpha: 0.5);
      case SuggestionType.eventReminder:
        return Colors.purple.withValues(alpha: 0.5);
      case SuggestionType.favorite:
        return Colors.amber.withValues(alpha: 0.5);
      default:
        return NexGenPalette.primary.withValues(alpha: 0.3);
    }
  }

  Color _getIconBackgroundColor(SuggestionType type) {
    return _getIconColor(type).withValues(alpha: 0.15);
  }

  Color _getIconColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return NexGenPalette.primary;
      case SuggestionType.applyPattern:
        return NexGenPalette.secondary;
      case SuggestionType.eventReminder:
        return Colors.purple;
      case SuggestionType.favorite:
        return Colors.amber;
      case SuggestionType.automation:
        return Colors.green;
      case SuggestionType.optimization:
        return Colors.blue;
      default:
        return NexGenPalette.primary;
    }
  }

  IconData _getIconForType(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return Icons.schedule_rounded;
      case SuggestionType.applyPattern:
        return Icons.auto_awesome_rounded;
      case SuggestionType.eventReminder:
        return Icons.event_rounded;
      case SuggestionType.favorite:
        return Icons.star_rounded;
      case SuggestionType.automation:
        return Icons.settings_suggest_rounded;
      case SuggestionType.optimization:
        return Icons.tune_rounded;
      default:
        return Icons.lightbulb_rounded;
    }
  }

  IconData _getActionIcon(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return Icons.add_rounded;
      case SuggestionType.applyPattern:
        return Icons.play_arrow_rounded;
      case SuggestionType.eventReminder:
        return Icons.check_rounded;
      case SuggestionType.favorite:
        return Icons.star_rounded;
      default:
        return Icons.arrow_forward_rounded;
    }
  }

  String _getActionLabel(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return 'Create';
      case SuggestionType.applyPattern:
        return 'Apply';
      case SuggestionType.eventReminder:
        return 'Got it';
      case SuggestionType.favorite:
        return 'Add';
      default:
        return 'Action';
    }
  }
}
