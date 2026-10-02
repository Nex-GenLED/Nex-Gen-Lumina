import 'package:flutter/material.dart';
import 'package:nexgen_command/theme.dart';

// The walkthrough's section and mark controls (+113), kept free of providers
// so the accessibility text-scale harness can lay them out on their own.

/// One compiled section of a channel, with "merge into neighbour" as its
/// delete. When the section cannot be merged away, the button is disabled and
/// [blocker] says why, in the row itself — a grey button with no reason was
/// the tester's report.
class RooflineSectionRow extends StatelessWidget {
  const RooflineSectionRow({
    super.key,
    required this.label,
    required this.lights,
    required this.onMerge,
    this.blocker,
    this.onTap,
  });

  /// "Corner", "Run 2", "Peak section"…
  final String label;

  /// "light 43" or "lights 1–42" (1-indexed for display only).
  final String lights;

  /// Removes the section by merging its lights into the neighbour. Null
  /// disables the control; give [blocker] then.
  final VoidCallback? onMerge;

  /// Why the section cannot be merged away. Shown when [onMerge] is null.
  final String? blocker;

  /// Moves the cursor to the section's first light.
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onMerge == null;
    return Material(
      type: MaterialType.transparency,
      child: ListTile(
        contentPadding: EdgeInsets.zero,
        dense: true,
        onTap: onTap,
        title: Text('$label · $lights',
            style: const TextStyle(color: Colors.white)),
        subtitle: disabled && blocker != null
            ? Text(blocker!,
                style: const TextStyle(color: NexGenPalette.textMedium))
            : null,
        trailing: Semantics(
          button: true,
          enabled: !disabled,
          hint: disabled ? blocker : 'Merge into the neighbouring section',
          child: IconButton(
            tooltip: disabled
                ? (blocker ?? 'Cannot merge this section')
                : 'Merge into neighbour',
            icon: const Icon(Icons.call_merge),
            onPressed: onMerge,
          ),
        ),
      ),
    );
  }
}

/// "Undo last mark" and "Start over" for the channel being marked. When both
/// are disabled, one line says why instead of two grey buttons.
class WalkthroughMarkActions extends StatelessWidget {
  const WalkthroughMarkActions({
    super.key,
    required this.onUndo,
    required this.onStartOver,
    this.disabledReason,
  });

  final VoidCallback? onUndo;
  final VoidCallback? onStartOver;

  /// Shown when both actions are disabled.
  final String? disabledReason;

  @override
  Widget build(BuildContext context) {
    final bothOff = onUndo == null && onStartOver == null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('walkthrough-undo-mark'),
              onPressed: onUndo,
              icon: const Icon(Icons.undo),
              label: const Text('Undo last mark'),
            ),
            TextButton.icon(
              key: const ValueKey('walkthrough-start-over'),
              onPressed: onStartOver,
              icon: const Icon(Icons.restart_alt),
              label: const Text('Start over on this channel'),
            ),
          ],
        ),
        if (bothOff && disabledReason != null)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(disabledReason!,
                style: const TextStyle(color: NexGenPalette.textMedium)),
          ),
      ],
    );
  }
}

/// The map's light count for a channel disagrees with the strip.
class ChannelLengthNotice extends StatelessWidget {
  const ChannelLengthNotice({
    super.key,
    required this.channelNumber,
    required this.mapped,
    required this.strip,
  });

  /// 1-indexed, as the customer sees it.
  final int channelNumber;
  final int mapped;
  final int strip;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 6),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withValues(alpha: 0.4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, color: Colors.amber, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'Your map says channel $channelNumber has $mapped lights, but '
              'the strip has $strip. Marking uses the strip. Saving this '
              'channel updates the map to match.',
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }
}

/// What "Start over" will remove, as the confirmation's body.
String startOverDescription({
  required int channelNumber,
  required int lights,
  required ({int corners, int peaks, int splits, int other}) marks,
}) {
  final parts = <String>[];
  void add(int n, String one, String many) {
    if (n > 0) parts.add('$n ${n == 1 ? one : many}');
  }

  add(marks.corners, 'corner', 'corners');
  add(marks.peaks, 'peak', 'peaks');
  add(marks.splits, 'run split', 'run splits');
  add(marks.other, 'other feature', 'other features');
  final removed = parts.isEmpty ? 'every mark' : parts.join(', ');
  return 'This removes $removed on channel $channelNumber. The channel '
      'becomes one straight run of $lights lights. Nothing is saved until you '
      'tap Save.';
}
