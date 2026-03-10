import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/theme.dart';

/// A speed slider that uses per-effect speed profiles for non-linear mapping.
///
/// Instead of a dumb 0-255 linear slider, this widget:
///  - Maps slider travel through a logarithmic or ease-out curve
///  - Constrains the range to the effect's usable speed window
///  - Shows a human-readable speed label instead of raw numbers
///  - Offers an "extended range" toggle at the far-right end
class EffectSpeedSlider extends StatefulWidget {
  /// Current raw WLED speed value (0-255).
  final int rawSpeed;

  /// WLED effect ID — determines which speed profile to use.
  final int effectId;

  /// Called with the new raw speed value when the user drags the slider.
  final ValueChanged<int> onChanged;

  /// If true, the slider starts in extended-range mode.
  /// Typically set when loading a saved pattern whose speed exceeds
  /// the profile's recommendedMax.
  final bool initialExtended;

  const EffectSpeedSlider({
    super.key,
    required this.rawSpeed,
    required this.effectId,
    required this.onChanged,
    this.initialExtended = false,
  });

  @override
  State<EffectSpeedSlider> createState() => _EffectSpeedSliderState();
}

class _EffectSpeedSliderState extends State<EffectSpeedSlider> {
  late bool _extended;

  @override
  void initState() {
    super.initState();
    _extended = widget.initialExtended;
  }

  @override
  void didUpdateWidget(EffectSpeedSlider old) {
    super.didUpdateWidget(old);
    // When the effect changes, reset extended mode
    if (old.effectId != widget.effectId) {
      _extended = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final profile = getSpeedProfile(widget.effectId);
    final mapping = profile.mapRawToSlider(widget.rawSpeed);

    // Auto-enter extended mode if saved speed requires it
    if (mapping.needsExtended && !_extended) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _extended = true);
      });
    }

    final sliderPos = _extended || !mapping.needsExtended
        ? mapping.position
        : 1.0; // Clamp at max if in standard mode but speed is high

    final label = profile.speedLabel(sliderPos, extended: _extended);
    final isInExtended = _extended && sliderPos > 0.95;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label row
          Row(
            children: [
              SizedBox(
                width: 70,
                child: Text(
                  'Speed',
                  style: TextStyle(
                    color: NexGenPalette.textSecondary,
                    fontSize: 13,
                  ),
                ),
              ),
              const Spacer(),
              // Contextual speed label
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 150),
                child: Row(
                  key: ValueKey('$label-$isInExtended'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (isInExtended) ...[
                      const Text(
                        '\u26A1 ',
                        style: TextStyle(fontSize: 11),
                      ),
                    ],
                    Text(
                      label,
                      style: TextStyle(
                        color: isInExtended
                            ? Colors.amber
                            : NexGenPalette.textMedium,
                        fontSize: 12,
                        fontWeight:
                            isInExtended ? FontWeight.w600 : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 4),
              // Extended range toggle
              GestureDetector(
                onTap: () => setState(() => _extended = !_extended),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: _extended
                        ? Colors.amber.withValues(alpha: 0.2)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: _extended
                          ? Colors.amber.withValues(alpha: 0.6)
                          : NexGenPalette.line,
                    ),
                  ),
                  child: Text(
                    _extended ? '\u26A1 Fast' : '+',
                    style: TextStyle(
                      color: _extended ? Colors.amber : NexGenPalette.textSecondary,
                      fontSize: 10,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          // Slider
          Row(
            children: [
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor:
                        _extended ? Colors.amber : NexGenPalette.cyan,
                    inactiveTrackColor: NexGenPalette.trackDark,
                    thumbColor:
                        _extended ? Colors.amber : NexGenPalette.cyan,
                    overlayColor: (_extended ? Colors.amber : NexGenPalette.cyan)
                        .withValues(alpha: 0.2),
                    trackHeight: 4,
                  ),
                  child: Slider(
                    value: sliderPos.clamp(0.0, 1.0),
                    min: 0.0,
                    max: 1.0,
                    onChanged: (v) {
                      final raw =
                          profile.mapSliderToRaw(v, extended: _extended);
                      widget.onChanged(raw);
                    },
                  ),
                ),
              ),
            ],
          ),
          // Effect-specific hint
          if (profile.label.isNotEmpty)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 0, bottom: 2),
                child: Text(
                  profile.label,
                  style: TextStyle(
                    color: NexGenPalette.textSecondary.withValues(alpha: 0.6),
                    fontSize: 10,
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
