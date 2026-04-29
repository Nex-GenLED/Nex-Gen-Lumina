import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:nexgen_command/models/controller_type.dart';
import 'package:nexgen_command/services/image_upload_service.dart';
import 'package:nexgen_command/services/wled_config_pusher.dart';
import 'package:nexgen_command/theme.dart';

/// Step 2: Controller Setup screen for the installer wizard
class ControllerSetupScreen extends ConsumerStatefulWidget {
  final VoidCallback onNext;
  final VoidCallback onBack;

  const ControllerSetupScreen({
    super.key,
    required this.onNext,
    required this.onBack,
  });

  @override
  ConsumerState<ControllerSetupScreen> createState() => _ControllerSetupScreenState();
}

class _ControllerSetupScreenState extends ConsumerState<ControllerSetupScreen> {
  final Map<String, bool> _controllerStatus = {};
  final Map<String, bool> _checkingStatus = {};
  final Map<String, ControllerType> _controllerTypes = {};
  final Set<String> _pushingDefaults = {};
  final Set<String> _backgroundCheckInFlight = {};
  Timer? _statusRefreshTimer;
  bool _isUploading = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAllControllerStatus();
      _loadControllerTypes();
      _statusRefreshTimer = Timer.periodic(
        const Duration(seconds: 15),
        (_) {
          if (mounted) _checkAllControllerStatusSilently();
        },
      );
    });
  }

  @override
  void dispose() {
    _statusRefreshTimer?.cancel();
    super.dispose();
  }

  /// Reads the `controller_type` field from each Firestore controller document
  /// so we can show type-specific UI (e.g. "Apply NGL Defaults" for SKIKBILY).
  Future<void> _loadControllerTypes() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .collection('controllers')
          .get();
      for (final doc in snap.docs) {
        final typeStr = doc.data()['controller_type'] as String?;
        if (typeStr != null) {
          _controllerTypes[doc.id] = ControllerType.fromFirestore(typeStr);
        }
      }
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('Failed to load controller types: $e');
    }
  }

  Future<void> _checkAllControllerStatus() async {
    final controllersAsync = ref.read(controllersStreamProvider);
    controllersAsync.whenData((controllers) {
      for (final controller in controllers) {
        _checkControllerStatus(controller);
      }
    });
  }

  Future<void> _checkControllerStatus(ControllerInfo controller) async {
    if (_checkingStatus[controller.id] == true) return;

    setState(() {
      _checkingStatus[controller.id] = true;
    });

    try {
      final service = WledService('http://${controller.ip}');
      final state = await service.getState().timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (mounted) {
        setState(() {
          _controllerStatus[controller.id] = state != null;
          _checkingStatus[controller.id] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _controllerStatus[controller.id] = false;
          _checkingStatus[controller.id] = false;
        });
      }
    }
  }

  /// Background-safe variant of [_checkAllControllerStatus] that does NOT
  /// show a spinner on each card. Used by the 15-second periodic refresh.
  Future<void> _checkAllControllerStatusSilently() async {
    final controllersAsync = ref.read(controllersStreamProvider);
    controllersAsync.whenData((controllers) {
      for (final controller in controllers) {
        _checkControllerStatusSilently(controller);
      }
    });
  }

  /// Pings a single controller without showing a spinner. Skips if a visible
  /// or background check is already in flight for this controller.
  Future<void> _checkControllerStatusSilently(ControllerInfo controller) async {
    if (_checkingStatus[controller.id] == true) return;
    if (_backgroundCheckInFlight.contains(controller.id)) return;
    _backgroundCheckInFlight.add(controller.id);

    try {
      final service = WledService('http://${controller.ip}');
      final state = await service.getState().timeout(
        const Duration(seconds: 5),
        onTimeout: () => null,
      );
      if (mounted) {
        final isOnline = state != null;
        if (_controllerStatus[controller.id] != isOnline) {
          setState(() {
            _controllerStatus[controller.id] = isOnline;
          });
        }
      }
    } catch (e) {
      if (mounted && _controllerStatus[controller.id] != false) {
        setState(() {
          _controllerStatus[controller.id] = false;
        });
      }
    } finally {
      _backgroundCheckInFlight.remove(controller.id);
    }
  }

  void _toggleControllerSelection(String controllerId) {
    final current = ref.read(installerSelectedControllersProvider);
    final newSet = Set<String>.from(current);
    if (newSet.contains(controllerId)) {
      newSet.remove(controllerId);
    } else {
      newSet.add(controllerId);
    }
    ref.read(installerSelectedControllersProvider.notifier).state = newSet;
    ref.read(installerModeActiveProvider.notifier).recordActivity();
    setState(() {
      _validationError = null;
    });
  }

  Future<void> _renameController(ControllerInfo controller) async {
    final nameController = TextEditingController(text: controller.name ?? '');

    final newName = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Rename Controller', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: nameController,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: InputDecoration(
            labelText: 'Controller Name',
            labelStyle: const TextStyle(color: NexGenPalette.textMedium),
            hintText: 'e.g., Front Yard, Roofline',
            hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
            filled: true,
            fillColor: NexGenPalette.matteBlack,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, nameController.text.trim()),
            style: ElevatedButton.styleFrom(backgroundColor: NexGenPalette.cyan),
            child: const Text('Save', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (newName != null && newName.isNotEmpty && newName != controller.name) {
      final rename = ref.read(renameControllerProvider);
      await rename(controller.id, newName);
    }
  }

  Future<void> _deleteController(ControllerInfo controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Delete Controller?', style: TextStyle(color: Colors.white)),
        content: Text(
          'Remove "${controller.name ?? controller.ip}" from this installation?',
          style: const TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      // Remove from selection
      final current = ref.read(installerSelectedControllersProvider);
      final newSet = Set<String>.from(current)..remove(controller.id);
      ref.read(installerSelectedControllersProvider.notifier).state = newSet;

      // Delete from Firestore
      final delete = ref.read(deleteControllerProvider);
      await delete(controller.id);
    }
  }

  Future<void> _addController() async {
    // Show option: BLE scan or manual IP entry
    final choice = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Add Controller', style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.bluetooth, color: NexGenPalette.cyan),
                title: const Text('BLE Scan (New Device)', style: TextStyle(color: Colors.white)),
                subtitle: const Text('For controllers not yet on WiFi', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'ble'),
              ),
              ListTile(
                leading: const Icon(Icons.wifi, color: NexGenPalette.green),
                title: const Text('Enter IP Address', style: TextStyle(color: Colors.white)),
                subtitle: const Text('For controllers already on the network', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12)),
                onTap: () => Navigator.pop(ctx, 'ip'),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );

    if (choice == 'ble') {
      if (!mounted) return;
      await context.push(AppRoutes.deviceSetup);
      _checkAllControllerStatus();
    } else if (choice == 'ip') {
      await _addControllerByIp();
    }
  }

  /// Shows a bottom sheet with three tappable hardware-type cards and returns
  /// the user's selection, or `null` if they dismiss.
  Future<ControllerType?> _pickControllerType() async {
    var selected = ControllerType.digOcta;

    return showModalBottomSheet<ControllerType>(
      context: context,
      backgroundColor: NexGenPalette.matteBlack,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Select controller hardware',
                  style: TextStyle(
                    color: NexGenPalette.textHigh,
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 20),
                Row(
                  children: ControllerType.values.map((type) {
                    final isSelected = type == selected;
                    return Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(
                          right: type != ControllerType.values.last ? 10 : 0,
                        ),
                        child: GestureDetector(
                          onTap: () {
                            HapticFeedback.selectionClick();
                            setSheetState(() => selected = type);
                          },
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            padding: const EdgeInsets.symmetric(
                              vertical: 16,
                              horizontal: 8,
                            ),
                            decoration: BoxDecoration(
                              color: NexGenPalette.gunmetal,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(
                                color: isSelected
                                    ? NexGenPalette.cyan
                                    : Colors.transparent,
                                width: 2,
                              ),
                            ),
                            child: Column(
                              children: [
                                SvgPicture.asset(
                                  type.iconAsset,
                                  width: 48,
                                  height: 48,
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  type.fullName,
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(
                                    color: NexGenPalette.textHigh,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  type.defaultChannelCount != null
                                      ? '${type.defaultChannelCount} channels'
                                      : 'Variable',
                                  style: TextStyle(
                                    color: NexGenPalette.textHigh
                                        .withValues(alpha: 0.6),
                                    fontSize: 11,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx, selected),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: const Text(
                      'Continue',
                      style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _addControllerByIp() async {
    // Step 1: Pick controller hardware type
    final controllerType = await _pickControllerType();
    if (controllerType == null || !mounted) return;

    // Step 2: IP entry (unchanged)
    final ipCtrl = TextEditingController();
    final nameCtrl = TextEditingController();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) {
          final bottomInset = MediaQuery.of(ctx).viewInsets.bottom;
          return AlertDialog(
            backgroundColor: NexGenPalette.gunmetal90,
            insetPadding: EdgeInsets.only(
              left: 24,
              right: 24,
              top: 24,
              bottom: 24 + bottomInset,
            ),
            title: const Text('Add Controller by IP',
                style: TextStyle(color: Colors.white)),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // static IP warning banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.amber.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: Colors.amber.withValues(alpha: 0.4)),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(Icons.warning_amber_rounded,
                            color: Colors.amber, size: 18),
                        const SizedBox(width: 8),
                        const Expanded(
                          child: Text(
                            'Set a static IP in WLED first: '
                            'Config → WiFi Setup → Static IP. '
                            'DHCP addresses change and will break the connection.',
                            style: TextStyle(
                                fontSize: 12, color: Colors.amber),
                          ),
                        ),
                      ],
                    ),
                  ),
                  // IP field
                  TextField(
                    controller: ipCtrl,
                    autofocus: true,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true),
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'IP Address',
                      hintText: '192.168.50.200',
                      labelStyle:
                          const TextStyle(color: NexGenPalette.textMedium),
                      hintStyle: TextStyle(
                          color: NexGenPalette.textMedium
                              .withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                  const SizedBox(height: 16),
                  // Name field (keep existing)
                  TextField(
                    controller: nameCtrl,
                    style: const TextStyle(color: Colors.white),
                    decoration: InputDecoration(
                      labelText: 'Name (optional)',
                      hintText: 'e.g., Front Roofline',
                      labelStyle:
                          const TextStyle(color: NexGenPalette.textMedium),
                      hintStyle: TextStyle(
                          color: NexGenPalette.textMedium
                              .withValues(alpha: 0.5)),
                      filled: true,
                      fillColor: NexGenPalette.matteBlack,
                      border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Cancel',
                    style: TextStyle(color: NexGenPalette.textMedium)),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan),
                child: const Text('Add',
                    style: TextStyle(color: Colors.black)),
              ),
            ],
          );
        },
      ),
    );

    if (confirmed != true) return;

    final ip = ipCtrl.text.trim();
    if (ip.isEmpty) return;

    // Step 3: Validate controller type against live device info. The
    // validation call also returns the parsed /json/info so we can enrich
    // the Firestore doc without a second network round-trip.
    WledInfoResponse? info;
    if (mounted) {
      final validation = await _validateControllerType(ip, controllerType);
      if (!validation.proceed || !mounted) return;
      info = validation.info;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('No auth session — please re-enter your PIN')),
        );
      }
      return;
    }

    // Pull enrichment fields from /json/info. Any of these may be null if
    // the device is unreachable or running older firmware — we include
    // them in the doc only when present.
    final rawMac = (info?.raw['mac'] as String?)?.trim();
    final mac =
        (rawMac == null || rawMac.isEmpty) ? null : rawMac.toLowerCase();
    final firmwareVersion =
        (info == null || info.ver.isEmpty) ? null : info.ver;
    final arch = (info == null || info.arch.isEmpty) ? null : info.arch;
    final ledsRaw = info?.raw['leds'];
    final ledCount = (ledsRaw is Map && ledsRaw['count'] is num)
        ? (ledsRaw['count'] as num).toInt()
        : null;
    final ethRaw = info?.raw['ethernet'];
    final hasEthernet = ethRaw == true ||
        (ethRaw is Map && ethRaw.isNotEmpty) ||
        (ethRaw is num && ethRaw != 0);
    final connectionType = hasEthernet ? 'ethernet_wifi' : 'wifi';

    final name = nameCtrl.text.trim().isEmpty
        ? 'Controller ($ip)'
        : nameCtrl.text.trim();

    final controllersRef = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .collection('controllers');

    try {
      // Duplicate check by MAC: if this physical controller is already
      // registered under this user, update the existing doc's IP instead
      // of creating a second record. MAC survives IP changes and router
      // swaps, so it's the stable identity.
      if (mac != null) {
        final dup = await controllersRef
            .where('mac', isEqualTo: mac)
            .limit(1)
            .get();
        if (dup.docs.isNotEmpty) {
          final existing = dup.docs.first;
          await existing.reference.update({
            'ip': ip,
            'updatedAt': FieldValue.serverTimestamp(),
          });
          _controllerTypes[existing.id] = controllerType;
          ref.invalidate(controllersStreamProvider);
          _checkAllControllerStatus();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Controller already registered — updated IP address.'),
              ),
            );
          }
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: const Text(
                  '✓ Controller added. If the red dot persists, open '
                  'WLED in a browser at this IP → Config → WiFi Setup '
                  '→ set a Static IP → Save & Reboot.',
                ),
                duration: const Duration(seconds: 8),
                backgroundColor: Colors.amber.shade800,
                action: SnackBarAction(
                  label: 'Got it',
                  textColor: Colors.white,
                  onPressed: () {},
                ),
              ),
            );
          }
          return;
        }
      }

      final docData = <String, dynamic>{
        'ip': ip,
        'name': name,
        'wifiConfigured': true,
        'controller_type': controllerType.toFirestore(),
        'connectionType': connectionType,
        'createdAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        if (mac != null) 'mac': mac,
        if (firmwareVersion != null) 'firmwareVersion': firmwareVersion,
        if (ledCount != null) 'ledCount': ledCount,
        if (arch != null) 'arch': arch,
      };

      // Use the MAC as the document ID so records are stable across IP
      // changes and router swaps. Fall back to an auto-generated ID only
      // when the device didn't report a MAC (unreachable / old firmware).
      final String newDocId;
      if (mac != null) {
        newDocId = _macToDocId(mac);
        await controllersRef.doc(newDocId).set(docData);
      } else {
        final added = await controllersRef.add(docData);
        newDocId = added.id;
      }

      _controllerTypes[newDocId] = controllerType;
      ref.invalidate(controllersStreamProvider);
      _checkAllControllerStatus();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              '✓ Controller added. If the red dot persists, open '
              'WLED in a browser at this IP → Config → WiFi Setup '
              '→ set a Static IP → Save & Reboot.',
            ),
            duration: const Duration(seconds: 8),
            backgroundColor: Colors.amber.shade800,
            action: SnackBarAction(
              label: 'Got it',
              textColor: Colors.white,
              onPressed: () {},
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to add controller: $e')),
        );
      }
    }
  }

  /// Formats a MAC address for use as a Firestore document ID: lowercase
  /// hex with underscores between each octet (e.g. `80_f3_da_b3_95_4c`).
  /// Tolerates input with or without colon separators — WLED firmware
  /// varies by version.
  String _macToDocId(String mac) {
    final clean =
        mac.toLowerCase().replaceAll(RegExp(r'[^0-9a-f]'), '');
    if (clean.length != 12) {
      // Not a standard 48-bit MAC — fall back to a sanitized form so we
      // still produce a legal doc ID.
      return clean.isEmpty ? mac.replaceAll(':', '_') : clean;
    }
    final buf = StringBuffer();
    for (int i = 0; i < 12; i += 2) {
      if (i > 0) buf.write('_');
      buf.write(clean.substring(i, i + 2));
    }
    return buf.toString();
  }

  /// Fetches /json/info from [ip], validates against [expected], and shows a
  /// warning dialog if the channel count doesn't match. Returns a record with
  /// `proceed` (true if the caller should continue with saving) and `info`
  /// (the parsed response, when the device was reachable — so the caller can
  /// enrich the Firestore doc without a second fetch).
  Future<({bool proceed, WledInfoResponse? info})> _validateControllerType(
    String ip,
    ControllerType expected,
  ) async {
    final service = WledService('http://$ip');
    final info = await service.getInfo().timeout(
      const Duration(seconds: 10),
      onTimeout: () => null,
    );

    // If we can't reach the device at all, let the existing status-check
    // flow surface the problem — don't block the add.
    if (info == null) return (proceed: true, info: null);

    final result = validateControllerMatch(info, expected);
    if (result.isMatch || result.warningMessage == null) {
      return (proceed: true, info: info);
    }

    if (!mounted) return (proceed: false, info: info);

    final continueAnyway = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: NexGenPalette.violet, width: 2),
        ),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded,
                color: NexGenPalette.violet, size: 24),
            const SizedBox(width: 10),
            const Expanded(
              child: Text(
                'Hardware Mismatch',
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              result.warningMessage!,
              style: const TextStyle(
                color: NexGenPalette.textHigh,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              'WLED ${info.ver}  •  ${info.arch}',
              style: TextStyle(
                color: NexGenPalette.textHigh.withValues(alpha: 0.6),
                fontSize: 12,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Go Back',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.violet,
            ),
            child: const Text('Continue Anyway',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    return (proceed: continueAnyway == true, info: info);
  }

  Future<void> _capturePhoto(ImageSource source) async {
    setState(() {
      _isUploading = true;
    });

    try {
      final picker = ImagePicker();
      final image = await picker.pickImage(
        source: source,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (image == null) {
        setState(() => _isUploading = false);
        return;
      }

      // Use the current auth user's ID for Storage path (matches security rules)
      final currentUser = FirebaseAuth.instance.currentUser;
      final uploadId = currentUser?.uid ?? 'installer_${DateTime.now().millisecondsSinceEpoch}';
      final service = ImageUploadService();

      // Upload the already-picked image bytes directly (don't re-pick)
      final bytes = await image.readAsBytes();
      final url = await service.uploadImage(uploadId, bytes);

      if (url != null && mounted) {
        ref.read(installerPhotoUrlProvider.notifier).state = url;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to upload photo: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isUploading = false);
      }
    }
  }

  void _removePhoto() {
    ref.read(installerPhotoUrlProvider.notifier).state = null;
  }

  void _saveAndContinue() {
    final selected = ref.read(installerSelectedControllersProvider);
    if (selected.isEmpty) {
      setState(() {
        _validationError = 'Please select at least one controller for this installation.';
      });
      return;
    }

    ref.read(installerModeActiveProvider.notifier).recordActivity();
    widget.onNext();
  }

  @override
  Widget build(BuildContext context) {
    final controllersAsync = ref.watch(controllersStreamProvider);
    final selectedControllers = ref.watch(installerSelectedControllersProvider);
    final photoUrl = ref.watch(installerPhotoUrlProvider);

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          const Text(
            'Controller Setup',
            style: TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Select the controllers that are part of this installation. '
            'Add new controllers using the button below.',
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
          const SizedBox(height: 24),

          // Controller list
          controllersAsync.when(
            loading: () => const Center(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: CircularProgressIndicator(color: NexGenPalette.cyan),
              ),
            ),
            error: (e, _) => _buildErrorCard('Failed to load controllers: $e'),
            data: (controllers) {
              if (controllers.isEmpty) {
                return _buildEmptyState();
              }
              return Column(
                children: controllers.map((controller) {
                  return _buildControllerCard(
                    controller,
                    isSelected: selectedControllers.contains(controller.id),
                    isOnline: _controllerStatus[controller.id],
                    isChecking: _checkingStatus[controller.id] ?? false,
                  );
                }).toList(),
              );
            },
          ),

          const SizedBox(height: 16),

          // Add controller button
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _addController,
              icon: const Icon(Icons.add, color: NexGenPalette.cyan),
              label: const Text(
                'Add Controller',
                style: TextStyle(color: NexGenPalette.cyan),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                side: const BorderSide(color: NexGenPalette.cyan),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),

          const SizedBox(height: 32),

          // Photo capture section
          _buildPhotoSection(photoUrl),

          // Validation error
          if (_validationError != null) ...[
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.error_outline, color: Colors.red, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _validationError!,
                      style: const TextStyle(color: Colors.red, fontSize: 14),
                    ),
                  ),
                ],
              ),
            ),
          ],

          const SizedBox(height: 32),

          // Navigation buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: widget.onBack,
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: NexGenPalette.line),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text('Back', style: TextStyle(color: Colors.white)),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: ElevatedButton(
                  onPressed: _saveAndContinue,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  child: const Text(
                    'Continue',
                    style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _buildControllerCard(
    ControllerInfo controller, {
    required bool isSelected,
    bool? isOnline,
    required bool isChecking,
  }) {
    final ctrlType = _controllerTypes[controller.id];
    final showApplyDefaults =
        ctrlType == ControllerType.skikbily &&
        isOnline == true &&
        !isChecking;
    final isPushing = _pushingDefaults.contains(controller.id);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isSelected ? NexGenPalette.cyan : NexGenPalette.line,
          width: isSelected ? 2 : 1,
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: () => _toggleControllerSelection(controller.id),
            borderRadius: showApplyDefaults
                ? const BorderRadius.vertical(top: Radius.circular(12))
                : BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Selection checkbox
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isSelected ? NexGenPalette.cyan : Colors.transparent,
                      border: Border.all(
                        color: isSelected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                        width: 2,
                      ),
                    ),
                    child: isSelected
                        ? const Icon(Icons.check, color: Colors.black, size: 16)
                        : null,
                  ),
                  const SizedBox(width: 16),

                  // Controller info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          controller.name ?? 'Unnamed Controller',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 16,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          controller.ip,
                          style: const TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),

                  // Status indicator
                  if (isChecking)
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: NexGenPalette.cyan,
                      ),
                    )
                  else
                    Container(
                      width: 12,
                      height: 12,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline == null
                            ? NexGenPalette.textMedium
                            : isOnline
                                ? Colors.green
                                : Colors.red,
                      ),
                    ),
                  const SizedBox(width: 12),

                  // Actions menu
                  PopupMenuButton<String>(
                    icon: const Icon(Icons.more_vert, color: NexGenPalette.textMedium),
                    color: NexGenPalette.gunmetal90,
                    onSelected: (value) {
                      switch (value) {
                        case 'rename':
                          _renameController(controller);
                          break;
                        case 'refresh':
                          _checkControllerStatus(controller);
                          break;
                        case 'delete':
                          _deleteController(controller);
                          break;
                      }
                    },
                    itemBuilder: (context) => [
                      const PopupMenuItem(
                        value: 'rename',
                        child: Row(
                          children: [
                            Icon(Icons.edit, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Rename', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'refresh',
                        child: Row(
                          children: [
                            Icon(Icons.refresh, color: Colors.white, size: 20),
                            SizedBox(width: 12),
                            Text('Check Status', style: TextStyle(color: Colors.white)),
                          ],
                        ),
                      ),
                      const PopupMenuItem(
                        value: 'delete',
                        child: Row(
                          children: [
                            Icon(Icons.delete_outline, color: Colors.red, size: 20),
                            SizedBox(width: 12),
                            Text('Delete', style: TextStyle(color: Colors.red)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // "Apply NGL Defaults" — only for SKIKBILY controllers that are online
          if (showApplyDefaults)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: isPushing
                      ? null
                      : () => _applyNglDefaults(controller),
                  icon: isPushing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: NexGenPalette.green,
                          ),
                        )
                      : const Icon(Icons.tune, color: NexGenPalette.green, size: 18),
                  label: Text(
                    isPushing ? 'Applying...' : 'Apply NGL Defaults',
                    style: TextStyle(
                      color: isPushing ? NexGenPalette.textMedium : NexGenPalette.green,
                      fontSize: 13,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    side: BorderSide(
                      color: isPushing
                          ? NexGenPalette.line
                          : NexGenPalette.green.withValues(alpha: 0.5),
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _applyNglDefaults(ControllerInfo controller) async {
    // Confirmation dialog — this writes persistent config.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text(
          'Apply NGL Defaults?',
          style: TextStyle(color: Colors.white),
        ),
        content: const Text(
          'This will overwrite the controller\'s current LED settings. Continue?',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel',
                style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: NexGenPalette.green,
            ),
            child:
                const Text('Apply', style: TextStyle(color: Colors.black)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _pushingDefaults.add(controller.id));

    final ctrlType = _controllerTypes[controller.id] ?? ControllerType.genericWled;
    final result = await pushDefaultsForControllerType(controller.ip, ctrlType);

    if (!mounted) return;
    setState(() => _pushingDefaults.remove(controller.id));

    if (result.success && result.warnings.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SKIKBILY configured with NGL defaults'),
          backgroundColor: Colors.green,
        ),
      );
    } else if (result.success && result.warnings.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.amber.shade700,
          content: Text(
            'Configured with warnings: ${result.warnings.length} setting(s) need manual verification.',
            style: const TextStyle(color: NexGenPalette.textHigh),
          ),
          action: SnackBarAction(
            label: 'Details',
            textColor: NexGenPalette.textHigh,
            onPressed: () {
              showDialog(
                context: context,
                builder: (ctx) => AlertDialog(
                  backgroundColor: NexGenPalette.gunmetal90,
                  title: const Text(
                    'Configuration Warnings',
                    style: TextStyle(color: Colors.white),
                  ),
                  content: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: result.warnings
                        .map((w) => Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('• ',
                                      style: TextStyle(
                                          color: NexGenPalette.textHigh)),
                                  Expanded(
                                    child: Text(w,
                                        style: const TextStyle(
                                            color: NexGenPalette.textHigh,
                                            fontSize: 14)),
                                  ),
                                ],
                              ),
                            ))
                        .toList(),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(ctx),
                      child: const Text('OK',
                          style: TextStyle(color: NexGenPalette.cyan)),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.errorMessage ?? 'Configuration push failed'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Column(
        children: [
          Icon(
            Icons.router_outlined,
            size: 64,
            color: NexGenPalette.textMedium.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          const Text(
            'No Controllers Found',
            style: TextStyle(
              color: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Add your first controller using the button below to begin setup.',
            textAlign: TextAlign.center,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorCard(String message) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          const Icon(Icons.error_outline, color: Colors.red),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Colors.red),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPhotoSection(String? photoUrl) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.camera_alt_outlined, color: NexGenPalette.cyan, size: 20),
            const SizedBox(width: 8),
            const Text(
              'Installation Photo',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w600,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'Optional',
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Text(
          'Capture a photo of the completed installation for records.',
          style: TextStyle(color: NexGenPalette.textMedium, fontSize: 14),
        ),
        const SizedBox(height: 16),

        if (_isUploading) ...[
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Column(
              children: [
                const CircularProgressIndicator(color: NexGenPalette.cyan),
                const SizedBox(height: 16),
                Text(
                  'Uploading photo...',
                  style: TextStyle(color: NexGenPalette.textMedium),
                ),
              ],
            ),
          ),
        ] else if (photoUrl != null) ...[
          Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(
                  photoUrl,
                  height: 200,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      height: 200,
                      color: NexGenPalette.gunmetal90,
                      child: const Center(
                        child: CircularProgressIndicator(color: NexGenPalette.cyan),
                      ),
                    );
                  },
                ),
              ),
              Positioned(
                top: 8,
                right: 8,
                child: Row(
                  children: [
                    _buildPhotoActionButton(
                      icon: Icons.refresh,
                      onTap: () => _showPhotoSourceDialog(),
                    ),
                    const SizedBox(width: 8),
                    _buildPhotoActionButton(
                      icon: Icons.delete_outline,
                      onTap: _removePhoto,
                      color: Colors.red,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ] else ...[
          Row(
            children: [
              Expanded(
                child: _buildPhotoButton(
                  icon: Icons.camera_alt,
                  label: 'Take Photo',
                  onTap: () => _capturePhoto(ImageSource.camera),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildPhotoButton(
                  icon: Icons.photo_library,
                  label: 'Choose Photo',
                  onTap: () => _capturePhoto(ImageSource.gallery),
                ),
              ),
            ],
          ),
        ],
      ],
    );
  }

  void _showPhotoSourceDialog() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Replace Photo',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),
              ListTile(
                leading: const Icon(Icons.camera_alt, color: NexGenPalette.cyan),
                title: const Text('Take Photo', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _capturePhoto(ImageSource.camera);
                },
              ),
              ListTile(
                leading: const Icon(Icons.photo_library, color: NexGenPalette.cyan),
                title: const Text('Choose from Gallery', style: TextStyle(color: Colors.white)),
                onTap: () {
                  Navigator.pop(context);
                  _capturePhoto(ImageSource.gallery);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPhotoButton({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Column(
          children: [
            Icon(icon, color: NexGenPalette.cyan, size: 32),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoActionButton({
    required IconData icon,
    required VoidCallback onTap,
    Color? color,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.black.withValues(alpha: 0.6),
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: color ?? Colors.white, size: 20),
      ),
    );
  }
}
