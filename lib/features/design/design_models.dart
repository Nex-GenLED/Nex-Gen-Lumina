import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/models/segment_aware_pattern.dart';

/// Represents a complete custom design that can be saved and applied to WLED devices.
class CustomDesign {
  final String id;
  final String name;
  final String? description;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String ownerId;

  /// Per-channel configurations
  final List<ChannelDesign> channels;

  /// Global brightness (0-255)
  final int brightness;

  /// Searchable tags for organization
  final List<String> tags;

  /// Reference to roofline configuration used (for segment mode)
  final String? rooflineConfigId;

  /// Whether this design was generated from segment-aware pattern
  final bool isSegmentAware;

  /// Pattern template type used (for segment mode)
  final PatternTemplateType? templateType;

  /// LED color groups for segment-aware patterns
  final List<LedColorGroup>? segmentColorGroups;

  /// Segment pattern configuration (anchor color, spacing, etc.)
  final Map<String, dynamic>? segmentPatternConfig;

  const CustomDesign({
    required this.id,
    required this.name,
    this.description,
    required this.createdAt,
    required this.updatedAt,
    required this.ownerId,
    required this.channels,
    this.brightness = 200,
    this.tags = const [],
    this.rooflineConfigId,
    this.isSegmentAware = false,
    this.templateType,
    this.segmentColorGroups,
    this.segmentPatternConfig,
  });

  CustomDesign copyWith({
    String? id,
    String? name,
    String? description,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? ownerId,
    List<ChannelDesign>? channels,
    int? brightness,
    List<String>? tags,
    String? rooflineConfigId,
    bool? isSegmentAware,
    PatternTemplateType? templateType,
    List<LedColorGroup>? segmentColorGroups,
    Map<String, dynamic>? segmentPatternConfig,
  }) {
    return CustomDesign(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      ownerId: ownerId ?? this.ownerId,
      channels: channels ?? this.channels,
      brightness: brightness ?? this.brightness,
      tags: tags ?? this.tags,
      rooflineConfigId: rooflineConfigId ?? this.rooflineConfigId,
      isSegmentAware: isSegmentAware ?? this.isSegmentAware,
      templateType: templateType ?? this.templateType,
      segmentColorGroups: segmentColorGroups ?? this.segmentColorGroups,
      segmentPatternConfig: segmentPatternConfig ?? this.segmentPatternConfig,
    );
  }

  /// Creates a new empty design for the editor
  factory CustomDesign.empty(String ownerId) {
    final now = DateTime.now();
    return CustomDesign(
      id: '',
      name: 'Untitled Design',
      createdAt: now,
      updatedAt: now,
      ownerId: ownerId,
      channels: [],
      brightness: 200,
    );
  }

