import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';

/// Brightness slider + quick-preset chips for the adjustment panel.
class BrightnessAdjustmentCard extends ConsumerWidget {
  const BrightnessAdjustmentCard({super.key});

  static const _presets = [0.25, 0.50, 0.75, 1.0];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    if (adjState == null) return const SizedBox.shrink();

    final brightness = adjState.currentSuggestion.brightness;
    final pct = (brightness * 100).round();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Slider row with percentage label
        Row(
          children: [
            Expanded(
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 4,
                  thumbShape: const RoundSliderThumbShape(
                      enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(
                      overlayRadius: 16),
                  activeTrackColor: NexGenPalette.cyan,
                  inactiveTrackColor: NexGenPalette.trackDark,
                  thumbColor: NexGenPalette.cyan,
                  overlayColor: NexGenPalette.cyan.withValues(alpha: 0.15),
                ),
                child: Slider(
                  value: brightness,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    ref
                        .read(adjustmentStateProvider.notifier)
                        .updateBrightness(v);
                  },
                ),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 38,
              child: Text(
                '$pct%',
                textAlign: TextAlign.right,
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 13,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        // Quick preset chips
        Row(
          children: _presets.map((preset) {
            final label = '${(preset * 100).round()}%';
            final isActive = (brightness - preset).abs() < 0.03;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _QuickChip(
                label: label,
                isActive: isActive,
                onTap: () => ref
                    .read(adjustmentStateProvider.notifier)
                    .updateBrightness(preset),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }
}

/// Shared quick-chip used across adjustment cards.
class _QuickChip extends StatelessWidget {
  final String label;
  final bool isActive;
  final VoidCallback onTap;

  const _QuickChip({
    required this.label,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
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
          label,
          style: TextStyle(
            fontSize: 12,
            color: isActive ? NexGenPalette.cyan : NexGenPalette.textMedium,
            fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
          ),
        ),
      ),
    );
  }
}
