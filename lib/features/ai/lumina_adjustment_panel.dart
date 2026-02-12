import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/light_preview_strip.dart';
import 'package:nexgen_command/features/ai/palette_adjustment_card.dart';
import 'package:nexgen_command/features/ai/effect_adjustment_card.dart';
import 'package:nexgen_command/features/ai/brightness_adjustment_card.dart';
import 'package:nexgen_command/features/ai/speed_adjustment_card.dart';
import 'package:nexgen_command/features/ai/zone_adjustment_card.dart';

/// The full adjustment panel that expands below a [LuminaResponseCard].
///
/// Contains 5 parameter cards (palette, effect, brightness, speed, zone),
/// a live preview strip, and an "Apply This" CTA. All state is managed by
/// [adjustmentStateProvider] — every tap or slider change instantly updates
/// the preview strip above.
class LuminaAdjustmentPanel extends ConsumerWidget {
  const LuminaAdjustmentPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final adjState = ref.watch(adjustmentStateProvider);
    final isExpanded = adjState?.isExpanded ?? false;

    return AnimatedSize(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOutCubic,
      alignment: Alignment.topCenter,
      child: isExpanded ? _buildPanel(context, ref, adjState!) : const SizedBox.shrink(),
    );
  }

  Widget _buildPanel(
      BuildContext context, WidgetRef ref, AdjustmentState adjState) {
    final s = adjState.currentSuggestion;
    final isStatic = s.effect.isStatic;

    return Container(
      margin: const EdgeInsets.only(top: 6),
      decoration: BoxDecoration(
        color: const Color(0xFF151B23),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: NexGenPalette.line.withValues(alpha: 0.5),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Accent line at top
          Container(
            height: 3,
            margin: const EdgeInsets.symmetric(horizontal: 40),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.25),
              borderRadius: const BorderRadius.vertical(
                  bottom: Radius.circular(2)),
            ),
          ),

          const SizedBox(height: 10),

          // Live preview strip
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: LightPreviewStrip(
              colors: s.colors,
              effectType: s.effect.category,
              speed: s.speed ?? 0.5,
              brightness: s.brightness,
              pixelCount: 20,
              height: 34,
              borderRadius: 10,
            ),
          ),

          const SizedBox(height: 8),

          // Palette
          _AdjustmentSection(
            title: 'Colors',
            child: const PaletteAdjustmentCard(),
          ),

          // Effect
          _AdjustmentSection(
            title: 'Effect',
            child: const EffectAdjustmentCard(),
          ),

          // Brightness
          _AdjustmentSection(
            title: 'Brightness',
            child: const BrightnessAdjustmentCard(),
          ),

          // Speed (conditionally visible)
          AnimatedCrossFade(
            firstChild: _AdjustmentSection(
              title: 'Speed',
              child: const SpeedAdjustmentCard(),
            ),
            secondChild: const SizedBox.shrink(),
            crossFadeState: isStatic
                ? CrossFadeState.showSecond
                : CrossFadeState.showFirst,
            duration: const Duration(milliseconds: 250),
            sizeCurve: Curves.easeOutCubic,
          ),

          // Zone
          _AdjustmentSection(
            title: 'Zone',
            child: const ZoneAdjustmentCard(),
          ),

          const SizedBox(height: 8),

          // Apply This CTA
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 12),
            child: SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () {
                  ref.read(adjustmentStateProvider.notifier).applyToDevice();
                },
                icon: const Icon(Icons.bolt_rounded, size: 18),
                label: const Text(
                  'Apply This',
                  style: TextStyle(fontWeight: FontWeight.w600),
                ),
                style: FilledButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                  elevation: 4,
                  shadowColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section wrapper
// ---------------------------------------------------------------------------

/// Consistent section wrapper with a muted title label.
class _AdjustmentSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _AdjustmentSection({
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 14, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: NexGenPalette.textMedium.withValues(alpha: 0.7),
              fontSize: 11,
              fontWeight: FontWeight.w600,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 6),
          child,
        ],
      ),
    );
  }
}
