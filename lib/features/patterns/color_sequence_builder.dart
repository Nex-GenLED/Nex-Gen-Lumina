import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';
import 'package:nexgen_command/theme.dart';

/// A compact, horizontal color sequence builder for WLED custom palettes.
///
/// Users can:
/// - Tap a color slot to open a full color picker (color wheel + brightness)
/// - Long-press a slot to delete it
/// - Tap the + button to add a new color via color picker
///
/// Emits the sequence as a list of RGB arrays (e.g., [255, 0, 0]).
/// When colors are modified from the original, onCustomized is called.
class ColorSequenceBuilder extends StatefulWidget {
  /// Available team/base colors to pick from, as RGB arrays.
  final List<List<int>> baseColors;

  /// Optional initial sequence. Falls back to [baseColors] when not provided or empty.
  final List<List<int>>? initialSequence;

  /// Called every time the sequence changes.
  final ValueChanged<List<List<int>>> onChanged;

  /// Called when colors are modified from the original pattern.
  /// This allows the parent to know to display "Custom" instead of the original pattern name.
  final VoidCallback? onCustomized;

  const ColorSequenceBuilder({
    super.key,
    required this.baseColors,
    this.initialSequence,
    required this.onChanged,
    this.onCustomized,
  });

  @override
  State<ColorSequenceBuilder> createState() => _ColorSequenceBuilderState();
}

class _ColorSequenceBuilderState extends State<ColorSequenceBuilder> {
  late List<List<int>> _sequence;
  bool _hasBeenCustomized = false;

  @override
  void initState() {
    super.initState();
    final init = (widget.initialSequence ?? widget.baseColors).where(_isRgbTriplet).map((e) => [e[0], e[1], e[2]]).toList(growable: true);
    _sequence = init.isNotEmpty ? init : (widget.baseColors.isNotEmpty ? [widget.baseColors.first] : <List<int>>[]);
  }

  bool _isRgbTriplet(List<int> rgb) => rgb.length >= 3;

  Color _toColor(List<int> rgb) => Color.fromARGB(255, rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255));

  void _markAsCustomized() {
    if (!_hasBeenCustomized) {
      _hasBeenCustomized = true;
      widget.onCustomized?.call();
    }
  }

  /// Converts a Color to RGB int array
  List<int> _colorToRgb(Color c) => [
    (c.r * 255.0).round().clamp(0, 255),
    (c.g * 255.0).round().clamp(0, 255),
    (c.b * 255.0).round().clamp(0, 255),
  ];

  /// Opens color picker to add a new color slot
  Future<void> _addNewColor() async {
    // Start with a default color (white if nothing else)
    final defaultColor = widget.baseColors.isNotEmpty
        ? _toColor(widget.baseColors.first)
        : Colors.white;

    final selected = await _showColorPickerDialog(defaultColor);
    if (selected != null) {
      setState(() => _sequence.add(_colorToRgb(selected)));
      _markAsCustomized();
      widget.onChanged(_sequence);
    }
  }

  /// Opens color picker to change an existing color slot
  Future<void> _pickForIndex(int index) async {
    final currentColor = _toColor(_sequence[index]);
    final selected = await _showColorPickerDialog(currentColor);

    if (selected != null) {
      setState(() => _sequence[index] = _colorToRgb(selected));
      _markAsCustomized();
      widget.onChanged(_sequence);
    }
  }

  /// Shows the color picker dialog with color wheel and brightness slider
  Future<Color?> _showColorPickerDialog(Color initialColor) async {
    return showModalBottomSheet<Color>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => _ColorPickerSheet(initialColor: initialColor),
    );
  }

  void _removeAt(int index) {
    setState(() {
      if (_sequence.length > 1) {
        _sequence.removeAt(index);
        _markAsCustomized();
      } else {
        // Keep at least one slot to avoid empty palette; reset to first base color if possible
        if (widget.baseColors.isNotEmpty) {
          _sequence[0] = [widget.baseColors.first[0], widget.baseColors.first[1], widget.baseColors.first[2]];
        }
      }
    });
    widget.onChanged(_sequence);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          // Existing slots
          for (int i = 0; i < _sequence.length; i++) ...[
            _SequenceSlot(
              color: _toColor(_sequence[i]),
              index: i,
              onTap: () => _pickForIndex(i),
              onLongPress: () => _removeAt(i),
            ),
            const SizedBox(width: 10),
          ],
          // Add new slot button - opens color picker
          _AddSlotButton(onTap: _addNewColor),
        ]),
      ),
    );
  }
}

