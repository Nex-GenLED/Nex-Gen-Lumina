import 'dart:ui' show Color;

/// A named brand color used for commercial lighting design generation.
class BrandColor {
  final String id;
  final String colorName;
  final String hexCode;
  final String roleTag;
  final bool activeInEngine;
  final String? notes;

  const BrandColor({
    required this.id,
    required this.colorName,
    required this.hexCode,
    this.roleTag = 'primary',
    this.activeInEngine = true,
    this.notes,
  });

  factory BrandColor.fromJson(Map<String, dynamic> json) {
    return BrandColor(
      id: json['id'] as String,
      colorName: json['color_name'] as String,
      hexCode: json['hex_code'] as String,
      roleTag: (json['role_tag'] as String?) ?? 'primary',
      activeInEngine: (json['active_in_engine'] as bool?) ?? true,
      notes: json['notes'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'color_name': colorName,
        'hex_code': hexCode,
        'role_tag': roleTag,
        'active_in_engine': activeInEngine,
        if (notes != null) 'notes': notes,
      };

  BrandColor copyWith({
    String? id,
    String? colorName,
    String? hexCode,
    String? roleTag,
    bool? activeInEngine,
    String? notes,
  }) {
    return BrandColor(
      id: id ?? this.id,
      colorName: colorName ?? this.colorName,
      hexCode: hexCode ?? this.hexCode,
      roleTag: roleTag ?? this.roleTag,
      activeInEngine: activeInEngine ?? this.activeInEngine,
      notes: notes ?? this.notes,
    );
  }

  /// Convert hex code to a Flutter Color.
  Color toColor() => Color(int.parse('FF$hexCode', radix: 16));
}
