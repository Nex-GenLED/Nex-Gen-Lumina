import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';

/// Model representing a favorite pattern with usage metadata
class FavoritePattern {
  final String patternId;
  final String name;
  final int usageCount;
  final DateTime lastUsed;
  final Map<String, dynamic> wledPayload;

  FavoritePattern({
    required this.patternId,
    required this.name,
    required this.usageCount,
    required this.lastUsed,
    required this.wledPayload,
  });

  factory FavoritePattern.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoritePattern(
      patternId: doc.id,
      name: data['name'] as String? ?? 'Unnamed Pattern',
      usageCount: data['usageCount'] as int? ?? 0,
      lastUsed: (data['lastUsed'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wledPayload: data['wledPayload'] as Map<String, dynamic>? ?? {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'usageCount': usageCount,
      'lastUsed': Timestamp.fromDate(lastUsed),
      'wledPayload': wledPayload,
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
      .map((snap) => snap.docs.map((d) => FavoritePattern.fromFirestore(d)).toList());
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
      .map((snap) => snap.docs.map((d) => FavoritePattern.fromFirestore(d)).toList());
});

/// Notifier for managing favorites (add, remove, track usage)
class FavoritesNotifier extends Notifier<void> {
  @override
  void build() {}

  /// Track pattern usage - auto-adds to favorites and increments usage count
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
        // Increment usage count and update timestamp
        await docRef.update({
          'usageCount': FieldValue.increment(1),
          'lastUsed': FieldValue.serverTimestamp(),
        });
      } else {
        // Create new favorite entry
        await docRef.set({
          'name': patternName,
          'usageCount': 1,
          'lastUsed': FieldValue.serverTimestamp(),
          'wledPayload': wledPayload,
        });
      }
    } catch (e) {
      // Silently fail - favorites are a nice-to-have feature
      print('Failed to track pattern usage: $e');
    }
  }

  /// Manually add a pattern to favorites
  Future<void> addToFavorites({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> wledPayload,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      await FirebaseFirestore.instance
          .doc('users/${user.uid}/favorites/$patternId')
          .set({
        'name': patternName,
        'usageCount': FieldValue.increment(1),
        'lastUsed': FieldValue.serverTimestamp(),
        'wledPayload': wledPayload,
      }, SetOptions(merge: true));
    } catch (e) {
      print('Failed to add favorite: $e');
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
      print('Failed to remove favorite: $e');
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
}

final favoritesNotifierProvider = NotifierProvider<FavoritesNotifier, void>(
  FavoritesNotifier.new,
);