  /// Creates from Firestore document
  factory CustomDesign.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data()!;
    return CustomDesign.fromFirestoreData(doc.id, data);
  }

  /// Creates from raw Firestore data with explicit ID
  factory CustomDesign.fromFirestoreData(String id, Map<String, dynamic> data) {
    // Parse template type if present
    PatternTemplateType? parsedTemplateType;
    final templateTypeStr = data['template_type'] as String?;
    if (templateTypeStr != null) {
      parsedTemplateType = PatternTemplateType.values.firstWhere(
        (t) => t.name == templateTypeStr,
        orElse: () => PatternTemplateType.downlighting,
      );
    }

    return CustomDesign(
      id: id,
      name: data['name'] as String? ?? 'Untitled',
      description: data['description'] as String?,
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      ownerId: data['owner_id'] as String? ?? '',
      channels: (data['channels'] as List<dynamic>?)
              ?.map((c) => ChannelDesign.fromJson(c as Map<String, dynamic>))
              .toList() ??
          [],
      brightness: (data['brightness'] as int?) ?? 200,
      tags: (data['tags'] as List<dynamic>?)?.cast<String>() ?? [],
      rooflineConfigId: data['roofline_config_id'] as String?,
      isSegmentAware: data['is_segment_aware'] as bool? ?? false,
      templateType: parsedTemplateType,
      segmentColorGroups: (data['segment_color_groups'] as List<dynamic>?)
              ?.map((g) => LedColorGroup.fromJson(g as Map<String, dynamic>))
              .toList(),
      segmentPatternConfig: data['segment_pattern_config'] as Map<String, dynamic>?,
    );
  }

  /// Converts to Firestore document data
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'description': description,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'owner_id': ownerId,
      'channels': channels.map((c) => c.toJson()).toList(),
      'brightness': brightness,
      'tags': tags,
      if (rooflineConfigId != null) 'roofline_config_id': rooflineConfigId,
      'is_segment_aware': isSegmentAware,
      if (templateType != null) 'template_type': templateType!.name,
      if (segmentColorGroups != null)
        'segment_color_groups': segmentColorGroups!.map((g) => g.toJson()).toList(),
      if (segmentPatternConfig != null) 'segment_pattern_config': segmentPatternConfig,
    };
  }

  /// Converts this design to a WLED JSON API payload
  Map<String, dynamic> toWledPayload() {
    final segments = <Map<String, dynamic>>[];

    for (final channel in channels) {
      if (!channel.included) continue;

      // WLED supports up to 3 colors in col array
      final colors = channel.colorGroups
          .take(3)
          .map((g) => g.color)
          .toList();

      // If no colors defined, use white
      if (colors.isEmpty) {
        colors.add([255, 255, 255, 0]);
      }

      segments.add({
        'id': channel.channelId,
        'col': colors,
        'fx': channel.effectId,
        'sx': channel.speed,
        'ix': channel.intensity,
        'rev': channel.reverse,
      });
    }

    return {
      'on': true,
      'bri': brightness,
      'seg': segments,
    };
  }

  /// Get preview colors for UI display (up to 4 colors)
  List<List<int>> get previewColors {
    final colors = <List<int>>[];
    for (final channel in channels.where((ch) => ch.included)) {
      for (final group in channel.colorGroups.take(2)) {
        colors.add(group.color.take(3).toList());
        if (colors.length >= 4) break;
      }
      if (colors.length >= 4) break;
    }
    return colors;
  }

  /// Get primary effect ID from first included channel
  int? get primaryEffectId {
    return channels
        .where((ch) => ch.included)
        .map((ch) => ch.effectId)
        .firstOrNull;
  }
}

/// Configuration for a single channel/segment in the design.
class ChannelDesign {
  /// Maps to WLED segment ID
  final int channelId;

  /// Display name for the channel
  final String channelName;

  /// Whether this channel is active in the design
  final bool included;

  /// LED color assignments (groups of LEDs with same color)
  final List<LedColorGroup> colorGroups;

  /// WLED effect ID (0 = Solid)
  final int effectId;

  /// Animation speed (0-255)
  final int speed;

  /// Effect intensity (0-255)
  final int intensity;

  /// Direction of effect
  final bool reverse;

  /// Total LED count for this channel (for visualization)
  final int ledCount;

  const ChannelDesign({
    required this.channelId,
    required this.channelName,
    this.included = true,
    this.colorGroups = const [],
    this.effectId = 0,
    this.speed = 128,
    this.intensity = 128,
    this.reverse = false,
    this.ledCount = 0,
  });

  ChannelDesign copyWith({
    int? channelId,
    String? channelName,
    bool? included,
    List<LedColorGroup>? colorGroups,
    int? effectId,
    int? speed,
    int? intensity,
    bool? reverse,
    int? ledCount,
  }) {
    return ChannelDesign(
      channelId: channelId ?? this.channelId,
      channelName: channelName ?? this.channelName,
      included: included ?? this.included,
      colorGroups: colorGroups ?? this.colorGroups,
      effectId: effectId ?? this.effectId,
      speed: speed ?? this.speed,
      intensity: intensity ?? this.intensity,
      reverse: reverse ?? this.reverse,
      ledCount: ledCount ?? this.ledCount,
    );
  }

