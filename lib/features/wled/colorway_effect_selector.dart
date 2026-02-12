import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/favorite_heart_button.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:go_router/go_router.dart';

/// Helper to convert RGB to RGBW format for WLED.
List<int> _rgbToRgbw(int r, int g, int b) => [r, g, b, 0];

/// Effect selector page that replaces the pattern grid.
/// Shows a large live preview with categorized effect list.
class ColorwayEffectSelectorPage extends ConsumerStatefulWidget {
  final LibraryNode paletteNode;

  const ColorwayEffectSelectorPage({
    super.key,
    required this.paletteNode,
  });

  @override
  ConsumerState<ColorwayEffectSelectorPage> createState() =>
      _ColorwayEffectSelectorPageState();
}

class _ColorwayEffectSelectorPageState
    extends ConsumerState<ColorwayEffectSelectorPage> {
  Timer? _debounceTimer;

  List<Color> get _paletteColors =>
      widget.paletteNode.themeColors ?? [Colors.white];

  @override
  void initState() {
    super.initState();
    // Initialize selector state with defaults
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectorEffectIdProvider.notifier).state = 0;
      ref.read(selectorSpeedProvider.notifier).state = 128;
      ref.read(selectorIntensityProvider.notifier).state = 128;
      ref.read(selectorColorGroupProvider.notifier).state = 1;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  void _sendToWled() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final effectId = ref.read(selectorEffectIdProvider);
      final speed = ref.read(selectorSpeedProvider);
      final intensity = ref.read(selectorIntensityProvider);
      final colorGroup = ref.read(selectorColorGroupProvider);
      final demoMode = ref.read(demoModeProvider);

      if (demoMode) return;

      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;

      // Build WLED payload
      final cols = _paletteColors
          .take(3)
          .map((c) => _rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()))
          .toList();
      if (cols.isEmpty) {
        cols.add([255, 255, 255, 0]);
      }

      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': effectId,
            'sx': speed,
            'ix': intensity,
            'pal': 5, // "Colors Only" palette
            'grp': colorGroup,
            'col': cols,
          }
        ]
      };

      await repo.applyJson(payload);
    });
  }

  Future<void> _applyPattern() async {
    final effectId = ref.read(selectorEffectIdProvider);
    final speed = ref.read(selectorSpeedProvider);
    final intensity = ref.read(selectorIntensityProvider);
    final colorGroup = ref.read(selectorColorGroupProvider);

    final effectName = WledEffectsCatalog.getName(effectId);
    final notifier = ref.read(wledStateProvider.notifier);
    final currentState = ref.read(wledStateProvider);
    bool appliedToDevice = false;

    // Try to send to device
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      final cols = _paletteColors
          .take(3)
          .map((c) => _rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round()))
          .toList();
      if (cols.isEmpty) {
        cols.add([255, 255, 255, 0]);
      }

      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': effectId,
            'sx': speed,
            'ix': intensity,
            'pal': 5,
            'grp': colorGroup,
            'col': cols,
          }
        ]
      };

      try {
        await repo.applyJson(payload);
        appliedToDevice = currentState.connected;
      } catch (e) {
        debugPrint('Pattern apply failed (device offline?): $e');
      }
    }

    // Always update local preview state so roofline shows on house image
    notifier.applyLocalPreview(
      colors: _paletteColors,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      effectName: '${widget.paletteNode.name} - $effectName',
    );

    // Show feedback with offline awareness
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            appliedToDevice
                ? 'Applied: $effectName'
                : 'Preview: $effectName (device offline)',
          ),
          duration: const Duration(seconds: 2),
          backgroundColor: appliedToDevice
              ? NexGenPalette.gunmetal
              : Colors.orange.shade800,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final effectId = ref.watch(selectorEffectIdProvider);
    final speed = ref.watch(selectorSpeedProvider);
    final intensity = ref.watch(selectorIntensityProvider);
    final colorGroup = ref.watch(selectorColorGroupProvider);
    final expandedMoods = ref.watch(selectorExpandedMoodsProvider);

    final effect = WledEffectsCatalog.getById(effectId);
    final showColorLayout = effect?.usesColorLayout ?? false;

    // This widget is embedded in the library browser, so no Scaffold needed
    return Column(
      children: [
        // Apply button row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              // Color palette preview
              Expanded(
                child: Row(
                  children: [
                    for (final color in _paletteColors.take(3))
                      Container(
                        width: 24,
                        height: 24,
                        margin: const EdgeInsets.only(right: 4),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(color: NexGenPalette.line),
                        ),
                      ),
                  ],
                ),
              ),
              // Heart / favorite button
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FavoriteHeartButton(
                  patternId: widget.paletteNode.id,
                  patternName: widget.paletteNode.name,
                  patternData: {
                    'colors': _paletteColors.map((c) => c.value).toList(),
                    'nodeType': 'palette',
                  },
                  size: 24,
                ),
              ),
              // Open in full pattern editor
              IconButton(
                onPressed: () {
                  final effectId = ref.read(selectorEffectIdProvider);
                  final speed = ref.read(selectorSpeedProvider);
                  final intensity = ref.read(selectorIntensityProvider);
                  final pattern = EditablePattern.fromGradientColors(
                    id: widget.paletteNode.id,
                    name: widget.paletteNode.name,
                    colors: _paletteColors,
                    effectId: effectId,
                    speed: speed,
                    intensity: intensity,
                  );
                  context.push(AppRoutes.editPattern, extra: pattern);
                },
                icon: const Icon(Icons.tune, size: 20),
                tooltip: 'Open in Pattern Editor',
                style: IconButton.styleFrom(
                  foregroundColor: NexGenPalette.textMedium,
                ),
              ),
              // Apply button
              ElevatedButton.icon(
                onPressed: _applyPattern,
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Apply'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  foregroundColor: NexGenPalette.matteBlack,
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                ),
              ),
            ],
          ),
        ),

        // Large preview
        Container(
          height: 160,
          margin: const EdgeInsets.symmetric(horizontal: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: EffectPreviewWidget(
              effectId: effectId,
              colors: _paletteColors,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // Color layout selector (conditional)
        if (showColorLayout) _buildColorLayoutSelector(colorGroup),

        // Speed slider
        _buildSlider(
          label: 'Speed',
          value: speed,
          onChanged: (v) {
            ref.read(selectorSpeedProvider.notifier).state = v.round();
            _sendToWled();
          },
        ),

        // Intensity slider
        _buildSlider(
          label: 'Intensity',
          value: intensity,
          onChanged: (v) {
            ref.read(selectorIntensityProvider.notifier).state = v.round();
            _sendToWled();
          },
        ),

        const SizedBox(height: 8),

        // Effect list
        Expanded(
          child: _buildEffectList(effectId, expandedMoods),
        ),
      ],
    );
  }

  Widget _buildColorLayoutSelector(int colorGroup) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'LEDs per color',
            style: TextStyle(
              color: NexGenPalette.textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: List.generate(5, (i) {
              final value = i + 1;
              final isSelected = colorGroup == value;
              return GestureDetector(
                onTap: () {
                  ref.read(selectorColorGroupProvider.notifier).state = value;
                  _sendToWled();
                },
                child: Container(
                  width: 48,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NexGenPalette.cyan.withValues(alpha: 0.2)
                        : NexGenPalette.gunmetal,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: isSelected
                          ? NexGenPalette.cyan
                          : NexGenPalette.line,
                      width: isSelected ? 2 : 1,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      '$value',
                      style: TextStyle(
                        color: isSelected
                            ? NexGenPalette.cyan
                            : NexGenPalette.textMedium,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          // Visual preview of pattern
          _buildColorLayoutPreview(colorGroup),
        ],
      ),
    );
  }

  Widget _buildColorLayoutPreview(int colorGroup) {
    final colors = _paletteColors.take(3).toList();
    if (colors.isEmpty) colors.add(Colors.white);

    // Generate pattern preview dots
    final dots = <Widget>[];
    for (int i = 0; i < 18; i++) {
      final colorIndex = (i ~/ colorGroup) % colors.length;
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: colors[colorIndex],
          shape: BoxShape.circle,
          border: Border.all(
            color: NexGenPalette.line,
            width: 0.5,
          ),
        ),
      ));
    }

    return Row(
      children: [
        Text(
          'Pattern:',
          style: TextStyle(
            color: NexGenPalette.textSecondary,
            fontSize: 11,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: dots),
          ),
        ),
      ],
    );
  }

  Widget _buildSlider({
    required String label,
    required int value,
    required ValueChanged<double> onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 70,
            child: Text(
              label,
              style: TextStyle(
                color: NexGenPalette.textSecondary,
                fontSize: 13,
              ),
            ),
          ),
          Expanded(
            child: SliderTheme(
              data: SliderThemeData(
                activeTrackColor: NexGenPalette.cyan,
                inactiveTrackColor: NexGenPalette.trackDark,
                thumbColor: NexGenPalette.cyan,
                overlayColor: NexGenPalette.cyan.withValues(alpha: 0.2),
                trackHeight: 4,
              ),
              child: Slider(
                value: value.toDouble(),
                min: 0,
                max: 255,
                onChanged: onChanged,
              ),
            ),
          ),
          SizedBox(
            width: 40,
            child: Text(
              '$value',
              textAlign: TextAlign.right,
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEffectList(int selectedEffectId, Set<SelectorMood> expandedMoods) {
    final effectsByMood = WledEffectsCatalog.effectsBySelectorMood;

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      itemCount: SelectorMood.values.length,
      itemBuilder: (context, index) {
        final mood = SelectorMood.values[index];
        final effects = effectsByMood[mood] ?? [];
        if (effects.isEmpty) return const SizedBox.shrink();

        final isExpanded = expandedMoods.contains(mood);

        return Container(
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Column(
            children: [
              // Category header
              InkWell(
                onTap: () {
                  final newSet = Set<SelectorMood>.from(expandedMoods);
                  if (isExpanded) {
                    newSet.remove(mood);
                  } else {
                    newSet.add(mood);
                  }
                  ref.read(selectorExpandedMoodsProvider.notifier).state =
                      newSet;
                },
                borderRadius: BorderRadius.circular(12),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      Text(
                        mood.icon,
                        style: const TextStyle(fontSize: 18),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${mood.displayName} (${effects.length})',
                          style: const TextStyle(
                            color: NexGenPalette.textHigh,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                      Icon(
                        isExpanded
                            ? Icons.keyboard_arrow_up
                            : Icons.keyboard_arrow_down,
                        color: NexGenPalette.textSecondary,
                      ),
                    ],
                  ),
                ),
              ),

              // Effect tiles
              if (isExpanded)
                Padding(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: Column(
                    children: effects.map((effect) {
                      final isSelected = effect.id == selectedEffectId;
                      return _buildEffectTile(effect, isSelected);
                    }).toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildEffectTile(WledEffect effect, bool isSelected) {
    return InkWell(
      onTap: () {
        ref.read(selectorEffectIdProvider.notifier).state = effect.id;
        _sendToWled();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(8),
          border: isSelected
              ? Border.all(color: NexGenPalette.cyan, width: 1.5)
              : null,
        ),
        child: Row(
          children: [
            // Mini preview
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: EffectPreviewWidget(
                  effectId: effect.id,
                  colors: _paletteColors,
                  borderRadius: 8,
                ),
              ),
            ),
            const SizedBox(width: 12),
            // Effect name
            Expanded(
              child: Text(
                effect.name,
                style: TextStyle(
                  color: isSelected
                      ? NexGenPalette.cyan
                      : NexGenPalette.textHigh,
                  fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // Checkmark if selected
            if (isSelected)
              Icon(
                Icons.check,
                color: NexGenPalette.cyan,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
