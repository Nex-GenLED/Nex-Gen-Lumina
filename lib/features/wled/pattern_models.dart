// Models for Pattern Library
import 'package:flutter/material.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;

/// Represents a folder/category for patterns in the Pattern Library.
class PatternCategory {
  final String id;
  final String name;
  final String imageUrl;

  const PatternCategory({required this.id, required this.name, required this.imageUrl});

  factory PatternCategory.fromJson(Map<String, dynamic> json) => PatternCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
      );

  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'imageUrl': imageUrl};
}

/// Represents an individual pattern/effect, including its WLED JSON payload.
class PatternItem {
  final String id;
  final String name;
  final String imageUrl;
  final String categoryId;
  final Map<String, dynamic> wledPayload;

  const PatternItem({
    required this.id,
    required this.name,
    required this.imageUrl,
    required this.categoryId,
    required this.wledPayload,
  });

  factory PatternItem.fromJson(Map<String, dynamic> json) => PatternItem(
        id: json['id'] as String,
        name: json['name'] as String,
        imageUrl: json['imageUrl'] as String,
        categoryId: json['categoryId'] as String,
        wledPayload: (json['wledPayload'] as Map).cast<String, dynamic>(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'imageUrl': imageUrl,
        'categoryId': categoryId,
        'wledPayload': wledPayload,
      };

  PatternItem copyWith({String? name, String? imageUrl, String? categoryId, Map<String, dynamic>? wledPayload}) => PatternItem(
        id: id,
        name: name ?? this.name,
        imageUrl: imageUrl ?? this.imageUrl,
        categoryId: categoryId ?? this.categoryId,
        wledPayload: wledPayload != null ? Map<String, dynamic>.from(wledPayload) : this.wledPayload,
      );

  @override
  String toString() => 'PatternItem(id: '+id+', name: '+name+')';
}

/// Represents a Sub-Category under a main PatternCategory.
/// Each sub-category carries a small palette of theme colors to drive UI presets.
class SubCategory {
  final String id;
  final String name;
  final List<Color> themeColors;
  final String parentCategoryId;

  const SubCategory({required this.id, required this.name, required this.themeColors, required this.parentCategoryId});

  factory SubCategory.fromJson(Map<String, dynamic> json) => SubCategory(
        id: json['id'] as String,
        name: json['name'] as String,
        themeColors: ((json['themeColors'] as List?) ?? const <dynamic>[])
            .whereType<int>()
            .map((v) => Color(v))
            .toList(growable: false),
        parentCategoryId: json['parentCategoryId'] as String,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        // Store theme colors as ARGB ints
        'themeColors': themeColors.map((c) => c.value).toList(growable: false),
        'parentCategoryId': parentCategoryId,
      };
}

/// Rich data model for pattern suggestions/previews.
///
/// Used by the Pattern Library UI and recommendation engines.
/// Includes effect details, motion type, direction, and WLED payload.
///
/// IMPORTANT: When choosing effectId, be aware that some WLED effects are
/// "palette-based" and ignore the segment colors (col array). These include:
/// - 110 (Flow), 9 (Colorful), 11 (Rainbow), 63 (Pride 2015), etc.
///
/// Effects that properly use segment colors include:
/// - 0 (Solid), 1 (Blink), 2 (Breathe), 9 (Chase), 12 (Theater Chase),
/// - 28 (Chase 2), 41 (Running), 42 (Saw), 65 (Comet), 66 (Fireworks), etc.
class GradientPattern {
  final String name;
  final String? subtitle; // e.g., "Gold chasing Red" or "Static warm glow"
  final List<Color> colors;
  final int effectId; // WLED fx value
  final String? effectName; // e.g., "Chase", "Breathe", "Solid"
  final String? direction; // e.g., "left", "right", "center-out", "none"
  final bool isStatic;
  final int speed; // 0-255
  final int intensity; // 0-255
  final int brightness; // 0-255

  const GradientPattern({
    required this.name,
    this.subtitle,
    required this.colors,
    this.effectId = 0,
    this.effectName,
    this.direction,
    this.isStatic = true,
    this.speed = 128,
    this.intensity = 128,
    this.brightness = 210,
  });

  /// Generate WLED payload from this pattern
  /// Forces W=0 for saturated colors to maintain color accuracy
  Map<String, dynamic> toWledPayload() {
    // Force W=0 for pattern colors to prevent white LED from washing out saturated colors
    final cols = colors.take(3).map((c) => rgbToRgbw(c.red, c.green, c.blue, forceZeroWhite: true)).toList();
    if (cols.isEmpty) cols.add(rgbToRgbw(255, 255, 255, forceZeroWhite: true));

    return {
      'on': true,
      'bri': brightness,
      'seg': [
        {
          'fx': effectId,
          'sx': speed,
          'ix': intensity,
          'pal': 0,
          'col': cols,
        }
      ]
    };
  }
}
