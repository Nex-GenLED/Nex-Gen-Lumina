import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/schedule/schedule_enforcement.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/ddp_service.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/demo/demo_wled_repository.dart';
import 'package:nexgen_command/features/wled/cloud_relay_repository.dart';
import 'package:nexgen_command/features/wled/controller_defaults_healer.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/services/bridge_health_service.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';

/// Defensive int coercion used by [WledNotifier.applyPayloadWithLabel] when
/// reading WLED JSON payload fields that may be `int`, `num`, or absent.
int? _asInt(Object? v) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  return null;
}

/// Connectivity status stream that checks if user is on home network.
///
/// Polls every 10 seconds using the user's saved homeSsidHash from their
/// profile. Re-evaluates whenever the user profile changes (e.g. after
/// saving a new home SSID in Remote Access settings).
///
/// Also invalidated on app resume via [_connectivityRefreshProvider] so a
/// fresh SSID check runs immediately when the user opens the app.
final wledConnectivityStatusProvider = StreamProvider<ConnectivityStatus>((ref) {
  // Prevent the stream from being disposed when temporarily unwatched
  // (e.g. during screen transitions). Without this, navigating away from
  // every screen that watches this provider would destroy & recreate the
  // stream, causing a brief "loading" gap → null repository → false offline.
  ref.keepAlive();

  // Watch the refresh counter — incrementing it restarts this stream,
  // which clears the SSID cache and forces a fresh network check.
  ref.watch(_connectivityRefreshProvider);

  final connectivityService = ref.watch(connectivityServiceProvider);
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );

  final homeSsidHash = userProfile?.homeSsidHash;

  // Clear cached SSID so the first emission uses a live value.
  connectivityService.clearCache();

  return connectivityService.watchConnectivity(homeSsidHash);
});

/// Last-known connectivity status. Updated whenever the stream emits.
/// Used as fallback during stream rebuilds so the repository provider
/// never sees null during the async loading gap.
final _lastConnectivityStatusProvider = StateProvider<ConnectivityStatus?>((ref) => null);

/// Counter that, when incremented, forces [wledConnectivityStatusProvider]
/// to restart its stream and re-check the network.
final _connectivityRefreshProvider = StateProvider<int>((ref) => 0);

/// Call this to force an immediate network re-check (e.g. on app resume).
void refreshConnectivityStatus(WidgetRef ref) {
  ref.read(connectivityServiceProvider).clearCache();
  ref.read(_connectivityRefreshProvider.notifier).state++;
}

/// Overload for use inside providers / notifiers (Ref instead of WidgetRef).
void refreshConnectivityStatusFromRef(Ref ref) {
  ref.read(connectivityServiceProvider).clearCache();
  ref.read(_connectivityRefreshProvider.notifier).state++;
}

/// Whether the app is currently in remote mode (cloud relay).
/// Falls back to last-known status during stream loading gaps.
final isRemoteModeProvider = Provider<bool>((ref) {
  final status = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (s) => s,
    orElse: () => ref.read(_lastConnectivityStatusProvider),
  );
  return status == ConnectivityStatus.remote;
});

/// Shared bridge reachability state.
///
/// Set to `true` by the Remote Access screen (or any future code) when a
/// Firestore round-trip through the ESP32 bridge succeeds. Set to `false`
/// when a bridge test fails or times out. `null` means "never tested yet."
///
/// The home-screen indicator reads this to decide whether to show
/// "bridge active" (green/teal) vs "offline" (red) when in remote mode.
final bridgeReachableProvider = StateProvider<bool?>((ref) => null);

/// One-time startup bridge health check.
///
/// Runs when the authenticated user has a registered controller. Writes a
/// ping document to Firestore and waits up to 15 s for the ESP32 bridge to
/// acknowledge it. The result is exposed as [BridgeHealth] for future UI use.
final bridgeHealthProvider = FutureProvider<BridgeHealth>((ref) async {
  final userId = ref.watch(authStateProvider).maybeWhen(
    data: (user) => user?.uid,
    orElse: () => null,
  );
  final controllerId = ref.watch(selectedControllerIdProvider);
  final ip = ref.watch(selectedDeviceIpProvider);

  // Can't run the check without auth + a registered controller.
  if (userId == null || controllerId == null || ip == null) {
    return BridgeHealth.unreachable;
  }

  final service = BridgeHealthService();
  return service.check(userId: userId, controllerIp: ip);
});

/// Provides a WledRepository based on Demo Mode, network location, and
/// controller registration.
///
/// Priority:
/// 1.  Demo / reviewer mode                         → DemoWledRepository
/// 2.  No selected device IP                        → null
/// 3.  Connectivity loading                         → null (wait for check)
/// 4.  Offline                                      → null
/// 5.  Local WiFi                                   → WledService (direct HTTP, fastest)
/// 6.  Remote + userId + controllerId               → CloudRelayRepository (bridge relay)
/// 7.  Everything else                              → null
final wledRepositoryProvider = Provider<WledRepository?>((ref) {
  // ── 1. Demo / reviewer mode ───────────────────────────────────────────────
  final isDemo = ref.watch(demoModeProvider);
  if (isDemo) {
    debugPrint('RepositoryInit: selected=DemoWledRepository, network=n/a, hasControllerId=n/a');
    return DemoWledRepository();
  }

  final authUser = ref.watch(authStateProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );
  final userId = authUser?.uid;
  if (ReviewerSeedService.isReviewer(authUser)) {
    debugPrint('RepositoryInit: selected=DemoWledRepository, network=n/a, hasControllerId=n/a');
    return DemoWledRepository();
  }

  // ── 2. Require a selected device ─────────────────────────────────────────
  final ip = ref.watch(selectedDeviceIpProvider);
  if (ip == null) {
    debugPrint('RepositoryInit: selected=null, network=n/a, hasControllerId=n/a');
    return null;
  }

  // ── 3. Network location ──────────────────────────────────────────────────
  //
  // When the connectivity stream rebuilds (profile change, app resume) there
  // is a brief async gap where the StreamProvider is in "loading" state.
  // Fall back to the last-known status so we don't flash null → offline.
  final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
    data: (status) {
      // Cache every successful emission for use during future loading gaps.
      // Defer to a microtask so the mutation lands AFTER this provider's
      // build completes — Riverpod forbids providers from mutating other
      // providers during their own initialization (debug-only assertion,
      // fired 8x per cold launch). Microtasks drain before the next event
      // loop iteration, so no listener can observe stale state visibly.
      // Item #68.
      Future.microtask(() {
        ref.read(_lastConnectivityStatusProvider.notifier).state = status;
      });
      return status;
    },
    orElse: () => ref.read(_lastConnectivityStatusProvider),
  );

  if (connectivityStatus == null) {
    debugPrint('RepositoryInit: selected=null, network=null (loading), hasControllerId=n/a');
    return null;
  }

  // ── 4. Offline → no repository ───────────────────────────────────────────
  if (connectivityStatus == ConnectivityStatus.offline) {
    debugPrint('RepositoryInit: selected=null, network=offline, hasControllerId=n/a');
    return null;
  }

  // ── Shared lookups for steps 5-7 ─────────────────────────────────────────
  final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
    data: (user) => user,
    orElse: () => null,
  );
  final controllerId = ref.watch(selectedControllerIdProvider);
  final webhookUrl = userProfile?.webhookUrl;

  // ── 5. Local WiFi → always use direct HTTP ───────────────────────────────
  //
  // Direct HTTP to the controller is faster and more reliable than any relay.
  // The bridge/cloud relay paths are for remote access only.
  if (connectivityStatus == ConnectivityStatus.local) {
    debugPrint('RepositoryInit: selected=WledService, '
        'network=${connectivityStatus.name}, hasControllerId=$controllerId');
    return WledService('http://$ip');
  }

  // ── 6. Remote + Firestore bridge relay ───────────────────────────────────
  if (userId != null && controllerId != null) {
    final hasWebhook = webhookUrl != null && webhookUrl.isNotEmpty;
    final mode = hasWebhook ? 'Webhook relay' : 'ESP32 Bridge';
    final bridgeTarget = hasWebhook ? webhookUrl : 'firestore://$userId/commands';
    debugPrint('🏠 BridgeRouter: routing via BRIDGE, url=$bridgeTarget ($mode)');
    debugPrint('RepositoryInit: selected=CloudRelayRepository, '
        'network=${connectivityStatus.name}, hasControllerId=$controllerId');
    return CloudRelayRepository(
      userId: userId,
      controllerId: controllerId,
      controllerIp: ip,
      webhookUrl: webhookUrl ?? '',
    );
  }

  // ── 7. Remote but no relay path available ────────────────────────────────
  debugPrint('RepositoryInit: selected=null, '
      'network=${connectivityStatus.name}, hasControllerId=$controllerId');
  return null;
});

