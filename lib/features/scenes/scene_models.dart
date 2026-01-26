import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/features/design/design_models.dart';
import 'package:nexgen_command/models/smart_pattern.dart';

/// A Scene represents any saved lighting state that can be activated.
///
/// Scenes unify different sources of lighting configurations:
/// - Custom designs from Design Studio
/// - Patterns from the Pattern Library
/// - System presets (Off, Warm White, etc.)
/// - Captured snapshots of current state
///
/// This abstraction enables automations to reference any lighting state
/// consistently, regardless of how it was created.
class Scene {
  /// Unique identifier
  final String id;

  /// User-facing name
  final String name;

  /// Optional description
  final String? description;

  /// Type of scene (determines which payload field is used)
  final SceneType type;

  /// Icon name for display (Material Icons name)
  final String iconName;

  /// Owner user ID
  final String ownerId;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last modified timestamp
  final DateTime updatedAt;

  /// Preview colors for UI thumbnails (up to 4 RGB arrays)
  final List<List<int>> previewColors;

  /// Primary effect ID (for display purposes)
  final int? effectId;

  /// Brightness level (0-255)
  final int brightness;

  /// Tags for organization
  final List<String> tags;

  /// Whether this is a favorite
  final bool isFavorite;

  // ============== Source-specific payloads ==============
  // Only ONE of these should be non-null based on SceneType

  /// For SceneType.custom - full Design Studio design
  final CustomDesign? customDesign;

  /// For SceneType.library - pattern from library
  final SmartPattern? libraryPattern;

  /// For SceneType.system or SceneType.snapshot - raw WLED payload
  final Map<String, dynamic>? wledPayload;

  const Scene({
    required this.id,
    required this.name,
    this.description,
    required this.type,
    this.iconName = 'palette',
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.previewColors = const [],
    this.effectId,
    this.brightness = 200,
    this.tags = const [],
    this.isFavorite = false,
    this.customDesign,
    this.libraryPattern,
    this.wledPayload,
  });

