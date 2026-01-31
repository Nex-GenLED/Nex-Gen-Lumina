import 'dart:io';
import 'dart:ui';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/voice/deep_link_service.dart';
import 'package:nexgen_command/features/voice/siri_shortcut_service.dart';
import 'package:nexgen_command/features/voice/android_shortcut_service.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/usage_tracking_extension.dart';

/// Provider for the Siri Shortcuts service (iOS only)
final siriShortcutServiceProvider = Provider<SiriShortcutService?>((ref) {
  if (!Platform.isIOS) return null;

  final service = SiriShortcutService(
    onShortcutActivated: (activityType, userInfo) {
      debugPrint('Voice: Siri shortcut activated: $activityType');
      _handleSiriShortcut(ref, activityType, userInfo);
    },
    onAddToSiriResult: (success, phrase, error) {
      debugPrint('Voice: Add to Siri result - success: $success, phrase: $phrase');
    },
  );

  ref.onDispose(() => service.dispose());
  return service;
});

/// Provider for the Android Shortcuts service
final androidShortcutServiceProvider = Provider<AndroidShortcutService?>((ref) {
  if (!Platform.isAndroid) return null;
  // Use full implementation with native Kotlin ShortcutManagerPlugin
  return AndroidShortcutService();
});

/// Provider for the Deep Link service
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService(
    onAction: (action) {
      debugPrint('Voice: Deep link action received: ${action.type}');
      _handleDeepLinkAction(ref, action);
    },
  );

  // Initialize the service
  service.initialize();

  ref.onDispose(() => service.dispose());
  return service;
});

/// Initialize voice assistant services
/// Call this early in app startup
Future<void> initializeVoiceServices(ProviderContainer container) async {
  // Touch the providers to initialize them
  container.read(deepLinkServiceProvider);

  if (Platform.isIOS) {
    container.read(siriShortcutServiceProvider);
  } else if (Platform.isAndroid) {
    container.read(androidShortcutServiceProvider);
  }

  debugPrint('Voice: Services initialized');
}

/// Donate a scene to Siri for suggestions
final donateSceneToSiriProvider = Provider<Future<bool> Function(Scene)>((ref) {
  return (scene) async {
    final siriService = ref.read(siriShortcutServiceProvider);
    if (siriService == null) return false;
    return siriService.donateSceneShortcut(scene);
  };
});

/// Present "Add to Siri" UI for a scene
final presentAddToSiriProvider = Provider<Future<bool> Function(Scene)>((ref) {
  return (scene) async {
    final siriService = ref.read(siriShortcutServiceProvider);
    if (siriService == null) return false;
    return siriService.presentAddToSiri(scene);
  };
});

/// Check if Siri Shortcuts are available
final isSiriAvailableProvider = Provider<bool>((ref) {
  return Platform.isIOS;
});

/// Check if Android Shortcuts are available
final isAndroidShortcutsAvailableProvider = Provider<bool>((ref) {
  return Platform.isAndroid;
});

/// Auto-donate a scene to voice assistants after save.
/// Call this from scene save providers to register with Siri/Android shortcuts.
final autoRegisterVoiceShortcutProvider = Provider<Future<void> Function(Scene)>((ref) {
  return (scene) async {
    // Donate to Siri on iOS
    if (Platform.isIOS) {
      final donateToSiri = ref.read(donateSceneToSiriProvider);
      await donateToSiri(scene);
      debugPrint('Voice: Auto-donated scene "${scene.name}" to Siri');
    }

    // Update dynamic shortcuts on Android
    if (Platform.isAndroid) {
      final androidService = ref.read(androidShortcutServiceProvider);
      if (androidService != null) {
        // Get all user scenes and update shortcuts
        final allScenesAsync = ref.read(allScenesProvider);
        allScenesAsync.whenData((scenes) {
          final userScenes = scenes.where((s) => s.type != SceneType.system).toList();
          androidService.updateShortcuts(userScenes);
        });
        debugPrint('Voice: Updated Android shortcuts after scene save');
      }
    }
  };
});

