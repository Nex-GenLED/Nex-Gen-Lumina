import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart' show rgbToRgbw;
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:shared_preferences/shared_preferences.dart';

const String _kGeofencePromptShownKey = 'geofence_location_prompt_shown';
const String _kGeofenceDeniedExplKey = 'geofence_denied_explanation_shown';

class GeofenceConfig {
  final double centerLat;
  final double centerLng;
  final double radiusMeters;
  final String actionName;
  final bool onlyAtNight;
  const GeofenceConfig({required this.centerLat, required this.centerLng, required this.radiusMeters, required this.actionName, required this.onlyAtNight});

  factory GeofenceConfig.fromMap(Map<String, dynamic> m) => GeofenceConfig(
        centerLat: (m['center_lat'] as num).toDouble(),
        centerLng: (m['center_lng'] as num).toDouble(),
        radiusMeters: ((m['radius_m'] as num?) ?? 300).toDouble(),
        actionName: (m['action_name'] ?? '') as String,
        onlyAtNight: (m['only_at_night'] as bool?) ?? false,
      );
}

class GeofenceState {
  final bool enabled;
  final bool isInside;
  final double? lastDistance;
  const GeofenceState({required this.enabled, required this.isInside, this.lastDistance});

  GeofenceState copyWith({bool? enabled, bool? isInside, double? lastDistance}) => GeofenceState(
        enabled: enabled ?? this.enabled,
        isInside: isInside ?? this.isInside,
        lastDistance: lastDistance ?? this.lastDistance,
      );
  static GeofenceState initial() => const GeofenceState(enabled: false, isInside: false);
}

class GeofenceMonitor extends Notifier<GeofenceState> {
  StreamSubscription<Position>? _posSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _cfgSub;
  GeofenceConfig? _config;
  bool _started = false;

  /// Debounced re-subscribe timer for the config stream. Set when the config
  /// listener surfaces a stream-level error (#52 dead-listener class); fires a
  /// fresh subscription so live config edits keep applying after a transient
  /// Firestore error instead of going dead until app relaunch.
  Timer? _cfgResubscribeTimer;

  /// Factory for the config-doc snapshot stream. In production it returns
  /// `docRef.snapshots()`; a fresh stream per call so a re-subscribe gets a
  /// new listener. Held as a field (rather than re-reading auth) so the #52
  /// re-subscribe path can rebuild the listener, and so a test can inject a
  /// controllable stream.
  Stream<DocumentSnapshot<Map<String, dynamic>>> Function()? _configStreamFactory;

  /// Debounce before re-subscribing the config stream after an error. Mirrors
  /// the engine's 2s debounce (e005a02) so an error storm doesn't hot-loop new
  /// listeners. Overridable in tests.
  @visibleForTesting
  Duration configResubscribeDelay = const Duration(seconds: 2);

  /// Test-only view of the parsed config, to assert that live edits keep
  /// applying across a stream error / re-subscribe.
  @visibleForTesting
  GeofenceConfig? get configForTest => _config;

  @override
  GeofenceState build() {
    // Lazy start; app can call start() explicitly after permissions.
    ref.onDispose(() {
      _posSub?.cancel();
      _cfgSub?.cancel();
      _cfgResubscribeTimer?.cancel();
    });
    return GeofenceState.initial();
  }

  /// Returns true if location permission is sufficient to start monitoring.
  /// Does NOT prompt — use [ensurePermissionsWithDialog] for interactive requests.
  Future<bool> hasLocationPermission() async {
    final perm = await Geolocator.checkPermission();
    return perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse;
  }

