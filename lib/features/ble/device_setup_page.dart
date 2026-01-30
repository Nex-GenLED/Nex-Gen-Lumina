import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/ble/provisioning_service.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:geolocator/geolocator.dart';
import 'package:network_info_plus/network_info_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/user_role.dart';

/// Device Setup screen with a specialized BLE scanner for Improv Standard.
class DeviceSetupPage extends ConsumerStatefulWidget {
  const DeviceSetupPage({super.key});

  @override
  ConsumerState<DeviceSetupPage> createState() => _DeviceSetupPageState();
}

class _DeviceSetupPageState extends ConsumerState<DeviceSetupPage> with SingleTickerProviderStateMixin {
  static final Guid _improvUuid = Guid('00000000-0090-0016-0128-633215502390');
  final List<ScanResult> _results = [];
  StreamSubscription<List<ScanResult>>? _scanSub;
  bool _isScanning = false;
  bool _connecting = false;
  bool _connected = false;

  BluetoothDevice? _device;
  BluetoothCharacteristic? _improvChar;
  BluetoothCharacteristic? _improvResultChar; // Optional: RPC Result characteristic
  StreamSubscription<List<int>>? _notifySub;

  // Provisioning form state
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passCtrl = TextEditingController();
  bool _provisioning = false;
  String? _statusText;
  bool _showPassword = false;
  bool _provisionSuccess = false;
  String? _provisionedIp;
  // Triggers a quick scale/fade animation on success overlay
  bool _showSuccessOverlay = false;
  // Wi‑Fi prompt flow state
  bool _showWifiPrompt = false;
  bool _wifiFormVisible = false;
  String? _currentSsid;

  late final AnimationController _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();

