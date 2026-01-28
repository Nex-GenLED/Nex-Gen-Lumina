import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/properties/property_models.dart';
import 'package:nexgen_command/app_providers.dart';

/// Stream of all properties for the current user
final userPropertiesProvider = StreamProvider<List<Property>>((ref) {
  final authState = ref.watch(authStateProvider);

  return authState.when(
    data: (user) {
      if (user == null) {
        debugPrint('Properties: No authenticated user');
        return Stream.value([]);
      }

      debugPrint('Properties: Loading properties for user ${user.uid}');

      return FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('properties')
          .snapshots()
          .map((snapshot) {
            debugPrint('Properties: Received ${snapshot.docs.length} properties from Firestore');
            final properties = snapshot.docs
                .map((doc) {
                  try {
                    return Property.fromFirestore(doc);
                  } catch (e) {
                    debugPrint('Properties: Error parsing property ${doc.id}: $e');
                    rethrow;
                  }
                })
                .toList();
            // Sort client-side: primary properties first, then by name
            properties.sort((a, b) {
              if (a.isPrimary != b.isPrimary) {
                return a.isPrimary ? -1 : 1; // Primary comes first
              }
              return a.name.compareTo(b.name);
            });
            return properties;
          })
          .handleError((error, stack) {
            debugPrint('Properties: Stream error: $error');
            debugPrint('Properties: Stack trace: $stack');
            throw error;
          });
    },
    loading: () {
      debugPrint('Properties: Auth state loading...');
      return Stream.value([]);
    },
    error: (error, stack) {
      debugPrint('Properties: Auth state error: $error');
      return Stream.error(error, stack);
    },
  );
});

/// Currently selected property ID (persisted locally)
final selectedPropertyIdProvider = StateProvider<String?>((ref) => null);

/// Currently selected property (derived from ID and properties list)
final selectedPropertyProvider = Provider<Property?>((ref) {
  final selectedId = ref.watch(selectedPropertyIdProvider);
  final propertiesAsync = ref.watch(userPropertiesProvider);

  return propertiesAsync.whenOrNull(
    data: (properties) {
      if (properties.isEmpty) return null;

      // If no selection, return primary or first property
      if (selectedId == null) {
        return properties.firstWhere(
          (p) => p.isPrimary,
          orElse: () => properties.first,
        );
      }

      // Find selected property
      return properties.firstWhere(
        (p) => p.id == selectedId,
        orElse: () => properties.first,
      );
    },
  );
});

/// Whether user has multiple properties
final hasMultiplePropertiesProvider = Provider<bool>((ref) {
  final propertiesAsync = ref.watch(userPropertiesProvider);
  return propertiesAsync.whenOrNull(data: (p) => p.length > 1) ?? false;
});

/// Property management notifier
final propertyManagerProvider = Provider<PropertyManager>((ref) {
  return PropertyManager(ref);
});

/// Manages property CRUD operations
class PropertyManager {
  final Ref _ref;

  PropertyManager(this._ref);

  FirebaseFirestore get _firestore => FirebaseFirestore.instance;

  String? get _userId {
    final authState = _ref.read(authStateProvider);
    return authState.valueOrNull?.uid;
  }

  CollectionReference<Map<String, dynamic>> get _propertiesCollection {
    final userId = _userId;
    if (userId == null) throw Exception('User not authenticated');
    return _firestore.collection('users').doc(userId).collection('properties');
  }

  /// Create a new property
  Future<Property?> createProperty({
    required String name,
    String? address,
    String iconName = 'home',
    bool isPrimary = false,
  }) async {
    final userId = _userId;
    if (userId == null) return null;

    try {
      // If this is primary, unset other primaries first
      if (isPrimary) {
        await _unsetAllPrimaries();
      }

      final property = Property.create(
        ownerId: userId,
        name: name,
        address: address,
        iconName: iconName,
        isPrimary: isPrimary,
      );

      final docRef = await _propertiesCollection.add(property.toFirestore());

      debugPrint('PropertyManager: Created property "${name}" with ID: ${docRef.id}');

      // Select the new property
      _ref.read(selectedPropertyIdProvider.notifier).state = docRef.id;

      return property.copyWith(id: docRef.id);
    } catch (e) {
      debugPrint('PropertyManager: Error creating property: $e');
      return null;
    }
  }

