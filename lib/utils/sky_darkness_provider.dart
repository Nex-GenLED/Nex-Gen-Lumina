import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

/// Calculates the current sky darkness level based on time of day and user's location.
///
/// Returns a value from 0.0 (full daylight) to 1.0 (full night).
/// Uses smooth transitions during twilight periods (civil twilight ~30 min before/after).
class SkyDarknessService {
  /// Calculate sky darkness at the current time for a given location.
  ///
  /// Returns:
  /// - 0.0 = Full daylight (sun is up)
  /// - 0.0-0.3 = Dawn/morning (sun rising)
  /// - 0.3-0.7 = Twilight transition
  /// - 0.7-1.0 = Dusk/evening (sun setting)
  /// - 1.0 = Full night (sun is down)
  static double calculateSkyDarkness({
    required double latitude,
    required double longitude,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();

    // Get sunrise/sunset for today
    final sunrise = SunUtils.sunriseLocal(latitude, longitude, now);
    final sunset = SunUtils.sunsetLocal(latitude, longitude, now);

    // If we can't calculate (polar regions), return based on time
    if (sunrise == null || sunset == null) {
      final hour = now.hour;
      if (hour >= 6 && hour < 18) return 0.0; // Daytime fallback
      return 1.0; // Nighttime fallback
    }

    // Define twilight periods (civil twilight ~30-40 minutes)
    const twilightMinutes = 40;
    final dawnStart = sunrise.subtract(const Duration(minutes: twilightMinutes));
    final dawnEnd = sunrise.add(const Duration(minutes: 20)); // Full brightness after sunrise
    final duskStart = sunset.subtract(const Duration(minutes: 20)); // Start dimming before sunset
    final duskEnd = sunset.add(const Duration(minutes: twilightMinutes));

    // Calculate darkness based on time
    if (now.isBefore(dawnStart)) {
      // Before dawn - full night
      return 1.0;
    } else if (now.isBefore(dawnEnd)) {
      // Dawn transition
      final totalDawn = dawnEnd.difference(dawnStart).inMinutes;
      final elapsed = now.difference(dawnStart).inMinutes;
      final progress = (elapsed / totalDawn).clamp(0.0, 1.0);
      // Smooth easing from night (1.0) to day (0.0)
      return _easeInOutCubic(1.0 - progress);
    } else if (now.isBefore(duskStart)) {
      // Full daylight
      return 0.0;
    } else if (now.isBefore(duskEnd)) {
      // Dusk transition
      final totalDusk = duskEnd.difference(duskStart).inMinutes;
      final elapsed = now.difference(duskStart).inMinutes;
      final progress = (elapsed / totalDusk).clamp(0.0, 1.0);
      // Smooth easing from day (0.0) to night (1.0)
      return _easeInOutCubic(progress);
    } else {
      // After dusk - full night
      return 1.0;
    }
  }

  /// Get a color tint for the sky based on darkness level and time of day.
  ///
  /// During twilight, adds warm orange/pink tones.
  /// At night, adds deep blue tones.
  static Color getSkyTintColor({
    required double darkness,
    required double latitude,
    required double longitude,
    DateTime? currentTime,
  }) {
    final now = currentTime ?? DateTime.now();
    final sunrise = SunUtils.sunriseLocal(latitude, longitude, now);
    final sunset = SunUtils.sunsetLocal(latitude, longitude, now);

    // Determine if we're in golden hour (near sunrise/sunset)
    bool isGoldenHour = false;
    if (sunrise != null && sunset != null) {
      final minToSunrise = now.difference(sunrise).inMinutes.abs();
      final minToSunset = now.difference(sunset).inMinutes.abs();
      isGoldenHour = minToSunrise < 45 || minToSunset < 45;
    }

    if (darkness < 0.1) {
      // Full daylight - no tint (transparent)
      return Colors.transparent;
    } else if (darkness < 0.5 && isGoldenHour) {
      // Golden hour - warm orange/pink tint
      final warmth = (darkness * 2).clamp(0.0, 1.0);
      return Color.lerp(
        Colors.transparent,
        const Color(0x40FF8844), // Warm orange
        warmth,
      )!;
    } else if (darkness < 0.7) {
      // Twilight - purple/pink tint transitioning to blue
      final twilightProgress = ((darkness - 0.3) / 0.4).clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0x30FF6688), // Pink/purple
        const Color(0x50102040), // Dark blue
        twilightProgress,
      )!;
    } else {
      // Night - deep blue tint
      final nightIntensity = ((darkness - 0.7) / 0.3).clamp(0.0, 1.0);
      return Color.lerp(
        const Color(0x50102040), // Dark blue
        const Color(0x70081020), // Deeper blue
        nightIntensity,
      )!;
    }
  }

  /// Cubic ease-in-out function for smooth transitions.
  static double _easeInOutCubic(double t) {
    return t < 0.5
        ? 4 * t * t * t
        : 1 - pow(-2 * t + 2, 3) / 2;
  }
}

/// Provider that returns the current sky darkness level (0.0-1.0).
///
/// Updates every minute to track time changes.
/// Returns 0.0 if user location is not set.
final skyDarknessProvider = StreamProvider<double>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(
    data: (p) => p,
    orElse: () => null,
  );

  // If no location, default to 0 (daylight)
  if (profile?.latitude == null || profile?.longitude == null) {
    return Stream.value(0.0);
  }

  final lat = profile!.latitude!;
  final lon = profile.longitude!;

  // Create a stream that emits every minute
  return Stream.periodic(const Duration(minutes: 1), (_) {
    return SkyDarknessService.calculateSkyDarkness(
      latitude: lat,
      longitude: lon,
    );
  }).asyncMap((darkness) async {
    return darkness;
  });
});

/// Provider for the current sky darkness value (non-stream, for immediate use).
final currentSkyDarknessProvider = Provider<double>((ref) {
  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(
    data: (p) => p,
    orElse: () => null,
  );

  if (profile?.latitude == null || profile?.longitude == null) {
    // Fallback based on current hour if no location
    final hour = DateTime.now().hour;
    if (hour >= 7 && hour < 18) return 0.0;
    if (hour >= 18 && hour < 20) return 0.4;
    if (hour >= 20 && hour < 21) return 0.7;
    return 1.0;
  }

  return SkyDarknessService.calculateSkyDarkness(
    latitude: profile!.latitude!,
    longitude: profile.longitude!,
  );
});

/// Provider for the sky tint color based on time of day.
final skyTintColorProvider = Provider<Color>((ref) {
  final darkness = ref.watch(currentSkyDarknessProvider);
  final profileAsync = ref.watch(currentUserProfileProvider);
  final profile = profileAsync.maybeWhen(
    data: (p) => p,
    orElse: () => null,
  );

  if (profile?.latitude == null || profile?.longitude == null) {
    // Fallback tint based on darkness
    if (darkness < 0.3) return Colors.transparent;
    if (darkness < 0.7) return const Color(0x30102040);
    return const Color(0x50081020);
  }

  return SkyDarknessService.getSkyTintColor(
    darkness: darkness,
    latitude: profile!.latitude!,
    longitude: profile.longitude!,
  );
});

/// Provider that indicates if it's currently night time.
final isNightTimeProvider = Provider<bool>((ref) {
  final darkness = ref.watch(currentSkyDarknessProvider);
  return darkness > 0.5;
});
