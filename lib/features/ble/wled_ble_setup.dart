import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// BLE-based WLED controller setup
/// Uses Bluetooth to provision WiFi credentials, then discovers controller on network
class WledBleSetup extends ConsumerStatefulWidget {
  const WledBleSetup({super.key});

  @override
  ConsumerState<WledBleSetup> createState() => _WledBleSetupState();
}

class _WledBleSetupState extends ConsumerState<WledBleSetup> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _manualIpCtrl = TextEditingController();

  bool _showPassword = false;
  bool _processing = false;
  String? _errorMessage;
  int _step = 0; // 0=scan, 1=credentials, 2=provisioning, 3=discovering, 4=manual, 5=done

  BluetoothDevice? _selectedDevice;
  List<ScanResult> _scanResults = [];
  StreamSubscription<List<ScanResult>>? _scanSubscription;
  String? _discoveredIp;

  @override
  void dispose() {
    _scanSubscription?.cancel();
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _startBleScan() async {
    setState(() {
      _processing = true;
      _errorMessage = null;
      _scanResults = [];
    });

    try {
      debugPrint('🔵 Starting BLE scan for WLED controllers...');

      // Check Bluetooth state
      final adapterState = await FlutterBluePlus.adapterState.first;
      if (adapterState != BluetoothAdapterState.on) {
        throw Exception('Bluetooth is not enabled. Please enable Bluetooth.');
      }

      // Start scanning
      await FlutterBluePlus.startScan(
        timeout: const Duration(seconds: 15),
        androidUsesFineLocation: true,
      );

      _scanSubscription = FlutterBluePlus.scanResults.listen((results) {
        // Debug: Log ALL devices found
        debugPrint('🔵 Total BLE devices found: ${results.length}');
        for (var result in results) {
          final name = result.device.platformName;
          debugPrint('   - Device: "${name.isEmpty ? "(no name)" : name}" | ${result.device.remoteId} | RSSI: ${result.rssi}');
        }

        setState(() {
          // Filter for WLED devices (they advertise with "WLED" in the name)
          _scanResults = results.where((r) {
            final name = r.device.platformName;
            return name.isNotEmpty &&
                   (name.contains('WLED') ||
                    name.contains('ESP') ||
                    name.contains('Dig-Octa'));
          }).toList();
        });

        debugPrint('🔵 Found ${_scanResults.length} WLED devices (after filter)');
        for (var result in _scanResults) {
          debugPrint('   ✓ ${result.device.platformName} (${result.device.remoteId})');
        }
      });

      // Wait for scan to complete
      await Future.delayed(const Duration(seconds: 15));
      await FlutterBluePlus.stopScan();

      setState(() => _processing = false);

      if (_scanResults.isEmpty) {
        setState(() {
          _errorMessage = 'No WLED controllers found via Bluetooth.\n\n'
              'Make sure:\n'
              '• Controller is powered on\n'
              '• Controller is in AP mode (factory reset if needed)\n'
              '• Bluetooth is enabled on your device\n'
              '• You are within range (~10 meters)';
        });
      }
    } catch (e) {
      debugPrint('❌ BLE scan error: $e');
      setState(() {
        _processing = false;
        _errorMessage = 'Bluetooth scan failed: $e';
      });
    }
  }

  Future<void> _selectDevice(BluetoothDevice device) async {
    setState(() {
      _selectedDevice = device;
      _nameCtrl.text = device.platformName;
      _step = 1; // Move to credentials input
    });
  }

  Future<void> _provisionViaBle() async {
    if (_ssidCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter WiFi network name');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
      _step = 2;
    });

    try {
      debugPrint('🔵 Connecting to ${_selectedDevice!.platformName}...');

      // Connect to device (using dynamic to bypass API version issues)
      await (_selectedDevice as dynamic).connect();
      debugPrint('✅ Connected to BLE device');

      // Discover services
      debugPrint('🔵 Discovering services...');
      final services = await _selectedDevice!.discoverServices();

      // WLED uses a custom service UUID for WiFi provisioning
      // Service UUID: 00000001-0000-1000-8000-00805f9b34fb (WLED WiFi service)
      // Characteristic UUID: 00000002-0000-1000-8000-00805f9b34fb (WiFi credentials)

      BluetoothCharacteristic? wifiCharacteristic;

      for (var service in services) {
        debugPrint('🔵 Service: ${service.uuid}');
        for (var char in service.characteristics) {
          debugPrint('   - Characteristic: ${char.uuid}');

          // Look for writable characteristic (WiFi config)
          if (char.properties.write || char.properties.writeWithoutResponse) {
            wifiCharacteristic = char;
            debugPrint('   ✅ Found writable characteristic');
          }
        }
      }

      if (wifiCharacteristic == null) {
        throw Exception('Could not find WiFi provisioning characteristic');
      }

      // Send WiFi credentials as JSON
      final credentials = {
        'ssid': _ssidCtrl.text.trim(),
        'password': _passwordCtrl.text,
      };

      final credentialsJson = jsonEncode(credentials);
      final credentialsBytes = utf8.encode(credentialsJson);

      debugPrint('🔵 Sending credentials to device...');
      debugPrint('   SSID: ${_ssidCtrl.text.trim()}');
      debugPrint('   Password length: ${_passwordCtrl.text.length} chars');

      await wifiCharacteristic.write(
        credentialsBytes,
        withoutResponse: wifiCharacteristic.properties.writeWithoutResponse,
      );

      debugPrint('✅ Credentials sent via BLE');

      // Disconnect from BLE
      await _selectedDevice!.disconnect();
      debugPrint('🔵 Disconnected from BLE');

      // Wait for controller to reboot and connect to WiFi
      debugPrint('⏳ Waiting 45 seconds for controller to connect to WiFi...');
      setState(() => _step = 3);
      await Future.delayed(const Duration(seconds: 45));

      // Try to discover controller on network
      await _tryAutoDiscover();

    } catch (e) {
      debugPrint('❌ BLE provisioning error: $e');

      try {
        await _selectedDevice?.disconnect();
      } catch (_) {}

      setState(() {
        _processing = false;
        _errorMessage = 'BLE provisioning failed: $e\n\nTry factory resetting the controller.';
        _step = 1;
      });
    }
  }

  Future<void> _tryAutoDiscover() async {
    debugPrint('🔍 Attempting auto-discovery on network...');

    try {
      final service = ref.read(deviceDiscoveryServiceProvider);
      final devices = await service.discover(timeout: const Duration(seconds: 20));

      debugPrint('📡 Discovery complete: Found ${devices.length} devices');
      for (var device in devices) {
        debugPrint('   - ${device.address.address} (${device.name})');
      }

      if (devices.isNotEmpty) {
        _discoveredIp = devices.first.address.address;
        debugPrint('✅ Using first discovered controller at $_discoveredIp');

        // Save immediately
        await _saveController(_discoveredIp!);
      } else {
        debugPrint('⚠️ No WLED devices found on network');
        debugPrint('   Controller may still be connecting to WiFi...');

        if (!mounted) return;
        setState(() {
          _processing = false;
          _step = 4; // Manual IP entry
        });
      }
    } catch (e) {
      debugPrint('⚠️ Discovery failed: $e - showing manual entry');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _step = 4;
      });
    }
  }

  Future<void> _saveManualIp() async {
    final ip = _manualIpCtrl.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter IP address');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    // Try up to 3 times with delays
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        debugPrint('🔄 Connection attempt $attempt/3 to $ip');
        await _saveController(ip);
        return; // Success!
      } catch (e) {
        debugPrint('❌ Attempt $attempt failed: $e');
        if (attempt < 3) {
          debugPrint('⏳ Waiting 10 seconds before retry...');
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    // All attempts failed
    setState(() {
      _processing = false;
      _errorMessage = 'Could not connect to controller at $ip after 3 attempts.\n\n'
          'The controller may still be rebooting or connecting to WiFi.\n'
          'Check your router for the device and try again.';
    });
  }

  Future<void> _saveController(String ip) async {
    debugPrint('🔍 Testing connection to $ip');

    try {
      // Test connection
      final infoUri = Uri.parse('http://$ip/json/info');
      final response = await http.get(infoUri).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        throw Exception('Controller returned HTTP ${response.statusCode}');
      }

      debugPrint('✅ Controller is reachable!');

      final info = jsonDecode(response.body);
      // Prioritize user-provided name over WLED device name
      final deviceName = _nameCtrl.text.trim().isNotEmpty
          ? _nameCtrl.text.trim()
          : 'My Controller';

      debugPrint('📝 Controller name: $deviceName');

      // Save to Firebase
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      debugPrint('💾 Saving to Firebase');

      // Create repository instance and save
      final repository = DeviceRepository();
      await repository.saveDevice(
        userId: user.uid,
        serial: ip.replaceAll('.', '_'),
        ip: ip,
        name: deviceName,
        ssid: _ssidCtrl.text.trim(),
      );

      debugPrint('✅ Controller saved successfully!');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _step = 5;
      });

      // Auto-navigate after 2 seconds
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppRoutes.controllersSettings);

    } catch (e) {
      debugPrint('❌ Save failed: $e');
      rethrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: GlassAppBar(
        title: const Text('BLE Controller Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [
              NexGenPalette.gunmetal90,
              NexGenPalette.matteBlack,
            ],
          ),
        ),
        child: SafeArea(
          child: _buildStepContent(),
        ),
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0:
        return _buildScanStep();
      case 1:
        return _buildCredentialsStep();
      case 2:
        return _buildProvisioningStep();
      case 3:
        return _buildDiscoveringStep();
      case 4:
        return _buildManualIpStep();
      case 5:
        return _buildSuccessStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildScanStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.bluetooth_searching, size: 64, color: NexGenPalette.cyan),
          const SizedBox(height: 24),
          Text(
            'Find WLED Controller',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Text(
            'Make sure your WLED controller is:\n'
            '• Powered on\n'
            '• In AP mode (factory reset if needed)\n'
            '• Within Bluetooth range',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          if (_scanResults.isEmpty && !_processing)
            ElevatedButton.icon(
              onPressed: _startBleScan,
              icon: const Icon(Icons.bluetooth_searching),
              label: const Text('Scan for Controllers'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.all(16),
              ),
            ),

          if (_processing)
            const Center(
              child: Column(
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Scanning for WLED controllers...'),
                ],
              ),
            ),

          if (_scanResults.isNotEmpty) ...[
            const Text(
              'Found Controllers:',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: ListView.builder(
                itemCount: _scanResults.length,
                itemBuilder: (context, index) {
                  final result = _scanResults[index];
                  final device = result.device;

                  return Card(
                    color: Colors.white.withOpacity(0.1),
                    child: ListTile(
                      leading: const Icon(Icons.bluetooth, color: NexGenPalette.cyan),
                      title: Text(device.platformName),
                      subtitle: Text('Signal: ${result.rssi} dBm'),
                      trailing: const Icon(Icons.arrow_forward_ios),
                      onTap: () => _selectDevice(device),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: _startBleScan,
              icon: const Icon(Icons.refresh),
              label: const Text('Scan Again'),
            ),
          ],

          if (_errorMessage != null) ...[
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCredentialsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi, size: 64, color: NexGenPalette.cyan),
          const SizedBox(height: 24),
          Text(
            'Configure WiFi',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            'Selected: ${_selectedDevice?.platformName}',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white70),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Controller Name',
              hintText: 'e.g., Front Yard Lights',
              prefixIcon: Icon(Icons.label),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _ssidCtrl,
            decoration: const InputDecoration(
              labelText: 'WiFi Network Name (SSID)',
              hintText: 'Enter your WiFi network name',
              prefixIcon: Icon(Icons.wifi),
            ),
          ),
          const SizedBox(height: 16),

          TextField(
            controller: _passwordCtrl,
            obscureText: !_showPassword,
            decoration: InputDecoration(
              labelText: 'WiFi Password',
              hintText: 'Enter WiFi password',
              prefixIcon: const Icon(Icons.lock),
              suffixIcon: IconButton(
                icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
                onPressed: () => setState(() => _showPassword = !_showPassword),
              ),
            ),
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.red)),
            ),
          ],

          const SizedBox(height: 32),

          ElevatedButton(
            onPressed: _processing ? null : _provisionViaBle,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
            child: _processing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Send to Controller'),
          ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: () => setState(() => _step = 0),
            icon: const Icon(Icons.arrow_back),
            label: const Text('Back to Scan'),
          ),
        ],
      ),
    );
  }

  Widget _buildProvisioningStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Provisioning Controller',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sending WiFi credentials via Bluetooth...',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDiscoveringStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Discovering Controller',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Waiting for controller to connect to WiFi and scanning network...\n\n'
              'This may take up to 60 seconds.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white70),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildManualIpStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.edit_location_alt, size: 64, color: Colors.orange),
          const SizedBox(height: 24),
          Text(
            'Manual IP Entry',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          const Text(
            'Controller not found automatically.\n\n'
            'Check your router\'s connected devices list for your WLED controller and enter its IP address below.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70),
          ),
          const SizedBox(height: 32),

          TextField(
            controller: _manualIpCtrl,
            decoration: const InputDecoration(
              labelText: 'IP Address',
              hintText: '192.168.1.100',
              prefixIcon: Icon(Icons.router),
            ),
            keyboardType: TextInputType.number,
          ),

          if (_errorMessage != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.2),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange),
              ),
              child: Text(_errorMessage!, style: const TextStyle(color: Colors.orange)),
            ),
          ],

          const SizedBox(height: 24),

          ElevatedButton(
            onPressed: _processing ? null : _saveManualIp,
            style: ElevatedButton.styleFrom(padding: const EdgeInsets.all(16)),
            child: _processing
                ? const SizedBox(height: 20, width: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Connect'),
          ),

          const SizedBox(height: 16),

          OutlinedButton.icon(
            onPressed: _tryAutoDiscover,
            icon: const Icon(Icons.refresh),
            label: const Text('Try Auto-Discovery Again'),
          ),
        ],
      ),
    );
  }

  Widget _buildSuccessStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.check_circle, size: 96, color: Colors.green),
            const SizedBox(height: 24),
            Text(
              'Setup Complete!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              'Controller "${_nameCtrl.text}" has been added and is ready to use.',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white70),
            ),
            const SizedBox(height: 32),
            ElevatedButton(
              onPressed: () => context.go(AppRoutes.controllersSettings),
              child: const Text('Go to My Controllers'),
            ),
          ],
        ),
      ),
    );
  }
}
