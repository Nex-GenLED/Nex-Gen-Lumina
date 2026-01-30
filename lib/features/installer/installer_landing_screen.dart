import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Landing screen explaining Installer Mode before PIN entry.
///
/// Purpose: Customer onboarding and hardware setup by certified installers.
/// - Create new customer accounts with temporary passwords
/// - Pair and configure WLED controllers
/// - Complete installation records for warranty tracking
class InstallerLandingScreen extends StatelessWidget {
  const InstallerLandingScreen({super.key});

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
                            NexGenPalette.violet.withValues(alpha: 0.3),
                            NexGenPalette.cyan.withValues(alpha: 0.3),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        border: Border.all(
                          color: NexGenPalette.cyan.withValues(alpha: 0.5),
                          width: 2,
                        ),
                      ),
                      child: const Icon(
                        Icons.engineering_outlined,
                        size: 48,
                        color: NexGenPalette.cyan,
                      ),
                    ),

                    const SizedBox(height: 32),

                    // Title
                    Text(
                      'Installer Mode',
                      style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                        color: NexGenPalette.textHigh,
                        fontWeight: FontWeight.bold,
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Subtitle
                    Text(
                      'For certified Nex-Gen LED installers',
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: NexGenPalette.textMedium,
                      ),
                      textAlign: TextAlign.center,
                    ),

                    const SizedBox(height: 40),

                    // Feature cards
                    _buildFeatureCard(
                      context,
                      icon: Icons.person_add_outlined,
                      title: 'Customer Onboarding',
                      description: 'Create new customer accounts with secure temporary credentials during installation.',
                    ),

                    const SizedBox(height: 16),

                    _buildFeatureCard(
                      context,
                      icon: Icons.bluetooth,
                      title: 'Controller Setup',
                      description: 'Pair and configure WLED controllers via Bluetooth. Connect to customer Wi-Fi.',
                    ),

                    const SizedBox(height: 16),

                    _buildFeatureCard(
                      context,
                      icon: Icons.verified_outlined,
                      title: 'Warranty Registration',
                      description: 'Installation records are logged for 5-year warranty tracking and dealer statistics.',
                    ),

                    const SizedBox(height: 40),

                    // PIN format info
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
                                  Icon(Icons.info_outline, size: 20, color: NexGenPalette.textMedium),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'PIN Format',
                                      style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                        color: NexGenPalette.textHigh,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Row(
                                children: [
                                  _buildPinSegment(context, 'XX', 'Dealer Code', NexGenPalette.violet),
                                  const SizedBox(width: 8),
                                  Text('+', style: TextStyle(color: NexGenPalette.textMedium, fontSize: 20)),
                                  const SizedBox(width: 8),
                                  _buildPinSegment(context, 'XX', 'Installer Code', NexGenPalette.cyan),
                                ],
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'Your 4-digit PIN was assigned by your dealer administrator.',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: NexGenPalette.textMedium,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
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
                  onPressed: () => context.push(AppRoutes.installerPin),
                  style: FilledButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.lock_outline),
                  label: const Text(
                    'Enter Installer PIN',
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
              color: NexGenPalette.cyan.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: NexGenPalette.cyan, size: 22),
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

  Widget _buildPinSegment(BuildContext context, String value, String label, Color color) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.5)),
          ),
          child: Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(
            color: color.withValues(alpha: 0.8),
            fontSize: 10,
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
