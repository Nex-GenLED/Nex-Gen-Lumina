import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';

/// Extension methods for tracking pattern usage (for Ref)
extension UsageTracking on Ref {
  /// Track when a GradientPattern is applied to the device
  Future<void> trackPatternUsage({
    required GradientPattern pattern,
    String source = 'manual',
  }) async {
    try {
      final colorNames = pattern.colors.map((c) {
        return _colorToName(c);
      }).toList();

      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: pattern.name,
        colorNames: colorNames,
        effectId: pattern.effectId,
        effectName: pattern.effectName,
        brightness: pattern.brightness,
        speed: pattern.speed,
        intensity: pattern.intensity,
        wledPayload: pattern.toWledPayload(),
      );

      debugPrint('📊 Tracked usage: ${pattern.name} (source: $source)');
    } catch (e) {
      debugPrint('❌ trackPatternUsage failed: $e');
    }
  }

  /// Track when a custom WLED payload is applied
  Future<void> trackWledPayload({
    required Map<String, dynamic> payload,
    String? patternName,
    String source = 'manual',
  }) async {
    try {
      // Extract info from payload
      final seg = (payload['seg'] as List?)?.firstOrNull as Map<String, dynamic>?;
      final effectId = seg?['fx'] as int?;
      final speed = seg?['sx'] as int?;
      final intensity = seg?['ix'] as int?;
      final brightness = payload['bri'] as int?;

      // Extract colors from payload
      List<String>? colorNames;
      final cols = seg?['col'] as List?;
      if (cols != null && cols.isNotEmpty) {
        colorNames = [];
        for (final col in cols) {
          if (col is List && col.length >= 3) {
            final r = (col[0] as num).toInt();
            final g = (col[1] as num).toInt();
            final b = (col[2] as num).toInt();
            colorNames.add(_rgbToName(r, g, b));
          }
        }
      }

      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: patternName,
        colorNames: colorNames,
        effectId: effectId,
        brightness: brightness,
        speed: speed,
        intensity: intensity,
        wledPayload: payload,
      );

      debugPrint('📊 Tracked WLED payload (source: $source)');
    } catch (e) {
      debugPrint('❌ trackWledPayload failed: $e');
    }
  }

  /// Track basic on/off usage
  Future<void> trackPowerToggle({
    required bool isOn,
    String source = 'manual',
  }) async {
    try {
      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: isOn ? 'Power On' : 'Power Off',
        wledPayload: {'on': isOn},
      );
    } catch (e) {
      debugPrint('❌ trackPowerToggle failed: $e');
    }
  }
}

/// Extension methods for tracking pattern usage (for WidgetRef)
extension UsageTrackingWidget on WidgetRef {
  /// Track when a GradientPattern is applied to the device
  Future<void> trackPatternUsage({
    required GradientPattern pattern,
    String source = 'manual',
  }) async {
    try {
      final colorNames = pattern.colors.map((c) {
        return _colorToName(c);
      }).toList();

      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: pattern.name,
        colorNames: colorNames,
        effectId: pattern.effectId,
        effectName: pattern.effectName,
        brightness: pattern.brightness,
        speed: pattern.speed,
        intensity: pattern.intensity,
        wledPayload: pattern.toWledPayload(),
      );

      debugPrint('📊 Tracked usage: ${pattern.name} (source: $source)');
    } catch (e) {
      debugPrint('❌ trackPatternUsage failed: $e');
    }
  }

  /// Track when a custom WLED payload is applied
  Future<void> trackWledPayload({
    required Map<String, dynamic> payload,
    String? patternName,
    String source = 'manual',
  }) async {
    try {
      // Extract info from payload
      final seg = (payload['seg'] as List?)?.firstOrNull as Map<String, dynamic>?;
      final effectId = seg?['fx'] as int?;
      final speed = seg?['sx'] as int?;
      final intensity = seg?['ix'] as int?;
      final brightness = payload['bri'] as int?;

      // Extract colors
      final colorNames = <String>[];
      final cols = seg?['col'] as List?;
      if (cols != null) {
        for (final col in cols) {
          if (col is List && col.length >= 3) {
            final r = (col[0] as num).toInt();
            final g = (col[1] as num).toInt();
            final b = (col[2] as num).toInt();
            colorNames.add(_rgbToName(r, g, b));
          }
        }
      }

      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: patternName,
        colorNames: colorNames,
        effectId: effectId,
        brightness: brightness,
        speed: speed,
        intensity: intensity,
        wledPayload: payload,
      );

      debugPrint('📊 Tracked WLED payload (source: $source)');
    } catch (e) {
      debugPrint('❌ trackWledPayload failed: $e');
    }
  }

  /// Track basic on/off usage
  Future<void> trackPowerToggle({
    required bool isOn,
    String source = 'manual',
  }) async {
    try {
      await read(usageLoggerNotifierProvider.notifier).logUsage(
        source: source,
        patternName: isOn ? 'Power On' : 'Power Off',
        wledPayload: {'on': isOn},
      );
    } catch (e) {
      debugPrint('❌ trackPowerToggle failed: $e');
    }
  }
}

/// Convert Flutter Color to a human-readable name
String _colorToName(Color color) {
  final r = color.red;
  final g = color.green;
  final b = color.blue;

  return _rgbToName(r, g, b);
}

/// Convert RGB values to a color name
String _rgbToName(int r, int g, int b) {
  // Pure primary colors
  if (r > 200 && g < 50 && b < 50) return 'red';
  if (r < 50 && g > 200 && b < 50) return 'green';
  if (r < 50 && g < 50 && b > 200) return 'blue';

  // Secondary colors
  if (r > 200 && g > 200 && b < 50) return 'yellow';
  if (r > 200 && g < 50 && b > 200) return 'magenta';
  if (r < 50 && g > 200 && b > 200) return 'cyan';

  // White/warm tones
  if (r > 200 && g > 200 && b > 200) return 'white';
  if (r > 200 && g > 150 && b < 100) return 'warm_white';
  if (r > 200 && g > 100 && b < 50) return 'orange';

  // Other common colors
  if (r > 100 && g < 50 && b > 100) return 'purple';
  if (r > 200 && g > 100 && b > 100) return 'pink';
  if (r > 150 && g > 100 && b < 50) return 'amber';

  // Fallback to hex representation
  return '#${r.toRadixString(16).padLeft(2, '0')}${g.toRadixString(16).padLeft(2, '0')}${b.toRadixString(16).padLeft(2, '0')}';
}
