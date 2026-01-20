import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/utils/sun_utils.dart';

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

  @override
  GeofenceState build() {
    // Lazy start; app can call start() explicitly after permissions.
    ref.onDispose(() {
      _posSub?.cancel();
      _cfgSub?.cancel();
    });
    return GeofenceState.initial();
  }

  Future<void> ensurePermissionsWithDialog(BuildContext context) async {
    // Explain why we need Always Allow
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Enable Always Allow Location'),
        content: const Text('To trigger "Welcome Home" reliably, we need background location access so your arrival is detected even when the app is closed.'),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text('Not now')),
          FilledButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text('Continue')),
        ],
      ),
    );
    if (confirmed != true) return;

    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.deniedForever) return;
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
    // On iOS, request "Always" by requesting again after whileInUse.
    if (perm == LocationPermission.whileInUse) {
      perm = await Geolocator.requestPermission();
    }
  }

  Future<void> start() async {
    if (_started) return;
    _started = true;
    await NotificationsService.init();
    // Subscribe to user config
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final docRef = FirebaseFirestore.instance.collection('users').doc(uid).collection('geofences').doc('welcome_home');
    _cfgSub = docRef.snapshots().listen((snap) {
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
    });

    // Position stream
    final settings = const LocationSettings(accuracy: LocationAccuracy.best, distanceFilter: 25);
    _posSub = Geolocator.getPositionStream(locationSettings: settings).listen(_onPosition, onError: (e) => debugPrint('Position stream error: $e'));
  }

  Future<void> stop() async {
    await _posSub?.cancel();
    await _cfgSub?.cancel();
    _posSub = null;
    _cfgSub = null;
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
        await repo.applyJson(payload);
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
      await repo.setState(on: false);
      return;
    }
    if (lower.contains('relax')) {
      await repo.setState(on: true, brightness: 180, color: const Color(0xFFFFD6AA));
      return;
    }
    if (lower.contains('warm')) {
      await repo.setState(on: true, brightness: 200, color: const Color(0xFFFFD6AA));
      return;
    }
    if (lower.contains('party')) {
      await repo.applyJson({
        'on': true,
        'bri': 190,
        'seg': [
          {
            'id': 0,
            'fx': 27,
            'sx': 200,
            'ix': 180,
            'col': [
              [255, 0, 0],
              [0, 255, 0],
              [0, 0, 255]
            ]
          }
        ]
      });
      return;
    }
    // Default: gentle on
    await repo.setState(on: true, brightness: 170, color: const Color(0xFFCCE7FF));
  }
}

final geofenceMonitorProvider = NotifierProvider<GeofenceMonitor, GeofenceState>(GeofenceMonitor.new);
