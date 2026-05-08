// lib/features/game_day/ephemeral_session/_debug_test_trigger.dart
//
// Debug-only widget for manually creating ephemeral game sessions.
// NOT wired into any production screen. Tyler instantiates this from a
// test harness or temporarily drops it into a settings page when needed.
//
// To remove for production: delete this file.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../sports_alerts/services/game_schedule_service.dart';
import 'ephemeral_game_session_providers.dart';

/// Hardcoded test values — `mlb_royals` matches `kTeamColors[]` (NOT the
/// `kc-royals` placeholder used in the original prompt example, which
/// doesn't exist in the team color map).
const _kTestTeamSlug = 'mlb_royals';
const _kTestRevertLabel = 'Test Blue Revert';
const Map<String, dynamic> _kTestRevertPayload = {
  'on': true,
  'bri': 200,
  'seg': [
    {
      'fx': 0,
      'col': [
        [0, 100, 200, 0]
      ],
    }
  ],
};

class EphemeralSessionDebugTrigger extends ConsumerWidget {
  const EphemeralSessionDebugTrigger({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton(
      onPressed: () => _onTap(context, ref),
      child: const Text('DEBUG: Create Ephemeral Royals Session'),
    );
  }

  Future<void> _onTap(BuildContext context, WidgetRef ref) async {
    final messenger = ScaffoldMessenger.of(context);

    final svc = ref.read(ephemeralGameSessionServiceProvider);
    if (svc == null) {
      messenger.showSnackBar(
        const SnackBar(content: Text('Not signed in')),
      );
      return;
    }

    // Local schedule service instance — debug widget owns its own to avoid
    // depending on a private provider.
    final scheduleSvc = GameScheduleService();
    try {
      final games = await scheduleSvc.resolveGamesForTeamOnDate(
        _kTestTeamSlug,
        DateTime.now(),
      );
      if (games.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text(
              'No Royals game today — try another day or override.',
            ),
          ),
        );
        return;
      }

      final game = games.first;
      final session = await svc.createSession(
        teamSlug: _kTestTeamSlug,
        gameId: game.gameId,
        revertWledPayload: _kTestRevertPayload,
        revertLabel: _kTestRevertLabel,
      );
      await svc.startTracking(session.sessionId);

      messenger.showSnackBar(
        SnackBar(content: Text('Created session ${session.sessionId}')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    } finally {
      scheduleSvc.dispose();
    }
  }
}
