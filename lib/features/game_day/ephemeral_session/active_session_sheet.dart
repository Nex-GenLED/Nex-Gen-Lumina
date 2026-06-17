// lib/features/game_day/ephemeral_session/active_session_sheet.dart
//
// Item #51 Prompt 4 — bottom sheet that surfaces the currently-active
// ephemeral game session (preGame/liveGame/postGame phase) with controls
// to edit the design or cancel the session.
//
// Time-formatting discipline: all session timestamps are converted via
// .toLocal() before extraction (Item #63 lesson — ESPN-sourced DateTime
// values are UTC-flagged).

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../theme.dart';
import '../../sports_alerts/data/team_colors.dart';
import '../../wled/sports_library_builder.dart';
import 'ephemeral_game_session.dart';
import 'ephemeral_game_session_providers.dart';

/// Bottom sheet surfaced when the user taps the home dashboard Game Day
/// button while a session is in active phase. Shows the team, phase,
/// game start time, revert label, and Edit Design / Cancel actions.
class ActiveSessionSheet extends ConsumerWidget {
  final EphemeralGameSession session;

  const ActiveSessionSheet({super.key, required this.session});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final teamInfo = kTeamColors[session.teamSlug];
    final teamName = teamInfo?.teamName ?? session.teamSlug;
    final primary = teamInfo?.primary ?? NexGenPalette.cyan;
    final secondary = teamInfo?.secondary ?? NexGenPalette.cyan;

    return Container(
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20,
        12,
        20,
        24 + MediaQuery.of(context).padding.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Drag handle
          Center(
            child: Container(
              width: 40,
              height: 4,
              margin: const EdgeInsets.only(bottom: 16),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Team header with team-color gradient strip
          Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [primary, secondary],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                const Icon(Icons.stadium_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        teamName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 16,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _phaseLabel(session.phase),
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: 0.85),
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.0,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          // Game start time row
          _DetailRow(
            icon: Icons.schedule_rounded,
            label: 'Game start',
            value: _formatGameTime(session.gameStart),
          ),
          const SizedBox(height: 8),
          // Revert label row
          _DetailRow(
            icon: Icons.replay_rounded,
            label: 'Will revert to',
            value: session.revertLabel,
          ),
          const SizedBox(height: 20),
          // Edit Design button
          FilledButton.icon(
            onPressed: () => _onEditDesign(context),
            icon: const Icon(Icons.tune_rounded),
            label: const Text('Edit Design'),
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
          const SizedBox(height: 8),
          // Cancel Session button (destructive)
          OutlinedButton.icon(
            onPressed: () => _onCancel(context, ref),
            icon: const Icon(Icons.close_rounded),
            label: const Text('Cancel Session'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.red.shade300,
              side: BorderSide(
                color: Colors.red.shade300.withValues(alpha: 0.5),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ],
      ),
    );
  }

  static String _phaseLabel(EphemeralSessionPhase phase) {
    switch (phase) {
      case EphemeralSessionPhase.preGame:
        return 'PRE-GAME';
      case EphemeralSessionPhase.liveGame:
        return 'LIVE';
      case EphemeralSessionPhase.postGame:
        return 'POST-GAME';
      case EphemeralSessionPhase.idle:
        return 'WAITING';
      case EphemeralSessionPhase.completed:
        return 'COMPLETED';
    }
  }

  // Item #63 discipline: ESPN-sourced DateTime values are UTC-flagged.
  // .toLocal() converts to the device's local timezone before clock-field
  // extraction.
  static String _formatGameTime(DateTime utcStart) {
    final local = utcStart.toLocal();
    final h24 = local.hour;
    final m = local.minute;
    final hour12 = h24 == 0 ? 12 : (h24 > 12 ? h24 - 12 : h24);
    final period = h24 >= 12 ? 'PM' : 'AM';
    final mm = m.toString().padLeft(2, '0');
    return '$hour12:$mm $period';
  }

  void _onEditDesign(BuildContext context) {
    final teamSlug = session.teamSlug;
    final messenger = ScaffoldMessenger.of(context);
    // Dismiss the sheet first; the sheet's Navigator pops, leaving the
    // dashboard route intact. Then push the picker route from Item #64
    // which uses parentNavigatorKey: _rootNavigatorKey so back-arrow
    // returns directly to the dashboard.
    Navigator.of(context).pop();
    if (!context.mounted) return;

    // Resolve the real catalog leaf node id from the team identity (derived
    // from kTeamColors) rather than minting `team_<slug>`. See
    // SportsLibraryBuilder.resolveTeamNodeId.
    final team = kTeamColors[teamSlug];
    final nodeId = team == null
        ? null
        : SportsLibraryBuilder.resolveTeamNodeId(
            teamName: team.teamName,
            sport: team.sport,
            espnTeamId: team.espnTeamId,
          );
    if (nodeId == null) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
              "Couldn't find ${team?.teamName ?? 'that team'}'s designs in the library."),
        ),
      );
      return;
    }
    // teamSlug passed explicitly so it still reaches saveDesign.
    context.push('/dashboard/game-day/picker/$nodeId',
        extra: {'teamSlug': teamSlug});
  }

  Future<void> _onCancel(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);
    final svc = ref.read(ephemeralGameSessionServiceProvider);
    if (svc == null) return;

    // Capture session data BEFORE cancelling so undo can recreate the
    // session as a new Firestore document with identical parameters
    // (option-b approach — service does not need a restoreSession method).
    final captured = session;
    Navigator.of(context).pop(); // dismiss the sheet

    await svc.cancelSession(captured.sessionId);

    messenger.showSnackBar(
      SnackBar(
        content: const Text('Session cancelled'),
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: 'UNDO',
          onPressed: () async {
            try {
              final restored = await svc.createSession(
                teamSlug: captured.teamSlug,
                gameId: captured.gameId,
                revertWledPayload: captured.revertWledPayload,
                revertLabel: captured.revertLabel,
              );
              await svc.startTracking(restored.sessionId);
            } catch (e) {
              debugPrint('[ActiveSessionSheet] undo cancel failed: $e');
              messenger.showSnackBar(
                SnackBar(content: Text('Could not undo: $e')),
              );
            }
          },
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, size: 18, color: NexGenPalette.textSecondary),
        const SizedBox(width: 12),
        Text(
          '$label:',
          style: const TextStyle(
            color: NexGenPalette.textSecondary,
            fontSize: 13,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              color: NexGenPalette.textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w600,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.end,
          ),
        ),
      ],
    );
  }
}
