import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/services/segment_pattern_generator.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';
import 'package:nexgen_command/theme.dart';

/// State provider for the currently selected pattern template.
final selectedPatternTemplateProvider =
    StateProvider<SegmentAwarePattern?>((ref) => null);

/// Provider for generated LED color groups based on current pattern and config.
final generatedPatternProvider = Provider<List<LedColorGroup>>((ref) {
  final pattern = ref.watch(selectedPatternTemplateProvider);
  final configAsync = ref.watch(currentRooflineConfigProvider);

  if (pattern == null) return [];

  final config = configAsync.maybeWhen(
    data: (c) => c,
    orElse: () => null,
  );

  if (config == null) return [];

  final generator = ref.read(segmentPatternGeneratorProvider);
  return generator.generate(config: config, pattern: pattern);
});

/// Widget for selecting and configuring segment-aware pattern templates.
///
/// Displays a grid of available pattern templates, with configuration
/// options for the selected template (colors, spacing, etc.).
class PatternTemplateSelector extends ConsumerStatefulWidget {
  /// Callback when pattern is generated and should be applied.
  final void Function(List<LedColorGroup> groups, SegmentAwarePattern pattern)?
      onApply;

  const PatternTemplateSelector({
    super.key,
    this.onApply,
  });

  @override
  ConsumerState<PatternTemplateSelector> createState() =>
      _PatternTemplateSelectorState();
}

class _PatternTemplateSelectorState
    extends ConsumerState<PatternTemplateSelector> {
  // Configuration state
  Color _anchorColor = const Color(0xFFFFE4C4); // Warm white
  Color _spacedColor = const Color(0xFFFFE4C4);
  int _spacingCount = 4;
  int _anchorLedCount = 2;
  bool _anchorAlwaysOn = true;

  @override
  Widget build(BuildContext context) {
    final selectedPattern = ref.watch(selectedPatternTemplateProvider);
    final hasConfig = ref.watch(hasRooflineConfigProvider);

    if (!hasConfig) {
      return _buildNoConfigState();
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                const Text(
                  'Pattern Templates',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                if (selectedPattern != null)
                  TextButton.icon(
                    onPressed: () {
                      ref.read(selectedPatternTemplateProvider.notifier).state =
                          null;
                    },
                    icon: const Icon(Icons.close, size: 16),
                    label: const Text('Clear'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white54,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                    ),
                  ),
              ],
            ),
          ),

          // Template grid
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: _buildTemplateGrid(selectedPattern),
          ),

          // Configuration section (when template selected)
          if (selectedPattern != null) ...[
            const Divider(color: Colors.white12),
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildConfigSection(selectedPattern),
            ),
          ],

          // Generate button
          if (selectedPattern != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: _buildGenerateButton(selectedPattern),
            ),
        ],
      ),
    );
  }

  Widget _buildNoConfigState() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withValues(alpha: 0.1)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.settings_outlined,
            size: 32,
            color: Colors.white.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 8),
          Text(
            'Configure Roofline First',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.6),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Set up your roofline segments before using pattern templates',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 12,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildTemplateGrid(SegmentAwarePattern? selected) {
    final templates = SegmentAwarePattern.presets;

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: templates.map((template) {
        final isSelected = selected?.templateType == template.templateType;

        return _TemplateChip(
          template: template,
          isSelected: isSelected,
          onTap: () {
            ref.read(selectedPatternTemplateProvider.notifier).state = template;
            // Reset config to template defaults
            setState(() {
              _anchorColor = template.anchorColor;
              _spacedColor = template.spacedColor;
              _spacingCount = template.spacingCount;
              _anchorAlwaysOn = template.anchorAlwaysOn;
            });
          },
        );
      }).toList(),
    );
  }

  Widget _buildConfigSection(SegmentAwarePattern template) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Template name
        Text(
          template.templateType.displayName,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          template.templateType.description,
          style: TextStyle(
            color: Colors.white.withValues(alpha: 0.5),
            fontSize: 12,
          ),
        ),
        const SizedBox(height: 16),

        // Configuration based on template type
        if (template.templateType == PatternTemplateType.downlighting) ...[
          _buildColorPicker('Anchor Color', _anchorColor, (c) {
            setState(() => _anchorColor = c);
          }),
          const SizedBox(height: 12),
          _buildColorPicker('Spaced LED Color', _spacedColor, (c) {
            setState(() => _spacedColor = c);
          }),
          const SizedBox(height: 12),
          _buildSpacingSlider(),
          const SizedBox(height: 12),
          _buildAnchorLedCountSelector(),
        ] else if (template.templateType ==
            PatternTemplateType.alternatingSegments) ...[
          _buildColorPicker('Color 1', _anchorColor, (c) {
            setState(() => _anchorColor = c);
          }),
          const SizedBox(height: 12),
          _buildColorPicker('Color 2', _spacedColor, (c) {
            setState(() => _spacedColor = c);
          }),
        ] else if (template.templateType == PatternTemplateType.cornerAccent) ...[
          _buildColorPicker('Accent Color', _anchorColor, (c) {
            setState(() => _anchorColor = c);
          }),
          const SizedBox(height: 12),
          _buildColorPicker('Fill Color', _spacedColor, (c) {
            setState(() => _spacedColor = c);
          }),
        ] else ...[
          _buildColorPicker('Color', _anchorColor, (c) {
            setState(() => _anchorColor = c);
          }),
        ],
      ],
    );
  }

  Widget _buildColorPicker(
      String label, Color color, ValueChanged<Color> onChanged) {
    return Row(
      children: [
        Expanded(
          child: Text(
            label,
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        GestureDetector(
          onTap: () => _showColorPicker(color, onChanged),
          child: Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.white24),
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 4,
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildSpacingSlider() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text(
              'LEDs Between Anchors',
              style: TextStyle(color: Colors.white70, fontSize: 13),
            ),
            Text(
              '$_spacingCount',
              style: const TextStyle(
                color: NexGenPalette.cyan,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Slider(
          value: _spacingCount.toDouble(),
          min: 0,
          max: 10,
          divisions: 10,
          activeColor: NexGenPalette.cyan,
          inactiveColor: Colors.white.withValues(alpha: 0.1),
          onChanged: (v) => setState(() => _spacingCount = v.round()),
        ),
      ],
    );
  }

  Widget _buildAnchorLedCountSelector() {
    return Row(
      children: [
        const Expanded(
          child: Text(
            'LEDs per Anchor',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
        ),
        SegmentedButton<int>(
          segments: const [
            ButtonSegment(value: 1, label: Text('1')),
            ButtonSegment(value: 2, label: Text('2')),
            ButtonSegment(value: 3, label: Text('3')),
          ],
          selected: {_anchorLedCount},
          onSelectionChanged: (values) {
            setState(() => _anchorLedCount = values.first);
          },
          style: ButtonStyle(
            visualDensity: VisualDensity.compact,
          ),
        ),
      ],
    );
  }

  Widget _buildGenerateButton(SegmentAwarePattern template) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: () => _generateAndApply(template),
        icon: const Icon(Icons.auto_fix_high),
        label: const Text('Generate Pattern'),
      ),
    );
  }

  void _generateAndApply(SegmentAwarePattern baseTemplate) {
    // Create pattern with current config
    final pattern = baseTemplate.copyWith(
      anchorColor: _anchorColor,
      spacedColor: _spacedColor,
      spacingCount: _spacingCount,
      anchorAlwaysOn: _anchorAlwaysOn,
    );

    // Update the selected pattern
    ref.read(selectedPatternTemplateProvider.notifier).state = pattern;

    // Get generated groups
    final groups = ref.read(generatedPatternProvider);

    // Callback
    widget.onApply?.call(groups, pattern);
  }

  Future<void> _showColorPicker(
      Color currentColor, ValueChanged<Color> onChanged) async {
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => _QuickColorPicker(initialColor: currentColor),
    );

    if (result != null) {
      onChanged(result);
    }
  }
}

