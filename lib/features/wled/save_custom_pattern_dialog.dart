import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// Dialog for naming and saving a custom pattern
class SaveCustomPatternDialog extends StatefulWidget {
  const SaveCustomPatternDialog({super.key});

  @override
  State<SaveCustomPatternDialog> createState() => _SaveCustomPatternDialogState();
}

class _SaveCustomPatternDialogState extends State<SaveCustomPatternDialog> {
  final _nameController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.save, color: NexGenPalette.cyan),
          const SizedBox(width: 12),
          const Text('Save Custom Pattern'),
        ],
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Give your custom pattern a name so you can find it later in My Designs.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Pattern Name',
                hintText: 'e.g., My Sunset Colors',
                prefixIcon: Icon(Icons.palette, color: NexGenPalette.cyan),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.cyan, width: 2),
                ),
              ),
              validator: (value) {
                if (value == null || value.trim().isEmpty) {
                  return 'Please enter a pattern name';
                }
                if (value.trim().length < 3) {
                  return 'Name must be at least 3 characters';
                }
                if (value.trim().length > 30) {
                  return 'Name must be less than 30 characters';
                }
                return null;
              },
              maxLength: 30,
              textCapitalization: TextCapitalization.words,
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 20,
                    color: NexGenPalette.cyan,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Your pattern will be saved to My Designs',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
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
        OutlinedButton(
          onPressed: () => Navigator.of(context).pop(null),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            if (_formKey.currentState?.validate() ?? false) {
              Navigator.of(context).pop(_nameController.text.trim());
            }
          },
          style: FilledButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
          ),
          child: const Text('Save'),
        ),
      ],
    );
  }
}
