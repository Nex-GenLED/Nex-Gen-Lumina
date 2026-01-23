import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/models/usage_analytics_models.dart';
import 'package:nexgen_command/theme.dart';

/// A widget that displays smart suggestions as dismissible cards
class SmartSuggestionsList extends ConsumerWidget {
  final Function(SmartSuggestion)? onSuggestionAction;
  final int maxSuggestions;

  const SmartSuggestionsList({
    super.key,
    this.onSuggestionAction,
    this.maxSuggestions = 5,
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
                return _SuggestionCard(
                  suggestion: suggestion,
                  onAction: onSuggestionAction != null
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
          color: Colors.red.shade900.withOpacity(0.3),
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(
          Icons.delete_outline_rounded,
          color: Colors.red,
        ),
      ),
      onDismissed: (direction) {
        ref.read(suggestionsNotifierProvider.notifier).dismissSuggestion(suggestion.id);
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
                        color: Colors.amber.withOpacity(0.2),
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
                    onPressed: () {
                      ref
                          .read(suggestionsNotifierProvider.notifier)
                          .dismissSuggestion(suggestion.id);
                    },
                    child: Text(
                      'Dismiss',
                      style: TextStyle(color: NexGenPalette.textSecondary),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton.icon(
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
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _getCardColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return NexGenPalette.cardBackground;
      case SuggestionType.applyPattern:
        return NexGenPalette.primary.withOpacity(0.05);
      case SuggestionType.eventReminder:
        return Colors.purple.shade900.withOpacity(0.1);
      case SuggestionType.favorite:
        return Colors.amber.shade900.withOpacity(0.1);
      default:
        return NexGenPalette.cardBackground;
    }
  }

  Color _getBorderColor(SuggestionType type) {
    switch (type) {
      case SuggestionType.createSchedule:
        return NexGenPalette.primary.withOpacity(0.3);
      case SuggestionType.applyPattern:
        return NexGenPalette.primary.withOpacity(0.5);
      case SuggestionType.eventReminder:
        return Colors.purple.withOpacity(0.5);
      case SuggestionType.favorite:
        return Colors.amber.withOpacity(0.5);
      default:
        return NexGenPalette.primary.withOpacity(0.3);
    }
  }

  Color _getIconBackgroundColor(SuggestionType type) {
    return _getIconColor(type).withOpacity(0.15);
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