/// Provider for the currently selected controller's Firestore document ID.
/// Needed for cloud relay to identify which controller to target.
final selectedControllerIdProvider = Provider<String?>((ref) {
  final controllers = ref.watch(controllersStreamProvider).maybeWhen(
    data: (list) => list,
    orElse: () => <dynamic>[],
  );
  final selectedIp = ref.watch(selectedDeviceIpProvider);

  if (selectedIp == null || controllers.isEmpty) return null;

  // Find the controller with matching IP
  for (final controller in controllers) {
    if (controller.ip == selectedIp) {
      return controller.id;
    }
  }

  return null;
});

/// Provider that fetches the total LED count from the connected WLED device.
/// Returns null if no device is connected or if the count cannot be fetched.
final deviceTotalLedCountProvider = FutureProvider<int?>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return null;

  try {
    return await repo.getTotalLedCount();
  } catch (e) {
    debugPrint('Error fetching device LED count: $e');
    return null;
  }
});

/// Provider that fetches the full hardware LED configuration (buses, power, etc.)
/// from the connected WLED device via GET /json/cfg.
final deviceHardwareConfigProvider = FutureProvider<WledHardwareConfig?>((ref) async {
  final repo = ref.watch(wledRepositoryProvider);
  if (repo == null) return null;

  try {
    return await repo.getConfig();
  } catch (e) {
    debugPrint('Error fetching device hardware config: $e');
    return null;
  }
});

/// Provider for updating segment configuration on the WLED device.
/// Returns a function that can be called to update a segment's boundaries.
final updateSegmentConfigProvider = Provider<Future<bool> Function({
  required int segmentId,
  int? start,
  int? stop,
})>((ref) {
  return ({required int segmentId, int? start, int? stop}) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    try {
      return await repo.updateSegmentConfig(
        segmentId: segmentId,
        start: start,
        stop: stop,
      );
    } catch (e) {
      debugPrint('Error updating segment config: $e');
      return false;
    }
  };
});

/// Tag for a continuous-knob command class that coalesces latest-wins
/// inside [WledNotifier._postUpdate]. Discrete intents (power on/off,
/// pattern apply, preset load) MUST NOT be tagged — every tap must
/// execute. See [WledNotifier._postUpdate] for the gate logic.
const String _kTransientBrightness = 'brightness';
const String _kTransientSpeed = 'speed';
const String _kTransientColor = 'color';

/// Args carried forward when a transient write is coalesced. Stored in
/// [WledNotifier._transientPending] and replayed by the in-flight write's
/// `finally` block. Latest-wins: each new arrival overwrites the slot.
class _PendingPost {
  final bool? on;
  final int? brightness;
  final int? speed;
  final Color? color;
  final int? white;
  final bool? forceRgbwZeroWhite;
  final bool isManualChange;
  const _PendingPost({
    this.on,
    this.brightness,
    this.speed,
    this.color,
    this.white,
    this.forceRgbwZeroWhite,
    required this.isManualChange,
  });
}

/// Pure, deterministic background-poll cadence policy for [WledNotifier].
///
/// Extracted so the throttle/backoff logic is unit-testable without a
/// ProviderContainer. The goal is to stop the phone overwhelming its own
/// bridge with status polls — measured: 90% of all command timeouts were the
/// remote getState poll firing every 10s into a serial bridge queue.
///
///   • Remote base 10s / local base 1.5s (unchanged steady-state).
///   • Backgrounded → poll rarely (remote 60s) / slowly (local 10s): the user
///     isn't watching live state, so don't flood the queue.
///   • Failure backoff applies ONLY once the bridge is already marked offline
///     (consecutiveFailures >= downgradeThreshold). The first N failures stay
///     at base cadence so the offline indicator still trips on time; afterward
///     we stop hammering a dead bridge, capped at [maxBackoff], still polling
///     often enough to notice recovery.
class PollCadencePolicy {
  static const remoteBase = Duration(seconds: 10);
  static const localBase = Duration(milliseconds: 1500);
  static const remoteBackground = Duration(seconds: 60);
  static const localBackground = Duration(seconds: 10);
  static const maxBackoff = Duration(seconds: 120);

  static Duration intervalFor({
    required bool isRemote,
    required bool backgrounded,
    required int consecutiveFailures,
    required int downgradeThreshold,
  }) {
    final base = isRemote ? remoteBase : localBase;
    if (backgrounded) return isRemote ? remoteBackground : localBackground;
    // Failure backoff is remote-only: a LAN failure flips offline immediately
    // and a fast local retry is cheap. Kicks in only after the offline
    // threshold so the indicator isn't slowed.
    if (isRemote && consecutiveFailures >= downgradeThreshold) {
      final over = consecutiveFailures - downgradeThreshold; // 0,1,2,...
      final shift = (over + 1).clamp(1, 4); // mult 2,4,8,16
      final backed = base * (1 << shift);
      return backed > maxBackoff ? maxBackoff : backed;
    }
    return base;
  }
}

/// Thin lifecycle observer that forwards app foreground/background transitions
/// to [WledNotifier] so it can adjust poll cadence. Kept separate so the
/// notifier doesn't have to be a WidgetsBindingObserver itself.
class _WledPollLifecycleObserver extends WidgetsBindingObserver {
  _WledPollLifecycleObserver(this.onState);
  final void Function(AppLifecycleState) onState;
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) => onState(state);
}

class WledNotifier extends Notifier<WledStateModel> {
  Timer? _poller;
  GammaWatchdog? _gammaWatchdog;
  bool _posting = false;
  bool _polling = false;
  bool _infoQueried = false;

  /// True while the app is backgrounded — drives poll-cadence backoff so a
  /// suspended app doesn't keep flooding the bridge queue with status polls.
  bool _appBackgrounded = false;

  /// Set in onDispose so the self-scheduling poller stops rescheduling after
  /// the notifier is torn down.
  bool _disposed = false;

  /// Per-transient-type in-flight gate + latest-wins pending slot.
  ///
  /// While a write of a given transient type (brightness/speed/color) is
  /// in flight, a newer write of the SAME type replaces the slot in
  /// [_transientPending] rather than issuing a second durable command.
  /// The in-flight write's `finally` block drains the slot recursively.
  /// Discrete commands (power, pattern apply) pass `transientType: null`
  /// and bypass this entirely.
  final Set<String> _transientInFlight = <String>{};
  final Map<String, _PendingPost> _transientPending = <String, _PendingPost>{};

  // Monotonically incremented for every _resolvePresetName invocation. The
  // resolver captures its seq at entry and aborts the write if a newer call
  // has since started — prevents a stale HTTP response from clobbering a
  // freshly-written user label.
  int _resolveSeq = 0;

  // Monotonically incremented by every optimistic device-state setter
  // (togglePower / setBrightness / setSpeed / setColor / setWarmWhite). Each
  // poll captures this value just before its getState dispatch and passes it
  // into [_applyStateData]; if the counter has since advanced (a newer
  // optimistic write landed while the poll was in flight), the poll's
  // device-echoed visual fields are suppressed at the commit site — closing
  // the #87b optimistic-UI vs stale-poll race. Distinct from [_resolveSeq]
  // (preset-name resolver) — different lifecycle, different write set.
  int _stateApplySeq = 0;

  /// Consecutive remote poll failures. After 3, bridge is marked unreachable
  /// even if it was previously confirmed — prevents stale "Connected" status.
  int _consecutiveRemoteFailures = 0;
  static const _maxRemoteFailuresBeforeDowngrade = 3;

  /// One-shot guard for the cold-start Now Playing label reconciliation.
  /// Flipped true on the first successful /json/state parse after notifier
  /// construction (or refreshConnection-driven rebuild), preventing
  /// subsequent polls from re-triggering reconcile. See
  /// ActivePresetLabelNotifier.reconcileWithDeviceState.
  bool _hasReconciledOnStartup = false;

