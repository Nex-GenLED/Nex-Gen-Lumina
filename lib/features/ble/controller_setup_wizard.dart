import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// First-run Controller Setup Wizard (Screen 1 - Welcome)
/// - Explains BLE setup and requests Bluetooth + Location permissions
class ControllerSetupWizard extends StatefulWidget {
  const ControllerSetupWizard({super.key});

  @override
  State<ControllerSetupWizard> createState() => _ControllerSetupWizardState();
}

class _ControllerSetupWizardState extends State<ControllerSetupWizard> with SingleTickerProviderStateMixin {
  late final AnimationController _fadeCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
  bool _requesting = false;

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  Future<void> _onStartScanning() async {
    if (kIsWeb) {
      if (!mounted) return;
      context.push(AppRoutes.deviceSetup);
      return;
    }
    setState(() => _requesting = true);
    try {
      Map<Permission, PermissionStatus> results = {};
      if (Platform.isAndroid) {
        results = await <Permission>[Permission.bluetoothScan, Permission.locationWhenInUse].request();
      } else if (Platform.isIOS) {
        // iOS shows a system Bluetooth permission; request it explicitly and ask for location (optional for BLE proximity).
        results = await <Permission>[Permission.bluetooth, Permission.locationWhenInUse].request();
      } else {
        // Other platforms: proceed without explicit runtime permissions
      }

      final allGranted = results.isEmpty || results.values.every((s) => s.isGranted);
      if (!mounted) return;
      if (allGranted) {
        context.push(AppRoutes.deviceSetup);
      } else {
        _showPermissionHelp(results);
      }
    } catch (e) {
      debugPrint('Permission request failed: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Unable to request permissions. Please try again.')));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  void _showPermissionHelp(Map<Permission, PermissionStatus> statuses) {
    final bt = statuses[Permission.bluetooth] ?? statuses[Permission.bluetoothScan];
    final loc = statuses[Permission.locationWhenInUse];
    final needBt = bt != null && !bt.isGranted;
    final needLoc = loc != null && !loc.isGranted;
    final lines = <String>[];
    if (needBt) lines.add('Bluetooth is required to discover your Nex-Gen Controller.');
    if (needLoc) lines.add('Location helps with Bluetooth scanning and nearby device discovery.');
    if (lines.isEmpty) lines.add('Some permissions were denied. You can enable them in Settings.');

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Theme.of(ctx).colorScheme.surface,
        title: const Text('Permissions Needed'),
        content: Text(lines.join('\n\n')),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const Text('Not Now')),
          FilledButton(
            onPressed: () async {
              Navigator.of(ctx).pop();
              await openAppSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text("Controller Setup")),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              FadeTransition(
                opacity: Tween<double>(begin: 0.35, end: 1.0).animate(CurvedAnimation(parent: _fadeCtrl, curve: Curves.easeInOut)),
                child: Container(
                  width: 110,
                  height: 110,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                  ),
                  child: const Icon(Icons.bluetooth_searching, size: 56, color: NexGenPalette.cyan),
                ),
              ),
              const SizedBox(height: 20),
              Text("Let's Connect Your System.", style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(
                'Ensure your Nex-Gen Controller is powered on and you are within 10 feet.',
                style: Theme.of(context).textTheme.bodyMedium,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _requesting ? null : _onStartScanning,
                  icon: _requesting
                      ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.radar, color: Colors.black),
                  label: const Padding(
                    padding: EdgeInsets.symmetric(vertical: 4),
                    child: Text('Start Scanning'),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text('We will request Bluetooth and Location permissions to find your controller.', style: Theme.of(context).textTheme.labelMedium, textAlign: TextAlign.center),
            ]),
          ),
        ),
      ),
    );
  }
}
