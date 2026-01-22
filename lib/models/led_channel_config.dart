import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a complete LED channel/controller configuration.
///
/// This is the top-level configuration that defines:
/// - Total LED count for the channel
/// - Physical location of LED #1
/// - Connection details for the WLED controller
/// - Architecture type for pattern recommendations
class LedChannelConfig {
  /// Unique identifier
  final String id;

  /// User-friendly name (e.g., "Main Roofline", "Back Patio")
  final String name;

  /// Total number of LEDs in this channel
  final int totalLedCount;

  /// IP address of the WLED controller
  final String controllerIp;

  /// Physical description of where LED #1 is located
  final String startLocation;

  /// Physical description of where the last LED is located
  final String endLocation;

  /// Type of architecture this channel covers
  final ArchitectureType architectureType;

  /// Whether this channel has RGBW LEDs (vs RGB only)
  final bool isRgbw;

  /// WLED segment ID for this channel (usually 0)
  final int segmentId;

  /// Whether this is the primary/main channel
  final bool isPrimary;

  /// Reference to the roofline configuration for this channel
  final String? rooflineConfigId;

  /// When this configuration was created
  final DateTime createdAt;

  /// When this configuration was last updated
  final DateTime updatedAt;

  const LedChannelConfig({
    required this.id,
    required this.name,
    required this.totalLedCount,
    required this.controllerIp,
    required this.startLocation,
    required this.endLocation,
    this.architectureType = ArchitectureType.gabled,
    this.isRgbw = false,
    this.segmentId = 0,
    this.isPrimary = true,
    this.rooflineConfigId,
    required this.createdAt,
    required this.updatedAt,
  });

