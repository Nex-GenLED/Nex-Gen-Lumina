import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/light_effect_animator.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';

/// Horizontally scrollable effect type chips for the adjustment panel.
///
/// Uses [WledEffectsCatalog.topPicks] (10 curated effects) so the list
/// is data-driven and consistent with the rest of the app.
class EffectAdjustmentCard extends ConsumerWidget {
  const EffectAdjustmentCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    if (adjState == null) return const SizedBox.shrink();

    final currentId = adjState.currentSuggestion.effect.id;
    final effects = WledEffectsCatalog.topPicks;

    return SizedBox(
      height: 36,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: effects.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final fx = effects[i];
          final isActive = fx.id == currentId;

          return GestureDetector(
            onTap: () {
              final newEffect = EffectInfo(
                id: fx.id,
                name: fx.name,
                category: effectTypeFromWledId(fx.id),
              );
              ref
                  .read(adjustmentStateProvider.notifier)
                  .updateEffect(newEffect);
            },
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: isActive
                    ? NexGenPalette.cyan.withValues(alpha: 0.15)
                    : NexGenPalette.gunmetal,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isActive
                      ? NexGenPalette.cyan.withValues(alpha: 0.5)
                      : NexGenPalette.line,
                ),
              ),
              child: Text(
                fx.name,
                style: TextStyle(
                  fontSize: 12,
                  color:
                      isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
