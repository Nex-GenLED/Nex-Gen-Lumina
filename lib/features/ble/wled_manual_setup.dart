import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

/// Manual WLED controller setup
/// Guides user through WLED's web interface, then discovers and saves the controller
class WledManualSetup extends ConsumerStatefulWidget {
  const WledManualSetup({super.key});

  @override
  ConsumerState<WledManualSetup> createState() => _WledManualSetupState();
}

class _WledManualSetupState extends ConsumerState<WledManualSetup> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _manualIpCtrl = TextEditingController();

  bool _processing = false;
  String? _errorMessage;
  int _step = 0; // 0=instructions, 1=discovering, 2=manual IP, 3=done

  @override
  void dispose() {
    _nameCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _startDiscovery() async {
    setState(() {
      _processing = true;
      _errorMessage = null;
      _step = 1;
    });

    await Future.delayed(const Duration(seconds: 2));

    try {
      debugPrint('🔍 Scanning network for WLED controllers...');

      final service = ref.read(deviceDiscoveryServiceProvider);
      final devices = await service.discover(timeout: const Duration(seconds: 20));

      debugPrint('📡 Discovery complete: Found ${devices.length} devices');
      for (var device in devices) {
        debugPrint('   - ${device.address.address} (${device.name})');
      }

      if (devices.isNotEmpty) {
        final ip = devices.first.address.address;
        debugPrint('✅ Found controller at $ip');

        await _saveController(ip);
      } else {
        debugPrint('⚠️ No WLED devices found on network');

        if (!mounted) return;
        setState(() {
          _processing = false;
          _step = 2; // Manual IP entry
        });
      }
    } catch (e) {
      debugPrint('❌ Discovery failed: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = 'Discovery failed: $e';
        _step = 2;
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

    try {
      await _saveController(ip);
    } catch (e) {
      setState(() {
        _processing = false;
        _errorMessage = 'Could not connect to controller: $e';
      });
    }
  }

  Future<void> _saveController(String ip) async {
    debugPrint('🔍 Testing connection to $ip');

    try {
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

      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('No user logged in');
      }

      debugPrint('💾 Saving to Firebase');

      final repository = DeviceRepository();
      await repository.saveDevice(
        userId: user.uid,
        serial: ip.replaceAll('.', '_'),
        ip: ip,
        name: deviceName,
      );

      debugPrint('✅ Controller saved successfully!');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _step = 3;
      });

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
        title: const Text('Add Controller'),
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
        return _buildInstructionsStep();
      case 1:
        return _buildDiscoveringStep();
      case 2:
        return _buildManualIpStep();
      case 3:
        return _buildSuccessStep();
      default:
        return const SizedBox();
    }
  }

  Widget _buildInstructionsStep() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.settings_remote, size: 64, color: NexGenPalette.cyan),
          const SizedBox(height: 24),
          Text(
            'Setup WLED Controller',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),

          _buildInstructionCard(
            '1',
            'Connect to WLED-AP',
            'Power on your controller and connect to the "WLED-AP" or "ESP_xxxxxx" WiFi network from your device settings.',
          ),
          const SizedBox(height: 16),

          _buildInstructionCard(
            '2',
            'Open WLED Web Interface',
            'Open your browser and go to:\nhttp://4.3.2.1',
          ),
          const SizedBox(height: 16),

          _buildInstructionCard(
            '3',
            'Configure WiFi',
            'In WLED\'s web interface:\n• Tap "Config" → "WiFi Setup"\n• Enter your home WiFi credentials\n• Tap "Save & Connect"',
          ),
          const SizedBox(height: 16),

          _buildInstructionCard(
            '4',
            'Reconnect to Home WiFi',
            'After WLED reboots:\n• Disconnect from WLED-AP\n• Reconnect to your home WiFi network\n• Return to this app',
          ),

          const SizedBox(height: 32),

          TextField(
            controller: _nameCtrl,
            decoration: const InputDecoration(
              labelText: 'Controller Name (Optional)',
              hintText: 'e.g., Front Yard Lights',
              prefixIcon: Icon(Icons.label),
            ),
          ),

          const SizedBox(height: 32),

          ElevatedButton.icon(
            onPressed: _startDiscovery,
            icon: const Icon(Icons.search),
            label: const Text('Find My Controller'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
          ),

          const SizedBox(height: 16),

          Text(
            'Tap when you\'ve completed the steps above',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Colors.white60,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(String number, String title, String description) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: const BoxDecoration(
                  color: NexGenPalette.cyan,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: Text(
                    number,
                    style: const TextStyle(
                      color: Colors.black,
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Padding(
            padding: const EdgeInsets.only(left: 44),
            child: Text(
              description,
              style: TextStyle(
                fontSize: 14,
                color: Colors.white.withOpacity(0.8),
                height: 1.5,
              ),
            ),
          ),
        ],
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
              'Searching for Controller',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Scanning your network for WLED controllers...',
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
            'Enter Controller IP',
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
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
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
            onPressed: _startDiscovery,
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
              'Controller Added!',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 16),
            Text(
              _nameCtrl.text.isEmpty
                  ? 'Your controller has been added and is ready to use.'
                  : 'Controller "${_nameCtrl.text}" has been added and is ready to use.',
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
