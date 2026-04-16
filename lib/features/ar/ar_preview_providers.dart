import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/effect_database.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/models/roofline_segment.dart';

/// Provider for the user's roofline mask configuration.
/// Returns the mask from the user's profile, or null if not set.
///
/// In demo mode, synthesizes a mask from the first demo segment's points
/// so legacy consumers (AnimatedRooflineOverlay fallback path) render
/// correctly without an authenticated user profile.
final rooflineMaskProvider = Provider<RooflineMask?>((ref) {
  // DEMO MODE: synthesize a mask from the first demo segment's points.
  final isDemo = ref.watch(demoExperienceActiveProvider);
  if (isDemo) {
    final demoConfig = ref.watch(demoRooflineConfigProvider);
    if (demoConfig == null || demoConfig.segments.isEmpty) {
      return null;
    }
    RooflineSegment firstWithPoints;
    try {
      firstWithPoints =
          demoConfig.segments.firstWhere((s) => s.points.length >= 2);
    } catch (_) {
      return null;
    }
    return RooflineMask(
      points: firstWithPoints.points,
      isManuallyDrawn: true,
    );
  }

  // PRODUCTION: read from user profile.
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
  solid,      // No animation, static color
  breathe,    // Pulsing opacity
  chase,      // Moving segment
  rainbow,    // Color cycling
  twinkle,    // Random sparkle
  wave,       // Oscillating pattern
  fire,       // Fire-like flickering
  explosive,  // Sudden bursts or flashes
  scanning,   // Scanning back and forth
  dripping,   // Dripping or falling motion
  bouncing,   // Bouncing motion
  morphing,   // Morphing/color-shifting
}

/// Helper to categorize WLED effects by consulting EffectDatabase.
EffectCategory categorizeEffect(int effectId) {
  final meta = EffectDatabase.getEffect(effectId);
  if (meta == null) return EffectCategory.chase;

  // Effects that override user colors get the rainbow renderer
  if (!meta.respectsColors) return EffectCategory.rainbow;

  switch (meta.motionType) {
    case MotionType.static:
      return EffectCategory.solid;
    case MotionType.pulsing:
      return EffectCategory.breathe;
    case MotionType.flowing:
      return EffectCategory.wave;
    case MotionType.chasing:
      return EffectCategory.chase;
    case MotionType.twinkling:
      return EffectCategory.twinkle;
    case MotionType.flickering:
      return EffectCategory.fire;
    case MotionType.explosive:
      return EffectCategory.explosive;
    case MotionType.scanning:
      return EffectCategory.scanning;
    case MotionType.dripping:
      return EffectCategory.dripping;
    case MotionType.bouncing:
      return EffectCategory.bouncing;
    case MotionType.morphing:
      return EffectCategory.morphing;
  }
}

/// Convert WLED speed (0-255) to animation duration
Duration speedToDuration(int wledSpeed) {
  // Dampen the speed mapping significantly for smooth, elegant preview animations
  // Map 0-255 to 8s (slowest) to 3s (fastest)
  // This ensures animations are always smooth and not chaotic
  final seconds = 8.0 - (wledSpeed / 255.0) * 5.0;
  return Duration(milliseconds: (seconds * 1000).round());
}

/// Convert WLED speed (0-255) to animation duration with effect-specific adjustments
Duration speedToDurationForEffect(int wledSpeed, EffectCategory category) {
  // Base duration calculation
  final baseDuration = speedToDuration(wledSpeed);

  // Apply effect-specific multipliers for optimal visual appearance
  switch (category) {
    case EffectCategory.twinkle:
      // Twinkle needs to be slower to avoid jarring sparkle changes
      return Duration(milliseconds: (baseDuration.inMilliseconds * 1.5).round());
    case EffectCategory.fire:
      // Fire looks best with moderate speed
      return Duration(milliseconds: (baseDuration.inMilliseconds * 1.2).round());
    case EffectCategory.chase:
      // Chase can be slightly faster for better visual flow
      return baseDuration;
    case EffectCategory.rainbow:
      // Rainbow benefits from slower color cycling
      return Duration(milliseconds: (baseDuration.inMilliseconds * 1.3).round());
    case EffectCategory.breathe:
    case EffectCategory.wave:
    case EffectCategory.solid:
    case EffectCategory.explosive:
    case EffectCategory.scanning:
    case EffectCategory.dripping:
    case EffectCategory.bouncing:
    case EffectCategory.morphing:
      return baseDuration;
  }
}
