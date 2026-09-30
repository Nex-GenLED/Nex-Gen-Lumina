import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

// The Design Studio's dialogs as widgets of their own (+110 E2), so the
// accessibility harness can open and measure them the way the app does. The
// editor and the detail screen used to build them inline.

/// "Name This Design" — a new painted design's name. Resolves to the name, or
/// null when cancelled.
Future<String?> showNameDesignDialog(
  BuildContext context, {
  required String initialName,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => NameDesignDialog(initialName: initialName),
    );

class NameDesignDialog extends StatefulWidget {
  const NameDesignDialog({super.key, required this.initialName});

  final String initialName;

  @override
  State<NameDesignDialog> createState() => _NameDesignDialogState();
}

class _NameDesignDialogState extends State<NameDesignDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Name This Design'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Save')),
      ],
    );
  }
}

/// "Rename Design". Resolves to the new name, or null when cancelled.
Future<String?> showRenameDesignDialog(
  BuildContext context, {
  required String currentName,
}) =>
    showDialog<String>(
      context: context,
      builder: (_) => RenameDesignDialog(currentName: currentName),
    );

class RenameDesignDialog extends StatefulWidget {
  const RenameDesignDialog({super.key, required this.currentName});

  final String currentName;

  @override
  State<RenameDesignDialog> createState() => _RenameDesignDialogState();
}

class _RenameDesignDialogState extends State<RenameDesignDialog> {
  late final TextEditingController _controller =
      TextEditingController(text: widget.currentName);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      scrollable: true,
      title: const Text('Rename Design'),
      content: TextField(
        controller: _controller,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Name'),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel')),
        FilledButton(
            onPressed: () => Navigator.of(context).pop(_controller.text),
            child: const Text('Save')),
      ],
    );
  }
}

/// What the customer chose in the "On / off pattern" dialog.
enum OnOffPatternAction { select, paint }

/// The dialog's outcome: the action (null when cancelled) and the numbers as
/// they were left, so the next open resumes from them.
class OnOffPatternResult {
  const OnOffPatternResult({
    required this.action,
    required this.start,
    required this.end,
    required this.on,
    required this.off,
  });

  final OnOffPatternAction? action;
  final int start;
  final int end;
  final int on;
  final int off;
}

/// The "N on, M off" pattern tool (was "Every-Nth").
Future<OnOffPatternResult> showOnOffPatternDialog(
  BuildContext context, {
  required int length,
  required int start,
  required int end,
  required int on,
  required int off,
}) async {
  final state = _OnOffValues(start: start, end: end, on: on, off: off);
  final action = await showDialog<OnOffPatternAction>(
    context: context,
    builder: (_) => OnOffPatternDialog(length: length, values: state),
  );
  return OnOffPatternResult(
    action: action,
    start: state.start,
    end: state.end,
    on: state.on,
    off: state.off,
  );
}

/// Mutable numbers shared between the dialog and its caller, so a cancelled
/// dialog still hands back where the sliders were left.
class _OnOffValues {
  _OnOffValues(
      {required this.start, required this.end, required this.on, required this.off});
  int start;
  int end;
  int on;
  int off;
}

/// The pattern dialog body. Every-Nth only ever ADDED to the selection, and
/// Paint only ever ADDS pixels, so re-running it to widen a pattern produced
/// the UNION of old and new (followup N3a). "Paint pattern" writes BOTH halves
/// in one undoable step; "Select" replaces the selection inside the range.
class OnOffPatternDialog extends StatefulWidget {
  const OnOffPatternDialog({
    super.key,
    required this.length,
    required _OnOffValues values,
  }) : _values = values;

  /// For the harness and for callers outside the editor: a dialog with its
  /// own numbers.
  factory OnOffPatternDialog.standalone({
    Key? key,
    required int length,
    int start = 0,
    int? end,
    int on = 1,
    int off = 2,
  }) =>
      OnOffPatternDialog(
        key: key,
        length: length,
        values: _OnOffValues(
            start: start, end: end ?? (length - 1), on: on, off: off),
      );

  final int length;
  final _OnOffValues _values;

  @override
  State<OnOffPatternDialog> createState() => _OnOffPatternDialogState();
}

