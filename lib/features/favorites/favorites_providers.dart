import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/services/debug_capture.dart';
import 'package:nexgen_command/services/user_service.dart';

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

  factory FavoritePattern.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return FavoritePattern(
      patternId: doc.id,
      name: data['name'] as String? ?? 'Unnamed Pattern',
      usageCount: data['usageCount'] as int? ?? 0,
      lastUsed: (data['lastUsed'] as Timestamp?)?.toDate() ?? DateTime.now(),
      wledPayload: decodeWledPayload(data['wledPayload']),
      autoAdded: data['autoAdded'] as bool? ?? false,
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
  ///
  /// Also used in production by [GeofenceMonitor] to recover a stored
  /// favorite's payload (Shape A String / Shape B Map) when applying a
  /// geofence trigger, so this is a shared decode utility — not test-only.
  static Map<String, dynamic> decodeWledPayload(dynamic raw) {
    if (raw is String) {
      if (raw.isEmpty) return <String, dynamic>{};
      try {
        final decoded = jsonDecode(raw);
        if (decoded is Map) return Map<String, dynamic>.from(decoded);
      } catch (_) {
        return <String, dynamic>{};
      }
      return <String, dynamic>{};
    }
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return <String, dynamic>{};
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'usageCount': usageCount,
      'lastUsed': Timestamp.fromDate(lastUsed),
      'wledPayload': wledPayload,
      'autoAdded': autoAdded,
      if (actionColorValues != null) 'actionColorValues': actionColorValues,
      if (backgroundColorValue != null) 'backgroundColorValue': backgroundColorValue,
      if (effectId != null) 'effectId': effectId,
      if (speed != null) 'speed': speed,
      if (intensity != null) 'intensity': intensity,
      if (brightness != null) 'brightness': brightness,
      if (colorGroupSize != null) 'colorGroupSize': colorGroupSize,
      if (direction != null) 'direction': direction,
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

      await docRef.set(UserService.sanitizeForFirestore({
        'name': patternName,
        'usageCount': 1,
        'lastUsed': FieldValue.serverTimestamp(),
        // #84 — jsonEncode to avoid native FSTUserDataReader rejecting
        // nested arrays like `'col': [[r,g,b,w]]` (uncatchable SIGABRT).
        // Mirrors the 8 other WLED-payload write paths; see
        // user_service.dart:298-300 for the canonical comment.
        'wledPayload': jsonEncode(patternData),
        'autoAdded': autoAdded,
      }), SetOptions(merge: true));
    } catch (e, st) {
      // #84 INSTRUMENTATION — TEMPORARY, strip before public release.
      await captureBug84(
        marker: 'BUG84-fav-write',
        step: 'write-catch',
        errorType: e.runtimeType.toString(),
        errorMessage: e.toString(),
        stackTrace: st.toString(),
      );
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