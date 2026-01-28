import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/nav.dart';
import 'package:url_launcher/url_launcher.dart';

/// Placeholder for WLED WebView WiFi setup.
/// The webview_flutter package is not included, so this screen
/// provides a fallback that launches the WLED config in the system browser.
class WledWebViewSetup extends StatelessWidget {
  const WledWebViewSetup({super.key});

  Future<void> _launchWledConfig() async {
    final uri = Uri.parse('http://4.3.2.1/settings/wifi');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('WLED WiFi Setup'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.pop(),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.wifi_tethering,
              size: 80,
              color: Colors.cyan,
            ),
            const SizedBox(height: 24),
            const Text(
              'Configure WLED WiFi',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              'Connect to your WLED device\'s WiFi network (WLED-AP), then tap the button below to open the WiFi configuration page in your browser.',
              style: TextStyle(fontSize: 16, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: _launchWledConfig,
              icon: const Icon(Icons.open_in_browser),
              label: const Text('Open WLED WiFi Settings'),
            ),
            const SizedBox(height: 16),
            const Text(
              'After saving your WiFi settings, the controller will reboot and connect to your network.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            OutlinedButton(
              onPressed: () => context.go(AppRoutes.controllersSettings),
              child: const Text('Done - Go to My Controllers'),
            ),
          ],
        ),
      ),
    );
  }
}
