import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/wled/current_colors_provider.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';
import 'package:nexgen_command/features/wled/save_custom_pattern_dialog.dart';
import 'package:nexgen_command/theme.dart';
import 'package:go_router/go_router.dart';

/// Screen for viewing and editing current WLED colors
class CurrentColorsEditorScreen extends ConsumerWidget {
  const CurrentColorsEditorScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colorsState = ref.watch(currentColorsProvider);

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Current Colors'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh',
            onPressed: () {
              ref.read(currentColorsProvider.notifier).refresh();
            },
          ),
        ],
      ),
      body: colorsState.isLoading
          ? const Center(child: CircularProgressIndicator())
          : colorsState.errorMessage != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.error,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          colorsState.errorMessage!,
                          style: Theme.of(context).textTheme.titleMedium,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 24),
                        FilledButton.icon(
                          onPressed: () {
                            ref.read(currentColorsProvider.notifier).refresh();
                          },
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ],
                    ),
                  ),
                )
              : _buildColorEditor(context, ref, colorsState),
    );
  }

  Widget _buildColorEditor(BuildContext context, WidgetRef ref, CurrentColorsState state) {
    return Column(
      children: [
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Info card
                _buildInfoCard(context),
                const SizedBox(height: 24),

                // Currently Active Colors header
                Text(
                  'Currently Active Colors',
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Tap any color to change it',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 24),

                // Color swatches
                _buildColorSwatches(context, ref, state),

                const SizedBox(height: 32),

                // Effect info (optional)
                _buildEffectInfo(context, state),
              ],
            ),
          ),
        ),

        // Bottom action buttons
        _buildActionButtons(context, ref),
      ],
    );
  }

  Widget _buildInfoCard(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.cyan.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: NexGenPalette.cyan.withValues(alpha: 0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            Icons.info_outline,
            color: NexGenPalette.cyan,
            size: 24,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Edit colors temporarily or save as a custom pattern for future use',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface,
                  ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildColorSwatches(BuildContext context, WidgetRef ref, CurrentColorsState state) {
    final colors = state.colors;
    final maxColors = 3; // WLED supports up to 3 colors per segment

    return Column(
      children: [
        for (int i = 0; i < maxColors; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: _buildColorSwatch(
              context,
              ref,
              index: i,
              color: i < colors.length ? colors[i] : Colors.grey.shade800,
              label: _getColorLabel(i),
              isActive: i < colors.length,
            ),
          ),
      ],
    );
  }

  String _getColorLabel(int index) {
    switch (index) {
      case 0:
        return 'Primary Color';
      case 1:
        return 'Secondary Color';
      case 2:
        return 'Tertiary Color';
      default:
        return 'Color ${index + 1}';
    }
  }

  Widget _buildColorSwatch(
    BuildContext context,
    WidgetRef ref, {
    required int index,
    required Color color,
    required String label,
    required bool isActive,
  }) {
    return InkWell(
      onTap: () => _showColorPicker(context, ref, index, color),
      borderRadius: BorderRadius.circular(16),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            // Color circle
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.2),
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: color.withValues(alpha: 0.3),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 16),

            // Label and RGB values
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'RGB: ${(color.r * 255.0).round()}, ${(color.g * 255.0).round()}, ${(color.b * 255.0).round()}',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                  ),
                ],
              ),
            ),

            // Edit icon
            Icon(
              Icons.edit,
              color: NexGenPalette.cyan,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectInfo(BuildContext context, CurrentColorsState state) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Effect',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.bold,
                ),
          ),
          const SizedBox(height: 8),
          _buildInfoRow(context, 'Effect ID', '${state.effectId}'),
          _buildInfoRow(context, 'Speed', '${state.speed}'),
          _buildInfoRow(context, 'Intensity', '${state.intensity}'),
          _buildInfoRow(context, 'Brightness', '${state.brightness}'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.bold,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context, WidgetRef ref) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _handleApply(context, ref),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  side: BorderSide(color: NexGenPalette.cyan),
                ),
                child: const Text('Apply'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: FilledButton(
                onPressed: () => _handleSaveAs(context, ref),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Save As...'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showColorPicker(BuildContext context, WidgetRef ref, int index, Color currentColor) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _ColorPickerModal(
        initialColor: currentColor,
        onColorSelected: (color) {
          ref.read(currentColorsProvider.notifier).updateColor(index, color);
        },
      ),
    );
  }

  Future<void> _handleApply(BuildContext context, WidgetRef ref) async {
    // Show loading indicator
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(child: CircularProgressIndicator()),
    );

    final success = await ref.read(currentColorsProvider.notifier).applyTemporaryColors();

    if (context.mounted) {
      Navigator.of(context).pop(); // Close loading dialog

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Colors applied successfully'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop(); // Close the editor screen
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to apply colors'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _handleSaveAs(BuildContext context, WidgetRef ref) async {
    final patternName = await showDialog<String>(
      context: context,
      builder: (context) => const SaveCustomPatternDialog(),
    );

    if (patternName == null || patternName.trim().isEmpty) return;

    if (context.mounted) {
      // Show loading indicator
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(child: CircularProgressIndicator()),
      );

      final success = await ref.read(currentColorsProvider.notifier).saveAsCustomPattern(patternName);

      if (context.mounted) {
        Navigator.of(context).pop(); // Close loading dialog

        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Pattern "$patternName" saved successfully'),
              backgroundColor: Colors.green,
            ),
          );
          context.pop(); // Close the editor screen
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Failed to save pattern'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    }
  }
}

/// Color picker modal with HSV wheel
class _ColorPickerModal extends StatefulWidget {
  final Color initialColor;
  final ValueChanged<Color> onColorSelected;

  const _ColorPickerModal({
    required this.initialColor,
    required this.onColorSelected,
  });

  @override
  State<_ColorPickerModal> createState() => _ColorPickerModalState();
}

class _ColorPickerModalState extends State<_ColorPickerModal> {
  late Color _selectedColor;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
    _brightness = HSVColor.fromColor(widget.initialColor).value;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 24),

              // Title
              Text(
                'Select Color',
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 24),

              // Color wheel
              NeonColorWheel(
                size: 280,
                color: _selectedColor,
                onChanged: (color) {
                  setState(() => _selectedColor = color);
                },
              ),
              const SizedBox(height: 24),

              // Brightness slider
              Row(
                children: [
                  Icon(Icons.brightness_6, color: Theme.of(context).colorScheme.onSurfaceVariant),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Slider(
                      value: _brightness,
                      min: 0.0,
                      max: 1.0,
                      onChanged: (value) {
                        setState(() {
                          _brightness = value;
                          final hsv = HSVColor.fromColor(_selectedColor);
                          _selectedColor = hsv.withValue(value).toColor();
                        });
                      },
                      activeColor: NexGenPalette.cyan,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 24),

              // Color preview
              Container(
                width: double.infinity,
                height: 60,
                decoration: BoxDecoration(
                  color: _selectedColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.2),
                    width: 2,
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Action buttons
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: FilledButton(
                      onPressed: () {
                        widget.onColorSelected(_selectedColor);
                        Navigator.of(context).pop();
                      },
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                      ),
                      child: const Text('Select'),
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
}
