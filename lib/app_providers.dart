import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/auth/auth_manager.dart';
import 'package:nexgen_command/features/demo/demo_code_screen.dart' show validatedDemoCodeProvider;
import 'package:nexgen_command/features/labels/label_intent.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Global Simulation Mode toggle.
/// When true, the app bypasses permissions and network scanning, and can
/// simulate a local virtual device for fast web preview testing.
///
/// Note: You can also wire this to a bool.fromEnvironment or kDebugMode
/// if you want build-time control. Set to false for real device provisioning.
const bool kSimulationMode = false;

/// Whether the app is in the foreground (resumed). Fed by the root shell's
/// lifecycle observer (main_scaffold `didChangeAppLifecycleState`). Consumed by
/// surfaces that must stop work off-screen — e.g. the live score-badge poller
/// ([upcomingGameProvider]) which must not keep hitting ESPN in the background.
/// Defaults to true (the app is foreground at first build).
final appForegroundProvider = StateProvider<bool>((ref) => true);

// Demo state is intentionally in-memory only.
// Resets on app restart — no persistence needed.

/// Static flag mirroring [demoBrowsingProvider] for use in route guards
/// where a Riverpod ref is not available.
bool isDemoBrowsingFlag = false;

/// Global toggle for Demo Mode. When true, the app uses mock repositories
/// and bypasses network requirements to let users try the UI instantly.
final demoModeProvider = StateProvider<bool>((ref) => false);

/// True when a prospect is actively browsing the app in demo mode.
/// Used to show the demo banner and gate certain features.
final demoBrowsingProvider = StateProvider<bool>((ref) => false);

/// Stores the dealer code context for the current demo session.
/// Used to attribute the demo lead to the correct dealer.
final demoDealerCodeProvider = StateProvider<String?>((ref) => null);

/// Whether the demo conversion nudge snackbar has been shown this session.
final hasShownDemoNudgeProvider = StateProvider<bool>((ref) => false);

/// Atomically resets all demo-browsing state.
void exitDemoMode(WidgetRef ref) {
  ref.read(demoModeProvider.notifier).state = false;
  ref.read(demoBrowsingProvider.notifier).state = false;
  ref.read(demoDealerCodeProvider.notifier).state = null;
  ref.read(hasShownDemoNudgeProvider.notifier).state = false;
  ref.read(validatedDemoCodeProvider.notifier).state = null;
  isDemoBrowsingFlag = false;
}

/// Guided Mode toggle. When enabled (default), the app provides:
/// - Improved visual hierarchy with larger controls
/// - Contextual help and tooltips
/// - Auto-populated favorites from usage patterns
/// - Simplified navigation labels
/// - Quick action shortcuts
/// This mode doesn't restrict features - it makes them easier to discover and use.
final guidedModeProvider = StateProvider<bool>((ref) => true);

/// Legacy storage key. Persisted a bare label string with no device-state
/// fingerprint — that's the root of the "Now Playing shows Warm White after
/// cold restart regardless of device state" bug. Read once on app startup
/// for migration logging, then deleted. New writes go to [_activePresetIntentKey].
const String _activePresetKey = 'active_preset_label';

/// Current storage key. Persists a JSON-encoded [LabelIntent] containing the
/// label plus a device-state fingerprint (effectId, presetId, color hash).
/// On cold start the persisted intent is held in escrow until the first
/// successful /json/state poll, then either committed (fingerprint matches
/// device) or discarded (device has drifted).
const String _activePresetIntentKey = 'active_preset_label_intent';

/// Static cache for the active preset label to avoid async race conditions.
/// This ensures immediate reads return the correct value even during navigation.
String? _activePresetLabelCache;

/// Test-only escape hatch to clear the module-level [_activePresetLabelCache]
/// between test cases. Production code must not call this — the cache is
/// intentionally session-wide so navigation rebuilds preserve state.
@visibleForTesting
void resetActivePresetLabelCacheForTest() {
  _activePresetLabelCache = null;
}

