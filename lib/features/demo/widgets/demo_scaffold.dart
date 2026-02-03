import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_progress_bar.dart';
import 'package:nexgen_command/theme.dart';

/// A scaffold widget specifically designed for demo screens.
///
/// Provides:
/// - Consistent gradient background
/// - Demo progress header
/// - Back/Skip navigation
/// - Exit demo confirmation
class DemoScaffold extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final Widget body;
  final Widget? bottomAction;
  final bool showSkip;
  final VoidCallback? onSkip;
  final bool showExitButton;
  final bool extendBodyBehindHeader;

  const DemoScaffold({
    super.key,
    required this.title,
    this.subtitle,
    required this.body,
    this.bottomAction,
    this.showSkip = false,
    this.onSkip,
    this.showExitButton = true,
    this.extendBodyBehindHeader = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: NexGenPalette.atmosphere,
        ),
        child: Column(
          children: [
            // Progress header
            DemoProgressHeader(
              title: title,
              subtitle: subtitle,
              showSkip: showSkip,
              onBack: () {
                ref.read(demoFlowProvider.notifier).previousStep();
              },
              onSkip: onSkip ?? () {
                ref.read(demoFlowProvider.notifier).skipStep();
              },
            ),

            // Body content
            Expanded(
              child: body,
            ),

            // Bottom action (if provided)
            if (bottomAction != null)
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: bottomAction!,
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Show exit demo confirmation dialog.
  static Future<bool> showExitConfirmation(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => const _ExitDemoDialog(),
    );
    return result ?? false;
  }
}

/// Exit demo confirmation dialog.
class _ExitDemoDialog extends StatelessWidget {
  const _ExitDemoDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(24),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal.withOpacity(0.9),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Icon
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: NexGenPalette.amber.withOpacity(0.1),
                    border: Border.all(
                      color: NexGenPalette.amber.withOpacity(0.3),
                    ),
                  ),
                  child: const Icon(
                    Icons.exit_to_app_rounded,
                    size: 32,
                    color: NexGenPalette.amber,
                  ),
                ),

                const SizedBox(height: 20),

                // Title
                Text(
                  'Exit Demo?',
                  style: Theme.of(context).textTheme.titleLarge,
                ),

                const SizedBox(height: 12),

                // Message
                Text(
                  'Your progress will not be saved. You can always start the demo again from the login screen.',
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                ),

                const SizedBox(height: 24),

                // Actions
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.of(context).pop(false),
                        child: const Text('Continue Demo'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(true),
                        style: FilledButton.styleFrom(
                          backgroundColor: NexGenPalette.amber,
                        ),
                        child: const Text('Exit'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Primary action button for demo screens.
class DemoPrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final bool isLoading;
  final IconData? icon;

  const DemoPrimaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.isLoading = false,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: FilledButton(
        onPressed: isLoading ? null : onPressed,
        child: isLoading
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
                ),
              )
            : Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (icon != null) ...[
                    Icon(icon, size: 20),
                    const SizedBox(width: 8),
                  ],
                  Text(
                    label,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}

/// Secondary action button for demo screens.
class DemoSecondaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;

  const DemoSecondaryButton({
    super.key,
    required this.label,
    this.onPressed,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton(
        onPressed: onPressed,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(icon, size: 20),
              const SizedBox(width: 8),
            ],
            Text(
              label,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Glass card widget for demo screens.
class DemoGlassCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry? padding;
  final VoidCallback? onTap;
  final bool isSelected;

  const DemoGlassCard({
    super.key,
    required this.child,
    this.padding,
    this.onTap,
    this.isSelected = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: padding ?? const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: isSelected
                  ? NexGenPalette.cyan.withOpacity(0.1)
                  : NexGenPalette.gunmetal.withOpacity(0.6),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: isSelected
                    ? NexGenPalette.cyan
                    : NexGenPalette.line,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: NexGenPalette.cyan.withOpacity(0.2),
                        blurRadius: 12,
                        spreadRadius: 2,
                      ),
                    ]
                  : null,
            ),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Info banner for demo screens.
class DemoInfoBanner extends StatelessWidget {
  final String message;
  final IconData icon;
  final Color? color;

  const DemoInfoBanner({
    super.key,
    required this.message,
    this.icon = Icons.info_outline,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final bannerColor = color ?? NexGenPalette.cyan;

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: bannerColor.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: bannerColor.withOpacity(0.3),
        ),
      ),
      child: Row(
        children: [
          Icon(
            icon,
            size: 20,
            color: bannerColor,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              message,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: bannerColor,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
