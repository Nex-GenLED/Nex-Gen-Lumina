import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:nexgen_command/services/user_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Screen to configure the "Welcome Home" geofence trigger.
///
/// Features
/// - Google Map centered on user's home (from profile lat/lng), with a Home marker
/// - Cyan semi-transparent circle indicating the trigger radius
/// - Live-updating radius slider (100m - 1000m)
/// - Action dropdown (favorites or fallback scenes)
/// - "Only at Night" toggle
/// - Save to Firestore under users/{uid}/geofences/welcome_home
class GeofenceSetupScreen extends StatefulWidget {
  const GeofenceSetupScreen({super.key});

  @override
  State<GeofenceSetupScreen> createState() => _GeofenceSetupScreenState();
}

class _GeofenceSetupScreenState extends State<GeofenceSetupScreen> {
  final _userService = UserService();
  final _firestore = FirebaseFirestore.instance;
  GoogleMapController? _mapController;

  static const double _defaultZoom = 16;
  static const LatLng _fallbackCenter = LatLng(37.422, -122.084); // Fallback: Googleplex

  LatLng _center = _fallbackCenter;
  double _radiusMeters = 300; // default
  bool _onlyAtNight = true;

  List<String> _actions = const ['Turn On Warm White', 'Start Party Mode', 'Relax', 'Turn Off'];
  String? _selectedAction;

  bool _loading = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) {
        debugPrint('GeofenceSetup: no authed user');
        return;
      }

      // 1) Load user profile for home coordinates
      final user = await _userService.getUser(uid);
      if (user?.latitude != null && user?.longitude != null) {
        _center = LatLng(user!.latitude!, user.longitude!);
      }

      // 3) Load existing geofence config (if any)
      final doc = await _firestore.collection('users').doc(uid).collection('geofences').doc('welcome_home').get();
      if (doc.exists) {
        final data = doc.data()!;
        final r = data['radius_m'] as num?;
        final night = data['only_at_night'] as bool?;
        final action = data['action_name'] as String?;
        final lat = data['center_lat'] as num?;
        final lng = data['center_lng'] as num?;
        if (r != null) _radiusMeters = r.toDouble().clamp(100.0, 1000.0);
        if (night != null) _onlyAtNight = night;
        if (action != null && action.isNotEmpty) _selectedAction = action;
        if (lat != null && lng != null) _center = LatLng(lat.toDouble(), lng.toDouble());
      }

      // 4) Try to load favorites list from Firestore, else defaults
      try {
        final favSnap = await _firestore.collection('users').doc(uid).collection('favorites').get();
        final names = favSnap.docs.map((d) => (d.data()['name'] ?? '').toString()).where((e) => e.isNotEmpty).toList();
        if (names.isNotEmpty) {
          _actions = names;
          _selectedAction ??= _actions.first;
        }
      } catch (e) {
        debugPrint('Load favorites failed: $e');
      }
    } catch (e) {
      debugPrint('GeofenceSetup init failed: $e');
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  // If no stored home position is available, we keep the fallback center.

  Future<void> _save() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_selectedAction == null || _selectedAction!.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Select an action to trigger')));
      return;
    }
    setState(() => _saving = true);
    try {
      await _firestore.collection('users').doc(uid).collection('geofences').doc('welcome_home').set({
        'center_lat': _center.latitude,
        'center_lng': _center.longitude,
        'radius_m': _radiusMeters.round(),
        'action_name': _selectedAction,
        'only_at_night': _onlyAtNight,
        'updated_at': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Welcome Home trigger saved')));
      context.pop();
    } catch (e) {
      debugPrint('Save geofence failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Set<Marker> get _markers => {
        Marker(
          markerId: const MarkerId('home'),
          position: _center,
          infoWindow: const InfoWindow(title: 'Home'),
          icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueCyan),
        ),
      };

  Set<Circle> get _circles => {
        Circle(
          circleId: const CircleId('geofence'),
          center: _center,
          radius: _radiusMeters,
          fillColor: NexGenPalette.cyan.withValues(alpha: 0.18),
          strokeColor: NexGenPalette.cyan,
          strokeWidth: 2,
        ),
      };

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Welcome Home'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton.icon(
              onPressed: _saving ? null : _save,
              icon: _saving ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
              label: const Text('Save'),
            ),
          )
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Stack(children: [
              Positioned.fill(
                child: GoogleMap(
                  onMapCreated: (c) => _mapController = c,
                  initialCameraPosition: CameraPosition(target: _center, zoom: _defaultZoom),
                  myLocationButtonEnabled: true,
                  myLocationEnabled: true,
                  markers: _markers,
                  circles: _circles,
                  compassEnabled: true,
                  zoomControlsEnabled: false,
                  mapToolbarEnabled: false,
                ),
              ),
              Align(
                alignment: Alignment.bottomCenter,
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                    child: _ControlsCard(
                      radius: _radiusMeters,
                      actions: _actions,
                      selectedAction: _selectedAction,
                      onlyAtNight: _onlyAtNight,
                      onRadiusChanged: (v) => setState(() => _radiusMeters = v),
                      onActionChanged: (s) => setState(() => _selectedAction = s),
                      onOnlyAtNightChanged: (v) => setState(() => _onlyAtNight = v),
                    ),
                  ),
                ),
              )
            ]),
    );
  }
}

class _ControlsCard extends StatelessWidget {
  final double radius;
  final List<String> actions;
  final String? selectedAction;
  final bool onlyAtNight;
  final ValueChanged<double> onRadiusChanged;
  final ValueChanged<String?> onActionChanged;
  final ValueChanged<bool> onOnlyAtNightChanged;
  const _ControlsCard({required this.radius, required this.actions, required this.selectedAction, required this.onlyAtNight, required this.onRadiusChanged, required this.onActionChanged, required this.onOnlyAtNightChanged});

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.home, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Text('Geofence Controls', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          Text('Trigger Distance: ${radius.round()} m', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: radius,
            min: 100,
            max: 1000,
            divisions: 18,
            label: '${radius.round()} m',
            onChanged: onRadiusChanged,
          ),
          const SizedBox(height: 8),
          Text('When I enter this circle…', style: Theme.of(context).textTheme.labelLarge),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: selectedAction ?? (actions.isNotEmpty ? actions.first : null),
            items: actions.map((e) => DropdownMenuItem(value: e, child: Text(e, overflow: TextOverflow.ellipsis))).toList(),
            onChanged: onActionChanged,
            decoration: const InputDecoration(prefixIcon: Icon(Icons.bolt), hintText: 'Select action'),
          ),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(child: Text('Only at Night?', style: Theme.of(context).textTheme.labelLarge)),
            Switch(value: onlyAtNight, onChanged: onOnlyAtNightChanged),
          ]),
        ]),
      ),
    );
  }
}
