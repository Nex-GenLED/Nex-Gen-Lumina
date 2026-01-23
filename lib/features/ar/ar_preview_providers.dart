import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';

/// Provider for the user's roofline mask configuration.
/// Returns the mask from the user's profile, or null if not set.
final rooflineMaskProvider = Provider<RooflineMask?>((ref) {
  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (u) => u,
    orElse: () => null,
  );

  if (profile?.rooflineMask == null) return null;

  try {
    return RooflineMask.fromJson(profile!.rooflineMask!);
  } catch (e) {
    debugPrint('Failed to parse roofline mask: $e');
    return null;
  }
});

/// Provider to check if user wants to use the stock demo image
final useStockImageProvider = Provider<bool>((ref) {
  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (u) => u,
    orElse: () => null,
  );
  return profile?.useStockHouseImage ?? false;
});

/// Provider for the effective house image URL to display.
/// Returns null if using stock image or no custom image uploaded.
final houseImageUrlProvider = Provider<String?>((ref) {
  final useStock = ref.watch(useStockImageProvider);
  if (useStock) return null;

  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (u) => u,
    orElse: () => null,
  );

  final housePhotoUrl = profile?.housePhotoUrl;
  if (housePhotoUrl == null || housePhotoUrl.isEmpty) return null;

  return housePhotoUrl;
});

/// Provider to check if user has uploaded a custom house image
final hasCustomHouseImageProvider = Provider<bool>((ref) {
  final useStock = ref.watch(useStockImageProvider);
  if (useStock) return false;

  final profile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (u) => u,
    orElse: () => null,
  );

  final housePhotoUrl = profile?.housePhotoUrl;
  return housePhotoUrl != null && housePhotoUrl.isNotEmpty;
});

/// State for AR preview mode (used in Lumina chat)
class ARPreviewState {
  final List<Color> colors;
  final int effectId;
  final int speed;
  final int intensity;
  final bool isActive;

  const ARPreviewState({
    this.colors = const [],
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.isActive = false,
  });

  ARPreviewState copyWith({
    List<Color>? colors,
    int? effectId,
    int? speed,
    int? intensity,
    bool? isActive,
  }) {
    return ARPreviewState(
      colors: colors ?? this.colors,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      isActive: isActive ?? this.isActive,
    );
  }

  static const ARPreviewState inactive = ARPreviewState();
}

/// Notifier for managing AR preview state
class ARPreviewNotifier extends Notifier<ARPreviewState> {
  @override
  ARPreviewState build() => ARPreviewState.inactive;

  /// Start previewing a pattern
  void startPreview({
    required List<Color> colors,
    int effectId = 0,
    int speed = 128,
    int intensity = 128,
  }) {
    state = ARPreviewState(
      colors: colors,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      isActive: true,
    );
  }

  /// Update preview colors
  void updateColors(List<Color> colors) {
    state = state.copyWith(colors: colors);
  }

  /// Update preview effect
  void updateEffect(int effectId, {int? speed, int? intensity}) {
    state = state.copyWith(
      effectId: effectId,
      speed: speed,
      intensity: intensity,
    );
  }

  /// Stop preview mode
  void stopPreview() {
    state = ARPreviewState.inactive;
  }
}

/// Provider for AR preview state (used when Lumina suggests patterns)
final arPreviewProvider = NotifierProvider<ARPreviewNotifier, ARPreviewState>(() {
  return ARPreviewNotifier();
});

/// Convenience provider to check if preview mode is active
final isPreviewModeProvider = Provider<bool>((ref) {
  return ref.watch(arPreviewProvider).isActive;
});

/// Provider for current preview colors (or null if not in preview mode)
final previewColorsProvider = Provider<List<Color>?>((ref) {
  final state = ref.watch(arPreviewProvider);
  if (!state.isActive) return null;
  return state.colors;
});

/// Provider for current preview effect ID (or null if not in preview mode)
final previewEffectIdProvider = Provider<int?>((ref) {
  final state = ref.watch(arPreviewProvider);
  if (!state.isActive) return null;
  return state.effectId;
});

/// Effect categories for determining animation style
enum EffectCategory {
  solid,     // No animation, static color
  breathe,   // Pulsing opacity
  chase,     // Moving segment
  rainbow,   // Color cycling
  twinkle,   // Random sparkle
  wave,      // Oscillating pattern
  fire,      // Fire-like flickering
}

/// Helper to categorize WLED effects
EffectCategory categorizeEffect(int effectId) {
  // Solid/static
  if (effectId == 0) return EffectCategory.solid;

  // Breathe/pulse effects
  if (effectId == 2 || effectId == 25) return EffectCategory.breathe;

  // Chase effects
  if ([28, 29, 30, 31, 32, 33, 47, 48].contains(effectId)) {
    return EffectCategory.chase;
  }

  // Rainbow effects
  if ([9, 10, 11, 12, 13, 14].contains(effectId)) return EffectCategory.rainbow;

  // Twinkle/sparkle effects
  if ([17, 43, 44, 45, 46, 51, 52].contains(effectId)) return EffectCategory.twinkle;

  // Wave effects
  if ([35, 36, 37, 67, 68].contains(effectId)) return EffectCategory.wave;

  // Fire effects
  if ([66, 94, 95].contains(effectId)) return EffectCategory.fire;

  // Default to chase for animated effects
  return EffectCategory.chase;
}

/// Convert WLED speed (0-255) to animation duration
Duration speedToDuration(int wledSpeed) {
  // Dampen the speed mapping for smoother preview animations
  // Map 0-255 to 6s (slowest) to 1.5s (fastest) instead of 0.3s
  // This eliminates sub-1-second animations that cause chaotic flashing
  final seconds = 6.0 - (wledSpeed / 255.0) * 4.5;
  return Duration(milliseconds: (seconds * 1000).round());
}
