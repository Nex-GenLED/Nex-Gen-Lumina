import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';

/// Screen shown to users who have created an account but are not linked
/// to any Nex-Gen LED installation.
///
/// This blocks access to app features until the user either:
/// 1. Enters an invitation code from a Primary user
/// 2. Is set up by an installer
/// 3. Contacts a dealer to purchase a system
class LinkAccountScreen extends ConsumerWidget {
  const LinkAccountScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            children: [
              const Spacer(),
              // Logo
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
                      NexGenPalette.cyan.withValues(alpha: 0.5),
                    ],
                  ),
                ),
                child: const Icon(
                  Icons.lightbulb_outline,
                  size: 60,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 32),
              // Welcome message
              const Text(
                'Welcome to Lumina',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'This app requires a Nex-Gen LED lighting system.',
                style: TextStyle(
                  color: NexGenPalette.textMedium,
                  fontSize: 16,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              if (user != null)
                Text(
                  'Signed in as ${user.email}',
                  style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.7),
                    fontSize: 14,
                  ),
                ),
              const Spacer(),
              // Option 1: Have invitation code
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => context.push(AppRoutes.joinWithCode),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: NexGenPalette.cyan,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.vpn_key, color: Colors.black),
                  label: const Text(
                    'I have an invitation code',
                    style: TextStyle(
                      color: Colors.black,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Option 2: Find a dealer
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _showDealerInfo(context),
                  style: OutlinedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    side: const BorderSide(color: NexGenPalette.line),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: const Icon(Icons.store, color: Colors.white),
                  label: const Text(
                    'Find a Nex-Gen dealer',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              // Professional access section
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: NexGenPalette.gunmetal90.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.badge_outlined, size: 18, color: NexGenPalette.textMedium),
                        const SizedBox(width: 8),
                        Text(
                          'Nex-Gen Professional Access',
                          style: TextStyle(
                            color: NexGenPalette.textMedium,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: _ProfessionalButton(
                            icon: Icons.engineering_outlined,
                            label: 'Installer',
                            color: NexGenPalette.cyan,
                            onTap: () => context.push(AppRoutes.installerLanding),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _ProfessionalButton(
                            icon: Icons.videocam_outlined,
                            label: 'Media',
                            color: NexGenPalette.magenta,
                            onTap: () => context.push(AppRoutes.mediaLanding),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              // Sign out option
              TextButton(
                onPressed: () async {
                  await FirebaseAuth.instance.signOut();
                  if (context.mounted) {
                    context.go(AppRoutes.login);
                  }
                },
                child: Text(
                  'Sign out',
                  style: TextStyle(
                    color: NexGenPalette.textMedium.withValues(alpha: 0.6),
                    fontSize: 14,
                  ),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  void _showDealerInfo(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text(
          'Find a Dealer',
          style: TextStyle(color: Colors.white),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'To get a Nex-Gen LED lighting system installed:',
              style: TextStyle(color: NexGenPalette.textMedium),
            ),
            const SizedBox(height: 16),
            _buildInfoRow(Icons.language, 'Visit nexgenled.com'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.email, 'info@nexgenled.com'),
            const SizedBox(height: 12),
            _buildInfoRow(Icons.phone, '1-800-NEXGEN-LED'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: NexGenPalette.cyan, size: 20),
        const SizedBox(width: 12),
        Text(text, style: const TextStyle(color: Colors.white)),
      ],
    );
  }
}

/// Button for professional access options (Installer / Media).
class _ProfessionalButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ProfessionalButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(
                color: color,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
