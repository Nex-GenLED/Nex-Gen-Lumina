import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';

/// Dialog for collecting user feedback on a pattern
class PatternFeedbackDialog extends ConsumerStatefulWidget {
  final String patternName;
  final String? source;

  const PatternFeedbackDialog({
    super.key,
    required this.patternName,
    this.source,
  });

  @override
  ConsumerState<PatternFeedbackDialog> createState() => _PatternFeedbackDialogState();

  /// Show the feedback dialog
  static Future<void> show(
    BuildContext context, {
    required String patternName,
    String? source,
  }) {
    return showDialog(
      context: context,
      builder: (context) => PatternFeedbackDialog(
        patternName: patternName,
        source: source,
      ),
    );
  }
}

class _PatternFeedbackDialogState extends ConsumerState<PatternFeedbackDialog> {
  int _rating = 3;
  final _commentController = TextEditingController();
  bool _saved = false;

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    final notifier = ref.read(patternFeedbackNotifierProvider.notifier);

    await notifier.submitFeedback(
      patternName: widget.patternName,
      rating: _rating,
      comment: _commentController.text.trim().isEmpty ? null : _commentController.text.trim(),
      saved: _saved,
      source: widget.source,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Thank you for your feedback!'),
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final feedbackState = ref.watch(patternFeedbackNotifierProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.star_outline, color: NexGenPalette.gold),
          const SizedBox(width: 8),
          const Expanded(child: Text('Rate this Pattern')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Pattern name
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.palette, size: 16, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      widget.patternName,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Star rating
            Text('How would you rate this pattern?', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(5, (index) {
                final starValue = index + 1;
                return IconButton(
                  icon: Icon(
                    starValue <= _rating ? Icons.star : Icons.star_outline,
                    color: starValue <= _rating ? NexGenPalette.gold : Colors.white54,
                    size: 32,
                  ),
                  onPressed: () => setState(() => _rating = starValue),
                );
              }),
            ),
            const SizedBox(height: 8),
            Center(
              child: Text(
                _ratingLabel(_rating),
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: NexGenPalette.gold,
                    ),
              ),
            ),
            const SizedBox(height: 16),

            // Optional comment
            Text('Comments (optional)', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _commentController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Tell us what you liked or what could be improved...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Saved checkbox
            Row(
              children: [
                Checkbox(
                  value: _saved,
                  onChanged: (value) => setState(() => _saved = value ?? false),
                  activeColor: NexGenPalette.cyan,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'I saved this pattern to my favorites',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              ],
            ),

            // Privacy note
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Row(
                children: [
                  Icon(Icons.lock_outline, size: 14, color: Colors.white60),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Your feedback is anonymized and helps us improve',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
                            color: Colors.white60,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: feedbackState.isLoading ? null : _submitFeedback,
          child: feedbackState.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Submit'),
        ),
      ],
    );
  }

  String _ratingLabel(int rating) {
    switch (rating) {
      case 1:
        return 'Poor';
      case 2:
        return 'Fair';
      case 3:
        return 'Good';
      case 4:
        return 'Very Good';
      case 5:
        return 'Excellent';
      default:
        return 'Good';
    }
  }
}
