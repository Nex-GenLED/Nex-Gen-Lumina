import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/analytics/analytics_providers.dart';

/// Dialog for requesting a missing pattern
class PatternRequestDialog extends ConsumerStatefulWidget {
  const PatternRequestDialog({super.key});

  @override
  ConsumerState<PatternRequestDialog> createState() => _PatternRequestDialogState();

  /// Show the pattern request dialog
  static Future<void> show(BuildContext context) {
    return showDialog(
      context: context,
      builder: (context) => const PatternRequestDialog(),
    );
  }
}

class _PatternRequestDialogState extends ConsumerState<PatternRequestDialog> {
  final _themeController = TextEditingController();
  final _descriptionController = TextEditingController();
  String? _selectedCategory;

  final List<String> _categories = [
    'Holiday',
    'Sports',
    'Seasonal',
    'Architectural',
    'Event',
    'Custom',
  ];

  @override
  void dispose() {
    _themeController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    final theme = _themeController.text.trim();
    if (theme.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please enter a theme or pattern name')),
      );
      return;
    }

    final notifier = ref.read(patternRequestNotifierProvider.notifier);

    await notifier.requestPattern(
      requestedTheme: theme,
      description: _descriptionController.text.trim().isEmpty ? null : _descriptionController.text.trim(),
      suggestedCategory: _selectedCategory,
    );

    if (mounted) {
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pattern request submitted! We\'ll review and consider adding it.'),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final requestState = ref.watch(patternRequestNotifierProvider);

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.lightbulb_outline, color: NexGenPalette.cyan),
          const SizedBox(width: 8),
          const Expanded(child: Text('Request a Pattern')),
        ],
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Info banner
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Can\'t find the pattern you\'re looking for? Let us know!',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            // Theme/pattern name
            Text('What pattern would you like?', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _themeController,
              decoration: const InputDecoration(
                hintText: 'e.g., "Halloween Spooky", "Lakers Purple & Gold"',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.palette_outlined),
              ),
            ),
            const SizedBox(height: 16),

            // Category
            Text('Category (optional)', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            DropdownButtonFormField<String>(
              value: _selectedCategory,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.category_outlined),
              ),
              hint: const Text('Select a category'),
              items: _categories.map((cat) {
                return DropdownMenuItem(
                  value: cat,
                  child: Text(cat),
                );
              }).toList(),
              onChanged: (value) => setState(() => _selectedCategory = value),
            ),
            const SizedBox(height: 16),

            // Description
            Text('Description (optional)', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 8),
            TextField(
              controller: _descriptionController,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Describe the colors, effects, or vibe you\'re looking for...',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),

            // Community voting note
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: NexGenPalette.gold.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: NexGenPalette.gold.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Icons.trending_up, size: 14, color: NexGenPalette.gold),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Popular requests get priority! Others can vote for your idea.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            fontSize: 10,
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
        FilledButton.icon(
          onPressed: requestState.isLoading ? null : _submitRequest,
          icon: requestState.isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.send),
          label: const Text('Submit Request'),
        ),
      ],
    );
  }
}
