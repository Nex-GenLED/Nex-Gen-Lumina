// lib/features/schedule/widgets/ladder_repair_banner.dart
//
// +114 item 1d — says what the on-connect ladder repair DID.
//
// A repair writes to the customer's controller without them asking, and the
// psaves flash the house for a moment before the restore puts the look back.
// They are owed a sentence. This banner shows the last repair that wrote, in
// plain words, until it is dismissed; it shows nothing otherwise (deferred,
// dry-run and not-needed considerations are not news to a customer).
//
// WORDS. Presets are named by what they do — On, Dim, Low, Medium, Off — never
// by slot number.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair.dart';
import 'package:nexgen_command/features/wled/base_ladder_repair_providers.dart';
import 'package:nexgen_command/features/wled/base_ladder_restore.dart';
import 'package:nexgen_command/features/wled/base_look.dart';

/// What each ladder slot is called on screen.
String ladderSlotLabel(int presetId) => switch (presetId) {
      1 => 'On',
      2 => 'Off',
      3 => 'Dim',
      4 => 'Low',
      5 => 'Medium',
      _ => 'preset $presetId',
    };

String _joinLabels(List<int> ids) {
  final names = [for (final id in ids) ladderSlotLabel(id)];
  if (names.length <= 1) return names.join();
  return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
}

String _what(List<int> ids) {
  final on = [for (final id in ids) if (id != kLadderOffPresetId) id];
  final off = ids.contains(kLadderOffPresetId);
  return [
    if (on.isNotEmpty)
      'Your ${_joinLabels(on)} setting${on.length == 1 ? '' : 's'} would have '
          'turned your lights on with nothing showing.',
    if (off) 'Your Off setting would have left some lights on.',
  ].join(' ');
}

/// PURE. The banner's title and lines for one status.
({String title, List<String> lines}) ladderRepairCopy(LadderRepairStatus s) {
  // #183 — a repair the customer asked for is reported as what it was, not as
  // a surprise: the "would have turned your lights on with nothing showing"
  // story belongs to the captured-black defect, not to a bus that was added.
  if (s.userInitiated && s.outcome == LadderRepairOutcome.repaired) {
    return (
      title: 'Your everyday lighting was repaired',
      lines: const [
        'Your On, Off, Dim, Low and Medium settings now cover every channel on '
            'your controller. We kept a copy of the old settings.',
      ],
    );
  }
  switch (s.outcome) {
    case LadderRepairOutcome.repaired:
      return (
        title: 'We fixed your everyday lighting',
        lines: [
          _what(s.repairedIds),
          [
            if (s.repairedIds.any((id) => id != kLadderOffPresetId))
              'They now light every channel in $kBaseLookName.',
            if (s.repairedIds.contains(kLadderOffPresetId))
              'Off now turns every channel off.',
            'We kept a copy of the old settings. You will see the change the '
                'next time your schedule turns your lights on.',
          ].join(' '),
        ],
      );
    case LadderRepairOutcome.partial:
      return (
        title: 'We fixed part of your everyday lighting',
        lines: [
          'Fixed: ${_joinLabels(s.repairedIds)}. Not fixed: '
              '${_joinLabels(s.stillBadIds)} — the controller did not save it.',
          'If your lights come on with nothing showing, contact support. We '
              'kept a copy of the old settings.',
        ],
      );
    default:
      return (
        title: 'We could not fix your everyday lighting',
        lines: [
          _what(s.stillBadIds),
          'Saving the fix did not work, so nothing was changed. Contact support '
              'if your lights come on with nothing showing.',
        ],
      );
  }
}

/// The last repair that wrote, until dismissed. Renders nothing otherwise.
class LadderRepairBanner extends ConsumerWidget {
  const LadderRepairBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(ladderRepairStatusProvider);
    if (status == null) return const SizedBox.shrink();
    final copy = ladderRepairCopy(status);
    final ok = status.outcome == LadderRepairOutcome.repaired;
    final tint = ok ? NexGenPalette.cyan : Colors.orange.shade400;

    return Semantics(
      container: true,
      liveRegion: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  ok ? Icons.build_circle_outlined : Icons.warning_amber_rounded,
                  size: 18,
                  color: tint,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy.title,
                    style: TextStyle(
                      color: tint,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            for (final l in copy.lines)
              if (l.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  l,
                  style: const TextStyle(
                    color: NexGenPalette.textMedium,
                    fontSize: 13,
                    height: 1.35,
                  ),
                ),
              ],
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton(
                onPressed: () =>
                    ref.read(ladderRepairStatusProvider.notifier).dismiss(),
                style: TextButton.styleFrom(foregroundColor: tint),
                child: const Text('Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
