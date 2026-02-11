import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
import 'package:nexgen_command/services/roofline_auto_detect_service.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/roofline_editor.dart';

/// Full-page screen for tracing the roofline on a house image.
///
/// Allows users to tap points to create a polyline tracing their roofline,
/// which is then used for accurate light preview placement.
class RooflineEditorScreen extends ConsumerStatefulWidget {
  const RooflineEditorScreen({super.key});

  @override
  ConsumerState<RooflineEditorScreen> createState() => _RooflineEditorScreenState();
}

class _RooflineEditorScreenState extends ConsumerState<RooflineEditorScreen> {
  final GlobalKey<RooflineEditorState> _editorKey = GlobalKey();
  bool _isSaving = false;
  bool _isDetecting = false;
  RooflineMask _currentMask = RooflineMask.defaultMask;

  @override
  Widget build(BuildContext context) {
    final imageUrl = ref.watch(houseImageUrlProvider);
    final useStock = ref.watch(useStockImageProvider);
    final existingMask = ref.watch(rooflineMaskProvider);

    // Determine image to edit
    ImageProvider imageProvider;
    if (imageUrl != null && !useStock) {
      imageProvider = NetworkImage(imageUrl);
    } else {
      imageProvider = const AssetImage('assets/images/Demohomephoto.jpg');
    }

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => context.pop(),
        ),
        title: const Text('Trace Your Roofline'),
        actions: [
          // Clear current drawing
          if (_currentMask.hasCustomPoints)
            TextButton.icon(
              onPressed: () => _editorKey.currentState?.clear(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Clear'),
            ),
          // Delete saved roofline from cloud
          if (existingMask != null && existingMask.hasCustomPoints)
            TextButton.icon(
              onPressed: _isSaving ? null : _resetSavedRoofline,
              icon: const Icon(Icons.delete_outline, size: 18, color: Colors.redAccent),
              label: const Text('Reset Saved', style: TextStyle(color: Colors.redAccent)),
            ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // Instructions
            Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: NexGenPalette.cyan, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Instructions',
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Tap along your roofline from left to right to trace where your lights are installed. '
                    'The light preview will follow this path.',
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
                  ),
                ],
              ),
            ),

            // Editor
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: RooflineEditor(
                  key: _editorKey,
                  imageProvider: imageProvider,
                  initialMask: existingMask,
                  onChanged: (mask) {
                    setState(() => _currentMask = mask);
                  },
                ),
              ),
            ),

            // Point count indicator
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Text(
                _currentMask.points.isEmpty
                    ? 'Tap to add points'
                    : '${_currentMask.points.length} points',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
              ),
            ),

            // Controls
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  // Undo button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _currentMask.points.isEmpty
                          ? null
                          : () => _editorKey.currentState?.undo(),
                      icon: const Icon(Icons.undo),
                      label: const Text('Undo'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white,
                        side: BorderSide(
                          color: _currentMask.points.isEmpty
                              ? NexGenPalette.gunmetal50
                              : NexGenPalette.line,
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  // Save button
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      onPressed: _currentMask.points.length >= 2 && !_isSaving
                          ? _saveRoofline
                          : null,
                      icon: _isSaving
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.black,
                              ),
                            )
                          : const Icon(Icons.check),
                      label: Text(_isSaving ? 'Saving...' : 'Save Roofline'),
                      style: FilledButton.styleFrom(
                        backgroundColor: NexGenPalette.cyan,
                        foregroundColor: Colors.black,
                        disabledBackgroundColor: NexGenPalette.gunmetal50,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // Auto-detect and template options
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  // Auto-detect button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving || _isDetecting
                          ? null
                          : _autoDetectRoofline,
                      icon: _isDetecting
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: NexGenPalette.cyan,
                              ),
                            )
                          : const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(_isDetecting ? 'Detecting...' : 'Auto-Detect'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: NexGenPalette.cyan,
                        side: const BorderSide(color: NexGenPalette.cyan),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Templates button
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _isSaving ? null : _showTemplates,
                      icon: const Icon(Icons.dashboard_customize, size: 18),
                      label: const Text('Templates'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.white70,
                        side: const BorderSide(color: NexGenPalette.line),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Default fallback
            TextButton(
              onPressed: _isSaving ? null : () => _useDefaultMask(),
              child: Text(
                'Use default top-edge detection',
                style: TextStyle(color: NexGenPalette.textMedium),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Future<void> _autoDetectRoofline() async {
    final editorState = _editorKey.currentState;
    if (editorState == null) return;

    setState(() => _isDetecting = true);

    try {
      final imageProvider = editorState.currentImageProvider;
      final result = await RooflineAutoDetectService.detectFromImage(imageProvider);

      if (!mounted) return;

      if (result != null && result.points.length >= 2) {
        editorState.setPoints(result.points);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Detected ${result.points.length} roofline points. Adjust if needed, then save.'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        // Detection failed - offer templates
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not detect roofline. Try a template or draw manually.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint('Auto-detect failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Auto-detection failed. Try drawing manually.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  void _showTemplates() {
    final templates = RooflineAutoDetectService.templates;

    showModalBottomSheet(
      context: context,
      backgroundColor: NexGenPalette.gunmetal90,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Choose a Roofline Template',
              style: Theme.of(ctx).textTheme.titleMedium?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'Select the shape closest to your roofline, then adjust points manually.',
              style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                color: NexGenPalette.textMedium,
              ),
            ),
            const SizedBox(height: 16),
            ...templates.map((template) => ListTile(
              leading: Icon(template.icon, color: NexGenPalette.cyan),
              title: Text(template.name, style: const TextStyle(color: Colors.white)),
              trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: NexGenPalette.textMedium),
              onTap: () {
                Navigator.pop(ctx);
                _editorKey.currentState?.setPoints(template.points);
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Applied "${template.name}" template. Adjust points, then save.'),
                    duration: const Duration(seconds: 2),
                  ),
                );
              },
            )),
          ],
        ),
      ),
    );
  }

  Future<void> _saveRoofline() async {
    if (_isSaving) return;

    final mask = _editorKey.currentState?.getMask();
    if (mask == null || mask.points.length < 2) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add at least 2 points to trace your roofline')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );

      if (profile == null) {
        throw Exception('No user profile found');
      }

      final userService = ref.read(userServiceProvider);
      final updatedProfile = profile.copyWith(
        rooflineMask: mask.toJson(),
        updatedAt: DateTime.now(),
      );
      await userService.updateUser(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Roofline saved successfully'),
            backgroundColor: Colors.green,
          ),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('Failed to save roofline: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save roofline: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  /// Reset/delete the saved roofline from the cloud
  Future<void> _resetSavedRoofline() async {
    // Confirm with user
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Reset Roofline?'),
        content: const Text(
          'This will delete your saved roofline tracing. You can draw a new one afterwards.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
            child: const Text('Reset'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _isSaving = true);

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );

      if (profile == null) {
        throw Exception('No user profile found');
      }

      // Clear the roofline mask by setting it to null
      final userService = ref.read(userServiceProvider);
      final updatedProfile = profile.copyWith(
        rooflineMask: null,
        updatedAt: DateTime.now(),
      );
      await userService.updateUser(updatedProfile);

      // Also clear the local editor
      _editorKey.currentState?.clear();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Roofline reset successfully. You can now draw a new one.'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Failed to reset roofline: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to reset roofline: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }

  Future<void> _useDefaultMask() async {
    setState(() => _isSaving = true);

    try {
      final profile = ref.read(currentUserProfileProvider).maybeWhen(
        data: (p) => p,
        orElse: () => null,
      );

      if (profile == null) {
        throw Exception('No user profile found');
      }

      // Save a default mask (not manually drawn)
      final defaultMask = const RooflineMask(
        maskHeight: 0.25,
        isManuallyDrawn: false,
      );

      final userService = ref.read(userServiceProvider);
      final updatedProfile = profile.copyWith(
        rooflineMask: defaultMask.toJson(),
        updatedAt: DateTime.now(),
      );
      await userService.updateUser(updatedProfile);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Using default roofline detection')),
        );
        context.pop();
      }
    } catch (e) {
      debugPrint('Failed to save default mask: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSaving = false);
      }
    }
  }
}
