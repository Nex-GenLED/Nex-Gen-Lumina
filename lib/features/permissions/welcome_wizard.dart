import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/app_providers.dart';

/// Key stored in SharedPreferences to mark the welcome wizard as completed locally
const String kWelcomeCompletedKey = 'welcome_completed_v1';

/// Checks whether the welcome wizard has been completed.
/// First checks Firestore (for cross-device sync), falls back to SharedPreferences.
Future<bool> isWelcomeCompleted() async {
  try {
    // First, check Firestore if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final welcomeCompleted = doc.data()?['welcome_completed'] as bool?;
        if (welcomeCompleted == true) {
          // Also update local storage for offline access
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(kWelcomeCompletedKey, true);
          return true;
        }
      }
    }

    // Fall back to local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kWelcomeCompletedKey) ?? false;
  } catch (e) {
    debugPrint('Welcome completed check error: $e');
    // Fall back to local storage on error
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kWelcomeCompletedKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Marks the welcome wizard as completed in both Firestore and locally.
Future<void> markWelcomeCompleted() async {
  try {
    // Mark locally first
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWelcomeCompletedKey, true);

    // Then update Firestore if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'welcome_completed': true,
        'updated_at': Timestamp.now(),
      });
      debugPrint('Welcome wizard marked complete in Firestore');
    }
  } catch (e) {
    debugPrint('Mark welcome completed error: $e');
  }
}

/// Resets the welcome wizard status (for re-showing the tutorial)
Future<void> resetWelcomeWizard() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kWelcomeCompletedKey, false);
    debugPrint('Welcome wizard reset locally');
  } catch (e) {
    debugPrint('Reset welcome wizard error: $e');
  }
}

class WelcomeWizardPage extends StatefulWidget {
  const WelcomeWizardPage({super.key});

  @override
  State<WelcomeWizardPage> createState() => _WelcomeWizardPageState();
}

class _WelcomeWizardPageState extends State<WelcomeWizardPage> {
  final PageController _controller = PageController();
  bool _requesting = false;

  @override
  void initState() {
    super.initState();
    // Simulation Mode: skip the wizard entirely and go to dashboard.
    if (kSimulationMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await markWelcomeCompleted();
        } catch (_) {}
        if (!mounted) return;
        context.go(AppRoutes.dashboard);
      });
    }
  }

  Future<void> _requestNetwork() async {
    setState(() => _requesting = true);
    try {
      if (Platform.isAndroid) {
        // Request location (for network discovery) and nearby Wi‑Fi (Android 13+)
        final results = await [
          Permission.locationWhenInUse,
          Permission.nearbyWifiDevices,
        ].request();
        debugPrint('Network permission results: $results');
      } else if (Platform.isIOS) {
        // iOS Local Network prompt is triggered automatically on first mDNS call.
        // We simply inform the user here and continue.
      }
      if (!mounted) return;
      _controller.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeOut);
    } catch (e) {
      debugPrint('Network permission request error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to request network permissions')));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  Future<void> _requestCameraAndFinish() async {
    setState(() => _requesting = true);
    try {
      final status = await Permission.camera.request();
      debugPrint('Camera permission: $status');
      await markWelcomeCompleted();
      if (!mounted) return;
      context.go(AppRoutes.discovery);
    } catch (e) {
      debugPrint('Camera permission request error: $e');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to request camera permission')));
    } finally {
      if (mounted) setState(() => _requesting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Welcome')),
      body: PageView(
        controller: _controller,
        physics: const NeverScrollableScrollPhysics(),
        children: [
          _WizardPanel(
            icon: Icons.wifi_find,
            title: 'Local Network Access',
            description: 'To find your Nex-Gen Controller, we need access to your local network.'
                '\n\nAndroid: We request Location and Nearby Wi‑Fi.\n'
                'iOS: You\'ll see a Local Network prompt when we start discovery.',
            buttonText: 'Grant Network Access',
            onPressed: _requestNetwork,
            loading: _requesting,
          ),
          _WizardPanel(
            icon: Icons.photo_camera_back_outlined,
            title: 'Camera Access',
            description: 'To map your home for effects, we use the camera in AR.',
            buttonText: 'Grant Camera',
            onPressed: _requestCameraAndFinish,
            loading: _requesting,
          ),
        ],
      ),
    );
  }
}

class _WizardPanel extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final String buttonText;
  final VoidCallback onPressed;
  final bool loading;
  const _WizardPanel({
    required this.icon,
    required this.title,
    required this.description,
    required this.buttonText,
    required this.onPressed,
    required this.loading,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        const SizedBox(height: 12),
        Icon(icon, color: NexGenPalette.cyan, size: 52),
        const SizedBox(height: 16),
        Text(title, style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
        const Spacer(),
        FilledButton.icon(
          onPressed: loading ? null : onPressed,
          icon: loading ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.check_circle_outline),
          label: Text(buttonText),
        ),
      ]),
    );
  }
}
