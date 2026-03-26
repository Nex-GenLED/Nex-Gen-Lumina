import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Computed display name for the currently active pattern/effect.
///
/// Label resolution hierarchy:
///   Priority 1: WLED preset name (resolved from ps + /json/presets lookup,
///               stored in activePresetLabelProvider by _resolvePresetName)
///   Priority 2: activePresetLabelProvider value (app-set label from library
///               pattern, saved design, or quick control — only if effectId
///               matches current state)
///   Priority 3: Warm White detection (RGBW strip, white channel active, solid)
///   Priority 4: Effect name only (e.g. "Glitter", "Chase") — never color
///   Priority 5: "Custom" — absolute fallback
///
/// The old "[color] [effect]" generated strings (e.g. "Blue Streaking",
/// "Orange Solid") have been removed entirely — they were never accurate
/// enough to show the user.
final displayPatternNameProvider = Provider<String>((ref) {
  final wledState = ref.watch(wledStateProvider);

  // Off state
  if (!wledState.isOn) return 'Lights Off';

  // Priority 1 & 2: activePresetLabelProvider holds either the WLED preset
  // name (set by _resolvePresetName when ps > 0) or an app-set label
  final activePreset = ref.watch(activePresetLabelProvider);
  if (activePreset != null && activePreset.isNotEmpty) return activePreset;

  // Priority 3: Warm White detection
  if (wledState.supportsRgbw && wledState.warmWhite > 0 && wledState.effectId == 0) {
    return 'Warm White';
  }

  // Priority 4: Effect name only — no color prefix/suffix
  final effectName = wledState.effectName;
  if (effectName.isNotEmpty && effectName != 'Effect #${wledState.effectId}') {
    return effectName;
  }

  // Priority 5: Absolute fallback
  return 'Custom';
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