  /// Flipped true at the END of the first successful _applyStateData, AFTER
  /// the cold-start reconciler has run. Gates the steady-state polling
  /// resolver: on the first poll, cold-start reconciliation owns the label
  /// outcome and the resolver does not touch activePresetLabelProvider;
  /// on subsequent polls, the resolver handles steady-state drift
  /// (preset changes + effect-only changes) via [_resolvePresetName] and
  /// the effect-drift clear branch. See the comment block in
  /// [_applyStateData] for the full lifecycle.
  bool _hasPolledOnce = false;

  /// Wall-clock time of the most recent [applyLocalPreview] /
  /// [applyPreviewSync] call. Within [_kLocalApplyPollSuppressWindow] of
  /// this stamp, [_applyStateData] skips writes to the visual fields the
  /// local apply just owned — preventing the polled (lossy) representation
  /// of the device state from clobbering the as-sent preview.
  ///
  /// The user-facing apply paths bypass `_postUpdate` and call `applyJson`
  /// directly, so the regular 1.5s periodic poller is the clobber source.
  /// Window sizing math (local mode, 1.5s poll cadence):
  ///   need ≥ poll_cadence + max_observed_echo_lag
  /// On-device validation of the 2s window showed a slow-effect residual
  /// race where the device's `/json/state` echo lagged >2s; a poll fired
  /// between window-close (2s) and next-cycle (3s) read the stale device
  /// state and clobbered. 3500ms covers two full poll cycles (3.0s) plus
  /// a 500ms buffer for slower effect transitions while still letting
  /// external visual-field changes surface within ~4s. Remote mode (10s
  /// cadence) sees no poll inside the window so the guard is a no-op there.
  DateTime? _lastLocalApplyAt;
  static const _kLocalApplyPollSuppressWindow =
      Duration(milliseconds: 3500);

  bool _isPollOverwriteSuppressed() {
    final at = _lastLocalApplyAt;
    if (at == null) return false;
    return DateTime.now().difference(at) < _kLocalApplyPollSuppressWindow;
  }

  @override
  WledStateModel build() {
    final s = WledStateModel.initial();
    // Lifecycle-aware poll backoff: when the app is backgrounded the user
    // isn't watching live state, so we poll far less often (don't flood the
    // bridge queue). Registration is defensive — a plain unit test without a
    // WidgetsBinding simply runs without lifecycle backoff (the cadence policy
    // is still exercised directly in PollCadencePolicy tests).
    final lifecycleObserver = _WledPollLifecycleObserver((appState) {
      final bg = appState == AppLifecycleState.paused ||
          appState == AppLifecycleState.hidden ||
          appState == AppLifecycleState.detached;
      if (bg == _appBackgrounded) return;
      _appBackgrounded = bg;
      if (!bg) {
        // Resumed: refresh immediately, then return to fast cadence.
        unawaited(_pollOnce());
      }
      _scheduleNextPoll();
    });
    try {
      WidgetsBinding.instance.addObserver(lifecycleObserver);
    } catch (_) {
      // No binding (unit test) — lifecycle backoff is inert here.
    }
    // Controller-defaults self-heal: on each NEW controller connect, remediate
    // the silent schedule-killers clock-health detects (failed NTP host, UTC
    // tz, 0,0 coords) plus the color-gamma standard — heal-only-broken, one
    // evaluation per connect, surgical POSTs. Fire-and-forget; failures retry
    // on the next connect. The endpoint guard in [shouldHealOnConnect] keeps
    // this to once per controller, so the frequent wledRepositoryProvider
    // rebuilds (connectivity/profile churn, each a fresh repo for the same
    // endpoint) don't re-fire the evaluation.
    ref.listen<WledRepository?>(wledRepositoryProvider, (prev, next) {
      if (shouldHealOnConnect(prev, next)) {
        unawaited(ref.read(controllerDefaultsHealerProvider)());
      }
    }, fireImmediately: true);
    // Gamma watchdog: the connect heal above fires once per connect, so a
    // mid-session device-side gamma revert would persist until reconnect. This
    // re-asserts gamma on a low-frequency (≥60s) readback-gated cadence — a
    // healthy board incurs zero cfg writes (every tick is a GET that skips),
    // and a real revert costs exactly one corrective write. LAN-only; ticks
    // no-op off-LAN.
    final gammaWatchdog = ref.read(gammaWatchdogProvider);
    _gammaWatchdog = gammaWatchdog;
    gammaWatchdog.start();
    _startPolling();
    ref.onDispose(() {
      _disposed = true;
      try {
        WidgetsBinding.instance.removeObserver(lifecycleObserver);
      } catch (_) {}
      _poller?.cancel();
      _poller = null;
      _gammaWatchdog?.stop();
      _gammaWatchdog = null;
    });
    return s;
  }

  void _startPolling() {
    _poller?.cancel();
    // Cold-start hydration: fire one immediate fetch so the dashboard doesn't
    // sit on WledStateModel.initial() for a full poll interval (BRIDGE_LATENCY
    // _AUDIT_2026-05 §1). `_pollOnce` is re-entry-safe (`_polling` guard) and
    // null-repo-safe; on null repo it returns silently and the scheduled loop
    // retries once the repository resolves.
    unawaited(_pollOnce());
    _scheduleNextPoll();
  }

  /// Self-scheduling background poll (replaces the old fixed Timer.periodic).
  ///
  /// One-shot timer that reschedules itself after every tick, with the
  /// interval computed by [PollCadencePolicy] — so the cadence adapts to
  /// app-background state and to consecutive-failure backoff. This is the
  /// SINGLE getState stream to the bridge: the previous separate 10s reconnect
  /// timer (unguarded, ran concurrently with this poller, doubling load on an
  /// already-struggling bridge) has been removed. This poller never stops on
  /// its own, so it also owns recovery detection.
  void _scheduleNextPoll() {
    if (_disposed) return;
    _poller?.cancel();
    final interval = PollCadencePolicy.intervalFor(
      isRemote: ref.read(isRemoteModeProvider),
      backgrounded: _appBackgrounded,
      consecutiveFailures: _consecutiveRemoteFailures,
      downgradeThreshold: _maxRemoteFailuresBeforeDowngrade,
    );
    _poller = Timer(interval, () async {
      await _runPollTick();
      _scheduleNextPoll();
    });
  }

  /// One background poll attempt. Preserves the original periodic-callback
  /// semantics — in-flight + posting guards, remote-failure counting, the
  /// 3-strike offline downgrade, and the one-shot RGBW query — only the
  /// scheduling moved out into [_scheduleNextPoll].
  Future<void> _runPollTick() async {
    final service = ref.read(wledRepositoryProvider);
    if (service == null) return;
    if (_posting) return; // avoid fighting with user updates
    // In-flight guard: in remote mode CloudRelayRepository.getState() can take
    // up to 45s. Skipping while one is pending prevents the poll pile-up that
    // floods the bridge's serial queue — caps in-flight depth at 1.
    if (_polling) {
      debugPrint('🔍 BridgeRouter: poll skipped (previous in-flight)');
      return;
    }
    _polling = true;
    try {
      // Capture the state-apply token BEFORE dispatch. If an optimistic setter
      // advances the counter while this getState is in flight (the #87b race —
      // worst case a remote getState pending up to 45s), the commit below
      // suppresses the stale device-echoed visual fields.
      final tokenAtDispatch = _stateApplySeq;
      final data = await service.getState();
      // The container can tear down during the up-to-45s remote getState above.
      // Bail before any ref.read / state mutation so a post-dispose write can't
      // throw "Bad state: ... after dispose". The finally only touches the
      // _polling bool (safe post-dispose).
      if (_disposed) return;
      final isRemote = ref.read(isRemoteModeProvider);
      if (data == null) {
        if (isRemote) {
          _consecutiveRemoteFailures++;
          // Fix D: defer state.connected flip until threshold reached in
          // remote mode. A single null/timeout poll is normal during bridge
          // queue spikes and shouldn't trigger the disconnected indicator.
          // The same threshold gates both the dot and bridgeReachableProvider
          // so they flip together. Backoff (PollCadencePolicy) only engages
          // AFTER this threshold, so the indicator still trips on time.
          if (_consecutiveRemoteFailures >= _maxRemoteFailuresBeforeDowngrade) {
            if (state.connected) {
              state = state.copyWith(connected: false);
            }
            ref.read(bridgeReachableProvider.notifier).state = false;
          }
        } else {
          // Local mode: flip immediately as before — LAN HTTP failure is
          // more likely real (no queue layer to absorb transient spikes).
          if (state.connected) {
            state = state.copyWith(connected: false);
          }
          // Repository transitioned remote → local at some point; clear
          // any stacked remote failures so the next remote session starts
          // fresh (Fix D reset semantics).
          _consecutiveRemoteFailures = 0;
        }
        return;
      }
      // Reset the consecutive-failure counter on ANY successful poll — also
      // collapses the failure backoff back to base cadence on the next
      // schedule, and clears the offline indicator.
      _consecutiveRemoteFailures = 0;
      if (isRemote) {
        ref.read(bridgeReachableProvider.notifier).state = true;
      }
      try {
        _applyStateData(data, tokenAtDispatch: tokenAtDispatch);
      } catch (e) {
        debugPrint('WLED parse state error: $e');
      }
    } finally {
      _polling = false;
    }

    // Query RGBW support once after connection
    if (!_infoQueried) {
      _infoQueried = true;
      try {
        final rgbw = await service.supportsRgbw();
        state = state.copyWith(supportsRgbw: rgbw);
      } catch (e) {
        debugPrint('supportsRgbw check failed: $e');
      }
    }
  }

