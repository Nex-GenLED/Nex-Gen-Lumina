import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/services/bridge_api_client.dart';
import 'package:nexgen_command/services/bridge_discovery_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Three-step bridge setup wizard:
///   1. Discover — find the bridge on the local network
///   2. Pair — send userId + WLED IP to the bridge
///   3. Verify — confirm the round-trip works
class BridgeSetupScreen extends ConsumerStatefulWidget {
  const BridgeSetupScreen({super.key});

  @override
  ConsumerState<BridgeSetupScreen> createState() => _BridgeSetupScreenState();
}

enum _Step { discover, pair, verify }

class _BridgeSetupScreenState extends ConsumerState<BridgeSetupScreen> {
  _Step _step = _Step.discover;

  // Discovery
  List<BridgeEndpoint> _bridges = [];
  bool _scanning = false;
  final _manualIpController = TextEditingController();

  // Selected bridge
  BridgeApiClient? _client;
  BridgeInfo? _bridgeInfo;
  String _bridgeIp = '';

  // Pair step
  bool _pairing = false;
  String? _pairError;

  // Verify step
  bool _verifying = false;
  bool _verified = false;
  String? _verifyError;

  @override
  void initState() {
    super.initState();
    _startDiscovery();
  }

  @override
  void dispose() {
    _manualIpController.dispose();
    super.dispose();
  }

  // ── Step 1: Discovery ─────────────────────────────────────────────────────

  Future<void> _startDiscovery() async {
    setState(() {
      _scanning = true;
      _bridges = [];
    });

    try {
      final service = ref.read(bridgeDiscoveryServiceProvider);
      final results = await service.discover();
      if (mounted) {
        setState(() {
          _bridges = results;
          _scanning = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _scanning = false);
    }
  }

  Future<void> _selectBridge(String ip) async {
    setState(() {
      _bridgeIp = ip;
      _client = BridgeApiClient.fromIp(ip);
    });

    // Fetch bridge info to confirm it's a Lumina device
    final info = await _client!.getInfo();
    if (!mounted) return;

    if (info == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not reach $ip — is the bridge powered on?'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Hijack protection: if this bridge is already paired to a different
    // Nex-Gen account, require explicit confirmation before continuing.
    // A null status (bridge unreachable for /status) is non-fatal — the
    // Verify step will catch it later.
    final status = await _client!.getStatus();
    if (!mounted) return;

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (status != null &&
        status.paired &&
        status.userId.isNotEmpty &&
        status.userId != currentUid) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Bridge already paired'),
          content: const Text(
            'This bridge is currently paired to a different Nex-Gen '
            'account. Continuing will transfer the bridge to your '
            'account and stop service for the previous owner.\n\n'
            'Continue only if you are the authorized installer for '
            'this bridge.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(ctx).pop(true),
              child: const Text('Transfer to my account'),
            ),
          ],
        ),
      );
      if (!mounted) return;
      if (confirmed != true) return;
    }

