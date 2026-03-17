import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/effect_preview_widget.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/effect_speed_profiles.dart';
import 'package:nexgen_command/features/wled/pattern_repository.dart' show PatternRepository;
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/effect_speed_slider.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/nav.dart' show AppRoutes;
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';

/// Effect selector page that replaces the pattern grid.
/// Shows a large live preview with filter chips and curated effect grid.
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
    // Initialize selector state from palette metadata (architectural patterns
    // store grouping/spacing here) or fall back to defaults.
    final meta = widget.paletteNode.metadata;
    final initGrouping = (meta?['grouping'] as int?) ?? (meta?['bandWidth'] as int?) ?? 1;
    final initSpacing = (meta?['spacing'] as int?) ?? 0;
    final isBrGradient = meta?['type'] == 'brightness_gradient';
    // Resolve initial gradient preset index from node ID suffix
    int initPreset = 0;
    if (isBrGradient) {
      final nodeId = widget.paletteNode.id;
      final suffix = nodeId.contains('_gradients_') ? nodeId.split('_gradients_').last : '';
      final presets = PatternRepository.brightnessGradientPresets;
      for (var pi = 0; pi < presets.length; pi++) {
        if (presets[pi].id == suffix) { initPreset = pi; break; }
      }
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(selectorEffectIdProvider.notifier).state = 0;
      ref.read(selectorSpeedProvider.notifier).state = getSpeedProfile(0).rawDefault;
      ref.read(selectorIntensityProvider.notifier).state = 128;
      ref.read(selectorColorGroupProvider.notifier).state = initGrouping;
      ref.read(selectorSpacingProvider.notifier).state = initSpacing;
      ref.read(selectorGradientPresetProvider.notifier).state = initPreset;
      ref.read(selectorBreathingProvider.notifier).state = false;
      ref.read(selectorMotionTypeProvider.notifier).state = null;
      ref.read(selectorColorBehaviorProvider.notifier).state = null;
    });
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  /// Whether this palette node carries architectural spacing metadata.
  bool get _isArchitectural =>
      widget.paletteNode.metadata?['grouping'] != null &&
      widget.paletteNode.metadata?['spacing'] != null;

  /// Whether this palette node is a brightness gradient pattern.
  bool get _isBrightnessGradient =>
      widget.paletteNode.metadata?['type'] == 'brightness_gradient';

  /// Compute gradient colors from the base (100%) color and preset steps.
  List<Color> _gradientColorsForPreset(int presetIndex) {
    final presets = PatternRepository.brightnessGradientPresets;
    final preset = presets[presetIndex.clamp(0, presets.length - 1)];
    final baseColor = widget.paletteNode.themeColors!.first;
    final r = (baseColor.r * 255).round();
    final g = (baseColor.g * 255).round();
    final b = (baseColor.b * 255).round();
    return preset.steps
        .map((pct) => Color.fromARGB(
              255,
              (r * pct).round().clamp(0, 255),
              (g * pct).round().clamp(0, 255),
              (b * pct).round().clamp(0, 255),
            ))
        .toList();
  }

  /// Returns the effective WLED effect ID. When effect 0 (Solid) is selected
  /// with multiple palette colors, substitutes effect 83 (Solid Pattern)
  /// which distributes colors in repeating blocks using `grp`.
  /// Architectural patterns keep effect 0 — their spacing comes from grp/spc,
  /// not from multi-color distribution.
  int _effectiveEffectId(int selectedId) {
    if (selectedId == 0 && _paletteColors.length > 1 && !_isArchitectural) return 83;
    return selectedId;
  }

  void _sendToWled() {
    _debounceTimer?.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 150), () async {
      final demoMode = ref.read(demoModeProvider);
      if (demoMode) return;

      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;

      final colorGroup = ref.read(selectorColorGroupProvider);
      final spacing = ref.read(selectorSpacingProvider);

      // For brightness gradients, derive colors and effect from gradient state
      final List<List<int>> cols;
      final int fxId;
      final int speed;
      if (_isBrightnessGradient) {
        final presetIdx = ref.read(selectorGradientPresetProvider);
        final breathing = ref.read(selectorBreathingProvider);
        final gradColors = _gradientColorsForPreset(presetIdx);
        cols = PatternRepository.colorsToWledCol(gradColors);
        fxId = breathing ? 2 : 83;
        speed = breathing ? 100 : 0;
      } else {
        final effectId = ref.read(selectorEffectIdProvider);
        cols = _paletteColors
            .take(3)
            .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), forceZeroWhite: true))
            .toList();
        if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255));
        fxId = _effectiveEffectId(effectId);
        speed = ref.read(selectorSpeedProvider);
      }

      var payload = <String, dynamic>{
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': fxId,
            'sx': speed,
            'ix': ref.read(selectorIntensityProvider),
            'pal': 5, // "Colors Only" palette
            'grp': colorGroup,
            'spc': spacing,
            'col': cols,
          }
        ]
      };

      // Apply channel filter so all targeted segments receive the change
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));

      await repo.applyJson(payload);
    });
  }

  Future<void> _applyPattern() async {
    final colorGroup = ref.read(selectorColorGroupProvider);
    final spacing = ref.read(selectorSpacingProvider);
    final intensity = ref.read(selectorIntensityProvider);

    // Resolve effect, speed, and colors depending on pattern type
    final int fxId;
    final int speed;
    final List<Color> previewColors;
    final String effectName;
    if (_isBrightnessGradient) {
      final breathing = ref.read(selectorBreathingProvider);
      final presetIdx = ref.read(selectorGradientPresetProvider);
      previewColors = _gradientColorsForPreset(presetIdx);
      fxId = breathing ? 2 : 83;
      speed = breathing ? 100 : 0;
      effectName = breathing ? 'Breathing' : 'Static';
    } else {
      final effectId = ref.read(selectorEffectIdProvider);
      previewColors = _paletteColors;
      fxId = _effectiveEffectId(effectId);
      speed = ref.read(selectorSpeedProvider);
      effectName = WledEffectsCatalog.getName(effectId);
    }

    final notifier = ref.read(wledStateProvider.notifier);
    final currentState = ref.read(wledStateProvider);
    bool appliedToDevice = false;

    // Try to send to device
    final repo = ref.read(wledRepositoryProvider);
    if (repo != null) {
      final List<List<int>> cols;
      if (_isBrightnessGradient) {
        cols = PatternRepository.colorsToWledCol(previewColors);
      } else {
        final raw = previewColors
            .take(3)
            .map((c) => rgbToRgbw((c.r * 255).round(), (c.g * 255).round(), (c.b * 255).round(), forceZeroWhite: true))
            .toList();
        if (raw.isEmpty) raw.add(rgbToRgbw(255, 255, 255));
        cols = raw;
      }

      var payload = <String, dynamic>{
        'on': true,
        'bri': 255,
        'seg': [
          {
            'fx': fxId,
            'sx': speed,
            'ix': intensity,
            'pal': 5,
            'grp': colorGroup,
            'spc': spacing,
            'col': cols,
          }
        ]
      };

      // Apply channel filter so all targeted segments receive the pattern
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) {
        payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      }

      try {
        await repo.applyJson(payload);
        appliedToDevice = currentState.connected;
      } catch (e) {
        debugPrint('Pattern apply failed (device offline?): $e');
      }
    }

    // Always update local preview state so roofline shows on house image
    notifier.applyLocalPreview(
      colors: previewColors,
      effectId: fxId,
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
    final motionFilter = ref.watch(selectorMotionTypeProvider);
    final colorFilter = ref.watch(selectorColorBehaviorProvider);

    // For brightness gradient patterns, derive preview colors from the active preset
    final gradientPresetIdx = ref.watch(selectorGradientPresetProvider);
    final breathing = ref.watch(selectorBreathingProvider);
    final gradientPreviewColors = _isBrightnessGradient
        ? _gradientColorsForPreset(gradientPresetIdx)
        : _paletteColors;
    final gradientPreviewFx = _isBrightnessGradient
        ? (breathing ? 2 : 83)
        : effectId;
    final gradientPreviewSpeed = _isBrightnessGradient
        ? (breathing ? 100 : 0)
        : speed;

    final effect = WledEffectsCatalog.getById(effectId);
    final hasMultipleColors = _paletteColors.length > 1;
    final showColorLayout = !_isBrightnessGradient &&
        ((effect?.usesColorLayout ?? false) || (effectId == 0 && hasMultipleColors));

    // Build filtered effect list (only used for non-gradient patterns)
    final bool showingTopPicks = motionFilter == null && colorFilter == null;
    final List<WledEffect> displayEffects = showingTopPicks
        ? WledEffectsCatalog.topPicks
        : WledEffectsCatalog.filterEffects(
            motionType: motionFilter,
            colorBehavior: colorFilter,
          );

    return CustomScrollView(
      slivers: [
        // Channel/Area selector
        const SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: ChannelSelectorBar(),
          ),
        ),

        // Apply button row
        SliverToBoxAdapter(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              children: [
                // Color palette preview
                Expanded(
                  child: Row(
                    children: [
                      for (final color in gradientPreviewColors.take(3))
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
                // Open in full pattern editor (not applicable for gradients)
                if (!_isBrightnessGradient)
                  SizedBox(
                    width: 44,
                    height: 44,
                    child: IconButton(
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
                      icon: const Icon(Icons.tune, size: 22),
                      tooltip: 'Open in Pattern Editor',
                      style: IconButton.styleFrom(
                        foregroundColor: NexGenPalette.textMedium,
                      ),
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
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
                    textStyle: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Roofline preview
        SliverToBoxAdapter(child: _buildRooflinePreview(gradientPreviewFx, gradientPreviewSpeed)),

        const SliverToBoxAdapter(child: SizedBox(height: 8)),

        // ---- Brightness Gradient controls ----
        if (_isBrightnessGradient) ...[
          SliverToBoxAdapter(child: _buildGradientPresetSelector(gradientPresetIdx)),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverToBoxAdapter(child: _buildBandWidthSelector(colorGroup)),
          const SliverToBoxAdapter(child: SizedBox(height: 4)),
          SliverToBoxAdapter(child: _buildBreathingToggle(breathing)),
          SliverPadding(padding: EdgeInsets.only(bottom: navBarTotalHeight(context))),
        ],

        // ---- Standard effect controls ----
        if (!_isBrightnessGradient) ...[
          // Color layout selector (conditional)
          if (showColorLayout) SliverToBoxAdapter(child: _buildColorLayoutSelector(colorGroup)),

          // Speed slider
          SliverToBoxAdapter(
            child: EffectSpeedSlider(
              rawSpeed: speed,
              effectId: effectId,
              onChanged: (raw) {
                ref.read(selectorSpeedProvider.notifier).state = raw;
                _sendToWled();
              },
            ),
          ),

          // Intensity slider
          SliverToBoxAdapter(
            child: _buildSlider(
              label: 'Intensity',
              value: intensity,
              onChanged: (v) {
                ref.read(selectorIntensityProvider.notifier).state = v.round();
                _sendToWled();
              },
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Motion type filter chips
          SliverToBoxAdapter(child: _buildMotionFilterRow(motionFilter)),

          const SliverToBoxAdapter(child: SizedBox(height: 6)),

          // Color behavior filter chips
          SliverToBoxAdapter(child: _buildColorFilterRow(colorFilter)),

          const SliverToBoxAdapter(child: SizedBox(height: 8)),

          // Section header
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Text(
                    showingTopPicks ? 'TOP PICKS' : '${displayEffects.length} EFFECTS',
                    style: TextStyle(
                      color: NexGenPalette.textSecondary,
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.0,
                    ),
                  ),
                  if (!showingTopPicks) ...[
                    const Spacer(),
                    GestureDetector(
                      onTap: () {
                        ref.read(selectorMotionTypeProvider.notifier).state = null;
                        ref.read(selectorColorBehaviorProvider.notifier).state = null;
                      },
                      child: Text(
                        'Clear filters',
                        style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),

          const SliverToBoxAdapter(child: SizedBox(height: 6)),

          // Effect list
          SliverPadding(
            padding: EdgeInsets.only(left: 16, right: 16, bottom: navBarTotalHeight(context)),
            sliver: SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final effect = displayEffects[index];
                  final isSelected = effect.id == effectId;
                  return _buildEffectTile(effect, isSelected);
                },
                childCount: displayEffects.length,
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ---------------------------------------------------------------------------
  // Brightness Gradient Controls
  // ---------------------------------------------------------------------------

  /// CONTROL 1 — Gradient Preset Selector (horizontal pill chips)
  Widget _buildGradientPresetSelector(int activeIndex) {
    final presets = PatternRepository.brightnessGradientPresets;
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
            'Brightness Pattern',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 12),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: List.generate(presets.length, (i) {
              final preset = presets[i];
              final isSelected = i == activeIndex;
              return GestureDetector(
                onTap: () {
                  ref.read(selectorGradientPresetProvider.notifier).state = i;
                  _sendToWled();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? NexGenPalette.cyan.withValues(alpha: 0.2)
                        : NexGenPalette.gunmetal,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
                      width: isSelected ? 1.5 : 1,
                    ),
                  ),
                  child: Text(
                    preset.name,
                    style: TextStyle(
                      color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                      fontSize: 12,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                    ),
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          // LED dot preview showing the brightness gradient pattern
          _buildGradientDotPreview(activeIndex, ref.watch(selectorColorGroupProvider)),
        ],
      ),
    );
  }

  /// Shows a row of LED dots at varying brightness levels for the active preset.
  Widget _buildGradientDotPreview(int presetIndex, int bandWidth) {
    final colors = _gradientColorsForPreset(presetIndex);
    final dots = <Widget>[];
    for (int i = 0; i < 18; i++) {
      final colorIdx = (i ~/ bandWidth) % colors.length;
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: colors[colorIdx],
          shape: BoxShape.circle,
          border: Border.all(color: NexGenPalette.line, width: 0.5),
        ),
      ));
    }
    return Row(
      children: [
        Text('Pattern:', style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 11)),
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

  /// CONTROL 2 — Band Width Selector (1 LED or 2 LED per brightness step)
  Widget _buildBandWidthSelector(int activeBandWidth) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Text(
            'LEDs per Step',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 12),
          ),
          const Spacer(),
          for (final bw in [1, 2]) ...[
            if (bw == 2) const SizedBox(width: 8),
            GestureDetector(
              onTap: () {
                ref.read(selectorColorGroupProvider.notifier).state = bw;
                _sendToWled();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: activeBandWidth == bw
                      ? NexGenPalette.cyan.withValues(alpha: 0.2)
                      : NexGenPalette.gunmetal,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: activeBandWidth == bw ? NexGenPalette.cyan : NexGenPalette.line,
                    width: activeBandWidth == bw ? 2 : 1,
                  ),
                ),
                child: Text(
                  '$bw LED',
                  style: TextStyle(
                    color: activeBandWidth == bw ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 13,
                    fontWeight: activeBandWidth == bw ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  /// CONTROL 3 — Breathing Toggle
  Widget _buildBreathingToggle(bool isBreathing) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        children: [
          Text(
            'Breathing',
            style: TextStyle(color: NexGenPalette.textSecondary, fontSize: 13),
          ),
          const Spacer(),
          Switch(
            value: isBreathing,
            onChanged: (v) {
              ref.read(selectorBreathingProvider.notifier).state = v;
              _sendToWled();
            },
            activeThumbColor: NexGenPalette.cyan,
            activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.3),
            inactiveThumbColor: NexGenPalette.textSecondary,
            inactiveTrackColor: NexGenPalette.gunmetal,
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Roofline Preview
  // ---------------------------------------------------------------------------

  Widget _buildRooflinePreview(int effectId, int speed) {
    final houseImageUrl = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u?.housePhotoUrl,
      orElse: () => null,
    );
    final hasCustomImage = houseImageUrl != null && houseImageUrl.isNotEmpty;

    return Container(
      height: 140,
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.line),
        color: NexGenPalette.matteBlack,
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // House image
            if (hasCustomImage)
              Image.network(houseImageUrl, fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => Image.asset(
                  'assets/images/Demohomephoto.jpg', fit: BoxFit.cover,
                ),
              )
            else
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover),

            // Gradient overlay for legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [
                      Colors.black.withValues(alpha: 0.4),
                      Colors.transparent,
                    ],
                  ),
                ),
              ),
            ),

            // Animated roofline overlay with current pattern
            Positioned.fill(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return AnimatedRooflineOverlay(
                    previewColors: _isBrightnessGradient
                        ? _gradientColorsForPreset(ref.watch(selectorGradientPresetProvider))
                        : _paletteColors,
                    previewEffectId: effectId,
                    previewSpeed: speed,
                    forceOn: true,
                    targetAspectRatio: constraints.maxWidth / constraints.maxHeight,
                    useBoxFitCover: true,
                    colorGroupSize: ref.watch(selectorColorGroupProvider),
                    spacing: ref.watch(selectorSpacingProvider),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // Filter Chip Rows
  // ---------------------------------------------------------------------------

  Widget _buildMotionFilterRow(MotionType? selected) {
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            label: 'All',
            icon: '⭐',
            isSelected: selected == null,
            onTap: () => ref.read(selectorMotionTypeProvider.notifier).state = null,
          ),
          for (final type in MotionType.values) ...[
            const SizedBox(width: 6),
            _buildFilterChip(
              label: type.displayName,
              icon: type.icon,
              isSelected: selected == type,
              onTap: () => ref.read(selectorMotionTypeProvider.notifier).state =
                  selected == type ? null : type,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColorFilterRow(ColorBehavior? selected) {
    // Simplified color behavior options - merge usesSelected + blends into "My Colors"
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        children: [
          _buildFilterChip(
            label: 'Any Color',
            isSelected: selected == null,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state = null,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'My Colors',
            isSelected: selected == ColorBehavior.usesSelectedColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.usesSelectedColors ? null : ColorBehavior.usesSelectedColors,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'Blended',
            isSelected: selected == ColorBehavior.blendsSelectedColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.blendsSelectedColors ? null : ColorBehavior.blendsSelectedColors,
            subtle: true,
          ),
          const SizedBox(width: 6),
          _buildFilterChip(
            label: 'Auto Colors',
            isSelected: selected == ColorBehavior.generatesOwnColors,
            onTap: () => ref.read(selectorColorBehaviorProvider.notifier).state =
                selected == ColorBehavior.generatesOwnColors ? null : ColorBehavior.generatesOwnColors,
            subtle: true,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterChip({
    required String label,
    String? icon,
    required bool isSelected,
    required VoidCallback onTap,
    bool subtle = false,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? (subtle ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.cyan.withValues(alpha: 0.2))
              : NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Text(icon, style: const TextStyle(fontSize: 12)),
              const SizedBox(width: 4),
            ],
            Text(
              label,
              style: TextStyle(
                color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEffectTile(WledEffect effect, bool isSelected) {
    // Color behavior badge text
    final badgeText = effect.colorBehavior.shortName;
    final badgeColor = switch (effect.colorBehavior) {
      ColorBehavior.usesSelectedColors => NexGenPalette.cyan,
      ColorBehavior.blendsSelectedColors => Colors.purpleAccent,
      ColorBehavior.generatesOwnColors => Colors.orange,
      ColorBehavior.usesPalette => Colors.tealAccent,
    };

    return InkWell(
      onTap: () {
        ref.read(selectorEffectIdProvider.notifier).state = effect.id;
        // Reset speed to this effect's profile default for best experience
        ref.read(selectorSpeedProvider.notifier).state =
            getSpeedProfile(effect.id).rawDefault;
        _sendToWled();
      },
      borderRadius: BorderRadius.circular(10),
      child: Container(
        margin: const EdgeInsets.only(bottom: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? NexGenPalette.cyan.withValues(alpha: 0.15)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
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
            // Effect name + color behavior badge
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    effect.name,
                    style: TextStyle(
                      color: isSelected
                          ? NexGenPalette.cyan
                          : NexGenPalette.textHigh,
                      fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    badgeText,
                    style: TextStyle(
                      color: badgeColor.withValues(alpha: 0.8),
                      fontSize: 10,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
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

  // ---------------------------------------------------------------------------
  // Color Layout & Sliders (unchanged)
  // ---------------------------------------------------------------------------

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
          _buildColorLayoutPreview(colorGroup),
        ],
      ),
    );
  }

  Widget _buildColorLayoutPreview(int colorGroup) {
    final colors = _paletteColors.take(3).toList();
    if (colors.isEmpty) colors.add(Colors.white);
    final spc = ref.watch(selectorSpacingProvider);
    final cycle = colorGroup + spc;

    final dots = <Widget>[];
    for (int i = 0; i < 18; i++) {
      final bool lit = spc == 0 || cycle == 0 || (i % cycle) < colorGroup;
      final Color dotColor;
      if (lit) {
        final colorIndex = (i ~/ colorGroup) % colors.length;
        dotColor = colors[colorIndex];
      } else {
        dotColor = colors.first.withValues(alpha: 0.10);
      }
      dots.add(Container(
        width: 14,
        height: 14,
        margin: const EdgeInsets.only(right: 2),
        decoration: BoxDecoration(
          color: dotColor,
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
}
