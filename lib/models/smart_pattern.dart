import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;

/// SmartPattern represents a WLED-ready lighting pattern configuration.
///
/// Fields align with common WLED API parameters and app needs.
class SmartPattern {
  /// Unique identifier (UUID preferred)
  final String id;

  /// Human-readable name of the pattern
  final String name;

  /// Optional description of the pattern
  final String description;

  /// List of RGB color triplets, e.g., [[255,0,0],[0,255,0]]
  final List<List<int>> colors;

  /// WLED effect ID (fx)
  final int effectId;

  /// WLED speed (sx) 0-255
  final int speed;

  /// WLED intensity (ix) 0-255
  final int intensity;

  /// Optional WLED palette ID (pal)
  final int? paletteId;

  /// Direction flag (rev)
  final bool reverse;

  /// Bulb grouping (gp) 1-10
  final int grouping;

  /// Spacing/gaps (sp) 0-10
  final int spacing;

  /// Category for grouping (e.g., 'holiday', 'sports')
  final String category;

  const SmartPattern({
    required this.id,
    required this.name,
    this.description = '',
    required this.colors,
    required this.effectId,
    this.speed = 128,
    this.intensity = 128,
    this.paletteId,
    this.reverse = false,
    this.grouping = 1,
    this.spacing = 0,
    this.category = '',
  });

  /// Returns a WLED API-ready JSON structure.
  /// Example shape:
  /// {
  ///   'seg': [
  ///     {
  ///       'col': [[r, g, b, w], ...],  // RGBW format required by WLED
  ///       'fx': effectId,
  ///       'sx': speed,
  ///       'ix': intensity,
  ///       'rev': reverse,
  ///       'pal': paletteId? // included only when not null
  ///     }
  ///   ]
  /// }
  Map<String, dynamic> toJson() {
    // Convert RGB colors to RGBW format for WLED
    // Force W=0 for saturated colors to maintain color accuracy
    final rgbwColors = colors.take(3).map((rgb) {
      if (rgb.length >= 3) {
        return rgbToRgbw(rgb[0], rgb[1], rgb[2], forceZeroWhite: true);
      }
      return [255, 255, 255, 0]; // Fallback white
    }).toList();

    final seg = <String, dynamic>{
      'col': rgbwColors,
      'fx': effectId,
      'sx': speed,
      'ix': intensity,
      'rev': reverse,
      'grp': grouping,
      'spc': spacing,
    };
    if (paletteId != null) seg['pal'] = paletteId;
    return {'seg': [seg]};
  }
}
