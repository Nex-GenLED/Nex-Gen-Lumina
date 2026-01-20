import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/models/roofline_mask.dart';
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
          if (_currentMask.hasCustomPoints)
            TextButton.icon(
              onPressed: () => _editorKey.currentState?.clear(),
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Reset'),
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

            // Skip option
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
