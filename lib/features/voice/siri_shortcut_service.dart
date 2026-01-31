import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';

/// Service for managing Siri Shortcuts on iOS.
///
/// Allows the app to:
/// - Donate scenes to Siri for suggestions
/// - Present the "Add to Siri" UI for custom voice phrases
/// - Handle incoming shortcut activations
class SiriShortcutService {
  static const _channel = MethodChannel('com.nexgen.lumina/siri');

  /// Callback when a Siri Shortcut is activated
  final void Function(String activityType, Map<String, dynamic> userInfo)? onShortcutActivated;

  /// Callback when user completes "Add to Siri" flow
  final void Function(bool success, String? phrase, String? error)? onAddToSiriResult;

  SiriShortcutService({this.onShortcutActivated, this.onAddToSiriResult}) {
    _channel.setMethodCallHandler(_handleMethodCall);
  }

  /// Check if Siri Shortcuts are available (iOS 12+)
  bool get isAvailable => Platform.isIOS;

  /// Donate a scene as a Siri Shortcut suggestion.
  ///
  /// This makes the scene available in Siri Suggestions and the Shortcuts app.
  /// Siri learns from user patterns and may suggest this shortcut.
  Future<bool> donateSceneShortcut(Scene scene) async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('donateShortcut', {
        'sceneId': scene.id,
        'sceneName': scene.name,
        'activityType': 'com.nexgen.lumina.applyScene',
        'suggestedPhrase': 'Set lights to ${scene.name}',
      });
      debugPrint('SiriShortcutService: Donated shortcut for "${scene.name}"');
      return result ?? false;
    } catch (e) {
      debugPrint('SiriShortcutService: Failed to donate shortcut: $e');
      return false;
    }
  }

  /// Donate a power action shortcut
  Future<bool> donatePowerShortcut({required bool on}) async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('donateShortcut', {
        'sceneId': on ? 'power_on' : 'power_off',
        'sceneName': on ? 'Lights On' : 'Lights Off',
        'activityType': on ? 'com.nexgen.lumina.powerOn' : 'com.nexgen.lumina.powerOff',
        'suggestedPhrase': on ? 'Turn on my lights' : 'Turn off my lights',
      });
      return result ?? false;
    } catch (e) {
      debugPrint('SiriShortcutService: Failed to donate power shortcut: $e');
      return false;
    }
  }

  /// Donate a color shortcut
  Future<bool> donateColorShortcut({
    required String colorName,
    required int r,
    required int g,
    required int b,
    int? w,
  }) async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('donateShortcut', {
        'sceneId': 'color_${colorName.toLowerCase().replaceAll(' ', '_')}',
        'sceneName': colorName,
        'activityType': SiriActivityTypes.setColor,
        'suggestedPhrase': 'Set lights to $colorName',
        'userInfo': {
          'r': r,
          'g': g,
          'b': b,
          'w': w ?? 0,
          'colorName': colorName,
        },
      });
      debugPrint('SiriShortcutService: Donated color shortcut for "$colorName"');
      return result ?? false;
    } catch (e) {
      debugPrint('SiriShortcutService: Failed to donate color shortcut: $e');
      return false;
    }
  }

  /// Donate all predefined color shortcuts
  Future<void> donateAllColorShortcuts() async {
    for (final entry in SiriColorPresets.colors.entries) {
      await donateColorShortcut(
        colorName: entry.key,
        r: entry.value['r']!,
        g: entry.value['g']!,
        b: entry.value['b']!,
        w: entry.value['w'],
      );
    }
    debugPrint('SiriShortcutService: Donated all color presets');
  }

  /// Present the "Add to Siri" UI for a scene.
  ///
  /// This shows iOS's native voice shortcut creation UI where the user
  /// can record a custom phrase for the shortcut.
  Future<bool> presentAddToSiri(Scene scene) async {
    if (!isAvailable) return false;

    try {
      final result = await _channel.invokeMethod<bool>('presentAddToSiri', {
        'sceneId': scene.id,
        'sceneName': scene.name,
        'activityType': 'com.nexgen.lumina.applyScene',
        'suggestedPhrase': 'Set lights to ${scene.name}',
      });
      return result ?? false;
    } catch (e) {
      debugPrint('SiriShortcutService: Failed to present Add to Siri: $e');
      return false;
    }
  }

  /// Handle method calls from native side
  Future<dynamic> _handleMethodCall(MethodCall call) async {
    switch (call.method) {
      case 'onShortcutActivated':
        final args = call.arguments as Map<Object?, Object?>;
        final activityType = args['activityType'] as String?;
        final userInfo = (args['userInfo'] as Map<Object?, Object?>?)
            ?.map((k, v) => MapEntry(k.toString(), v)) ?? {};

        if (activityType != null) {
          debugPrint('SiriShortcutService: Shortcut activated: $activityType');
          onShortcutActivated?.call(activityType, userInfo);
        }
        break;

      case 'onAddToSiriResult':
        final args = call.arguments as Map<Object?, Object?>;
        final success = args['success'] as bool? ?? false;
        final phrase = args['phrase'] as String?;
        final error = args['error'] as String?;
        final cancelled = args['cancelled'] as bool? ?? false;

        debugPrint('SiriShortcutService: Add to Siri result - success: $success, phrase: $phrase');
        if (!cancelled) {
          onAddToSiriResult?.call(success, phrase, error);
        }
        break;
    }
  }

  /// Dispose of the service
  void dispose() {
    _channel.setMethodCallHandler(null);
  }
}

/// Activity types for Siri Shortcuts
class SiriActivityTypes {
  static const String applyScene = 'com.nexgen.lumina.applyScene';
  static const String powerOn = 'com.nexgen.lumina.powerOn';
  static const String powerOff = 'com.nexgen.lumina.powerOff';
  static const String setBrightness = 'com.nexgen.lumina.setBrightness';
  static const String setColor = 'com.nexgen.lumina.setColor';
}

/// Predefined color shortcuts for Siri
class SiriColorPresets {
  static const Map<String, Map<String, int>> colors = {
    'Warm White': {'r': 255, 'g': 180, 'b': 100, 'w': 150},
    'Cool White': {'r': 255, 'g': 255, 'b': 255, 'w': 255},
    'Daylight': {'r': 255, 'g': 240, 'b': 220, 'w': 200},
    'Red': {'r': 255, 'g': 0, 'b': 0, 'w': 0},
    'Green': {'r': 0, 'g': 255, 'b': 0, 'w': 0},
    'Blue': {'r': 0, 'g': 0, 'b': 255, 'w': 0},
    'Purple': {'r': 128, 'g': 0, 'b': 255, 'w': 0},
    'Orange': {'r': 255, 'g': 100, 'b': 0, 'w': 0},
    'Pink': {'r': 255, 'g': 50, 'b': 150, 'w': 0},
    'Cyan': {'r': 0, 'g': 255, 'b': 255, 'w': 0},
    'Yellow': {'r': 255, 'g': 255, 'b': 0, 'w': 0},
  };
}
