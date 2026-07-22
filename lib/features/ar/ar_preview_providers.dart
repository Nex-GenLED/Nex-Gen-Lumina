import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_effects_catalog.dart'
    show WledEffectsCatalog;
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

/// Helper to categorize WLED effects for preview rendering.
///
/// Routes through [WledEffectsCatalog] — the single authoritative
/// effect-id → category map shared by every preview surface (#6). This
/// previously consulted the divergent `EffectDatabase`, whose id space
/// disagreed with canonical WLED (e.g. id 37 = "Candle"/flickering there vs
/// "Chase 2" in WLED), which made chases mis-render as flame on the roofline.
/// Now the roofline, the tile preview, the theme-selection strip, and the
/// chat strip all derive their render category from the same catalog category.
EffectCategory categorizeEffect(int effectId) {
  final effect = WledEffectsCatalog.getById(effectId);
  if (effect == null) return EffectCategory.chase;

  switch (effect.category) {
    case 'Basic':
      // Basic spans static, breathe, and fade variants — sub-classify by id
      // to mirror the tile preview (effect_preview_widget.getPreviewType).
      if (effectId == 2 ||
          effectId == 12 ||
          effectId == 18 ||
          effectId == 56 ||
          effectId == 86 ||
          effectId == 100) {
        return EffectCategory.breathe;
      }
      return EffectCategory.solid;
    case 'Wipe':
    case 'Ripple':
    case 'Ambient':
      return EffectCategory.wave;
    case 'Chase':
    case 'Meteor':
      return EffectCategory.chase;
    case 'Scanner':
      return EffectCategory.scanning;
    case 'Sparkle':
    case 'Holiday':
      return EffectCategory.twinkle;
    case 'Fire':
      return EffectCategory.fire;
    case 'Fireworks':
      return EffectCategory.explosive;
    case 'Rainbow':
      return EffectCategory.rainbow;
    case 'Strobe':
      return EffectCategory.breathe;
    case 'Game':
      return EffectCategory.bouncing;
    case 'Noise':
    case '2D':
    case 'Audio':
    default:
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
