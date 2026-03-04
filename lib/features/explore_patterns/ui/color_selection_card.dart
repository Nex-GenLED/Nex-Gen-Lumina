import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/explore_patterns/ui/explore_design_system.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';

/// A card for selecting a solid color in the Explore Patterns grid.
///
/// Features a radial gradient fill matching the color, a large glowing
/// color circle, color name, hex code, selected state animation,
/// and long-press to copy hex.
class ColorSelectionCard extends ConsumerStatefulWidget {
  final Color color;
  final String name;
  final int index;
  final bool isSelected;
  final VoidCallback? onTap;

  /// Optional WLED payload for direct apply. If null, builds a solid color payload.
  final Map<String, dynamic>? wledPayload;

  const ColorSelectionCard({
    super.key,
    required this.color,
    required this.name,
    this.index = 0,
    this.isSelected = false,
    this.onTap,
    this.wledPayload,
  });

  @override
  ConsumerState<ColorSelectionCard> createState() => _ColorSelectionCardState();
}

class _ColorSelectionCardState extends ConsumerState<ColorSelectionCard> {
  int _to255(double v) => (v * 255.0).round().clamp(0, 255);

  String _colorToHex(Color c) {
    return '#${_to255(c.r).toRadixString(16).padLeft(2, '0')}'
        '${_to255(c.g).toRadixString(16).padLeft(2, '0')}'
        '${_to255(c.b).toRadixString(16).padLeft(2, '0')}'.toUpperCase();
  }

  void _copyHex() {
    final hex = _colorToHex(widget.color);
    Clipboard.setData(ClipboardData(text: hex));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Copied $hex'),
          duration: const Duration(seconds: 1),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _applyColor() async {
    final shouldProceed =
        await SyncWarningDialog.checkAndProceed(context, ref);
    if (!shouldProceed) return;

    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No device connected')),
        );
      }
      return;
    }

    try {
      final r = _to255(widget.color.r);
      final g = _to255(widget.color.g);
      final b = _to255(widget.color.b);

      if (widget.wledPayload != null) {
        var payload = widget.wledPayload!;
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) {
          payload = applyChannelFilter(
              payload, channels, ref.read(deviceChannelsProvider));
        }
        final success = await repo.applyJson(payload);
        if (!success) throw Exception('Device did not accept command');
      } else {
        // Build a simple solid color payload
        final payload = <String, dynamic>{
          'seg': [
            {
              'col': [
                [r, g, b, 0]
              ],
              'fx': 0,
              'sx': 128,
              'ix': 128,
            }
          ],
        };
        var finalPayload = payload;
        final channels = ref.read(effectiveChannelIdsProvider);
        if (channels.isNotEmpty) {
          finalPayload = applyChannelFilter(
              finalPayload, channels, ref.read(deviceChannelsProvider));
        }
        final success = await repo.applyJson(finalPayload);
        if (!success) throw Exception('Device did not accept command');
      }

      // Update preview
      try {
        ref.read(wledStateProvider.notifier).applyLocalPreview(
              colors: [widget.color],
              effectId: 0,
              speed: 128,
              intensity: 128,
              effectName: widget.name,
            );
      } catch (_) {}
      ref.read(activePresetLabelProvider.notifier).state = widget.name;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Applied: ${widget.name}'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to apply color: $e'),
            backgroundColor: Colors.red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final hex = _colorToHex(widget.color);

    // Staggered entrance: 40ms per card
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 350 + widget.index * 40),
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
      child: AnimatedScale(
        scale: widget.isSelected ? 1.03 : 1.0,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOutCubic,
        child: LuminaGlassCard(
          glowColor: widget.color,
          glowIntensity: 0.25,
          animate: false,
          child: GestureDetector(
            onTap: () {
              widget.onTap?.call();
              _applyColor();
            },
            onLongPress: _copyHex,
            child: Stack(
              children: [
                // Full card radial gradient fill
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      gradient: RadialGradient(
                        center: const Alignment(0, -0.3),
                        radius: 1.2,
                        colors: [
                          widget.color.withValues(alpha: 0.35),
                          widget.color.withValues(alpha: 0.08),
                          Colors.transparent,
                        ],
                        stops: const [0.0, 0.5, 1.0],
                      ),
                    ),
                  ),
                ),

                // Content
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Top spacer
                    const Spacer(flex: 2),

                    // Large color circle
                    Container(
                      width: 56,
                      height: 56,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.7),
                            blurRadius: 32,
                            spreadRadius: 4,
                          ),
                        ],
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.2),
                          width: 1.5,
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Color name
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      child: Text(
                        widget.name,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                      ),
                    ),

                    const SizedBox(height: 2),

                    // Hex code
                    Text(
                      hex,
                      style: TextStyle(
                        color: ExploreDesignTokens.textMuted,
                        fontSize: 10,
                        fontFamily: 'monospace',
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),

                    const Spacer(flex: 3),
                  ],
                ),

                // Selected state: animated border
                if (widget.isSelected)
                  Positioned.fill(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: widget.color,
                          width: 2,
                        ),
                      ),
                    ),
                  ),

                // Selected state: checkmark
                if (widget.isSelected)
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      width: 22,
                      height: 22,
                      decoration: BoxDecoration(
                        color: widget.color,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: widget.color.withValues(alpha: 0.5),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.check,
                        size: 14,
                        color: Colors.white,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
