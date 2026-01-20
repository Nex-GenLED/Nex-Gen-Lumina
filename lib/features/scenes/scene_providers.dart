import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/smart_pattern.dart';

/// Service for scene CRUD operations
class SceneService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// Get scenes collection reference for a user
  CollectionReference<Map<String, dynamic>> _scenesCollection(String userId) {
    return _firestore.collection('users').doc(userId).collection('scenes');
  }

  /// Stream all scenes for a user (saved patterns only, not designs)
  Stream<List<Scene>> streamScenes(String userId) {
    return _scenesCollection(userId)
        .orderBy('updated_at', descending: true)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((doc) => Scene.fromFirestore(doc)).toList());
  }

  /// Save a scene to Firestore
  Future<String> saveScene(String userId, Scene scene) async {
    final docRef = scene.id.isEmpty
        ? _scenesCollection(userId).doc()
        : _scenesCollection(userId).doc(scene.id);

    final updatedScene = scene.copyWith(
      id: docRef.id,
      updatedAt: DateTime.now(),
    );

    await docRef.set(updatedScene.toFirestore());
    return docRef.id;
  }

  /// Delete a scene
  Future<void> deleteScene(String userId, String sceneId) async {
    await _scenesCollection(userId).doc(sceneId).delete();
  }

  /// Toggle favorite status
  Future<void> toggleFavorite(String userId, String sceneId, bool isFavorite) async {
    await _scenesCollection(userId).doc(sceneId).update({
      'is_favorite': isFavorite,
      'updated_at': Timestamp.now(),
    });
  }
}

/// Provider for scene service
final sceneServiceProvider = Provider<SceneService>((ref) {
  return SceneService();
});

/// Stream of user's saved scenes (patterns saved from library)
final savedScenesStreamProvider = StreamProvider<List<Scene>>((ref) {
  final user = ref.watch(authStateProvider).valueOrNull;
  if (user == null) return Stream.value([]);

  final service = ref.read(sceneServiceProvider);
  return service.streamScenes(user.uid);
});

/// Combined provider that merges all scene sources into a unified list
final allScenesProvider = Provider<AsyncValue<List<Scene>>>((ref) {
  final designsAsync = ref.watch(designsStreamProvider);
  final savedScenesAsync = ref.watch(savedScenesStreamProvider);

  // Combine the async values
  return designsAsync.when(
    data: (designs) {
      return savedScenesAsync.when(
        data: (savedScenes) {
          final allScenes = <Scene>[];

          // Add system presets first
          allScenes.addAll(SystemScenes.all);

          // Convert designs to scenes
          for (final design in designs) {
            allScenes.add(Scene.fromDesign(design));
          }

          // Add saved scenes (patterns from library)
          allScenes.addAll(savedScenes);

          // Sort by updated date, keeping system presets at the end
          allScenes.sort((a, b) {
            // System presets always go last
            if (a.type == SceneType.system && b.type != SceneType.system) return 1;
            if (b.type == SceneType.system && a.type != SceneType.system) return -1;
            // Favorites go first
            if (a.isFavorite && !b.isFavorite) return -1;
            if (b.isFavorite && !a.isFavorite) return 1;
            // Then by update date
            return b.updatedAt.compareTo(a.updatedAt);
          });

          return AsyncValue.data(allScenes);
        },
        loading: () => const AsyncValue.loading(),
        error: (e, st) => AsyncValue.error(e, st),
      );
    },
    loading: () => const AsyncValue.loading(),
    error: (e, st) => AsyncValue.error(e, st),
  );
});

/// Provider for user's custom scenes only (excludes system presets)
final userScenesProvider = Provider<AsyncValue<List<Scene>>>((ref) {
  final allScenes = ref.watch(allScenesProvider);
  return allScenes.whenData((scenes) =>
      scenes.where((s) => s.type != SceneType.system).toList());
});

/// Provider for favorite scenes
final favoriteScenesProvider = Provider<AsyncValue<List<Scene>>>((ref) {
  final allScenes = ref.watch(allScenesProvider);
  return allScenes.whenData((scenes) =>
      scenes.where((s) => s.isFavorite).toList());
});

/// Apply a scene to the connected device
final applySceneProvider = Provider<Future<bool> Function(Scene scene)>((ref) {
  return (scene) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    try {
      final payload = scene.toWledPayload();
      debugPrint('🎬 Applying scene "${scene.name}": $payload');
      final success = await repo.applyJson(payload);

      // Log usage for learning
      if (success) {
        final user = ref.read(authStateProvider).valueOrNull;
        if (user != null) {
          final userService = ref.read(userServiceProvider);

          // Extract color names from preview colors
          final colorNames = scene.previewColors
              .map((c) => _colorToName(c))
              .toSet()
              .toList();

          await userService.logPatternUsage(
            userId: user.uid,
            colorNames: colorNames,
            effectId: scene.effectId,
            wled: payload,
            source: 'scene_${scene.type.name}',
          );
        }
      }

      return success;
    } catch (e) {
      debugPrint('Error applying scene: $e');
      return false;
    }
  };
});

