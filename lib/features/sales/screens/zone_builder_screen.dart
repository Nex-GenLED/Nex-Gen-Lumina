import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ── Constants ──────────────────────────────────────────────────

const int maxPixelsPerSegment = 100;
const int minPixelsPerSegment = 66;
const int controllerCapacitySlots = 4;
const int controllerWatts = 600;

// ── Zone Builder Screen (Step 2 of 3) ─────────────────────────

class ZoneBuilderScreen extends ConsumerStatefulWidget {
  const ZoneBuilderScreen({super.key});

  @override
  ConsumerState<ZoneBuilderScreen> createState() => _ZoneBuilderScreenState();
}

class _ZoneBuilderScreenState extends ConsumerState<ZoneBuilderScreen> {
  List<InstallZone> _zones = [];
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    final job = ref.read(activeJobProvider);
    if (job != null && job.zones.isNotEmpty) {
      _zones = List.from(job.zones);
    }
  }

  int get _totalSlots =>
      _zones.fold(0, (acc, z) => acc + z.controllerSlotCount);

  double get _totalFt =>
      _zones.fold(0.0, (acc, z) => acc + z.runLengthFt);

  int get _totalInjections =>
      _zones.fold(0, (acc, z) => acc + z.injections.length);

  double get _totalPrice =>
      _zones.fold(0.0, (acc, z) => acc + z.priceUsd);

  void _addOrEditZone({InstallZone? existing, int? index}) async {
    final result = await showModalBottomSheet<InstallZone>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => ZoneEditorSheet(
        existing: existing,
        allZones: _zones,
        editIndex: index,
        jobId: ref.read(activeJobProvider)?.id ?? '',
      ),
    );

    if (result != null) {
      setState(() {
        if (index != null) {
          _zones[index] = result;
        } else {
          _zones.add(result);
        }
      });
      ref.read(salesModeProvider.notifier).recordActivity();
    }
  }

  void _removeZone(int index) {
    setState(() => _zones.removeAt(index));
  }

  Future<void> _saveAndContinue() async {
    if (_zones.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one zone')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final job = ref.read(activeJobProvider);
      if (job == null) return;

      final updated = job.copyWith(
        zones: _zones,
        totalPriceUsd: _totalPrice,
        updatedAt: DateTime.now(),
      );

      await FirebaseFirestore.instance
          .collection('sales_jobs')
          .doc(job.id)
          .set(updated.toJson(), SetOptions(merge: true));

      ref.read(activeJobProvider.notifier).state = updated;

      if (mounted) context.push(AppRoutes.salesReview);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('New Visit'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ),
      body: Column(
        children: [
          // Step indicator
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step 2 of 3 — Install zones',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: 0.66,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: NexGenPalette.cyan,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),

          // Zone list
          Expanded(
            child: _zones.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    itemCount: _zones.length + 1, // +1 for add button
                    separatorBuilder: (_, __) => const SizedBox(height: 12),
                    itemBuilder: (context, i) {
                      if (i == _zones.length) return _buildAddButton();
                      return _ZoneCard(
                        zone: _zones[i],
                        onEdit: () => _addOrEditZone(existing: _zones[i], index: i),
                        onRemove: () => _removeZone(i),
                      );
                    },
                  ),
          ),

          // Controller slot tracker
          _buildControllerTracker(),

          // Summary bar
          if (_zones.isNotEmpty) _buildSummaryBar(),

          // Continue button
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving || _zones.isEmpty ? null : _saveAndContinue,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: _isSaving
                    ? const SizedBox(
                        height: 20, width: 20,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                      )
                    : const Text(
                        'Review and estimate →',
                        style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 16),
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.layers_outlined, size: 56, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text('No zones yet', style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 16)),
          const SizedBox(height: 8),
          Text('Add your first install zone', style: TextStyle(color: Colors.white.withValues(alpha: 0.3), fontSize: 13)),
          const SizedBox(height: 24),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildAddButton() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: OutlinedButton.icon(
        onPressed: () => _addOrEditZone(),
        icon: Icon(Icons.add, color: NexGenPalette.cyan),
        label: Text('Add zone', style: TextStyle(color: NexGenPalette.cyan)),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  Widget _buildControllerTracker() {
    final used = _totalSlots;
    final color = used <= 3
        ? NexGenPalette.green
        : used == 4
            ? NexGenPalette.amber
            : Colors.red;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      child: Row(
        children: [
          Icon(Icons.developer_board, size: 16, color: color),
          const SizedBox(width: 6),
          Text(
            'Controller: $used of $controllerCapacitySlots slots used',
            style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryBar() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Text(
        '${_zones.length} zone${_zones.length == 1 ? '' : 's'} · '
        '${_totalFt.toStringAsFixed(0)} ft total · '
        '$_totalInjections injection${_totalInjections == 1 ? '' : 's'} · '
        '\$${_totalPrice.toStringAsFixed(0)}',
        style: TextStyle(color: NexGenPalette.textHigh, fontSize: 13, fontWeight: FontWeight.w500),
        textAlign: TextAlign.center,
      ),
    );
  }
}

// ── Zone card ──────────────────────────────────────────────────

class _ZoneCard extends StatelessWidget {
  final InstallZone zone;
  final VoidCallback onEdit;
  final VoidCallback onRemove;

  const _ZoneCard({required this.zone, required this.onEdit, required this.onRemove});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: InkWell(
        onTap: onEdit,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(zone.name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w600)),
                    const SizedBox(height: 4),
                    Text(
                      '${zone.runLengthFt.toStringAsFixed(0)} ft · ${zone.productType.label} · ${zone.colorPreset.label}',
                      style: TextStyle(color: Colors.white.withValues(alpha: 0.5), fontSize: 13),
                    ),
                    if (zone.injections.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        '${zone.injections.length} injection${zone.injections.length == 1 ? '' : 's'} · '
                        '${zone.controllerSlotCount} controller slot${zone.controllerSlotCount == 1 ? '' : 's'}',
                        style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.7), fontSize: 12),
                      ),
                    ],
                    if (zone.priceUsd > 0) ...[
                      const SizedBox(height: 4),
                      Text(
                        '\$${zone.priceUsd.toStringAsFixed(0)}',
                        style: TextStyle(color: NexGenPalette.green, fontSize: 13, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ],
                ),
              ),
              IconButton(
                icon: Icon(Icons.delete_outline, color: Colors.red.withValues(alpha: 0.6), size: 20),
                onPressed: onRemove,
              ),
              Icon(Icons.chevron_right, color: Colors.white.withValues(alpha: 0.3)),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Zone editor bottom sheet ──────────────────────────────────

class ZoneEditorSheet extends StatefulWidget {
  final InstallZone? existing;
  final List<InstallZone> allZones;
  final int? editIndex;
  final String jobId;

  const ZoneEditorSheet({
    super.key,
    this.existing,
    required this.allZones,
    this.editIndex,
    required this.jobId,
  });

  @override
  State<ZoneEditorSheet> createState() => _ZoneEditorSheetState();
}

class _ZoneEditorSheetState extends State<ZoneEditorSheet> {
  final _nameCtrl = TextEditingController();
  final _runLengthCtrl = TextEditingController();
  final _pxPerFtCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _connectorRunCtrl = TextEditingController();

  ProductType _productType = ProductType.roofline;
  ColorPreset _colorPreset = ColorPreset.rgbw;
  RailType _railType = RailType.none;
  RailColor _railColor = RailColor.none;
  List<InjectionPoint> _injections = [];
  List<PowerMount> _mounts = [];
  List<String> _photoUrls = [];
  bool _isUploadingPhoto = false;

  @override
  void initState() {
    super.initState();
    if (widget.existing != null) {
      final z = widget.existing!;
      _nameCtrl.text = z.name;
      _runLengthCtrl.text = z.runLengthFt.toStringAsFixed(1);
      _productType = z.productType;
      _colorPreset = z.colorPreset;
      _pxPerFtCtrl.text = z.pixelsPerFoot.toStringAsFixed(3);
      _notesCtrl.text = z.notes;
      _priceCtrl.text = z.priceUsd > 0 ? z.priceUsd.toStringAsFixed(2) : '';
      _railType = z.railType;
      _railColor = z.railColor;
      _connectorRunCtrl.text = z.connectorRunFt > 0 ? z.connectorRunFt.toStringAsFixed(1) : '';
      _injections = List.from(z.injections);
      _mounts = List.from(z.mounts);
      _photoUrls = List.from(z.photoUrls);
    } else {
      _pxPerFtCtrl.text = _productType.pixelsPerFoot.toStringAsFixed(3);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _runLengthCtrl.dispose();
    _pxPerFtCtrl.dispose();
    _notesCtrl.dispose();
    _priceCtrl.dispose();
    _connectorRunCtrl.dispose();
    super.dispose();
  }

  double get _effectivePxPerFt {
    if (_productType == ProductType.custom) {
      return double.tryParse(_pxPerFtCtrl.text) ?? 0;
    }
    return _productType.pixelsPerFoot;
  }

  double get _runLength => double.tryParse(_runLengthCtrl.text) ?? 0;

  void _onProductTypeChanged(ProductType type) {
    setState(() {
      _productType = type;
      if (type != ProductType.custom) {
        _pxPerFtCtrl.text = type.pixelsPerFoot.toStringAsFixed(3);
      }
      if (type != ProductType.roofline) {
        _railType = RailType.none;
        _railColor = RailColor.none;
      }
    });
    _recalculate();
  }

  void _recalculate() {
    final pxPerFt = _effectivePxPerFt;
    final runFt = _runLength;
    if (pxPerFt <= 0 || runFt <= 0) {
      setState(() {
        _injections = [];
        _mounts = [];
      });
      return;
    }

    final minFt = minPixelsPerSegment / pxPerFt;
    final maxFt = maxPixelsPerSegment / pxPerFt;

    // Calculate injection count
    int injCount;
    if (runFt <= minFt) {
      injCount = 0;
    } else {
      injCount = max(1, (runFt / maxFt).ceil() - 1);
    }

    // Slots used by OTHER zones
    int otherSlots = 0;
    for (int i = 0; i < widget.allZones.length; i++) {
      if (i != widget.editIndex) {
        otherSlots += widget.allZones[i].controllerSlotCount;
      }
    }
    final availableSlots = max(0, controllerCapacitySlots - otherSlots);

    // Build injections
    final newInjections = <InjectionPoint>[];
    for (int i = 0; i < injCount; i++) {
      // Spread evenly
      final pos = runFt * (i + 1) / (injCount + 1);
      final byController = i < availableSlots;
      newInjections.add(InjectionPoint(
        id: 'inj_$i',
        positionFt: double.parse(pos.toStringAsFixed(1)),
        servedByController: byController,
        wireGauge: WireGauge.direct, // will be set after mounts
        wireRunFt: 0,
      ));
    }

    // Build mounts
    final newMounts = <PowerMount>[];

    // Controller mount at 0ft
    final controllerInjIds = newInjections
        .where((inj) => inj.servedByController)
        .map((inj) => inj.id)
        .toList();
    newMounts.add(PowerMount(
      id: 'mount_controller',
      positionFt: 0,
      isController: true,
      supplySize: 'controller',
      servesInjectionIds: controllerInjIds,
    ));

    // Additional supply mounts
    final additionalInjs = newInjections.where((inj) => !inj.servedByController).toList();
    if (additionalInjs.isNotEmpty) {
      final supplySize = _recommendSupplySize(additionalInjs.length);
      // Center the mount between additional injections
      final avgPos = additionalInjs.fold(0.0, (acc, inj) => acc + inj.positionFt) /
          additionalInjs.length;
      newMounts.add(PowerMount(
        id: 'mount_supply_0',
        positionFt: double.parse(avgPos.toStringAsFixed(1)),
        isController: false,
        supplySize: supplySize,
        servesInjectionIds: additionalInjs.map((inj) => inj.id).toList(),
      ));
    }

    // Recalculate wire gauge per injection
    final finalInjections = newInjections.map((inj) {
      final mount = newMounts.firstWhere(
        (m) => m.servesInjectionIds.contains(inj.id),
        orElse: () => newMounts.first,
      );
      final dist = (inj.positionFt - mount.positionFt).abs();
      return InjectionPoint(
        id: inj.id,
        positionFt: inj.positionFt,
        servedByController: inj.servedByController,
        wireGauge: WireGaugeX.fromDistance(dist),
        wireRunFt: double.parse(dist.toStringAsFixed(1)),
        architecturalNote: inj.architecturalNote,
      );
    }).toList();

    setState(() {
      _injections = finalInjections;
      _mounts = newMounts;
    });
  }

  String _recommendSupplySize(int extraInjections) {
    if (extraInjections <= 2) return '350w';
    if (extraInjections <= 4) return '600w';
    if (extraInjections <= 6) return '600w + 350w';
    return '2× 600w';
  }

  Future<void> _addPhoto() async {
    if (_photoUrls.length >= 4) return;

    final picker = ImagePicker();
    final image = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1920,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (image == null || !mounted) return;

    setState(() => _isUploadingPhoto = true);
    try {
      final zoneId = widget.existing?.id ?? 'zone_${DateTime.now().millisecondsSinceEpoch}';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sales_jobs/${widget.jobId}/zones/$zoneId/photo_$timestamp.jpg');
      final bytes = await image.readAsBytes();
      await storageRef.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await storageRef.getDownloadURL();

      if (mounted) setState(() => _photoUrls.add(url));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Upload failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isUploadingPhoto = false);
    }
  }

  void _save() {
    final name = _nameCtrl.text.trim();
    final runFt = _runLength;

    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Zone name is required')),
      );
      return;
    }
    if (runFt <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Run length must be greater than 0')),
      );
      return;
    }

    final zone = InstallZone(
      id: widget.existing?.id ?? 'zone_${DateTime.now().millisecondsSinceEpoch}',
      name: name,
      runLengthFt: runFt,
      productType: _productType,
      pixelsPerFoot: _effectivePxPerFt,
      colorPreset: _colorPreset,
      injections: _injections,
      mounts: _mounts,
      photoUrls: _photoUrls,
      notes: _notesCtrl.text.trim(),
      priceUsd: double.tryParse(_priceCtrl.text) ?? 0,
      railType: _railType,
      railColor: _railColor,
      connectorRunFt: double.tryParse(_connectorRunCtrl.text) ?? 0,
    );

    Navigator.of(context).pop(zone);
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.92,
      ),
      decoration: const BoxDecoration(
        color: NexGenPalette.gunmetal,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(bottom: bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Center(
            child: Container(
              margin: const EdgeInsets.only(top: 12, bottom: 8),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          // Header
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              children: [
                Text(
                  widget.existing != null ? 'Edit Zone' : 'New Zone',
                  style: const TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                ),
                const Spacer(),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),

          // Scrollable body
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Section A: Zone basics ──
                  _sectionHeader('Zone basics'),
                  const SizedBox(height: 12),
                  _buildField(controller: _nameCtrl, label: 'Zone name', hint: 'e.g. Front roofline', icon: Icons.layers_outlined),
                  const SizedBox(height: 12),

                  // Product type selector
                  const Text('Product type', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
                  const SizedBox(height: 8),
                  _buildProductTypeSelector(),
                  const SizedBox(height: 12),

                  // Pixels per foot (editable only for custom)
                  if (_productType == ProductType.custom) ...[
                    _buildField(
                      controller: _pxPerFtCtrl,
                      label: 'Pixels per foot',
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => _recalculate(),
                    ),
                    const SizedBox(height: 12),
                  ],

                  // Run length
                  _buildField(
                    controller: _runLengthCtrl,
                    label: 'Run length (ft)',
                    icon: Icons.straighten,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    onChanged: (_) => _recalculate(),
                  ),
                  const SizedBox(height: 12),

                  // Rail type (roofline only)
                  if (_productType == ProductType.roofline) ...[
                    const Text('Rail type', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildRailTypeSelector(),
                    const SizedBox(height: 12),
                  ],

                  // Rail color (when rail is selected)
                  if (_railType != RailType.none) ...[
                    const Text('Rail color', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
                    const SizedBox(height: 8),
                    _buildRailColorGrid(),
                    const SizedBox(height: 12),
                  ],

                  // Connector run distance
                  _buildField(
                    controller: _connectorRunCtrl,
                    label: 'Connector run to this zone (ft)',
                    icon: Icons.cable,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(left: 12, top: 4),
                    child: Text(
                      'Estimated distance from controller or previous zone',
                      style: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.6), fontSize: 11),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Color preset
                  const Text('Color preset', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13)),
                  const SizedBox(height: 8),
                  _buildColorPresetRow(),
                  const SizedBox(height: 12),

                  // Notes
                  _buildField(controller: _notesCtrl, label: 'Zone notes', maxLines: 2),
                  const SizedBox(height: 24),

                  // ── Section B: Injection & power ──
                  if (_runLength > 0 && _effectivePxPerFt > 0) ...[
                    _sectionHeader('Injection & power'),
                    const SizedBox(height: 12),
                    _buildRunBar(),
                    const SizedBox(height: 12),
                    _buildInjectionSummary(),
                    const SizedBox(height: 8),
                    ..._buildInjectionDetails(),
                    const SizedBox(height: 8),
                    ..._buildMountDetails(),
                    const SizedBox(height: 24),
                  ],

                  // ── Section C: Photos ──
                  _sectionHeader('Zone photos'),
                  const SizedBox(height: 8),
                  _buildPhotoRow(),
                  const SizedBox(height: 24),

                  // ── Section D: Pricing ──
                  _sectionHeader('Pricing'),
                  const SizedBox(height: 12),
                  _buildField(
                    controller: _priceCtrl,
                    label: 'Zone price (USD)',
                    icon: Icons.attach_money,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
          ),

          // Save button
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _save,
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text(
                  'Save zone',
                  style: TextStyle(color: Colors.black, fontWeight: FontWeight.w600, fontSize: 16),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── UI helpers ──────────────────────────────────────────────

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: TextStyle(color: NexGenPalette.cyan, fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.5),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    String? hint,
    IconData? icon,
    TextInputType? keyboardType,
    int maxLines = 1,
    void Function(String)? onChanged,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      maxLines: maxLines,
      onChanged: onChanged,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: NexGenPalette.textMedium),
        hintText: hint,
        hintStyle: TextStyle(color: NexGenPalette.textMedium.withValues(alpha: 0.5)),
        prefixIcon: icon != null ? Icon(icon, color: NexGenPalette.textMedium) : null,
        filled: true,
        fillColor: NexGenPalette.gunmetal90,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: NexGenPalette.line)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: NexGenPalette.line)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: NexGenPalette.cyan)),
      ),
    );
  }

  Widget _buildProductTypeSelector() {
    return Row(
      children: ProductType.values.map((type) {
        final selected = _productType == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: type != ProductType.custom ? 8 : 0),
            child: GestureDetector(
              onTap: () => _onProductTypeChanged(type),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.line,
                  ),
                ),
                child: Text(
                  type == ProductType.roofline
                      ? 'Roofline'
                      : type == ProductType.diffusedRope
                          ? 'Rope'
                          : 'Custom',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildColorPresetRow() {
    const presetColors = {
      ColorPreset.rgbw: [Colors.red, Colors.green, Colors.blue, Colors.white],
      ColorPreset.warmWhite: [Color(0xFFFFD180)],
      ColorPreset.coolWhite: [Color(0xFFB3E5FC)],
      ColorPreset.fullRgb: [Colors.red, Colors.green, Colors.blue],
    };

    return Row(
      children: ColorPreset.values.map((preset) {
        final selected = _colorPreset == preset;
        final colors = presetColors[preset]!;

        return Padding(
          padding: const EdgeInsets.only(right: 12),
          child: GestureDetector(
            onTap: () => setState(() => _colorPreset = preset),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: colors.length > 1
                        ? SweepGradient(colors: [...colors, colors.first])
                        : null,
                    color: colors.length == 1 ? colors.first : null,
                    border: Border.all(
                      color: selected ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.2),
                      width: selected ? 2 : 1,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  preset.label,
                  style: TextStyle(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRailTypeSelector() {
    final options = [RailType.onePiece, RailType.twoPiece];
    return Row(
      children: options.map((type) {
        final selected = _railType == type;
        return Expanded(
          child: Padding(
            padding: EdgeInsets.only(right: type != options.last ? 8 : 0),
            child: GestureDetector(
              onTap: () => setState(() {
                _railType = type;
                if (_railColor == RailColor.none) {
                  _railColor = RailColor.black;
                }
              }),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: selected ? NexGenPalette.cyan.withValues(alpha: 0.15) : NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.line,
                  ),
                ),
                child: Text(
                  type.label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                    fontSize: 13,
                    fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildRailColorGrid() {
    const colorOptions = <RailColor, Color>{
      RailColor.black:  Color(0xFF1C1C1C),
      RailColor.brown:  Color(0xFF5C3D1E),
      RailColor.beige:  Color(0xFFD4B896),
      RailColor.white:  Color(0xFFF5F5F5),
      RailColor.navy:   Color(0xFF1B2A4A),
      RailColor.silver: Color(0xFFA8A8A8),
      RailColor.grey:   Color(0xFF6B6B6B),
    };

    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: colorOptions.entries.map((entry) {
        final railColor = entry.key;
        final displayColor = entry.value;
        final selected = _railColor == railColor;

        return GestureDetector(
          onTap: () => setState(() => _railColor = railColor),
          child: Column(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: displayColor,
                  border: Border.all(
                    color: selected ? NexGenPalette.cyan : Colors.white.withValues(alpha: 0.2),
                    width: selected ? 2 : 1,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                railColor.label,
                style: TextStyle(
                  color: selected ? NexGenPalette.cyan : NexGenPalette.textMedium,
                  fontSize: 10,
                ),
              ),
            ],
          ),
        );
      }).toList(),
    );
  }

  // ── Run bar visualization ───────────────────────────────────

  Widget _buildRunBar() {
    final runFt = _runLength;
    if (runFt <= 0) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Bar
        Container(
          height: 40,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            color: NexGenPalette.gunmetal90,
            border: Border.all(color: NexGenPalette.line),
          ),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final barWidth = constraints.maxWidth;
              return Stack(
                clipBehavior: Clip.none,
                children: [
                  // Green safe zone fill
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(5),
                      child: Container(color: NexGenPalette.green.withValues(alpha: 0.15)),
                    ),
                  ),
                  // Injection markers (diamonds)
                  ..._injections.map((inj) {
                    final x = (inj.positionFt / runFt) * barWidth;
                    final color = inj.servedByController
                        ? NexGenPalette.cyan
                        : const Color(0xFFFF6B6B);
                    return Positioned(
                      left: x - 6,
                      top: 8,
                      child: Transform.rotate(
                        angle: 0.785, // 45 degrees
                        child: Container(
                          width: 12,
                          height: 12,
                          decoration: BoxDecoration(
                            color: color,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    );
                  }),
                  // Mount markers (squares)
                  ..._mounts.map((m) {
                    final x = (m.positionFt / runFt) * barWidth;
                    return Positioned(
                      left: x - 5,
                      bottom: 4,
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          color: m.isController ? NexGenPalette.violet : NexGenPalette.amber,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    );
                  }),
                ],
              );
            },
          ),
        ),
        const SizedBox(height: 6),
        // Legend
        Row(
          children: [
            _legendDot(NexGenPalette.cyan, 'Controller inj.'),
            const SizedBox(width: 12),
            _legendDot(const Color(0xFFFF6B6B), 'Add\'l inj.'),
            const SizedBox(width: 12),
            _legendDot(NexGenPalette.violet, 'Controller'),
            const SizedBox(width: 12),
            _legendDot(NexGenPalette.amber, 'Supply'),
          ],
        ),
      ],
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(width: 8, height: 8, decoration: BoxDecoration(color: color, borderRadius: BorderRadius.circular(2))),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: NexGenPalette.textMedium, fontSize: 10)),
      ],
    );
  }

  Widget _buildInjectionSummary() {
    final additional = _injections.where((i) => !i.servedByController).length;
    final supplyRec = additional > 0 ? _recommendSupplySize(additional) : null;

    return Row(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Text(
            '${_injections.length} injection${_injections.length == 1 ? '' : 's'} required',
            style: TextStyle(color: NexGenPalette.cyan, fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ),
        if (supplyRec != null) ...[
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: NexGenPalette.amber.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              'Supply: $supplyRec',
              style: TextStyle(color: NexGenPalette.amber, fontSize: 12, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  List<Widget> _buildInjectionDetails() {
    return _injections.map((inj) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Icon(
                Icons.diamond_outlined,
                size: 14,
                color: inj.servedByController ? NexGenPalette.cyan : const Color(0xFFFF6B6B),
              ),
              const SizedBox(width: 8),
              Text(
                '${inj.positionFt.toStringAsFixed(1)} ft',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: inj.wireGauge == WireGauge.exceeds
                      ? Colors.red.withValues(alpha: 0.15)
                      : NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  inj.wireGauge.label,
                  style: TextStyle(
                    color: inj.wireGauge == WireGauge.exceeds ? Colors.red : NexGenPalette.textMedium,
                    fontSize: 11,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${inj.wireRunFt.toStringAsFixed(0)} ft run',
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
              ),
              const Spacer(),
              Text(
                inj.servedByController ? 'Controller' : 'Add\'l supply',
                style: TextStyle(
                  color: inj.servedByController ? NexGenPalette.cyan : const Color(0xFFFF6B6B),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  List<Widget> _buildMountDetails() {
    return _mounts.map((m) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Icon(
                Icons.electrical_services,
                size: 14,
                color: m.isController ? NexGenPalette.violet : NexGenPalette.amber,
              ),
              const SizedBox(width: 8),
              Text(
                '${m.positionFt.toStringAsFixed(1)} ft',
                style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w500),
              ),
              const SizedBox(width: 12),
              Text(
                m.supplySize,
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
              ),
              const Spacer(),
              Text(
                m.outletType.label,
                style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ── Photo row ───────────────────────────────────────────────

  Widget _buildPhotoRow() {
    return SizedBox(
      height: 108,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _photoUrls.length + (_photoUrls.length < 4 ? 1 : 0),
        separatorBuilder: (_, __) => const SizedBox(width: 10),
        itemBuilder: (context, i) {
          if (i == _photoUrls.length) {
            return GestureDetector(
              onTap: _isUploadingPhoto ? null : _addPhoto,
              child: Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3)),
                ),
                child: _isUploadingPhoto
                    ? const Center(child: SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan)))
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.add_a_photo_outlined, color: NexGenPalette.cyan, size: 28),
                          const SizedBox(height: 4),
                          Text('Add photo', style: TextStyle(color: NexGenPalette.cyan, fontSize: 11)),
                        ],
                      ),
              ),
            );
          }
          return Stack(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.network(_photoUrls[i], width: 100, height: 100, fit: BoxFit.cover),
              ),
              Positioned(
                top: 4,
                right: 4,
                child: GestureDetector(
                  onTap: () => setState(() => _photoUrls.removeAt(i)),
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                    child: const Icon(Icons.close, color: Colors.white, size: 16),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
