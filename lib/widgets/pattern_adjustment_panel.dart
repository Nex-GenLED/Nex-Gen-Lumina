import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/patterns/color_sequence_builder.dart';
import 'package:nexgen_command/theme.dart';

/// Common WLED effects for the effect selector dropdown.
/// These are curated effects that work well and preserve custom color palettes.
const List<_EffectOption> _commonEffects = [
  _EffectOption(0, 'Solid', Icons.square_rounded),
  _EffectOption(2, 'Breathe', Icons.air),
  _EffectOption(1, 'Blink', Icons.flash_on),
  _EffectOption(3, 'Wipe', Icons.arrow_forward),
  _EffectOption(12, 'Theater Chase', Icons.theater_comedy),
  _EffectOption(41, 'Running', Icons.directions_run),
  _EffectOption(43, 'Twinkle', Icons.auto_awesome),
  _EffectOption(52, 'Fireworks', Icons.celebration),
  _EffectOption(65, 'Chase', Icons.double_arrow),
  _EffectOption(70, 'Twinkle Fox', Icons.pets),
  _EffectOption(72, 'Sparkle', Icons.star),
  _EffectOption(77, 'Meteor', Icons.rocket_launch),
  _EffectOption(95, 'Ripple', Icons.waves),
  _EffectOption(110, 'Flow', Icons.water),
  _EffectOption(37, 'Candle', Icons.local_fire_department),
];

class _EffectOption {
  final int id;
  final String name;
  final IconData icon;
  const _EffectOption(this.id, this.name, this.icon);
}

/// Reusable pattern adjustment panel with speed, intensity, direction, effect, and color controls.
///
/// This widget can be embedded in multiple places (home screen, explore patterns, etc.)
/// and provides real-time debounced updates to the connected WLED device.
class PatternAdjustmentPanel extends ConsumerStatefulWidget {
  /// Initial speed value (0-255)
  final int initialSpeed;
  /// Initial intensity value (0-255)
  final int initialIntensity;
  /// Initial direction (false = left-to-right, true = right-to-left)
  final bool initialReverse;
  /// Initial effect ID (WLED fx value)
  final int? initialEffectId;
  /// Initial colors for the color sequence builder (list of RGB arrays)
  final List<List<int>>? initialColors;
  /// Whether to show the color sequence builder
  final bool showColors;
  /// Whether to show pixel layout controls (grouping/spacing)
  final bool showPixelLayout;
  /// Whether to show the effect selector
  final bool showEffectSelector;
  /// Callback when any value changes (for external state tracking)
  final void Function(PatternAdjustmentValues values)? onChanged;

  const PatternAdjustmentPanel({
    super.key,
    this.initialSpeed = 128,
    this.initialIntensity = 128,
    this.initialReverse = false,
    this.initialEffectId,
    this.initialColors,
    this.showColors = true,
    this.showPixelLayout = false,
    this.showEffectSelector = true,
    this.onChanged,
  });

  @override
  ConsumerState<PatternAdjustmentPanel> createState() => _PatternAdjustmentPanelState();
}

/// Values container for adjustment panel state
class PatternAdjustmentValues {
  final int speed;
  final int intensity;
  final bool reverse;
  final int? effectId;
  final List<List<int>>? colors;
  final int grouping;
  final int spacing;

  const PatternAdjustmentValues({
    required this.speed,
    required this.intensity,
    required this.reverse,
    this.effectId,
    this.colors,
    this.grouping = 1,
    this.spacing = 0,
  });
}

class _PatternAdjustmentPanelState extends ConsumerState<PatternAdjustmentPanel> {
  late int _speed;
  late int _intensity;
  late bool _reverse;
  int? _effectId;
  late List<List<int>>? _colors;
  int _grouping = 1;
  int _spacing = 0;
  Timer? _debounce;
  Timer? _layoutDebounce;

  @override
  void initState() {
    super.initState();
    _speed = widget.initialSpeed;
    _intensity = widget.initialIntensity;
    _reverse = widget.initialReverse;
    _effectId = widget.initialEffectId;
    _colors = widget.initialColors;
  }

