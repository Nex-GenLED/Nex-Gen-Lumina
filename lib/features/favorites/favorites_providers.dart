import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';

/// Model representing a favorite pattern with usage metadata
class FavoritePattern {
  final String patternId;
  final String name;
  final int usageCount;
  final DateTime lastUsed;
  final Map<String, dynamic> wledPayload;
  final bool autoAdded;

  FavoritePattern({
    required this.patternId,
    required this.name,
    required this.usageCount,
    required this.lastUsed,
    required this.wledPayload,
    this.autoAdded = false,
  });

  factory FavoritePattern.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoritePattern(
      patternId: doc.id,
      name: data['name'] as String? ?? 'Unnamed Pattern',
      usageCount: data['usageCount'] as int? ?? 0,
      lastUsed: (data['lastUsed'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wledPayload: data['wledPayload'] as Map<String, dynamic>? ?? {},
      autoAdded: data['autoAdded'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'usageCount': usageCount,
      'lastUsed': Timestamp.fromDate(lastUsed),
      'wledPayload': wledPayload,
      'autoAdded': autoAdded,
    };
  }
}

/// Provider that streams the user's favorite patterns, sorted by usage count
final favoritesPatternsProvider = StreamProvider<List<FavoritePattern>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users/${user.uid}/favorites')
      .orderBy('usageCount', descending: true)
      .limit(5)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => FavoritePattern.fromFirestore(d)).toList());
});

/// Provider for recently used patterns (last 5)
final recentPatternsProvider = StreamProvider<List<FavoritePattern>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users/${user.uid}/favorites')
      .orderBy('lastUsed', descending: true)
      .limit(5)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => FavoritePattern.fromFirestore(d)).toList());
});

/// Notifier for managing favorites (add, remove, track usage)
class FavoritesNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Records that a favorite was clicked/used.
  /// Increments usage count and updates timestamp.
  Future<void> recordFavoriteUsage(String patternId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId');

      // Update existing document
      await docRef.update({
        'usageCount': FieldValue.increment(1),
        'lastUsed': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      // Silently fail or log
      debugPrint('Failed to record favorite usage: $e');
    }
  }

  /// Adds a new favorite to Firestore.
  /// Updated to accept 'patternData' and 'autoAdded' to match WledDashboardPage
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false, // FIXED: Added this parameter
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId');

      await docRef.set({
        'name': patternName,
        'usageCount': 1,
        'lastUsed': FieldValue.serverTimestamp(),
        'wledPayload': patternData,
        'autoAdded': autoAdded, // Store the flag in Firestore
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to add favorite: $e');
      rethrow;
    }
  }

  /// Remove a pattern from favorites
  Future<void> removeFromFavorites(String patternId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId')
          .delete();
    } catch (e) {
      debugPrint('Failed to remove favorite: $e');
      rethrow;
    }
  }

  /// Check if a pattern is favorited
  Future<bool> isFavorited(String patternId) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return false;

    try {
      final doc = await FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId')
          .get();
      return doc.exists;
    } catch (e) {
      return false;
    }
  }

  /// Legacy wrapper if you still use trackPatternUsage elsewhere
  Future<void> trackPatternUsage({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      final docRef = FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId');

      final docSnap = await docRef.get();

      if (docSnap.exists) {
        await recordFavoriteUsage(patternId);
      } else {
        await addFavorite(
          patternId: patternId,
          patternName: patternName,
          patternData: wledPayload,
          autoAdded: true, // Implicitly true for tracking usage of new patterns
        );
      }
    } catch (e) {
      debugPrint('Failed to track pattern usage: $e');
    }
  }

  /// Legacy alias to support older calls to addToFavorites
  Future<void> addToFavorites({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    return addFavorite(
      patternId: patternId,
      patternName: patternName,
      patternData: wledPayload,
      autoAdded: false, // Explicit adds are not auto-added
    );
  }
}

final favoritesNotifierProvider = NotifierProvider<FavoritesNotifier, void>(
  FavoritesNotifier.new,
);