  /// Shows the "Always Allow" upgrade dialog, but only when contextually
  /// appropriate (user is enabling geofencing). Respects prior responses:
  ///  - Already "always" → silent success
  ///  - Already "whileInUse" → ask once to upgrade, accept if declined
  ///  - "denied" → one-time explanation, then open settings
  ///  - "deniedForever" → never prompt again
  Future<void> ensurePermissionsWithDialog(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    LocationPermission perm = await Geolocator.checkPermission();

    // Already have background location — nothing to do
    if (perm == LocationPermission.always) return;

    // Permanently denied — never prompt, user must go to Settings manually
    if (perm == LocationPermission.deniedForever) return;

    // "While in use" — ask once to upgrade to Always for geofencing
    if (perm == LocationPermission.whileInUse) {
      final alreadyAsked = prefs.getBool(_kGeofencePromptShownKey) ?? false;
      if (alreadyAsked) return; // Already asked once, accept "while in use"

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Enable Background Location'),
          content: const Text(
            'To trigger "Welcome Home" reliably, we need background '
            'location access so your arrival is detected even when '
            'the app is closed.\n\n'
            'You can change this later in Settings.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Not now'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );

      await prefs.setBool(_kGeofencePromptShownKey, true);
      if (confirmed != true) return;

      // On iOS, requesting again after whileInUse escalates to Always
      perm = await Geolocator.requestPermission();
      return;
    }

    // Permission is "denied" (not yet determined or previously denied)
    if (perm == LocationPermission.denied) {
      final alreadyExplained =
          prefs.getBool(_kGeofenceDeniedExplKey) ?? false;
      if (alreadyExplained) return; // Only explain once per denial

      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Location Access Needed'),
          content: const Text(
            'Geofence features like "Welcome Home" need location '
            'access to detect when you arrive. Grant location '
            'permission to enable this feature.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Skip'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Grant Access'),
            ),
          ],
        ),
      );

      await prefs.setBool(_kGeofenceDeniedExplKey, true);
      if (confirmed != true) return;

      perm = await Geolocator.requestPermission();
    }
  }

  /// Resets prompt flags so the dialog can be shown again (e.g. after
  /// the user revokes permission and re-enables geofencing).
  static Future<void> resetPromptFlags() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kGeofencePromptShownKey);
    await prefs.remove(_kGeofenceDeniedExplKey);
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await NotificationsService.init();
    // Subscribe to user config
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('geofences').doc('welcome_home');
    _configStreamFactory = () => docRef.snapshots();
    _subscribeConfig();

    // Position stream
    final settings = const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 25);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (e) => debugPrint('Position stream error: $e'));
  }

  /// Subscribes (or re-subscribes) to the geofence config doc.
  ///
  /// The CONFIG stream previously had no `onError` — only the inner parse was
  /// guarded — so one stream-level error (a transient Firestore disconnect /
  /// permission blip) killed the subscription permanently (#52 dead-listener
  /// class). Live enable/disable + radius edits then stopped applying and
  /// automation ran on stale config until app relaunch. Mirrors the position
  /// stream's `onError` (above) and the engine's debounced re-subscribe
  /// (e005a02): on a stream error, log + schedule a re-subscribe so the
  /// listener survives.
  void _subscribeConfig() {
    final factory = _configStreamFactory;
    if (factory == null) return;
    _cfgSub?.cancel();
    _cfgSub = factory().listen(
      _onConfigSnapshot,
      onError: (e) {
        debugPrint('Geofence cfg stream error: $e — scheduling re-subscribe');
        _scheduleConfigResubscribe();
      },
    );
  }

  /// Handles one config-doc emission. Unchanged from the original inline
  /// listener body — the parse guard still swallows a bad doc so a single
  /// malformed config can't take down the stream.
  void _onConfigSnapshot(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!snap.exists) {
      state = state.copyWith(enabled: false);
      return;
    }
    try {
      final data = snap.data();
      if (data == null) return;
      _config = GeofenceConfig.fromMap(data);
      state = state.copyWith(enabled: true);
    } catch (e) {
      debugPrint('Geofence cfg parse error: $e');
    }
  }

  /// Debounced re-subscribe after a config-stream error, so an error storm
  /// doesn't hot-loop new listeners. Mirrors the #52 fix (e005a02).
  void _scheduleConfigResubscribe() {
    if (!_started) return;
    _cfgResubscribeTimer?.cancel();
    _cfgResubscribeTimer = Timer(configResubscribeDelay, () {
      if (_started) _subscribeConfig();
    });
  }

  /// Test seam: drives the config subscription off an injected stream factory
  /// (re-invoked on every re-subscribe — return a fresh stream each call),
  /// bypassing auth + Firestore so the #52 re-subscribe path is exercisable
  /// without a live backend.
  @visibleForTesting
  void startConfigForTest(
    Stream<DocumentSnapshot<Map<String, dynamic>>> Function() factory,
  ) {
    _started = true;
    _configStreamFactory = factory;
    _subscribeConfig();
  }

  Future<void> stop() async {
    _cfgResubscribeTimer?.cancel();
    _cfgResubscribeTimer = null;
    await _posSub?.cancel();
    await _cfgSub?.cancel();
    _posSub = null;
    _cfgSub = null;
    _configStreamFactory = null;
    _started = false;
    state = state.copyWith(enabled: false);
  }

  Future<void> _onPosition(Position pos) async {
    final cfg = _config;
    if (cfg == null) return;
    final dist = Geolocator.distanceBetween(pos.latitude, pos.longitude, cfg.centerLat, cfg.centerLng);
    final inside = dist <= cfg.radiusMeters;
    final wasInside = state.isInside;
    state = state.copyWith(lastDistance: dist, isInside: inside);

    if (inside && !wasInside) {
      // Enter transition
      if (cfg.onlyAtNight) {
        final sunset = SunUtils.sunsetLocal(cfg.centerLat, cfg.centerLng, DateTime.now());
        if (sunset != null && DateTime.now().isBefore(sunset)) {
          debugPrint('Geofence enter ignored (before sunset)');
          return;
        }
      }
      await _triggerAction(cfg.actionName);
    }
  }

  Future<void> _triggerAction(String actionName) async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) {
        debugPrint('No WLED repository available');
        return;
      }
      final uid = FirebaseAuth.instance.currentUser?.uid;
      Map<String, dynamic>? payload;
      if (uid != null) {
        try {
          final favs = await FirebaseFirestore.instance.collection('users').doc(uid).collection('favorites').where('name', isEqualTo: actionName).limit(1).get();
          if (favs.docs.isNotEmpty) {
            final data = favs.docs.first.data();
            final p = data['payload'];
            if (p is Map<String, dynamic>) payload = p;
          }
        } catch (e) {
          debugPrint('Favorites lookup failed: $e');
        }
      }

      if (payload != null) {
        // Route the geofence-triggered apply through the chokepoint so
        // the dashboard + roofline preview + Now Playing chip all
        // reflect the action that just fired (e.g. "Welcome Home").
        // Bare repo.applyJson would leave Now Playing stale.
        await ref
            .read(wledStateProvider.notifier)
            .applyPayloadWithLabel(payload, labelHint: actionName);
      } else {
        await _applyFallback(actionName, repo);
      }
      await NotificationsService.showWelcomeHome(actionName);
    } catch (e) {
      debugPrint('Trigger action failed: $e');
    }
  }

  Future<void> _applyFallback(String actionName, WledRepository repo) async {
    final lower = actionName.toLowerCase();
    if (lower.contains('turn off')) {
      await repo.setState(on: false); // power off is global — no seg needed
      return;
    }
    if (lower.contains('relax')) {
      await _applyColorFallback(actionName, 180, const Color(0xFFFFD6AA), repo);
      return;
    }
    if (lower.contains('warm')) {
      await _applyColorFallback(actionName, 200, const Color(0xFFFFD6AA), repo);
      return;
    }
    if (lower.contains('party')) {
      // Route through the Class-1 chokepoint so the party scene lights every
      // effective channel, not just bus 0. No per-seg 'id' — applyToDevice
      // fans the template out per effective channel.
      await ref.read(wledStateProvider.notifier).applyToDevice({
        'on': true,
        'bri': 190,
        'seg': [
          {
            'fx': 27,
            'sx': 200,
            'ix': 180,
            'col': [
              [255, 0, 0, 0],
              [0, 255, 0, 0],
              [0, 0, 255, 0]
            ]
          }
        ]
      }, labelHint: actionName);
      return;
    }
    // Default: gentle on
    await _applyColorFallback(actionName, 170, const Color(0xFFCCE7FF), repo);
  }

  /// Welcome-home solid-colour fallback. Routes through the Class-1
  /// channel-aware chokepoint (applyToDevice) so it lights EVERY effective
  /// channel, not just bus 0. If the U1 gate blocks (cold start before the
  /// hardware config loads / no channel map), falls back to the legacy
  /// setState so welcome-home still lights something rather than nothing.
  Future<void> _applyColorFallback(
    String label,
    int bri,
    Color c,
    WledRepository repo,
  ) async {
    final rgbw = rgbToRgbw(c.red, c.green, c.blue);
    final ok = await ref.read(wledStateProvider.notifier).applyToDevice({
      'on': true,
      'bri': bri,
      'seg': [
        {'fx': 0, 'col': [rgbw]},
      ],
    }, labelHint: label);
    if (!ok) {
      await repo.setState(on: true, brightness: bri, color: c);
    }
  }
}

final geofenceMonitorProvider = NotifierProvider<GeofenceMonitor, GeofenceState>(GeofenceMonitor.new);
