import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

/// Computed display name for the currently active pattern/effect.
///
/// Label resolution hierarchy:
///   Priority 1: Lumina "My Favorites" name — when the active label matches a
///               saved favorite by name (case-insensitive), we prefer the
///               Lumina-side name so user-renamed favorites win over the raw
///               WLED preset name.
///   Priority 2: WLED preset name (resolved from ps + /json/presets lookup,
///               stored in activePresetLabelProvider by _resolvePresetName)
///               OR any app-set label (library pattern, saved design, quick
///               control). Both flow through activePresetLabelProvider.
///   Priority 3: Warm White detection (RGBW strip, white channel active, solid)
///   Priority 4: Effect name only (e.g. "Glitter", "Chase") — never color
///   Priority 5: "Custom" — absolute fallback
final displayPatternNameProvider = Provider<String>((ref) {
  final wledState = ref.watch(wledStateProvider);

  // Off state
  if (!wledState.isOn) return 'Lights Off';

  final activePreset = ref.watch(activePresetLabelProvider);
  if (activePreset != null && activePreset.isNotEmpty) {
    // Priority 1: prefer a matching Lumina favorite's name, if any.
    final favoritesAsync = ref.watch(allFavoritesProvider);
    final favorites = favoritesAsync.valueOrNull;
    if (favorites != null && favorites.isNotEmpty) {
      final target = activePreset.trim().toLowerCase();
      for (final fav in favorites) {
        if (fav.name.trim().toLowerCase() == target) {
          return fav.name;
        }
      }
    }
    // Priority 2: fall through to the preset / app-set label.
    return activePreset;
  }

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
