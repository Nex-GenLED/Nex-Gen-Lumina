import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/voice/deep_link_service.dart';
import 'package:nexgen_command/features/voice/siri_shortcut_service.dart';
import 'package:nexgen_command/features/voice/android_shortcut_service.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';

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
  // Use stub for now - full implementation requires Kotlin native code
  return AndroidShortcutServiceStub();
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

/// Run the current schedule
void _runSchedule(ProviderRef ref) {
  debugPrint('Voice: Running schedule');
  // This would trigger the schedule sync or apply current scheduled pattern
  // Implementation depends on schedule system
}