  /// Single immediate state fetch — used right after a command completes so
  /// the UI reflects device-confirmed state without waiting for the next
  /// 1.5s periodic tick. Respects the same `_polling` guard as the periodic
  /// poller to avoid overlapping requests.
  Future<void> _pollOnce() async {
    if (_polling) return;
    final service = ref.read(wledRepositoryProvider);
    if (service == null) return;
    _polling = true;
    try {
      // Token captured before dispatch (see _runPollTick). The settle re-poll
      // from _postUpdate runs AFTER the optimistic write, so it captures the
      // current token and reconciles normally; only polls dispatched before a
      // newer optimistic write are suppressed.
      final tokenAtDispatch = _stateApplySeq;
      final data = await service.getState();
      if (data == null) return;
      try {
        _applyStateData(data, tokenAtDispatch: tokenAtDispatch);
      } catch (e) {
        debugPrint('WLED parse state error (pollOnce): $e');
      }
    } catch (e) {
      debugPrint('WLED pollOnce failed: $e');
    } finally {
      _polling = false;
    }
  }

  /// Parse a full /json/state response and update all state fields.
  /// Used by both polling and refreshConnection to avoid duplication.
  void _applyStateData(Map<String, dynamic> data, {int? tokenAtDispatch}) {
    final prevPresetId = state.presetId;
    final prevEffectId = state.effectId;
    // Within the post-apply window, polled writes to fields the local apply
    // just owned are suppressed so the dashboard preview reflects the
    // as-sent payload instead of snapping to the device's (lossy) echo.
    // Non-visual fields (paletteId, presetId, reverse, connected) update
    // either way — external state changes still surface.
    //
    // Two independent suppression conditions, OR'd:
    //   1. Time window (_isPollOverwriteSuppressed) — covers the apply-path
    //      lossy-echo race (pattern/effect/grp/spc reduced by /json/state).
    //   2. Sequence token (#87b) — covers the optimistic-setter race: a poll
    //      whose getState was dispatched BEFORE the latest optimistic write
    //      (togglePower/setBrightness/setSpeed/setColor/setWarmWhite) carries a
    //      stale tokenAtDispatch and must not snap the UI back to pre-tap state.
    //      A null token (e.g. the test seam) skips this check.
    final suppressVisual = _isPollOverwriteSuppressed() ||
        (tokenAtDispatch != null && tokenAtDispatch != _stateApplySeq);
    final isOn = (data['on'] as bool?) ?? (data['bri'] != null ? (data['bri'] as int) > 0 : state.isOn);
    final bri = (data['bri'] as int?) ?? state.brightness;
    int speed = state.speed;
    int intensity = state.intensity;

    // Parse active preset ID from WLED state (0 = no preset active)
    final ps = (data['ps'] is num) ? (data['ps'] as num).toInt() : state.presetId;

    // WLED 'seg' in /json/state can be either a List or a single Map depending on build.
    final dynamic segAny = data['seg'];
    Map<dynamic, dynamic>? firstSeg;
    if (segAny is List && segAny.isNotEmpty) {
      final s0 = segAny.first;
      if (s0 is Map) firstSeg = s0;
    } else if (segAny is Map) {
      firstSeg = segAny;
    }

    int effectId = state.effectId;
    int paletteId = state.paletteId;
    bool reverse = state.reverse;
    int colorGroupSize = state.colorGroupSize;
    int spacing = state.spacing;

    if (firstSeg != null) {
      final sx = firstSeg['sx'];
      if (sx is int) speed = sx;

      final ix = firstSeg['ix'];
      if (ix is int) intensity = ix;

      final fx = firstSeg['fx'];
      if (fx is int) effectId = fx;

      final pal = firstSeg['pal'];
      if (pal is int) paletteId = pal;

      final rev = firstSeg['rev'];
      if (rev is bool) reverse = rev;

      // WLED grouping/spacing for spaced patterns (e.g. "1 On 2 Off").
      // Without parsing these, the home dashboard preview falls back to
      // "all on" defaults even though the device is showing the spacing.
      final grp = firstSeg['grp'];
      if (grp is int) colorGroupSize = grp.clamp(1, 64);

      final spc = firstSeg['spc'];
      if (spc is int) spacing = spc.clamp(0, 64);

      final cols = firstSeg['col'];
      if (cols is List && cols.isNotEmpty && cols.first is List) {
        final List<Color> colorSequence = [];
        Color? primaryColor;
        int ww = state.warmWhite;

        // Solid mode (fx=0) only uses col[0]; col[1]/col[2] in solid are
        // residual values from prior writes (audit 2026-05-29). Take just
        // the primary slot so the preview and the persisted-label
        // fingerprint stay aligned with what the device is actually
        // rendering. Non-solid effects can legitimately use multi-slot
        // colors, so they parse all entries as before.
        final Iterable<dynamic> colsToParse =
            effectId == 0 ? cols.take(1) : cols;

        for (final c in colsToParse) {
          if (c is List && c.length >= 3) {
            final rr = (c[0] as num).toInt().clamp(0, 255);
            final gg = (c[1] as num).toInt().clamp(0, 255);
            final bb = (c[2] as num).toInt().clamp(0, 255);

            if (rr > 0 || gg > 0 || bb > 0) {
              colorSequence.add(Color.fromARGB(255, rr, gg, bb));
            }

            if (primaryColor == null) {
              primaryColor = Color.fromARGB(255, rr, gg, bb);
              if (c.length >= 4) {
                ww = (c[3] as num).toInt().clamp(0, 255);
              }
            }
          }
        }

        if (primaryColor != null && !suppressVisual) {
          state = state.copyWith(
            color: primaryColor,
            warmWhite: ww,
            colorSequence: colorSequence,
          );
        }
      }
    }

    if (suppressVisual) {
      // Visual fields owned by [applyLocalPreview] (isOn, brightness, speed,
      // intensity, effectId, colorGroupSize, spacing, color, colorSequence)
      // stay at their just-applied values. Non-visual fields still update.
      state = state.copyWith(
        paletteId: paletteId,
        presetId: ps,
        reverse: reverse,
        connected: true,
      );
    } else {
      state = state.copyWith(
        isOn: isOn,
        brightness: bri,
        speed: speed,
        intensity: intensity,
        effectId: effectId,
        paletteId: paletteId,
        presetId: ps,
        reverse: reverse,
        colorGroupSize: colorGroupSize,
        spacing: spacing,
        connected: true,
      );
    }

    // Mark that we have received a live fetch
    ref.read(wledStateFreshProvider.notifier).state = true;

    // First-poll cold-start is handled by
    // activePresetLabelProvider.reconcileWithDeviceState in
    // app_providers.dart, gated by [_hasReconciledOnStartup] below. This
    // resolver handles steady-state drift only — when the device's effect
    // or preset changes after [_hasPolledOnce] is true without a
    // corresponding user-driven label write within the 3-second race-guard
    // window. On the first poll all three branches are skipped so
    // reconcile owns the label outcome and the persisted fingerprint
    // controls whether a previously-set label is restored.
    if (_hasPolledOnce) {
      // Preset slot changed to a new non-zero value → resolve the
      // device-side preset name and write it via setLabelWithFingerprint.
      // Race-guard inside [_resolvePresetName] protects against a
      // user-driven label write landing while fetchPresetNames is in flight.
      if (ps > 0 && ps != prevPresetId) {
        _resolvePresetName(ps);
      }

      // Preset slot dropped to 0. Use the custom effect name when present
      // (Lumina-set), otherwise clear so the dashboard falls through to the
      // P3 effect-name display.
      if (ps <= 0 && prevPresetId > 0) {
        try {
          final customName = state.customEffectName;
          if (customName != null && customName.isNotEmpty) {
            // `state` here is the Notifier's WledStateModel (just updated by
            // the surrounding _applyStateData call), so we can fingerprint
            // against it directly rather than re-reading wledStateProvider.
            ref
                .read(activePresetLabelProvider.notifier)
                .setLabelWithFingerprint(customName, state);
          } else {
            ref.read(activePresetLabelProvider.notifier).clear();
          }
        } catch (e) {
          debugPrint('Error in WledNotifier clearing preset label: $e');
        }
      }

      // Effect drifted on-device without a matching preset change (manual
      // WLED web-UI tap, autopilot fired, wall switch loaded a different
      // scene, etc.). The persisted Lumina label is no longer truthful —
      // clear it so the dashboard falls through to the live effect name.
      // The 3-second race guard prevents this from clobbering a label the
      // user just set when the device's response races ahead of the
      // optimistic state update.
      if (ps == prevPresetId && effectId != prevEffectId) {
        try {
          final notifier = ref.read(activePresetLabelProvider.notifier);
          final lastSet = notifier.labelUserSetAt;
          final recentUserWrite = lastSet != null &&
              DateTime.now().difference(lastSet).inSeconds < 3;
          if (!recentUserWrite) {
            debugPrint(
                '🏷️ Effect drift detected (fx $prevEffectId → $effectId, ps unchanged at $ps), clearing stale label');
            notifier.clear();
          } else {
            debugPrint(
                '🏷️ Effect drift detected (fx $prevEffectId → $effectId), '
                'but recent user write ${DateTime.now().difference(lastSet).inMilliseconds}ms ago — label preserved');
          }
        } catch (e) {
          debugPrint('Error in WledNotifier drift clear: $e');
        }
      }
    }

    // One-shot cold-start reconciliation of any persisted Now Playing
    // label intent against the freshly-parsed device state. Fires on the
    // first successful poll after notifier construction; subsequent polls
    // are no-ops because the notifier's escrow has been emptied. See
    // ActivePresetLabelNotifier.reconcileWithDeviceState for the
    // fingerprint-matching logic.
    if (!_hasReconciledOnStartup) {
      _hasReconciledOnStartup = true;
      try {
        ref
            .read(activePresetLabelProvider.notifier)
            .reconcileWithDeviceState(state);
      } catch (e) {
        debugPrint('🏷️ Reconcile on startup failed: $e');
      }
    }

    // Flip the steady-state gate ONLY after the cold-start reconciler has
    // run on this poll. The drift branches above check this flag at the top
    // of the next poll so they don't see the first poll's effectId/ps
    // values as "drift from the initial WledStateModel.initial() zeros".
    _hasPolledOnce = true;
  }

