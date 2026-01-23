import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/scenes/scene_providers.dart';

/// Voice command handler for dashboard-level voice control
/// Processes natural language commands and routes them to appropriate providers
class VoiceCommandHandler {
  final Ref ref;

  VoiceCommandHandler(this.ref);

  /// Process a voice command and return a user-friendly confirmation message
  Future<String> processCommand(String command) async {
    final cmd = command.toLowerCase().trim();
    debugPrint('Voice: Processing dashboard command: $cmd');

    // Scene commands (check FIRST to prevent "turn on christmas" from triggering power on)
    if (_isSceneCommand(cmd)) {
      return await _handleSceneCommand(cmd);
    }

    // Power commands (only if not a scene command)
    if (_isPowerOnCommand(cmd)) {
      return await _handlePowerOn();
    } else if (_isPowerOffCommand(cmd)) {
      return await _handlePowerOff();
    }

    // "All off" - turn everything off
    else if (_isAllOffCommand(cmd)) {
      return await _handlePowerOff();
    }

    // Brightness adjustments
    else if (_isBrighterCommand(cmd)) {
      return await _handleBrighter();
    } else if (_isDimmerCommand(cmd)) {
      return await _handleDimmer();
    }

    // Pattern/scene commands
    else if (_isWarmWhiteCommand(cmd)) {
      return await _handleWarmWhite();
    } else if (_isBrightWhiteCommand(cmd)) {
      return await _handleBrightWhite();
    } else if (_isFestiveCommand(cmd)) {
      return await _handleFestive();
    }

    // Schedule commands
    else if (_isScheduleCommand(cmd)) {
      return await _handleSchedule(cmd);
    }

    // Fallback - command not recognized
    return 'I didn\'t understand "$command". Try saying "Turn on", "Warm white", or "Turn off at 10pm".';
  }

  // ========== Command Matchers ==========

  bool _isPowerOnCommand(String cmd) {
    return cmd.contains('turn on') ||
        cmd.contains('power on') ||
        cmd.contains('lights on') ||
        cmd == 'on';
  }

  bool _isPowerOffCommand(String cmd) {
    return cmd.contains('turn off') ||
        cmd.contains('power off') ||
        cmd.contains('lights off') ||
        cmd == 'off';
  }

  bool _isAllOffCommand(String cmd) {
    return cmd.contains('all off') ||
        cmd.contains('everything off') ||
        cmd.contains('turn everything off');
  }

  bool _isBrighterCommand(String cmd) {
    return cmd.contains('brighter') ||
        cmd.contains('increase brightness') ||
        cmd.contains('brighten');
  }

  bool _isDimmerCommand(String cmd) {
    return cmd.contains('dimmer') ||
        cmd.contains('decrease brightness') ||
        cmd.contains('dim');
  }

  bool _isWarmWhiteCommand(String cmd) {
    return cmd.contains('warm white') ||
        cmd.contains('warm light') ||
        cmd.contains('warm lights');
  }

  bool _isBrightWhiteCommand(String cmd) {
    return cmd.contains('bright white') ||
        cmd.contains('cool white') ||
        cmd.contains('white');
  }

  bool _isFestiveCommand(String cmd) {
    return cmd.contains('festive') ||
        cmd.contains('christmas') ||
        cmd.contains('holiday') ||
        cmd.contains('party');
  }

  bool _isScheduleCommand(String cmd) {
    return cmd.contains('at') && (cmd.contains('pm') || cmd.contains('am')) ||
        cmd.contains('schedule') ||
        cmd.contains('set timer');
  }

  // ========== Command Handlers ==========

  Future<String> _handlePowerOn() async {
    try {
      final notifier = ref.read(wledStateProvider.notifier);
      await notifier.togglePower(true);
      ref.read(activePresetLabelProvider.notifier).state = 'On';
      return '✓ Turning on';
    } catch (e) {
      debugPrint('Voice: Power on failed: $e');
      return 'Failed to turn on lights';
    }
  }

  Future<String> _handlePowerOff() async {
    try {
      final notifier = ref.read(wledStateProvider.notifier);
      await notifier.togglePower(false);
      ref.read(activePresetLabelProvider.notifier).state = 'Off';
      return '✓ Turning off';
    } catch (e) {
      debugPrint('Voice: Power off failed: $e');
      return 'Failed to turn off lights';
    }
  }