/// Notifier that persists the active preset label to SharedPreferences with
/// a device-state fingerprint. The fingerprint is reconciled against the
/// freshly-polled WLED state on first poll after cold-start; if the device
/// has drifted (manual web-UI tap, schedule fired, controller reboot to
/// default), the stale label is dropped and the dashboard falls back to
/// the live effect name.
///
/// The legacy bare-string setter `state = '...'` is retained for backward
/// compatibility with the 30+ existing call sites; it persists without a
/// fingerprint and is marked deprecated. New code should call
/// [setLabelWithFingerprint] so the label round-trips correctly through a
/// cold restart.
class ActivePresetLabelNotifier extends Notifier<String?> {
  // Timestamp of the most recent state write. Read by the WLED polling loop's
  // _resolvePresetName so a stale in-flight HTTP response cannot overwrite a
  // label that was set very recently (e.g. by a user tapping a pattern card).
  DateTime? _labelUserSetAt;
  DateTime? get labelUserSetAt => _labelUserSetAt;

  /// Persisted intent loaded from SharedPreferences at startup, held in
  /// escrow until [reconcileWithDeviceState] is called with the first
  /// successful /json/state poll. Null after reconciliation or on fresh
  /// install. Single-use: cleared whether the intent was committed or
  /// discarded.
  LabelIntent? _pendingLabelIntent;

  /// Test hook: expose the in-escrow intent so tests can verify it landed
  /// in pending state before reconciliation. Not for production use.
  LabelIntent? get pendingLabelIntentForTest => _pendingLabelIntent;

  @override
  String? build() {
    // Return cached value immediately if available (handles navigation scenarios
    // and hot-reload — preserves state when the notifier rebuilds within a
    // single app session).
    if (_activePresetLabelCache != null) {
      return _activePresetLabelCache;
    }
    // Load persisted value asynchronously on first access. The result lands
    // in [_pendingLabelIntent] rather than [state] — the WLED notifier will
    // call [reconcileWithDeviceState] on the first successful poll to decide
    // whether to commit it.
    _loadPersistedValue();
    return null;
  }

  Future<void> _loadPersistedValue() async {
    try {
      final prefs = await SharedPreferences.getInstance();

      // One-time migration: surface any legacy bare-string label so we can
      // see it in logs, then delete the key. We deliberately do NOT promote
      // the legacy value into the new fingerprinted format — without a
      // fingerprint we can't reconcile against the device, and committing
      // it unconditionally would just reproduce the bug we're fixing.
      final legacyLabel = prefs.getString(_activePresetKey);
      if (legacyLabel != null) {
        debugPrint(
            '🏷️ Migrating legacy active_preset_label="$legacyLabel" → discarded (no fingerprint)');
        await prefs.remove(_activePresetKey);
      }

      final encoded = prefs.getString(_activePresetIntentKey);
      if (encoded == null || encoded.isEmpty) return;
      final intent = LabelIntent.decode(encoded);
      if (intent == null) {
        // Corrupt or unreadable — drop it.
        await prefs.remove(_activePresetIntentKey);
        return;
      }
      _pendingLabelIntent = intent;
      debugPrint(
          '🏷️ Loaded persisted intent into escrow: ${intent.toString()}');
    } catch (e) {
      debugPrint('🏷️ _loadPersistedValue error: $e');
    }
  }

  /// Reconcile the persisted intent (loaded in escrow at startup) against
  /// the device's freshly-polled state. One-shot per session: clears
  /// [_pendingLabelIntent] after running regardless of outcome.
  ///
  /// - If escrow is empty → no-op (fresh install or post-reconcile call).
  /// - If fingerprint matches → commit the label to [state].
  /// - If fingerprint mismatches → drop both the in-memory and persisted
  ///   intent. The dashboard will fall through to the live effect name.
  void reconcileWithDeviceState(WledStateModel deviceState) {
    final intent = _pendingLabelIntent;
    _pendingLabelIntent = null; // single-use, always clear
    if (intent == null) return;

    if (intent.matches(deviceState)) {
      debugPrint(
          '🏷️ Reconcile MATCH: restoring "${intent.label}" (fx=${intent.effectId}, ps=${intent.presetId}, color=${intent.colorFingerprint})');
      _activePresetLabelCache = intent.label;
      _labelUserSetAt = intent.writtenAt;
      // Bypass the deprecated setter so we don't re-persist (we already
      // have the intent stored; rewriting would just update writtenAt
      // unnecessarily). Persisted record stays as-is.
      super.state = intent.label;
    } else {
      debugPrint(
          '🏷️ Reconcile MISMATCH: dropping "${intent.label}" '
          '(intent fx=${intent.effectId} ps=${intent.presetId} color=${intent.colorFingerprint}, '
          'device fx=${deviceState.effectId} ps=${deviceState.presetId} color=${LabelIntent.fingerprintForState(deviceState)})');
      _activePresetLabelCache = null;
      super.state = null;
      _clearPersistedIntent();
    }
  }

