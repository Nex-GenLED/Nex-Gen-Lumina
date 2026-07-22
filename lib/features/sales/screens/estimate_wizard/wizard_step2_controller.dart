import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/models/sales_models.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/estimate_wizard_notifier.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_form_fields.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_photo_capture.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_shell.dart';
import 'package:nexgen_command/theme.dart';

/// Step 2 of the Estimate Wizard: where will the WLED controller be
/// mounted? Captures location text, interior/exterior toggle, distance
/// to nearest outlet, and an optional photo.
class WizardStep2Controller extends ConsumerStatefulWidget {
  final String jobId;
  const WizardStep2Controller({super.key, required this.jobId});

  @override
  ConsumerState<WizardStep2Controller> createState() =>
      _WizardStep2ControllerState();
}

class _WizardStep2ControllerState extends ConsumerState<WizardStep2Controller> {
  final _locationCtrl = TextEditingController();
  final _outletDistanceCtrl = TextEditingController();
  bool _isInterior = true;
  String? _photoPath;
  bool _isUploading = false;
  bool _initialized = false;

  @override
  void dispose() {
    _locationCtrl.dispose();
    _outletDistanceCtrl.dispose();
    super.dispose();
  }

  void _hydrateFromState(SalesJob job) {
    if (_initialized) return;
    final mount = job.controllerMount;
    if (mount != null) {
      _locationCtrl.text = mount.locationDescription;
      _isInterior = mount.isInteriorMount;
      _photoPath = mount.photoPath;
      if (mount.distanceFromOutletFeet != null) {
        _outletDistanceCtrl.text =
            mount.distanceFromOutletFeet!.toStringAsFixed(1);
      }
    }
    _initialized = true;
  }

  Future<void> _capturePhoto() async {
    setState(() => _isUploading = true);
    try {
      final url = await pickAndUploadWizardPhoto(
        context: context,
        jobId: widget.jobId,
        subPath: 'controller_mount',
      );
      if (url != null) setState(() => _photoPath = url);
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _commitToWizardState() {
    final mount = ControllerMount(
      id: ref
              .read(estimateWizardProvider(widget.jobId))
              .controllerMount
              ?.id ??
          'controller_mount_${DateTime.now().millisecondsSinceEpoch}',
      locationDescription: _locationCtrl.text.trim(),
      photoPath: _photoPath,
      isInteriorMount: _isInterior,
      distanceFromOutletFeet: double.tryParse(_outletDistanceCtrl.text),
    );
    ref
        .read(estimateWizardProvider(widget.jobId).notifier)
        .updateControllerMount(mount);
  }

  void _continue() {
    if (_locationCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add a location description first')),
      );
      return;
    }
    _commitToWizardState();
    context.push(
      AppRoutes.salesWizardStep3.replaceFirst(':jobId', widget.jobId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(estimateWizardProvider(widget.jobId));
    _hydrateFromState(job);
    final hasPhoto = _photoPath != null && _photoPath!.isNotEmpty;

    return WizardShell(
      stepNumber: 2,
      stepTitle: 'Controller placement',
      jobId: widget.jobId,
      bottomAction: WizardContinueButton(onPressed: _continue),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const WizardSectionHeader(
              title: 'WHERE DOES THE CONTROLLER MOUNT?',
              subtitle:
                  'The Day 1 electrician will run wire to this location.',
            ),
            const SizedBox(height: 16),

            WizardTextField(
              controller: _locationCtrl,
              label: 'Location description',
              hint: 'e.g. Garage left interior wall, near breaker panel',
              icon: Icons.place_outlined,
              maxLines: 2,
              onChanged: (_) => _commitToWizardState(),
            ),
            const SizedBox(height: 20),

            const Text(
              'Mount type',
              style: TextStyle(
                color: NexGenPalette.textMedium,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 8),
            WizardSegmentedSelector<bool>(
              values: const [true, false],
              selected: _isInterior,
              labelBuilder: (v) => v ? 'Interior' : 'Exterior',
              onChanged: (v) {
                setState(() => _isInterior = v);
                _commitToWizardState();
              },
            ),
            const SizedBox(height: 20),

            WizardTextField(
              controller: _outletDistanceCtrl,
              label: 'Distance to nearest outlet (ft)',
              icon: Icons.electrical_services,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]')),
              ],
              onChanged: (_) => _commitToWizardState(),
            ),
            const SizedBox(height: 20),

            const WizardSectionHeader(title: 'CONTROLLER LOCATION PHOTO'),
            const SizedBox(height: 12),

            AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Image.network(
                        _photoPath!,
                        fit: BoxFit.cover,
                        loadingBuilder: (_, child, progress) {
                          if (progress == null) return child;
                          return const Center(
                            child: CircularProgressIndicator(
                              color: NexGenPalette.cyan,
                              strokeWidth: 2,
                            ),
                          );
                        },
                        errorBuilder: (_, __, ___) => const Center(
                          child: Icon(
                            Icons.broken_image_outlined,
                            color: Colors.white24,
                            size: 48,
                          ),
                        ),
                      )
                    : Center(
                        child: Icon(
                          Icons.developer_board,
                          color: Colors.white.withValues(alpha: 0.2),
                          size: 56,
                        ),
                      ),
              ),
            ),
            const SizedBox(height: 12),

            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _isUploading ? null : _capturePhoto,
                icon: _isUploading
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: NexGenPalette.cyan,
                        ),
                      )
                    : Icon(Icons.add_a_photo_outlined,
                        color: NexGenPalette.cyan),
                label: Text(
                  hasPhoto ? 'Replace photo' : 'Capture photo',
                  style: TextStyle(color: NexGenPalette.cyan),
                ),
                style: OutlinedButton.styleFrom(
                  side: BorderSide(
                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
