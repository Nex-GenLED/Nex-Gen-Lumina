import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';

/// Service for managing Android App Shortcuts (long-press launcher shortcuts).
///
/// Supports:
/// - Static shortcuts defined in shortcuts.xml (always available)
/// - Dynamic shortcuts created at runtime for user scenes
/// - Pinned shortcuts added to home screen
class AndroidShortcutService {
  static const _channel = MethodChannel('com.nexgen.lumina/shortcuts');

  /// Maximum number of dynamic shortcuts allowed
  static const int maxDynamicShortcuts = 4;

  /// Check if Android shortcuts are available
  bool get isAvailable => Platform.isAndroid;

  /// Update dynamic shortcuts with the user's scenes.
  ///
  /// This replaces all current dynamic shortcuts with the provided scenes.
  /// Maximum 4 shortcuts due to Android limits.
  Future<bool> updateShortcuts(List<Scene> scenes) async {
    if (!isAvailable) return false;

    try {
      // Take the most recently used/favorite scenes
      final shortcutScenes = scenes
          .where((s) => s.type != SceneType.system) // Skip system presets
          .take(maxDynamicShortcuts)
          .toList();

      final shortcutsData = shortcutScenes.map((scene) => {
        'id': 'scene_${scene.id}',
        'shortLabel': scene.name,
        'longLabel': 'Activate ${scene.name}',
        'uri': 'lumina://scene/apply?id=${Uri.encodeComponent(scene.id)}',
        'iconType': _iconTypeForScene(scene),
      }).toList();

      await _channel.invokeMethod('updateDynamicShortcuts', {
        'shortcuts': shortcutsData,
      });

      debugPrint('AndroidShortcutService: Updated ${shortcutsData.length} dynamic shortcuts');
      return true;
    } catch (e) {
      debugPrint('AndroidShortcutService: Failed to update shortcuts: $e');
      return false;
    }
  }

  /// Pin a scene shortcut to the home screen.
  ///
  /// This adds a shortcut icon to the user's home screen that directly
  /// activates the scene when tapped.
  Future<bool> pinShortcut(Scene scene) async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('pinShortcut', {
        'id': 'scene_${scene.id}',
        'shortLabel': scene.name,
        'longLabel': 'Activate ${scene.name}',
        'uri': 'lumina://scene/apply?id=${Uri.encodeComponent(scene.id)}',
        'iconType': _iconTypeForScene(scene),
      });

      debugPrint('AndroidShortcutService: Pinned shortcut for "${scene.name}"');
      return result ?? false;
    } catch (e) {
      debugPrint('AndroidShortcutService: Failed to pin shortcut: $e');
      return false;
    }
  }

  /// Report that a shortcut was used (helps Android prioritize it)
  Future<void> reportShortcutUsed(String sceneId) async {
    if (!isAvailable) return;

    try {
      await _channel.invokeMethod('reportShortcutUsed', {
        'id': 'scene_$sceneId',
      });
    } catch (e) {
      debugPrint('AndroidShortcutService: Failed to report shortcut usage: $e');
    }
  }

  /// Remove a dynamic shortcut
  Future<bool> removeShortcut(String sceneId) async {
    if (!isAvailable) return false;

    try {
      await _channel.invokeMethod('removeShortcut', {
        'id': 'scene_$sceneId',
      });
      return true;
    } catch (e) {
      debugPrint('AndroidShortcutService: Failed to remove shortcut: $e');
      return false;
    }
  }

  /// Check if pinned shortcuts are supported
  Future<bool> isPinnedShortcutSupported() async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('isPinnedShortcutSupported');
      return result ?? false;
    } catch (e) {
      return false;
    }
  }

  /// Get icon type based on scene type
  String _iconTypeForScene(Scene scene) {
    switch (scene.type) {
      case SceneType.custom:
        return 'custom';
      case SceneType.library:
        return 'pattern';
      case SceneType.snapshot:
        return 'camera';
      case SceneType.system:
        return 'system';
    }
  }
}

/// Native Android shortcut manager implementation
/// Note: This requires a corresponding Kotlin implementation on the Android side.
/// For now, we'll use a stub that doesn't require native code.
class AndroidShortcutServiceStub extends AndroidShortcutService {
  @override
  Future<bool> updateShortcuts(List<Scene> scenes) async {
    // Android shortcuts work through intent filters in the manifest
    // and the shortcuts.xml file. Dynamic shortcuts require native code.
    // This stub always returns true as static shortcuts are already defined.
    debugPrint('AndroidShortcutService: Using stub (static shortcuts only)');
    return true;
  }

  @override
  Future<bool> pinShortcut(Scene scene) async {
    // Pinning requires native ShortcutManager API
    debugPrint('AndroidShortcutService: Pin shortcut not available in stub');
    return false;
  }

  @override
  Future<bool> isPinnedShortcutSupported() async => false;
}