/// Donate system shortcuts (power on/off, colors) on app startup
final donateSystemShortcutsProvider = Provider<Future<void> Function()>((ref) {
  return () async {
    if (!Platform.isIOS) return;

    final siriService = ref.read(siriShortcutServiceProvider);
    if (siriService == null) return;

    // Donate power shortcuts
    await siriService.donatePowerShortcut(on: true);
    await siriService.donatePowerShortcut(on: false);

    // Donate color shortcuts
    await siriService.donateAllColorShortcuts();

    debugPrint('Voice: Donated system shortcuts to Siri');
  };
});

// ============== Private Handlers ==============

/// Handle Siri Shortcut activation
void _handleSiriShortcut(ProviderRef ref, String activityType, Map<String, dynamic> userInfo) {
  switch (activityType) {
    case SiriActivityTypes.applyScene:
      final sceneId = userInfo['sceneId'] as String?;
      if (sceneId != null) {
        _applySceneById(ref, sceneId);
      }
      break;

    case SiriActivityTypes.powerOn:
      _setPower(ref, true);
      break;

    case SiriActivityTypes.powerOff:
      _setPower(ref, false);
      break;

    case SiriActivityTypes.setBrightness:
      final level = userInfo['level'] as int?;
      if (level != null) {
        _setBrightness(ref, level);
      }
      break;

    case SiriActivityTypes.setColor:
      _setColor(ref, userInfo);
      break;
  }
}

/// Handle Deep Link action
void _handleDeepLinkAction(ProviderRef ref, DeepLinkAction action) {
  switch (action.type) {
    case DeepLinkActionType.powerOn:
      _setPower(ref, true);
      break;

    case DeepLinkActionType.powerOff:
      _setPower(ref, false);
      break;

    case DeepLinkActionType.setBrightness:
      final level = action.params['level'] as int?;
      if (level != null) {
        _setBrightness(ref, level);
      }
      break;

    case DeepLinkActionType.applySceneById:
      final sceneId = action.params['id'] as String?;
      if (sceneId != null) {
        _applySceneById(ref, sceneId);
      }
      break;

    case DeepLinkActionType.applySceneByName:
      final sceneName = action.params['name'] as String?;
      if (sceneName != null) {
        _applySceneByName(ref, sceneName);
      }
      break;

    case DeepLinkActionType.runSchedule:
      _runSchedule(ref);
      break;
  }
}

/// Apply scene by ID
void _applySceneById(ProviderRef ref, String sceneId) {
  debugPrint('Voice: Applying scene by ID: $sceneId');

  final allScenesAsync = ref.read(allScenesProvider);
  allScenesAsync.whenData((scenes) {
    final scene = scenes.firstWhere(
      (s) => s.id == sceneId || s.id.endsWith(sceneId),
      orElse: () => scenes.first,
    );

    ref.read(applySceneProvider)(scene);
  });
}

/// Apply scene by name
void _applySceneByName(ProviderRef ref, String sceneName) {
  debugPrint('Voice: Applying scene by name: $sceneName');

  final allScenesAsync = ref.read(allScenesProvider);
  allScenesAsync.whenData((scenes) {
    // Find scene by exact name match or partial match
    final scene = scenes.firstWhere(
      (s) => s.name.toLowerCase() == sceneName.toLowerCase(),
      orElse: () => scenes.firstWhere(
        (s) => s.name.toLowerCase().contains(sceneName.toLowerCase()),
        orElse: () => scenes.first,
      ),
    );

    ref.read(applySceneProvider)(scene);
  });
}

/// Set power on/off
void _setPower(ProviderRef ref, bool on) {
  debugPrint('Voice: Setting power: $on');

  final notifier = ref.read(wledStateProvider.notifier);
  notifier.togglePower(on);
}

/// Set brightness level
void _setBrightness(ProviderRef ref, int level) {
  debugPrint('Voice: Setting brightness: $level');

  final notifier = ref.read(wledStateProvider.notifier);
  notifier.setBrightness(level.clamp(0, 255));
}

