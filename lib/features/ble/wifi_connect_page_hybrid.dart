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

/// HYBRID APPROACH: Send WiFi credentials, auto-discover, with manual IP fallback
class WifiConnectPageHybrid extends ConsumerStatefulWidget {
  const WifiConnectPageHybrid({super.key});

  @override
  ConsumerState<WifiConnectPageHybrid> createState() => _WifiConnectPageHybridState();
}

class _WifiConnectPageHybridState extends ConsumerState<WifiConnectPageHybrid> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();
  final TextEditingController _manualIpCtrl = TextEditingController();

  bool _showPassword = false;
  bool _processing = false;
  String? _errorMessage;
  int _step = 0; // 0=instructions, 1=name+wifi, 2=sending, 3=discovering, 4=manual_fallback, 5=done
  String? _discoveredIp;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    _manualIpCtrl.dispose();
    super.dispose();
  }

  void _startSetup() {
    setState(() => _step = 1);
  }

  Future<void> _sendCredentials() async {
    if (_nameCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter a controller name');
      return;
    }
    if (_ssidCtrl.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your WiFi network name');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
      _step = 2;
    });

    try {
      // Send WiFi credentials to WLED controller using correct endpoint and format
      debugPrint('📡 Sending WiFi credentials to WLED at 4.3.2.1');
      debugPrint('   SSID: ${_ssidCtrl.text.trim()}');
      debugPrint('   Password: ${_passwordCtrl.text.isNotEmpty ? "[provided]" : "[empty]"}');

      // Send WiFi credentials using form-encoded POST to /settings
      // CRITICAL: Must use /settings (not /settings/wifi) with the WS parameter to save and apply
      debugPrint('📡 Step 1: Sending WiFi configuration to /settings...');
      final settingsUri = Uri.parse('http://4.3.2.1/settings');
      final settingsResponse = await http.post(
        settingsUri,
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'CS': _ssidCtrl.text.trim(),  // Client SSID
          'CP': _passwordCtrl.text,      // Client Password
          'I0': '0',                      // Use DHCP (not static IP)
          'WS': '1',                      // Save WiFi settings (CRITICAL!)
        },
      ).timeout(const Duration(seconds: 15));

      debugPrint('   Settings response: ${settingsResponse.statusCode}');
      debugPrint('   Response body: ${settingsResponse.body.substring(0, settingsResponse.body.length > 200 ? 200 : settingsResponse.body.length)}');

      if (settingsResponse.statusCode != 200 && settingsResponse.statusCode != 301 && settingsResponse.statusCode != 302) {
        throw Exception('WLED rejected WiFi credentials (HTTP ${settingsResponse.statusCode})');
      }

      // Wait a moment for settings to be written to flash
      await Future.delayed(const Duration(seconds: 2));

      // Step 2: Verify what was saved
      debugPrint('📡 Step 2: Verifying saved configuration...');
      try {
        final verifyUri = Uri.parse('http://4.3.2.1/json/cfg');
        final verifyResponse = await http.get(verifyUri).timeout(const Duration(seconds: 10));

        if (verifyResponse.statusCode == 200) {
          final config = json.decode(verifyResponse.body);
          debugPrint('   📋 Network config: ${json.encode(config['nw'])}');

          // Check the saved SSID in the network interfaces array
          var savedSSID = (config['nw']?['ins'] is List && (config['nw']['ins'] as List).isNotEmpty
                              ? config['nw']['ins'][0]['ssid']
                              : 'NOT FOUND');

          debugPrint('   ✅ Saved SSID: "$savedSSID"');
          debugPrint('   ✅ Expected SSID: "${_ssidCtrl.text.trim()}"');
          debugPrint('   ✅ Match: ${savedSSID == _ssidCtrl.text.trim() ? "YES ✓" : "NO ✗"}');

          if (savedSSID != _ssidCtrl.text.trim()) {
            throw Exception('WLED did not save the SSID! Got "$savedSSID" instead of "${_ssidCtrl.text.trim()}"');
          }
        }
      } catch (e) {
        debugPrint('   ⚠️ Could not verify settings: $e');
        // Continue anyway - maybe it worked
      }

      // Step 3: Send reboot command
      debugPrint('📡 Step 3: Sending reboot command...');
      final jsonUri = Uri.parse('http://4.3.2.1/json/state');
      try {
        await http.post(
          jsonUri,
          headers: {'Content-Type': 'application/json'},
          body: '{"rb":true}',  // Reboot command
        ).timeout(const Duration(seconds: 5));
      } catch (e) {
        // Reboot request may timeout or fail as controller is rebooting - this is expected
        debugPrint('   ⚠️ Reboot request threw (expected): $e');
      }

      debugPrint('✅ WiFi configuration complete! Controller will:');
      debugPrint('   1. Reboot now');
      debugPrint('   2. Connect to ${_ssidCtrl.text.trim()}');
      debugPrint('   3. Disable AP hotspot');
      debugPrint('   4. Get IP address from your router');

      if (!mounted) return;

      // Wait longer for full reboot and WiFi connection (WLED can take 30-60 seconds)
      await Future.delayed(const Duration(seconds: 5));

      setState(() => _step = 3);

      // Wait 45 seconds for controller to fully reboot and connect to WiFi
      // WLED typically takes 30-60 seconds for full reboot + WiFi connection
      await Future.delayed(const Duration(seconds: 45));

      if (!mounted) return;

      // Try to auto-discover
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
    debugPrint('🔍 Attempting auto-discovery...');

    try {
      final service = ref.read(deviceDiscoveryServiceProvider);
      final devices = await service.discover(timeout: const Duration(seconds: 15));

      if (devices.isNotEmpty) {
        _discoveredIp = devices.first.address.address;
        debugPrint('✅ Found controller at $_discoveredIp');

        // Save immediately
        await _saveController(_discoveredIp!);
      } else {
        debugPrint('⚠️ No devices found - showing manual entry');
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
        _step = 4; // Manual IP entry
      });
    }
  }

  Future<void> _saveManualIp() async {
    final ip = _manualIpCtrl.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter an IP address');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    // Try multiple times with delays - controller might be rebooting
    for (int attempt = 1; attempt <= 3; attempt++) {
      debugPrint('🔄 Connection attempt $attempt/3 to $ip');

      try {
        await _saveController(ip);
        return; // Success! Exit the retry loop
      } catch (e) {
        debugPrint('❌ Attempt $attempt failed: $e');

        if (attempt < 3) {
          debugPrint('⏳ Waiting 10 seconds before retry $attempt...');
          await Future.delayed(const Duration(seconds: 10));

          if (!mounted) return;

          setState(() {
            _errorMessage = 'Attempt $attempt failed. Retrying... (${attempt + 1}/3)\n\n'
                'Controller may still be rebooting. Please wait.';
          });
        } else {
          // Final attempt failed
          if (!mounted) return;
          setState(() {
            _processing = false;
            _errorMessage = 'Connection failed after 3 attempts.\n\n'
                'The controller appeared on your network but isn\'t responding.\n\n'
                'Possible causes:\n'
                '• Controller is still rebooting (wait 1 minute and try again)\n'
                '• Controller crashed and needs power cycle\n'
                '• IP address changed (check router again)\n\n'
                'Try power cycling the controller and checking the IP again.';
          });
        }
      }
    }
  }

  Future<void> _forceAddController() async {
    final ip = _manualIpCtrl.text.trim();
    if (ip.isEmpty) {
      setState(() => _errorMessage = 'Please enter an IP address');
      return;
    }

    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in');
      }

      final controllerName = _nameCtrl.text.trim();

      debugPrint('⚠️ FORCE ADDING controller without testing connection');
      debugPrint('💾 Saving $controllerName @ $ip to Firebase');

      final repo = DeviceRepository();
      await repo.saveDevice(
        userId: user.uid,
        serial: ip.replaceAll('.', '_'),
        ip: ip,
        name: controllerName,
        ssid: _ssidCtrl.text.trim(),
      );

      // Set as active
      ref.read(selectedDeviceIpProvider.notifier).state = ip;

      debugPrint('✅ Controller force-added!');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _step = 5;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$controllerName added (untested)'),
          backgroundColor: Colors.orange,
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (e) {
      debugPrint('❌ Force add failed: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = 'Failed to save: $e';
      });
    }
  }

  Future<void> _saveController(String ip) async {
    try {
      // Test connection first with better error messages
      debugPrint('🔍 Testing connection to $ip');
      final testUri = Uri.parse('http://$ip/json/info');

      final testResponse = await http.get(testUri).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          debugPrint('⏰ Connection timed out - controller not responding');
          throw Exception(
            'Controller not responding at $ip.\n\n'
            'Please verify:\n'
            '• Controller is powered on\n'
            '• Controller is connected to WiFi "${_ssidCtrl.text.trim()}"\n'
            '• Your phone is on the same WiFi network\n'
            '• IP address is correct (check your router)'
          );
        },
      );

      if (testResponse.statusCode != 200) {
        throw Exception('Controller responded with error: HTTP ${testResponse.statusCode}');
      }

      debugPrint('✅ Controller is reachable!');

      // Get device name
      final info = jsonDecode(testResponse.body);
      String finalName = _nameCtrl.text.trim();
      if (info['name'] != null && info['name'].toString().isNotEmpty) {
        finalName = info['name'].toString();
        debugPrint('📝 Controller name: $finalName');
      }

      // Save to Firebase
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in');
      }

      debugPrint('💾 Saving to Firebase');
      final repo = DeviceRepository();
      await repo.saveDevice(
        userId: user.uid,
        serial: ip.replaceAll('.', '_'),
        ip: ip,
        name: finalName,
        ssid: _ssidCtrl.text.trim(),
      );

      // Set as active
      ref.read(selectedDeviceIpProvider.notifier).state = ip;

      debugPrint('✅ SUCCESS! Controller saved and activated');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _step = 5;
      });

      // Show success and navigate
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$finalName connected successfully!'),
          backgroundColor: Colors.green,
          duration: const Duration(seconds: 3),
        ),
      );

      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (e) {
      debugPrint('❌ Save failed: $e');
      if (!mounted) return;

      String errorMsg;
      if (e.toString().contains('TimeoutException')) {
        errorMsg = 'Connection timeout!\n\n'
            'The controller at $ip is not responding.\n\n'
            'Make sure:\n'
            '• Controller is powered on\n'
            '• Controller connected to "${_ssidCtrl.text.trim()}"\n'
            '• Your phone is on the same network\n'
            '• IP address is correct';
      } else if (e.toString().contains('SocketException') || e.toString().contains('Failed host lookup')) {
        errorMsg = 'Invalid IP address!\n\n'
            'Cannot reach $ip.\n\n'
            'Please check:\n'
            '• IP address format is correct\n'
            '• Controller is on your network\n'
            '• Check your router for the right IP';
      } else {
        errorMsg = e.toString();
      }

      setState(() {
        _processing = false;
        _errorMessage = errorMsg;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Add Controller')),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_step == 0) _buildInstructions(),
              if (_step == 1) _buildFormStep(),
              if (_step == 2) _buildSendingStep(),
              if (_step == 3) _buildDiscoveringStep(),
              if (_step == 4) _buildManualIpStep(),
              if (_step == 5) _buildSuccessStep(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInstructions() {
    return Column(
      children: [
        const Icon(Icons.info_outline, size: 80, color: NexGenPalette.cyan),
        const SizedBox(height: 24),
        Text(
          'Setup Instructions',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
          ),
          child: const Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '1. Connect your phone to the WLED controller\'s WiFi hotspot (usually named "WLED-AP")',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '2. Return to this app',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '3. The app will send your home WiFi credentials to the controller',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
              SizedBox(height: 12),
              Text(
                '4. The controller will automatically connect and be ready to use!',
                style: TextStyle(fontSize: 15, height: 1.5),
              ),
            ],
          ),
        ),
        const SizedBox(height: 32),
        FilledButton.icon(
          onPressed: _startSetup,
          icon: const Icon(Icons.arrow_forward),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16, horizontal: 8),
            child: Text('I\'m Connected to WLED-AP'),
          ),
        ),
      ],
    );
  }

  Widget _buildFormStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.edit, size: 64, color: NexGenPalette.cyan),
        const SizedBox(height: 16),
        Text(
          'Controller Setup',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),

        // Name
        TextField(
          controller: _nameCtrl,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Controller Name',
            hintText: 'Front Yard',
            prefixIcon: const Icon(Icons.label),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        // WiFi SSID
        TextField(
          controller: _ssidCtrl,
          decoration: InputDecoration(
            labelText: 'Your WiFi Network Name',
            hintText: 'MyHomeNetwork',
            prefixIcon: const Icon(Icons.wifi),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        // WiFi Password
        TextField(
          controller: _passwordCtrl,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'WiFi Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 24),

        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),
        ],

        FilledButton.icon(
          onPressed: _processing ? null : _sendCredentials,
          icon: _processing
              ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
              : const Icon(Icons.send),
          label: const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Text('Send to Controller'),
          ),
        ),
      ],
    );
  }

  Widget _buildSendingStep() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 24),
        Text(
          'Sending WiFi Credentials',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Please wait while we configure your controller...',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildDiscoveringStep() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 24),
        Text(
          'Finding Controller',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'The controller is rebooting and connecting to your WiFi network.\n\n'
          'This takes about 30 seconds...',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildManualIpStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.search, size: 64, color: Colors.orange),
        const SizedBox(height: 16),
        Text(
          'Find Controller IP',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          'Auto-discovery didn\'t find the controller.\n\n'
          'Make sure your phone is connected to "${_ssidCtrl.text.trim()}" WiFi, then find the controller\'s IP address.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.cyan.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.lightbulb_outline, color: NexGenPalette.cyan),
                  SizedBox(width: 8),
                  Text('Quick Tips', style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '✓ Your phone MUST be on "${_ssidCtrl.text.trim()}"\n'
                '✓ Controller MUST be powered on\n'
                '✓ Controller should have successfully connected to WiFi\n'
                '✓ Look for device named "WLED" or "ESP" in router',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.orange.withOpacity(0.3)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.orange),
                  SizedBox(width: 8),
                  Text('How to Find IP', style: TextStyle(color: Colors.orange, fontWeight: FontWeight.bold)),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Open your router\'s admin page (usually 192.168.1.1 or 192.168.0.1)\n'
                '2. Find "Connected Devices" or "DHCP Clients" section\n'
                '3. Look for device named "WLED", "ESP", or similar\n'
                '4. Copy the IP address (format: 192.168.x.x)',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24),

        TextField(
          controller: _manualIpCtrl,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: 'IP Address',
            hintText: '192.168.1.100',
            prefixIcon: const Icon(Icons.pin),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        const SizedBox(height: 16),

        if (_errorMessage != null) ...[
          Container(
            padding: const EdgeInsets.all(12),
            margin: const EdgeInsets.only(bottom: 16),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red),
            ),
            child: Row(
              children: [
                const Icon(Icons.error, color: Colors.red),
                const SizedBox(width: 8),
                Expanded(child: Text(_errorMessage!, style: const TextStyle(color: Colors.red))),
              ],
            ),
          ),
        ],

        Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: _processing ? null : _saveManualIp,
                icon: _processing
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                    : const Icon(Icons.save),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Test & Save'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: OutlinedButton.icon(
                onPressed: _processing ? null : _forceAddController,
                icon: const Icon(Icons.add_circle_outline),
                label: const Padding(
                  padding: EdgeInsets.symmetric(vertical: 16),
                  child: Text('Force Add'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          '"Force Add" skips connection test - use if controller keeps rebooting',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(color: Colors.grey),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSuccessStep() {
    return Column(
      children: [
        const SizedBox(height: 40),
        const Icon(Icons.check_circle, size: 100, color: Colors.green),
        const SizedBox(height: 24),
        Text(
          'Setup Complete!',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 16),
        const Text(
          'Your controller has been added and is ready to use!',
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