class _OnOffPatternDialogState extends State<OnOffPatternDialog> {
  _OnOffValues get v => widget._values;

  ({List<int> lit, List<int> dark}) _pattern() {
    final lit = <int>[], dark = <int>[];
    if (v.end < v.start) return (lit: lit, dark: dark);
    final n = v.on < 1 ? 1 : v.on;
    final m = v.off < 0 ? 0 : v.off;
    final cycle = n + m;
    for (int i = v.start; i <= v.end; i++) {
      ((i - v.start) % cycle < n ? lit : dark).add(i);
    }
    return (lit: lit, dark: dark);
  }

  @override
  Widget build(BuildContext context) {
    final len = widget.length;
    final pattern = _pattern();
    final lit = pattern.lit.length;
    final span = v.end - v.start + 1;
    // The one way this tool yields a single LED: a range shorter than one
    // repeat (e.g. End left at 6 with 1 on / 6 off).
    final degenerate = v.end >= v.start && lit <= 1 && len > v.on + v.off;
    return AlertDialog(
      scrollable: true,
      backgroundColor: NexGenPalette.gunmetal90,
      title: const Text('On / off pattern', style: TextStyle(color: Colors.white)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        _NumRow('Lit', v.on, 1, 10, (x) => setState(() => v.on = x)),
        _NumRow('Dark', v.off, 0, 20, (x) => setState(() => v.off = x)),
        _NumRow('From LED', v.start, 0, len - 1, (x) => setState(() => v.start = x)),
        _NumRow('To LED', v.end, 0, len - 1, (x) => setState(() => v.end = x)),
        const SizedBox(height: 8),
        Text(
          v.end < v.start
              ? '"To LED" is before "From LED" — nothing will be lit.'
              : '${v.on} on, ${v.off} off across LEDs ${v.start}–${v.end} '
                  '($span LEDs) → $lit lit.',
          key: const ValueKey('pattern-summary'),
          style: TextStyle(
              color: v.end < v.start ? Colors.orangeAccent : NexGenPalette.textMedium,
              fontSize: 12),
        ),
        if (degenerate)
          const Padding(
            padding: EdgeInsets.only(top: 6),
            child: Text(
              'Only one LED — the range is shorter than one repeat of the '
              'pattern. Raise "To LED" to cover more of the channel.',
              style: TextStyle(color: Colors.orangeAccent, fontSize: 12),
            ),
          ),
      ]),
      actionsOverflowButtonSpacing: 4,
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        TextButton(
            onPressed: () => Navigator.pop(context, OnOffPatternAction.select),
            child: const Text('Select')),
        FilledButton(
            onPressed: () => Navigator.pop(context, OnOffPatternAction.paint),
            child: const Text('Paint pattern')),
      ],
    );
  }
}

class _NumRow extends StatelessWidget {
  const _NumRow(this.label, this.value, this.min, this.max, this.onChanged);
  final String label;
  final int value;
  final int min;
  final int max;
  final ValueChanged<int> onChanged;

  @override
  Widget build(BuildContext context) {
    // Label above the slider row: at large text a fixed 72-point label cell
    // cut "From LED" short.
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(label, style: const TextStyle(color: NexGenPalette.textMedium)),
      Row(children: [
        Expanded(
          child: Slider(
            value: value.toDouble().clamp(min.toDouble(), max.toDouble()),
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: (max - min).clamp(1, 1000),
            label: '$value',
            onChanged: (x) => onChanged(x.round()),
          ),
        ),
        // − / + so an exact number is reachable: on a 162-LED channel one
        // slider division is about 2 px of finger travel.
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.remove, size: 16, color: Colors.white70),
          onPressed: value > min ? () => onChanged(value - 1) : null,
        ),
        ConstrainedBox(
          constraints: const BoxConstraints(minWidth: 30),
          child: Text('$value',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white)),
        ),
        IconButton(
          visualDensity: VisualDensity.compact,
          icon: const Icon(Icons.add, size: 16, color: Colors.white70),
          onPressed: value < max ? () => onChanged(value + 1) : null,
        ),
      ]),
    ]);
  }
}