  factory ChannelDesign.fromJson(Map<String, dynamic> json) {
    return ChannelDesign(
      channelId: json['channel_id'] as int? ?? 0,
      channelName: json['channel_name'] as String? ?? 'Channel',
      included: json['included'] as bool? ?? true,
      colorGroups: (json['color_groups'] as List<dynamic>?)
              ?.map((g) => LedColorGroup.fromJson(g as Map<String, dynamic>))
              .toList() ??
          [],
      effectId: json['effect_id'] as int? ?? 0,
      speed: json['speed'] as int? ?? 128,
      intensity: json['intensity'] as int? ?? 128,
      reverse: json['reverse'] as bool? ?? false,
      ledCount: json['led_count'] as int? ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'channel_id': channelId,
      'channel_name': channelName,
      'included': included,
      'color_groups': colorGroups.map((g) => g.toJson()).toList(),
      'effect_id': effectId,
      'speed': speed,
      'intensity': intensity,
      'reverse': reverse,
      'led_count': ledCount,
    };
  }

  /// Gets the primary color for display (first color group or white)
  Color get primaryColor {
    if (colorGroups.isEmpty) return Colors.white;
    final c = colorGroups.first.color;
    return Color.fromARGB(255, c[0], c[1], c[2]);
  }
}

/// Represents a group of LEDs with the same color.
/// Allows "virtual" per-LED control by defining color ranges.
class LedColorGroup {
  /// 0-indexed start LED position
  final int startLed;

  /// 0-indexed end LED position (inclusive)
  final int endLed;

  /// Color as [R, G, B] or [R, G, B, W]
  final List<int> color;

  const LedColorGroup({
    required this.startLed,
    required this.endLed,
    required this.color,
  });

  /// Number of LEDs in this group
  int get ledCount => endLed - startLed + 1;

  LedColorGroup copyWith({
    int? startLed,
    int? endLed,
    List<int>? color,
  }) {
    return LedColorGroup(
      startLed: startLed ?? this.startLed,
      endLed: endLed ?? this.endLed,
      color: color ?? this.color,
    );
  }

  factory LedColorGroup.fromJson(Map<String, dynamic> json) {
    return LedColorGroup(
      startLed: json['start_led'] as int? ?? 0,
      endLed: json['end_led'] as int? ?? 0,
      color: (json['color'] as List<dynamic>?)?.cast<int>() ?? [255, 255, 255],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'start_led': startLed,
      'end_led': endLed,
      'color': color,
    };
  }

  /// Creates from a Flutter Color
  factory LedColorGroup.fromColor(int startLed, int endLed, Color color, {int white = 0}) {
    return LedColorGroup(
      startLed: startLed,
      endLed: endLed,
      color: [color.red, color.green, color.blue, white],
    );
  }

  /// Gets the Flutter Color representation
  Color get flutterColor {
    if (color.length >= 3) {
      return Color.fromARGB(255, color[0], color[1], color[2]);
    }
    return Colors.white;
  }
}

/// Common WLED effects with user-friendly names
const Map<int, String> kDesignEffects = {
  0: 'Solid',
  1: 'Blink',
  2: 'Breathe',
  9: 'Rainbow',
  12: 'Theater Chase',
  28: 'Chase',
  37: 'Candle',
  38: 'Fire',
  42: 'Fireworks',
  44: 'Twinkle',
  63: 'Colortwinkles',
  74: 'Palette',
  80: 'Ripple',
  97: 'Pacifica',
};

/// Curated list of effect IDs for the design studio
const List<int> kCuratedEffectIds = [0, 2, 9, 12, 28, 37, 44, 63, 74, 80, 97];