/// Save a pattern from library as a scene
final savePatternAsSceneProvider = Provider<Future<String?> Function(dynamic pattern)>((ref) {
  return (pattern) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return null;

    try {
      // Handle SmartPattern
      if (pattern is SmartPattern) {
        final scene = Scene.fromPattern(pattern, user.uid);
        final service = ref.read(sceneServiceProvider);
        return await service.saveScene(user.uid, scene);
      }

      debugPrint('Unsupported pattern type: ${pattern.runtimeType}');
      return null;
    } catch (e) {
      debugPrint('Error saving pattern as scene: $e');
      return null;
    }
  };
});

/// Capture current device state as a snapshot scene
final captureSnapshotProvider = Provider<Future<String?> Function(String name)>((ref) {
  return (name) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return null;

    final wledState = ref.read(wledStateProvider);
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return null;

    try {
      // Get full current state from device
      final fullState = await repo.getState();
      if (fullState == null) return null;

      // Extract relevant fields for the payload
      final payload = <String, dynamic>{
        'on': fullState['on'] ?? true,
        'bri': fullState['bri'] ?? 200,
      };

      // Include segment data if available
      if (fullState['seg'] != null) {
        payload['seg'] = fullState['seg'];
      }

      // Extract preview colors from segments
      final previewColors = <List<int>>[];
      final segments = fullState['seg'] as List?;
      if (segments != null && segments.isNotEmpty) {
        for (final seg in segments.take(2)) {
          final cols = seg['col'] as List?;
          if (cols != null) {
            for (final col in cols.take(2)) {
              if (col is List && col.length >= 3) {
                previewColors.add([col[0] as int, col[1] as int, col[2] as int]);
              }
            }
          }
        }
      }

      final scene = Scene.snapshot(
        name: name,
        ownerId: user.uid,
        wledPayload: payload,
        previewColors: previewColors,
        effectId: wledState.effectId,
        brightness: wledState.brightness,
      );

      final service = ref.read(sceneServiceProvider);
      return await service.saveScene(user.uid, scene);
    } catch (e) {
      debugPrint('Error capturing snapshot: $e');
      return null;
    }
  };
});

/// Delete a scene
final deleteSceneProvider = Provider<Future<bool> Function(Scene scene)>((ref) {
  return (scene) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return false;

    try {
      // For custom designs, delete from designs collection
      if (scene.type == SceneType.custom && scene.customDesign != null) {
        await ref.read(deleteDesignProvider)(scene.customDesign!.id);
        return true;
      }

      // For library/snapshot scenes, delete from scenes collection
      if (scene.type == SceneType.library || scene.type == SceneType.snapshot) {
        final service = ref.read(sceneServiceProvider);
        await service.deleteScene(user.uid, scene.id);
        return true;
      }

      // System scenes cannot be deleted
      return false;
    } catch (e) {
      debugPrint('Error deleting scene: $e');
      return false;
    }
  };
});

/// Toggle scene favorite status
final toggleSceneFavoriteProvider = Provider<Future<bool> Function(Scene scene)>((ref) {
  return (scene) async {
    final user = ref.read(authStateProvider).valueOrNull;
    if (user == null) return false;

    try {
      final service = ref.read(sceneServiceProvider);
      await service.toggleFavorite(user.uid, scene.id, !scene.isFavorite);
      return true;
    } catch (e) {
      debugPrint('Error toggling favorite: $e');
      return false;
    }
  };
});

/// Helper to convert RGB array to color name
String _colorToName(List<int> color) {
  if (color.length < 3) return 'unknown';
  final r = color[0];
  final g = color[1];
  final b = color[2];

  if (r > 200 && g < 100 && b < 100) return 'red';
  if (r < 100 && g > 200 && b < 100) return 'green';
  if (r < 100 && g < 100 && b > 200) return 'blue';
  if (r > 200 && g > 200 && b > 200) return 'white';
  if (r > 200 && g > 200 && b < 100) return 'yellow';
  if (r > 200 && g > 100 && g < 200 && b < 100) return 'orange';
  if (r > 100 && g < 100 && b > 200) return 'purple';
  if (r < 100 && g > 200 && b > 200) return 'cyan';
  if (r > 200 && g < 150 && b > 150) return 'pink';

  return 'custom';
}
