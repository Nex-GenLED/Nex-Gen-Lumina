import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';

/// Speed selector with Slow/Medium/Fast chips and a fine-grained slider.
///
/// Only visible when the current effect is not static — the parent
/// [LuminaAdjustmentPanel] handles the AnimatedCrossFade wrapper.
class SpeedAdjustmentCard extends ConsumerWidget {
  const SpeedAdjustmentCard({super.key});

  static const _presets = <(String, double)>[
    ('Slow', 0.15),
    ('Medium', 0.50),
    ('Fast', 0.85),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    if (adjState == null) return const SizedBox.shrink();

    final speed = adjState.currentSuggestion.speed ?? 0.5;
    final activeLabel = EffectInfo.speedLabel(speed);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Chips row
        Row(
          children: _presets.map((preset) {
            final isActive = preset.$1 == activeLabel;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: GestureDetector(
                onTap: () => ref
                    .read(adjustmentStateProvider.notifier)
                    .updateSpeed(preset.$2),
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
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
                    preset.$1,
                    style: TextStyle(
                      fontSize: 12,
                      color: isActive
                          ? NexGenPalette.cyan
                          : NexGenPalette.textMedium,
                      fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 6),
        // Fine-grained slider
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.7),
            inactiveTrackColor: NexGenPalette.trackDark,
            thumbColor: NexGenPalette.cyan,
            overlayColor: NexGenPalette.cyan.withValues(alpha: 0.12),
          ),
          child: Slider(
            value: speed,
            min: 0.0,
            max: 1.0,
            onChanged: (v) {
              ref.read(adjustmentStateProvider.notifier).updateSpeed(v);
            },
          ),
        ),
      ],
    );
  }
}
