// lib/features/game_day/game_day_entry_button.dart
//
// The home dashboard's "Game Day" tile: the ONE entry point to Game Day from
// the home screen.
//
// Item #51 Prompt 4 gave it session awareness: while an ephemeral session is
// in an active phase the tile paints in the team's colours and a tap opens
// the session sheet instead of the Game Day screen. Two things were missing
// and are fixed here (2026-09-25):
//
//   1. The tile trusted the stored phase. A `postGame` document left over
//      from a game the night before still counted as "active", so the tile
//      opened a sheet for a finished game and the Game Day screen — with the
//      team selector — was unreachable from the home screen. The provider
//      now applies ephemeral_session_expiry.dart, and the tap re-checks the
//      clock so a session that expires while the dashboard sits open cannot
//      sneak through between provider recomputes.
//
//   2. The sheet was shown via the branch navigator, so the glass dock
//      painted over its lower edge — on the device only "Edit Design" was
//      visible; the cancel action underneath was covered. It now opens on
//      the root navigator, above the dock.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app_router.dart';
import '../dashboard/widgets/feature_button.dart';
import '../sports_alerts/data/team_colors.dart';
import 'ephemeral_session/active_session_sheet.dart';
import 'ephemeral_session/ephemeral_game_session.dart';
import 'ephemeral_session/ephemeral_game_session_providers.dart';
import 'ephemeral_session/ephemeral_session_expiry.dart';

class GameDayEntryButton extends ConsumerWidget {
  const GameDayEntryButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(activePhaseSessionProvider);
    final teamInfo = session != null ? kTeamColors[session.teamSlug] : null;
    final gradient = (session != null && teamInfo != null)
        ? LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [teamInfo.primary, teamInfo.secondary],
          )
        : null;

    return FeatureButton(
      icon: Icons.stadium_rounded,
      label: 'Game Day',
      gradient: gradient,
      onTap: () => _onTap(context, ref, session),
    );
  }

  void _onTap(
      BuildContext context, WidgetRef ref, EphemeralGameSession? session) {
    final now = ref.read(ephemeralSessionClockProvider)();
    final current = session != null &&
        session.phase.isActive &&
        !isEphemeralSessionExpired(session, now);
    if (!current) {
      context.push(AppRoutes.gameDay);
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      // Root navigator: the sheet must sit ABOVE the persistent glass dock,
      // not inside the branch navigator the dock overlays.
      useRootNavigator: true,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => ActiveSessionSheet(session: session),
    );
  }
}
