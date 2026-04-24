import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/connectivity_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';

// ─── Diagnostic: end-to-end bridge ping ──────────────────────────────────────

/// Sends a getInfo command through the Firestore relay (the same path
/// CloudRelayRepository uses) and logs the full round-trip result.
///
/// This is a TEMPORARY diagnostic — remove before release.
Future<void> debugBridgePing({
  required String controllerIp,
  required String? userId,
  required String? controllerId,
  required String webhookUrl,
}) async {
  final sw = Stopwatch()..start();
  final tag = '🩺 debugBridgePing';

  if (userId == null) {
    debugPrint('$tag: ABORT — no userId (not signed in)');
    return;
  }

  final commandsRef = FirebaseFirestore.instance
      .collection('users')
      .doc(userId)
      .collection('commands');

  final firestorePath = 'users/$userId/commands';
  debugPrint('$tag: sending getInfo via Firestore relay');
  debugPrint('$tag: firestorePath=$firestorePath');
  debugPrint('$tag: controllerIp=$controllerIp, controllerId=$controllerId');
  debugPrint('$tag: webhookUrl=${webhookUrl.isEmpty ? "(none — bridge mode)" : webhookUrl}');

  try {
    // Write the command — identical structure to CloudRelayRepository
    final docRef = await commandsRef.add({
      'type': 'getInfo',
      'payload': '{}',
      'controllerId': controllerId ?? '',
      'controllerIp': controllerIp,
      'webhookUrl': webhookUrl,
      'createdAt': FieldValue.serverTimestamp(),
      'status': 'pending',
    });

    final commandId = docRef.id;
    debugPrint('$tag: command queued — id=$commandId, elapsed=${sw.elapsedMilliseconds}ms');

    // Poll for result (same cadence as CloudRelayRepository: 500ms × 60 = 30s)
    for (var i = 0; i < 60; i++) {
      await Future.delayed(const Duration(milliseconds: 500));
      final snap = await docRef.get();
      final data = snap.data();
      final status = data?['status'] as String?;

      if (status == 'completed') {
        sw.stop();
        final result = data?['result'];
        final resultStr = result is Map ? jsonEncode(result) : '$result';
        // Truncate if huge
        final preview = resultStr.length > 500
            ? '${resultStr.substring(0, 500)}…'
            : resultStr;
        debugPrint('$tag: ✅ status=completed, roundTrip=${sw.elapsedMilliseconds}ms');
        debugPrint('$tag: response body=$preview');
        await docRef.delete(); // clean up
        return;
      }

      if (status == 'failed') {
        sw.stop();
        final error = data?['error'] as String? ?? 'unknown';
        debugPrint('$tag: ❌ status=failed, roundTrip=${sw.elapsedMilliseconds}ms');
        debugPrint('$tag: error=$error');
        await docRef.delete();
        return;
      }

      // Still pending/executing — keep polling
      if (i % 10 == 9) {
        debugPrint('$tag: still waiting… status=$status, elapsed=${sw.elapsedMilliseconds}ms');
      }
    }

    // Timeout
    sw.stop();
    debugPrint('$tag: ⏰ TIMEOUT after ${sw.elapsedMilliseconds}ms — bridge never responded');
    debugPrint('$tag: command left as timeout in Firestore for inspection (id=$commandId)');
    await docRef.update({'status': 'timeout'});
  } catch (e) {
    sw.stop();
    debugPrint('$tag: 💥 EXCEPTION after ${sw.elapsedMilliseconds}ms — $e');
  }
}

// ─── Remote access mode ──────────────────────────────────────────────────────

/// How remote commands are relayed to the WLED controller.
enum RemoteAccessMode {
  /// ESP32 bridge on local network polls Firestore for commands.
  /// No port forwarding or Dynamic DNS needed.
  bridge,

  /// Cloud Function forwards commands to a webhook URL.
  /// Requires Dynamic DNS + port forwarding.
  webhook,
}

// ─── Health check state ───────────────────────────────────────────────────────

enum _WebhookStatus { idle, checking, connected, disconnected }

