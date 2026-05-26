import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';
import 'package:nexgen_command/features/schedule/schedule_conflict_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/theme.dart';

const _kFrost = Color(0xFFDCF0FF);

/// Shared dispatcher for the AI's `schedulingIntents` field — used by both
/// the full-screen Lumina chat ([LuminaAiScreen]) and the dashboard
/// bottom-sheet entry ([LuminaBottomSheet]) so the two surfaces stay in
/// lock-step.
///
/// Accepts a LIST of intents (Item #51 compound-schedule support, completed
/// with this Type-A handler). The cloud parser
/// (`CloudAIProcessor.normalizeSchedulingIntents`) canonicalizes the AI's
/// singular or array shape into a `List<Map>` before this handler sees it,
/// so a model that emitted `schedulingIntent: {…}` arrives here as a
/// one-element list and a `schedulingIntents: [{…}, {…}]` arrives as a
/// two-element list. Either way, the dispatch path is the same.
///
/// Behavior:
///   • Posts the AI's response to the shared chat thread.
///   • Pre-checks conflicts across the whole batch (existing schedules +
///     intra-batch siblings colliding with each other) via
///     `checkConflictsForAddAll` and surfaces `showScheduleConflictDialog`
///     once if any are found.
///   • Confirms via ONE SnackBar (single-item wording for 1 schedule,
///     consolidated count for N).
///   • Persists every item in ONE atomic Firestore write via
///     `schedulesProvider.notifier.addAll(items, resolution: …)` — all or
///     nothing.
///   • Every item in a batch shares the same opaque [ScheduleItem.sourcePromptId]
///     so the UI can later group, bulk-undo, or atomically delete siblings
///     authored by the same prompt.
///
/// **Known Type-A limitation:** `result.wledPayload` is one blob for the
/// whole response. The cloud schema does not provide per-intent WLED
/// payloads, so every item in a compound batch carries the same
/// `wledPayload`. Distinct per-intent designs are a follow-up requiring a
/// schema extension; today, "warm white at sunset AND red on Friday" yields
/// two schedules that run the same single design.
Future<void> handleSchedulingIntents({
  required WidgetRef ref,
  required BuildContext context,
  required List<Map<String, dynamic>> intents,
  required LuminaCommandResult result,
  required LuminaPatternPreview? preview,
  VoidCallback? onMessagePosted,
}) async {
  if (intents.isEmpty) return;

  final controller = ref.read(luminaSheetProvider.notifier);

  // Post the AI's response to the chat thread first so the user sees the
  // confirmation message Claude crafted. Both surfaces read the same
  // provider, so the message lands in the active chat regardless of the
  // entry point.
  controller.addAssistantMessage(
    result.responseText,
    preview: preview,
    wledPayload: result.wledPayload,
  );
  onMessagePosted?.call();

  // ── Build N ScheduleItems sharing one sourcePromptId ──────────────────
  // sourcePromptId: a single opaque uuid stamped on every sibling so the
  // UI can later group, bulk-undo, or atomically roll back the set.
  final sourcePromptId = const Uuid().v4();
  final batchTs = DateTime.now().millisecondsSinceEpoch;
  final items = buildScheduleItemsFromIntents(
    intents: intents,
    sourcePromptId: sourcePromptId,
    batchTs: batchTs,
    sharedWledPayload: result.wledPayload,
  );

  if (!context.mounted) return;

  // ── Conflict pre-check (batch-vs-existing + intra-batch) ──────────────
  // checkConflictsForAddAll aggregates per-item conflicts AND detects two
  // siblings in the same batch overlapping each other. One dialog shows
  // every conflict so the user makes a single decision.
  ConflictResolution? resolution;
  final conflicts =
      ref.read(schedulesProvider.notifier).checkConflictsForAddAll(items);
  if (conflicts.hasConflicts) {
    resolution = await showScheduleConflictDialog(context, conflicts);
    if (resolution == ConflictResolution.cancel) return;
    if (!context.mounted) return;
  }

  // ── ONE consolidated SnackBar confirmation ───────────────────────────
  // Wording diverges by count but the mechanism is identical: single
  // ScaffoldMessenger SnackBar with one Add action that persists via
  // addAll(). Names route through displayNameFor so the prompt cell
  // never leaks a raw slug.
  final String promptText;
  final String successText;
  if (items.length == 1) {
    final firstName = displayNameFor(intents.first['patternName'] as String? ?? 'Custom');
    final firstTime = intents.first['timeLabel'] as String? ?? 'Sunset';
    promptText = 'Add "$firstName" to your schedule at $firstTime?';
    successText = 'Schedule added';
  } else {
    final names = intents
        .map((i) => displayNameFor(i['patternName'] as String? ?? 'Custom'))
        .toList();
    // For 2-3 items list the names inline; for 4+ just say the count to
    // keep the SnackBar from overflowing.
    final namesPreview = names.length <= 3
        ? names.map((n) => '"$n"').join(', ')
        : '${names.length} schedules';
    promptText = 'Add $namesPreview to your weekly plan?';
    successText = '${items.length} schedules added';
  }

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        promptText,
        style: const TextStyle(color: _kFrost),
      ),
      backgroundColor: NexGenPalette.gunmetal90,
      duration: const Duration(seconds: 8),
      action: SnackBarAction(
        label: 'Add',
        textColor: NexGenPalette.cyan,
        onPressed: () async {
          final messenger = ScaffoldMessenger.of(context);
          try {
            await ref
                .read(schedulesProvider.notifier)
                .addAll(items, resolution: resolution);
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text(successText),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          } catch (e) {
            debugPrint('handleSchedulingIntents: addAll failed: $e');
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text('Could not add schedules: $e'),
                backgroundColor: Colors.red.shade700,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        },
      ),
    ),
  );
}

