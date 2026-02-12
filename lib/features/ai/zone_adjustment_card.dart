import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/site/site_providers.dart';

/// Zone targeting chips populated from the user's device configuration.
///
/// Hidden entirely when there is only one zone option (typical in
/// residential single-controller setups).
class ZoneAdjustmentCard extends ConsumerWidget {
  const ZoneAdjustmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    if (adjState == null) return const SizedBox.shrink();

    final zones = ref.watch(zonesProvider);
    // Hide if there are no configured zones — nothing to switch between
    if (zones.isEmpty) return const SizedBox.shrink();

    final currentZone = adjState.currentSuggestion.zone;

    // Build chip list: "All Zones" first, then each configured zone
    final chips = <_ZoneChipData>[
      _ZoneChipData(
        label: 'All Zones',
        zone: ZoneInfo.allZones,
        isActive: currentZone.name == 'All Zones',
      ),
      ...zones.map((z) => _ZoneChipData(
            label: z.name,
            zone: ZoneInfo(id: z.primaryIp, name: z.name),
            isActive: currentZone.name == z.name,
          )),
    ];

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: chips.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final chip = chips[i];
          return GestureDetector(
            onTap: () => ref
                .read(adjustmentStateProvider.notifier)
                .updateZone(chip.zone),
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: chip.isActive
                    ? NexGenPalette.cyan.withValues(alpha: 0.15)
                    : NexGenPalette.gunmetal,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: chip.isActive
                      ? NexGenPalette.cyan.withValues(alpha: 0.5)
                      : NexGenPalette.line,
                ),
              ),
              child: Text(
                chip.label,
                style: TextStyle(
                  fontSize: 12,
                  color: chip.isActive
                      ? NexGenPalette.cyan
                      : NexGenPalette.textMedium,
                  fontWeight:
                      chip.isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ZoneChipData {
  final String label;
  final ZoneInfo zone;
  final bool isActive;
  const _ZoneChipData({
    required this.label,
    required this.zone,
    required this.isActive,
  });
}
