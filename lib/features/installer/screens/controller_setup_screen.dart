import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/services/image_upload_service.dart';
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
  bool _isUploading = false;
  String? _validationError;

  @override
  void initState() {
    super.initState();
    // Check status of all controllers on load
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkAllControllerStatus();
    });
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
        const Duration(seconds: 5),
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

  void _addController() {
    // Navigate to BLE provisioning
    Navigator.of(context).pushNamed('/device-setup').then((_) {
      // Refresh status after returning
      _checkAllControllerStatus();
    });
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

      // Use a temporary ID for installer uploads
      final tempId = 'installer_${DateTime.now().millisecondsSinceEpoch}';
      final service = ImageUploadService();

      final url = await service.pickAndUploadHousePhoto(
        tempId,
        source: source,
      );

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
      child: InkWell(
        onTap: () => _toggleControllerSelection(controller.id),
        borderRadius: BorderRadius.circular(12),
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
    );
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
      builder: (context) => Padding(
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
