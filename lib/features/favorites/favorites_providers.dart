import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/favorites/favorite_doc.dart';

/// Model representing a favorite pattern with usage metadata.
///
/// Stores the full pattern state so it can be restored exactly:
/// action colors, background color, effect, direction, speed, etc.
class FavoritePattern {
  final String patternId;
  final String name;
  final int usageCount;
  final DateTime lastUsed;
  final Map<String, dynamic> wledPayload;
  final bool autoAdded;

  // Rich pattern state for full restore
  final List<int>? actionColorValues;
  final int? backgroundColorValue;
  final int? effectId;
  final int? speed;
  final int? intensity;
  final int? brightness;
  final int? colorGroupSize;
  final String? direction;

  FavoritePattern({
    required this.patternId,
    required this.name,
    required this.usageCount,
    required this.lastUsed,
    required this.wledPayload,
    this.autoAdded = false,
    this.actionColorValues,
    this.backgroundColorValue,
    this.effectId,
    this.speed,
    this.intensity,
    this.brightness,
    this.colorGroupSize,
    this.direction,
  });

  /// Reads the canonical snake_case document (see `favorite_doc.dart`) — the
  /// only shape the live rule accepts and the only one in production. This
  /// model used to read ONLY the camelCase shape, which no stored document has
  /// ever had, so every favorite came back as "Unnamed Pattern" with no
  /// payload. The camelCase keys remain as a fallback so nothing written by an
  /// older build can ever read worse than it did.
  factory FavoritePattern.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final used = data[kFavoriteLastUsed] ?? data['lastUsed'] ?? data[kFavoriteAddedAt];
    return FavoritePattern(
      patternId: doc.id,
      name: (data[kFavoritePatternName] ?? data['name']) as String? ??
          'Unnamed Pattern',
      usageCount:
          ((data[kFavoriteUsageCount] ?? data['usageCount']) as num?)?.toInt() ??
              0,
      // Null while a server timestamp is still pending locally.
      lastUsed: (used as Timestamp?)?.toDate() ?? DateTime.now(),
      wledPayload:
          decodeWledPayload(data[kFavoritePatternData] ?? data['wledPayload']),
      autoAdded: (data[kFavoriteAutoAdded] ?? data['autoAdded']) as bool? ?? false,
      actionColorValues: (data['actionColorValues'] as List?)?.cast<int>(),
      backgroundColorValue: data['backgroundColorValue'] as int?,
      effectId: data['effectId'] as int?,
      speed: data['speed'] as int?,
      intensity: data['intensity'] as int?,
      brightness: data['brightness'] as int?,
      colorGroupSize: data['colorGroupSize'] as int?,
      direction: data['direction'] as String?,
    );
  }

  /// Decodes `wledPayload` from a Firestore document, tolerating both shapes:
  /// - **String (current):** `jsonEncode`d by `addFavorite` so Firestore's
  ///   native iOS codec doesn't reject nested arrays like `col: [[r,g,b,w]]`
  ///   (#84 root cause — uncatchable SIGABRT in `FSTUserDataReader`).
  /// - **Map (legacy):** docs that somehow persisted as raw Map before the
  ///   jsonEncode fix landed; pass through so reads of old data don't throw.
  /// Returns `{}` for null / empty / unparseable input.
  static Map<String, dynamic> decodeWledPayload(dynamic raw) =>
      decodeFavoritePayload(raw);
}

/// Provider that streams the user's favorite patterns, sorted by usage count
final favoritesPatternsProvider = StreamProvider<List<FavoritePattern>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('users/${user.uid}/favorites')
      .orderBy(kFavoriteUsageCount, descending: true)
      .limit(5)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => FavoritePattern.fromFirestore(d)).toList());
});

/// Streams every favorite the user has saved (no ordering or limit).
/// Used for name-match lookups against the active WLED preset so the
/// Now Playing bar can prefer the Lumina-side name.
final allFavoritesProvider = StreamProvider<List<FavoritePattern>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(const []);

  return FirebaseFirestore.instance
      .collection('users/${user.uid}/favorites')
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
      // `last_used` is absent until a favorite is first applied, and orderBy
      // drops docs lacking the field — which is what "recently USED" means.
      .orderBy(kFavoriteLastUsed, descending: true)
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

      await docRef.update(buildFavoriteUsageData());
    } catch (e) {
      // Silently fail or log
      debugPrint('Failed to record favorite usage: $e');
    }
  }

  /// Adds a favorite at `favorites/{patternId}` (or refreshes its stored look
  /// when it is already there).
  ///
  /// [patternData] must be the WLED payload to re-apply — it is what the
  /// dashboard's My Favorites grid POSTs to the controller.
  ///
  /// The document is built by [writeFavorite], the one canonical shape. This
  /// method used to write `{name, usageCount, lastUsed, wledPayload,
  /// autoAdded}`, which the live rule rejects (a create must carry
  /// `pattern_name` + `added_at`): every heart tap and every "Save to
  /// Favorites" ended in "Failed to save favorite".
  Future<void> addFavorite({
    required String patternId,
    required String patternName,
    required Map<String, dynamic> patternData,
    bool autoAdded = false,
  }) async {
    final user = ref.read(authStateProvider).value;
    if (user == null) return;

    try {
      await writeFavorite(
        FirebaseFirestore.instance
            .doc('users/${user.uid}/favorites/$patternId'),
        patternName: patternName,
        payload: patternData,
        autoAdded: autoAdded,
      );
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

/// Streams the set of all favorited pattern IDs for efficient lookup.
/// Used by FavoriteHeartButton to show filled/outlined state without
/// individual async calls per card.
final favoritedPatternIdsProvider = StreamProvider<Set<String>>((ref) {
  final user = ref.watch(authStateProvider).value;
  if (user == null) return Stream.value(<String>{});

  return FirebaseFirestore.instance
      .collection('users/${user.uid}/favorites')
      .snapshots()
      .map((snap) => snap.docs.map((d) => d.id).toSet());
});