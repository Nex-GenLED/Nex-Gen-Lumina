import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/patterns/utils/pattern_display_name.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/theme.dart';

const _kFrost = Color(0xFFDCF0FF);

/// Shared dispatcher for the AI's `schedulingIntent` field — used by both
/// the full-screen Lumina chat ([LuminaAiScreen]) and the dashboard
/// bottom-sheet entry ([LuminaBottomSheet]) so the two surfaces stay in
/// lock-step.
///
/// Posts the AI's response to the chat thread first (both surfaces share
/// [luminaSheetProvider]), then offers a one-tap SnackBar action to
/// persist a [ScheduleItem] via [schedulesProvider].
///
/// SINGLE-ACTION path only. Compound temporal prompts ("red until Dec 25,
/// then warm white through New Year's") cannot decompose through this
/// dispatcher — the cloud-AI schema is currently `schedulingIntent:
/// object|null`. Multi-action decomposition is tracked as Item #51
/// Prompts 3-4.
Future<void> handleSchedulingIntent({
  required WidgetRef ref,
  required BuildContext context,
  required Map<String, dynamic> intent,
  required LuminaCommandResult result,
  required LuminaPatternPreview? preview,
  VoidCallback? onMessagePosted,
}) async {
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

  // Pull the schedule fields. ScheduleItem.repeatDays expects three-letter
  // day codes ('Sun','Mon',…); the prompt instructs the AI to emit them
  // that way, but we fall back to the full week for safety.
  final timeLabel = intent['timeLabel'] as String? ?? 'Sunset';
  final offTimeLabel = intent['offTimeLabel'] as String?;
  final repeatDays = (intent['repeatDays'] as List?)
          ?.map((e) => e.toString())
          .toList() ??
      const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
  final patternName = intent['patternName'] as String? ?? 'Custom';
  final displayPatternName = displayNameFor(patternName);

  if (!context.mounted) return;

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        'Add "$displayPatternName" to your schedule at $timeLabel?',
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
            final item = ScheduleItem(
              id: 'ai-${DateTime.now().millisecondsSinceEpoch}',
              timeLabel: timeLabel,
              offTimeLabel: offTimeLabel,
              repeatDays: repeatDays,
              actionLabel: 'Pattern: $patternName',
              enabled: true,
              wledPayload: result.wledPayload,
            );
            await ref.read(schedulesProvider.notifier).add(item);
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: const Text('Schedule added'),
                backgroundColor: Colors.green.shade700,
                duration: const Duration(seconds: 2),
              ),
            );
          } catch (e) {
            debugPrint('handleSchedulingIntent: add failed: $e');
            if (!context.mounted) return;
            messenger.showSnackBar(
              SnackBar(
                content: Text('Could not add schedule: $e'),
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
