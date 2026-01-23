import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/scenes/scene_models.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:nexgen_command/theme.dart';

/// A button that presents the iOS "Add to Siri" UI for a scene.
///
/// Only renders on iOS. On other platforms, returns an empty widget.
class AddToSiriButton extends ConsumerStatefulWidget {
  final Scene scene;
  final bool compact;
  final VoidCallback? onAdded;

  const AddToSiriButton({
    super.key,
    required this.scene,
    this.compact = false,
    this.onAdded,
  });

  @override
  ConsumerState<AddToSiriButton> createState() => _AddToSiriButtonState();
}

class _AddToSiriButtonState extends ConsumerState<AddToSiriButton> {
  bool _isLoading = false;

  Future<void> _addToSiri() async {
    if (_isLoading) return;

    setState(() => _isLoading = true);

    try {
      final presentAddToSiri = ref.read(presentAddToSiriProvider);
      final success = await presentAddToSiri(widget.scene);

      if (mounted) {
        if (success) {
          widget.onAdded?.call();
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Added "${widget.scene.name}" to Siri!'),
              backgroundColor: NexGenPalette.cyan,
            ),
          );
        }
      }
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Only show on iOS
    if (!Platform.isIOS) return const SizedBox.shrink();

    if (widget.compact) {
      return IconButton(
        onPressed: _isLoading ? null : _addToSiri,
        icon: _isLoading
            ? const SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
              )
            : const Icon(Icons.mic, color: NexGenPalette.cyan),
        tooltip: 'Add to Siri',
      );
    }

    return OutlinedButton.icon(
      onPressed: _isLoading ? null : _addToSiri,
      icon: _isLoading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
            )
          : const Icon(Icons.mic, size: 18),
      label: const Text('Add to Siri'),
      style: OutlinedButton.styleFrom(
        foregroundColor: NexGenPalette.cyan,
        side: const BorderSide(color: NexGenPalette.cyan),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
    );
  }
}

/// A prominent "Add to Siri" card for scene detail pages.
class SiriShortcutCard extends ConsumerWidget {
  final Scene scene;

  const SiriShortcutCard({super.key, required this.scene});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Only show on iOS
    if (!Platform.isIOS) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            Colors.deepPurple.withValues(alpha: 0.2),
            NexGenPalette.cyan.withValues(alpha: 0.1),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.deepPurple.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.deepPurple.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.mic, color: Colors.deepPurple, size: 24),
              ),
              const SizedBox(width: 12),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Siri Shortcut',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      'Activate with your voice',
                      style: TextStyle(
                        color: NexGenPalette.textMedium,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            '"Hey Siri, ${scene.name}"',
            style: TextStyle(
              color: Colors.white.withValues(alpha: 0.8),
              fontStyle: FontStyle.italic,
              fontSize: 14,
            ),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            child: AddToSiriButton(scene: scene),
          ),
        ],
      ),
    );
  }
}

/// Small inline "Add to Siri" chip for lists.
class SiriChip extends ConsumerWidget {
  final Scene scene;

  const SiriChip({super.key, required this.scene});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!Platform.isIOS) return const SizedBox.shrink();

    return ActionChip(
      avatar: const Icon(Icons.mic, size: 16, color: Colors.deepPurple),
      label: const Text('Siri'),
      onPressed: () async {
        final presentAddToSiri = ref.read(presentAddToSiriProvider);
        await presentAddToSiri(scene);
      },
      backgroundColor: Colors.deepPurple.withValues(alpha: 0.15),
      side: BorderSide(color: Colors.deepPurple.withValues(alpha: 0.3)),
      labelStyle: const TextStyle(color: Colors.deepPurple, fontSize: 12),
    );
  }
}
