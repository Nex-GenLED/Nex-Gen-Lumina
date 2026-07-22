// lib/features/wled/clock_health_ui.dart
//
// BUG-CLOCK-1 surfacing — warn, never block. Shared between My Schedule (banner
// + creation-flow warnings) and the installer handoff checklist. All copy comes
// from clock_health.dart; this file is just presentation.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/wled/clock_health.dart';
import 'package:nexgen_command/features/wled/clock_health_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Accent color per issue — CLOCK_UNSET is red (nothing fires), the others are
/// amber (fires, but possibly wrong).
Color clockIssueTone(ClockHealthIssue issue) =>
    issue == ClockHealthIssue.clockUnset
        ? Colors.red.shade400
        : NexGenPalette.amber;

/// Dismissible-but-recurring banner for My Schedule. Watches [clockHealthProvider]
/// and renders the single highest-priority issue (LOCATION_UNSET only when
/// [solarRelevant]). Dismissal is owned by the caller ([dismissed]/[onDismiss])
/// so it reappears on the next screen open. Renders nothing when health is
/// unknown, healthy, dismissed, or there's no issue to surface for this context.
class ClockHealthBanner extends ConsumerWidget {
  final bool solarRelevant;
  final bool dismissed;
  final VoidCallback onDismiss;

  const ClockHealthBanner({
    super.key,
    required this.solarRelevant,
    required this.dismissed,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (dismissed) return const SizedBox.shrink();
    final health = ref.watch(clockHealthProvider).valueOrNull;
    if (health == null || health.isHealthy) return const SizedBox.shrink();
    final issue = primaryIssueToSurface(health, solarRelevant: solarRelevant);
    if (issue == null) return const SizedBox.shrink();

    final tone = clockIssueTone(issue);
    return Container(
      color: tone.withValues(alpha: 0.12),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      child: Row(
        children: [
          Icon(Icons.schedule_rounded, color: tone, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              clockHealthMessage(issue),
              style: TextStyle(
                color: tone,
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 6),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: NexGenPalette.cyan,
              visualDensity: VisualDensity.compact,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            ),
            onPressed: () => showClockRemediationDialog(context, issue),
            child: const Text('How to fix',
                style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12)),
          ),
          GestureDetector(
            onTap: onDismiss,
            child: Padding(
              padding: const EdgeInsets.all(4),
              child: Icon(Icons.close, size: 16, color: tone),
            ),
          ),
        ],
      ),
    );
  }
}

/// Remediation dialog — shows the controller-UI settings path for [issue].
/// Read-only guidance; no in-app remote fix in this slice (writing cfg time
/// settings via applyConfig is the future one-tap-fix follow-up).
Future<void> showClockRemediationDialog(
  BuildContext context,
  ClockHealthIssue issue,
) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Row(
        children: [
          Icon(Icons.schedule_rounded, color: clockIssueTone(issue), size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Controller clock')),
        ],
      ),
      content: Text(
        '${clockHealthMessage(issue)}\n\n${clockHealthRemediation(issue)}',
        style: const TextStyle(color: NexGenPalette.textMedium, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Got it'),
        ),
      ],
    ),
  );
}

/// Non-blocking pre-save warning for the schedule creation flow. Returns true to
/// proceed with the save (healthy, unknown, or the user chose "Save anyway"),
/// false to cancel. [creatingSolar] gates the LOCATION_UNSET warning to solar
/// schedules. Never blocks — "Save anyway" is always offered.
Future<bool> maybeWarnClockBeforeSave(
  BuildContext context,
  ClockHealth? health, {
  required bool creatingSolar,
}) async {
  if (health == null) return true;
  final issue = primaryIssueToSurface(health, solarRelevant: creatingSolar);
  if (issue == null) return true;

  final proceed = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: NexGenPalette.gunmetal90,
      title: Row(
        children: [
          Icon(Icons.warning_amber_rounded,
              color: clockIssueTone(issue), size: 20),
          const SizedBox(width: 8),
          const Expanded(child: Text('Heads up')),
        ],
      ),
      content: Text(
        '${clockHealthMessage(issue)}\n\n'
        'Your schedule will still be saved — it just may not run correctly '
        'until the controller is fixed.\n\n${clockHealthRemediation(issue)}',
        style: const TextStyle(color: NexGenPalette.textMedium, height: 1.35),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(ctx).pop(true),
          child: const Text('Save anyway'),
        ),
      ],
    ),
  );
  return proceed ?? false;
}