  LedChannelConfig copyWith({
    String? id,
    String? name,
    int? totalLedCount,
    String? controllerIp,
    String? startLocation,
    String? endLocation,
    ArchitectureType? architectureType,
    bool? isRgbw,
    int? segmentId,
    bool? isPrimary,
    String? rooflineConfigId,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LedChannelConfig(
      id: id ?? this.id,
      name: name ?? this.name,
      totalLedCount: totalLedCount ?? this.totalLedCount,
      controllerIp: controllerIp ?? this.controllerIp,
      startLocation: startLocation ?? this.startLocation,
      endLocation: endLocation ?? this.endLocation,
      architectureType: architectureType ?? this.architectureType,
      isRgbw: isRgbw ?? this.isRgbw,
      segmentId: segmentId ?? this.segmentId,
      isPrimary: isPrimary ?? this.isPrimary,
      rooflineConfigId: rooflineConfigId ?? this.rooflineConfigId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory LedChannelConfig.fromJson(String id, Map<String, dynamic> json) {
    return LedChannelConfig(
      id: id,
      name: json['name'] as String? ?? 'Unnamed Channel',
      totalLedCount: json['total_led_count'] as int? ?? 0,
      controllerIp: json['controller_ip'] as String? ?? '',
      startLocation: json['start_location'] as String? ?? '',
      endLocation: json['end_location'] as String? ?? '',
      architectureType: ArchitectureTypeExtension.fromString(
        json['architecture_type'] as String? ?? 'gabled',
      ),
      isRgbw: json['is_rgbw'] as bool? ?? false,
      segmentId: json['segment_id'] as int? ?? 0,
      isPrimary: json['is_primary'] as bool? ?? true,
      rooflineConfigId: json['roofline_config_id'] as String?,
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'name': name,
      'total_led_count': totalLedCount,
      'controller_ip': controllerIp,
      'start_location': startLocation,
      'end_location': endLocation,
      'architecture_type': architectureType.name,
      'is_rgbw': isRgbw,
      'segment_id': segmentId,
      'is_primary': isPrimary,
      if (rooflineConfigId != null) 'roofline_config_id': rooflineConfigId,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }

  factory LedChannelConfig.empty() {
    final now = DateTime.now();
    return LedChannelConfig(
      id: '',
      name: 'My Roofline',
      totalLedCount: 0,
      controllerIp: '',
      startLocation: '',
      endLocation: '',
      createdAt: now,
      updatedAt: now,
    );
  }
}

/// Type of home architecture for pattern recommendations.
enum ArchitectureType {
  /// Flat roof or minimal peaks (ranch-style)
  ranch,
  /// Single gable/peak
  gabled,
  /// Multiple gables/peaks
  multiGabled,
  /// Mixed architecture with various features
  complex,
  /// Modern/contemporary with unique shapes
  modern,
  /// Colonial style with dormers
  colonial,
}

extension ArchitectureTypeExtension on ArchitectureType {
  String get displayName {
    switch (this) {
      case ArchitectureType.ranch:
        return 'Ranch (Flat/Minimal Peaks)';
      case ArchitectureType.gabled:
        return 'Single Gable';
      case ArchitectureType.multiGabled:
        return 'Multi-Gabled';
      case ArchitectureType.complex:
        return 'Complex/Mixed';
      case ArchitectureType.modern:
        return 'Modern/Contemporary';
      case ArchitectureType.colonial:
        return 'Colonial with Dormers';
    }
  }

  String get description {
    switch (this) {
      case ArchitectureType.ranch:
        return 'Mostly horizontal roofline with few or no peaks';
      case ArchitectureType.gabled:
        return 'Traditional roof with one main peak';
      case ArchitectureType.multiGabled:
        return 'Multiple peaks and gables at different heights';
      case ArchitectureType.complex:
        return 'Combination of various architectural features';
      case ArchitectureType.modern:
        return 'Contemporary design with unique angles or shapes';
      case ArchitectureType.colonial:
        return 'Traditional style with dormers and symmetrical design';
    }
  }

  /// Recommended pattern types for this architecture
  List<String> get recommendedPatterns {
    switch (this) {
      case ArchitectureType.ranch:
        return ['uniform', 'alternating', 'chase'];
      case ArchitectureType.gabled:
        return ['cornerAccent', 'downlighting', 'chase'];
      case ArchitectureType.multiGabled:
        return ['cornerAccent', 'downlighting', 'alternatingSegments'];
      case ArchitectureType.complex:
        return ['downlighting', 'cornerAccent', 'segmentChase'];
      case ArchitectureType.modern:
        return ['uniform', 'chase', 'gradient'];
      case ArchitectureType.colonial:
        return ['downlighting', 'cornerAccent', 'symmetric'];
    }
  }

  static ArchitectureType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'ranch':
        return ArchitectureType.ranch;
      case 'gabled':
        return ArchitectureType.gabled;
      case 'multigabled':
      case 'multi_gabled':
        return ArchitectureType.multiGabled;
      case 'complex':
        return ArchitectureType.complex;
      case 'modern':
        return ArchitectureType.modern;
      case 'colonial':
        return ArchitectureType.colonial;
      default:
        return ArchitectureType.gabled;
    }
  }
}

/// Represents the complete LED installation for a user's property.
/// May contain multiple channels/controllers.
class LedInstallation {
  /// Unique identifier
  final String id;

  /// User ID who owns this installation
  final String userId;

  /// User-friendly name
  final String name;

  /// List of channel configurations
  final List<LedChannelConfig> channels;

  /// Total LEDs across all channels
  int get totalLedCount =>
      channels.fold(0, (total, ch) => total + ch.totalLedCount);

  /// Whether the installation setup is complete
  final bool setupComplete;

  /// When this was created
  final DateTime createdAt;

  /// When this was last updated
  final DateTime updatedAt;

  const LedInstallation({
    required this.id,
    required this.userId,
    required this.name,
    required this.channels,
    this.setupComplete = false,
    required this.createdAt,
    required this.updatedAt,
  });

  LedInstallation copyWith({
    String? id,
    String? userId,
    String? name,
    List<LedChannelConfig>? channels,
    bool? setupComplete,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return LedInstallation(
      id: id ?? this.id,
      userId: userId ?? this.userId,
      name: name ?? this.name,
      channels: channels ?? this.channels,
      setupComplete: setupComplete ?? this.setupComplete,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  factory LedInstallation.fromJson(String id, Map<String, dynamic> json) {
    return LedInstallation(
      id: id,
      userId: json['user_id'] as String? ?? '',
      name: json['name'] as String? ?? 'My Installation',
      channels: (json['channels'] as List<dynamic>?)
              ?.asMap()
              .entries
              .map((e) => LedChannelConfig.fromJson(
                    'ch_${e.key}',
                    e.value as Map<String, dynamic>,
                  ))
              .toList() ??
          [],
      setupComplete: json['setup_complete'] as bool? ?? false,
      createdAt: (json['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (json['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'user_id': userId,
      'name': name,
      'channels': channels.map((ch) => ch.toJson()).toList(),
      'setup_complete': setupComplete,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
    };
  }

  factory LedInstallation.empty(String userId) {
    final now = DateTime.now();
    return LedInstallation(
      id: '',
      userId: userId,
      name: 'My Home',
      channels: [],
      createdAt: now,
      updatedAt: now,
    );
  }

  /// Get the primary channel (first one marked as primary, or first channel)
  LedChannelConfig? get primaryChannel {
    try {
      return channels.firstWhere((ch) => ch.isPrimary);
    } catch (_) {
      return channels.isNotEmpty ? channels.first : null;
    }
  }
}