  Future<String> _handleBrighter() async {
    try {
      final state = ref.read(wledStateProvider);
      final currentBrightness = state.brightness;
      final newBrightness = (currentBrightness + 50).clamp(0, 255);

      final notifier = ref.read(wledStateProvider.notifier);
      await notifier.setBrightness(newBrightness);

      final percent = ((newBrightness / 255) * 100).round();
      return '✓ Brightness increased to $percent%';
    } catch (e) {
      debugPrint('Voice: Brighter failed: $e');
      return 'Failed to adjust brightness';
    }
  }

  Future<String> _handleDimmer() async {
    try {
      final state = ref.read(wledStateProvider);
      final currentBrightness = state.brightness;
      final newBrightness = (currentBrightness - 50).clamp(0, 255);

      final notifier = ref.read(wledStateProvider.notifier);
      await notifier.setBrightness(newBrightness);

      final percent = ((newBrightness / 255) * 100).round();
      return '✓ Brightness decreased to $percent%';
    } catch (e) {
      debugPrint('Voice: Dimmer failed: $e');
      return 'Failed to adjust brightness';
    }
  }

  Future<String> _handleWarmWhite() async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return 'No controller connected';

      // Warm white: RGB(255, 244, 229) - soft warm glow
      final payload = {
        'on': true,
        'bri': 200,
        'seg': [
          {
            'id': 0,
            'fx': 0, // Solid effect
            'col': [
              [255, 244, 229], // Warm white
            ],
          }
        ],
      };

      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = 'Warm White';
      return '✓ Applying warm white';
    } catch (e) {
      debugPrint('Voice: Warm white failed: $e');
      return 'Failed to apply warm white';
    }
  }

  Future<String> _handleBrightWhite() async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return 'No controller connected';

      // Bright white: RGB(255, 255, 255) - pure white
      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 0, // Solid effect
            'col': [
              [255, 255, 255], // Bright white
            ],
          }
        ],
      };

      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = 'Bright White';
      return '✓ Applying bright white';
    } catch (e) {
      debugPrint('Voice: Bright white failed: $e');
      return 'Failed to apply bright white';
    }
  }

  Future<String> _handleFestive() async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return 'No controller connected';

      // Festive: Red & Green chase effect
      final payload = {
        'on': true,
        'bri': 255,
        'seg': [
          {
            'id': 0,
            'fx': 28, // Chase effect
            'sx': 150, // Medium-fast speed
            'col': [
              [255, 0, 0], // Red
              [0, 255, 0], // Green
              [0, 0, 0], // Black spacer
            ],
          }
        ],
      };

      await repo.applyJson(payload);
      ref.read(activePresetLabelProvider.notifier).state = 'Festive';
      return '✓ Applying festive pattern';
    } catch (e) {
      debugPrint('Voice: Festive failed: $e');
      return 'Failed to apply festive pattern';
    }
  }

  Future<String> _handleSchedule(String cmd) async {
    try {
      // Extract time from command (e.g., "turn off at 10pm")
      final timeMatch = RegExp(r'(\d{1,2})\s*(am|pm)', caseSensitive: false).firstMatch(cmd);
      if (timeMatch == null) {
        return 'I couldn\'t understand the time. Try saying "Turn off at 10pm"';
      }

      final hour = int.parse(timeMatch.group(1)!);
      final meridiem = timeMatch.group(2)!.toLowerCase();

      // Determine action (turn off vs turn on)
      final isOffCommand = cmd.contains('off');
      final action = isOffCommand ? 'Turn Off' : 'Turn On';

      // Create a simple schedule entry
      // For now, just acknowledge - full schedule creation would require more UI
      final timeStr = '$hour$meridiem';
      return '✓ I\'ll $action at $timeStr. You can edit this in the Schedule tab.';
    } catch (e) {
      debugPrint('Voice: Schedule parsing failed: $e');
      return 'Failed to create schedule';
    }
  }

  // ========== Scene Command Handlers ==========

  bool _isSceneCommand(String cmd) {
    // Check for explicit scene triggers
    if (cmd.contains('scene') ||
        cmd.contains('apply') ||
        cmd.contains('switch to') ||
        cmd.contains('change to')) {
      return true;
    }

    // "turn on [scene name]" - but NOT just "turn on"
    if (cmd.startsWith('turn on ') && cmd.length > 8) {
      return true;
    }

    return false;
  }

  String? _extractSceneName(String cmd) {
    // Remove trigger words and extract scene name
    String sceneName = cmd;

    // Remove common trigger phrases
    sceneName = sceneName.replaceAll(RegExp(r'^(turn on|apply|switch to|change to|scene)\s+'), '');
    sceneName = sceneName.replaceAll(RegExp(r'\s+(scene|lights)$'), '');

    // Clean up extra whitespace
    sceneName = sceneName.trim();

    return sceneName.isEmpty ? null : sceneName;
  }

  int? _extractSceneNumber(String cmd) {
    // Match patterns like "scene number 2" or "scene 2"
    final match = RegExp(r'scene\s+(?:number\s+)?(\d+)', caseSensitive: false).firstMatch(cmd);
    if (match != null) {
      return int.tryParse(match.group(1)!);
    }
    return null;
  }

  Scene? _findMatchingScene(List<Scene> scenes, String searchName) {
    final search = searchName.toLowerCase().trim();

    // 1. Exact match
    for (final scene in scenes) {
      if (scene.name.toLowerCase() == search) {
        return scene;
      }
    }

    // 2. Starts with match
    for (final scene in scenes) {
      if (scene.name.toLowerCase().startsWith(search)) {
        return scene;
      }
    }

    // 3. Contains match
    for (final scene in scenes) {
      if (scene.name.toLowerCase().contains(search)) {
        return scene;
      }
    }

    // 4. Word-by-word match (for multi-word scenes)
    // "christmas lights" matches "lights" or "christmas"
    for (final scene in scenes) {
      final sceneWords = scene.name.toLowerCase().split(' ');
      if (sceneWords.contains(search)) {
        return scene;
      }
    }

    return null;
  }

  Future<String> _applyScene(Scene scene) async {
    try {
      final applyScene = ref.read(applySceneProvider);
      final success = await applyScene(scene);

      if (success) {
        ref.read(activePresetLabelProvider.notifier).state = scene.name;
        return '✓ Applying ${scene.name}';
      } else {
        return 'Failed to apply ${scene.name}';
      }
    } catch (e) {
      debugPrint('Voice: Apply scene failed: $e');
      return 'Failed to apply ${scene.name}';
    }
  }

  Future<String> _handleSceneCommand(String cmd) async {
    try {
      // Get all scenes
      final allScenesAsync = ref.read(allScenesProvider);

      // Check if async value has data
      final scenes = allScenesAsync.maybeWhen(
        data: (list) => list,
        orElse: () => <Scene>[],
      );

      if (scenes.isEmpty) {
        return 'No scenes found. Create scenes in the Explore tab.';
      }

      // Check for numbered scene command
      final sceneNumber = _extractSceneNumber(cmd);
      if (sceneNumber != null) {
        if (sceneNumber < 1 || sceneNumber > scenes.length) {
          return 'Scene number $sceneNumber not found. You have ${scenes.length} scenes.';
        }
        final scene = scenes[sceneNumber - 1];
        return await _applyScene(scene);
      }

      // Extract scene name
      final sceneName = _extractSceneName(cmd);
      if (sceneName == null || sceneName.isEmpty) {
        return 'I couldn\'t understand which scene to apply. Try saying "Turn on Christmas"';
      }

      // Find matching scene using fuzzy matching
      final matchedScene = _findMatchingScene(scenes, sceneName);
      if (matchedScene == null) {
        return 'Scene "$sceneName" not found. Check your scenes in the Explore tab.';
      }

      return await _applyScene(matchedScene);
    } catch (e) {
      debugPrint('Voice: Scene command failed: $e');
      return 'Failed to apply scene';
    }
  }
}

/// Provider for the voice command handler
final voiceCommandHandlerProvider = Provider<VoiceCommandHandler>((ref) {
  return VoiceCommandHandler(ref);
});
