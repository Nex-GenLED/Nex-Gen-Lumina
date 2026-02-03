import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Progress bar widget for the demo experience flow.
///
/// Shows the current step and progress through the demo.
class DemoProgressBar extends ConsumerWidget {
  const DemoProgressBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStep = ref.watch(demoFlowProvider);
    final progress = currentStep.progressValue;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Step indicator dots
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: DemoStep.values.map((step) {
            final isActive = step.index <= currentStep.index;
            final isCurrent = step == currentStep;

            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                width: isCurrent ? 24 : 8,
                height: 8,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(4),
                  color: isActive
                      ? NexGenPalette.cyan
                      : NexGenPalette.line.withOpacity(0.3),
                  boxShadow: isCurrent
                      ? [
                          BoxShadow(
                            color: NexGenPalette.cyan.withOpacity(0.4),
                            blurRadius: 8,
                            spreadRadius: 1,
                          ),
                        ]
                      : null,
                ),
              ),
            );
          }).toList(),
        ),

        const SizedBox(height: 8),

        // Step name
        Text(
          currentStep.displayName,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: NexGenPalette.textMedium,
              ),
        ),

        const SizedBox(height: 12),

        // Progress bar
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 4,
            backgroundColor: NexGenPalette.line.withOpacity(0.2),
            valueColor: const AlwaysStoppedAnimation<Color>(NexGenPalette.cyan),
          ),
        ),
      ],
    );
  }
}

/// Compact progress indicator for use in app bars.
class DemoProgressIndicator extends ConsumerWidget {
  const DemoProgressIndicator({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStep = ref.watch(demoFlowProvider);
    final totalSteps = DemoStep.values.length;
    final currentIndex = currentStep.index + 1;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal.withOpacity(0.8),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.play_circle_outline,
            size: 16,
            color: NexGenPalette.cyan,
          ),
          const SizedBox(width: 6),
          Text(
            'DEMO',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: NexGenPalette.cyan,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 1,
                ),
          ),
          const SizedBox(width: 8),
          Text(
            '$currentIndex / $totalSteps',
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
        ],
      ),
    );
  }
}

/// Full-width progress header for demo screens.
class DemoProgressHeader extends ConsumerWidget {
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final VoidCallback? onSkip;
  final bool showSkip;

  const DemoProgressHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.onSkip,
    this.showSkip = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentStep = ref.watch(demoFlowProvider);
    final canGoBack = ref.read(demoFlowProvider.notifier).canGoBack;

    return SafeArea(
      bottom: false,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Top row with back button and demo badge
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Back button
                if (canGoBack)
                  IconButton(
                    onPressed: onBack,
                    icon: const Icon(Icons.arrow_back_ios, size: 20),
                    style: IconButton.styleFrom(
                      backgroundColor: NexGenPalette.gunmetal.withOpacity(0.5),
                      padding: const EdgeInsets.all(8),
                    ),
                  )
                else
                  const SizedBox(width: 40),

                // Demo badge
                const DemoProgressIndicator(),

                // Skip button
                if (showSkip && currentStep.isSkippable)
                  TextButton(
                    onPressed: onSkip,
                    child: Text(
                      'Skip',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                    ),
                  )
                else
                  const SizedBox(width: 40),
              ],
            ),

            const SizedBox(height: 24),

            // Progress bar
            const DemoProgressBar(),

            const SizedBox(height: 24),

            // Title
            Text(
              title,
              style: Theme.of(context).textTheme.headlineMedium,
            ),

            // Subtitle
            if (subtitle != null) ...[
              const SizedBox(height: 8),
              Text(
                subtitle!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
