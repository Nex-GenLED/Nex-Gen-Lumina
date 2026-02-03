import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/demo/demo_models.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/demo/widgets/demo_scaffold.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/theme.dart';

/// Welcome screen for the demo experience.
///
/// Introduces the demo, explains what the user will experience,
/// and collects consent before capturing lead information.
class DemoWelcomeScreen extends ConsumerWidget {
  const DemoWelcomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: Container(
        decoration: const BoxDecoration(
          gradient: BrandGradients.atmosphere,
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Top bar with close button
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    // Back to login
                    TextButton.icon(
                      onPressed: () {
                        ref.read(demoSessionProvider.notifier).endDemo();
                        context.go(AppRoutes.login);
                      },
                      icon: const Icon(Icons.arrow_back_ios, size: 16),
                      label: const Text('Login'),
                    ),
                    // Demo badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: NexGenPalette.cyan.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: NexGenPalette.cyan.withOpacity(0.3),
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.play_circle_outline,
                            size: 16,
                            color: NexGenPalette.cyan,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'DEMO',
                            style:
                                Theme.of(context).textTheme.labelSmall?.copyWith(
                                      color: NexGenPalette.cyan,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 1,
                                    ),
                          ),
                        ],
                      ),
                    ),
                    // Placeholder for alignment
                    const SizedBox(width: 80),
                  ],
                ),
              ),

              // Main content
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const SizedBox(height: 20),

                      // Hero logo/image
                      Container(
                        width: 120,
                        height: 120,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [
                              NexGenPalette.cyan,
                              NexGenPalette.blue,
                            ],
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: NexGenPalette.cyan.withOpacity(0.4),
                              blurRadius: 30,
                              spreadRadius: 5,
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.light_mode,
                          size: 60,
                          color: Colors.black,
                        ),
                      ),

                      const SizedBox(height: 32),

                      // Title
                      Text(
                        'Experience Nex-Gen',
                        style: Theme.of(context).textTheme.headlineLarge,
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 12),

                      // Subtitle
                      Text(
                        'See how the Lumina app transforms your home with permanent smart LED lighting.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: NexGenPalette.textMedium,
                            ),
                        textAlign: TextAlign.center,
                      ),

                      const SizedBox(height: 40),

                      // Feature list
                      _buildFeatureItem(
                        context,
                        Icons.photo_camera_outlined,
                        'Visualize Your Home',
                        'Take a photo and see how lights look on your roofline',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        context,
                        Icons.palette_outlined,
                        'Explore 500+ Patterns',
                        'Browse holidays, sports teams, and custom designs',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        context,
                        Icons.schedule_outlined,
                        'Smart Scheduling',
                        'See how automation syncs with sunrise & sunset',
                      ),
                      const SizedBox(height: 16),
                      _buildFeatureItem(
                        context,
                        Icons.auto_awesome_outlined,
                        'Meet Lumina AI',
                        'Your personal lighting assistant',
                      ),

                      const SizedBox(height: 40),

                      // Privacy notice
                      DemoGlassCard(
                        padding: const EdgeInsets.all(16),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: NexGenPalette.cyan.withOpacity(0.1),
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                Icons.privacy_tip_outlined,
                                size: 20,
                                color: NexGenPalette.cyan,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                'We\'ll ask for your contact info so a lighting specialist can help you get started.',
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: NexGenPalette.textMedium,
                                    ),
                              ),
                            ),
                          ],
                        ),
                      ),

                      const SizedBox(height: 40),
                    ],
                  ),
                ),
              ),

              // Bottom action
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      DemoPrimaryButton(
                        label: 'Start Demo',
                        icon: Icons.play_arrow,
                        onPressed: () {
                          // Initialize demo session
                          ref.read(demoSessionProvider.notifier).startDemo();
                          // Navigate to profile screen
                          ref.read(demoFlowProvider.notifier).goToStep(DemoStep.profile);
                          context.push(AppRoutes.demoProfile);
                        },
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'Takes about 3 minutes',
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: NexGenPalette.textMedium,
                            ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFeatureItem(
    BuildContext context,
    IconData icon,
    String title,
    String description,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal.withOpacity(0.6),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Icon(
            icon,
            size: 24,
            color: NexGenPalette.cyan,
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: Theme.of(context).textTheme.titleSmall,
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
