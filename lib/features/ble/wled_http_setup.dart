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

/// HTTP-based WLED controller setup
/// Uses HTTP POST to configure WiFi while connected to WLED-AP hotspot
class WledHttpSetup extends ConsumerStatefulWidget {
  const WledHttpSetup({super.key});

  @override
  ConsumerState<WledHttpSetup> createState() => _WledHttpSetupState();
}

class _WledHttpSetupState extends ConsumerState<WledHttpSetup> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _manualIpCtrl = TextEditingController();

  bool _showPassword = false;
  bool _processing = false;
  String? _errorMessage;
  int _step = 0; // 0=instructions, 1=credentials, 2=sending, 3=discovering, 4=manual, 5=done
  String? _discoveredIp;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendCredentials() async {
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
      debugPrint('📡 Sending WiFi credentials to WLED at 4.3.2.1');
      debugPrint('   SSID: ${_ssidCtrl.text.trim()}');
      debugPrint('   Password: ${_passwordCtrl.text.isNotEmpty ? "[provided]" : "[empty]"}');

      // Use a simple GET request with query parameters (no CSRF issues)
      // WLED accepts WiFi config via GET to /settings/wifi with these parameters
      final uri = Uri.parse('http://4.3.2.1/settings/wifi').replace(
        queryParameters: {
          'CS': _ssidCtrl.text.trim(),
          'CP': _passwordCtrl.text,
          'I0': '0', // DHCP
        },
      );

      debugPrint('📡 Sending GET request to configure WiFi...');
      debugPrint('   URL: $uri');

      final response = await http.get(uri).timeout(const Duration(seconds: 20));

      debugPrint('   Response status: ${response.statusCode}');
      debugPrint('   Response body length: ${response.body.length} bytes');

      // WLED returns an HTML page on success
      if (response.statusCode == 200 || response.statusCode == 301 || response.statusCode == 302) {
        debugPrint('✅ WiFi configuration accepted!');
      } else {
        throw Exception('WLED returned HTTP ${response.statusCode}');
      }

      // Wait 3 seconds, then trigger reboot via JSON API
      await Future.delayed(const Duration(seconds: 3));

      debugPrint('📡 Sending reboot command...');
      try {
        final rebootUri = Uri.parse('http://4.3.2.1/json/state');
        await http.post(
          rebootUri,
          headers: {'Content-Type': 'application/json'},
          body: '{"rb":true}',
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('   ⚠️ Reboot request threw (expected): $e');
      }

      debugPrint('✅ Setup complete! Controller will:');
      debugPrint('   1. Reboot now');
      debugPrint('   2. Connect to ${_ssidCtrl.text.trim()}');
      debugPrint('   3. Get IP from your router');

      if (!mounted) return;

      setState(() => _step = 3);

      // Wait 45 seconds for controller to reboot and connect
      await Future.delayed(const Duration(seconds: 45));

      if (!mounted) return;

      // Try auto-discovery
      await _tryAutoDiscover();

    } catch (e) {
      debugPrint('❌ Error: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = 'Failed to send credentials: $e';
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

        await _saveController(_discoveredIp!);
      } else {
        debugPrint('⚠️ No WLED devices found on network');

        if (!mounted) return;
        setState(() {
          _processing = false;
          _step = 4; // Manual IP entry
        });
      }
    } catch (e) {
      debugPrint('⚠️ Discovery failed: $e');
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
        return;
      } catch (e) {
        debugPrint('❌ Attempt $attempt failed: $e');
        if (attempt < 3) {
          debugPrint('⏳ Waiting 10 seconds before retry...');
          await Future.delayed(const Duration(seconds: 10));
        }
      }
    }

    setState(() {
      _processing = false;
      _errorMessage = 'Could not connect to controller at $ip after 3 attempts.';
    });
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
      final deviceName = info['name'] ?? (_nameCtrl.text.isEmpty ? 'Controller $ip' : _nameCtrl.text);

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
        ssid: _ssidCtrl.text.trim(),
      );

      debugPrint('✅ Controller saved successfully!');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _step = 5;
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
        title: const Text('Controller Setup'),
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
        return _buildCredentialsStep();
      case 2:
        return _buildSendingStep();
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

  Widget _buildInstructionsStep() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Icon(Icons.wifi_tethering, size: 64, color: NexGenPalette.cyan),
          const SizedBox(height: 24),
          Text(
            'Connect to WLED Controller',
            style: Theme.of(context).textTheme.headlineMedium,
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 32),
          _buildInstructionCard('1', 'Power on your WLED controller'),
          const SizedBox(height: 16),
          _buildInstructionCard('2', 'Look for "WLED-AP" or "ESP_xxxxxx" WiFi network'),
          const SizedBox(height: 16),
          _buildInstructionCard('3', 'Connect your phone/tablet to that network'),
          const SizedBox(height: 16),
          _buildInstructionCard('4', 'Return to this app and tap Continue below'),
          const Spacer(),
          ElevatedButton(
            onPressed: () => setState(() => _step = 1),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.all(16),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  Widget _buildInstructionCard(String number, String text) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.cyan.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              color: NexGenPalette.cyan,
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                number,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(fontSize: 16),
            ),
          ),
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
              labelText: 'Home WiFi Network Name (SSID)',
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
            onPressed: _processing ? null : _sendCredentials,
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
            label: const Text('Back to Instructions'),
          ),
        ],
      ),
    );
  }

  Widget _buildSendingStep() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 24),
            Text(
              'Configuring Controller',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 16),
            const Text(
              'Sending WiFi credentials and triggering reboot...',
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
              'Waiting for controller to connect to your home network...\n\n'
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
            'Check your router\'s connected devices for "Dig-Octa" or "WLED" and enter its IP address below.',
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