  /// Create an empty scene for a user
  factory Scene.empty(String ownerId) {
    final now = DateTime.now();
    return Scene(
      id: '',
      name: 'New Scene',
      type: SceneType.custom,
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Create a scene from a CustomDesign
  factory Scene.fromDesign(CustomDesign design) {
    // Extract preview colors from the design
    final previewColors = <List<int>>[];
    for (final channel in design.channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(2)) {
        previewColors.add(group.color.take(3).toList());
        if (previewColors.length >= 4) break;
      }
      if (previewColors.length >= 4) break;
    }

    // Get primary effect from first included channel
    final primaryEffect = design.channels
        .where((ch) => ch.included)
        .map((ch) => ch.effectId)
        .firstOrNull;

    return Scene(
      id: 'design_${design.id}',
      name: design.name,
      description: design.description,
      type: SceneType.custom,
      iconName: 'design_services',
      ownerId: design.ownerId,
      createdAt: design.createdAt,
      updatedAt: design.updatedAt,
      previewColors: previewColors,
      effectId: primaryEffect,
      brightness: design.brightness,
      tags: design.tags,
      customDesign: design,
    );
  }

  /// Create a scene from a SmartPattern
  factory Scene.fromPattern(SmartPattern pattern, String ownerId) {
    final now = DateTime.now();
    return Scene(
      id: 'pattern_${pattern.id}',
      name: pattern.name,
      description: pattern.description,
      type: SceneType.library,
      iconName: _iconForCategory(pattern.category),
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
      previewColors: pattern.colors,
      effectId: pattern.effectId,
      brightness: 200,
      tags: [pattern.category],
      libraryPattern: pattern,
    );
  }

  /// Create a system preset scene
  factory Scene.systemPreset({
    required String id,
    required String name,
    required String description,
    required String iconName,
    required Map<String, dynamic> wledPayload,
    List<List<int>> previewColors = const [],
    int brightness = 200,
  }) {
    final now = DateTime.now();
    return Scene(
      id: 'system_$id',
      name: name,
      description: description,
      type: SceneType.system,
      iconName: iconName,
      ownerId: 'system',
      createdAt: now,
      updatedAt: now,
      previewColors: previewColors,
      brightness: brightness,
      wledPayload: wledPayload,
    );
  }

  /// Create a snapshot of current device state
  factory Scene.snapshot({
    required String name,
    required String ownerId,
    required Map<String, dynamic> wledPayload,
    List<List<int>> previewColors = const [],
    int? effectId,
    int brightness = 200,
  }) {
    final now = DateTime.now();
    return Scene(
      id: 'snapshot_${now.millisecondsSinceEpoch}',
      name: name,
      description: 'Captured on ${_formatDate(now)}',
      type: SceneType.snapshot,
      iconName: 'camera',
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
      previewColors: previewColors,
      effectId: effectId,
      brightness: brightness,
      wledPayload: wledPayload,
    );
  }

  static String _formatDate(DateTime date) {
    const months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    return '${months[date.month - 1]} ${date.day}, ${date.year}';
  }

  static String _iconForCategory(String category) {
    switch (category.toLowerCase()) {
      case 'holiday':
      case 'holidays':
        return 'celebration';
      case 'sports':
        return 'sports_football';
      case 'nature':
        return 'park';
      case 'mood':
        return 'mood';
      case 'seasonal':
        return 'wb_sunny';
      default:
        return 'palette';
    }
  }

  /// Get the WLED payload to apply this scene
  Map<String, dynamic> toWledPayload() {
    switch (type) {
      case SceneType.custom:
        return customDesign?.toWledPayload() ?? {'on': true, 'bri': brightness};
      case SceneType.library:
        if (libraryPattern != null) {
          return {
            'on': true,
            'bri': brightness,
            'seg': [{
              'col': libraryPattern!.colors,
              'fx': libraryPattern!.effectId,
              'sx': libraryPattern!.speed,
              'ix': libraryPattern!.intensity,
            }],
          };
        }
        return {'on': true, 'bri': brightness};
      case SceneType.system:
      case SceneType.snapshot:
        return wledPayload ?? {'on': true, 'bri': brightness};
    }
  }

  /// Copy with modifications
  Scene copyWith({
    String? id,
    String? name,
    String? description,
    SceneType? type,
    String? iconName,
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    List<List<int>>? previewColors,
    int? effectId,
    int? brightness,
    List<String>? tags,
    bool? isFavorite,
    CustomDesign? customDesign,
    SmartPattern? libraryPattern,
    Map<String, dynamic>? wledPayload,
  }) {
    return Scene(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      type: type ?? this.type,
      iconName: iconName ?? this.iconName,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      previewColors: previewColors ?? this.previewColors,
      effectId: effectId ?? this.effectId,
      brightness: brightness ?? this.brightness,
      tags: tags ?? this.tags,
      isFavorite: isFavorite ?? this.isFavorite,
      customDesign: customDesign ?? this.customDesign,
      libraryPattern: libraryPattern ?? this.libraryPattern,
      wledPayload: wledPayload ?? this.wledPayload,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'type': type.name,
      'icon_name': iconName,
      'owner_id': ownerId,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'preview_colors': previewColors,
      'effect_id': effectId,
      'brightness': brightness,
      'tags': tags,
      'is_favorite': isFavorite,
      // Store the appropriate payload based on type
      if (type == SceneType.custom && customDesign != null)
        'custom_design': customDesign!.toFirestore(),
      if (type == SceneType.library && libraryPattern != null)
        'library_pattern': {
          'id': libraryPattern!.id,
          'name': libraryPattern!.name,
          'colors': libraryPattern!.colors,
          'effect_id': libraryPattern!.effectId,
          'speed': libraryPattern!.speed,
          'intensity': libraryPattern!.intensity,
          'category': libraryPattern!.category,
        },
      if ((type == SceneType.system || type == SceneType.snapshot) && wledPayload != null)
        'wled_payload': wledPayload,
    };
  }

  /// Create from Firestore document
  factory Scene.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final typeStr = data['type'] as String? ?? 'custom';
    final type = SceneType.values.firstWhere(
      (t) => t.name == typeStr,
      orElse: () => SceneType.custom,
    );

    CustomDesign? customDesign;
    SmartPattern? libraryPattern;
    Map<String, dynamic>? wledPayload;

    // Parse the appropriate payload
    if (type == SceneType.custom && data['custom_design'] != null) {
      customDesign = CustomDesign.fromFirestoreData(
        doc.id,
        data['custom_design'] as Map<String, dynamic>,
      );
    } else if (type == SceneType.library && data['library_pattern'] != null) {
      final patternData = data['library_pattern'] as Map<String, dynamic>;
      libraryPattern = SmartPattern(
        id: patternData['id'] as String? ?? '',
        name: patternData['name'] as String? ?? '',
        description: '',
        colors: (patternData['colors'] as List?)
            ?.map((c) => (c as List).map((v) => v as int).toList())
            .toList() ?? [],
        effectId: patternData['effect_id'] as int? ?? 0,
        speed: patternData['speed'] as int? ?? 128,
        intensity: patternData['intensity'] as int? ?? 128,
        category: patternData['category'] as String? ?? '',
      );
    } else if (data['wled_payload'] != null) {
      wledPayload = Map<String, dynamic>.from(data['wled_payload'] as Map);
    }

    return Scene(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Scene',
      description: data['description'] as String?,
      type: type,
      iconName: data['icon_name'] as String? ?? 'palette',
      ownerId: data['owner_id'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      previewColors: (data['preview_colors'] as List?)
          ?.map((c) => (c as List).map((v) => v as int).toList())
          .toList() ?? [],
      effectId: data['effect_id'] as int?,
      brightness: data['brightness'] as int? ?? 200,
      tags: (data['tags'] as List?)?.map((t) => t as String).toList() ?? [],
      isFavorite: data['is_favorite'] as bool? ?? false,
      customDesign: customDesign,
      libraryPattern: libraryPattern,
      wledPayload: wledPayload,
    );
  }
}

/// Type of scene source
enum SceneType {
  /// Created in Design Studio
  custom,

