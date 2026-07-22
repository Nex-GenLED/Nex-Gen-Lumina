import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/services/commercial/daylight_suppression_service.dart';

/// Calculates a brightness multiplier for a channel based on its daylight
/// suppression settings and the current sunrise/sunset window.
///
/// Supports a 10-minute linear fade at both sunrise and sunset boundaries
/// so lights ramp smoothly instead of snapping on/off.
class DaylightBrightnessModifier {
  const DaylightBrightnessModifier();

  /// Duration of the sunrise/sunset fade ramp.
  static const _fadeDuration = Duration(minutes: 10);

  /// Returns a brightness multiplier in the range [0.0, 1.0].
  ///
  /// * 1.0 — full brightness (nighttime, or suppression disabled).
  /// * 0.20 — dimmed (SOFT_DIM during daylight).
  /// * 0.0 — off (HARD_OFF during daylight).
  ///
  /// The value transitions linearly over 10 minutes at sunrise and sunset.
  double getBrightnessMultiplier(
    ChannelRoleConfig config,
    DaylightWindow window,
  ) {
    // Suppression disabled at channel level or via mode.
    if (!config.daylightSuppression ||
        config.daylightMode == DaylightMode.disabled) {
      return 1.0;
    }

    final now = DateTime.now();

    // Target multiplier when fully in daylight.
    final double suppressedTarget;
    switch (config.daylightMode) {
      case DaylightMode.softDim:
        suppressedTarget = 0.20;
      case DaylightMode.hardOff:
        suppressedTarget = 0.0;
      case DaylightMode.disabled:
        return 1.0;
    }

    // ---- Sunrise fade (night → day) ----
    // Fade from 1.0 down to suppressedTarget over 10 min starting at sunrise.
    final sunriseStart = window.sunrise;
    final sunriseEnd = sunriseStart.add(_fadeDuration);

    // ---- Sunset fade (day → night) ----
    // Fade from suppressedTarget back up to 1.0 over 10 min starting at sunset.
    final sunsetStart = window.sunset;
    final sunsetEnd = sunsetStart.add(_fadeDuration);

    // Before sunrise — full brightness (nighttime).
    if (now.isBefore(sunriseStart)) {
      return 1.0;
    }

    // During sunrise ramp — fade from 1.0 → suppressedTarget.
    if (now.isBefore(sunriseEnd)) {
      final progress = _progress(sunriseStart, sunriseEnd, now);
      return _lerp(1.0, suppressedTarget, progress);
    }

    // Full daylight — between sunrise ramp end and sunset start.
    if (now.isBefore(sunsetStart)) {
      return suppressedTarget;
    }

    // During sunset ramp — fade from suppressedTarget → 1.0.
    if (now.isBefore(sunsetEnd)) {
      final progress = _progress(sunsetStart, sunsetEnd, now);
      return _lerp(suppressedTarget, 1.0, progress);
    }

    // After sunset — full brightness (nighttime).
    return 1.0;
  }

  /// Linear interpolation between [a] and [b] by [t] (0.0–1.0).
  static double _lerp(double a, double b, double t) => a + (b - a) * t;

  /// Returns a 0.0–1.0 progress value for [now] between [start] and [end].
  static double _progress(DateTime start, DateTime end, DateTime now) {
    final total = end.difference(start).inMilliseconds;
    if (total <= 0) return 1.0;
    final elapsed = now.difference(start).inMilliseconds;
    return (elapsed / total).clamp(0.0, 1.0);
  }
}
