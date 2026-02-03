import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';

/// Demo photo capture screen.
///
/// Allows users to:
/// - Take a photo of their home
/// - Upload a photo from gallery
/// - Use a stock demo home image
class DemoPhotoScreen extends ConsumerStatefulWidget {
  const DemoPhotoScreen({super.key});

  @override
  ConsumerState<DemoPhotoScreen> createState() => _DemoPhotoScreenState();
}

class _DemoPhotoScreenState extends ConsumerState<DemoPhotoScreen> {
  final ImagePicker _picker = ImagePicker();
  Uint8List? _capturedPhoto;
  bool _isLoading = false;

  Future<void> _takePhoto() async {
    setState(() => _isLoading = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.camera,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedPhoto = bytes;
        });
        ref.read(demoPhotoProvider.notifier).state = bytes;
        ref.read(demoUsingStockPhotoProvider.notifier).state = false;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access camera: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickFromGallery() async {
    setState(() => _isLoading = true);
    try {
      final XFile? photo = await _picker.pickImage(
        source: ImageSource.gallery,
        maxWidth: 1920,
        maxHeight: 1080,
        imageQuality: 85,
      );

      if (photo != null) {
        final bytes = await photo.readAsBytes();
        setState(() {
          _capturedPhoto = bytes;
        });
        ref.read(demoPhotoProvider.notifier).state = bytes;
        ref.read(demoUsingStockPhotoProvider.notifier).state = false;
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access gallery: $e')),
      );
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _useStockPhoto() {
    ref.read(demoUsingStockPhotoProvider.notifier).state = true;
    ref.read(demoPhotoProvider.notifier).state = null;
    _continueToNext();
  }

  void _continueToNext() {
    ref.read(demoFlowProvider.notifier).goToStep(DemoStep.rooflineSetup);
    context.push(AppRoutes.demoRoofline);
  }

  @override
  Widget build(BuildContext context) {
    return DemoScaffold(
      title: 'Capture Your Home',
      subtitle: 'Take a photo of your roofline to see how Nex-Gen lights will look',
      showSkip: true,
      onSkip: _useStockPhoto,
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          children: [
            const SizedBox(height: 16),

            // Photo preview or placeholder
            AspectRatio(
              aspectRatio: 16 / 10,
              child: Container(
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _capturedPhoto != null
                        ? NexGenPalette.cyan
                        : NexGenPalette.line,
                    width: _capturedPhoto != null ? 2 : 1,
                  ),
                  boxShadow: _capturedPhoto != null
                      ? [
                          BoxShadow(
                            color: NexGenPalette.cyan.withOpacity(0.2),
                            blurRadius: 12,
                            spreadRadius: 2,
                          ),
                        ]
                      : null,
                ),
                clipBehavior: Clip.antiAlias,
                child: _capturedPhoto != null
                    ? Stack(
                        fit: StackFit.expand,
                        children: [
                          Image.memory(
                            _capturedPhoto!,
                            fit: BoxFit.cover,
                          ),
                          // Edit overlay
                          Positioned(
                            bottom: 12,
                            right: 12,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.black.withOpacity(0.7),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(
                                    Icons.check_circle,
                                    size: 16,
                                    color: NexGenPalette.cyan,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Photo captured',
                                    style: Theme.of(context)
                                        .textTheme
                                        .labelSmall
                                        ?.copyWith(
                                          color: Colors.white,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      )
                    : Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.home_outlined,
                            size: 64,
                            color: NexGenPalette.textMedium.withOpacity(0.5),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'No photo yet',
                            style:
                                Theme.of(context).textTheme.bodyLarge?.copyWith(
                                      color: NexGenPalette.textMedium,
                                    ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Capture your roofline for a personalized preview',
                            style:
                                Theme.of(context).textTheme.bodySmall?.copyWith(
                                      color: NexGenPalette.textMedium
                                          .withOpacity(0.7),
                                    ),
                            textAlign: TextAlign.center,
                          ),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 32),

            // Photo capture buttons
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else ...[
              // Take photo button
              DemoPrimaryButton(
                label: 'Take Photo',
                icon: Icons.camera_alt,
                onPressed: _takePhoto,
              ),

              const SizedBox(height: 12),

              // Upload from gallery
              DemoSecondaryButton(
                label: 'Upload from Gallery',
                icon: Icons.photo_library_outlined,
                onPressed: _pickFromGallery,
              ),

              const SizedBox(height: 24),

              // Divider
              Row(
                children: [
                  Expanded(
                    child: Divider(
                      color: NexGenPalette.line.withOpacity(0.5),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Text(
                      'or',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                  ),
                  Expanded(
                    child: Divider(
                      color: NexGenPalette.line.withOpacity(0.5),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Use stock photo
              TextButton.icon(
                onPressed: _useStockPhoto,
                icon: const Icon(Icons.image_outlined),
                label: const Text('Use Sample Home Instead'),
              ),

              const SizedBox(height: 16),

              // Tip
              DemoInfoBanner(
                message:
                    'Tip: For best results, capture your home\'s roofline during daylight from across the street.',
                icon: Icons.lightbulb_outline,
              ),
            ],

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomAction: _capturedPhoto != null
          ? DemoPrimaryButton(
              label: 'Continue',
              icon: Icons.arrow_forward,
              onPressed: _continueToNext,
            )
          : null,
    );
  }
}