/// Template selection chip.
class _TemplateChip extends StatelessWidget {
  final SegmentAwarePattern template;
  final bool isSelected;
  final VoidCallback onTap;

  const _TemplateChip({
    required this.template,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.2)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : Colors.white12,
            width: isSelected ? 2 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              template.templateType.icon,
              size: 16,
              color: isSelected ? NexGenPalette.cyan : Colors.white54,
            ),
            const SizedBox(width: 6),
            Text(
              template.templateType.displayName,
              style: TextStyle(
                color: isSelected ? NexGenPalette.cyan : Colors.white70,
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick color picker dialog with preset colors.
class _QuickColorPicker extends StatefulWidget {
  final Color initialColor;

  const _QuickColorPicker({required this.initialColor});

  @override
  State<_QuickColorPicker> createState() => _QuickColorPickerState();
}

class _QuickColorPickerState extends State<_QuickColorPicker> {
  late Color _selectedColor;

  @override
  void initState() {
    super.initState();
    _selectedColor = widget.initialColor;
  }

  // Preset color palettes
  static const _presetColors = [
    // Warm whites
    Color(0xFFFFE4C4), // Bisque
    Color(0xFFFFE0B2), // Soft amber
    Color(0xFFF5DEB3), // Wheat
    Color(0xFFFFF5E1), // Antique white
    // Cool whites
    Color(0xFFF0F8FF), // Alice blue
    Color(0xFFF5F5F5), // White smoke
    Color(0xFFFFFFFF), // Pure white
    // Colors
    Color(0xFFFF0000), // Red
    Color(0xFF00FF00), // Green
    Color(0xFF0000FF), // Blue
    Color(0xFFFFFF00), // Yellow
    Color(0xFFFF00FF), // Magenta
    Color(0xFF00FFFF), // Cyan
    Color(0xFFFF8800), // Orange
    Color(0xFF8800FF), // Purple
    Color(0xFFFFD700), // Gold
  ];

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: const Text('Select Color', style: TextStyle(color: Colors.white)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Current color preview
          Container(
            width: double.infinity,
            height: 48,
            decoration: BoxDecoration(
              color: _selectedColor,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white24),
            ),
          ),
          const SizedBox(height: 16),

          // Color grid
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: _presetColors.map((color) {
              final isSelected = _selectedColor.value == color.value;
              return GestureDetector(
                onTap: () => setState(() => _selectedColor = color),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: color,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? Colors.white : Colors.white24,
                      width: isSelected ? 3 : 1,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: color.withValues(alpha: 0.4),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _selectedColor),
          child: const Text('Select'),
        ),
      ],
    );
  }
}
