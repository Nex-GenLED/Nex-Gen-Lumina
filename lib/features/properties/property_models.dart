import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a user's property (home, vacation house, etc.)
///
/// Each property has its own set of linked controllers, schedules,
/// and can be controlled independently.
class Property {
  /// Unique Firestore document ID
  final String id;

  /// User-facing name (e.g., "Main Home", "Lake House", "Beach Condo")
  final String name;

  /// Optional address or location description
  final String? address;

  /// Icon name for display (Material Icons name)
  final String iconName;

  /// Owner user ID
  final String ownerId;

  /// Creation timestamp
  final DateTime createdAt;

  /// Last modified timestamp
  final DateTime updatedAt;

  /// IDs of controllers linked to this property
  final Set<String> controllerIds;

  /// Whether this is the user's default/primary property
  final bool isPrimary;

  /// Optional timezone for this property (for schedule calculations)
  final String? timezone;

  /// Optional geofence configuration
  final PropertyGeofence? geofence;

  /// Optional photo URL for the property
  final String? photoUrl;

  const Property({
    required this.id,
    required this.name,
    this.address,
    this.iconName = 'home',
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.controllerIds = const {},
    this.isPrimary = false,
    this.timezone,
    this.geofence,
    this.photoUrl,
  });

  /// Create an empty property for a user
  factory Property.create({
    required String ownerId,
    required String name,
    String? address,
    String iconName = 'home',
    bool isPrimary = false,
  }) {
    final now = DateTime.now();
    return Property(
      id: '',
      name: name,
      address: address,
      iconName: iconName,
      ownerId: ownerId,
      createdAt: now,
      updatedAt: now,
      isPrimary: isPrimary,
    );
  }

  /// Create from Firestore document
  factory Property.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return Property(
      id: doc.id,
      name: data['name'] as String? ?? 'Unnamed Property',
      address: data['address'] as String?,
      iconName: data['icon_name'] as String? ?? 'home',
      ownerId: data['owner_id'] as String? ?? '',
      createdAt: (data['created_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      updatedAt: (data['updated_at'] as Timestamp?)?.toDate() ?? DateTime.now(),
      controllerIds: (data['controller_ids'] as List?)
          ?.map((e) => e as String)
          .toSet() ?? {},
      isPrimary: data['is_primary'] as bool? ?? false,
      timezone: data['timezone'] as String?,
      geofence: data['geofence'] != null
          ? PropertyGeofence.fromMap(data['geofence'] as Map<String, dynamic>)
          : null,
      photoUrl: data['photo_url'] as String?,
    );
  }

  /// Convert to Firestore document
  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'address': address,
      'icon_name': iconName,
      'owner_id': ownerId,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'controller_ids': controllerIds.toList(),
      'is_primary': isPrimary,
      'timezone': timezone,
      if (geofence != null) 'geofence': geofence!.toMap(),
      'photo_url': photoUrl,
    };
  }

  Property copyWith({
    String? id,
    String? name,
    String? address,
    String? iconName,
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    Set<String>? controllerIds,
    bool? isPrimary,
    String? timezone,
    PropertyGeofence? geofence,
    String? photoUrl,
  }) {
    return Property(
      id: id ?? this.id,
      name: name ?? this.name,
      address: address ?? this.address,
      iconName: iconName ?? this.iconName,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      controllerIds: controllerIds ?? this.controllerIds,
      isPrimary: isPrimary ?? this.isPrimary,
      timezone: timezone ?? this.timezone,
      geofence: geofence ?? this.geofence,
      photoUrl: photoUrl ?? this.photoUrl,
    );
  }

  @override
  String toString() => 'Property($id, $name, controllers: ${controllerIds.length})';
}

/// Geofence configuration for a property
class PropertyGeofence {
  /// Center latitude
  final double latitude;

  /// Center longitude
  final double longitude;

  /// Radius in meters
  final double radiusMeters;

  /// Whether geofencing is enabled for this property
  final bool enabled;

  const PropertyGeofence({
    required this.latitude,
    required this.longitude,
    this.radiusMeters = 150.0,
    this.enabled = true,
  });

  factory PropertyGeofence.fromMap(Map<String, dynamic> map) {
    return PropertyGeofence(
      latitude: (map['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (map['longitude'] as num?)?.toDouble() ?? 0.0,
      radiusMeters: (map['radius_meters'] as num?)?.toDouble() ?? 150.0,
      enabled: map['enabled'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'radius_meters': radiusMeters,
      'enabled': enabled,
    };
  }

  PropertyGeofence copyWith({
    double? latitude,
    double? longitude,
    double? radiusMeters,
    bool? enabled,
  }) {
    return PropertyGeofence(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radiusMeters: radiusMeters ?? this.radiusMeters,
      enabled: enabled ?? this.enabled,
    );
  }
}

/// Available property icons
class PropertyIcons {
  static const List<PropertyIconOption> options = [
    PropertyIconOption('home', 'Home'),
    PropertyIconOption('villa', 'Villa'),
    PropertyIconOption('cottage', 'Cottage'),
    PropertyIconOption('apartment', 'Apartment'),
    PropertyIconOption('cabin', 'Cabin'),
    PropertyIconOption('beach_access', 'Beach'),
    PropertyIconOption('landscape', 'Mountain'),
    PropertyIconOption('pool', 'Pool House'),
    PropertyIconOption('business', 'Office'),
    PropertyIconOption('storefront', 'Store'),
  ];

  static String getDisplayName(String iconName) {
    return options.firstWhere(
      (o) => o.iconName == iconName,
      orElse: () => const PropertyIconOption('home', 'Home'),
    ).displayName;
  }
}

class PropertyIconOption {
  final String iconName;
  final String displayName;

  const PropertyIconOption(this.iconName, this.displayName);
}
