// BASE-LAYER GATE — audit/BASE_LAYER_GATE.md
//
// Game Day fires a design and relies on an END SIGNAL to put the house back.
// If that signal never lands — bridge offline, command expired, ESPN never
// reports final, a Functions outage — the house is returned by the BASE LAYER
// at its next boundary. An account with no everyday schedule has no next
// boundary, so the design runs until a human intervenes.
//
// Six accounts are in that state today, one of them commercial. This prompt
// informs them before they opt in.
//
// ⚠️ WHAT THIS CAN AND CANNOT KNOW — the caveat that must not be optimised away:
// this reads FIRESTORE INTENT (the user's recurring schedules), not device
// reality. A controller can hold base timer rows with no Firestore schedules —
// the bench rig is exactly that. So "no base layer" here means "we can't see
// one", NOT "there isn't one", and it is not knowable off-LAN. Every string in
// this file is worded to claim only what is true, and
// [BaseLayerStatus.absentInFirestore] is named to keep that honest at the call
// site. Do not rename it to `absent`.
//
// ⚠️ NOT A GUARD. If anything here fails — no context, dialog throws, provider
// unavailable — the enable PROCEEDS. A broken prompt must never block a
// customer from turning on a feature they already use. See [maybeWarnNoBaseLayer].

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';

/// What we can see of an account's everyday schedule.
///
/// `absentInFirestore` deliberately does NOT claim the house has no base layer —
/// only that this app cannot see one. See the file header.
enum BaseLayerStatus { present, absentInFirestore }

/// PURE. An account has a visible base layer when at least one recurring
/// schedule is enabled and would actually arm.
///
/// Dated calendar entries do NOT count: they cover a single day, so they are
/// not a floor for a game on any other day. An evicted or disabled item does
/// not count either — it will not fire.
BaseLayerStatus evaluateBaseLayer(List<ScheduleItem> schedules) {
  for (final s in schedules) {
    if (!s.enabled) continue;
    if (s.isCurrentlyEvicted) continue;
    if (s.repeatDays.isEmpty) continue;
    return BaseLayerStatus.present;
  }
  return BaseLayerStatus.absentInFirestore;
}

/// Accounts already prompted this app session, keyed by uid.
///
/// Session-scoped on purpose: no persisted "don't show again", because the
/// condition is worth re-stating in a later session if it still holds, and a
/// persisted flag would silently hide it forever after one dismissal.
final Set<String> _promptedUids = <String>{};

@visibleForTesting
void resetBaseLayerPromptSession() => _promptedUids.clear();

@visibleForTesting
bool wasPromptedThisSession(String uid) => _promptedUids.contains(uid);

/// True when [uid] has not yet been prompted in this session. Marks it as
/// prompted. Called only once the status is known to be absent.
bool markPromptedOnce(String uid) {
  if (_promptedUids.contains(uid)) return false;
  _promptedUids.add(uid);
  return true;
}

/// Show the informational prompt if this account has no visible base layer.
///
/// RETURNS `true` TO PROCEED. It returns `true` in every case except the one
/// where the customer explicitly chose not to: no base layer needed, already
/// prompted this session, no context, an exception anywhere — all proceed.
/// The ONLY `false` is an explicit "Not now".
///
/// This is not a guard and must not become one.
Future<bool> maybeWarnNoBaseLayer({
  required BuildContext context,
  required WidgetRef ref,
  required String uid,
  VoidCallback? onSetUpSchedule,
}) async {
  try {
    final schedules = ref.read(schedulesProvider);
    if (evaluateBaseLayer(schedules) == BaseLayerStatus.present) return true;
    if (!markPromptedOnce(uid)) return true;
    if (!context.mounted) return true;
    final proceed = await _showNoBaseLayerDialog(context, onSetUpSchedule);
    return proceed;
  } catch (e) {
    // FAIL OPEN. A prompt that cannot render must not cost the customer the
    // feature. Logged so a silent regression is still visible in a debug run.
    debugPrint('BaseLayerGate: prompt failed ($e) — proceeding with enable');
    return true;
  }
}

Future<bool> _showNoBaseLayerDialog(
    BuildContext context, VoidCallback? onSetUpSchedule) async {
  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: NexGenPalette.gunmetal,
      title: const Text(
        'No everyday schedule set',
        style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
      ),
      content: const Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Plain terms, and only what is true. We do not say "your lights WILL
          // stay on" — we cannot see the controller, and we do not say the
          // house has no schedule at all, only that we don't have one saved.
          Text(
            'Game Day turns your lights on for a game and turns them back off '
            'when it ends.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 12),
          Text(
            'You don\'t have an everyday schedule saved. If something goes '
            'wrong at the end of a game — your bridge is offline, or the score '
            'never arrives — there\'s nothing scheduled to turn the lights off '
            'afterwards, so they may stay on until you turn them off yourself.',
            style: TextStyle(fontSize: 14, height: 1.4),
          ),
          SizedBox(height: 12),
          Text(
            'Setting an everyday schedule fixes that — your lights go back to '
            'their normal routine at the next on or off time.',
            style: TextStyle(fontSize: 13, height: 1.4, color: Colors.white70),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx, false),
          child: const Text('Not now'),
        ),
        if (onSetUpSchedule != null)
          TextButton(
            onPressed: () {
              Navigator.pop(ctx, false);
              onSetUpSchedule();
            },
            child: const Text('Set a schedule'),
          ),
        TextButton(
          onPressed: () => Navigator.pop(ctx, true),
          style: TextButton.styleFrom(foregroundColor: NexGenPalette.cyan),
          child: const Text('Enable anyway'),
        ),
      ],
    ),
  );
  // Dismissed (tap-outside / back) → PROCEED. This informs, it does not block;
  // defaulting a dismissal to "cancel" would make it a guard.
  return result ?? true;
}