  /// Preferred write path. Persists the label with a fingerprint of the
  /// current device state so cold-restart can verify the device hasn't
  /// drifted before re-showing the label.
  void setLabelWithFingerprint(String label, WledStateModel deviceState) {
    final intent = LabelIntent.fromDeviceState(
      label: label,
      deviceState: deviceState,
    );
    _activePresetLabelCache = label;
    _labelUserSetAt = intent.writtenAt;
    super.state = label;
    _persistIntent(intent);
  }

  /// Bare-string setter — keeps the 30+ existing call sites working without
  /// migration in this commit. Persists under the new key with a degenerate
  /// fingerprint (all zeros), which means the cold-restart reconciler will
  /// always treat it as a mismatch and drop it. That's intentional: bare
  /// labels can't be reliably restored across a cold start anyway, and the
  /// dashboard correctly falls back to the live effect name. Migrate call
  /// sites to [setLabelWithFingerprint] in a follow-up to make them
  /// cold-restart-stable.
  @Deprecated(
      'Use setLabelWithFingerprint(label, deviceState) so the label survives '
      'cold-restart reconciliation. The bare-string setter persists without '
      'a fingerprint and is dropped on the next cold start.')
  @override
  set state(String? value) {
    _activePresetLabelCache = value;
    _labelUserSetAt = DateTime.now();
    super.state = value;
    if (value == null || value.isEmpty) {
      _clearPersistedIntent();
    } else {
      // Degenerate fingerprint — guaranteed not to match any real device
      // state. The label survives the current session but won't be
      // restored across a cold start. Call sites that want round-trip
      // persistence should use setLabelWithFingerprint().
      _persistIntent(LabelIntent(
        label: value,
        effectId: -1,
        presetId: -1,
        colorFingerprint: '',
        writtenAt: _labelUserSetAt!,
      ));
    }
  }

  Future<void> _persistIntent(LabelIntent intent) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_activePresetIntentKey, intent.encode());
    } catch (e) {
      debugPrint('🏷️ _persistIntent error: $e');
    }
  }

  Future<void> _clearPersistedIntent() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_activePresetIntentKey);
    } catch (e) {
      debugPrint('🏷️ _clearPersistedIntent error: $e');
    }
  }

  /// Clear the active preset label (e.g., when turning off lights).
  void clear() {
    _activePresetLabelCache = null;
    _labelUserSetAt = DateTime.now();
    super.state = null;
    _clearPersistedIntent();
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

/// Whether the user is currently on their home (local) network.
/// Defaults to true if we can't determine (to preserve existing local-first behavior).
///
/// NOTE: The authoritative network check lives in [wledConnectivityStatusProvider]
/// (wled_providers.dart). This provider exists for non-WLED code that needs a
/// quick local-network boolean without pulling in the full WLED dependency tree.
/// It re-evaluates when the connectivity service or user profile changes.
final isLocalNetworkProvider = FutureProvider<bool>((ref) async {
  final service = ref.watch(connectivityServiceProvider);
  return service.isOnHomeNetwork(null); // null = no profile → assume local
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

/// Holds a pending voice message to be sent to Lumina chat.
/// When set, the Lumina chat screen will automatically consume and send it.
/// Set to null after the message is consumed.
final pendingVoiceMessageProvider = StateProvider<String?>((ref) => null);