/// Set color from Siri shortcut
void _setColor(ProviderRef ref, Map<String, dynamic> userInfo) {
  final r = (userInfo['r'] as num?)?.toInt() ?? 255;
  final g = (userInfo['g'] as num?)?.toInt() ?? 255;
  final b = (userInfo['b'] as num?)?.toInt() ?? 255;
  final w = (userInfo['w'] as num?)?.toInt();
  final colorName = userInfo['colorName'] as String? ?? 'Custom';

  debugPrint('Voice: Setting color to $colorName: RGB($r, $g, $b) W:$w');

  final notifier = ref.read(wledStateProvider.notifier);

  // Ensure lights are on
  notifier.togglePower(true);

  // Set the color
  notifier.setColor(Color.fromARGB(255, r, g, b));

  // Set white channel if specified (for RGBW strips)
  if (w != null && w > 0) {
    notifier.setWarmWhite(w);
  }

  // Update the preset label
  ref.read(activePresetLabelProvider.notifier).state = colorName;
}

/// Run the current schedule - applies whatever pattern/action should be active now
Future<void> _runSchedule(ProviderRef ref) async {
  debugPrint('Voice: Running schedule');

  // Find the current scheduled action based on time and day
  final currentSchedule = ref.read(currentScheduledActionProvider);

  if (currentSchedule == null) {
    debugPrint('Voice: No schedule is active right now');
    return;
  }

  final repo = ref.read(wledRepositoryProvider);
  if (repo == null) {
    debugPrint('Voice: No controller connected');
    return;
  }

  debugPrint('Voice: Applying "${currentSchedule.actionLabel}" from schedule "${currentSchedule.timeLabel}"');

  try {
    final action = currentSchedule.actionLabel.trim();
    final actionLower = action.toLowerCase();

    if (actionLower.contains('turn off') || actionLower == 'off') {
      await repo.applyJson({'on': false});
      ref.read(activePresetLabelProvider.notifier).state = 'Off (Scheduled)';
    } else if (actionLower.startsWith('brightness')) {
      final match = RegExp(r'(\d{1,3})%').firstMatch(action);
      final brightness = int.tryParse(match?.group(1) ?? '') ?? 100;
      final bri = (brightness * 255 / 100).round().clamp(0, 255);
      await repo.applyJson({'on': true, 'bri': bri});
      ref.read(activePresetLabelProvider.notifier).state = 'Brightness $brightness%';
    } else if (actionLower.startsWith('pattern')) {
      final idx = action.indexOf(':');
      final patternName = (idx != -1 && idx + 1 < action.length)
          ? action.substring(idx + 1).trim()
          : action.replaceFirst(RegExp(r'^(?i)pattern'), '').trim();

      final library = ref.read(publicPatternLibraryProvider);
      final pattern = library.all.where(
        (p) => p.name.toLowerCase() == patternName.toLowerCase()
      ).firstOrNull;

      if (pattern != null) {
        await repo.applyJson(pattern.toWledPayload());
        ref.read(activePresetLabelProvider.notifier).state = patternName;

        // Track usage
        ref.trackPatternUsage(pattern: pattern, source: 'voice');
      } else {
        debugPrint('Voice: Pattern "$patternName" not found, applying generic');
        await repo.applyJson({'on': true, 'bri': 200, 'seg': [{'id': 0, 'fx': 0}]});
        ref.read(activePresetLabelProvider.notifier).state = patternName;
      }
    } else if (actionLower.contains('turn on') || actionLower == 'on') {
      await repo.applyJson({'on': true, 'bri': 200});
      ref.read(activePresetLabelProvider.notifier).state = 'On (Scheduled)';
    } else {
      debugPrint('Voice: Unknown schedule action: $action');
      await repo.applyJson({'on': true});
      ref.read(activePresetLabelProvider.notifier).state = action;
    }

    debugPrint('Voice: Successfully applied schedule');
  } catch (e) {
    debugPrint('Voice: Run Schedule failed: $e');
  }
}