  /// Test-only entry point that directly drives the polling parse + drift
  /// handlers without going through the periodic Timer. Tests can simulate
  /// a sequence of polls by calling this with successive state maps.
  @visibleForTesting
  void applyStateDataForTest(Map<String, dynamic> data) {
    _applyStateData(data);
  }

  @visibleForTesting
  bool get hasPolledOnceForTest => _hasPolledOnce;

  @visibleForTesting
  bool get hasReconciledOnStartupForTest => _hasReconciledOnStartup;

  // ── Poll-throttle test hooks (cut bridge backpressure) ──────────────
  @visibleForTesting
  Future<void> debugPollOnce() => _pollOnce();

  @visibleForTesting
  Future<void> debugRunPollTick() => _runPollTick();

  @visibleForTesting
  bool get debugIsPolling => _polling;

  @visibleForTesting
  int get debugConsecutiveFailures => _consecutiveRemoteFailures;

  @visibleForTesting
  set debugBackgrounded(bool v) => _appBackgrounded = v;

  /// The interval the next scheduled poll would use, given current failure /
  /// background state. Mirrors what [_scheduleNextPoll] reads.
  @visibleForTesting
  Duration debugNextPollInterval() => PollCadencePolicy.intervalFor(
        isRemote: ref.read(isRemoteModeProvider),
        backgrounded: _appBackgrounded,
        consecutiveFailures: _consecutiveRemoteFailures,
        downgradeThreshold: _maxRemoteFailuresBeforeDowngrade,
      );

  /// Fetches preset names from the WLED controller and sets the active label.
  /// If the requested preset isn't in the cached map (e.g. it was added
  /// after we first fetched), drop the cache and retry once.
  ///
  /// Concurrency: every call captures its own seq at entry. After the awaited
  /// HTTP returns, we abort if a newer call has started OR if the label was
  /// written within the last 3 s — that window covers the case where the user
  /// taps a pattern card while a stale resolution is still in flight.
  Future<void> _resolvePresetName(int presetId) async {
    final service = ref.read(wledRepositoryProvider);
    if (service == null) return;

    final seq = ++_resolveSeq;

    try {
      var presetNames = await service.fetchPresetNames();
      var name = presetNames[presetId];
      if (name == null || name.isEmpty) {
        service.invalidatePresetCache();
        presetNames = await service.fetchPresetNames();
        name = presetNames[presetId];
      }
      if (name != null && name.isNotEmpty) {
        // Guard 1: a newer resolution has started — drop this stale write.
        if (seq != _resolveSeq) {
          debugPrint('🏷️ Preset $presetId → "$name" superseded (seq=$seq, latest=$_resolveSeq)');
          return;
        }
        // Guard 2: the label was just set (e.g. user tapped a pattern card)
        // — don't clobber a fresh user-driven write with a stale device ps.
        final notifier = ref.read(activePresetLabelProvider.notifier);
        final lastSet = notifier.labelUserSetAt;
        if (lastSet != null &&
            DateTime.now().difference(lastSet).inSeconds < 3) {
          debugPrint('🏷️ Preset $presetId → "$name" skipped (label set ${DateTime.now().difference(lastSet).inMilliseconds}ms ago)');
          return;
        }
        // `state` here is the Notifier's WledStateModel; passing it directly
        // avoids a second provider read and ensures the fingerprint reflects
        // exactly the state that this resolver is naming.
        notifier.setLabelWithFingerprint(name, state);
        debugPrint('🏷️ Resolved WLED preset $presetId → "$name"');
      }
    } catch (e) {
      debugPrint('🏷️ Preset name lookup failed for $presetId: $e');
    }
  }

  /// Force refresh connection state - call when app resumes from background
  Future<void> refreshConnection() async {
    debugPrint('🔄 WledNotifier: Refreshing connection...');
    // Unblock the poller/poster in case a Future hung across the suspend.
    // Without this, a stuck flag would cause every subsequent 1.5s tick to
    // return early and the connection would appear permanently lost.
    _polling = false;
    _posting = false;
    // Fix D: reset the remote-failure counter on app-resume / explicit
    // reconnect so a successful refresh doesn't inherit stale failures
    // accumulated before the suspend.
    _consecutiveRemoteFailures = 0;
    // Mark state as stale until fresh data arrives
    ref.read(wledStateFreshProvider.notifier).state = false;
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      debugPrint('🔄 WledNotifier: No repository available');
      return;
    }

    // Purge cached device capabilities + preset names and drop any stale
    // connection-level resources so the first request after resume doesn't
    // sit on an iOS-invalidated socket.
    service.reset();

