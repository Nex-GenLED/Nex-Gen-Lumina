import 'dart:math' show sin, pi;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/wled_models.dart' show kEffectNames;
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/features/wled/pattern_explore_screen.dart'
    show executeCustomEffectIfNeeded;

/// Redesigned pattern card for the Explore Patterns grid.
///
/// Features a color preview area with simulated LED dots, a color strip,
/// pattern info, and a compact Apply button.
class ExplorePatternCard extends ConsumerWidget {
  final PatternItem pattern;
  final int index;

  const ExplorePatternCard({
    super.key,
    required this.pattern,
    this.index = 0,
  });

  // ── Color extraction helpers ──

  List<Color> _getColors() {
    try {
      final seg = pattern.wledPayload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <Color>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add(Color.fromARGB(
                  255,
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                ));
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (_) {}
    return [ExploreDesignTokens.accentBlue, ExploreDesignTokens.accentPurple];
  }

  int _getEffectId() {
    try {
      final seg = pattern.wledPayload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final fx = firstSeg['fx'];
          if (fx is int) return fx;
        }
      }
    } catch (_) {}
    return 0;
  }

  String? _getEffectName() {
    final effectId = _getEffectId();
    return kEffectNames[effectId];
  }

  bool get _isAnimated => _getEffectId() > 0;

  List<List<int>> _getColorsRgbw() {
    try {
      final seg = pattern.wledPayload['seg'];
      if (seg is List && seg.isNotEmpty) {
        final firstSeg = seg.first;
        if (firstSeg is Map) {
          final cols = firstSeg['col'];
          if (cols is List && cols.isNotEmpty) {
            final colors = <List<int>>[];
            for (final col in cols) {
              if (col is List && col.length >= 3) {
                colors.add([
                  (col[0] as num).toInt().clamp(0, 255),
                  (col[1] as num).toInt().clamp(0, 255),
                  (col[2] as num).toInt().clamp(0, 255),
                  col.length >= 4 ? (col[3] as num).toInt().clamp(0, 255) : 0,
                ]);
              }
            }
            if (colors.isNotEmpty) return colors;
          }
        }
      }
    } catch (_) {}
    return [[255, 255, 255, 0]];
  }

  /// Lighten a color by a factor (0.0 = unchanged, 1.0 = white)
  Color _lighten(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl
        .withLightness((hsl.lightness + amount).clamp(0.0, 1.0))
        .toColor();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = _getColors();
    final primaryColor = colors.first;
    final isAnimated = _isAnimated;

    // Staggered entrance: 40ms per card
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (context, value, child) {
        return Opacity(
          opacity: value.clamp(0.0, 1.0),
          child: Transform.translate(
            offset: Offset(0, 20 * (1 - value)),
            child: child,
          ),
        );
      },
      child: LuminaGlassCard(
        glowColor: primaryColor,
        glowIntensity: 0.18,
        onTap: () => _applyPattern(context, ref),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1. PREVIEW AREA
            ClipRRect(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(16)),
              child: SizedBox(
                height: 130,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    // Background fill
                    if (colors.length == 1)
                      Container(
                        decoration: BoxDecoration(
                          gradient: RadialGradient(
                            center: Alignment.center,
                            radius: 1.0,
                            colors: [
                              primaryColor.withValues(alpha: 0.9),
                              primaryColor.withValues(alpha: 0.4),
                              Colors.transparent,
                            ],
                            stops: const [0.0, 0.6, 1.0],
                          ),
                        ),
                      )
                    else
                      // Multi-color diagonal bands
                      Transform.rotate(
                        angle: -0.08, // subtle tilt
                        child: Column(
                          children: [
                            for (int i = 0; i < colors.length; i++)
                              Expanded(
                                child: Container(
                                  color: colors[i].withValues(alpha: 0.7),
                                ),
                              ),
                          ],
                        ),
                      ),
                    // Simulated LED dots
                    Center(
                      child: _LedDotsRow(colors: colors),
                    ),
                    // Animated badge
                    if (isAnimated)
                      Positioned(
                        left: 8,
                        bottom: 8,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: const Color(0xCC000000),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.bolt, size: 10, color: Colors.amber),
                              const SizedBox(width: 2),
                              Text(
                                'Animated',
                                style: TextStyle(
                                  color: ExploreDesignTokens.textSecondary,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),

            // 2. COLOR STRIP
            PatternColorStrip(colors: colors, height: 6),

            // 3. INFO AREA
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Pattern name
                    Text(
                      pattern.name,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Tags row
                    Row(
                      children: [
                        if (isAnimated)
                          _TagPill(label: 'Animated'),
                        if (_getEffectName() != null && !isAnimated)
                          _TagPill(label: 'Solid'),
                      ],
                    ),
                    const Spacer(),
                    // Bottom row: indicator + Apply button
                    Row(
                      children: [
                        if (isAnimated)
                          Icon(
                            Icons.bolt,
                            size: 14,
                            color: ExploreDesignTokens.textMuted,
                          ),
                        const Spacer(),
                        // Compact Apply button
                        _CompactApplyButton(
                          gradientColors: [
                            primaryColor,
                            _lighten(primaryColor, 0.3),
                          ],
                          onTap: () => _applyPattern(context, ref),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Apply logic (carried forward from PatternCard) ──

  Future<void> _applyPattern(BuildContext context, WidgetRef ref) async {
    final shouldProceed =
        await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      final effectId = _getEffectId();
      final colorsRgbw = _getColorsRgbw();

      final isCustomEffect = await executeCustomEffectIfNeeded(
        effectId: effectId,
        colors: colorsRgbw,
        repo: repo,
      );

      if (!isCustomEffect) {
        var payload = pattern.wledPayload;
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) {
          payload = applyChannelFilter(
              payload, channels, ref.read(deviceChannelsProvider));
        }
        final success = await repo.applyJson(payload);
        if (!success) throw Exception('Device did not accept command');
      }

      // Update preview
      try {
        final colors = _getColors();
        ref.read(wledStateProvider.notifier).applyLocalPreview(
              colors: colors,
              effectId: effectId,
              speed: pattern.wledPayload['seg'] is List &&
                      (pattern.wledPayload['seg'] as List).isNotEmpty
                  ? ((pattern.wledPayload['seg'] as List).first['sx']
                          as int?) ??
                      128
                  : 128,
              intensity: pattern.wledPayload['seg'] is List &&
                      (pattern.wledPayload['seg'] as List).isNotEmpty
                  ? ((pattern.wledPayload['seg'] as List).first['ix']
                          as int?) ??
                      128
                  : 128,
              effectName: pattern.name,
            );
      } catch (_) {}
      ref.read(activePresetLabelProvider.notifier).state = pattern.name;

      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied: ${pattern.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply pattern: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }
}

// ── LED dot visualization ──

class _LedDotsRow extends StatefulWidget {
  final List<Color> colors;
  const _LedDotsRow({required this.colors});

  @override
  State<_LedDotsRow> createState() => _LedDotsRowState();
}

class _LedDotsRowState extends State<_LedDotsRow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const dotCount = 5;
    const dotSize = 10.0;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(dotCount, (i) {
            final color = widget.colors[i % widget.colors.length];
            // Staggered sine wave: each dot offset by 0.15
            final phase = (_controller.value + i * 0.15) % 1.0;
            final sineValue = sin(phase * pi);
            final scale = 0.8 + 0.2 * sineValue;
            final blurRadius = 8.0 + 10.0 * sineValue;
            return Transform.scale(
              scale: scale,
              child: Container(
                width: dotSize,
                height: dotSize,
                decoration: BoxDecoration(
                  color: color,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(alpha: 0.8),
                      blurRadius: blurRadius,
                      spreadRadius: 3,
                    ),
                  ],
                ),
              ),
            );
          }),
        );
      },
    );
  }
}

