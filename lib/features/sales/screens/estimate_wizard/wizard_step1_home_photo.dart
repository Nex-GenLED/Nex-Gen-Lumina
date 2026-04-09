import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/estimate_wizard_notifier.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_photo_capture.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/widgets/wizard_shell.dart';
import 'package:nexgen_command/theme.dart';

/// Step 1 of the Estimate Wizard: capture or pick the primary home photo
/// used as the blueprint background. Skippable.
class WizardStep1HomePhoto extends ConsumerStatefulWidget {
  final String jobId;
  const WizardStep1HomePhoto({super.key, required this.jobId});

  @override
  ConsumerState<WizardStep1HomePhoto> createState() =>
      _WizardStep1HomePhotoState();
}

class _WizardStep1HomePhotoState extends ConsumerState<WizardStep1HomePhoto> {
  bool _isUploading = false;

  Future<void> _capturePhoto() async {
    setState(() => _isUploading = true);
    try {
      final url = await pickAndUploadWizardPhoto(
        context: context,
        jobId: widget.jobId,
        subPath: 'home_photo',
      );
      if (url != null) {
        ref
            .read(estimateWizardProvider(widget.jobId).notifier)
            .updateHomePhotoPath(url);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  void _continue() {
    context.push(
      AppRoutes.salesWizardStep2.replaceFirst(':jobId', widget.jobId),
    );
  }

  @override
  Widget build(BuildContext context) {
    final job = ref.watch(estimateWizardProvider(widget.jobId));
    final hasPhoto =
        job.homePhotoPath != null && job.homePhotoPath!.isNotEmpty;

    return WizardShell(
      stepNumber: 1,
      stepTitle: 'Home photo',
      jobId: widget.jobId,
      bottomAction: WizardContinueButton(
        onPressed: _continue,
        label: hasPhoto ? 'Continue →' : 'Skip for now →',
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Photograph the front of the home',
              style: TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'This photo will be used as the blueprint background for the '
              'install team. You can add it later from the job detail screen.',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 24),

            // Photo preview / placeholder
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: NexGenPalette.line),
                ),
                clipBehavior: Clip.antiAlias,
                child: hasPhoto
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.network(
                            job.homePhotoPath!,
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
                            errorBuilder: (_, __, ___) =>
                                _placeholder(error: true),
                          ),
                          Positioned(
                            right: 12,
                            bottom: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black54,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.check_circle,
                                      color: NexGenPalette.green, size: 14),
                                  SizedBox(width: 6),
                                  Text(
                                    'Saved',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : _placeholder(),
              ),
            ),
            const SizedBox(height: 16),

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
                  hasPhoto ? 'Replace photo' : 'Capture or choose photo',
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

  Widget _placeholder({bool error = false}) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            error ? Icons.broken_image_outlined : Icons.home_outlined,
            color: Colors.white.withValues(alpha: 0.2),
            size: 56,
          ),
          const SizedBox(height: 12),
          Text(
            error ? 'Could not load photo' : 'No photo yet',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.4),
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }
}
