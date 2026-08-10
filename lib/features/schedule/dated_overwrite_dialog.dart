// A3 — interim overwrite guard. audit/MULTI_ENTRY_DISPLAY.md §2.
//
// `calendar_entries` holds ONE entry per date (Map keyed by 'YYYY-MM-DD'), so
// saving a second entry for a date destroys the first. This prompt makes that
// deliberate instead of silent.
//
// WHY A DIALOG AND NOT presetErrors: presetErrors is a POST-hoc report rendered
// after a sync has already run. This is a PRE-write decision about a
// destructive action — the customer has to answer before anything is lost. A
// warning that arrives after the entry is gone is the wrong shape, and telling
// someone what you just destroyed is not a choice.
//
// WHY THERE IS NO "KEEP BOTH": storage cannot represent two entries for one
// date (A1 is unbuilt). ScheduleConflictInfo's ConflictResolution has a
// `keepBoth` option and is deliberately NOT reused here — offering it would
// promise something the write cannot deliver. Replace or cancel are the only
// honest options, so they are the only ones offered.

import 'package:flutter/material.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/app_colors.dart';

/// The only two outcomes storage can honour today.
enum DatedOverwriteChoice { replace, cancel }

String _prettyDate(String dateKey) {
  try {
    final d = DateTime.parse(dateKey);
    const months = [
      '', 'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
    ];
    return '${months[d.month]} ${d.day}';
  } catch (_) {
    return dateKey;
  }
}

String _describe(String? name, String? onTime) {
  final n = (name == null || name.trim().isEmpty) ? 'Untitled' : name.trim();
  return (onTime == null || onTime.isEmpty) ? n : '$n · $onTime';
}

/// Ask before replacing user-authored dated entries.
///
/// Returns [DatedOverwriteChoice.cancel] if dismissed by tapping outside or
/// back — the safe default for a destructive action.
Future<DatedOverwriteChoice> showDatedOverwriteDialog(
  BuildContext context,
  List<DatedOverwrite> overwrites,
) async {
  final multiple = overwrites.length > 1;
  final result = await showDialog<DatedOverwriteChoice>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: NexGenPalette.gunmetal,
      title: Text(
        multiple
            ? 'Replace ${overwrites.length} saved days?'
            : 'Replace what\'s saved on ${_prettyDate(overwrites.first.dateKey)}?',
        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            multiple
                ? 'These days already have something saved. Saving replaces them.'
                : 'This day already has something saved. Saving replaces it.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          const SizedBox(height: 14),
          // Name what is being lost. "This date has an entry" is not a decision
          // anyone can make; "Deep Blue · 18:00" is.
          ...overwrites.take(4).map((o) => Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      margin: const EdgeInsets.only(top: 4, right: 10),
                      decoration: BoxDecoration(
                        color: o.existing.color,
                        shape: BoxShape.circle,
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (multiple)
                            Text(_prettyDate(o.dateKey),
                                style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600)),
                          Text(
                            _describe(
                                o.existing.patternName, o.existing.onTime),
                            style: const TextStyle(
                                fontSize: 13, color: Colors.white70),
                          ),
                          Text(
                            'replaced by  ${_describe(o.incoming.patternName, o.incoming.onTime)}',
                            style: const TextStyle(
                                fontSize: 12, color: Colors.white38),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          if (overwrites.length > 4)
            Text('and ${overwrites.length - 4} more',
                style:
                    const TextStyle(fontSize: 12, color: Colors.white38)),
          const SizedBox(height: 6),
          // Do not imply both are kept — they are not, and cannot be.
          const Text(
            'A day can only hold one saved entry. The old one is not kept.',
            style: TextStyle(fontSize: 12, color: Colors.white38),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, DatedOverwriteChoice.cancel),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.pop(ctx, DatedOverwriteChoice.replace),
          style: TextButton.styleFrom(foregroundColor: NexGenPalette.cyan),
          child: const Text('Replace'),
        ),
      ],
    ),
  );
  // Dismissed → cancel. Never default a destructive action to proceeding.
  return result ?? DatedOverwriteChoice.cancel;
}