// ── Tag pill chip ──

class _TagPill extends StatelessWidget {
  final String label;
  const _TagPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(right: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0x1AFFFFFF), // 10% white
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: ExploreDesignTokens.textSecondary,
          fontSize: 12,
        ),
      ),
    );
  }
}

// ── Compact Apply button with gradient ──

class _CompactApplyButton extends StatefulWidget {
  final List<Color> gradientColors;
  final VoidCallback onTap;
  const _CompactApplyButton({
    required this.gradientColors,
    required this.onTap,
  });

  @override
  State<_CompactApplyButton> createState() => _CompactApplyButtonState();
}

class _CompactApplyButtonState extends State<_CompactApplyButton> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) {
        setState(() => _pressed = false);
        widget.onTap();
      },
      onTapCancel: () => setState(() => _pressed = false),
      child: AnimatedScale(
        scale: _pressed ? 0.94 : 1.0,
        duration: const Duration(milliseconds: 100),
        child: Container(
          height: 40,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: widget.gradientColors),
            borderRadius: BorderRadius.circular(10),
            boxShadow: [
              BoxShadow(
                color: widget.gradientColors.first.withValues(alpha: 0.4),
                blurRadius: 12,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: const Center(
            child: Text(
              'Apply',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w600,
                fontSize: 13,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
