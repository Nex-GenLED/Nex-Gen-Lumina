import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/auth/auth_manager.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global Simulation Mode toggle.
/// When true, the app bypasses permissions and network scanning, and can
/// simulate a local virtual device for fast web preview testing.
///
/// Note: You can also wire this to a bool.fromEnvironment or kDebugMode
/// if you want build-time control. Set to false for real device provisioning.
const bool kSimulationMode = false;

/// Global toggle for Demo Mode. When true, the app uses mock repositories
/// and bypasses network requirements to let users try the UI instantly.
final demoModeProvider = StateProvider<bool>((ref) => false);

/// Storage key for persisting the active preset label
const String _activePresetKey = 'active_preset_label';

/// Notifier that persists the active preset label to SharedPreferences.
/// This ensures the pattern name survives app restarts.
class ActivePresetLabelNotifier extends Notifier<String?> {
  @override
  String? build() {
    // Load persisted value asynchronously on first access
    _loadPersistedValue();
    return null;
  }

  Future<void> _loadPersistedValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(_activePresetKey);
      if (saved != null && saved.isNotEmpty) {
        state = saved;
      }
    } catch (e) {
      // Ignore errors - will just show default label
    }
  }

  @override
  set state(String? value) {
    super.state = value;
    _persistValue(value);
  }

  Future<void> _persistValue(String? value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (value == null || value.isEmpty) {
        await prefs.remove(_activePresetKey);
      } else {
        await prefs.setString(_activePresetKey, value);
      }
    } catch (e) {
      // Ignore persistence errors - label will just reset on next app launch
    }
  }

  /// Clear the active preset label (e.g., when turning off lights)
  void clear() {
    state = null;
  }
}

/// Tracks the currently active preset/pattern name for display in the UI.
/// Updated when user selects a quick control button or applies a pattern.
/// Persisted to SharedPreferences so it survives app restarts.
final activePresetLabelProvider = NotifierProvider<ActivePresetLabelNotifier, String?>(
  ActivePresetLabelNotifier.new,
);

/// Auth manager provider
final authManagerProvider = Provider<AuthManager>((ref) => FirebaseAuthManager());

/// Current user stream provider
final authStateProvider = StreamProvider<User?>((ref) {
  final authManager = ref.watch(authManagerProvider);
  return authManager.authStateChanges;
});

// ==================== Remote Access / Connectivity Providers ====================

/// Connectivity service for detecting local vs remote network
final connectivityServiceProvider = Provider<ConnectivityService>((ref) => ConnectivityService());

// Note: userServiceProvider is defined in user_profile_providers.dart

/// Current connectivity status (local, remote, or offline).
/// Updates every 10 seconds when watching.
final connectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  final connectivityService = ref.watch(connectivityServiceProvider);
  // Get home SSID from user profile (needs currentUserProfileProvider from site_providers)
  // For now, we'll use a simple approach - this will be wired up properly in wled_providers
  return connectivityService.watchConnectivity(null);
});

/// Whether the user is currently on their home (local) network.
/// Defaults to true if we can't determine (to preserve existing local-first behavior).
final isLocalNetworkProvider = FutureProvider<bool>((ref) async {
  final connectivityService = ref.watch(connectivityServiceProvider);
  // This will be properly wired to user's homeSsid in wled_providers.dart
  // For now, return true as a safe default
  return true;
});

/// Remote access configuration from user profile.
/// Returns null if remote access is not configured or disabled.
final remoteAccessConfigProvider = Provider<RemoteAccessConfig?>((ref) {
  // This will be properly wired to currentUserProfileProvider in wled_providers.dart
  // Returning null here - the actual logic is in wled_providers where we have access
  // to the user profile
  return null;
});

/// Tracks the currently selected tab index in the main navigation.
/// Used by screens like Lumina to detect when the user navigates away.
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);