  @override
  void initState() {
    super.initState();

    // Check user permissions before allowing controller pairing
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _checkPairingPermission();
    });

    // Avoid plugin calls on web/simulation; provide a mock experience.
    if (kIsWeb || kSimulationMode) {
      _mockPopulate();
    } else {
      _startScan();
    }
  }

  /// Verify the current user has permission to add new controllers.
  /// Only primary users and installers can pair new devices.
  Future<void> _checkPairingPermission() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('You must be signed in to add controllers.')),
        );
        context.pop();
      }
      return;
    }

    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (!userDoc.exists) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('User profile not found.')),
          );
          context.pop();
        }
        return;
      }

      final data = userDoc.data()!;
      final roleStr = data['installation_role'] as String?;
      final role = InstallationRoleExtension.fromJson(roleStr);

      // Only primary users and installers can add new controllers
      if (role != InstallationRole.primary && role != InstallationRole.installer) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Only system owners can add new controllers.'),
              backgroundColor: Colors.orange,
            ),
          );
          context.pop();
        }
        return;
      }
    } catch (e) {
      debugPrint('Error checking pairing permission: $e');
      // Allow through in case of network issues to avoid blocking installers
    }
  }

  Future<void> _startScan() async {
    try {
      setState(() => _isScanning = true);
      await FlutterBluePlus.stopScan();
      // Filter by the Improv service UUID; some devices mask it, so we will also apply a name fallback in onData.
      await FlutterBluePlus.startScan(withServices: [_improvUuid], timeout: const Duration(seconds: 8));

      _scanSub = FlutterBluePlus.scanResults.listen((list) {
        // Flatten and filter new results.
        final byId = <DeviceIdentifier, ScanResult>{};
        for (final r in list) {
          byId[r.device.remoteId] = r;
        }
        final filtered = byId.values.where((r) {
          final name = (r.device.platformName.isNotEmpty ? r.device.platformName : r.advertisementData.advName).toLowerCase();
          final advUuids = r.advertisementData.serviceUuids.map((e) => e.toString().toLowerCase()).toList();
          final hasImprov = advUuids.contains(_improvUuid.toString().toLowerCase());
          final nameFallback = name.contains('wled') || name.contains('nex-gen') || name.contains('nexgen');
          return hasImprov || nameFallback;
        }).toList()
          ..sort((a, b) => (b.rssi).compareTo(a.rssi));

        setState(() {
          _results
            ..clear()
            ..addAll(filtered);
        });
      });
    } catch (e) {
      debugPrint('BLE scan start failed: $e');
    } finally {
      // Allow the periodic timeout to end scanning; keep radar anim while we have results.
      unawaited(Future.delayed(const Duration(seconds: 9), () {
        if (mounted) setState(() => _isScanning = false);
      }));
    }
  }

  void _mockPopulate() {
    setState(() {
      _isScanning = true;
      _results.clear();
    });
    Future.delayed(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isScanning = false;
        _connected = true; // directly show provisioning form in simulation/web
      });
    });
  }

  @override
  void dispose() {
    _scanSub?.cancel();
    unawaited(FlutterBluePlus.stopScan());
    _radarCtrl.dispose();
    _notifySub?.cancel();
    if (_device != null && !(kIsWeb || kSimulationMode)) {
      // Best-effort disconnect; don't await in dispose.
      unawaited(_device!.disconnect());
    }
    _ssidCtrl.dispose();
    _passCtrl.dispose();
    super.dispose();
  }

  Future<void> _onConnect(ScanResult r) async {
    if (_connecting) return;
    setState(() => _connecting = true);
    try {
      final device = r.device;
      debugPrint('Connecting to ${device.remoteId} / ${device.platformName}');
      if (!(kIsWeb || kSimulationMode)) {
        await (device as dynamic).connect();
        debugPrint('Connected, discovering services…');
        final services = await device.discoverServices();
        final improvService = services.firstWhere(
          (s) => s.uuid == _improvUuid,
          orElse: () => services.firstWhere(
            (s) => s.characteristics.any((c) => c.uuid == _improvUuid),
            orElse: () => services.isNotEmpty ? services.first : throw Exception('No services on device'),
          ),
        );
        // Heuristics to locate Improv characteristics:
        // - Command (write / writeWithoutResponse)
        // - State/Notify (notify) — we will subscribe on the command char if shared
        // - RPC Result (read/notify, non-writable) — optional
        BluetoothCharacteristic? writeChar;
        BluetoothCharacteristic? resultChar;
        for (final c in improvService.characteristics) {
          // Prefer an explicit UUID match if present
          if (c.uuid == _improvUuid && (c.properties.write || c.properties.writeWithoutResponse)) {
            writeChar = c;
          }
          // Identify a likely result characteristic by being readable/notify but not writable
          if ((c.properties.read || c.properties.notify) && !(c.properties.write || c.properties.writeWithoutResponse)) {
            resultChar ??= c;
          }
        }
        // Fallback: pick first writable as command
        writeChar ??= improvService.characteristics.firstWhere(
          (c) => (c.properties.write || c.properties.writeWithoutResponse),
          orElse: () => improvService.characteristics.first,
        );

        _device = device;
        _improvChar = writeChar;
        _improvResultChar = resultChar;
      }

      if (!mounted) return;
      if (kIsWeb || kSimulationMode) {
        _device = device;
        _improvChar = null; // no real BLE on web
      }
      setState(() {
        _connected = true;
        _showWifiPrompt = true;
      });
      // Try to read current Wi‑Fi SSID to prefill
      unawaited(_loadCurrentWifiSsid());
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connected. Continue with Wi‑Fi setup.')));
    } catch (e) {
      debugPrint('BLE connect/discover failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Connection failed: $e')));
    } finally {
      if (mounted) setState(() => _connecting = false);
    }
  }

  // ================= Improv RPC =================
  Future<void> _provisionWifi() async {
    final ssid = _ssidCtrl.text.trim();
    final pass = _passCtrl.text;
    if (ssid.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Enter Wi‑Fi SSID')));
      return;
    }
    setState(() {
      _provisioning = true;
      _statusText = 'Sending credentials…';
    });

    if (kIsWeb || kSimulationMode) {
      // Simulate provisioning flow
      debugPrint('Simulation: provisioning "$ssid"');
      await Future.delayed(const Duration(seconds: 1));
      setState(() {
        _statusText = 'Connecting to Wi‑Fi…';
      });
      await Future.delayed(const Duration(seconds: 2));
      final ip = '192.168.1.123';
      if (mounted) {
        setState(() {
          _provisioning = false;
          _statusText = 'Connected to Wi‑Fi';
          _provisionSuccess = true;
          _provisionedIp = ip;
          _showSuccessOverlay = true;
        });
        ref.read(selectedDeviceIpProvider.notifier).state = ip;
        // Proactively refresh dashboard-related providers
        try {
          ref.invalidate(controllersStreamProvider);
          ref.invalidate(activeAreaControllerIpsProvider);
        } catch (e) {
          debugPrint('Provider refresh failed (sim): $e');
        }
        Future.delayed(const Duration(seconds: 2), () {
          if (!mounted) return;
          context.go(AppRoutes.dashboard);
        });
      }
      return;
    }

    try {
      final d = _device;
      if (d == null) {
        setState(() {
          _provisioning = false;
          _statusText = 'No device connected';
        });
        return;
      }
      // Use the new ProvisioningService to handle Improv BLE flow
      final service = ProvisioningService();
      final result = await service.provisionDevice(device: d, ssid: ssid, password: pass);
      if (!mounted) return;
      // Persisted inside service; update UI state and navigate
      ref.read(selectedDeviceIpProvider.notifier).state = result.ip;
      setState(() {
        _provisioning = false;
        _statusText = 'Connected to Wi‑Fi';
        _provisionSuccess = true;
        _provisionedIp = result.ip;
        _showSuccessOverlay = true;
      });
      // Proactively refresh dashboard-related providers to reflect new device immediately
      try {
        ref.invalidate(controllersStreamProvider);
        ref.invalidate(activeAreaControllerIpsProvider);
      } catch (e) {
        debugPrint('Provider refresh failed: $e');
      }
      Future.delayed(const Duration(seconds: 2), () {
        if (!mounted) return;
        context.go(AppRoutes.dashboard);
      });
    } catch (e) {
      debugPrint('Provisioning via service failed: $e');
      if (!mounted) return;
      setState(() {
        _provisioning = false;
        _statusText = 'Failed: $e';
        _provisionSuccess = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: const Text('Connection Failed. Please check your Wi‑Fi password and try again.'),
        backgroundColor: Theme.of(context).colorScheme.error,
      ));
    }
  }

  // Attempt to read optional RPC Result characteristic for error code diagnostics
  Future<void> _readRpcResult() async {
    final c = _improvResultChar;
    if (c == null || kIsWeb || kSimulationMode) return;
    try {
      final value = await c.read();
      if (value.isEmpty) return;
      final code = value.first;
      debugPrint('Improv RPC Result code: 0x${code.toRadixString(16)} (len=${value.length})');
    } catch (e) {
      debugPrint('Failed to read RPC Result characteristic: $e');
    }
  }

  Future<void> _loadCurrentWifiSsid() async {
    try {
      // On mobile, reading SSID requires location permission.
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.deniedForever) {
        debugPrint('Location permission permanently denied; cannot read SSID');
      }
      final info = NetworkInfo();
      final ssid = await info.getWifiName();
      if (!mounted) return;
      setState(() => _currentSsid = ssid);
    } catch (e) {
      debugPrint('Failed to fetch current Wi‑Fi SSID: $e');
    }
  }

  void _useCurrentNetwork() {
    if (_currentSsid != null && _currentSsid!.isNotEmpty) {
      _ssidCtrl.text = _currentSsid!;
    }
    setState(() {
      _wifiFormVisible = true;
      _showWifiPrompt = false;
    });
  }

  void _enterWifiManually() {
    setState(() {
      _wifiFormVisible = true;
      _showWifiPrompt = false;
    });
  }

  void _skipWifiForNow() {
    context.go(AppRoutes.dashboard);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Device Setup')),
      body: Stack(children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          // Header with radar animation
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              SizedBox(width: 64, height: 64, child: RadarScan(animation: _radarCtrl, active: _isScanning)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Scanning for Nex-Gen Controllers', style: Theme.of(context).textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text('Filtered by Improv Service UUID', style: Theme.of(context).textTheme.labelMedium),
                ]),
              ),
              if (_isScanning) const SizedBox(width: 12),
              if (_isScanning) const CircularProgressIndicator(strokeWidth: 2),
              if (!_isScanning)
                IconButton(
                  tooltip: 'Rescan',
                  onPressed: () {
                    if (kIsWeb || kSimulationMode) {
                      _mockPopulate();
                    } else {
                      _startScan();
                    }
                  },
                  icon: const Icon(Icons.refresh),
                ),
            ]),
          ),
          const SizedBox(height: 16),
          if (_connected && _showWifiPrompt) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.wifi, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Use your current Wi‑Fi network?', style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 8),
                  Text(
                    _currentSsid == null || _currentSsid!.isEmpty
                        ? 'We\'ll try to prefill your SSID if permissions allow.'
                        : 'Detected: '+_currentSsid!,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _useCurrentNetwork,
                      icon: const Icon(Icons.check_circle_outline),
                      label: const Text('Use This Network'),
                    ),
                    const SizedBox(width: 12),
                    OutlinedButton.icon(
                      onPressed: _enterWifiManually,
                      icon: const Icon(Icons.edit_outlined),
                      label: const Text('Enter Manually'),
                    ),
                    const SizedBox(width: 8),
                    TextButton(onPressed: _skipWifiForNow, child: const Text('Set up later')),
                  ])
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (_connected && _wifiFormVisible) ...[
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Icon(Icons.wifi_password, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Expanded(child: Text('Connect Controller to Wi‑Fi', style: Theme.of(context).textTheme.titleMedium)),
                  ]),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _ssidCtrl,
                    decoration: const InputDecoration(labelText: 'Home Wi‑Fi Name (SSID)'),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _passCtrl,
                    obscureText: !_showPassword,
                    decoration: InputDecoration(
                      labelText: 'Password',
                      suffixIcon: IconButton(
                        tooltip: _showPassword ? 'Hide Password' : 'Show Password',
                        icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                        onPressed: () => setState(() => _showPassword = !_showPassword),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  Row(children: [
                    FilledButton.icon(
                      onPressed: _provisioning || !_connected ? null : _provisionWifi,
                      icon: const Icon(Icons.send_rounded),
                      label: const Text('Connect & Finish Setup'),
                    ),
                    const SizedBox(width: 12),
                    if (_provisioning) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
                    if (_provisionSuccess) ...[
                      const SizedBox(width: 8),
                      Icon(Icons.check_circle, color: Theme.of(context).colorScheme.tertiary),
                      const SizedBox(width: 6),
                      Flexible(child: Text(_provisionedIp != null ? 'Success: '+_provisionedIp! : 'Success', overflow: TextOverflow.ellipsis)),
                    ] else ...[
                      const SizedBox(width: 8),
                      if (_statusText != null) Expanded(child: Text(_statusText!, overflow: TextOverflow.ellipsis)),
                    ]
                  ])
                ]),
              ),
            ),
            const SizedBox(height: 16),
          ],
          if (!_connected && _results.isEmpty && !_isScanning)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bluetooth_searching, color: NexGenPalette.violet, size: 48),
                  const SizedBox(height: 12),
                  Text('No devices found', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 8),
                  Text('Make sure the controller is in pairing mode and nearby.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            )
          else if (!_connected)
            Expanded(
              child: ListView.separated(
                itemCount: _results.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _DeviceCard(result: _results[i], onConnect: _onConnect, busy: _connecting),
              ),
            ),
          if (_connected && !_wifiFormVisible && !_showWifiPrompt)
            Expanded(
              child: Center(
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.bluetooth_connected, color: NexGenPalette.cyan),
                  const SizedBox(height: 8),
                  Text('Connected. You can set up Wi‑Fi now or later.', style: Theme.of(context).textTheme.bodyMedium),
                ]),
              ),
            ),
          ]),
        ),
        // Success overlay animation
        IgnorePointer(
          ignoring: true,
          child: AnimatedOpacity(
            opacity: _showSuccessOverlay ? 1 : 0,
            duration: const Duration(milliseconds: 280),
            child: Container(
              color: Colors.black.withValues(alpha: 0.4),
              alignment: Alignment.center,
              child: AnimatedScale(
                scale: _showSuccessOverlay ? 1 : 0.9,
                duration: const Duration(milliseconds: 360),
                curve: Curves.easeOutBack,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(Icons.check_circle_rounded, color: Theme.of(context).colorScheme.tertiary, size: 28),
                    const SizedBox(width: 10),
                    Text('Device Connected!', style: Theme.of(context).textTheme.titleMedium),
                  ]),
                ),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _DeviceCard extends StatelessWidget {
  final ScanResult result;
  final Future<void> Function(ScanResult) onConnect;
  final bool busy;
  const _DeviceCard({required this.result, required this.onConnect, required this.busy});

  String _title() {
    final name = result.device.platformName.isNotEmpty ? result.device.platformName : result.advertisementData.advName;
    if (name.toLowerCase().contains('wled') || name.toLowerCase().contains('nex')) return 'Nex-Gen Controller';
    return name.isEmpty ? 'Unknown Device' : name;
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.bluetooth, color: NexGenPalette.cyan),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(_title(), style: Theme.of(context).textTheme.titleMedium, overflow: TextOverflow.ellipsis),
              const SizedBox(height: 2),
              Text(result.device.remoteId.str, style: Theme.of(context).textTheme.labelMedium, overflow: TextOverflow.ellipsis),
            ]),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy ? null : () => onConnect(result),
            child: busy ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Connect'),
          )
        ]),
      ),
    );
  }
}

/// Animated radar circles to indicate scanning state.
class RadarScan extends StatelessWidget {
  final Animation<double> animation;
  final bool active;
  const RadarScan({super.key, required this.animation, required this.active});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (_, __) {
        final t = active ? animation.value : 0.0;
        return Stack(alignment: Alignment.center, children: [
          _ring(context, 1.0, t),
          _ring(context, 0.66, (t + 0.33) % 1.0),
          _ring(context, 0.33, (t + 0.66) % 1.0),
          Container(width: 8, height: 8, decoration: BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle, boxShadow: [BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.7), blurRadius: 10, spreadRadius: 1)])),
        ]);
      },
    );
  }

  Widget _ring(BuildContext context, double base, double t) {
    final size = 56 * (base + t);
    final opacity = (1.0 - t).clamp(0.0, 1.0);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3 * opacity)),
      ),
    );
  }
}
