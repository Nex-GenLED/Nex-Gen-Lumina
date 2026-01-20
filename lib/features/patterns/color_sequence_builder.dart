import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

/// A compact, horizontal color sequence builder for WLED custom palettes.
///
/// Users can:
/// - Tap a color slot to change it (picker only shows the provided base colors)
/// - Long-press a slot to delete it
/// - Tap the + button to append a new slot (defaults to first base color)
///
/// Emits the sequence as a list of RGB arrays (e.g., [255, 0, 0]).
class ColorSequenceBuilder extends StatefulWidget {
  /// Available team/base colors to pick from, as RGB arrays.
  final List<List<int>> baseColors;

  /// Optional initial sequence. Falls back to [baseColors] when not provided or empty.
  final List<List<int>>? initialSequence;

  /// Called every time the sequence changes.
  final ValueChanged<List<List<int>>> onChanged;

  const ColorSequenceBuilder({super.key, required this.baseColors, this.initialSequence, required this.onChanged});

  @override
  State<ColorSequenceBuilder> createState() => _ColorSequenceBuilderState();
}

class _ColorSequenceBuilderState extends State<ColorSequenceBuilder> {
  late List<List<int>> _sequence;

  @override
  void initState() {
    super.initState();
    final init = (widget.initialSequence ?? widget.baseColors).where(_isRgbTriplet).map((e) => [e[0], e[1], e[2]]).toList(growable: true);
    _sequence = init.isNotEmpty ? init : (widget.baseColors.isNotEmpty ? [widget.baseColors.first] : <List<int>>[]);
  }

  bool _isRgbTriplet(List<int> rgb) => rgb.length >= 3;

  Color _toColor(List<int> rgb) => Color.fromARGB(255, rgb[0].clamp(0, 255), rgb[1].clamp(0, 255), rgb[2].clamp(0, 255));

  void _append() {
    if (widget.baseColors.isEmpty) return;
    setState(() => _sequence.add([widget.baseColors.first[0], widget.baseColors.first[1], widget.baseColors.first[2]]));
    widget.onChanged(_sequence);
  }

  Future<void> _pickForIndex(int index) async {
    if (widget.baseColors.isEmpty) return;
    final selected = await showModalBottomSheet<List<int>>(
      context: context,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.palette, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Choose Color', style: Theme.of(ctx).textTheme.titleMedium),
              ]),
              const SizedBox(height: 12),
              Wrap(spacing: 12, runSpacing: 12, children: [
                for (final rgb in widget.baseColors)
                  _PickerDot(
                    color: _toColor(rgb),
                    onTap: () => Navigator.of(ctx).pop([rgb[0], rgb[1], rgb[2]]),
                  ),
              ]),
              const SizedBox(height: 16),
            ]),
          ),
        );
      },
    );

    if (selected != null && selected.length >= 3) {
      setState(() => _sequence[index] = [selected[0], selected[1], selected[2]]);
      widget.onChanged(_sequence);
    }
  }

  void _removeAt(int index) {
    setState(() {
      if (_sequence.length > 1) {
        _sequence.removeAt(index);
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
          // Add new slot button
          _AddSlotButton(onTap: _append),
        ]),
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

class _PickerDot extends StatelessWidget {
  final Color color;
  final VoidCallback onTap;
  const _PickerDot({required this.color, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(shape: BoxShape.circle, color: color, border: Border.all(color: NexGenPalette.line)),
      ),
    );
  }
}