  @override
  void didUpdateWidget(covariant PatternAdjustmentPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Update values if the widget is rebuilt with new initial values
    if (oldWidget.initialSpeed != widget.initialSpeed) {
      _speed = widget.initialSpeed;
    }
    if (oldWidget.initialIntensity != widget.initialIntensity) {
      _intensity = widget.initialIntensity;
    }
    if (oldWidget.initialReverse != widget.initialReverse) {
      _reverse = widget.initialReverse;
    }
    if (oldWidget.initialEffectId != widget.initialEffectId) {
      _effectId = widget.initialEffectId;
    }
    if (oldWidget.initialColors != widget.initialColors) {
      _colors = widget.initialColors;
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _layoutDebounce?.cancel();
    super.dispose();
  }

  void _notifyChanged() {
    widget.onChanged?.call(PatternAdjustmentValues(
      speed: _speed,
      intensity: _intensity,
      reverse: _reverse,
      effectId: _effectId,
      colors: _colors,
      grouping: _grouping,
      spacing: _spacing,
    ));
  }

  Future<void> _applyEffect(int effectId) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return;
    try {
      await repo.applyJson({
        'seg': [
          {'fx': effectId}
        ]
      });
    } catch (e) {
      debugPrint('PatternAdjustmentPanel effect apply failed: $e');
    }
  }

