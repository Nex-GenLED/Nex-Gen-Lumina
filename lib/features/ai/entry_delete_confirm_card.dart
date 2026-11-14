// lib/features/ai/entry_delete_confirm_card.dart
//
// Build 128 — the confirmation card for a `deleteCalendarEntries` proposal,
// shared by both Lumina surfaces. The model described which entries; the app
// resolved them; this card shows the count, the dates and the names, with
// Delete and Cancel. Nothing is removed until Delete is tapped. Once decided
// the buttons go and a one-word status takes their place, so the card cannot
// be tapped twice.

import 'package:flutter/material.dart';

import 'package:nexgen_command/features/ai/entry_delete_resolver.dart';
import 'package:nexgen_command/theme.dart';

const _kCarbon = Color(0xFF151B23);

class EntryDeleteConfirmCard extends StatelessWidget {
  /// The lead line ([EntryDeleteProposal.leadText]).
  final String text;
  final EntryDeleteProposal proposal;
  final VoidCallback? onDelete;
  final VoidCallback? onCancel;

  const EntryDeleteConfirmCard({
    super.key,
    required this.text,
    required this.proposal,
    this.onDelete,
    this.onCancel,
  });

  static const Key deleteKey = Key('entry-delete-confirm-delete');
  static const Key cancelKey = Key('entry-delete-confirm-cancel');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final pending = proposal.decision == EntryDeleteDecision.pending;

    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      decoration: BoxDecoration(
        color: _kCarbon,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NexGenPalette.line.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            text,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: NexGenPalette.textHigh,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 10),
          for (final line in proposal.lines)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2, right: 8),
                    child: Icon(Icons.event_outlined,
                        size: 16, color: NexGenPalette.textMedium),
                  ),
                  Expanded(
                    child: Text(
                      line,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: NexGenPalette.textHigh,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          const SizedBox(height: 6),
          if (pending)
            Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              runSpacing: 4,
              children: [
                TextButton(
                  key: cancelKey,
                  onPressed: onCancel,
                  style: TextButton.styleFrom(
                    foregroundColor: NexGenPalette.textMedium,
                  ),
                  child: const Text('Cancel'),
                ),
                FilledButton.tonal(
                  key: deleteKey,
                  onPressed: onDelete,
                  style: FilledButton.styleFrom(
                    foregroundColor: Colors.red.shade300,
                  ),
                  child: const Text('Delete'),
                ),
              ],
            )
          else
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  proposal.decision == EntryDeleteDecision.deleted
                      ? 'Deleted'
                      : 'Cancelled',
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: NexGenPalette.textMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