  /// Saved from Pattern Library
  library,

  /// Built-in system preset (Off, Warm White, etc.)
  system,

  /// Captured snapshot of current device state
  snapshot,
}

/// Extension for scene type display
extension SceneTypeExtension on SceneType {
  String get displayName {
    switch (this) {
      case SceneType.custom:
        return 'Custom Design';
      case SceneType.library:
        return 'Pattern';
      case SceneType.system:
        return 'System';
      case SceneType.snapshot:
        return 'Snapshot';
    }
  }

  IconData get icon {
    switch (this) {
      case SceneType.custom:
        return Icons.design_services;
      case SceneType.library:
        return Icons.auto_awesome;
      case SceneType.system:
        return Icons.settings;
      case SceneType.snapshot:
        return Icons.camera_alt;
    }
  }

  Color get color {
    switch (this) {
      case SceneType.custom:
        return const Color(0xFF00E5FF); // Cyan
      case SceneType.library:
        return const Color(0xFF7C4DFF); // Purple
      case SceneType.system:
        return const Color(0xFF78909C); // Blue grey
      case SceneType.snapshot:
        return const Color(0xFFFFB74D); // Amber
    }
  }
}

/// Built-in system scenes
class SystemScenes {
  SystemScenes._();

  static final Scene off = Scene.systemPreset(
    id: 'off',
    name: 'Lights Off',
    description: 'Turn all lights off',
    iconName: 'power_settings_new',
    wledPayload: {'on': false},
    brightness: 0,
  );

  static final Scene warmWhite = Scene.systemPreset(
    id: 'warm_white',
    name: 'Warm White',
    description: 'Cozy warm white ambiance',
    iconName: 'wb_incandescent',
    wledPayload: {
      'on': true,
      'bri': 180,
      'seg': [{'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': [[255, 180, 100, 120]]}],
    },
    previewColors: [[255, 180, 100]],
    brightness: 180,
  );

  static final Scene brightWhite = Scene.systemPreset(
    id: 'bright_white',
    name: 'Bright White',
    description: 'Full brightness white',
    iconName: 'wb_sunny',
    wledPayload: {
      'on': true,
      'bri': 255,
      'seg': [{'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': [[255, 255, 255, 255]]}],
    },
    previewColors: [[255, 255, 255]],
    brightness: 255,
  );

  static final Scene nightLight = Scene.systemPreset(
    id: 'night_light',
    name: 'Night Light',
    description: 'Dim, warm glow',
    iconName: 'nights_stay',
    wledPayload: {
      'on': true,
      'bri': 30,
      'seg': [{'fx': 0, 'sx': 128, 'ix': 128, 'pal': 0, 'col': [[255, 140, 60, 40]]}],
    },
    previewColors: [[255, 140, 60]],
    brightness: 30,
  );

  static List<Scene> get all => [off, warmWhite, brightWhite, nightLight];
}
