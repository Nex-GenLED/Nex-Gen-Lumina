import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/theme.dart';

/// Installer-mode home screen, reached after a valid installer PIN at
/// `/staff/pin`. Hosts the four primary install/service entry points
/// (New Install, Existing Customer, Day 1 Queue, Day 2 Queue) plus a
/// secondary Dealer Dashboard tile.
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

            // Explanatory header — fully visible, NOT inside an Expanded/scroll
            // wrapper that would compete with the button grid below for
            // vertical space.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Container(
                    width: 88,
                    height: 88,
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
                      size: 42,
                      color: NexGenPalette.cyan,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    'Installer Mode',
                    style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                          color: NexGenPalette.textHigh,
                          fontWeight: FontWeight.bold,
                        ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Onboard new customers, complete day-of installs, and manage existing accounts.',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: NexGenPalette.textMedium,
                          height: 1.35,
                        ),
                  ),
                ],
              ),
            ),

            // Spacer pushes the button grid toward the bottom; flex: 1 means
            // any leftover vertical space goes here, not into the explanatory
            // text.
            const Spacer(),

            // Action grid — 2 rows of 2 buttons + a full-width Dealer Dashboard.
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row 1: New Install | Existing Customer
                  Row(
                    children: [
                      Expanded(
                        child: _GridActionButton(
                          icon: Icons.home_work_outlined,
                          label: 'New Install',
                          accent: NexGenPalette.green,
                          onTap: () => context.push(AppRoutes.installerWizard),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GridActionButton(
                          icon: Icons.manage_accounts,
                          label: 'Existing Customer',
                          accent: NexGenPalette.cyan,
                          onTap: () => context.push(AppRoutes.existingCustomer),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 2: Day 1 Queue | Day 2 Queue
                  Row(
                    children: [
                      Expanded(
                        child: _GridActionButton(
                          icon: Icons.looks_one_outlined,
                          label: 'Day 1 Queue',
                          accent: NexGenPalette.cyan,
                          onTap: () => context.push(AppRoutes.day1Queue),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _GridActionButton(
                          icon: Icons.looks_two_outlined,
                          label: 'Day 2 Queue',
                          accent: NexGenPalette.green,
                          onTap: () => context.push(AppRoutes.day2Queue),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // Row 3: Dealer Dashboard (full width, secondary styling, shorter)
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: OutlinedButton.icon(
                      onPressed: () => context.push(AppRoutes.dealerDashboard),
                      icon: const Icon(
                        Icons.dashboard_outlined,
                        color: NexGenPalette.gold,
                      ),
                      label: const Text(
                        'Dealer Dashboard',
                        style: TextStyle(
                          color: NexGenPalette.gold,
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(
                          color: NexGenPalette.gold.withValues(alpha: 0.4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

}

/// Square primary action tile used in the 2x2 grid on the installer
/// landing screen. Min height 80, icon above label, accent-tinted card
/// styling.
class _GridActionButton extends StatelessWidget {
  const _GridActionButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexGenPalette.gunmetal90,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Ink(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: accent.withValues(alpha: 0.4)),
          ),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 80),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(icon, color: accent, size: 26),
                  const SizedBox(height: 8),
                  Text(
                    label,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: NexGenPalette.textHigh,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