class _WebhookCheckResult {
  final _WebhookStatus status;
  /// Plain-English error message, null when status == connected.
  final String? errorMessage;
  final DateTime? checkedAt;

  const _WebhookCheckResult(this.status, {this.errorMessage, this.checkedAt});
}

// ─── Screen ───────────────────────────────────────────────────────────────────

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

class _RemoteAccessScreenState extends ConsumerState<RemoteAccessScreen>
    with WidgetsBindingObserver {
  final _webhookUrlController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  bool _isSaving = false;
  bool _isDetectingNetwork = false;

  _WebhookCheckResult _webhookCheck =
      const _WebhookCheckResult(_WebhookStatus.idle);

  _WebhookCheckResult _bridgeCheck =
      const _WebhookCheckResult(_WebhookStatus.idle);

  Timer? _pollingTimer;

  /// The current remote access mode — derived from user profile on load.
  RemoteAccessMode _mode = RemoteAccessMode.bridge;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      final url = profile?.webhookUrl;

      // Set mode for UI regardless — drives which card is shown.
      if (url != null && url.isNotEmpty) {
        _webhookUrlController.text = url;
        _mode = RemoteAccessMode.webhook;
      } else {
        _mode = RemoteAccessMode.bridge;
      }

      // Only run network health checks and diagnostics when remote
      // access is actually enabled. Users on local WiFi with remote
      // access off shouldn't incur Firestore / webhook traffic.
      if (profile?.remoteAccessEnabled == true) {
        if (_mode == RemoteAccessMode.webhook) {
          _runHealthCheck(url!);
        } else {
          _runBridgeCheck();
        }
        _startPolling();

        // ── Diagnostic: fire an end-to-end bridge ping on screen open ──
        final userId = ref.read(authStateProvider).maybeWhen(
              data: (u) => u?.uid,
              orElse: () => null,
            );
        final controllerId = ref.read(selectedControllerIdProvider);
        final controllerIp = ref.read(selectedDeviceIpProvider) ?? '';
        debugBridgePing(
          controllerIp: controllerIp,
          userId: userId,
          controllerId: controllerId,
          webhookUrl: url ?? '',
        );
      }
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (u) => u,
        orElse: () => null,
      );
      if (profile?.remoteAccessEnabled != true) return;
      if (_mode == RemoteAccessMode.webhook) {
        final url = _webhookUrlController.text.trim();
        if (url.isNotEmpty) _runHealthCheck(url);
      } else {
        _runBridgeCheck();
      }
    }
  }

  @override
  void dispose() {
    _pollingTimer?.cancel();
    _webhookUrlController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  // ── Polling ────────────────────────────────────────────────────────────────

  void _startPolling() {
    final profile = ref.read(currentUserProfileProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );
    if (profile?.remoteAccessEnabled != true) return;
    _pollingTimer?.cancel();
    _pollingTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (_mode == RemoteAccessMode.webhook) {
        final url = _webhookUrlController.text.trim();
        if (url.isNotEmpty) _runHealthCheck(url);
      } else {
        _runBridgeCheck();
      }
    });
  }

  // ── Health check ───────────────────────────────────────────────────────────

  Future<void> _runHealthCheck(String baseUrl) async {
    if (!mounted) return;

    setState(() {
      _webhookCheck = const _WebhookCheckResult(_WebhookStatus.checking);
    });

    final result = await _checkWebhook(baseUrl);

    if (!mounted) return;
    setState(() => _webhookCheck = result);

    // Publish to shared provider so the home screen can see bridge state.
    ref.read(bridgeReachableProvider.notifier).state =
        result.status == _WebhookStatus.connected;
  }

  /// Performs a real HTTP GET to `<baseUrl>/json/info` with a 5-second timeout.
  /// Returns a result with plain-English error messages distinguishing:
  ///   - DNS failure (can't resolve the domain)
  ///   - Connection refused (host reachable but port closed)
  ///   - Timeout (slow network or firewall drop)
  static Future<_WebhookCheckResult> _checkWebhook(String baseUrl) async {
    final sanitised = baseUrl.endsWith('/') ? baseUrl : '$baseUrl/';
    final uri = Uri.tryParse('${sanitised}json/info');
    if (uri == null) {
      return const _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'The URL you entered doesn\'t look valid. '
            'Check for typos and try again.',
      );
    }

    try {
      final response = await http
          .get(uri, headers: {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 5));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        return _WebhookCheckResult(
          _WebhookStatus.connected,
          checkedAt: DateTime.now(),
        );
      }

      return _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'Your controller responded but returned an unexpected '
            'status (${response.statusCode}). Check your port forwarding.',
      );
    } on TimeoutException {
      return const _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'The connection timed out. Your network may be slow, '
            'or a firewall is blocking the request.',
      );
    } on SocketException catch (e) {
      final msg = e.message.toLowerCase();
      if (msg.contains('failed host lookup') ||
          msg.contains('no address associated') ||
          msg.contains('nodename nor servname')) {
        return const _WebhookCheckResult(
          _WebhookStatus.disconnected,
          errorMessage: 'Can\'t find that address. Check that your DuckDNS '
              '(or Dynamic DNS) domain is spelled correctly and is active.',
        );
      }
      if (msg.contains('connection refused') || e.osError?.errorCode == 111) {
        return const _WebhookCheckResult(
          _WebhookStatus.disconnected,
          errorMessage: 'Address found but the connection was refused. '
              'Check that port forwarding in your router points to your '
              'Lumina controller.',
        );
      }
      return _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'Network error — couldn\'t reach your controller. '
            '(${e.message})',
      );
    } catch (e) {
      return _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'Unexpected error: $e',
      );
    }
  }

  // ── Bridge health check ────────────────────────────────────────────────────

  /// Tests bridge connectivity by writing a lightweight ping command to
  /// Firestore and checking if the bridge picks it up within 10 seconds.
  Future<void> _runBridgeCheck() async {
    if (!mounted) return;

    setState(() {
      _bridgeCheck = const _WebhookCheckResult(_WebhookStatus.checking);
    });

    final result = await _checkBridge();
    if (!mounted) return;
    setState(() => _bridgeCheck = result);

    // Publish to shared provider so the home screen can see bridge state.
    ref.read(bridgeReachableProvider.notifier).state =
        result.status == _WebhookStatus.connected;
  }

  Future<_WebhookCheckResult> _checkBridge() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return const _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'Not signed in.',
      );
    }

    try {
      final commandsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('commands');

      // Write a ping command (no webhook URL → bridge mode)
      final docRef = await commandsRef.add({
        'type': 'getInfo',
        'payload': '{}',
        'controllerId': ref.read(selectedControllerIdProvider) ?? '',
        'controllerIp': ref.read(selectedDeviceIpProvider) ?? '',
        'webhookUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      // Poll for up to 10 seconds
      for (var i = 0; i < 20; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        final snap = await docRef.get();
        final status = snap.data()?['status'] as String?;
        if (status == 'completed') {
          // Clean up test command
          await docRef.delete();
          return _WebhookCheckResult(
            _WebhookStatus.connected,
            checkedAt: DateTime.now(),
          );
        }
        if (status == 'failed') {
          final error = snap.data()?['error'] as String? ?? 'Unknown error';
          await docRef.delete();
          return _WebhookCheckResult(
            _WebhookStatus.disconnected,
            errorMessage: 'Bridge reached controller but got an error: $error',
          );
        }
      }

      // Timeout — bridge didn't pick it up
      await docRef.update({'status': 'timeout'});
      return const _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'No response from ESP32 Bridge within 10 seconds. '
            'Check that the bridge is powered on and connected to WiFi.',
      );
    } catch (e) {
      return _WebhookCheckResult(
        _WebhookStatus.disconnected,
        errorMessage: 'Error testing bridge: $e',
      );
    }
  }

  // ── Save / toggle / detect ─────────────────────────────────────────────────

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

      final url = _webhookUrlController.text.trim();

      await userService.updateRemoteAccessConfig(userId, webhookUrl: url);
      _showSnackBar('Webhook URL saved');

      // Immediately validate — do not show "Connected" from the saved URL alone.
      _runHealthCheck(url);
    } catch (e) {
      _showSnackBar('Failed to save: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  Future<void> _detectHomeNetwork() async {
    setState(() => _isDetectingNetwork = true);

    try {
      // Android gates WiFi SSID reads behind location permission. iOS
      // requires precise location + Local Network entitlement. Request
      // location up front so getCurrentSsid() has a chance to succeed.
      final status = await Permission.locationWhenInUse.request();
      if (!status.isGranted) {
        _showSnackBar(
          'Location permission is required to detect your WiFi '
          'network name. Please grant it in Settings.',
          isError: true,
        );
        return;
      }

      final connectivityService = ref.read(connectivityServiceProvider);
      final currentSsid = await connectivityService.getCurrentSsid();

      if (currentSsid == null || currentSsid.isEmpty) {
        _showSnackBar(
          'Could not read WiFi name. Make sure WiFi is enabled and '
          'you are connected to your home network.',
          isError: true,
        );
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
      if (mounted) setState(() => _isDetectingNetwork = false);
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

      // Start / stop background network activity in lockstep with the flag.
      if (enabled) {
        _startPolling();
        if (_mode == RemoteAccessMode.bridge) {
          _runBridgeCheck();
        } else {
          final url = _webhookUrlController.text.trim();
          if (url.isNotEmpty) _runHealthCheck(url);
        }
      } else {
        _pollingTimer?.cancel();
        setState(() {
          _bridgeCheck = const _WebhookCheckResult(_WebhookStatus.idle);
          _webhookCheck = const _WebhookCheckResult(_WebhookStatus.idle);
        });
      }

      _showSnackBar(
          enabled ? 'Remote access enabled' : 'Remote access disabled');
    } catch (e) {
      _showSnackBar('Failed to update: $e', isError: true);
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
      setState(() {
        _webhookCheck = const _WebhookCheckResult(_WebhookStatus.idle);
      });
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

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final userProfile = ref.watch(currentUserProfileProvider).maybeWhen(
          data: (u) => u,
          orElse: () => null,
        );

    // Populate controller when profile loads (handles async timing).
    ref.listen(currentUserProfileProvider, (_, next) {
      final url =
          next.maybeWhen(data: (u) => u?.webhookUrl, orElse: () => null);
      if (url != null && url != _webhookUrlController.text) {
        _webhookUrlController.text = url;
        // Don't auto-run check here — initState already handles the first load.
      }
    });

    final connectivityStatus = ref.watch(wledConnectivityStatusProvider).maybeWhen(
          data: (s) => s,
          orElse: () => ConnectivityStatus.local,
        );
    final isRemote = ref.watch(isRemoteModeProvider);

    final isEnabled = userProfile?.remoteAccessEnabled ?? false;
    // Prefer the encrypted field (new profiles); fall back to the plaintext
    // `homeSsid` field for legacy profiles written before Option B landed.
    // Never used for comparison — that runs off `homeSsidHash`.
    final String? displaySsid = userProfile?.homeSsidEncrypted != null
        ? EncryptionService.decryptString(userProfile!.homeSsidEncrypted!)
        : userProfile?.homeSsid;
    final hasWebhookUrl = userProfile?.webhookUrl?.isNotEmpty ?? false;

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Remote Access'),
        actions: [
          if (hasWebhookUrl || displaySsid != null)
            IconButton(
              tooltip: 'Clear Configuration',
              icon: const Icon(Icons.delete_outline),
              onPressed: _clearConfiguration,
            ),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
        children: [
          _buildNetworkStatusCard(connectivityStatus, isRemote, isEnabled),
          const SizedBox(height: 16),

          // Connection status card (bridge or webhook)
          if (_mode == RemoteAccessMode.bridge)
            _buildBridgeStatusCard()
          else
            _buildWebhookStatusCard(),
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

          // Connection Mode selector
          _buildModeSelector(),
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
                      Text('Home Network',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Save your current WiFi network as your home network. '
                    'The app will use local connections when on this network.',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 12),
                  if (displaySsid != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.wifi, color: NexGenPalette.cyan, size: 20),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              displaySsid,
                              style: TextStyle(
                                color: NexGenPalette.cyan,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Icon(Icons.check_circle,
                              color: NexGenPalette.cyan, size: 20),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed:
                          _isDetectingNetwork ? null : _detectHomeNetwork,
                      icon: _isDetectingNetwork
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.wifi_find),
                      label: Text(displaySsid == null
                          ? 'Detect Home Network'
                          : 'Update Home Network'),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Webhook URL section (only in webhook mode)
          if (_mode == RemoteAccessMode.webhook) ...[
            const SizedBox(height: 16),
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
                          Text('Webhook URL',
                              style: Theme.of(context).textTheme.titleMedium),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'Enter your Dynamic DNS URL that points to your home network. '
                        'This is how the cloud will reach your Lumina controller.',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                      const SizedBox(height: 12),
                      TextFormField(
                        controller: _webhookUrlController,
                        decoration: const InputDecoration(
                          labelText: 'Webhook URL',
                          hintText: 'https://myhome.duckdns.org:8080',
                          prefixIcon: Icon(Icons.https),
                        ),
                        keyboardType: TextInputType.url,
                        autocorrect: false,
                        validator: (value) {
                          if (value == null || value.trim().isEmpty) {
                            return 'Please enter a webhook URL';
                          }
                          final url = value.trim();
                          if (!url.startsWith('http://') &&
                              !url.startsWith('https://')) {
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
                              onPressed:
                                  _webhookCheck.status == _WebhookStatus.checking
                                      ? null
                                      : () {
                                          final url = _webhookUrlController.text
                                              .trim();
                                          if (url.isEmpty) {
                                            _showSnackBar(
                                                'Please enter a webhook URL first',
                                                isError: true);
                                            return;
                                          }
                                          _runHealthCheck(url);
                                        },
                              icon: _webhookCheck.status ==
                                      _WebhookStatus.checking
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(
                                          strokeWidth: 2),
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
            _buildSetupGuide(context),
          ],

          // Bridge mode info card + setup button
          if (_mode == RemoteAccessMode.bridge) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: () => context.push(AppRoutes.bridgeSetup),
                icon: Icon(
                  userProfile?.bridgePaired == true
                      ? Icons.settings
                      : Icons.add_link,
                  color: Colors.black,
                ),
                label: Text(
                  userProfile?.bridgePaired == true
                      ? 'Reconfigure Bridge'
                      : 'Set Up Bridge',
                ),
              ),
            ),
            if (userProfile?.bridgePaired == true &&
                userProfile?.bridgeIp != null) ...[
              const SizedBox(height: 8),
              Card(
                child: ListTile(
                  leading: Icon(Icons.developer_board,
                      color: NexGenPalette.cyan),
                  title: const Text('Paired Bridge'),
                  subtitle: Text(userProfile!.bridgeIp!),
                  trailing: Icon(Icons.check_circle,
                      color: Colors.green, size: 20),
                ),
              ),
            ],
            const SizedBox(height: 16),
            _buildBridgeInfoCard(context),
          ],
        ],
      ),
    );
  }

  // ── Mode selector ─────────────────────────────────────────────────────────

  Widget _buildModeSelector() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_input_component, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Text('Connection Mode',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _ModeOption(
              icon: Icons.developer_board,
              title: 'ESP32 Bridge',
              subtitle: 'No port forwarding needed. Works with any ISP.',
              selected: _mode == RemoteAccessMode.bridge,
              onTap: () {
                setState(() => _mode = RemoteAccessMode.bridge);
                _runBridgeCheck();
              },
            ),
            const SizedBox(height: 8),
            _ModeOption(
              icon: Icons.webhook,
              title: 'Webhook (Dynamic DNS)',
              subtitle: 'Requires port forwarding and a public IP.',
              selected: _mode == RemoteAccessMode.webhook,
              onTap: () {
                setState(() => _mode = RemoteAccessMode.webhook);
                final url = _webhookUrlController.text.trim();
                if (url.isNotEmpty) _runHealthCheck(url);
              },
            ),
          ],
        ),
      ),
    );
  }

  // ── Status cards ───────────────────────────────────────────────────────────

  /// Bridge status card.
  /// Uses manual test result if available, otherwise falls back to the
  /// automatic bridge health check result from [bridgeReachableProvider].
  Widget _buildBridgeStatusCard() {
    final check = _bridgeCheck;

    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    switch (check.status) {
      case _WebhookStatus.checking:
        icon = Icons.sync;
        color = Colors.amber;
        title = 'Testing Bridge...';
        subtitle = 'Sending a test command via Firestore.';
        break;
      case _WebhookStatus.connected:
        final ago = check.checkedAt != null
            ? _formatAge(check.checkedAt!)
            : '';
        icon = Icons.check_circle;
        color = Colors.green;
        title = 'Bridge Connected';
        subtitle = ago.isEmpty
            ? 'Your ESP32 bridge is online and responding.'
            : 'Last confirmed $ago.';
        break;
      case _WebhookStatus.disconnected:
        icon = Icons.error_outline;
        color = Colors.red;
        title = 'Bridge Not Responding';
        subtitle = check.errorMessage ?? 'Could not reach the ESP32 bridge.';
        break;
      case _WebhookStatus.idle:
        // No manual test run yet — use automatic health check result.
        final bridgeState = ref.watch(bridgeReachableProvider);
        if (bridgeState == true) {
          icon = Icons.check_circle;
          color = Colors.green;
          title = 'Bridge Connected';
          subtitle = 'Confirmed via automatic health check.';
        } else if (bridgeState == false) {
          icon = Icons.warning_amber_rounded;
          color = Colors.amber;
          title = 'Relay Online — Waiting for Bridge';
          subtitle = 'Firestore is reachable but the ESP32 bridge has not '
              'responded. Check that the bridge is powered on and connected to WiFi.';
        } else {
          icon = Icons.developer_board;
          color = Colors.grey;
          title = 'Bridge Status Unknown';
          subtitle = 'Tap "Test Bridge" to check connectivity.';
        }
        break;
    }

    final user = FirebaseAuth.instance.currentUser;

    return Column(
      children: [
        _StatusCard(icon: icon, color: color, title: title, subtitle: subtitle),
        const SizedBox(height: 8),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: _bridgeCheck.status == _WebhookStatus.checking
                ? null
                : _runBridgeCheck,
            icon: _bridgeCheck.status == _WebhookStatus.checking
                ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.network_check),
            label: const Text('Test Bridge'),
          ),
        ),
        if (user != null) ...[
          const SizedBox(height: 12),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Icon(Icons.person_outline, color: NexGenPalette.cyan, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Your User ID',
                            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                                  color: Colors.grey,
                                )),
                        const SizedBox(height: 2),
                        SelectableText(
                          user.uid,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.copy, size: 18),
                    tooltip: 'Copy User ID',
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: user.uid));
                      _showSnackBar('User ID copied to clipboard');
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  /// Info card explaining bridge mode.
  Widget _buildBridgeInfoCard(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.info_outline, color: NexGenPalette.violet),
                const SizedBox(width: 8),
                Text('How Bridge Mode Works',
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 12),
            _buildGuideStep(
              context,
              1,
              'ESP32 bridge on your network',
              'A small ESP32 device plugged in at home stays connected '
                  'to your WiFi and monitors for commands.',
            ),
            _buildGuideStep(
              context,
              2,
              'Commands go through the cloud',
              'When you\'re away, the app writes commands to Firebase. '
                  'The bridge picks them up and sends them to your Lumina controller.',
            ),
            _buildGuideStep(
              context,
              3,
              'No port forwarding needed',
              'Unlike webhook mode, bridge mode works with any ISP '
                  'including T-Mobile, Starlink, and other CGNAT networks.',
            ),
          ],
        ),
      ),
    );
  }

  /// Top card: network location (home / away / offline) — unchanged logic.
  Widget _buildNetworkStatusCard(
      ConnectivityStatus status, bool isRemote, bool isEnabled) {
    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    switch (status) {
      case ConnectivityStatus.local:
        icon = Icons.home;
        color = Colors.green;
        title = 'On Home Network';
        subtitle = 'Using direct local connection to your Lumina controllers.';
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

    return _StatusCard(icon: icon, color: color, title: title, subtitle: subtitle);
  }

  /// Second card: actual webhook endpoint reachability.
  Widget _buildWebhookStatusCard() {
    final check = _webhookCheck;

    // Don't render the card at all when no URL has been entered/saved yet.
    if (check.status == _WebhookStatus.idle &&
        _webhookUrlController.text.trim().isEmpty) {
      return const SizedBox.shrink();
    }

    final IconData icon;
    final Color color;
    final String title;
    final String subtitle;

    switch (check.status) {
      case _WebhookStatus.checking:
        icon = Icons.sync;
        color = Colors.amber;
        title = 'Checking…';
        subtitle = 'Testing connection to your controller.';
        break;
      case _WebhookStatus.connected:
        final ago = check.checkedAt != null
            ? _formatAge(check.checkedAt!)
            : '';
        icon = Icons.check_circle;
        color = Colors.green;
        title = 'Connected';
        subtitle = ago.isEmpty
            ? 'Your controller is reachable remotely.'
            : 'Last confirmed $ago.';
        break;
      case _WebhookStatus.disconnected:
        icon = Icons.error_outline;
        color = Colors.red;
        title = 'Not Reachable';
        subtitle = check.errorMessage ?? 'Could not reach your controller.';
        break;
      case _WebhookStatus.idle:
        icon = Icons.help_outline;
        color = Colors.grey;
        title = 'Not Checked';
        subtitle = 'Tap "Test" to verify your webhook URL.';
        break;
    }

    return _StatusCard(icon: icon, color: color, title: title, subtitle: subtitle);
  }

  static String _formatAge(DateTime checkedAt) {
    final diff = DateTime.now().difference(checkedAt);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  // ── Setup guide ────────────────────────────────────────────────────────────

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
                Text('Setup Guide',
                    style: Theme.of(context).textTheme.titleMedium),
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
            _buildGuideStep(
              context,
              1,
              'Set up Dynamic DNS',
              'Create a free account with DuckDNS, No-IP, or similar service. '
                  'This gives you a domain that points to your home IP address.',
            ),
            _buildGuideStep(
              context,
              2,
              'Configure port forwarding',
              'In your router settings, forward an external port (e.g., 8080) '
                  'to your Lumina controller\'s local IP address on port 80.',
            ),
            _buildGuideStep(
              context,
              3,
              'Enter your webhook URL',
              'Use your Dynamic DNS domain with the forwarded port. '
                  'Example: https://myhome.duckdns.org:8080',
            ),
            _buildGuideStep(
              context,
              4,
              'Save your home network',
              'Connect to your home WiFi and tap "Detect Home Network" above. '
                  'This ensures the app uses direct connections when you\'re home.',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildGuideStep(
      BuildContext context, int step, String title, String description) {
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

// ─── Mode option radio tile ──────────────────────────────────────────────────

class _ModeOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  const _ModeOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected
                ? NexGenPalette.cyan
                : Colors.white.withValues(alpha: 0.1),
            width: selected ? 2 : 1,
          ),
          color: selected
              ? NexGenPalette.cyan.withValues(alpha: 0.1)
              : Colors.transparent,
        ),
        child: Row(
          children: [
            Icon(icon,
                color: selected ? NexGenPalette.cyan : Colors.grey, size: 24),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: selected ? NexGenPalette.cyan : null,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (selected)
              Icon(Icons.check_circle, color: NexGenPalette.cyan, size: 20),
          ],
        ),
      ),
    );
  }
}

// ─── Shared status card widget ────────────────────────────────────────────────

class _StatusCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String subtitle;

  const _StatusCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
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
}