  void _scheduleDebouncedApply() {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 200), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;
      try {
        await repo.applyJson({
          'seg': [
            {
              'sx': _speed,
              'ix': _intensity,
              'rev': _reverse,
            }
          ]
        });
      } catch (e) {
        debugPrint('PatternAdjustmentPanel apply failed: $e');
      }
    });
  }

  void _scheduleDebouncedLayoutApply() {
    _layoutDebounce?.cancel();
    _layoutDebounce = Timer(const Duration(milliseconds: 180), () async {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;
      try {
        await repo.applyJson({
          'seg': [
            {
              'gp': _grouping,
              'sp': _spacing,
            }
          ]
        });
      } catch (e) {
        debugPrint('PatternAdjustmentPanel layout apply failed: $e');
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wledStateProvider);
    final isConnected = state.connected;

    return IgnorePointer(
      ignoring: !isConnected,
      child: Opacity(
        opacity: isConnected ? 1.0 : 0.5,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Speed slider
            _SliderRow(
              icon: Icons.speed,
              label: 'Speed',
              value: _speed.toDouble(),
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => _speed = v.round().clamp(0, 255));
                _notifyChanged();
                _scheduleDebouncedApply();
              },
              displayValue: '$_speed',
            ),
            const SizedBox(height: 8),
            // Intensity slider
            _SliderRow(
              icon: Icons.local_fire_department,
              label: 'Intensity',
              value: _intensity.toDouble(),
              min: 0,
              max: 255,
              onChanged: (v) {
                setState(() => _intensity = v.round().clamp(0, 255));
                _notifyChanged();
                _scheduleDebouncedApply();
              },
              displayValue: '$_intensity',
            ),
            const SizedBox(height: 10),
            // Direction toggle
            Row(
              children: [
                const Icon(Icons.swap_horiz, color: NexGenPalette.cyan, size: 20),
                const SizedBox(width: 8),
                Text('Direction', style: Theme.of(context).textTheme.labelLarge),
                const Spacer(),
                SegmentedButton<bool>(
                  segments: const [
                    ButtonSegment(value: false, label: Text('L→R')),
                    ButtonSegment(value: true, label: Text('R→L')),
                  ],
                  selected: {_reverse},
                  onSelectionChanged: (s) {
                    final rev = s.isNotEmpty ? s.first : false;
                    setState(() => _reverse = rev);
                    _notifyChanged();
                    _scheduleDebouncedApply();
                  },
                  style: ButtonStyle(
                    visualDensity: VisualDensity.compact,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            // Effect selector (optional)
            if (widget.showEffectSelector) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.auto_awesome, color: NexGenPalette.cyan, size: 20),
                  const SizedBox(width: 8),
                  Text('Effect', style: Theme.of(context).textTheme.labelLarge),
                  const Spacer(),
                  Container(
                    constraints: const BoxConstraints(maxWidth: 180),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<int>(
                        value: _effectId != null && _commonEffects.any((e) => e.id == _effectId)
                            ? _effectId
                            : null,
                        hint: Text('Select effect', style: TextStyle(color: Colors.white.withValues(alpha: 0.7))),
                        dropdownColor: const Color(0xFF1E1E2E),
                        icon: const Icon(Icons.arrow_drop_down, color: NexGenPalette.cyan),
                        isExpanded: true,
                        borderRadius: BorderRadius.circular(12),
                        items: _commonEffects.map((effect) {
                          final wledEffect = WledEffectsCatalog.getById(effect.id);
                          final behavior = wledEffect?.colorBehavior;
                          final behaviorColor = behavior != null ? _colorForBehavior(behavior) : null;
                          return DropdownMenuItem<int>(
                            value: effect.id,
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(effect.icon, size: 18, color: NexGenPalette.cyan),
                                const SizedBox(width: 8),
                                Flexible(
                                  child: Text(
                                    effect.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                ),
                                // Color behavior indicator
                                if (behavior != null) ...[
                                  const SizedBox(width: 6),
                                  Tooltip(
                                    message: behavior.description,
                                    child: Icon(
                                      _iconForBehavior(behavior),
                                      size: 14,
                                      color: behaviorColor,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (effectId) {
                          if (effectId == null) return;
                          setState(() => _effectId = effectId);
                          _notifyChanged();
                          _applyEffect(effectId);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ],
            // Pixel Layout section (optional)
            if (widget.showPixelLayout) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.grid_view, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text('Pixel Layout', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              _SliderRow(
                icon: Icons.blur_on,
                label: 'Grouping',
                value: _grouping.toDouble(),
                min: 1,
                max: 10,
                divisions: 9,
                onChanged: (v) {
                  setState(() => _grouping = v.round().clamp(1, 10));
                  _notifyChanged();
                  _scheduleDebouncedLayoutApply();
                },
                displayValue: '$_grouping',
              ),
              const SizedBox(height: 6),
              _SliderRow(
                icon: Icons.space_bar,
                label: 'Spacing',
                value: _spacing.toDouble(),
                min: 0,
                max: 10,
                divisions: 10,
                onChanged: (v) {
                  setState(() => _spacing = v.round().clamp(0, 10));
                  _notifyChanged();
                  _scheduleDebouncedLayoutApply();
                },
                displayValue: '$_spacing',
              ),
            ],
            // Color Sequence Builder (optional)
            if (widget.showColors && _colors != null && _colors!.isNotEmpty) ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  const Icon(Icons.palette, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Text('Color Sequence', style: Theme.of(context).textTheme.titleSmall),
                ],
              ),
              const SizedBox(height: 8),
              Builder(builder: (context) {
                // Deduplicate base colors
                final seen = <String>{};
                final baseColors = <List<int>>[];
                for (final rgb in _colors!) {
                  if (rgb.length < 3) continue;
                  final key = '${rgb[0]}-${rgb[1]}-${rgb[2]}';
                  if (seen.add(key)) baseColors.add([rgb[0], rgb[1], rgb[2]]);
                }
                return ColorSequenceBuilder(
                  baseColors: baseColors.isNotEmpty ? baseColors : _colors!,
                  initialSequence: _colors!,
                  onChanged: (seq) async {
                    final repo = ref.read(wledRepositoryProvider);
                    if (repo == null) return;
                    try {
                      await repo.applyJson({
                        'seg': [
                          {'col': seq}
                        ]
                      });
                    } catch (e) {
                      debugPrint('Apply custom palette failed: $e');
                    }
                  },
                );
              }),
            ],
          ],
        ),
      ),
    );
  }
}

/// Helper widget for consistent slider rows
class _SliderRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
  final ValueChanged<double> onChanged;
  final String displayValue;

  const _SliderRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    this.divisions,
    required this.onChanged,
    required this.displayValue,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 8),
        SizedBox(
          width: 60,
          child: Text(label, style: Theme.of(context).textTheme.labelMedium),
        ),
        Expanded(
          child: SliderTheme(
            data: Theme.of(context).sliderTheme.copyWith(trackHeight: 4),
            child: Slider(
              value: value,
              min: min,
              max: max,
              divisions: divisions,
              onChanged: onChanged,
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withValues(alpha: 0.2),
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 32,
          child: Text(displayValue, style: Theme.of(context).textTheme.labelLarge, textAlign: TextAlign.right),
        ),
      ],
    );
  }
}

// Helper functions for color behavior display
IconData _iconForBehavior(ColorBehavior behavior) {
  switch (behavior) {
    case ColorBehavior.usesSelectedColors:
      return Icons.palette_outlined;
    case ColorBehavior.blendsSelectedColors:
      return Icons.gradient;
    case ColorBehavior.generatesOwnColors:
      return Icons.auto_awesome;
    case ColorBehavior.usesPalette:
      return Icons.color_lens_outlined;
  }
}

Color _colorForBehavior(ColorBehavior behavior) {
  switch (behavior) {
    case ColorBehavior.usesSelectedColors:
      return NexGenPalette.cyan;
    case ColorBehavior.blendsSelectedColors:
      return const Color(0xFF64B5F6);
    case ColorBehavior.generatesOwnColors:
      return const Color(0xFFFFB74D);
    case ColorBehavior.usesPalette:
      return const Color(0xFFBA68C8);
  }
}
