import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Color palette picker for the Design Studio.
/// Shows recent colors, preset palettes, and a custom color picker.
class ColorPalettePicker extends ConsumerStatefulWidget {
  const ColorPalettePicker({super.key});

  @override
  ConsumerState<ColorPalettePicker> createState() => _ColorPalettePickerState();
}

class _ColorPalettePickerState extends ConsumerState<ColorPalettePicker> {
  String? _expandedPalette;

  @override
  Widget build(BuildContext context) {
    final selectedColor = ref.watch(selectedColorProvider);
    final recentColors = ref.watch(recentColorsProvider);
    final palettes = ref.watch(colorPalettesProvider);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white.withOpacity(0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header with current color preview
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  decoration: BoxDecoration(
                    color: selectedColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withOpacity(0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: selectedColor.withOpacity(0.4),
                        blurRadius: 8,
                        spreadRadius: 1,
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Paint Color',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        '#${selectedColor.value.toRadixString(16).substring(2).toUpperCase()}',
                        style: const TextStyle(
                          color: Colors.white54,
                          fontSize: 12,
                          fontFamily: 'monospace',
                        ),
                      ),
                    ],
                  ),
                ),
                // Custom color button
                IconButton(
                  onPressed: () => _showColorPicker(context),
                  icon: const Icon(Icons.colorize, color: NexGenPalette.cyan),
                  tooltip: 'Custom Color',
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Recent colors
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Recent',
                  style: TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (final color in recentColors)
                      _ColorSwatch(
                        color: color,
                        isSelected: color.value == selectedColor.value,
                        onTap: () => ref.read(selectedColorProvider.notifier).state = color,
                      ),
                  ],
                ),
              ],
            ),
          ),
          const Divider(height: 1, color: Colors.white12),

          // Preset palettes
          ...palettes.entries.map((entry) => _PaletteSection(
            name: entry.key,
            colors: entry.value,
            isExpanded: _expandedPalette == entry.key,
            selectedColor: selectedColor,
            onToggle: () {
              setState(() {
                _expandedPalette = _expandedPalette == entry.key ? null : entry.key;
              });
            },
            onColorSelect: (color) {
              ref.read(selectedColorProvider.notifier).state = color;
              ref.read(recentColorsProvider.notifier).addColor(color);
            },
          )),
        ],
      ),
    );
  }

  Future<void> _showColorPicker(BuildContext context) async {
    final currentColor = ref.read(selectedColorProvider);
    final result = await showDialog<Color>(
      context: context,
      builder: (ctx) => _CustomColorDialog(initialColor: currentColor),
    );
    if (result != null) {
      ref.read(selectedColorProvider.notifier).state = result;
      ref.read(recentColorsProvider.notifier).addColor(result);
    }
  }
}

class _ColorSwatch extends StatelessWidget {
  final Color color;
  final bool isSelected;
  final VoidCallback onTap;

  const _ColorSwatch({
    required this.color,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 32,
        height: 32,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: isSelected ? Colors.white : Colors.white.withOpacity(0.2),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: [
            if (isSelected)
              BoxShadow(
                color: color.withOpacity(0.5),
                blurRadius: 8,
                spreadRadius: 1,
              ),
          ],
        ),
      ),
    );
  }
}

class _PaletteSection extends StatelessWidget {
  final String name;
  final List<Color> colors;
  final bool isExpanded;
  final Color selectedColor;
  final VoidCallback onToggle;
  final void Function(Color) onColorSelect;

  const _PaletteSection({
    required this.name,
    required this.colors,
    required this.isExpanded,
    required this.selectedColor,
    required this.onToggle,
    required this.onColorSelect,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onToggle,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Mini color preview
                ...colors.take(4).map((c) => Container(
                  width: 12,
                  height: 12,
                  margin: const EdgeInsets.only(right: 2),
                  decoration: BoxDecoration(
                    color: c,
                    borderRadius: BorderRadius.circular(2),
                  ),
                )),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    name,
                    style: const TextStyle(color: Colors.white70),
                  ),
                ),
                Icon(
                  isExpanded ? Icons.expand_less : Icons.expand_more,
                  color: Colors.white54,
                  size: 20,
                ),
              ],
            ),
          ),
        ),
        if (isExpanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final color in colors)
                  _ColorSwatch(
                    color: color,
                    isSelected: color.value == selectedColor.value,
                    onTap: () => onColorSelect(color),
                  ),
              ],
            ),
          ),
        const Divider(height: 1, color: Colors.white12),
      ],
    );
  }
}

class _CustomColorDialog extends StatefulWidget {
  final Color initialColor;

  const _CustomColorDialog({required this.initialColor});

  @override
  State<_CustomColorDialog> createState() => _CustomColorDialogState();
}

class _CustomColorDialogState extends State<_CustomColorDialog> {
  late double _hue;
  late double _saturation;
  late double _value;

  @override
  void initState() {
    super.initState();
    final hsv = HSVColor.fromColor(widget.initialColor);
    _hue = hsv.hue;
    _saturation = hsv.saturation;
    _value = hsv.value;
  }

  Color get _currentColor => HSVColor.fromAHSV(1, _hue, _saturation, _value).toColor();

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: const Text('Custom Color', style: TextStyle(color: Colors.white)),
      content: SizedBox(
        width: 280,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Color preview
            Container(
              height: 60,
              width: double.infinity,
              decoration: BoxDecoration(
                color: _currentColor,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: _currentColor.withOpacity(0.4),
                    blurRadius: 12,
                    spreadRadius: 2,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // Hue slider
            _ColorSlider(
              label: 'Hue',
              value: _hue,
              max: 360,
              gradient: LinearGradient(
                colors: List.generate(7, (i) =>
                  HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor(),
                ),
              ),
              onChanged: (v) => setState(() => _hue = v),
            ),
            const SizedBox(height: 16),

            // Saturation slider
            _ColorSlider(
              label: 'Saturation',
              value: _saturation,
              max: 1,
              gradient: LinearGradient(
                colors: [
                  HSVColor.fromAHSV(1, _hue, 0, _value).toColor(),
                  HSVColor.fromAHSV(1, _hue, 1, _value).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _saturation = v),
            ),
            const SizedBox(height: 16),

            // Brightness/Value slider
            _ColorSlider(
              label: 'Brightness',
              value: _value,
              max: 1,
              gradient: LinearGradient(
                colors: [
                  Colors.black,
                  HSVColor.fromAHSV(1, _hue, _saturation, 1).toColor(),
                ],
              ),
              onChanged: (v) => setState(() => _value = v),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _currentColor),
          child: const Text('Select'),
        ),
      ],
    );
  }
}

class _ColorSlider extends StatelessWidget {
  final String label;
  final double value;
  final double max;
  final Gradient gradient;
  final ValueChanged<double> onChanged;

  const _ColorSlider({
    required this.label,
    required this.value,
    required this.max,
    required this.gradient,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
        const SizedBox(height: 4),
        Container(
          height: 24,
          decoration: BoxDecoration(
            gradient: gradient,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withOpacity(0.2)),
          ),
          child: SliderTheme(
            data: SliderThemeData(
              trackHeight: 24,
              activeTrackColor: Colors.transparent,
              inactiveTrackColor: Colors.transparent,
              thumbColor: Colors.white,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 10),
              overlayShape: SliderComponentShape.noOverlay,
            ),
            child: Slider(
              value: value,
              min: 0,
              max: max,
              onChanged: onChanged,
            ),
          ),
        ),
      ],
    );
  }
}