    try {
      // Token captured before dispatch (see _runPollTick).
      final tokenAtDispatch = _stateApplySeq;
      final data = await service.getState();
      if (data != null) {
        debugPrint('🔄 WledNotifier: Connection restored');
        // Full state parse — colors, effect, speed, reverse, etc.
        _applyStateData(data, tokenAtDispatch: tokenAtDispatch);
        // Query RGBW support if not yet done
        if (!_infoQueried) {
          _infoQueried = true;
          try {
            final rgbw = await service.supportsRgbw();
            state = state.copyWith(supportsRgbw: rgbw);
          } catch (e) {
            debugPrint('Error in WledNotifier querying RGBW support: $e');
          }
        }
        // Restart polling to keep state fresh
        _startPolling();
      } else {
        debugPrint('🔄 WledNotifier: Connection failed, starting reconnect timer');
        state = state.copyWith(connected: false);
        _scheduleNextPoll();
      }
    } catch (e) {
      debugPrint('🔄 WledNotifier: Refresh failed: $e');
      state = state.copyWith(connected: false);
      _scheduleNextPoll();
    }
  }

  Future<void> togglePower(bool value, {bool isManualChange = true}) async {
    debugPrint('🔌 togglePower called: $value (manual: $isManualChange)');
    _stateApplySeq++;
    state = state.copyWith(isOn: value);
    // Only send power state - don't include brightness when turning off
    await _postUpdate(on: value, isManualChange: isManualChange);
  }

  /// PER-CHANNEL power (P1-43) — the ADDITIVE seg-scoped counterpart to the
  /// whole-house master [togglePower]. Firmware segment independence is
  /// bench-proven; the app previously had no way to express a per-seg off
  /// (power was master-only). Reads LIVE device state (master + which channels'
  /// segments are on) and force-refreshes the hardware config for fresh bounds,
  /// then emits the policy payload from [buildChannelPowerPayload]. Routes
  /// through applyJson (`/json/state` only — NO cfg writes). Leaves
  /// [togglePower] and its master callers (dashboard circle, voice, Game Day /
  /// Neighborhood resume) untouched.
  Future<void> setChannelPower(int channelId, bool on,
      {bool isManualChange = true}) async {
    debugPrint('🔌 setChannelPower ch$channelId → $on');
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      if (state.connected) state = state.copyWith(connected: false);
      return;
    }

    // 1. LIVE state — master + which channels' segments are currently on.
    //    Never guess from cached UI state (per policy).
    var masterOn = state.isOn;
    final litChannelIds = <int>{};
    try {
      final live = await service.getState();
      if (live != null) {
        masterOn = live['on'] == true;
        final segs = live['seg'];
        if (segs is List) {
          for (final s in segs) {
            if (s is Map && s['on'] == true && s['id'] is int) {
              litChannelIds.add(s['id'] as int);
            }
          }
        }
      }
    } catch (_) {
      // Fall back to cached master + empty lit set; better to act than stall.
    }

    // 2. CHANNEL CENSUS (#95: ids only — the builder no longer emits bounds).
    //
    //    The refresh stays. It was introduced for FRESH BOUNDS (P1-42), and
    //    bounds are gone — but it also does a second job that is easy to miss
    //    and expensive to get wrong: it guarantees the census is POPULATED.
    //    Case 3 (master off + channel on) enumerates every channel so master-on
    //    doesn't relight the whole house; with a cold `deviceChannelsProvider`
    //    and no re-fetch, that enumeration collapses to the target alone and
    //    the house comes up lit. Removing the refresh as "bounds-only" caused
    //    exactly that, and the integration test caught it.
    //
    //    Cached list captured first so the enumeration still has ids if the
    //    refresh fails.
    final cachedChannels = ref.read(deviceChannelsProvider);
    List<DeviceChannel> channels;
    try {
      ref.invalidate(deviceHardwareConfigProvider);
      final cfg = await ref
          .read(deviceHardwareConfigProvider.future)
          .timeout(const Duration(seconds: 3), onTimeout: () => null);
      channels = deviceChannelsFromConfig(cfg);
    } catch (_) {
      channels = const [];
    }
    if (channels.isEmpty) channels = cachedChannels;

    // 3. Build the policy payload.
    final payload = buildChannelPowerPayload(
      channelId: channelId,
      on: on,
      masterOn: masterOn,
      litChannelIds: litChannelIds,
      channels: channels,
    );

    // 4. Optimistic master reflection: only the master-writing cases carry a
    //    top-level `on`. Seg-scoped writes leave master as-is.
    if (payload.containsKey('on')) {
      state = state.copyWith(isOn: payload['on'] == true);
    }

    if (isManualChange) {
      try {
        ref.read(scheduleEnforcementServiceProvider).recordManualOverride();
      } catch (e) {
        debugPrint('Could not record manual override: $e');
      }
      SyncWarningDialog.autoPauseIfInSync(ref);
    }

    final ok = await service.applyJson(payload);
    if (!ok) {
      if (state.connected) {
        state = state.copyWith(connected: false);
        _scheduleNextPoll();
      }
      ref.read(wledCommandFailureProvider.notifier).state = WledCommandFailure(
          "Couldn't reach your lights — check your connection");
    }
  }

  Future<void> setBrightness(int bri, {bool isManualChange = true}) async {
    _stateApplySeq++;
    state = state.copyWith(brightness: bri);
    // Always send power state with brightness to ensure WLED interprets correctly
    await _postUpdate(
      on: state.isOn,
      brightness: bri,
      isManualChange: isManualChange,
      transientType: _kTransientBrightness,
    );
  }

  Future<void> setSpeed(int sx, {bool isManualChange = true}) async {
    _stateApplySeq++;
    state = state.copyWith(speed: sx);
    await _postUpdate(
      speed: sx,
      isManualChange: isManualChange,
      transientType: _kTransientSpeed,
    );
  }

  Future<void> setColor(Color color, {bool isManualChange = true}) async {
    _stateApplySeq++;
    state = state.copyWith(color: color);
    // Force W=0 unconditionally so the dedicated white LED never mixes into a
    // picked color. This closes the cold-start pink residual: supportsRgbw
    // defaults false and flips true only after the async /json/info probe, so
    // gating zero-white on it let a desaturated red take the auto-white-
    // extraction branch (W = min(r,g,b)) before the probe resolved → pink.
    // The device LED type (RGBW vs RGB) is itself only known via async probes,
    // so there is no early synchronous signal to gate on — and forcing W=0 is
    // safe for both strip types: on RGBW it's the desired pure-color path
    // (gamma handles accuracy), and on an RGB bus WLED ignores the W channel.
    // Pure dark red (G=B=0) is byte-identical either way (min=0), so it stays
    // unaffected. Intentional white (setWarmWhite) is a separate path and still
    // honors supportsRgbw.
    await _postUpdate(
      color: color,
      forceRgbwZeroWhite: true,
      isManualChange: isManualChange,
      transientType: _kTransientColor,
    );
  }

  Future<void> setWarmWhite(int white, {bool isManualChange = true}) async {
    _stateApplySeq++;
    final clamped = white.clamp(0, 255);
    state = state.copyWith(warmWhite: clamped);
    // Send an update including current color and the updated white channel
    // (same _kTransientColor channel as setColor — both write the col[] array,
    // so they coalesce together latest-wins).
    await _postUpdate(
      color: state.color,
      white: state.supportsRgbw ? clamped : null,
      isManualChange: isManualChange,
      transientType: _kTransientColor,
    );
  }

  /// Sets Lumina pattern metadata (colors, effect name) when a pattern is applied.
  /// This preserves the rich information from Lumina's AI response so it displays
  /// correctly on the home screen even after device polling overwrites raw values.
  void setLuminaPatternMetadata({
    List<Color>? colorSequence,
    List<String>? colorNames,
    String? effectName,
  }) {
    state = state.copyWith(
      colorSequence: colorSequence,
      colorNames: colorNames,
      customEffectName: effectName,
    );
    debugPrint('🎨 Set Lumina pattern metadata: ${colorSequence?.length ?? 0} colors, effect: $effectName');
  }

  /// Applies a pattern to the local preview state without requiring device connection.
  /// This allows users to see the roofline LED preview on the house image even when
  /// the WLED controller is offline. The next successful device poll will sync with
  /// actual device state.
  ///
  /// [colorGroupSize] and [spacing] map to WLED `grp`/`spc`. Pass them when
  /// applying spacing patterns (e.g. "1 On 2 Off") so the home dashboard
  /// roofline preview matches the device. They reset to defaults (1/0) when
  /// not provided so non-spaced patterns clear any previous spacing.
  ///
  /// Also arms the poll-overwrite suppression window so the next ~2s of
  /// polls don't clobber these just-applied visual fields with the device's
  /// (lossy) echo of the same payload. See [_isPollOverwriteSuppressed].
  void applyLocalPreview({
    required List<Color> colors,
    required int effectId,
    int speed = 128,
    int intensity = 128,
    int brightness = 255,
    String? effectName,
    int colorGroupSize = 1,
    int spacing = 0,
  }) {
    state = state.copyWith(
      isOn: true,
      colorSequence: colors,
      color: colors.isNotEmpty ? colors.first : Colors.white,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      customEffectName: effectName,
      colorGroupSize: colorGroupSize,
      spacing: spacing,
    );
    _lastLocalApplyAt = DateTime.now();
    debugPrint('🎨 Applied local preview: ${colors.length} colors, effect: $effectName, grp=$colorGroupSize spc=$spacing (offline OK)');
  }

  /// Single chokepoint every user-initiated apply path routes through.
  ///
  /// Writes the as-sent payload to [wledStateProvider] (via
  /// [applyLocalPreview]) so the dashboard hero stays aligned with what
  /// was just sent to the device. Also arms the poll-overwrite
  /// suppression window via [applyLocalPreview]'s timestamp side effect.
  void applyPreviewSync({
    required List<Color> colors,
    required int effectId,
    String? effectName,
    int speed = 128,
    int intensity = 128,
    int brightness = 255,
    int colorGroupSize = 1,
    int spacing = 0,
  }) {
    applyLocalPreview(
      colors: colors,
      effectId: effectId,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
      effectName: effectName,
      colorGroupSize: colorGroupSize,
      spacing: spacing,
    );
  }

  /// Persistent-pattern apply chokepoint for non-user writers (schedule,
  /// autopilot, scene, geofence, Game Day, AI design, etc.).
  ///
  /// Wraps [WledRepository.applyJson] and on success fans the change out to
  /// the same UI surfaces the cluster fix already paired manually at each
  /// call site:
  ///
  ///   • [wledStateProvider] via [applyPreviewSync]
  ///     (visual cache + dashboard hero)
  ///   • [activePresetLabelProvider] via [setLabelWithFingerprint]
  ///     (Now Playing chip) — ONLY when [labelHint] is non-null
  ///
  /// [labelHint] semantics — important:
  ///   • Non-null  → PERSISTENT pattern change (scheduled, autopilot, scene,
  ///     geofence, manually applied). Updates label.
  ///   • null      → TRANSIENT effect (score-celebration flash, override-
  ///     restore returning to prior state). Device write + visual cache
  ///     update happens but Now Playing stays at whatever persistent
  ///     pattern the user had — the flash does not steal the label.
  ///
  /// Payload extraction is defensive: missing fields fall back to current
  /// state. A `{'on': false}` power-off payload is handled specially —
  /// only [wledStateProvider.isOn] is updated; the label is left alone
  /// (the cluster fix's TurnOff teardown owns the label-clear-on-off
  /// case separately).
  ///
  /// Returns whatever [WledRepository.applyJson] returned. On a write
  /// failure no provider is mutated.
  Future<bool> applyPayloadWithLabel(
    Map<String, dynamic> payload, {
    required String? labelHint,
  }) async {
    final repo = ref.read(wledRepositoryProvider);
    if (repo == null) return false;

    final success = await repo.applyJson(payload);
    if (!success) return false;

    // Power-off short-circuit: don't fan a black-render to the preview hero.
    if (payload['on'] == false) {
      state = state.copyWith(isOn: false);
      if (labelHint != null) {
        ref
            .read(activePresetLabelProvider.notifier)
            .setLabelWithFingerprint(labelHint, state);
      }
      return true;
    }

    final current = state;
    // The DESIGN seg, not seg[0] — applyChannelFilter now emits the #67 full
    // partition, so an apply scoped away from channel 0 puts the exclusion
    // `{id:0, on:false}` first. Reading that as the design blanked the preview.
    final Map<String, dynamic>? firstSeg = firstDesignSeg(payload['seg']);

    final effectId = _asInt(firstSeg?['fx']) ?? current.effectId;
    final speed = _asInt(firstSeg?['sx']) ?? current.speed;
    final intensity = _asInt(firstSeg?['ix']) ?? current.intensity;
    final brightness = _asInt(payload['bri']) ?? current.brightness;

    List<Color> colors;
    final colArr = firstSeg?['col'];
    if (colArr is List && colArr.isNotEmpty) {
      colors = colArr.whereType<List>().take(3).map((c) {
        final r = c.isNotEmpty ? (_asInt(c[0]) ?? 0) : 0;
        final g = c.length > 1 ? (_asInt(c[1]) ?? 0) : 0;
        final b = c.length > 2 ? (_asInt(c[2]) ?? 0) : 0;
        return Color.fromARGB(
          255,
          r.clamp(0, 255),
          g.clamp(0, 255),
          b.clamp(0, 255),
        );
      }).toList();
    } else {
      colors = current.colorSequence.isNotEmpty
          ? current.colorSequence
          : const [Colors.white];
    }

    applyPreviewSync(
      colors: colors,
      effectId: effectId,
      effectName: labelHint,
      speed: speed,
      intensity: intensity,
      brightness: brightness,
    );

    if (labelHint != null) {
      // Fix 3 / Bug A: compose effect + color when the caller's hint
      // matches a vanilla catalog effect name. Custom labels ("Royals
      // Game Day"), unknown effects, and color-ignoring effects
      // (rainbow, palette) pass through unchanged. See composeEffectLabel
      // for the full heuristic.
      final composedLabel = composeEffectLabel(
        labelHint: labelHint,
        effectId: effectId,
        colors: colors
            .map((c) => [c.red, c.green, c.blue, 0])
            .toList(growable: false),
      );
      ref
          .read(activePresetLabelProvider.notifier)
          .setLabelWithFingerprint(composedLabel ?? labelHint, state);
    }

    return true;
  }

  /// Class-1 multi-channel chokepoint. The SINGLE apply path every
  /// aesthetic-command site that builds a RAW broadcast payload routes
  /// through (Current Colors, Lumina AI, Audio, Geofence, Voice, library
  /// Scenes). Mirrors the reference fix in
  /// [applySavedDesign](apply_saved_design.dart:50-63) and
  /// [game_day_apply.dart:88].
  ///
  /// Guarantees, in order:
  ///   1. **U1 gate** — reads [effectiveChannelIdsProvider] (channel selector
  ///      ∩ participation ∩ device buses). Empty → skip-apply, return false.
  ///      Never POST an empty seg array.
  ///   2. **[applyChannelFilter]** (RAW payloads only — see discriminator) —
  ///      rewrites the single template seg into one seg per effective channel
  ///      id, each with explicit `id`/`start`/`stop`/`on:true`. The result is
  ///      multi-seg-with-ids that survives the [expandForParticipation]
  ///      chokepoint via Rule 4, and is **cache-independent** — it does NOT
  ///      depend on the SharedPreferences participation cache being warm
  ///      (dissolving the Class-3 cold-cache dependency for these paths).
  ///   3. **[applyPayloadWithLabel]** — the device write + preview/label
  ///      fan-out (`labelHint` semantics unchanged: non-null = persistent
  ///      Now Playing label; null = transient / caller sets its own label).
  ///
  /// **Double-filter guard (Phase-3).** Only RAW broadcast-intent payloads
  /// (a single template seg with NO explicit `id`) are expanded. An
  /// ALREADY-filtered multi-seg / id-bearing payload (custom scenes, saved
  /// designs, getState snapshots — these reach this method via the Lumina AI
  /// command router's scene path, [lumina_command_router.dart] `_executeScene`)
  /// passes straight through: re-filtering would template off `seg.first` and
  /// flatten per-channel looks to bus-0 (the saved-design trap from the Game
  /// Day fix). This mirrors [expandForParticipation]'s raw-vs-prefiltered
  /// discriminator and keeps the helper idempotent and safe for any caller.
  Future<bool> applyToDevice(
    Map<String, dynamic> payload, {
    required String? labelHint,
  }) async {
    final channels = ref.read(effectiveChannelIdsProvider);
    if (channels.isEmpty) {
      debugPrint('applyToDevice: skip (U1 gate — no effective channels)');
      return false;
    }

    // Discriminator: expand only a single template seg with no explicit id.
    final seg = payload['seg'];
    final isRawBroadcast = seg is List &&
        seg.length == 1 &&
        seg.first is Map &&
        !(seg.first as Map).containsKey('id');

    final outgoing = isRawBroadcast
        ? applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider))
        : payload;
    return applyPayloadWithLabel(outgoing, labelHint: labelHint);
  }

  /// Test-only knob: rewind the poll-suppression timestamp so the next
  /// poll behaves as if the [_kLocalApplyPollSuppressWindow] has expired.
  /// Lets tests verify post-window behavior without sleeping 2 real seconds.
  @visibleForTesting
  void debugSetLastLocalApplyAtForTest(DateTime? at) {
    _lastLocalApplyAt = at;
  }

  /// Clears custom Lumina pattern metadata (e.g., when user manually adjusts pattern).
  /// The next poll will restore device-reported values.
  void clearLuminaPatternMetadata() {
    state = state.copyWith(
      colorNames: [],
      clearCustomEffectName: true,
    );
    debugPrint('🗑️ Cleared Lumina pattern metadata');
  }

  Future<void> _postUpdate({
    bool? on,
    int? brightness,
    int? speed,
    Color? color,
    int? white,
    bool? forceRgbwZeroWhite,
    bool isManualChange = false,
    String? transientType,
  }) async {
    // Per-transient-type latest-wins coalescing.
    //
    // When a same-type write is already in flight, replace the pending
    // slot and return. The in-flight write's `finally` block drains the
    // slot via a recursive call, so the LATEST value always lands —
    // earlier intermediate values are dropped on the floor. Discrete
    // commands (power, pattern apply) pass `transientType: null` and
    // bypass this gate so every tap executes.
    if (transientType != null && _transientInFlight.contains(transientType)) {
      _transientPending[transientType] = _PendingPost(
        on: on,
        brightness: brightness,
        speed: speed,
        color: color,
        white: white,
        forceRgbwZeroWhite: forceRgbwZeroWhite,
        isManualChange: isManualChange,
      );
      return;
    }

    // If DDP streaming is active, avoid HTTP state updates to prevent conflicts.
    final ddpStreaming = ref.read(ddpStreamingProvider);
    if (ddpStreaming) {
      debugPrint('Skipping HTTP update because DDP streaming is active');
      return;
    }
    final service = ref.read(wledRepositoryProvider);
    if (service == null) {
      // Surface the reason so the UI can react (red dot + message).
      final connStatus = ref.read(wledConnectivityStatusProvider).maybeWhen(
        data: (s) => s,
        orElse: () => null,
      );
      if (connStatus == ConnectivityStatus.remote) {
        debugPrint('❌ Command blocked: on remote network but remote access '
            'not configured or userId/controllerId unavailable');
      } else if (connStatus == null) {
        debugPrint('⏳ Command blocked: connectivity check still in progress');
      } else {
        debugPrint('❌ Command blocked: no repository (offline or no device selected)');
      }
      // Mark disconnected so the UI shows the red dot immediately
      // rather than waiting for a poll timeout.
      if (state.connected) {
        state = state.copyWith(connected: false);
      }
      return;
    }

    // Record manual override for schedule enforcement
    if (isManualChange) {
      try {
        ref.read(scheduleEnforcementServiceProvider).recordManualOverride();
      } catch (e) {
        // Ignore errors if enforcement service not available
        debugPrint('Could not record manual override: $e');
      }

      // Auto-pause Neighborhood Sync — user's local action always takes priority.
      // This runs fire-and-forget so it never delays the user's command.
      SyncWarningDialog.autoPauseIfInSync(ref);
    }

    _posting = true;
    if (transientType != null) {
      _transientInFlight.add(transientType);
    }
    bool ok = false;
    try {
      // Check if a channel filter is active (user selected specific channels).
      var effectiveChannels = ref.read(effectiveChannelIdsProvider);

      // Only segment-level props need per-channel targeting. Power/brightness
      // are device-global (top-level write), so they must NOT pay the
      // cold-resolve latency below — a power tap stays instant on a cold/
      // offline device.
      final needsChannels = speed != null || color != null || white != null;

      if (effectiveChannels.isEmpty && needsChannels) {
        // Cold start: device channels derive from the hardware config, which
        // may still be loading (FutureProvider unresolved in the first seconds
        // after launch / device select). Resolve it once — bounded so a slider
        // drag never blocks on a slow/offline config fetch — then re-read.
        // Without this a colour/speed change in that window falls to a bus-0
        // single-seg setState on a multi-bus install (Ellie, Blue Line).
        try {
          await ref
              .read(deviceHardwareConfigProvider.future)
              .timeout(const Duration(seconds: 3), onTimeout: () => null);
          effectiveChannels = ref.read(effectiveChannelIdsProvider);
        } catch (_) {
          // Genuine no-config / fetch error — fall through to setState below.
        }
      }

      if (effectiveChannels.isEmpty) {
        // Still no channel map: device has no resolvable buses. setState sends
        // a top-level GLOBAL write for power/brightness (correct on any
        // device); colour/speed fall to seg 0 — the only segment addressable
        // without a channel map.
        ok = await service.setState(
          on: on,
          brightness: brightness,
          speed: speed,
          color: color,
          white: white,
          forceRgbwZeroWhite: forceRgbwZeroWhite,
        );
      } else {
        // Target ALL effective channels (all segments, or filtered subset).
        final Map<String, dynamic> payload = {};
        // Device-level properties always apply globally.
        if (on != null) payload['on'] = on;
        if (brightness != null) payload['bri'] = brightness.clamp(0, 255);

        // Segment-specific properties go to each effective channel.
        final Map<String, dynamic> segTemplate = {};
        if (speed != null) segTemplate['sx'] = speed.clamp(0, 255);
        if (color != null || white != null) {
          final rgbw = rgbToRgbw(
            color?.red ?? 0,
            color?.green ?? 0,
            color?.blue ?? 0,
            explicitWhite: white,
            forceZeroWhite: forceRgbwZeroWhite == true,
          );
          segTemplate['col'] = [rgbw];
        }

        if (segTemplate.isNotEmpty) {
          final deviceCh = ref.read(deviceChannelsProvider);
          payload['seg'] = effectiveChannels.map((id) {
            // 'on': true per seg — a colour/speed tweak must relight a
            // targeted channel that is currently off (the channel-2-dark
            // class; mirrors applyChannelFilter). Scoped to the channels
            // being targeted; non-targeted channels are omitted, not touched.
            final s = <String, dynamic>{'id': id, ...segTemplate, 'on': true};
            for (final ch in deviceCh) {
              if (ch.id == id) {
                s['start'] = ch.start;
                s['stop'] = ch.stop;
                break;
              }
            }
            return s;
          }).toList();
        }

        ok = await service.applyJson(payload);
      }

      if (!ok && state.connected) {
        state = state.copyWith(connected: false);
        _scheduleNextPoll();
      }
      if (!ok) {
        // Surface failure so the dashboard can show a non-blocking snackbar.
        // Optimistic state updates above are preserved — this only notifies.
        ref.read(wledCommandFailureProvider.notifier).state =
            WledCommandFailure(
                "Couldn't reach your lights — check your connection");
      }
      // Wait before allowing poller to read back state.
      // In remote mode the bridge processes commands sequentially, so give it
      // extra time to finish before we queue another getState poll.
      final isRemote = ref.read(isRemoteModeProvider);
      await Future.delayed(Duration(milliseconds: isRemote ? 3000 : 150));
    } finally {
      _posting = false;
      if (transientType != null) {
        _transientInFlight.remove(transientType);
        // Drain the latest-wins slot: any same-type writes that arrived
        // during this in-flight period collapsed to one pending args set.
        // Replay them now so the most recent value lands on the device.
        // Runs in the finally so it executes even if the network write
        // threw — a transient gate must never deadlock.
        final pending = _transientPending.remove(transientType);
        if (pending != null) {
          unawaited(_postUpdate(
            on: pending.on,
            brightness: pending.brightness,
            speed: pending.speed,
            color: pending.color,
            white: pending.white,
            forceRgbwZeroWhite: pending.forceRgbwZeroWhite,
            isManualChange: pending.isManualChange,
            transientType: transientType,
          ));
        }
      }
    }

    // Trigger an immediate single poll so the UI reflects device-confirmed
    // state without waiting for the next 1.5s periodic tick.
    if (ok) {
      unawaited(_pollOnce());
    }
  }

}

final wledStateProvider = NotifierProvider<WledNotifier, WledStateModel>(WledNotifier.new);

/// Whether the WLED state has been fetched live from the controller at least
/// once since launch or the most recent app resume. Reset to false on resume
/// so the dashboard can show a "Last Known State" indicator until fresh data
/// arrives.
final wledStateFreshProvider = StateProvider<bool>((ref) => false);

/// Surfaces the most recent failed WLED command so the dashboard can show
/// a non-blocking snackbar. Each set carries a timestamp so consecutive
/// failures with identical messages still notify (StateProvider deduplicates
/// on equality, and the timestamp is part of equality).
class WledCommandFailure {
  final String message;
  final DateTime at;
  WledCommandFailure(this.message) : at = DateTime.now();
}

final wledCommandFailureProvider =
    StateProvider<WledCommandFailure?>((ref) => null);
