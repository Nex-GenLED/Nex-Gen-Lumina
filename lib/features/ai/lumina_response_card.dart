import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/light_preview_strip.dart';
import 'package:nexgen_command/features/ai/lumina_lighting_suggestion.dart';
import 'package:nexgen_command/features/ai/parameter_summary_row.dart';
import 'package:nexgen_command/features/ai/adjustment_state_controller.dart';
import 'package:nexgen_command/features/ai/lumina_adjustment_panel.dart';

/// A cohesive response card for the Lumina conversation thread.
///
/// Displays:
///  1. Lumina's verbal response text
///  2. Animated LED preview strip (showing the actual proposed effect)
///  3. Transparent parameter summary (palette, effect, brightness, speed, zone)
///  4. Action buttons: Apply, Adjust, Save as Favorite
///  5. Expandable [LuminaAdjustmentPanel] for inline parameter fine-tuning
///
/// When an adjustment session is active, the preview strip and parameter
/// summary read from [adjustmentStateProvider] for real-time updates.
class LuminaResponseCard extends ConsumerStatefulWidget {
  /// The lighting suggestion to display.
  final LuminaLightingSuggestion suggestion;

  /// Called when the user taps "Apply".
  final VoidCallback? onApply;

  /// Called when the user taps "Adjust" to expand inline controls.
  final VoidCallback? onAdjust;

  /// Called when the user taps "Save as Favorite".
  final VoidCallback? onSaveFavorite;

  const LuminaResponseCard({
    super.key,
    required this.suggestion,
    this.onApply,
    this.onAdjust,
    this.onSaveFavorite,
  });

  @override
  ConsumerState<LuminaResponseCard> createState() =>
      _LuminaResponseCardState();
}

class _LuminaResponseCardState extends ConsumerState<LuminaResponseCard> {
  /// The active suggestion — reads from adjustment state when active,
  /// otherwise falls back to the widget's original suggestion.
  LuminaLightingSuggestion get _s {
    final adj = ref.watch(adjustmentStateProvider);
    if (adj != null && adj.isExpanded) {
      return adj.currentSuggestion;
    }
    return widget.suggestion;
  }

  bool get _isAdjusting {
    final adj = ref.watch(adjustmentStateProvider);
    return adj?.isExpanded ?? false;
  }

  /// The set of user-changed params (for highlight indicators).
  Set<String> get _changedParams {
    final adj = ref.watch(adjustmentStateProvider);
    if (adj != null && adj.isExpanded) {
      return adj.userChangedParams;
    }
    return _s.changedParams;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 520),
      decoration: BoxDecoration(
        color: const Color(0xFF151B23),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: NexGenPalette.line.withValues(alpha: 0.6),
          width: 0.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ---- 1. Response text ----
          _buildResponseText(context),

          // ---- 2. LED preview strip ----
          _buildPreviewStrip(),

          // ---- 3. Parameter summary ----
          _buildParameterSummary(context),

          // ---- 4. Action buttons ----
          _buildActions(context),

          // ---- 5. Adjustment panel (expands/collapses) ----
          const LuminaAdjustmentPanel(),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 1. Response text
  // ---------------------------------------------------------------------------

  Widget _buildResponseText(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 10),
      child: Text(
        widget.suggestion.responseText,
        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: NexGenPalette.textHigh,
              height: 1.4,
            ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 2. Preview strip
  // ---------------------------------------------------------------------------

  Widget _buildPreviewStrip() {
    final s = _s;
    if (s.colors.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      child: LightPreviewStrip(
        colors: s.colors,
        effectType: s.effect.category,
        speed: s.speed ?? 0.5,
        brightness: s.brightness,
        pixelCount: 20,
        height: 36,
        borderRadius: 10,
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 3. Parameter summary
  // ---------------------------------------------------------------------------

  Widget _buildParameterSummary(BuildContext context) {
    final s = _s;
    final changed = _changedParams;

    // Build palette value — prefer color names, fall back to palette name
    final paletteValue = s.palette.colorNames.isNotEmpty
        ? s.palette.colorNames.join(', ')
        : s.palette.name;

    // Brightness as percentage
    final briPercent = '${(s.brightness * 100).round()}%';

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 4),
      child: Column(
        children: [
          // Subtle separator
          Container(
            height: 0.5,
            color: NexGenPalette.line.withValues(alpha: 0.4),
            margin: const EdgeInsets.only(bottom: 8),
          ),

          ParameterSummaryRow(
            label: 'Palette',
            value: paletteValue,
            changed: changed.contains('palette'),
          ),
          ParameterSummaryRow(
            label: 'Effect',
            value: s.effect.name,
            changed: changed.contains('effect'),
          ),
          ParameterSummaryRow(
            label: 'Brightness',
            value: briPercent,
            changed: changed.contains('brightness'),
            trailing: BrightnessBarIndicator(value: s.brightness),
          ),
          // Speed — only shown for non-static effects
          if (s.speed != null && !s.effect.isStatic)
            ParameterSummaryRow(
              label: 'Speed',
              value: EffectInfo.speedLabel(s.speed!),
              changed: changed.contains('speed'),
            ),
          ParameterSummaryRow(
            label: 'Zone',
            value: s.zone.name,
            changed: changed.contains('zone'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 4. Actions
  // ---------------------------------------------------------------------------

  Widget _buildActions(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Primary action row
          Row(
            children: [
              if (widget.onApply != null)
                _CardActionButton(
                  label: 'Apply',
                  icon: Icons.bolt_rounded,
                  primary: true,
                  onTap: widget.onApply!,
                ),
              const SizedBox(width: 8),
              _CardActionButton(
                label: _isAdjusting ? 'Done' : 'Adjust',
                icon: Icons.tune_rounded,
                onTap: _toggleAdjust,
              ),
            ],
          ),

          // Save as favorite link
          if (widget.onSaveFavorite != null) ...[
            const SizedBox(height: 6),
            GestureDetector(
              onTap: widget.onSaveFavorite,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.favorite_border_rounded,
                      size: 14,
                      color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'Save as Favorite',
                      style: TextStyle(
                        fontSize: 12,
                        color:
                            NexGenPalette.textMedium.withValues(alpha: 0.6),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  void _toggleAdjust() {
    final adj = ref.read(adjustmentStateProvider);
    if (adj != null && adj.isExpanded) {
      ref.read(adjustmentStateProvider.notifier).collapse();
    } else {
      ref.read(adjustmentStateProvider.notifier).beginAdjustment(
            widget.suggestion,
          );
    }
    widget.onAdjust?.call();
  }
}

// =============================================================================
// Card action button (private)
// =============================================================================

class _CardActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool primary;

  const _CardActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.primary = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: primary
                ? NexGenPalette.cyan.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: primary
                  ? NexGenPalette.cyan.withValues(alpha: 0.5)
                  : NexGenPalette.line.withValues(alpha: 0.6),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                icon,
                size: 16,
                color: primary ? NexGenPalette.cyan : NexGenPalette.textMedium,
              ),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: primary ? NexGenPalette.cyan : NexGenPalette.textHigh,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
