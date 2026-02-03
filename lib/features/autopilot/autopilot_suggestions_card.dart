import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/theme.dart';

/// A card displaying pending autopilot suggestions.
///
/// Shows when `autonomyLevel == 1` (Suggest mode) and there are
/// pending suggestions that need user approval.
class AutopilotSuggestionsCard extends ConsumerWidget {
  const AutopilotSuggestionsCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final suggestions = ref.watch(autopilotSuggestionsProvider);
    final pendingSuggestions =
        suggestions.where((s) => s.status == SuggestionStatus.pending).toList();

    if (pendingSuggestions.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lumina Suggestions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: NexGenPalette.cyan.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    '${pendingSuggestions.length} pending',
                    style: const TextStyle(
                      fontSize: 12,
                      color: NexGenPalette.cyan,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(),
          // Suggestions list
          ListView.separated(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            itemCount: pendingSuggestions.length.clamp(0, 3),
            separatorBuilder: (_, __) => const Divider(height: 1),
            itemBuilder: (context, index) {
              final suggestion = pendingSuggestions[index];
              return _SuggestionTile(
                suggestion: suggestion,
                onApply: () async {
                  // Use scheduler to properly apply pattern and record feedback
                  final scheduler = ref.read(autopilotSchedulerProvider);
                  await scheduler.approveSuggestion(suggestion.id);
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Applied "${suggestion.patternName}"'),
                        backgroundColor: Colors.green.shade700,
                      ),
                    );
                  }
                },
                onReject: () async {
                  // Use scheduler to record rejection feedback
                  final scheduler = ref.read(autopilotSchedulerProvider);
                  await scheduler.rejectSuggestion(suggestion.id);
                },
              );
            },
          ),
          if (pendingSuggestions.length > 3) ...[
            const Divider(),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Center(
                child: TextButton(
                  onPressed: () {
                    // Navigate to full suggestions view
                  },
                  child: Text(
                    'View all ${pendingSuggestions.length} suggestions',
                    style: const TextStyle(color: NexGenPalette.cyan),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Individual suggestion tile with swipe actions.
class _SuggestionTile extends StatefulWidget {
  final AutopilotSuggestion suggestion;
  final Future<void> Function() onApply;
  final Future<void> Function() onReject;

  const _SuggestionTile({
    required this.suggestion,
    required this.onApply,
    required this.onReject,
  });

  @override
  State<_SuggestionTile> createState() => _SuggestionTileState();
}

class _SuggestionTileState extends State<_SuggestionTile> {
  bool _isApplying = false;

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.suggestion.id),
      background: Container(
        color: Colors.green,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 16),
        child: const Icon(Icons.check, color: Colors.white),
      ),
      secondaryBackground: Container(
        color: Colors.red,
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: 16),
        child: const Icon(Icons.close, color: Colors.white),
      ),
      confirmDismiss: (direction) async {
        if (direction == DismissDirection.startToEnd) {
          await widget.onApply();
        } else {
          await widget.onReject();
        }
        return true;
      },
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        leading: _buildPatternPreview(),
        title: Text(
          widget.suggestion.patternName,
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              widget.suggestion.reason,
              style: TextStyle(
                color: Colors.grey[600],
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                Icon(
                  Icons.schedule,
                  size: 14,
                  color: Colors.grey[500],
                ),
                const SizedBox(width: 4),
                Text(
                  _formatScheduledTime(widget.suggestion.scheduledTime),
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[500],
                  ),
                ),
                const SizedBox(width: 12),
                _buildConfidenceIndicator(),
              ],
            ),
          ],
        ),
        trailing: _isApplying
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.check_circle_outline, color: Colors.green),
                    onPressed: () async {
                      setState(() => _isApplying = true);
                      await widget.onApply();
                      if (mounted) setState(() => _isApplying = false);
                    },
                    tooltip: 'Apply',
                  ),
                  IconButton(
                    icon: const Icon(Icons.cancel_outlined, color: Colors.red),
                    onPressed: () => widget.onReject(),
                    tooltip: 'Skip',
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildPatternPreview() {
    // Create a simple color preview from the pattern
    final colors = widget.suggestion.wledPayload['seg']?[0]?['col'] as List?;

    if (colors == null || colors.isEmpty) {
      return Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: Colors.grey[300],
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.lightbulb_outline, color: Colors.white),
      );
    }

    final displayColors = <Color>[];
    for (final colorArray in colors.take(3)) {
      if (colorArray is List && colorArray.length >= 3) {
        displayColors.add(Color.fromRGBO(
          colorArray[0] as int,
          colorArray[1] as int,
          colorArray[2] as int,
          1.0,
        ));
      }
    }

    if (displayColors.isEmpty) {
      displayColors.add(Colors.grey);
    }

    return Container(
      width: 48,
      height: 48,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        gradient: displayColors.length > 1
            ? LinearGradient(colors: displayColors)
            : null,
        color: displayColors.length == 1 ? displayColors.first : null,
      ),
    );
  }

  Widget _buildConfidenceIndicator() {
    final confidence = widget.suggestion.confidenceScore;
    final color = confidence >= 0.7
        ? Colors.green
        : confidence >= 0.4
            ? Colors.orange
            : Colors.red;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.psychology,
          size: 14,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          '${(confidence * 100).toStringAsFixed(0)}%',
          style: TextStyle(
            fontSize: 12,
            color: color,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatScheduledTime(DateTime time) {
    final hour = time.hour > 12 ? time.hour - 12 : (time.hour == 0 ? 12 : time.hour);
    final minute = time.minute.toString().padLeft(2, '0');
    final period = time.hour >= 12 ? 'PM' : 'AM';
    final monthDay = '${time.month}/${time.day}';
    return '$monthDay at $hour:$minute $period';
  }
}

/// Compact suggestion badge for dashboard header.
class AutopilotSuggestionsBadge extends ConsumerWidget {
  const AutopilotSuggestionsBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final count = ref.watch(pendingSuggestionsCountProvider);

    if (count == 0) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withOpacity(0.2),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withOpacity(0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.auto_awesome,
            size: 14,
            color: NexGenPalette.cyan,
          ),
          const SizedBox(width: 4),
          Text(
            '$count suggestion${count > 1 ? 's' : ''}',
            style: const TextStyle(
              fontSize: 12,
              color: NexGenPalette.cyan,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