  /// Update an existing property
  Future<bool> updateProperty(Property property) async {
    if (property.id.isEmpty) return false;

    try {
      // If setting as primary, unset other primaries first
      if (property.isPrimary) {
        await _unsetAllPrimaries(exceptId: property.id);
      }

      await _propertiesCollection.doc(property.id).update(
        property.copyWith(updatedAt: DateTime.now()).toFirestore(),
      );

      debugPrint('PropertyManager: Updated property "${property.name}"');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error updating property: $e');
      return false;
    }
  }

  /// Delete a property
  Future<bool> deleteProperty(String propertyId) async {
    try {
      await _propertiesCollection.doc(propertyId).delete();

      // If deleted property was selected, clear selection
      if (_ref.read(selectedPropertyIdProvider) == propertyId) {
        _ref.read(selectedPropertyIdProvider.notifier).state = null;
      }

      debugPrint('PropertyManager: Deleted property $propertyId');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error deleting property: $e');
      return false;
    }
  }

  /// Set a property as primary
  Future<bool> setPrimaryProperty(String propertyId) async {
    try {
      await _unsetAllPrimaries();
      await _propertiesCollection.doc(propertyId).update({
        'is_primary': true,
        'updated_at': Timestamp.now(),
      });

      debugPrint('PropertyManager: Set property $propertyId as primary');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error setting primary: $e');
      return false;
    }
  }

  /// Link a controller to a property
  Future<bool> linkController(String propertyId, String controllerId) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'controller_ids': FieldValue.arrayUnion([controllerId]),
        'updated_at': Timestamp.now(),
      });

      debugPrint('PropertyManager: Linked controller $controllerId to property $propertyId');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error linking controller: $e');
      return false;
    }
  }

  /// Unlink a controller from a property
  Future<bool> unlinkController(String propertyId, String controllerId) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'controller_ids': FieldValue.arrayRemove([controllerId]),
        'updated_at': Timestamp.now(),
      });

      debugPrint('PropertyManager: Unlinked controller $controllerId from property $propertyId');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error unlinking controller: $e');
      return false;
    }
  }

  /// Update property geofence
  Future<bool> updateGeofence(String propertyId, PropertyGeofence? geofence) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'geofence': geofence?.toMap(),
        'updated_at': Timestamp.now(),
      });

      debugPrint('PropertyManager: Updated geofence for property $propertyId');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error updating geofence: $e');
      return false;
    }
  }

  /// Update property photo
  Future<bool> updatePhoto(String propertyId, String? photoUrl) async {
    try {
      await _propertiesCollection.doc(propertyId).update({
        'photo_url': photoUrl,
        'updated_at': Timestamp.now(),
      });

      debugPrint('PropertyManager: Updated photo for property $propertyId');
      return true;
    } catch (e) {
      debugPrint('PropertyManager: Error updating photo: $e');
      return false;
    }
  }

  /// Create default property for new user
  Future<Property?> createDefaultProperty() async {
    return createProperty(
      name: 'My Home',
      iconName: 'home',
      isPrimary: true,
    );
  }

  /// Helper to unset all primary flags
  Future<void> _unsetAllPrimaries({String? exceptId}) async {
    final snapshot = await _propertiesCollection
        .where('is_primary', isEqualTo: true)
        .get();

    final batch = _firestore.batch();
    for (final doc in snapshot.docs) {
      if (doc.id != exceptId) {
        batch.update(doc.reference, {'is_primary': false});
      }
    }
    await batch.commit();
  }
}

/// Provider to get controllers for the selected property
final selectedPropertyControllersProvider = Provider<Set<String>>((ref) {
  final property = ref.watch(selectedPropertyProvider);
  return property?.controllerIds ?? {};
});

/// Provider to check if a controller belongs to the selected property
final isControllerInSelectedPropertyProvider = Provider.family<bool, String>((ref, controllerId) {
  final controllers = ref.watch(selectedPropertyControllersProvider);
  return controllers.contains(controllerId);
});

/// Select a property by ID
final selectPropertyProvider = Provider<void Function(String)>((ref) {
  return (propertyId) {
    ref.read(selectedPropertyIdProvider.notifier).state = propertyId;
    debugPrint('Properties: Selected property $propertyId');
  };
});

/// Initialize properties for a new user (creates default if none exist)
final initializePropertiesProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    final propertiesAsync = ref.read(userPropertiesProvider);
    final properties = propertiesAsync.valueOrNull ?? [];

    if (properties.isEmpty) {
      debugPrint('Properties: No properties found, creating default');
      final manager = ref.read(propertyManagerProvider);
      await manager.createDefaultProperty();
    }
  };
});
