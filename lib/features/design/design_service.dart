import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:nexgen_command/features/design/design_models.dart';

/// Service for managing custom designs in Firestore.
class DesignService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Gets the designs collection reference for a user
  CollectionReference<Map<String, dynamic>> _designsRef(String userId) {
    return _firestore.collection('users').doc(userId).collection('designs');
  }

  /// Creates a new design in Firestore
  Future<String> createDesign(String userId, CustomDesign design) async {
    try {
      final docRef = await _designsRef(userId).add(design.toFirestore());
      debugPrint('Created design: ${docRef.id}');
      return docRef.id;
    } catch (e) {
      debugPrint('Error creating design: $e');
      rethrow;
    }
  }

  /// Updates an existing design
  Future<void> updateDesign(String userId, CustomDesign design) async {
    try {
      final data = design.copyWith(updatedAt: DateTime.now()).toFirestore();
      await _designsRef(userId).doc(design.id).update(data);
      debugPrint('Updated design: ${design.id}');
    } catch (e) {
      debugPrint('Error updating design: $e');
      rethrow;
    }
  }

  /// Saves a design (creates if new, updates if existing)
  Future<String> saveDesign(String userId, CustomDesign design) async {
    if (design.id.isEmpty) {
      return createDesign(userId, design);
    } else {
      await updateDesign(userId, design);
      return design.id;
    }
  }

  /// Deletes a design
  Future<void> deleteDesign(String userId, String designId) async {
    try {
      await _designsRef(userId).doc(designId).delete();
      debugPrint('Deleted design: $designId');
    } catch (e) {
      debugPrint('Error deleting design: $e');
      rethrow;
    }
  }

  /// Gets a single design by ID
  Future<CustomDesign?> getDesign(String userId, String designId) async {
    try {
      final doc = await _designsRef(userId).doc(designId).get();
      if (!doc.exists) return null;
      return CustomDesign.fromFirestore(doc);
    } catch (e) {
      debugPrint('Error getting design: $e');
      return null;
    }
  }

  /// Streams all designs for a user, ordered by most recent
  Stream<List<CustomDesign>> streamDesigns(String userId) {
    return _designsRef(userId)
        .orderBy('updated_at', descending: true)
        .snapshots()
        .map((snap) {
      return snap.docs.map((doc) => CustomDesign.fromFirestore(doc)).toList();
    });
  }

  /// Gets all designs for a user (one-time fetch)
  Future<List<CustomDesign>> getDesigns(String userId) async {
    try {
      final snap = await _designsRef(userId)
          .orderBy('updated_at', descending: true)
          .get();
      return snap.docs.map((doc) => CustomDesign.fromFirestore(doc)).toList();
    } catch (e) {
      debugPrint('Error getting designs: $e');
      return [];
    }
  }

  /// Duplicates an existing design with a new name
  Future<String> duplicateDesign(String userId, CustomDesign original, String newName) async {
    final now = DateTime.now();
    final duplicate = original.copyWith(
      id: '',
      name: newName,
      createdAt: now,
      updatedAt: now,
    );
    return createDesign(userId, duplicate);
  }

  /// Searches designs by name or tags
  Future<List<CustomDesign>> searchDesigns(String userId, String query) async {
    final designs = await getDesigns(userId);
    final lowerQuery = query.toLowerCase();
    return designs.where((d) {
      return d.name.toLowerCase().contains(lowerQuery) ||
          d.tags.any((t) => t.toLowerCase().contains(lowerQuery));
    }).toList();
  }
}
