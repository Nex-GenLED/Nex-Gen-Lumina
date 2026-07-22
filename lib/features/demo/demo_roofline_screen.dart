import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/demo_stock_home.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/models/roofline_configuration.dart';
import 'package:nexgen_command/models/roofline_segment.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';

/// Demo roofline review screen.
///
/// Shows the user's captured photo (or stock sample home) with the
/// auto-detected or pre-authored roofline trace rendered over it. The user
/// can confirm and continue, or go back to retake/choose the sample home.
class DemoRooflineScreen extends ConsumerWidget {
  const DemoRooflineScreen({super.key});

  void _continueToNext(BuildContext context, WidgetRef ref) {
    ref.read(demoFlowProvider.notifier).goToStep(DemoStep.completion);
    context.push(AppRoutes.demoComplete);
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final photoBytes = ref.watch(demoPhotoProvider);
    final usingStock = ref.watch(demoUsingStockPhotoProvider);
    final config = ref.watch(demoRooflineConfigProvider);

    final hasConfig = config != null &&
        config.segments.any((s) => s.points.length >= 2);

    return DemoScaffold(
      title: 'Your Roofline',
      subtitle: hasConfig
          ? 'Here\'s how Nex-Gen LEDs will follow your roofline'
          : 'We couldn\'t detect your roofline — try again or use the sample home',
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),

            // Photo + overlay preview
            AspectRatio(
              aspectRatio: 994 / 492,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: hasConfig
                          ? NexGenPalette.cyan
                          : NexGenPalette.line,
                      width: hasConfig ? 2 : 1,
                    ),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      // Base image
                      if (usingStock)
                        Image.asset(
                          DemoStockHome.imageAssetPath,
                          fit: BoxFit.cover,
                        )
                      else if (photoBytes != null)
                        Image.memory(
                          photoBytes,
                          fit: BoxFit.cover,
                        )
                      else
                        Container(color: NexGenPalette.gunmetal),

                      // Light overlay — only render when we have geometry.
                      // currentRooflineConfigProvider is demo-aware as of
                      // Prompt 3, so AnimatedRooflineOverlay gets the demo
                      // config automatically.
                      if (hasConfig)
                        const AnimatedRooflineOverlay(
                          useBoxFitCover: true,
                          targetAspectRatio: 994 / 492,
                          forceOn: true,
                          brightness: 255,
                        ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 20),

            // Status / stats
            if (hasConfig) ...[
              DemoGlassCard(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 14,
                ),
                child: Row(
                  children: [
                    const Icon(
                      Icons.check_circle,
                      color: NexGenPalette.cyan,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        usingStock
                            ? 'Sample home roofline loaded — '
                                '${config.segmentCount} segments, '
                                '${config.totalPixelCount} LEDs'
                            : 'Roofline detected — '
                                '${config.totalPixelCount} LEDs across your home',
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              DemoInfoBanner(
                message:
                    'This is an approximation. In the full app, a Nex-Gen '
                    'specialist will precisely trace every roofline detail.',
                icon: Icons.info_outline,
              ),
            ] else ...[
              DemoGlassCard(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: NexGenPalette.cyan,
                      size: 32,
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Couldn\'t detect your roofline',
                      style: Theme.of(context).textTheme.titleSmall,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Try a different photo, use the sample home, or '
                      'continue with an approximate roofline.',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: NexGenPalette.textMedium,
                          ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    DemoPrimaryButton(
                      label: 'Continue with Approximate Roofline',
                      icon: Icons.check_circle_outline,
                      onPressed: () {
                        ref.read(demoRooflineConfigProvider.notifier).state =
                            _buildFallbackConfig();
                      },
                    ),
                  ],
                ),
              ),
            ],

            const SizedBox(height: 24),

            // Secondary: back to photo step
            DemoSecondaryButton(
              label: usingStock ? 'Use My Own Photo Instead' : 'Retake Photo',
              icon: usingStock ? Icons.camera_alt : Icons.refresh,
              onPressed: () {
                ref.read(demoFlowProvider.notifier)
                    .goToStep(DemoStep.photoCapture);
                context.pop();
              },
            ),

            const SizedBox(height: 24),
          ],
        ),
      ),
      bottomAction: hasConfig
          ? DemoPrimaryButton(
              label: 'Continue to Preview',
              icon: Icons.arrow_forward,
              onPressed: () => _continueToNext(context, ref),
            )
          : null,
    );
  }
}

/// Builds a generic roofline approximation for when auto-detect fails.
/// A gentle peaked shape across the upper third of the photo — works for
/// most 2-story and ranch homes. Not precise, but shows the product concept.
RooflineConfiguration _buildFallbackConfig() {
  final now = DateTime.now();
  return RooflineConfiguration(
    id: 'demo_fallback',
    name: 'Approximate Roofline',
    segments: [
      RooflineSegment(
        id: 'fallback_main',
        name: 'Main Roofline',
        pixelCount: 100,
        points: const [
          Offset(0.10, 0.32),
          Offset(0.30, 0.20),
          Offset(0.50, 0.14),
          Offset(0.70, 0.20),
          Offset(0.90, 0.32),
        ],
      ),
    ],
    createdAt: now,
    updatedAt: now,
  );
}
