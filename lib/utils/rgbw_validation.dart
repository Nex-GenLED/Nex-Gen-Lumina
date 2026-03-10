import 'package:flutter/foundation.dart';

/// Validates and normalizes an RGBW color array to guarantee all four channels
/// are present and within the valid 0–255 range.
///
/// Accepts arrays of length 3 (RGB — appends W=0) or 4 (RGBW).
/// Clamps out-of-range values rather than throwing.
/// Logs a warning if any channel was missing or invalid so issues surface in QA.
///
/// Returns a guaranteed `[R, G, B, W]` list with 4 valid integers.
List<int> validateRgbw(List<dynamic> color, {String? source}) {
  if (color.length < 3) {
    if (kDebugMode) {
      debugPrint('⚠️ RGBW validation: color has ${color.length} channels '
          '(need ≥3)${source != null ? ' from $source' : ''}');
    }
    // Pad with zeros to reach 4 channels
    final padded = List<int>.filled(4, 0);
    for (int i = 0; i < color.length && i < 4; i++) {
      padded[i] = _toClampedInt(color[i]);
    }
    return padded;
  }

  final r = _toClampedInt(color[0]);
  final g = _toClampedInt(color[1]);
  final b = _toClampedInt(color[2]);
  int w = 0;

  if (color.length >= 4) {
    w = _toClampedInt(color[3]);
  } else {
    if (kDebugMode) {
      debugPrint('⚠️ RGBW validation: W channel missing, defaulting to 0'
          '${source != null ? ' from $source' : ''}'
          ' — color: [$r, $g, $b]');
    }
  }

  return [r, g, b, w];
}

/// Validates a list of color arrays (e.g., the `col` field in a WLED segment).
/// Each sub-array is validated via [validateRgbw].
List<List<int>> validateRgbwList(List<dynamic> colors, {String? source}) {
  if (colors.isEmpty) return [[0, 0, 0, 0]];
  return colors.map((c) {
    if (c is List) {
      return validateRgbw(c, source: source);
    }
    if (kDebugMode) {
      debugPrint('⚠️ RGBW validation: expected List, got ${c.runtimeType}'
          '${source != null ? ' from $source' : ''}');
    }
    return [0, 0, 0, 0];
  }).toList();
}

/// Ensures every segment in a WLED payload has valid RGBW colors in its `col` field.
/// Mutates the payload in place and returns it for chaining.
Map<String, dynamic> ensurePayloadRgbw(Map<String, dynamic> payload, {String? source}) {
  final seg = payload['seg'];
  if (seg is! List) return payload;

  for (int i = 0; i < seg.length; i++) {
    final s = seg[i];
    if (s is! Map) continue;

    final col = s['col'];
    if (col is List && col.isNotEmpty) {
      s['col'] = validateRgbwList(col, source: source ?? 'payload seg[$i]');
    }

    // Also validate per-pixel 'i' arrays: [index, [r,g,b,w], index, [r,g,b,w], ...]
    final iArray = s['i'];
    if (iArray is List) {
      for (int j = 0; j < iArray.length; j++) {
        if (iArray[j] is List) {
          iArray[j] = validateRgbw(iArray[j] as List, source: source ?? 'payload seg[$i].i[$j]');
        }
      }
    }
  }

  return payload;
}

/// Safely converts a dynamic value to a clamped integer in 0–255 range.
int _toClampedInt(dynamic value) {
  if (value is int) return value.clamp(0, 255);
  if (value is double) return value.round().clamp(0, 255);
  if (value is String) {
    final parsed = int.tryParse(value) ?? double.tryParse(value)?.round();
    if (parsed != null) return parsed.clamp(0, 255);
  }
  return 0;
}
