// lib/features/game_day/game_day_design_save.dart
//
// The SAVE side of the Game Day design picker — the only place a design is
// written into a team's plan from the library.
//
// Until 2026-09-25 the colorway selector persisted to Game Day itself, from
// the same "Apply" button that wrote to the controller, and only inside the
// device-write block: off-LAN, with no readable channels, or with no
// repository the plan was never written while the snackbar still said
// "Preview". Now the selector runs in SAVE mode and hands the chosen design
// back here; nothing in this file touches a controller.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../autopilot/game_day_autopilot_config.dart';
import '../autopilot/game_day_autopilot_providers.dart';
import '../wled/colorway_effect_selector.dart' show LibraryDesignSelection;
import '../wled/pattern_theme_selection.dart' show LibraryBrowserScreen;

/// Persist [selection] as [teamSlug]'s base design. The plan stores ONE
/// representation — the WLED payload — plus the palette's name; the effect
/// the card shows is derived from the payload (see
/// [GameDayAutopilotConfig.designLabel]), so the two can never disagree.
Future<void> saveGameDayDesignSelection(
  WidgetRef ref,
  String teamSlug,
  LibraryDesignSelection selection,
) {
  return ref.read(gameDayAutopilotNotifierProvider.notifier).saveDesign(
        teamSlug: teamSlug,
        designName: selection.baseName,
        wledPayload: selection.wledPayload,
      );
}

/// The Game Day design picker: the library in SAVE mode for one team.
///
/// Routed at `/dashboard/game-day/picker/:nodeId` (root navigator). Tapping
/// "Save to Game Day" on a design writes the plan and pops back to Game Day;
/// "Preview on lights" is the only control that reaches the controller. The
/// selector is seeded from the team's current plan so the editor opens on the
/// effect the card shows, not on a default.
class GameDayDesignPickerScreen extends ConsumerWidget {
  final String nodeId;
  final String teamSlug;

  const GameDayDesignPickerScreen({
    super.key,
    required this.nodeId,
    required this.teamSlug,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final config = ref
        .watch(gameDayAutopilotConfigsProvider)
        .valueOrNull
        ?.where((c) => c.teamSlug == teamSlug)
        .firstOrNull;
    final seed = config?.effectiveDesignSegment;
    return LibraryBrowserScreen(
      nodeId: nodeId,
      saveDestinationLabel: 'Game Day',
      initialEffectId: (seed?['fx'] as num?)?.toInt(),
      initialSpeed: (seed?['sx'] as num?)?.toInt(),
      initialIntensity: (seed?['ix'] as num?)?.toInt(),
      onDesignSelected: (selection) async {
        final messenger = ScaffoldMessenger.of(context);
        final navigator = Navigator.of(context);
        try {
          await saveGameDayDesignSelection(ref, teamSlug, selection);
          messenger.showSnackBar(SnackBar(
            content: Text('Saved "${selection.name}" for Game Day'),
            duration: const Duration(seconds: 2),
          ));
          navigator.pop();
        } catch (e) {
          messenger.showSnackBar(SnackBar(
            content: Text("Couldn't save this design for Game Day: $e"),
            backgroundColor: Colors.red.shade800,
            duration: const Duration(seconds: 4),
          ));
        }
      },
    );
  }
}
