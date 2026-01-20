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
import 'package:network_info_plus/network_info_plus.dart';

/// Simplified Wi-Fi setup flow for WLED controllers
/// Flow: 1. Name controller → 2. Enter Wi-Fi credentials → 3. Auto-save and connect
class WifiConnectPage extends ConsumerStatefulWidget {
  const WifiConnectPage({super.key});

  @override
  ConsumerState<WifiConnectPage> createState() => _WifiConnectPageState();
}

class _WifiConnectPageState extends ConsumerState<WifiConnectPage> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ssidCtrl = TextEditingController();
  final TextEditingController _passwordCtrl = TextEditingController();

  bool _showPassword = false;
  bool _processing = false;
  String? _errorMessage;

  int _currentStep = 0; // 0: Connect to controller AP, 1: Name, 2: Wi-Fi credentials, 3: Reconnect to home WiFi, 4: Connecting/Complete
  String _controllerIp = '4.3.2.1'; // Default WLED AP mode IP
  bool _connectedToAp = false;
  bool _credentialsSent = false;
  bool _reconnectedToHomeWifi = false;

  @override
  void initState() {
    super.initState();
    _checkApConnection();
    _loadCurrentWifiSsid();
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ssidCtrl.dispose();
    _passwordCtrl.dispose();
    super.dispose();
  }

  /// Check if connected to WLED AP mode
  Future<void> _checkApConnection() async {
    try {
      final uri = Uri.parse('http://4.3.2.1/json/info');
      final response = await http.get(uri).timeout(const Duration(seconds: 3));
      if (response.statusCode == 200) {
        debugPrint('Connected to WLED AP mode at 4.3.2.1');
        if (mounted) {
          setState(() {
            _connectedToAp = true;
            _currentStep = 1; // Skip to name step since we're already connected
          });
        }
      }
    } catch (e) {
      debugPrint('Not connected to WLED AP: $e');
      if (mounted) {
        setState(() {
          _connectedToAp = false;
          _currentStep = 0; // Start at connection instructions
        });
      }
    }
  }

  /// Auto-fill current Wi-Fi SSID
  Future<void> _loadCurrentWifiSsid() async {
    try {
      final info = NetworkInfo();
      String? ssid = await info.getWifiName();
      if (ssid != null) {
        ssid = ssid.replaceAll('"', '').replaceAll("'", '');
        // Don't prefill if it's the controller's AP
        if (!ssid.toLowerCase().contains('wled') && !ssid.toLowerCase().contains('nexgen')) {
          if (mounted) {
            setState(() => _ssidCtrl.text = ssid!);
          }
        }
      }
    } catch (e) {
      debugPrint('Could not get Wi-Fi SSID: $e');
    }
  }

  void _nextStep() {
    if (_currentStep == 0) {
      // Check if connected to AP, then move to name step
      _checkApConnection();
    } else if (_currentStep == 1) {
      // Validate name
      if (_nameCtrl.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Please enter a name for your controller');
        return;
      }
      setState(() {
        _currentStep = 2;
        _errorMessage = null;
      });
    } else if (_currentStep == 2) {
      // Validate Wi-Fi credentials and send to controller
      if (_ssidCtrl.text.trim().isEmpty) {
        setState(() => _errorMessage = 'Please enter your Wi-Fi network name');
        return;
      }
      _sendWifiCredentials();
    } else if (_currentStep == 3) {
      // Check if reconnected to home WiFi, then proceed to discover
      _checkHomeWifiAndDiscover();
    }
  }

  void _previousStep() {
    if (_currentStep > 0) {
      setState(() {
        _currentStep--;
        _errorMessage = null;
      });
    }
  }

  /// Step 2.5: Send WiFi credentials to controller
  Future<void> _sendWifiCredentials() async {
    setState(() {
      _processing = true;
      _errorMessage = null;
    });

    final ssid = _ssidCtrl.text.trim();
    final password = _passwordCtrl.text;

    try {
      debugPrint('📡 Sending Wi-Fi credentials to controller at $_controllerIp');
      // Send Wi-Fi credentials to controller
      final uri = Uri.parse('http://$_controllerIp/settings/wifi');
      final payload = {'ssid': ssid, 'password': password};
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        throw Exception('Failed to configure Wi-Fi (HTTP ${response.statusCode})');
      }

      debugPrint('✅ Wi-Fi credentials sent successfully!');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _credentialsSent = true;
        _currentStep = 3; // Move to reconnect step
        _errorMessage = null;
      });
    } catch (e) {
      debugPrint('❌ Failed to send Wi-Fi credentials: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = 'Failed to send credentials: ${e.toString()}';
      });
    }
  }

  /// Step 3.5: Check if reconnected to home WiFi, then discover and save
  Future<void> _checkHomeWifiAndDiscover() async {
    setState(() {
      _processing = true;
      _currentStep = 4; // Move to final connecting/complete step
      _errorMessage = null;
    });

    final controllerName = _nameCtrl.text.trim();
    final ssid = _ssidCtrl.text.trim();

    try {
      debugPrint('🔍 Waiting for controller to connect to home network...');
      // Wait for controller to reboot and connect to home network
      await Future.delayed(const Duration(seconds: 25));

      debugPrint('🔎 Scanning network for controller...');
      // Scan network to find the controller's new IP
      final service = ref.read(deviceDiscoveryServiceProvider);
      final devices = await service.discover(timeout: const Duration(seconds: 15));

      String? newIp;
      if (devices.isNotEmpty) {
        // Found at least one device - use the first one
        newIp = devices.first.address.address;
        debugPrint('✅ Controller discovered at IP: $newIp');
      } else {
        debugPrint('❌ No devices found during discovery');
      }

      if (newIp == null || newIp == '127.0.0.1') {
        // Discovery failed, ask user to check router and try manual setup later
        debugPrint('⚠️ Discovery failed or found localhost - showing manual setup dialog');
        if (!mounted) return;
        _showManualSetupDialog(ssid);
        return;
      }

      // Save to Firebase with the new IP
      debugPrint('💾 Saving controller to Firebase: $controllerName @ $newIp (network: $ssid)');
      await _saveToFirebase(newIp, controllerName, ssid);
      debugPrint('✅ Controller saved successfully!');

    } catch (e) {
      debugPrint('❌ Setup failed: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = 'Setup failed: ${e.toString()}';
      });
    }
  }

  /// Save controller to Firebase
  Future<void> _saveToFirebase(String ip, String name, String ssid) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      debugPrint('❌ Cannot save - user not logged in');
      throw Exception('Not logged in');
    }

    debugPrint('📝 Saving to Firestore: userId=${user.uid}, ip=$ip, name=$name, ssid=$ssid');

    final repo = DeviceRepository();
    await repo.saveDevice(
      userId: user.uid,
      serial: ip.replaceAll('.', '_'),
      ip: ip,
      name: name,
      ssid: ssid,
    );

    debugPrint('✅ Firestore save complete - setting as active device');

    // Set as active device
    ref.read(selectedDeviceIpProvider.notifier).state = ip;

    if (!mounted) return;

    // Show success and navigate to dashboard
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$name successfully connected!'),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );

    debugPrint('🏠 Navigating to dashboard');
    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) return;
    context.go(AppRoutes.dashboard);
  }

  /// Show dialog when auto-discovery fails
  void _showManualSetupDialog(String ssid) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Setup Almost Complete'),
        content: Text(
          'Wi-Fi credentials have been sent to the controller.\n\n'
          'The controller is connecting to "$ssid" but we couldn\'t auto-discover its IP address.\n\n'
          'Please:\n'
          '1. Check your router to find the controller\'s IP\n'
          '2. Go to System Management → All Devices\n'
          '3. Tap "Rescan" to find your controller\n'
          '4. Tap it to add and activate',
        ),
        actions: [
          FilledButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              context.go(AppRoutes.dashboard);
            },
            child: const Text('Go to Dashboard'),
          ),
        ],
      ),
    );
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
              // Progress indicator
              _buildProgressIndicator(),
              const SizedBox(height: 32),

              // Step content
              if (_currentStep == 0) _buildConnectToApStep(),
              if (_currentStep == 1) _buildNameStep(),
              if (_currentStep == 2) _buildWifiStep(),
              if (_currentStep == 3) _buildReconnectStep(),
              if (_currentStep == 4) _buildConnectingStep(),

              // Error message
              if (_errorMessage != null) ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.red),
                  ),
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: Colors.red[300]),
                  ),
                ),
              ],

              const SizedBox(height: 24),

              // Navigation buttons
              if (_currentStep < 4) _buildNavigationButtons(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProgressIndicator() {
    return Row(
      children: [
        _buildStepCircle(0, 'AP'),
        _buildProgressLine(0),
        _buildStepCircle(1, 'Name'),
        _buildProgressLine(1),
        _buildStepCircle(2, 'WiFi'),
        _buildProgressLine(2),
        _buildStepCircle(3, 'Home'),
        _buildProgressLine(3),
        _buildStepCircle(4, 'Done'),
      ],
    );
  }

  Widget _buildStepCircle(int step, String label) {
    final isActive = _currentStep == step;
    final isComplete = _currentStep > step;
    return Expanded(
      child: Column(
        children: [
          Container(
            width: 32,
            height: 32,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isComplete
                  ? Colors.green
                  : isActive
                      ? NexGenPalette.cyan
                      : Colors.grey.withOpacity(0.3),
            ),
            child: Center(
              child: isComplete
                  ? const Icon(Icons.check, color: Colors.white, size: 16)
                  : Text(
                      '${step + 1}',
                      style: TextStyle(
                        color: isActive ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12,
                      ),
                    ),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: isActive ? NexGenPalette.cyan : Colors.grey,
                  fontSize: 10,
                ),
          ),
        ],
      ),
    );
  }

  Widget _buildProgressLine(int step) {
    final isComplete = _currentStep > step;
    return Expanded(
      child: Container(
        height: 2,
        margin: const EdgeInsets.only(bottom: 20),
        color: isComplete ? Colors.green : Colors.grey.withOpacity(0.3),
      ),
    );
  }

  Widget _buildConnectToApStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.router, size: 64, color: NexGenPalette.cyan),
        const SizedBox(height: 16),
        Text(
          'Connect to Controller',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'To set up your controller, you need to connect your phone to the controller\'s Wi-Fi hotspot first.',
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
              Row(
                children: [
                  const Icon(Icons.info_outline, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Text(
                    'Setup Instructions',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: NexGenPalette.cyan,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Open your phone\'s Wi-Fi settings\n'
                '2. Look for a network named "WLED-AP" or similar\n'
                '3. Connect to that network\n'
                '4. Return to this app and tap "Check Connection"',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        if (_connectedToAp) ...[
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.green.withOpacity(0.1),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.green),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: Colors.green),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Connected to controller at 4.3.2.1',
                    style: TextStyle(color: Colors.green[300]),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildNameStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.label, size: 64, color: NexGenPalette.cyan),
        const SizedBox(height: 16),
        Text(
          'Name Your Controller',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Choose a name to identify this controller (e.g., "Front Yard", "Backyard", "Garage").',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _nameCtrl,
          autofocus: true,
          textCapitalization: TextCapitalization.words,
          decoration: InputDecoration(
            labelText: 'Controller Name',
            hintText: 'Front Yard',
            prefixIcon: const Icon(Icons.label_outline),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (_) => _nextStep(),
        ),
      ],
    );
  }

  Widget _buildWifiStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.wifi, size: 64, color: NexGenPalette.cyan),
        const SizedBox(height: 16),
        Text(
          'Connect to Wi-Fi',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Enter your home Wi-Fi credentials. The controller will connect to this network for remote access.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        const SizedBox(height: 24),
        TextField(
          controller: _ssidCtrl,
          decoration: InputDecoration(
            labelText: 'Wi-Fi Network Name (SSID)',
            hintText: 'MyHomeNetwork',
            prefixIcon: const Icon(Icons.wifi),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          controller: _passwordCtrl,
          obscureText: !_showPassword,
          decoration: InputDecoration(
            labelText: 'Wi-Fi Password',
            prefixIcon: const Icon(Icons.lock),
            suffixIcon: IconButton(
              icon: Icon(_showPassword ? Icons.visibility_off : Icons.visibility),
              onPressed: () => setState(() => _showPassword = !_showPassword),
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
          onSubmitted: (_) => _nextStep(),
        ),
      ],
    );
  }

  Widget _buildReconnectStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(Icons.wifi_find, size: 64, color: NexGenPalette.cyan),
        const SizedBox(height: 16),
        Text(
          'Reconnect to Home Wi-Fi',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
        ),
        const SizedBox(height: 8),
        Text(
          'Wi-Fi credentials have been sent to the controller. Now you need to reconnect your phone to your home Wi-Fi network.',
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
              Row(
                children: [
                  const Icon(Icons.info_outline, color: NexGenPalette.cyan),
                  const SizedBox(width: 8),
                  Text(
                    'Next Steps',
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          color: NexGenPalette.cyan,
                        ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                '1. Open your phone\'s Wi-Fi settings\n'
                '2. Disconnect from the WLED AP hotspot\n'
                '3. Connect to "${_ssidCtrl.text.trim()}"\n'
                '4. Return to this app and tap "Continue"',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.orange.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: Colors.orange),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber, color: Colors.orange),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Make sure you\'re connected to your home Wi-Fi before continuing!',
                  style: TextStyle(color: Colors.orange[300]),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildConnectingStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const SizedBox(height: 32),
        const CircularProgressIndicator(strokeWidth: 3),
        const SizedBox(height: 24),
        Text(
          'Connecting Controller...',
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.bold,
              ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'Please wait while we:\n'
          '• Wait for controller to connect to your network\n'
          '• Discover controller\'s IP address\n'
          '• Save to your account',
          style: Theme.of(context).textTheme.bodyMedium,
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 16),
        Text(
          'This may take up to 40 seconds...',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Colors.grey,
              ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildNavigationButtons() {
    // Determine button labels and icons based on step
    String buttonLabel;
    IconData buttonIcon;

    if (_currentStep == 0) {
      buttonLabel = 'Check Connection';
      buttonIcon = Icons.refresh;
    } else if (_currentStep == 2) {
      buttonLabel = 'Send Credentials';
      buttonIcon = Icons.send;
    } else if (_currentStep == 3) {
      buttonLabel = 'Continue';
      buttonIcon = Icons.arrow_forward;
    } else {
      buttonLabel = 'Next';
      buttonIcon = Icons.arrow_forward;
    }

    return Row(
      children: [
        if (_currentStep > 0 && _currentStep < 4)
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _processing ? null : _previousStep,
              icon: const Icon(Icons.arrow_back),
              label: const Padding(
                padding: EdgeInsets.symmetric(vertical: 16),
                child: Text('Back'),
              ),
            ),
          ),
        if (_currentStep > 0 && _currentStep < 4) const SizedBox(width: 16),
        Expanded(
          child: FilledButton.icon(
            onPressed: _processing ? null : _nextStep,
            icon: _processing
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.black,
                    ),
                  )
                : Icon(buttonIcon),
            label: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(buttonLabel),
            ),
          ),
        ),
      ],
    );
  }
}
