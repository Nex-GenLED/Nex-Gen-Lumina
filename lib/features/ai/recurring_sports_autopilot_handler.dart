import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/features/ai/lumina_command.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/recurring_sports_autopilot_intent.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/features/sports_alerts/data/team_colors.dart';

/// Shared dispatcher for the AI's `recurringSportsAutopilot` rule — used by
/// both the full-screen Lumina chat ([LuminaAiScreen]) and the dashboard
/// bottom-sheet entry ([LuminaBottomSheet]) so the two surfaces stay in
/// lock-step (mirrors [handleSchedulingIntents]).
///
/// The AI emits this COMPACT rule (team slug + optional end bound) instead of
/// enumerating ~80 game dates — that enumeration is exactly what overflowed
/// the response token cap and truncated the JSON. This handler routes the rule
/// to the EXISTING Game Day Autopilot enable path
/// ([GameDayAutopilotNotifier.toggleAutopilot]):
///
///   • toggleAutopilot keys its Firestore doc by team slug, so enabling a team
///     that already has a config UPDATES that one doc — it NEVER creates a
///     second/parallel config. Single source of truth per team; a duplicate
///     would write competing CalendarEntry rows fighting for the same WLED
///     lease slots.
///   • The enable path's background populate then writes only the next rolling
///     7-day window of CalendarEntry rows (populateCalendarForTeam); the
///     CalendarEntryLeaseManager promotes those within 48h into ≤8 WLED RTC
///     timers. No per-game enumeration is ever persisted.
///   • [RecurringSportsAutopilotIntent.untilDate], when present, is persisted
///     on the config and bounds materialization (inclusive of its day).
///
/// Posts a single confirmation message to the shared chat thread. Does NOT
/// apply a design to the device — the rule is future automation, not an
/// immediate "now" command; the lights change at each game's lead time.
Future<void> handleRecurringSportsAutopilot({
  required WidgetRef ref,
  required RecurringSportsAutopilotIntent intent,
  required LuminaCommandResult result,
  VoidCallback? onMessagePosted,
}) async {
  final controller = ref.read(luminaSheetProvider.notifier);

  void post(String message) {
    controller.addAssistantMessage(message);
    onMessagePosted?.call();
  }

  // Validate the slug against the catalog up front. toggleAutopilot →
  // addTeam would throw ArgumentError on an unknown slug; catching it here
  // lets us surface an honest message instead of a generic snag.
  final team = kTeamColors[intent.teamSlug];
  if (team == null) {
    debugPrint(
        '[RecurringSportsAutopilot] unknown teamSlug "${intent.teamSlug}" — not enabling');
    post("I couldn't find that team in my roster yet, so I didn't set up "
        "automatic game-day lighting. Try the team's name again and I'll wire it up.");
    return;
  }

  // Idempotent enable-or-update — see [GameDayAutopilotNotifier.toggleAutopilot].
  try {
    await ref.read(gameDayAutopilotNotifierProvider.notifier).toggleAutopilot(
          teamSlug: intent.teamSlug,
          enabled: true,
          untilDate: intent.untilDate,
        );
  } catch (e) {
    debugPrint('[RecurringSportsAutopilot] toggleAutopilot failed: $e');
    post('I hit a snag turning on automatic game-day lighting for '
        '${team.teamName}. Please try again in a moment.');
    return;
  }

  // Confirmation. Prefer the AI's prose; always append a deterministic line
  // so the user knows automation is on (and through when, if bounded).
  final boundPhrase =
      intent.untilDate != null ? ' through ${_formatBound(intent.untilDate!)}' : '';
  final confirmation =
      '✓ Game Day Autopilot is on for ${team.teamName}$boundPhrase — '
      "I'll set your lights for every game automatically.";

  final prose = result.responseText.trim();
  post(prose.isEmpty ? confirmation : '$prose\n\n$confirmation');
}

const _kMonths = [
  'January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December',
];

/// "Oct 31, 2026"-style bound label for the confirmation message.
String _formatBound(DateTime d) =>
    '${_kMonths[d.month - 1].substring(0, 3)} ${d.day}, ${d.year}';
