import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Landing screen explaining Media Mode before code entry.
///
/// Purpose: Content creation access for the Nex-Gen media team.
/// - Access any customer's lighting system for video shoots
/// - View and control lights remotely
/// - No ability to modify customer settings or accounts
class MediaLandingScreen extends StatelessWidget {
  const MediaLandingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        child: Column(
          children: [
            // Header with back button
            Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  IconButton(
                    icon: const Icon(Icons.arrow_back, color: NexGenPalette.textHigh),
                    onPressed: () => context.pop(),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    const SizedBox(height: 20),

                    // Icon
                    Container(
                      width: 100,
                      height: 100,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: LinearGradient(
                          colors: [
                            NexGenPalette.magenta.withValues(alpha: 0.3),
                            NexGenPalette.violet.withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: NexGenPalette.magenta.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.videocam_outlined,
                        size: 48,
                        color: NexGenPalette.magenta,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Media Mode',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                      'For Nex-Gen content creation team',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Feature cards
                    _buildFeatureCard(
                      context,
                      icon: Icons.search,
                      title: 'Find Customer Systems',
                      description: 'Search for any customer by email or address to access their lighting system.',
                    ),

                    const SizedBox(height: 16),

                    _buildFeatureCard(
                      context,
                      icon: Icons.palette_outlined,
                      title: 'Control Lighting',
                      description: 'Adjust colors, patterns, and brightness for video shoots and photo sessions.',
                    ),

                    const SizedBox(height: 16),

                    _buildFeatureCard(
                      context,
                      icon: Icons.visibility_outlined,
                      title: 'View-Only Access',
                      description: 'Control lights temporarily. Cannot modify schedules, settings, or customer accounts.',
                    ),

                    const SizedBox(height: 40),

                    // Access code info
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: BackdropFilter(
                        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: NexGenPalette.line),
                          ),
                          child: Column(
                            children: [
                              Row(
                                children: [
                                  Icon(Icons.badge_outlined, size: 20, color: NexGenPalette.magenta),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Media Access Code',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        color: NexGenPalette.textHigh,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Enter your 6-character media access code. This code was provided by your Nex-Gen team lead.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: NexGenPalette.textMedium,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 12),
                              // Visual representation of code format
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: List.generate(6, (index) {
                                  return Container(
                                    margin: const EdgeInsets.symmetric(horizontal: 4),
                                    width: 32,
                                    height: 40,
                                    decoration: BoxDecoration(
                                      color: NexGenPalette.magenta.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: NexGenPalette.magenta.withValues(alpha: 0.4),
                                      ),
                                    ),
                                    child: Center(
                                      child: Text(
                                        '-',
                                        style: TextStyle(
                                          color: NexGenPalette.magenta.withValues(alpha: 0.5),
                                          fontSize: 16,
                                        ),
                                      ),
                                    ),
                                  );
                                }),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 24),

                    // Note about temporary sessions
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: NexGenPalette.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: NexGenPalette.amber.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.timer_outlined, size: 18, color: NexGenPalette.amber),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Text(
                              'Media sessions expire after 4 hours of inactivity.',
                              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                color: NexGenPalette.amber,
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

            // Bottom button
            Padding(
              padding: const EdgeInsets.all(24),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => context.push(AppRoutes.mediaAccessCode),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.magenta,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.key_outlined),
                  label: const Text(
                    'Enter Media Access Code',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeatureCard(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String description,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: NexGenPalette.magenta.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: NexGenPalette.magenta, size: 22),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: NexGenPalette.textHigh,
                    fontWeight: FontWeight.w600,
                  ),
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
      ),
    );
  }
}
