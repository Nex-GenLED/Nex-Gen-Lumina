import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import 'package:nexgen_command/features/sales/models/material_models.dart';
import 'package:nexgen_command/features/sales/providers/material_providers.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Day 1 Check-In Screen
//
// After checkout, the installer logs what was actually used on Day 1.
// Materials remain reserved until the final check-in.
// ─────────────────────────────────────────────────────────────────────────────

class MaterialDay1CheckInScreen extends ConsumerStatefulWidget {
  final String jobId;
  const MaterialDay1CheckInScreen({super.key, required this.jobId});

  @override
  ConsumerState<MaterialDay1CheckInScreen> createState() =>
      _MaterialDay1CheckInScreenState();
}

class _MaterialDay1CheckInScreenState
    extends ConsumerState<MaterialDay1CheckInScreen> {
  /// Per-line usedDay1 input, keyed by materialId.
  final Map<String, double> _usedDay1 = {};

  /// Per-line photo URLs, keyed by materialId.
  final Map<String, String> _photoUrls = {};

  /// Per-line photo uploading state.
  final Map<String, bool> _uploading = {};

  bool _isSaving = false;
  bool _isSaved = false;

  final _picker = ImagePicker();

  double _getUsedDay1(JobMaterialLine line) =>
      _usedDay1[line.materialId] ?? 0;

  double _getRemaining(JobMaterialLine line) =>
      line.checkedOutQty - _getUsedDay1(line);

  /// Check if any usedDay1 exceeds checkedOutQty.
  bool _hasOverUse(List<JobMaterialLine> lines) {
    for (final line in lines) {
      if (_getUsedDay1(line) > line.checkedOutQty) return true;
    }
    return false;
  }

  Future<void> _takePhoto(String materialId) async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );
      if (image == null || !mounted) return;

      setState(() => _uploading[materialId] = true);

      final bytes = await image.readAsBytes();
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref()
          .child('sales_jobs/${widget.jobId}/day1/$materialId/$timestamp.jpg');
      await storageRef.putData(
          bytes, SettableMetadata(contentType: 'image/jpeg'));
      final url = await storageRef.getDownloadURL();

      if (mounted) {
        setState(() {
          _photoUrls[materialId] = url;
          _uploading[materialId] = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _uploading[materialId] = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Photo upload failed: $e')),
        );
      }
    }
  }

  Future<void> _saveDay1Report(JobMaterialList matList) async {
    // Validate
    if (_hasOverUse(matList.lines)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Used today cannot exceed checked-out quantity')),
      );
      return;
    }

    setState(() => _isSaving = true);
    try {
      final session = ref.read(currentSalesSessionProvider);
      final invService = ref.read(inventoryServiceProvider);

      final updatedLines = matList.lines.map((line) {
        return JobMaterialLine(
          materialId: line.materialId,
          materialName: line.materialName,
          unit: line.unit,
          calculatedQty: line.calculatedQty,
          overageQty: line.overageQty,
          checkedOutQty: line.checkedOutQty,
          usedDay1: _usedDay1[line.materialId] ?? 0,
        );
      }).toList();

      await invService.checkInDay1(
        jobId: widget.jobId,
        dealerCode: session?.dealerCode ?? matList.dealerCode,
        installerId: session?.salespersonUid ?? 'unknown',
        updatedLines: updatedLines,
      );

      if (mounted) setState(() => _isSaved = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final matListAsync = ref.watch(jobMaterialListProvider(widget.jobId));

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: const Text('Day 1 Check-In'),
      ),
      body: matListAsync.when(
        loading: () => const Center(
            child: CircularProgressIndicator(color: NexGenPalette.cyan)),
        error: (e, _) => Center(
            child: Text('Error: $e',
                style: const TextStyle(color: Colors.white))),
        data: (matList) {
          if (matList == null) {
            return _buildGuard('No material list found');
          }
          // Allow viewing if already day1Complete (read-only)
          if (matList.status != JobMaterialStatus.checkedOut &&
              matList.status != JobMaterialStatus.day1Complete) {
            return _buildGuard(
                'Not ready for Day 1 — status is "${matList.status.name}"');
          }
          // If already saved in Firestore, force read-only
          final readOnly =
              _isSaved || matList.status == JobMaterialStatus.day1Complete;
          return _buildCheckInView(matList, readOnly);
        },
      ),
    );
  }

  // ── Guard ──────────────────────────────────────────────────────────────

  Widget _buildGuard(String message) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.block,
              size: 48, color: Colors.white.withValues(alpha: 0.2)),
          const SizedBox(height: 16),
          Text(message,
              style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 15)),
          const SizedBox(height: 24),
          OutlinedButton(
            onPressed: () => Navigator.of(context).maybePop(),
            style: OutlinedButton.styleFrom(
              side: BorderSide(
                  color: NexGenPalette.cyan.withValues(alpha: 0.3)),
              padding:
                  const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
            ),
            child:
                Text('Go back', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  // ── Check-in view ──────────────────────────────────────────────────────

  Widget _buildCheckInView(JobMaterialList matList, bool readOnly) {
    // Pre-fill from Firestore values if returning to a saved state
    if (readOnly && _usedDay1.isEmpty) {
      for (final line in matList.lines) {
        _usedDay1[line.materialId] = line.usedDay1;
      }
    }

    final hasError = _hasOverUse(matList.lines);

    return Column(
      children: [
        // Phase indicator
        _buildPhaseBar(2),

        // Banner
        Container(
          width: double.infinity,
          margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: NexGenPalette.cyan.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              Icon(Icons.info_outline,
                  size: 16, color: NexGenPalette.cyan),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Log what you used today. Materials stay reserved until the job is complete.',
                  style: TextStyle(color: NexGenPalette.cyan, fontSize: 12),
                ),
              ),
            ],
          ),
        ),

        // Lines
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: matList.lines.length,
            itemBuilder: (context, i) =>
                _buildLineRow(matList.lines[i], readOnly),
          ),
        ),

        // Bottom bar
        _buildBottomBar(matList, readOnly, hasError),
      ],
    );
  }

  // ── Phase indicator ────────────────────────────────────────────────────

  Widget _buildPhaseBar(int activeIndex) {
    const labels = ['Approved', 'Checked Out', 'Day 1', 'Final'];

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 8, 24, 12),
      child: Row(
        children: List.generate(labels.length, (i) {
          final isComplete = i < activeIndex;
          final isActive = i == activeIndex;
          final color = isComplete
              ? NexGenPalette.green
              : isActive
                  ? NexGenPalette.cyan
                  : NexGenPalette.textMedium;

          return Expanded(
            child: Row(
              children: [
                Container(
                  width: 22,
                  height: 22,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isComplete || isActive
                        ? color.withValues(alpha: 0.15)
                        : Colors.transparent,
                    border: Border.all(color: color, width: 1.5),
                  ),
                  child: isComplete
                      ? Icon(Icons.check, size: 13, color: color)
                      : isActive
                          ? Center(
                              child: Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: color)))
                          : null,
                ),
                const SizedBox(width: 4),
                Text(labels[i],
                    style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight:
                            isActive ? FontWeight.w600 : FontWeight.w400)),
                if (i < labels.length - 1)
                  Expanded(
                    child: Container(
                      height: 1,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isComplete
                          ? NexGenPalette.green.withValues(alpha: 0.4)
                          : NexGenPalette.line,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  // ── Line row ───────────────────────────────────────────────────────────

  Widget _buildLineRow(JobMaterialLine line, bool readOnly) {
    final usedDay1 = _getUsedDay1(line);
    final remaining = _getRemaining(line);
    final overUse = usedDay1 > line.checkedOutQty;
    final hasPhoto = _photoUrls.containsKey(line.materialId);
    final isUploading = _uploading[line.materialId] ?? false;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
            color: overUse
                ? Colors.red.withValues(alpha: 0.5)
                : NexGenPalette.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Row 1: name + camera + checked-out qty
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.materialName,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.w500)),
                    Text(
                      line.unit == MaterialUnit.piece ? 'piece' : 'each',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 10),
                    ),
                  ],
                ),
              ),
              // Camera button
              if (!readOnly)
                GestureDetector(
                  onTap: isUploading
                      ? null
                      : () => _takePhoto(line.materialId),
                  child: Container(
                    width: 32,
                    height: 32,
                    margin: const EdgeInsets.only(right: 8),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: hasPhoto
                          ? NexGenPalette.green.withValues(alpha: 0.15)
                          : NexGenPalette.gunmetal,
                      border: Border.all(
                          color: hasPhoto
                              ? NexGenPalette.green
                              : NexGenPalette.line),
                    ),
                    child: isUploading
                        ? const Padding(
                            padding: EdgeInsets.all(8),
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: NexGenPalette.cyan),
                          )
                        : Icon(
                            hasPhoto
                                ? Icons.check_circle
                                : Icons.camera_alt_outlined,
                            size: 16,
                            color: hasPhoto
                                ? NexGenPalette.green
                                : NexGenPalette.textMedium),
                  ),
                ),
              // Checked-out qty (muted)
              Column(
                children: [
                  Text(line.checkedOutQty.toStringAsFixed(0),
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 13)),
                  Text('pulled',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 9)),
                ],
              ),
            ],
          ),

          // Photo thumbnail
          if (hasPhoto) ...[
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.network(
                _photoUrls[line.materialId]!,
                width: 60,
                height: 60,
                fit: BoxFit.cover,
              ),
            ),
          ],

          const SizedBox(height: 10),

          // Row 2: Used Today input + Remaining readout
          Row(
            children: [
              // Used Today
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Used Today',
                        style: TextStyle(
                            color: NexGenPalette.textMedium, fontSize: 11)),
                    const SizedBox(height: 4),
                    SizedBox(
                      height: 40,
                      child: TextFormField(
                        initialValue: usedDay1 > 0
                            ? usedDay1.toStringAsFixed(0)
                            : '',
                        readOnly: readOnly,
                        keyboardType: TextInputType.number,
                        style: TextStyle(
                            color: overUse ? Colors.red : Colors.white,
                            fontSize: 14),
                        decoration: InputDecoration(
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 8),
                          filled: true,
                          fillColor: NexGenPalette.gunmetal,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide:
                                BorderSide(color: NexGenPalette.line),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: BorderSide(
                                color: overUse
                                    ? Colors.red
                                    : NexGenPalette.line),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                            borderSide: const BorderSide(
                                color: NexGenPalette.cyan),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = double.tryParse(val) ?? 0;
                          setState(() =>
                              _usedDay1[line.materialId] = parsed);
                        },
                      ),
                    ),
                    if (overUse)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text('Exceeds pulled qty',
                            style: TextStyle(
                                color: Colors.red, fontSize: 10)),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Remaining
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text('Remaining',
                      style: TextStyle(
                          color: NexGenPalette.textMedium, fontSize: 11)),
                  const SizedBox(height: 4),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: NexGenPalette.cyan.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      remaining.toStringAsFixed(0),
                      style: TextStyle(
                          color: NexGenPalette.cyan,
                          fontSize: 16,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Bottom bar ─────────────────────────────────────────────────────────

  Widget _buildBottomBar(
      JobMaterialList matList, bool readOnly, bool hasError) {
    final totalUsed = matList.lines.fold(
        0.0, (acc, l) => acc + (_usedDay1[l.materialId] ?? 0));

    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal,
        border: Border(top: BorderSide(color: NexGenPalette.line)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Summary
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('Items used today',
                  style: TextStyle(
                      color: NexGenPalette.textMedium, fontSize: 13)),
              Text(totalUsed.toStringAsFixed(0),
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
          ),
          const SizedBox(height: 12),

          if (!readOnly)
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _isSaving || hasError
                    ? null
                    : () => _saveDay1Report(matList),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.cyan,
                  disabledBackgroundColor:
                      NexGenPalette.cyan.withValues(alpha: 0.3),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: _isSaving
                    ? const SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.black))
                    : Text(
                        hasError
                            ? 'Fix errors before saving'
                            : 'Save Day 1 Report',
                        style: const TextStyle(
                            color: Colors.black,
                            fontWeight: FontWeight.w600,
                            fontSize: 15)),
              ),
            ),

          if (readOnly) ...[
            // Read-only confirmation
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle,
                      size: 18, color: NexGenPalette.green),
                  const SizedBox(width: 6),
                  Text('Day 1 report saved',
                      style: TextStyle(
                          color: NexGenPalette.green,
                          fontSize: 14,
                          fontWeight: FontWeight.w500)),
                ],
              ),
            ),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () => context.push(
                    '/sales/jobs/${widget.jobId}/materials/final'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: NexGenPalette.green,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text('Proceed to Final Check-In',
                    style: TextStyle(
                        color: Colors.black,
                        fontWeight: FontWeight.w600,
                        fontSize: 15)),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