/// Color picker bottom sheet with color wheel and brightness slider
class _ColorPickerSheet extends StatefulWidget {
  final Color initialColor;

  const _ColorPickerSheet({required this.initialColor});

  @override
  State<_ColorPickerSheet> createState() => _ColorPickerSheetState();
}

class _ColorPickerSheetState extends State<_ColorPickerSheet> {
  late Color _currentColor;
  late double _brightness;

  @override
  void initState() {
    super.initState();
    _currentColor = widget.initialColor;
    final hsv = HSVColor.fromColor(widget.initialColor);
    _brightness = hsv.value;
  }

  void _updateColorFromWheel(Color color) {
    // The wheel returns colors at V=1, apply our brightness
    final hsv = HSVColor.fromColor(color);
    setState(() {
      _currentColor = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, _brightness).toColor();
    });
  }

  void _updateBrightness(double value) {
    final hsv = HSVColor.fromColor(_currentColor);
    setState(() {
      _brightness = value;
      _currentColor = HSVColor.fromAHSV(1, hsv.hue, hsv.saturation, value).toColor();
    });
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Handle bar
            Container(
              width: 42,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(999),
              ),
            ),
            const SizedBox(height: 16),
            // Header
            Row(
              children: [
                const Icon(Icons.palette, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Choose Color', style: Theme.of(context).textTheme.titleLarge),
                const Spacer(),
                // Color preview
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _currentColor,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.3)),
                    boxShadow: [
                      BoxShadow(
                        color: _currentColor.withValues(alpha: 0.4),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            // Color wheel
            Center(
              child: NeonColorWheel(
                size: 220,
                color: HSVColor.fromColor(_currentColor).withValue(1).toColor(),
                onChanged: _updateColorFromWheel,
              ),
            ),
            const SizedBox(height: 24),
            // Brightness slider
            Row(
              children: [
                const Icon(Icons.brightness_6, color: Colors.white70, size: 20),
                const SizedBox(width: 12),
                Expanded(
                  child: Container(
                    height: 32,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          Colors.black,
                          HSVColor.fromColor(_currentColor).withValue(1).toColor(),
                        ],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                    ),
                    child: SliderTheme(
                      data: SliderThemeData(
                        trackHeight: 32,
                        activeTrackColor: Colors.transparent,
                        inactiveTrackColor: Colors.transparent,
                        thumbColor: Colors.white,
                        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 12),
                        overlayShape: SliderComponentShape.noOverlay,
                      ),
                      child: Slider(
                        value: _brightness,
                        min: 0,
                        max: 1,
                        onChanged: _updateBrightness,
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Brightness: ${(_brightness * 100).round()}%',
              style: Theme.of(context).textTheme.labelMedium?.copyWith(color: Colors.white70),
            ),
            const SizedBox(height: 24),
            // Action buttons
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.white70,
                      side: BorderSide(color: Colors.white.withValues(alpha: 0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _currentColor),
                    style: FilledButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      foregroundColor: Colors.black,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    child: const Text('Select'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SequenceSlot extends StatelessWidget {
  final Color color;
  final int index;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  const _SequenceSlot({required this.color, required this.index, required this.onTap, required this.onLongPress});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: NexGenPalette.line, width: 2)),
        ),
        const SizedBox(height: 6),
        Text('${index + 1}', style: Theme.of(context).textTheme.labelSmall),
      ]),
    );
  }
}

class _AddSlotButton extends StatelessWidget {
  final VoidCallback onTap;
  const _AddSlotButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: cs.surface.withValues(alpha: 0.4),
          border: Border.all(color: NexGenPalette.cyan, width: 1.5),
        ),
        child: const Icon(Icons.add, color: NexGenPalette.cyan, size: 22),
      ),
    );
  }
}

