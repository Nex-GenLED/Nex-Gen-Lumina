import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/image_upload_service.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Widget for uploading and managing the user's house photo.
///
/// Features:
/// - Displays current photo or placeholder
/// - Camera and gallery picker options
/// - "Use Stock Image" toggle
/// - Upload progress indicator
/// - Error handling with retry
class HousePhotoUploader extends ConsumerStatefulWidget {
  /// Callback when photo is successfully uploaded
  final Function(String url)? onPhotoUploaded;

  /// Callback when user selects stock image
  final VoidCallback? onUseStockImage;

  /// Height of the photo preview
  final double previewHeight;

  const HousePhotoUploader({
    super.key,
    this.onPhotoUploaded,
    this.onUseStockImage,
    this.previewHeight = 200,
  });

  @override
  ConsumerState<HousePhotoUploader> createState() => _HousePhotoUploaderState();
}

class _HousePhotoUploaderState extends ConsumerState<HousePhotoUploader> {
  bool _isUploading = false;
  double _uploadProgress = 0.0;
  String? _error;

  Future<void> _pickAndUpload(ImageSource source) async {
    final authState = ref.read(authStateProvider);
    final user = authState.maybeWhen(data: (u) => u, orElse: () => null);
    if (user == null) {
      setState(() => _error = 'Please sign in to upload a photo');
      return;
    }

    setState(() {
      _isUploading = true;
      _uploadProgress = 0.0;
      _error = null;
    });

    try {
      final uploadService = ref.read(imageUploadServiceProvider);
      final downloadUrl = await uploadService.pickAndUploadHousePhoto(
        user.uid,
        source: source,
      );

      if (downloadUrl == null) {
        // User cancelled or upload failed
        if (mounted) {
          setState(() {
            _isUploading = false;
            _uploadProgress = 0.0;
          });
        }
        return;
      }

      // Update user profile with new photo URL
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );

      if (profile != null) {
        final userService = ref.read(userServiceProvider);
        final updatedProfile = profile.copyWith(
          housePhotoUrl: downloadUrl,
          useStockHouseImage: false,
          updatedAt: DateTime.now(),
        );
        await userService.updateUser(updatedProfile);
      }

      if (mounted) {
        setState(() {
          _isUploading = false;
          _uploadProgress = 1.0;
        });
        widget.onPhotoUploaded?.call(downloadUrl);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('House photo uploaded successfully'),
            backgroundColor: Color(0xFF2ECC71),
          ),
        );
      }
    } catch (e, stackTrace) {
      debugPrint('HousePhotoUploader: Upload failed: $e');
      debugPrint('HousePhotoUploader: Stack trace: $stackTrace');
      if (mounted) {
        String errorMsg = 'Upload failed. Please try again.';
        final errorStr = e.toString().toLowerCase();
        if (errorStr.contains('permission')) {
          errorMsg = 'Permission denied. Please grant photo access in Settings.';
        } else if (errorStr.contains('network') || errorStr.contains('socket')) {
          errorMsg = 'Network error. Please check your connection.';
        } else if (errorStr.contains('storage') || errorStr.contains('firebase')) {
          errorMsg = 'Storage error. Please try again later.';
        } else if (errorStr.contains('unauthorized') || errorStr.contains('403')) {
          errorMsg = 'Not authorized. Please sign in again.';
        }
        setState(() {
          _isUploading = false;
          _error = errorMsg;
        });
        // Also show a snackbar with more details in debug mode
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: ${e.runtimeType}'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }

  Future<void> _useStockImage() async {
    final authState = ref.read(authStateProvider);
    final user = authState.maybeWhen(data: (u) => u, orElse: () => null);
    if (user == null) return;

    final profile = ref.read(currentUserProfileProvider).maybeWhen(
      data: (p) => p,
      orElse: () => null,
    );

    if (profile != null) {
      final userService = ref.read(userServiceProvider);
      final updatedProfile = profile.copyWith(
        useStockHouseImage: true,
        updatedAt: DateTime.now(),
      );
      await userService.updateUser(updatedProfile);
    }

    widget.onUseStockImage?.call();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Using demo house image')),
      );
    }
  }

  void _showPickerOptions() {
    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
                const SizedBox(height: 16),
                Text(
                  'Add House Photo',
                  style: Theme.of(ctx).textTheme.titleLarge?.copyWith(
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Your photo will be used to preview lighting effects',
                  style: Theme.of(ctx).textTheme.bodyMedium?.copyWith(
                    color: NexGenPalette.textMedium,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 20),
                _OptionTile(
                  icon: Icons.camera_alt_rounded,
                  label: 'Take Photo',
                  subtitle: 'Use your camera',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload(ImageSource.camera);
                  },
                ),
                const SizedBox(height: 8),
                _OptionTile(
                  icon: Icons.photo_library_rounded,
                  label: 'Choose from Gallery',
                  subtitle: 'Select an existing photo',
                  onTap: () {
                    Navigator.pop(ctx);
                    _pickAndUpload(ImageSource.gallery);
                  },
                ),
                const SizedBox(height: 8),
                _OptionTile(
                  icon: Icons.home_rounded,
                  label: 'Use Demo Image',
                  subtitle: 'Keep using the sample house',
                  onTap: () {
                    Navigator.pop(ctx);
                    _useStockImage();
                  },
                ),
                const SizedBox(height: 8),
                _OptionTile(
                  icon: Icons.edit_location_alt_outlined,
                  label: 'Trace Roofline',
                  subtitle: 'Draw where your lights are installed',
                  onTap: () {
                    Navigator.pop(ctx);
                    context.push(AppRoutes.rooflineEditor);
                  },
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final profileAsync = ref.watch(currentUserProfileProvider);
    final photoUrl = profileAsync.maybeWhen(
      data: (p) => p?.housePhotoUrl,
      orElse: () => null,
    );
    final useStock = profileAsync.maybeWhen(
      data: (p) => p?.useStockHouseImage ?? false,
      orElse: () => false,
    );

    final hasCustomPhoto = photoUrl != null && photoUrl.isNotEmpty && !useStock;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Photo preview
        ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: Stack(
            children: [
              // Image
              SizedBox(
                height: widget.previewHeight,
                width: double.infinity,
                child: hasCustomPhoto
                    ? Image.network(
                        photoUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) {
                          return Image.asset(
                            'assets/images/Demohomephoto.jpg',
                            fit: BoxFit.cover,
                          );
                        },
                      )
                    : Image.asset(
                        'assets/images/Demohomephoto.jpg',
                        fit: BoxFit.cover,
                      ),
              ),

              // Gradient overlay
              Positioned.fill(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.6),
                        Colors.transparent,
                      ],
                    ),
                  ),
                ),
              ),

              // Upload progress overlay
              if (_isUploading)
                Positioned.fill(
                  child: Container(
                    color: Colors.black54,
                    child: Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(
                            valueColor: AlwaysStoppedAnimation(NexGenPalette.cyan),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            'Uploading...',
                            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),

              // Change photo button (bottom right)
              Positioned(
                bottom: 12,
                right: 12,
                child: Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _isUploading ? null : _showPickerOptions,
                    borderRadius: BorderRadius.circular(12),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            hasCustomPhoto ? Icons.edit : Icons.add_a_photo,
                            size: 18,
                            color: Colors.black,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            hasCustomPhoto ? 'Change' : 'Add Photo',
                            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                              color: Colors.black,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

              // Current status chip (top left)
              Positioned(
                top: 12,
                left: 12,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasCustomPhoto ? Icons.check_circle : Icons.info_outline,
                        size: 14,
                        color: hasCustomPhoto ? NexGenPalette.cyan : Colors.white70,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        hasCustomPhoto ? 'Your Home' : 'Demo Image',
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),

        // Error message
        if (_error != null)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              _error!,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
          ),

        // Helper text
        Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Text(
            'Upload a photo of your home to see how lighting effects will look on your roofline.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: NexGenPalette.textMedium,
            ),
          ),
        ),

        // Roofline tracing status and button
        _RooflineStatusSection(hasCustomPhoto: hasCustomPhoto),
      ],
    );
  }
}

