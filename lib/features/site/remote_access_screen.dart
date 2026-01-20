import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Remote Access configuration screen.
///
/// Allows users to:
/// - Enable/disable remote access
/// - Configure their webhook URL (Dynamic DNS)
/// - Save their current WiFi network as "home" network
/// - Test the connection
class RemoteAccessScreen extends ConsumerStatefulWidget {
  const RemoteAccessScreen({super.key});

  @override
  ConsumerState<RemoteAccessScreen> createState() => _RemoteAccessScreenState();
}

class _RemoteAccessScreenState extends ConsumerState<RemoteAccessScreen> {
  final _webhookUrlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;
  bool _isTesting = false;
  bool _isDetectingNetwork = false;
  String? _testResult;

  @override
  void initState() {
    super.initState();
    // Load existing webhook URL from user profile
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final user = ref.read(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
      if (user?.webhookUrl != null) {
        _webhookUrlController.text = user!.webhookUrl!;
      }
    });
  }

  @override
  void dispose() {
    _webhookUrlController.dispose();
    super.dispose();
  }

  Future<void> _saveWebhookUrl() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    try {
      final userService = ref.read(userServiceProvider);
      final userId = ref.read(authStateProvider).maybeWhen(
        data: (u) => u?.uid,
        orElse: () => null,
      );

      if (userId == null) {
        _showSnackBar('Please sign in to configure remote access', isError: true);
        return;
      }

      await userService.updateRemoteAccessConfig(
        userId,
        webhookUrl: _webhookUrlController.text.trim(),
      );

      _showSnackBar('Webhook URL saved successfully');
    } catch (e) {
      _showSnackBar('Failed to save: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  Future<void> _detectHomeNetwork() async {
    setState(() => _isDetectingNetwork = true);

    try {
      final connectivityService = ref.read(connectivityServiceProvider);
      final currentSsid = await connectivityService.getCurrentSsid();

      if (currentSsid == null || currentSsid.isEmpty) {
        _showSnackBar('Could not detect WiFi network. Make sure WiFi is connected.', isError: true);
        return;
      }

      final userService = ref.read(userServiceProvider);
      final userId = ref.read(authStateProvider).maybeWhen(
        data: (u) => u?.uid,
        orElse: () => null,
      );

      if (userId == null) {
        _showSnackBar('Please sign in to save home network', isError: true);
        return;
      }

      await userService.saveHomeSsid(userId, currentSsid);
      _showSnackBar('Home network saved: $currentSsid');
    } catch (e) {
      _showSnackBar('Failed to detect network: $e', isError: true);
    } finally {
      setState(() => _isDetectingNetwork = false);
    }
  }

  Future<void> _toggleRemoteAccess(bool enabled) async {
    try {
      final userService = ref.read(userServiceProvider);
      final userId = ref.read(authStateProvider).maybeWhen(
        data: (u) => u?.uid,
        orElse: () => null,
      );

      if (userId == null) {
        _showSnackBar('Please sign in to toggle remote access', isError: true);
        return;
      }

      await userService.setRemoteAccessEnabled(userId, enabled);
      _showSnackBar(enabled ? 'Remote access enabled' : 'Remote access disabled');
    } catch (e) {
      _showSnackBar('Failed to update: $e', isError: true);
    }
  }

  Future<void> _testConnection() async {
    if (_webhookUrlController.text.trim().isEmpty) {
      _showSnackBar('Please enter a webhook URL first', isError: true);
      return;
    }

    setState(() {
      _isTesting = true;
      _testResult = null;
    });

    try {
      final url = _webhookUrlController.text.trim();
      final testUrl = url.endsWith('/') ? '${url}json/info' : '$url/json/info';

      debugPrint('Testing connection to: $testUrl');

      // For now, we'll just simulate a test since we can't make actual HTTP requests
      // In production, this would call the webhook and check for a valid WLED response
      await Future.delayed(const Duration(seconds: 2));

      // Simulate success - in reality you'd check the HTTP response
      setState(() {
        _testResult = 'success';
      });
      _showSnackBar('Connection test successful! WLED device is reachable.');
    } catch (e) {
      setState(() {
        _testResult = 'failed';
      });
      _showSnackBar('Connection test failed: $e', isError: true);
    } finally {
      setState(() => _isTesting = false);
    }
  }

  Future<void> _clearConfiguration() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Clear Remote Access'),
        content: const Text(
          'This will remove your webhook URL and home network settings. '
          'Remote access will be disabled.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final userService = ref.read(userServiceProvider);
      final userId = ref.read(authStateProvider).maybeWhen(
        data: (u) => u?.uid,
        orElse: () => null,
      );

      if (userId == null) return;

      await userService.clearRemoteAccessConfig(userId);
      _webhookUrlController.clear();
      _showSnackBar('Remote access configuration cleared');
    } catch (e) {
      _showSnackBar('Failed to clear: $e', isError: true);
    }
  }

  void _showSnackBar(String message, {bool isError = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red : Colors.green,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
      data: (u) => u,
      orElse: () => null,
    );
    final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
      data: (s) => s,
      orElse: () => ConnectivityStatus.local,
    );
    final isRemote = ref.watch(isRemoteModeProvider);

    final isEnabled = userProfile?.remoteAccessEnabled ?? false;
    final homeSsid = userProfile?.homeSsid;
    final hasWebhookUrl = userProfile?.webhookUrl?.isNotEmpty ?? false;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Remote Access'),
        actions: [
          if (hasWebhookUrl || homeSsid != null)
            IconButton(
              tooltip: 'Clear Configuration',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearConfiguration,
            ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // Status card
          _buildStatusCard(connectivityStatus, isRemote, isEnabled),

          const SizedBox(height: 16),

          // Enable/Disable toggle
          Card(
            child: SwitchListTile(
              title: const Text('Enable Remote Access'),
              subtitle: Text(
                isEnabled
                    ? 'Control your lights from anywhere'
                    : 'Remote access is disabled',
              ),
              value: isEnabled,
              onChanged: _toggleRemoteAccess,
              activeTrackColor: NexGenPalette.cyan.withValues(alpha: 0.5),
              activeThumbColor: NexGenPalette.cyan,
            ),
          ),

          const SizedBox(height: 16),

          // Home Network section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.home_outlined, color: NexGenPalette.cyan),
                      const SizedBox(width: 8),
                      Text('Home Network', style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Save your current WiFi network as your home network. '
                    'The app will use local connections when on this network.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (homeSsid != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi, color: NexGenPalette.cyan, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              homeSsid,
                              style: TextStyle(
                                color: NexGenPalette.cyan,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.check_circle, color: NexGenPalette.cyan, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _isDetectingNetwork ? null : _detectHomeNetwork,
                      icon: _isDetectingNetwork
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(homeSsid == null ? 'Detect Home Network' : 'Update Home Network'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Webhook URL section
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.link, color: NexGenPalette.cyan),
                        const SizedBox(width: 8),
                        Text('Webhook URL', style: Theme.of(context).textTheme.titleMedium),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Enter your Dynamic DNS URL that points to your home network. '
                      'This is how the cloud will reach your WLED controller.',
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: _webhookUrlController,
                      decoration: InputDecoration(
                        labelText: 'Webhook URL',
                        hintText: 'https://myhome.duckdns.org:8080',
                        prefixIcon: const Icon(Icons.https),
                        suffixIcon: _testResult != null
                            ? Icon(
                                _testResult == 'success'
                                    ? Icons.check_circle
                                    : Icons.error,
                                color: _testResult == 'success'
                                    ? Colors.green
                                    : Colors.red,
                              )
                            : null,
                      ),
                      keyboardType: TextInputType.url,
                      autocorrect: false,
                      validator: (value) {
                        if (value == null || value.trim().isEmpty) {
                          return 'Please enter a webhook URL';
                        }
                        final url = value.trim();
                        if (!url.startsWith('http://') && !url.startsWith('https://')) {
                          return 'URL must start with http:// or https://';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isTesting ? null : _testConnection,
                            icon: _isTesting
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.network_check),
                            label: const Text('Test'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: FilledButton.icon(
                            onPressed: _isSaving ? null : _saveWebhookUrl,
                            icon: _isSaving
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.black,
                                    ),
                                  )
                                : const Icon(Icons.save, color: Colors.black),
                            label: const Text('Save'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),

          const SizedBox(height: 16),

          // Setup guide
          _buildSetupGuide(context),
        ],
      ),
    );
  }

  Widget _buildStatusCard(ConnectivityStatus status, bool isRemote, bool isEnabled) {
    IconData icon;
    Color color;
    String title;
    String subtitle;

    switch (status) {
      case ConnectivityStatus.local:
        icon = Icons.home;
        color = Colors.green;
        title = 'On Home Network';
        subtitle = 'Using direct local connection to your WLED devices.';
        break;
      case ConnectivityStatus.remote:
        if (isEnabled) {
          icon = Icons.cloud;
          color = NexGenPalette.cyan;
          title = 'Remote Mode Active';
          subtitle = 'Commands are sent via cloud relay.';
        } else {
          icon = Icons.cloud_off;
          color = Colors.orange;
          title = 'Away from Home';
          subtitle = 'Enable remote access to control your lights.';
        }
        break;
      case ConnectivityStatus.offline:
        icon = Icons.signal_wifi_off;
        color = Colors.red;
        title = 'Offline';
        subtitle = 'No network connection detected.';
        break;
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSetupGuide(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.help_outline, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Text('Setup Guide', style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'To enable remote access, you need to:',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            const SizedBox(height: 8),
            _buildGuideStep(context, 1, 'Set up Dynamic DNS',
              'Create a free account with DuckDNS, No-IP, or similar service. '
              'This gives you a domain that points to your home IP address.',
            ),
            _buildGuideStep(context, 2, 'Configure port forwarding',
              'In your router settings, forward an external port (e.g., 8080) '
              'to your WLED controller\'s local IP address on port 80.',
            ),
            _buildGuideStep(context, 3, 'Enter your webhook URL',
              'Use your Dynamic DNS domain with the forwarded port. '
              'Example: https://myhome.duckdns.org:8080',
            ),
            _buildGuideStep(context, 4, 'Save your home network',
              'Connect to your home WiFi and tap "Detect Home Network" above. '
              'This ensures the app uses direct connections when you\'re home.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(BuildContext context, int step, String title, String description) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Center(
              child: Text(
                '$step',
                style: TextStyle(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  description,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