/// Map N AI intents to N [ScheduleItem]s sharing one [sourcePromptId].
///
/// Pure function — extracted from [handleSchedulingIntents] so the
/// item-construction invariants (shared sourcePromptId, unique ids,
/// field defaulting, "Pattern: " action-label prefix) are testable
/// without standing up Riverpod, ScaffoldMessenger, or Firebase Auth.
///
/// Each item's [ScheduleItem.id] is `'ai-$batchTs-$index'` so two items
/// minted in the same millisecond don't collide. The whole batch shares
/// [sourcePromptId] so the UI can later group, bulk-undo, or atomically
/// roll back siblings authored by the same prompt.
///
/// Known Type-A limitation: the cloud schema returns ONE top-level
/// `wled` payload for the whole response, not per-intent. Every item in
/// the batch carries the same [sharedWledPayload]. Distinct per-intent
/// payloads are a follow-up requiring a schema extension.
@visibleForTesting
List<ScheduleItem> buildScheduleItemsFromIntents({
  required List<Map<String, dynamic>> intents,
  required String sourcePromptId,
  required int batchTs,
  required Map<String, dynamic>? sharedWledPayload,
}) {
  final items = <ScheduleItem>[];
  for (int i = 0; i < intents.length; i++) {
    final intent = intents[i];
    final timeLabel = intent['timeLabel'] as String? ?? 'Sunset';
    final offTimeLabel = intent['offTimeLabel'] as String?;
    final repeatDays = (intent['repeatDays'] as List?)
            ?.map((e) => e.toString())
            .toList() ??
        const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
    final patternName = intent['patternName'] as String? ?? 'Custom';

    items.add(ScheduleItem(
      id: 'ai-$batchTs-$i',
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabel,
      repeatDays: repeatDays,
      actionLabel: 'Pattern: $patternName',
      enabled: true,
      wledPayload: sharedWledPayload,
      sourcePromptId: sourcePromptId,
    ));
  }
  return items;
}