/// Section showing roofline tracing status and button to trace
class _RooflineStatusSection extends ConsumerWidget {
  final bool hasCustomPhoto;

  const _RooflineStatusSection({required this.hasCustomPhoto});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rooflineMask = ref.watch(rooflineMaskProvider);
    final hasRoofline = rooflineMask != null && rooflineMask.hasCustomPoints;

    return Padding(
      padding: const EdgeInsets.only(top: 12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: NexGenPalette.gunmetal90,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: NexGenPalette.line),
        ),
        child: Row(
          children: [
            // Status icon
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: hasRoofline
                    ? NexGenPalette.cyan.withValues(alpha: 0.15)
                    : Colors.amber.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                hasRoofline ? Icons.check_circle : Icons.info_outline,
                color: hasRoofline ? NexGenPalette.cyan : Colors.amber,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            // Status text
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    hasRoofline ? 'Roofline Traced' : 'Roofline Not Set',
                    style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    hasRoofline
                        ? '${rooflineMask.points.length} points traced'
                        : 'Trace your roofline for accurate light preview',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                ],
              ),
            ),
            // Trace/Edit button
            TextButton(
              onPressed: () => context.push(AppRoutes.rooflineEditor),
              child: Text(hasRoofline ? 'Edit' : 'Trace'),
            ),
          ],
        ),
      ),
    );
  }
}

/// Option tile for the picker bottom sheet
class _OptionTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String subtitle;
  final VoidCallback onTap;

  const _OptionTile({
    required this.icon,
    required this.label,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: NexGenPalette.cyan.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: NexGenPalette.cyan, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      label,
                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right, color: Colors.white54),
            ],
          ),
        ),
      ),
    );
  }
}
