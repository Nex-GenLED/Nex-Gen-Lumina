import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/utils/color_name_utils.dart';

/// Computed display name for the currently active pattern/effect.
/// Implements the fallback hierarchy:
/// 1. Lights off → "Lights Off"
/// 2. Active preset label (library pattern or saved design) → as-is
/// 3. Warm White detection → "Warm White"
/// 4. AI color names available → "[Effect] · [Color Name]"
/// 5. Derived color name → "[Effect] · [Color Name]"
/// 6. Color is white/uninteresting → just effect name
/// 7. Absolute fallback → "Custom"
final displayPatternNameProvider = Provider<String>((ref) {
  final wledState = ref.watch(wledStateProvider);

  if (!wledState.isOn) return 'Lights Off';

  final activePreset = ref.watch(activePresetLabelProvider);
  if (activePreset != null && activePreset.isNotEmpty) return activePreset;

  if (wledState.supportsRgbw && wledState.warmWhite > 0 && wledState.effectId == 0) {
    return 'Warm White';
  }

  final effectName = wledState.effectName;

  // Use AI-provided color names if available
  if (wledState.colorNames.isNotEmpty) {
    return '$effectName · ${wledState.colorNames.first}';
  }

  // Generate color name from primary color
  final colorName = richColorName(wledState.color);

  // For solid effect with a meaningful color, show both
  if (wledState.effectId == 0 && colorName != 'White') {
    return 'Solid · $colorName';
  }

  // If color is white or generic, just show effect name
  if (colorName == 'White') {
    return effectName;
  }

  return '$effectName · $colorName';
});

/// Whether the current lighting config is an unsaved custom state.
/// True when lights are on but no named preset is active.
/// Used to enable tap-to-save on the Now Playing bar.
final isUnsavedCustomConfigProvider = Provider<bool>((ref) {
  final wledState = ref.watch(wledStateProvider);
  if (!wledState.isOn) return false;
  final activePreset = ref.watch(activePresetLabelProvider);
  return activePreset == null || activePreset.isEmpty;
});
