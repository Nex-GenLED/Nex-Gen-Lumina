import 'dart:async';
import 'dart:io';

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
///   1. Discover — find the bridge via Firestore self-registration
///   2. Pair    — write a pairing request to Firestore; bridge confirms
///   3. Verify  — confirm the bridge is heartbeating + round-trip works
///
/// The legacy mDNS / manual-IP path remains available under "Advanced"
/// for installer troubleshooting, but the primary flow no longer requires
/// the phone and bridge to be on the same WiFi at the same time.
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

  // Selected bridge — populated either from Firestore discovery (primary)
  // or from the Advanced manual-IP fallback (legacy path).
  BridgeEndpoint? _selectedBridge;
  // Optional fast-path local HTTP client. Populated only when the phone
  // is on the same WiFi as the bridge and an /api/info probe succeeds.
  // The pairing flow no longer depends on this — it's purely an
  // optimization for the verify step.
  BridgeApiClient? _client;
  // Legacy /api/info payload, populated only on the manual-IP fallback.
  BridgeInfo? _legacyBridgeInfo;

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

  /// Primary path: select a bridge from the Firestore-discovered list.
  /// All hijack/identity checks happen against the registry doc — no
  /// dependence on the phone reaching the bridge over LAN.
  Future<void> _selectBridge(BridgeEndpoint bridge) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;

    // Hijack protection — read the latest registry state by deviceId so
    // we don't act on a stale list snapshot. If the bridge is paired to
    // someone else, require explicit installer confirmation.
    if (bridge.deviceId != null && bridge.deviceId!.isNotEmpty) {
      final service = ref.read(bridgeDiscoveryServiceProvider);
      final fresh = await service.getById(bridge.deviceId!);
      if (!mounted) return;

      final freshPairedUid = fresh?.pairedUid ?? bridge.pairedUid ?? '';
      final freshStatus = fresh?.status ?? bridge.status ?? 'unpaired';

      if (freshStatus == 'paired' &&
          freshPairedUid.isNotEmpty &&
          freshPairedUid != currentUid) {
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
    }

    // Optional fast-path: if we happen to be on the same network, set up
    // a local HTTP client so the verify step can use the LAN as a fast
    // path. Failure here is non-fatal — Firestore is the source of truth.
    BridgeApiClient? client;
    try {
      client = BridgeApiClient.fromIp(bridge.address.address);
    } catch (_) {
      client = null;
    }

    setState(() {
      _selectedBridge = bridge;
      _client = client;
      _legacyBridgeInfo = null;
      _step = _Step.pair;
    });
  }

  /// Advanced fallback: user typed an IP. Same /api/info verification as
  /// before, then synthesize a BridgeEndpoint from the bridge's response.
  Future<void> _selectBridgeByIp(String ip) async {
    final client = BridgeApiClient.fromIp(ip);

    final info = await client.getInfo();
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

    if (info.type != 'bridge') {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'That IP responded but isn\'t a Lumina Bridge. '
            'Make sure you\'re entering the bridge IP, not the controller IP.',
          ),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    // Hijack-detection via local HTTP — keep for the manual path so the
    // legacy flow stays self-contained.
    final status = await client.getStatus();
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

    // Synthesize a BridgeEndpoint so the rest of the wizard can treat
    // manual-IP and Firestore-discovered bridges uniformly. deviceId
    // comes from the firmware's /api/info response (added in v1.2);
    // empty string on older firmware → falls through to the legacy
    // local-HTTP pairing path.
    final deviceId = info.deviceId.isNotEmpty ? info.deviceId : null;
    setState(() {
      _selectedBridge = BridgeEndpoint(
        name: info.name,
        address: InternetAddress(ip),
        deviceId: deviceId,
        status: status?.paired == true ? 'paired' : 'unpaired',
        pairedUid: status?.userId,
        bridgeEmail: info.bridgeEmail,
      );
      _client = client;
      _legacyBridgeInfo = info;
      _step = _Step.pair;
    });
  }

  Future<void> _promptManualIp() async {
    final ctrl = TextEditingController();
    final ip = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final bottom = MediaQuery.viewInsetsOf(ctx).bottom;
          return AlertDialog(
            backgroundColor: NexGenPalette.gunmetal90,
            insetPadding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + bottom,
            ),
            title: const Text(
              'Enter Bridge IP',
              style: TextStyle(color: Colors.white),
            ),
            content: SingleChildScrollView(
              child: TextField(
                controller: ctrl,
                autofocus: true,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
                  LengthLimitingTextInputFormatter(15),
                ],
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: '192.168.1.100',
                  hintStyle: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.5),
                  ),
                  filled: true,
                  fillColor: NexGenPalette.matteBlack,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onSubmitted: (_) => Navigator.pop(ctx, ctrl.text.trim()),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text(
                  'Cancel',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                ),
                child: const Text(
                  'Connect',
                  style: TextStyle(color: Colors.black),
                ),
              ),
            ],
          );
        },
      ),
    );
    if (ip != null && ip.isNotEmpty) {
      _selectBridgeByIp(ip);
    }
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

    final bridge = _selectedBridge;
    if (bridge == null) return;

    setState(() {
      _pairing = true;
      _pairError = null;
    });

    // Two pairing strategies:
    //   - Firestore-driven (primary): write pendingUid to the registry doc
    //     and poll until the bridge confirms. Works regardless of whether
    //     the phone is on the same WiFi.
    //   - Local HTTP fallback (manual IP only): legacy /api/bridge/pair.
    //     Used when the user typed an IP and we haven't been able to
    //     find the bridge in Firestore (e.g. registry doc missing).
    final hasDeviceId =
        bridge.deviceId != null && bridge.deviceId!.isNotEmpty;
    bool paired;

    if (hasDeviceId) {
      paired = await _pairViaFirestore(
        deviceId: bridge.deviceId!,
        userId: user.uid,
      );
    } else {
      paired = await _pairViaLocalHttp(
        userId: user.uid,
        wledIp: controllerIp,
      );
    }

    if (!mounted) return;

    if (!paired) {
      setState(() {
        _pairing = false;
        _pairError ??= 'Pair request failed. The bridge did not '
            'confirm pairing within 30 seconds.';
      });
      return;
    }

    // Resolve the bridge email from the registry (preferred) or the
    // legacy /api/info payload. Firestore rules grant the bridge access
    // via bridge_email matching its Firebase Auth email — without it the
    // bridge silently 403s on every Firestore read.
    final bridgeEmail = bridge.bridgeEmail?.isNotEmpty == true
        ? bridge.bridgeEmail!
        : (_legacyBridgeInfo?.bridgeEmail ?? '');
    if (bridgeEmail.isEmpty) {
      setState(() {
        _pairing = false;
        _pairError = 'This bridge firmware is outdated. Please reflash '
            'the bridge with the latest firmware and try again.';
      });
      return;
    }

    // Persist the bridge IP and email to the user doc so remote-access
    // queries can reach the bridge and Firestore rules grant it access.
    final bridgeIpToPersist = bridge.address.address;
    try {
      final userService = ref.read(userServiceProvider);
      await userService.saveBridgeConfig(
        user.uid,
        bridgeIp: bridgeIpToPersist,
        bridgeEmail: bridgeEmail,
      );
    } catch (e) {
      debugPrint('Failed to save bridge config to Firestore: $e');
    }

    // For the manual-IP path, also write the controller IP to the
    // bridge's NVS via /api/bridge/pair so it knows where to send
    // commands. The Firestore-driven path doesn't need this — the bridge
    // will receive controllerIp on each command.
    if (!hasDeviceId && _client != null) {
      await _client!.pair(
        userId: user.uid,
        wledIp: controllerIp,
      );
    }

    setState(() {
      _pairing = false;
      _step = _Step.verify;
    });

    _doVerify();
  }

  /// Firestore-driven pair: write status="pairing" + pendingUid, then poll
  /// the registry doc until the bridge promotes it to status="paired".
  Future<bool> _pairViaFirestore({
    required String deviceId,
    required String userId,
  }) async {
    final docRef = FirebaseFirestore.instance
        .collection('bridge_registry')
        .doc(deviceId);

    try {
      await docRef.update({
        'status': 'pairing',
        'pendingUid': userId,
        'pairingRequestedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      _pairError = 'Could not request pairing: $e';
      return false;
    }

    // Poll every 2 s for up to 30 s. The bridge polls the registry every
    // 5 s, so worst case we see the transition on iteration 3-4.
    for (var i = 0; i < 15; i++) {
      await Future.delayed(const Duration(seconds: 2));
      if (!mounted) return false;

      try {
        final snap = await docRef.get();
        final data = snap.data();
        if (data == null) continue;
        final status = data['status'] as String? ?? '';
        final pairedUid = data['pairedUid'] as String? ?? '';
        if (status == 'paired' && pairedUid == userId) {
          return true;
        }
      } catch (e) {
        debugPrint('[BridgeSetup] pair poll iteration $i failed: $e');
      }
    }

    _pairError = 'The bridge did not respond to the pairing request '
        'within 30 seconds. Make sure it is powered on and connected '
        'to WiFi.';
    return false;
  }

  /// Legacy local-HTTP pair — used only on the manual-IP fallback.
  Future<bool> _pairViaLocalHttp({
    required String userId,
    required String wledIp,
  }) async {
    final client = _client;
    if (client == null) {
      _pairError = 'No local connection to the bridge.';
      return false;
    }

    final paired = await client.pair(userId: userId, wledIp: wledIp);
    if (!paired) {
      _pairError = 'Pair request failed. Check the bridge is reachable.';
      return false;
    }

    final authed = await client.authenticate(userId: userId);
    if (!authed) {
      _pairError = 'Bridge did not confirm pairing to this account. '
          'It may be paired to another user, or it may need a firmware update.';
      return false;
    }

    return true;
  }

  // ── Step 3: Verify ────────────────────────────────────────────────────────

  Future<void> _doVerify() async {
    setState(() {
      _verifying = true;
      _verifyError = null;
      _verified = false;
    });

    final bridge = _selectedBridge;
    if (bridge == null) {
      setState(() {
        _verifying = false;
        _verifyError = 'No bridge selected.';
      });
      return;
    }

    // Primary: Firestore heartbeat — the bridge writes lastSeen every
    // 30 s. If we see a recent timestamp, the bridge is up and reachable
    // through the same Firestore path that production commands use.
    if (bridge.deviceId != null && bridge.deviceId!.isNotEmpty) {
      final firestoreOk =
          await _verifyViaFirestoreHeartbeat(bridge.deviceId!);
      if (!mounted) return;
      if (!firestoreOk) {
        setState(() {
          _verifying = false;
          _verifyError =
              'The bridge has not heartbeated to Firestore in the last '
              '60 seconds. Make sure it is powered on and connected to WiFi.';
        });
        return;
      }
    }

    // Optional fast-path: local HTTP /api/info, only if we have a client
    // (set up when the phone happens to be on the same network). Failure
    // is non-fatal — Firestore already proved the bridge is alive.
    if (_client != null) {
      try {
        final info = await _client!
            .getInfo()
            .timeout(const Duration(seconds: 5));
        if (info?.type == 'bridge') {
          debugPrint(
              '[BridgeSetup] Local fast-path verified for ${info?.name}');
        }
      } catch (_) {
        // Ignore — Firestore heartbeat is the authoritative check.
      }
    }

    // Round-trip test: send a ping command through Firestore, expect
    // the bridge to mark it completed within 15 s. Same path remote
    // commands use in production.
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

      await docRef.update({'status': 'timeout'});
      setState(() {
        _verifying = false;
        _verifyError = 'Bridge did not respond to a Firestore ping within '
            '15 seconds. The registry shows it heartbeating, so it is online '
            '— but it may be busy or the controller IP is unreachable.';
      });
    } catch (e) {
      setState(() {
        _verifying = false;
        _verifyError = 'Verification error: $e';
      });
    }
  }

  /// Firestore-only heartbeat freshness check. The bridge updates
  /// `lastSeen` every 30 s; we accept up to 60 s old to allow for
  /// one missed cycle.
  Future<bool> _verifyViaFirestoreHeartbeat(String deviceId) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('bridge_registry')
          .doc(deviceId)
          .get();
      if (!doc.exists) return false;
      final lastSeen = doc.data()?['lastSeen'] as Timestamp?;
      if (lastSeen == null) return false;
      final age = DateTime.now().difference(lastSeen.toDate());
      return age.inSeconds < 60;
    } catch (e) {
      debugPrint('[BridgeSetup] heartbeat check failed: $e');
      return false;
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
          _buildStepIndicator(),
          const SizedBox(height: 24),
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
                  'Make sure the bridge is powered on and connected to WiFi.',
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
                          Text('Looking for bridges...'),
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
                          const Icon(Icons.wifi_find,
                              size: 48, color: Colors.grey),
                          const SizedBox(height: 8),
                          const Text('No bridges found nearby.'),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            onPressed: _startDiscovery,
                            icon: const Icon(Icons.refresh),
                            label: const Text('Search Again'),
                          ),
                        ],
                      ),
                    ),
                  ),
                if (!_scanning && _bridges.isNotEmpty)
                  ..._bridges.map((b) {
                    final isPaired = b.status == 'paired';
                    return ListTile(
                      leading: Icon(Icons.developer_board,
                          color: NexGenPalette.cyan),
                      title: Text(b.name),
                      subtitle: Text(
                        isPaired ? 'Already paired' : 'Ready to pair',
                        style: TextStyle(
                          color: isPaired
                              ? Colors.orange
                              : NexGenPalette.cyan,
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, size: 16),
                      onTap: () => _selectBridge(b),
                    );
                  }),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        // Manual IP entry — under "Advanced" so non-technical installers
        // aren't confronted with it. The Firestore-driven primary path
        // covers >99 % of installs; this is here for diagnostic /
        // air-gapped scenarios only.
        Card(
          child: Theme(
            data: Theme.of(context).copyWith(
              dividerColor: Colors.transparent,
            ),
            child: ExpansionTile(
              leading: Icon(Icons.tune, color: NexGenPalette.textMedium),
              title: Text(
                'Advanced',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              subtitle: Text(
                'Manual IP entry for troubleshooting',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              childrenPadding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              children: [
                Text(
                  'Enter the bridge IP address directly. Use this only '
                  'when discovery isn\'t working — for example, on an '
                  'isolated network or for installer diagnostics.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: _promptManualIp,
                    icon: const Icon(Icons.lan),
                    label: const Text('Enter Bridge IP'),
                  ),
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
    final bridge = _selectedBridge;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (bridge != null)
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
                  // We deliberately don't show the IP — it's an
                  // implementation detail and confusing to non-technical
                  // installers. Name + status are enough.
                  _InfoRow(label: 'Name', value: bridge.name),
                  _InfoRow(
                    label: 'Status',
                    value: bridge.status == 'paired'
                        ? 'Already paired'
                        : 'Ready to pair',
                  ),
                  if (_legacyBridgeInfo != null)
                    _InfoRow(
                      label: 'Version',
                      value: _legacyBridgeInfo!.version,
                    ),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
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
                      _selectedBridge = null;
                      _legacyBridgeInfo = null;
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
    final bridge = _selectedBridge;

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
                    bridge != null
                        ? 'Your ${bridge.name} bridge is paired and responding '
                            'to commands through Firestore.'
                        : 'Your bridge is paired and responding through Firestore.',
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
