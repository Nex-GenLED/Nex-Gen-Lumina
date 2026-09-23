// lib/features/neighborhood/widgets/sync_fire_status_banner.dart
//
// Neighborhood Sync v1 — tells the initiator what happened at each house after
// a Start tap. Reads the fire the notifier recorded (lastSyncFireProvider) and
// polls its outcome (syncFireStatusProvider). Hidden until a crew fanout has
// returned a fireId, and again once the fire is older than the display window.
//
// Wording rule: the banner only ever states what the read-back shows. While
// the server is still waiting on a bridge it says "waiting"; when the callable
// cannot be reached it says "no confirmation" — never "done".

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../neighborhood_providers.dart';
import '../../../theme.dart';

/// A fire older than this is no longer shown (the street has moved on).
const Duration kSyncFireBannerWindow = Duration(minutes: 3);

class SyncFireStatusBanner extends ConsumerWidget {
  const SyncFireStatusBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fire = ref.watch(lastSyncFireProvider);
    if (fire == null) return const SizedBox.shrink();
    if (DateTime.now().difference(fire.startedAt) > kSyncFireBannerWindow) {
      return const SizedBox.shrink();
    }
    final status = ref.watch(syncFireStatusProvider(fire));
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: status.when(
        loading: () => const _Card(
          icon: Icons.hourglass_top,
          color: Colors.cyan,
          headline: 'Sent — waiting for houses to confirm…',
          notes: [],
        ),
        error: (_, __) => const _Card(
          icon: Icons.help_outline,
          color: Colors.orange,
          headline: 'Sent — no confirmation available',
          notes: ['Could not read the outcome from the server.'],
        ),
        data: (s) {
          if (s == null) {
            return const _Card(
              icon: Icons.help_outline,
              color: Colors.orange,
              headline: 'Sent — no confirmation available',
              notes: ['Could not read the outcome from the server.'],
            );
          }
          final allGood = s.settled && s.problemHouses == 0 && s.houses > 0;
          return _Card(
            icon: !s.settled
                ? Icons.hourglass_top
                : (allGood ? Icons.check_circle : Icons.warning_amber),
            color: !s.settled
                ? Colors.cyan
                : (allGood ? Colors.green : Colors.orange),
            headline: s.headline,
            notes: s.houseNotes,
          );
        },
      ),
    );
  }
}

class _Card extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String headline;
  final List<String> notes;

  const _Card({
    required this.icon,
    required this.color,
    required this.headline,
    required this.notes,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 18, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  headline,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          for (final n in notes)
            Padding(
              padding: const EdgeInsets.only(left: 26, top: 4),
              child: Text(
                n,
                style: TextStyle(color: Colors.grey.shade400, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }
}
