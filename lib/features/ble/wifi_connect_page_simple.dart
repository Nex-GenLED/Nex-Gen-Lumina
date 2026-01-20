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

/// SIMPLIFIED: Just ask for name and IP, test connection, save to Firebase
/// This removes ALL the complexity and WiFi credential sending
class WifiConnectPageSimple extends ConsumerStatefulWidget {
  const WifiConnectPageSimple({super.key});

  @override
  ConsumerState<WifiConnectPageSimple> createState() => _WifiConnectPageSimpleState();
}

class _WifiConnectPageSimpleState extends ConsumerState<WifiConnectPageSimple> {
  final TextEditingController _nameCtrl = TextEditingController();
  final TextEditingController _ipCtrl = TextEditingController();

  bool _processing = false;
  String? _errorMessage;
  String? _successMessage;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _ipCtrl.dispose();
    super.dispose();
  }

  Future<void> _addController() async {
    setState(() {
      _processing = true;
      _errorMessage = null;
      _successMessage = null;
    });

    final name = _nameCtrl.text.trim();
    final ip = _ipCtrl.text.trim();

    // Validate inputs
    if (name.isEmpty) {
      setState(() {
        _processing = false;
        _errorMessage = 'Please enter a controller name';
      });
      return;
    }

    if (ip.isEmpty) {
      setState(() {
        _processing = false;
        _errorMessage = 'Please enter an IP address';
      });
      return;
    }

    try {
      // Test connection
      debugPrint('🔍 Testing connection to $ip...');
      final testUri = Uri.parse('http://$ip/json/info');
      final testResponse = await http.get(testUri).timeout(const Duration(seconds: 10));

      if (testResponse.statusCode != 200) {
        throw Exception('Cannot reach controller at $ip');
      }

      debugPrint('✅ Controller is reachable!');

      // Get device info
      final info = jsonDecode(testResponse.body);
      String finalName = name;
      if (info['name'] != null && info['name'].toString().isNotEmpty) {
        finalName = info['name'].toString();
        debugPrint('Using controller name: $finalName');
      }

      // Save to Firebase
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        throw Exception('Not logged in');
      }

      debugPrint('💾 Saving to Firebase...');
      final repo = DeviceRepository();
      await repo.saveDevice(
        userId: user.uid,
        serial: ip.replaceAll('.', '_'),
        ip: ip,
        name: finalName,
      );

      // Set as active
      ref.read(selectedDeviceIpProvider.notifier).state = ip;

      debugPrint('✅ SUCCESS! Controller saved and activated');

      if (!mounted) return;

      setState(() {
        _processing = false;
        _successMessage = 'Controller added successfully!';
      });

      // Navigate to dashboard
      await Future.delayed(const Duration(seconds: 1));
      if (!mounted) return;
      context.go(AppRoutes.dashboard);
    } catch (e) {
      debugPrint('❌ Error: $e');
      if (!mounted) return;
      setState(() {
        _processing = false;
        _errorMessage = e.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Add Controller')),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.router, size: 80, color: NexGenPalette.cyan),
              const SizedBox(height: 24),
              Text(
                'Add Controller',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.bold),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              const Text(
                'Enter the controller\'s name and IP address',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 32),

              // Name field
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

              // IP field
              TextField(
                controller: _ipCtrl,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: 'IP Address',
                  hintText: '192.168.1.100',
                  prefixIcon: const Icon(Icons.pin),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
              const SizedBox(height: 24),

              // Error message
              if (_errorMessage != null)
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

              // Success message
              if (_successMessage != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.green.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.green),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.check_circle, color: Colors.green),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_successMessage!, style: const TextStyle(color: Colors.green))),
                    ],
                  ),
                ),

              // Add button
              FilledButton.icon(
                onPressed: _processing ? null : _addController,
                icon: _processing
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Icon(Icons.add),
                label: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Text(_processing ? 'Adding...' : 'Add Controller'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