    setState(() {
      _bridgeInfo = info;
      _step = _Step.pair;
    });
  }

  void _useManualIp() {
    final ip = _manualIpController.text.trim();
    if (ip.isEmpty) return;
    _selectBridge(ip);
  }

  // ── Step 2: Pair ──────────────────────────────────────────────────────────

  Future<void> _doPair() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controllerIp = ref.read(selectedDeviceIpProvider);
    if (controllerIp == null || controllerIp.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'No lighting controller selected. Choose a controller in '
            'Site Setup before pairing a bridge.',
          ),
        ),
      );
      return;
    }

    setState(() {
      _pairing = true;
      _pairError = null;
    });

    // Send pair request
    final paired = await _client!.pair(
      userId: user.uid,
      wledIp: controllerIp,
    );

    if (!mounted) return;

    if (!paired) {
      setState(() {
        _pairing = false;
        _pairError = 'Pair request failed. Check the bridge is reachable.';
      });
      return;
    }

    // Send auth credentials
    final authed = await _client!.authenticate(
      email: 'bridge@lumina.local',
      password: 'bridge@lumina.local',
    );

    if (!mounted) return;

    if (!authed) {
      setState(() {
        _pairing = false;
        _pairError = 'Auth request failed. The bridge may need a firmware update.';
      });
      return;
    }

    // Save bridge IP to user profile
    try {
      final userService = ref.read(userServiceProvider);
      await userService.saveBridgeConfig(user.uid, bridgeIp: _bridgeIp);
    } catch (e) {
      debugPrint('Failed to save bridge config to Firestore: $e');
    }

    setState(() {
      _pairing = false;
      _step = _Step.verify;
    });

    _doVerify();
  }

  // ── Step 3: Verify ────────────────────────────────────────────────────────

  BridgeStatus? _lastStatus;

  Future<void> _doVerify() async {
    setState(() {
      _verifying = true;
      _verifyError = null;
      _verified = false;
      _lastStatus = null;
    });

    // Check bridge status endpoint first
    final status = await _client!.getStatus();
    if (!mounted) return;

    _lastStatus = status;

    if (status == null) {
      setState(() {
        _verifying = false;
        _verifyError = 'Could not reach bridge at $_bridgeIp. Is it powered on?';
      });
      return;
    }

    if (!status.paired) {
      setState(() {
        _verifying = false;
        _verifyError = 'Bridge reports it is not paired. Try going back and re-pairing.';
      });
      return;
    }

    if (!status.authenticated) {
      setState(() {
        _verifying = false;
        _verifyError =
            'Bridge is paired but NOT authenticated with Firebase.\n\n'
            'The bridge@lumina.local account may not exist in Firebase Auth. '
            'Create it in the Firebase Console → Authentication → Add User, '
            'then re-run the pairing step.';
      });
      return;
    }

    // Now test the Firestore round-trip
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() {
        _verifying = false;
        _verifyError = 'Not signed in.';
      });
      return;
    }

    try {
      final commandsRef = FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('commands');

      final docRef = await commandsRef.add({
        'type': 'ping',
        'payload': '{}',
        'controllerId': '',
        'controllerIp': ref.read(selectedDeviceIpProvider) ?? '',
        'webhookUrl': '',
        'createdAt': FieldValue.serverTimestamp(),
        'status': 'pending',
      });

      // Poll for up to 15 seconds
      for (var i = 0; i < 30; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        if (!mounted) return;
        final snap = await docRef.get();
        final s = snap.data()?['status'] as String?;
        if (s == 'completed') {
          await docRef.delete();
          setState(() {
            _verifying = false;
            _verified = true;
          });
          return;
        }
        if (s == 'failed') {
          final error = snap.data()?['error'] as String? ?? 'Unknown error';
          await docRef.delete();
          setState(() {
            _verifying = false;
            _verifyError = 'Bridge command failed: $error';
          });
          return;
        }
      }

      // Timed out — re-fetch bridge status for diagnostics
      final refreshed = await _client!.getStatus();
      _lastStatus = refreshed;
      await docRef.update({'status': 'timeout'});

      final diag = StringBuffer(
        'Bridge did not respond within 15 seconds.\n\n',
      );
      if (refreshed != null) {
        diag.writeln('Bridge diagnostics:');
        diag.writeln('  WiFi: ${refreshed.wifi ? "connected" : "DISCONNECTED"}');
        diag.writeln('  Firebase Auth: ${refreshed.authenticated ? "OK" : "FAILED"}');
        diag.writeln('  Paired: ${refreshed.paired}');
        diag.writeln('  User ID: ${refreshed.userId.isNotEmpty ? refreshed.userId.substring(0, 8) + "..." : "(empty)"}');
        diag.writeln('  Controller IP: ${refreshed.wledIp}');
        diag.writeln('  Commands processed: ${refreshed.commands}');
        diag.writeln('  Errors: ${refreshed.errors}');
        diag.writeln('  Uptime: ${refreshed.uptime}s');
      } else {
        diag.writeln('Could not reach bridge for diagnostics.');
      }

      setState(() {
        _verifying = false;
        _verifyError = diag.toString();
      });
    } catch (e) {
      setState(() {
        _verifying = false;
        _verifyError = 'Verification error: $e';
      });
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Bridge Setup'),
      ),
      body: ListView(
        padding: EdgeInsets.fromLTRB(16, 16, 16, navBarTotalHeight(context)),
        children: [
          // Step indicator
          _buildStepIndicator(),
          const SizedBox(height: 24),
          // Step content
          if (_step == _Step.discover) _buildDiscoverStep(),
          if (_step == _Step.pair) _buildPairStep(),
          if (_step == _Step.verify) _buildVerifyStep(),
        ],
      ),
    );
  }

  Widget _buildStepIndicator() {
    return Row(
      children: [
        _StepDot(
          label: 'Find',
          active: _step == _Step.discover,
          done: _step.index > _Step.discover.index,
        ),
        Expanded(child: Divider(color: NexGenPalette.cyan.withValues(alpha: 0.3))),
        _StepDot(
          label: 'Pair',
          active: _step == _Step.pair,
          done: _step.index > _Step.pair.index,
        ),
        Expanded(child: Divider(color: NexGenPalette.cyan.withValues(alpha: 0.3))),
        _StepDot(
          label: 'Verify',
          active: _step == _Step.verify,
          done: _verified,
        ),
      ],
    );
  }

  // ── Discover step ─────────────────────────────────────────────────────────

  Widget _buildDiscoverStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.search, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Text('Find Your Bridge',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'Make sure your phone is on the same WiFi network as the bridge.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 16),

                if (_scanning)
                  const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Column(
                        children: [
                          CircularProgressIndicator(),
                          SizedBox(height: 12),
                          Text('Scanning for bridges...'),
                        ],
                      ),
                    ),
                  ),

                if (!_scanning && _bridges.isEmpty)
                  Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          Icon(Icons.wifi_find, size: 48, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text('No bridges found on this network.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _startDiscovery,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Scan Again'),
                          ),
                        ],
                      ),
                    ),
                  ),

                if (!_scanning && _bridges.isNotEmpty)
                  ..._bridges.map((b) => ListTile(
                        leading: Icon(Icons.developer_board,
                            color: NexGenPalette.cyan),
                        title: Text(b.name),
                        subtitle: Text(b.address.address),
                        trailing:
                            Icon(Icons.arrow_forward_ios, size: 16),
                        onTap: () => _selectBridge(b.address.address),
                      )),
              ],
            ),
          ),
        ),

        const SizedBox(height: 16),

        // Manual IP entry
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.edit, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Text('Enter IP Manually',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualIpController,
                        decoration: const InputDecoration(
                          labelText: 'Bridge IP Address',
                          hintText: '192.168.1.100',
                          prefixIcon: Icon(Icons.lan),
                        ),
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                          LengthLimitingTextInputFormatter(15),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _useManualIp,
                      child: const Text('Connect'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Pair step ─────────────────────────────────────────────────────────────

  Widget _buildPairStep() {
    final controllerIp = ref.watch(selectedDeviceIpProvider);
    final hasController = controllerIp != null && controllerIp.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bridge info card
        if (_bridgeInfo != null)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.developer_board, color: NexGenPalette.cyan),
                      const SizedBox(width: 8),
                      Text('Bridge Found',
                          style: Theme.of(context).textTheme.titleMedium),
                    ],
                  ),
                  const SizedBox(height: 12),
                  _InfoRow(label: 'Name', value: _bridgeInfo!.name),
                  _InfoRow(label: 'Version', value: _bridgeInfo!.version),
                  _InfoRow(label: 'IP', value: _bridgeInfo!.ip.isNotEmpty ? _bridgeInfo!.ip : _bridgeIp),
                  _InfoRow(label: 'mDNS', value: _bridgeInfo!.mdns),
                ],
              ),
            ),
          ),

        const SizedBox(height: 16),

        // Pairing config card
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.link, color: NexGenPalette.cyan),
                    const SizedBox(width: 8),
                    Text('Pair Bridge',
                        style: Theme.of(context).textTheme.titleMedium),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  'This will register the bridge with your account and point it '
                  'at your Lumina controller.',
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: 12),
                _InfoRow(
                  label: 'Controller Target',
                  value: hasController
                      ? controllerIp
                      : 'None selected — set up a controller first',
                ),
                const SizedBox(height: 16),

                if (_pairError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      children: [
                        const Icon(Icons.error_outline,
                            color: Colors.red, size: 20),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(_pairError!,
                              style: const TextStyle(color: Colors.red)),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),
                ],

                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed:
                        (_pairing || !hasController) ? null : _doPair,
                    icon: _pairing
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.black),
                          )
                        : const Icon(Icons.handshake, color: Colors.black),
                    label: Text(_pairing ? 'Pairing...' : 'Pair Bridge'),
                  ),
                ),

                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: TextButton(
                    onPressed: () => setState(() {
                      _step = _Step.discover;
                      _bridgeInfo = null;
                      _client = null;
                    }),
                    child: const Text('Back'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Verify step ───────────────────────────────────────────────────────────

  Widget _buildVerifyStep() {
    return Column(
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                if (_verifying) ...[
                  const CircularProgressIndicator(),
                  const SizedBox(height: 16),
                  const Text('Testing round-trip through Firestore...'),
                  const SizedBox(height: 8),
                  Text(
                    'The app sends a command to Firebase, the bridge picks it up '
                    'and responds.',
                    style: Theme.of(context).textTheme.bodySmall,
                    textAlign: TextAlign.center,
                  ),
                ],

                if (_verified) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.green.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle,
                        color: Colors.green, size: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Bridge is working!',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.green,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your ESP32 bridge at $_bridgeIp is paired and responding '
                    'to commands through Firestore.',
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: FilledButton.icon(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.done, color: Colors.black),
                      label: const Text('Done'),
                    ),
                  ),
                ],

                if (!_verifying && !_verified && _verifyError != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.15),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.warning_amber_rounded,
                        color: Colors.orange, size: 64),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Verification Issue',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _verifyError!,
                    style: Theme.of(context).textTheme.bodyMedium,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 24),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _doVerify,
                          icon: const Icon(Icons.refresh),
                          label: const Text('Retry'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: FilledButton(
                          onPressed: () => Navigator.of(context).pop(),
                          child: const Text('Done Anyway'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Helper widgets ──────────────────────────────────────────────────────────

class _StepDot extends StatelessWidget {
  final String label;
  final bool active;
  final bool done;

  const _StepDot({
    required this.label,
    required this.active,
    required this.done,
  });

  @override
  Widget build(BuildContext context) {
    final color = done
        ? Colors.green
        : active
            ? NexGenPalette.cyan
            : Colors.grey;

    return Column(
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            color: color.withValues(alpha: active || done ? 0.2 : 0.1),
            shape: BoxShape.circle,
            border: Border.all(color: color, width: active ? 2 : 1),
          ),
          child: Center(
            child: done
                ? Icon(Icons.check, color: color, size: 18)
                : Text(
                    label[0],
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11,
            color: color,
            fontWeight: active ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ],
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: Colors.grey),
            ),
          ),
          Expanded(
            child: Text(
              value.isEmpty ? '--' : value,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ],
      ),
    );
  }
}
