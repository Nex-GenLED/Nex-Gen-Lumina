// The Game Day screen's "who runs this" banner — three states (+114, plan §3.4).
//
//   Server   "Game Day runs from our servers" + the next fire and the last one.
//   Phone    "Game Day runs from this phone" + why, when an allowlisted home
//            was held back by pre-flight (or the server stopped checking in).
//   Blocked  the readiness gate's own headline and reasons — shown only for a
//            home on the server path, the one case the gate changes anything.
//
// WHAT IT REPLACED. The W2 banner showed the gate to every account and, once
// an account graduated, said "Your lights will fire for upcoming games." For a
// home the server does not run that was a promise about a path that would not
// fire (plan §5), and for a gated phone-run home "not firing yet" was wrong the
// other way — the phone fires regardless of the gate. The states and their
// words live in game_day_run_mode.dart; this file only lays them out.
//
// ALWAYS VISIBLE once the account has a team: which path runs a home is the
// one thing a dealer needs to see on game day ("Server" screenshot), so it is
// not hidden behind an acknowledgement.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart'
    show enabledAutopilotConfigsProvider;
import 'package:nexgen_command/utils/time_format.dart';
import 'game_day_run_mode.dart';
import 'game_day_server_status_provider.dart';
import 'gate_status.dart';
import 'gate_status_provider.dart';

/// Shows who runs this home's Game Day. Renders nothing for an account with no
/// Game Day teams that the server does not serve.
class GameDayRunBanner extends ConsumerWidget {
  const GameDayRunBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final status = ref.watch(gameDayServerStatusSyncProvider);
    final gate =
        ref.watch(gateStatusProvider).valueOrNull ?? GateStatus.unknown;
    final now = ref.watch(gameDayNowProvider)();
    final configs = ref.watch(enabledAutopilotConfigsProvider);
    final names = {for (final c in configs) c.teamSlug: c.teamName};

    final mode = gameDayRunModeFor(status: status, gate: gate, now: now);
    if (configs.isEmpty && mode == GameDayRunMode.phone) {
      return const SizedBox.shrink();
    }
    final copy = gameDayRunCopy(
      mode: mode,
      status: status,
      gate: gate,
      now: now,
      teamName: (slug) => names[slug] ?? slug,
      enabledTeamSlugs: [for (final c in configs) c.teamSlug],
      timeFormat: ref.watch(timeFormatPreferenceProvider),
    );
    return GameDayRunBannerView(mode: mode, copy: copy);
  }
}

/// The layout, split out so it can be laid out at large text sizes without
/// providers.
class GameDayRunBannerView extends StatelessWidget {
  final GameDayRunMode mode;
  final GameDayRunCopy copy;

  const GameDayRunBannerView({
    super.key,
    required this.mode,
    required this.copy,
  });

  @override
  Widget build(BuildContext context) {
    final (IconData icon, Color tint) = switch (mode) {
      GameDayRunMode.server => (Icons.cloud_done_outlined, NexGenPalette.cyan),
      GameDayRunMode.phone => (Icons.phone_iphone, NexGenPalette.textMedium),
      GameDayRunMode.blocked => (Icons.pending_outlined, NexGenPalette.amber),
    };
    return Semantics(
      container: true,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: tint.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(icon, size: 18, color: tint),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    copy.title,
                    style: TextStyle(
                      color: mode == GameDayRunMode.phone
                          ? NexGenPalette.textHigh
                          : tint,
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            for (final l in copy.lines) ...[
              const SizedBox(height: 6),
              Text(
                l,
                style: const TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 13,
                  height: 1.35,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// A team card's game-status chip. Live and final are reports of fact; only
/// the UPCOMING text says who will run it (server / phone / setup needed).
class GameDayStatusBadge extends StatelessWidget {
  final bool isLive;
  final bool isFinal;
  final String liveText;
  final String finalText;
  final GameDayRunMode mode;

  const GameDayStatusBadge({
    super.key,
    required this.isLive,
    required this.isFinal,
    required this.liveText,
    required this.finalText,
    required this.mode,
  });

  @override
  Widget build(BuildContext context) {
    final muted = isFinal || (!isLive && mode == GameDayRunMode.blocked);
    final Color tint = isLive
        ? Colors.green
        : muted
            ? NexGenPalette.textMedium
            : NexGenPalette.cyan;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: tint.withValues(alpha: isLive ? 0.2 : 0.15),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: tint.withValues(alpha: isLive ? 0.4 : 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isLive) ...[
            Container(
              width: 6,
              height: 6,
              decoration: const BoxDecoration(
                color: Colors.green,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: 6),
          ],
          Text(
            isLive
                ? liveText
                : isFinal
                    ? finalText
                    : upcomingBadgeLabel(mode),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w600,
              color: tint,
            ),
          ),
        ],
      ),
    );
  }
}

