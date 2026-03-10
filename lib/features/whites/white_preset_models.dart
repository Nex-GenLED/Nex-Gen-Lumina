import 'package:flutter/material.dart';

/// Represents a white lighting preset with RGBW values
class WhitePreset {
  final String id;
  final String name;
  final int r;
  final int g;
  final int b;
  final int w;

  const WhitePreset({
    required this.id,
    required this.name,
    required this.r,
    required this.g,
    required this.b,
    required this.w,
  });

  /// The visual preview color (ignoring W channel since screens can't show it)
  Color get previewColor {
    // Blend the RGB with a warm white tint proportional to W value
    final wFactor = w / 255.0;
    final rBlend = (r + (255 * wFactor)).clamp(0, 255).toInt();
    final gBlend = (g + (235 * wFactor)).clamp(0, 255).toInt();
    final bBlend = (b + (200 * wFactor)).clamp(0, 255).toInt();
    return Color.fromARGB(255, rBlend, gBlend, bBlend);
  }

  /// WLED-compatible RGBW color array
  List<int> get rgbwArray => [r, g, b, w];

  /// Build a WLED JSON payload to apply this white preset
  Map<String, dynamic> toWledPayload({int brightness = 220}) {
    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': 0,
          'sx': 128,
          'ix': 128,
          'pal': 0,
          'col': [[r, g, b, w]],
        }
      ],
    };
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'r': r,
        'g': g,
        'b': b,
        'w': w,
      };

  factory WhitePreset.fromJson(Map<String, dynamic> json) => WhitePreset(
        id: json['id'] as String? ?? 'custom',
        name: json['name'] as String? ?? 'Custom White',
        r: (json['r'] as num?)?.toInt() ?? 0,
        g: (json['g'] as num?)?.toInt() ?? 0,
        b: (json['b'] as num?)?.toInt() ?? 0,
        w: (json['w'] as num?)?.toInt() ?? 255,
      );

  WhitePreset copyWith({
    String? id,
    String? name,
    int? r,
    int? g,
    int? b,
    int? w,
  }) =>
      WhitePreset(
        id: id ?? this.id,
        name: name ?? this.name,
        r: r ?? this.r,
        g: g ?? this.g,
        b: b ?? this.b,
        w: w ?? this.w,
      );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WhitePreset &&
          id == other.id &&
          r == other.r &&
          g == other.g &&
          b == other.b &&
          w == other.w;

  @override
  int get hashCode => Object.hash(id, r, g, b, w);
}

/// The 5 built-in white presets
const kWhitePresets = [
  WhitePreset(id: 'warm_white', name: 'Warm White', r: 255, g: 147, b: 41, w: 200),
  WhitePreset(id: 'soft_white', name: 'Soft White', r: 255, g: 197, b: 143, w: 220),
  WhitePreset(id: 'natural_white', name: 'Natural White', r: 200, g: 200, b: 180, w: 240),
  WhitePreset(id: 'cool_white', name: 'Cool White', r: 180, g: 200, b: 255, w: 245),
  WhitePreset(id: 'bright_white', name: 'Bright White', r: 0, g: 0, b: 0, w: 255),
];

/// Given a primary white selection, suggest the best complement
WhitePreset suggestComplement(WhitePreset primary) {
  switch (primary.id) {
    case 'warm_white':
      return kWhitePresets[4]; // Bright White
    case 'bright_white':
      return kWhitePresets[0]; // Warm White
    case 'soft_white':
      return kWhitePresets[3]; // Cool White
    case 'cool_white':
      return kWhitePresets[1]; // Soft White
    case 'natural_white':
      // Natural leans slightly warm → suggest cool
      return kWhitePresets[3]; // Cool White
    default:
      // Custom: calculate color temperature direction
      final warmth = primary.r - primary.b;
      if (warmth > 0) {
        return kWhitePresets[4]; // Bright White
      } else {
        return kWhitePresets[0]; // Warm White
      }
  }
}
