import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:app_links/app_links.dart';

/// Service that handles deep links from Siri Shortcuts and Android App Shortcuts.
///
/// Supported URL schemes:
/// - lumina://power/on - Turn lights on
/// - lumina://power/off - Turn lights off
/// - lumina://brightness?level=128 - Set brightness (0-255)
/// - lumina://scene/apply?id={sceneId} - Apply scene by ID
/// - lumina://scene/apply?name={sceneName} - Apply scene by name
/// - lumina://schedule/run - Run current schedule
class DeepLinkService {
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  /// Callback for when a deep link action is received
  final void Function(DeepLinkAction action)? onAction;

  DeepLinkService({this.onAction});

  /// Initialize the deep link listener
  Future<void> initialize() async {
    // Handle initial link (app was launched from deep link)
    try {
      final initialUri = await _appLinks.getInitialLink();
      if (initialUri != null) {
        _handleUri(initialUri);
      }
    } catch (e) {
      debugPrint('DeepLinkService: Failed to get initial link: $e');
    }

    // Listen for subsequent links while app is running
    _subscription = _appLinks.uriLinkStream.listen(
      _handleUri,
      onError: (e) => debugPrint('DeepLinkService: Stream error: $e'),
    );
  }

  /// Parse and handle incoming URI
  void _handleUri(Uri uri) {
    debugPrint('DeepLinkService: Received URI: $uri');

    if (uri.scheme != 'lumina') {
      debugPrint('DeepLinkService: Ignoring non-lumina scheme: ${uri.scheme}');
      return;
    }

    final action = _parseUri(uri);
    if (action != null) {
      debugPrint('DeepLinkService: Parsed action: ${action.type}');
      onAction?.call(action);
    }
  }

  /// Parse URI into a DeepLinkAction
  DeepLinkAction? _parseUri(Uri uri) {
    final pathSegments = uri.pathSegments;
    if (pathSegments.isEmpty) return null;

    switch (pathSegments.first) {
      case 'power':
        if (pathSegments.length > 1) {
          if (pathSegments[1] == 'on') {
            return const DeepLinkAction(type: DeepLinkActionType.powerOn);
          } else if (pathSegments[1] == 'off') {
            return const DeepLinkAction(type: DeepLinkActionType.powerOff);
          }
        }
        break;

      case 'brightness':
        final levelStr = uri.queryParameters['level'];
        if (levelStr != null) {
          final level = int.tryParse(levelStr);
          if (level != null && level >= 0 && level <= 255) {
            return DeepLinkAction(
              type: DeepLinkActionType.setBrightness,
              params: {'level': level},
            );
          }
        }
        break;

      case 'scene':
        if (pathSegments.length > 1 && pathSegments[1] == 'apply') {
          final sceneId = uri.queryParameters['id'];
          final sceneName = uri.queryParameters['name'];
          if (sceneId != null) {
            return DeepLinkAction(
              type: DeepLinkActionType.applySceneById,
              params: {'id': sceneId},
            );
          } else if (sceneName != null) {
            return DeepLinkAction(
              type: DeepLinkActionType.applySceneByName,
              params: {'name': Uri.decodeComponent(sceneName)},
            );
          }
        }
        break;

      case 'schedule':
        if (pathSegments.length > 1 && pathSegments[1] == 'run') {
          return const DeepLinkAction(type: DeepLinkActionType.runSchedule);
        }
        break;
    }

    debugPrint('DeepLinkService: Could not parse URI: $uri');
    return null;
  }

  /// Dispose of the service
  void dispose() {
    _subscription?.cancel();
  }
}

/// Types of actions that can be triggered via deep links
enum DeepLinkActionType {
  powerOn,
  powerOff,
  setBrightness,
  applySceneById,
  applySceneByName,
  runSchedule,
}

/// Represents a deep link action with optional parameters
class DeepLinkAction {
  final DeepLinkActionType type;
  final Map<String, dynamic> params;

  const DeepLinkAction({
    required this.type,
    this.params = const {},
  });

  @override
  String toString() => 'DeepLinkAction($type, params: $params)';
}

/// Provider for the deep link service
final deepLinkServiceProvider = Provider<DeepLinkService>((ref) {
  final service = DeepLinkService();
  ref.onDispose(() => service.dispose());
  return service;
});
