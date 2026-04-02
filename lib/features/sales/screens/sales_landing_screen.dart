import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/sales_providers.dart';
import 'package:nexgen_command/theme.dart';

/// Sales Mode landing screen.
/// Mirrors installer_landing_screen.dart in structure and style.
class SalesLandingScreen extends ConsumerWidget {
  const SalesLandingScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isSalesMode = ref.watch(salesModeActiveProvider);

    // Guard: if session expired, bounce to PIN
    if (!isSalesMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (context.mounted) context.go(AppRoutes.salesPin);
      });
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        actions: [
          TextButton.icon(
            onPressed: () {
              ref.read(salesModeProvider.notifier).exitSalesMode();
              context.go('/');
            },
            icon: const Icon(Icons.logout, size: 18, color: Colors.white70),
            label: const Text('Exit', style: TextStyle(color: Colors.white70)),
          ),
        ],
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              const SizedBox(height: 16),

              // Logo & title
              Image.asset(
                'assets/images/nexgen_logo.png',
                height: 56,
                errorBuilder: (_, __, ___) => Icon(
                  Icons.storefront,
                  size: 56,
                  color: NexGenPalette.cyan,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Sales Mode',
                style: GoogleFonts.montserrat(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: NexGenPalette.cyan,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                'Nex-Gen LED Field Sales Tools',
                style: TextStyle(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 32),

              // Feature cards
              _FeatureCard(
                icon: Icons.home_outlined,
                color: NexGenPalette.cyan,
                title: 'Home Visit',
                description:
                    'Log zones, run lengths, injection points, and power mounts during a site survey.',
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.receipt_long_outlined,
                color: NexGenPalette.violet,
                title: 'Estimate',
                description:
                    'Generate a professional estimate with pricing and send it for customer signature.',
              ),
              const SizedBox(height: 12),
              _FeatureCard(
                icon: Icons.handshake_outlined,
                color: Colors.amber,
                title: 'Handoff',
                description:
                    'Connect the signed job to an installer team for Day 1 pre-wire and Day 2 install.',
              ),
              const SizedBox(height: 40),

              // Action buttons
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutes.salesProspect),
                  icon: const Icon(Icons.add, color: Colors.black),
                  label: Text(
                    'New Visit',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w700,
                      color: Colors.black,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.salesJobs),
                  icon: Icon(Icons.folder_outlined, color: NexGenPalette.cyan),
                  label: Text(
                    'My Estimates',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w600,
                      color: NexGenPalette.cyan,
                      fontSize: 16,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => context.push(AppRoutes.dealerDashboard),
                  icon: Icon(Icons.dashboard_outlined, color: Colors.amber),
                  label: Text(
                    'Dashboard',
                    style: GoogleFonts.montserrat(
                      fontWeight: FontWeight.w600,
                      color: Colors.amber,
                      fontSize: 16,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(color: Colors.amber.withValues(alpha: 0.4)),
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.color,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: color.withValues(alpha: 0.15),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.montserrat(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  description,
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                    height: 1.3,
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
