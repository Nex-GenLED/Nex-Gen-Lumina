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
/// Per-element `wled` payloads (Item #51 Type-A full):
///   • Each intent Map may carry its own `wled` field (full WLED state for
///     that schedule). When present, the resulting [ScheduleItem] uses that
///     per-element payload instead of [result.wledPayload].
///   • When omitted, the item falls back to [result.wledPayload] — the
///     primary design from the top of the AI response.
///
/// **Honesty guard:** when a sibling carries a distinct `patternName` from
/// the top-level design AND has no per-element `wled`, attaching the
/// top-level payload would create a "lying" entry (e.g. a schedule named
/// "Friday Red" running a warm-white payload). The guard drops those
/// siblings and surfaces them in the chat message so the user knows what
/// didn't land — never silently. The honest cases are:
///   • the intent's `patternName` matches the top-level — legitimate reuse;
///   • the intent has its own `wled` Map — distinct design provided.
/// At least one item is always scheduled: if every intent is ambiguous,
/// the first one is scheduled against the top-level payload (with the
/// honesty caveat noted in the message) so the user gets *something* they
/// asked for.
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

  // ── Honesty guard: drop ambiguous intents (distinct name, no own wled) ─
  // Without this, a sibling labeled "Friday Red" with no per-element wled
  // would silently attach to the top-level warm-white payload — a lying
  // entry. Dropped intent names surface in the post-add message so the
  // user knows what didn't land.
  final topLevelPatternName =
      result.wledPayload?['patternName'] as String?;
  final classification = classifyIntents(
    intents: intents,
    topLevelPatternName: topLevelPatternName,
  );
  final keptIntents = classification.kept;
  final droppedNames = classification.droppedNames;

  // ── Build N ScheduleItems sharing one sourcePromptId ──────────────────
  // sourcePromptId: a single opaque uuid stamped on every sibling so the
  // UI can later group, bulk-undo, or atomically roll back the set.
  // Per-element wled wins inside the builder; the shared payload is the
  // top-level fallback for honest reuse cases.
  final sourcePromptId = const Uuid().v4();
  final batchTs = DateTime.now().millisecondsSinceEpoch;
  final items = buildScheduleItemsFromIntents(
    intents: keptIntents,
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
  // never leaks a raw slug. Counts reflect only the KEPT (honest)
  // intents — the dropped ones appear in the post-Add chat message.
  final String promptText;
  final String successText;
  if (items.length == 1) {
    final firstName = displayNameFor(
        keptIntents.first['patternName'] as String? ?? 'Custom');
    final firstTime = keptIntents.first['timeLabel'] as String? ?? 'Sunset';
    promptText = 'Add "$firstName" to your schedule at $firstTime?';
    successText = 'Schedule added';
  } else {
    final names = keptIntents
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
            // Honesty follow-up: if the guard dropped any siblings,
            // post a chat message naming them so the user sees the
            // saved/skipped split in the conversation history (the
            // SnackBar disappears).
            if (droppedNames.isNotEmpty) {
              final savedQuoted = items
                  .map((i) => '"${displayNameFor(
                      i.actionLabel.startsWith('Pattern: ')
                          ? i.actionLabel.substring(9)
                          : i.actionLabel)}"')
                  .join(', ');
              final droppedQuoted = droppedNames
                  .map((n) => '"${displayNameFor(n)}"')
                  .join(', ');
              final droppedPhrase = droppedNames.length == 1
                  ? 'a separate design for $droppedQuoted'
                  : 'separate designs for $droppedQuoted';
              controller.addAssistantMessage(
                'Saved $savedQuoted. I couldn\'t set $droppedPhrase '
                'in one go — ask me to add it and I\'ll schedule it.',
              );
              onMessagePosted?.call();
            }
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

/// Result of [classifyIntents] — the honest slice plus the names of any
/// intents dropped for ambiguity.
class IntentClassification {
  /// Intents safe to schedule. Either carry their own `wled` (distinct
  /// design provided) or reuse the top-level design under the matching
  /// `patternName`. May be a subset of the input.
  final List<Map<String, dynamic>> kept;

  /// Display names of intents the guard dropped because they would have
  /// attached the wrong design under a truthful label. The caller surfaces
  /// these in the post-add message so the user knows what didn't land.
  final List<String> droppedNames;

  const IntentClassification({
    required this.kept,
    required this.droppedNames,
  });
}

/// Honesty guard. Partition `intents` into the ones safe to schedule
/// (`kept`) vs the ones that would create a lying entry (`droppedNames`,
/// surfaced to the user).
///
/// Classification per intent:
///   • HONEST if the intent has its own `wled` Map (distinct design
///     provided by the model) — schedule with the per-element payload.
///   • HONEST if the intent's `patternName` matches [topLevelPatternName]
///     (case-insensitive, trimmed) — legitimate reuse of the primary
///     design.
///   • AMBIGUOUS otherwise — distinct patternName but no per-element
///     payload would attach the wrong design under a truthful label.
///
/// Fallback: if EVERY intent is ambiguous (pathological — the model
/// produced N distinct names but no per-element payloads), the FIRST
/// intent is kept and scheduled against the top-level. The user still
/// gets *something* they asked for; the caller's message names the rest
/// as unsaved. This branch happens at most rarely; the schema explicitly
/// forbids the model from producing this shape, but the guard is the
/// belt-and-suspenders.
@visibleForTesting
IntentClassification classifyIntents({
  required List<Map<String, dynamic>> intents,
  required String? topLevelPatternName,
}) {
  if (intents.isEmpty) {
    return const IntentClassification(kept: [], droppedNames: []);
  }

  final topNormalized = topLevelPatternName?.trim().toLowerCase();

  final kept = <Map<String, dynamic>>[];
  final droppedNames = <String>[];
  for (final intent in intents) {
    final hasOwnWled = intent['wled'] is Map;
    final name = (intent['patternName'] as String?)?.trim() ?? '';
    final nameMatchesTop = topNormalized != null &&
        topNormalized.isNotEmpty &&
        name.toLowerCase() == topNormalized;
    if (hasOwnWled || nameMatchesTop) {
      kept.add(intent);
    } else {
      droppedNames.add(name.isEmpty ? 'Custom' : name);
    }
  }

  // Pathological fallback: every intent was ambiguous. Keep the first one
  // so the user gets at least one schedule from their compound prompt.
  // The first item's name moves out of droppedNames (it IS being saved,
  // just under the top-level design); the rest stay dropped.
  if (kept.isEmpty) {
    kept.add(intents.first);
    if (droppedNames.isNotEmpty) {
      droppedNames.removeAt(0);
    }
  }

  return IntentClassification(kept: kept, droppedNames: droppedNames);
}

/// Map N AI intents to N [ScheduleItem]s sharing one [sourcePromptId].
///
/// Pure function — extracted from [handleSchedulingIntents] so the
/// item-construction invariants (shared sourcePromptId, unique ids,
/// field defaulting, "Pattern: " action-label prefix, per-element vs
/// shared wledPayload selection) are testable without standing up
/// Riverpod, ScaffoldMessenger, or Firebase Auth.
///
/// Each item's [ScheduleItem.id] is `'ai-$batchTs-$index'` so two items
/// minted in the same millisecond don't collide. The whole batch shares
/// [sourcePromptId] so the UI can later group, bulk-undo, or atomically
/// roll back siblings authored by the same prompt.
///
/// Per-element WLED payload: each intent may carry its own `wled` Map
/// (Item #51 Type-A full). When present, the resulting item uses that
/// per-element payload. When absent, the item falls back to
/// [sharedWledPayload] — the top-level design.
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

    // Per-element wled wins when present; else fall back to the
    // shared top-level payload. The honesty guard upstream
    // ([classifyIntents]) ensures this fallback only fires when the
    // patternName matches the top-level design, so the user never sees
    // a sibling labeled "Friday Red" running a warm-white payload.
    final perIntentWled = intent['wled'];
    final itemPayload = perIntentWled is Map
        ? Map<String, dynamic>.from(perIntentWled)
        : sharedWledPayload;

    items.add(ScheduleItem(
      id: 'ai-$batchTs-$i',
      timeLabel: timeLabel,
      offTimeLabel: offTimeLabel,
      repeatDays: repeatDays,
      actionLabel: 'Pattern: $patternName',
      enabled: true,
      wledPayload: itemPayload,
      sourcePromptId: sourcePromptId,
    ));
  }
  return items;
}
