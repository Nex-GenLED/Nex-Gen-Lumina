import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/installer/admin/admin_providers.dart';
import 'package:nexgen_command/features/installer/admin/dealer_management_screen.dart';
import 'package:nexgen_command/features/installer/admin/installer_management_screen.dart';
import 'package:nexgen_command/theme.dart';

/// Admin PIN entry screen
class AdminPinScreen extends ConsumerStatefulWidget {
  const AdminPinScreen({super.key});

  @override
  ConsumerState<AdminPinScreen> createState() => _AdminPinScreenState();
}

class _AdminPinScreenState extends ConsumerState<AdminPinScreen> {
  String _enteredPin = '';
  bool _showError = false;
  static const int _pinLength = 4;

  void _onKeyPressed(String key) {
    if (_enteredPin.length < _pinLength) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin += key;
        _showError = false;
      });

      if (_enteredPin.length == _pinLength) {
        _submitPin();
      }
    }
  }

  void _onBackspace() {
    if (_enteredPin.isNotEmpty) {
      HapticFeedback.lightImpact();
      setState(() {
        _enteredPin = _enteredPin.substring(0, _enteredPin.length - 1);
        _showError = false;
      });
    }
  }

  void _submitPin() {
    if (_enteredPin == kAdminPin) {
      HapticFeedback.mediumImpact();
      ref.read(adminAuthenticatedProvider.notifier).state = true;
      context.go('/admin/dashboard');
    } else {
      HapticFeedback.heavyImpact();
      setState(() {
        _showError = true;
        _enteredPin = '';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => context.pop(),
        ),
        title: const Text('Admin Access', style: TextStyle(color: Colors.white)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Spacer(),
              // Admin icon
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: NexGenPalette.gunmetal90,
                  border: Border.all(color: NexGenPalette.line),
                ),
                child: Icon(
                  Icons.admin_panel_settings_outlined,
                  size: 48,
                  color: _showError ? Colors.red : Colors.amber,
                ),
              ),
              const SizedBox(height: 32),
              Text(
                'Enter Admin PIN',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w600,
                    ),
              ),
              const SizedBox(height: 8),
              Text(
                'Manage dealers and installers',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: NexGenPalette.textMedium,
                    ),
              ),
              const SizedBox(height: 32),
              // PIN dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(_pinLength, (index) {
                  final isFilled = index < _enteredPin.length;
                  return Container(
                    margin: const EdgeInsets.symmetric(horizontal: 8),
                    width: 20,
                    height: 20,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isFilled
                          ? (_showError ? Colors.red : Colors.amber)
                          : Colors.transparent,
                      border: Border.all(
                        color: _showError ? Colors.red : Colors.amber.withValues(alpha: 0.7),
                        width: 2,
                      ),
                    ),
                  );
                }),
              ),
              const SizedBox(height: 16),
              // Error message
              AnimatedOpacity(
                opacity: _showError ? 1.0 : 0.0,
                duration: const Duration(milliseconds: 200),
                child: const Text(
                  'Incorrect PIN',
                  style: TextStyle(color: Colors.red, fontSize: 14),
                ),
              ),
              const SizedBox(height: 32),
              // Keypad
              _buildKeypad(),
              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildKeypad() {
    return Column(
      children: [
        _buildKeypadRow(['1', '2', '3']),
        const SizedBox(height: 16),
        _buildKeypadRow(['4', '5', '6']),
        const SizedBox(height: 16),
        _buildKeypadRow(['7', '8', '9']),
        const SizedBox(height: 16),
        _buildKeypadRow(['', '0', 'backspace']),
      ],
    );
  }

  Widget _buildKeypadRow(List<String> keys) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: keys.map((key) {
        if (key.isEmpty) {
          return const SizedBox(width: 80, height: 80);
        }
        if (key == 'backspace') {
          return _buildKeypadButton(
            onPressed: _onBackspace,
            child: const Icon(Icons.backspace_outlined, color: Colors.white, size: 28),
          );
        }
        return _buildKeypadButton(
          onPressed: () => _onKeyPressed(key),
          child: Text(
            key,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 32,
              fontWeight: FontWeight.w500,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildKeypadButton({required VoidCallback onPressed, required Widget child}) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Center(child: child),
          ),
        ),
      ),
    );
  }
}

/// Admin dashboard with access to dealer and installer management
class AdminDashboardScreen extends ConsumerWidget {
  const AdminDashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAuthenticated = ref.watch(adminAuthenticatedProvider);

    // Redirect if not authenticated
    if (!isAuthenticated) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.go('/admin/pin');
      });
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    final statsAsync = ref.watch(installationStatsProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            ref.read(adminAuthenticatedProvider.notifier).state = false;
            context.pop();
          },
        ),
        title: const Text('Admin Dashboard', style: TextStyle(color: Colors.white)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.amber.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.amber.withValues(alpha: 0.5)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.admin_panel_settings, color: Colors.amber, size: 16),
                SizedBox(width: 6),
                Text('ADMIN', style: TextStyle(color: Colors.amber, fontSize: 12, fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Stats cards
            statsAsync.when(
              loading: () => const Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
              error: (_, __) => const SizedBox.shrink(),
              data: (stats) => Row(
                children: [
                  Expanded(
                    child: _StatCard(
                      label: 'Active Dealers',
                      value: stats['dealers']?.toString() ?? '0',
                      icon: Icons.business,
                      color: NexGenPalette.violet,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Active Installers',
                      value: stats['installers']?.toString() ?? '0',
                      icon: Icons.engineering,
                      color: NexGenPalette.cyan,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: _StatCard(
                      label: 'Installations',
                      value: stats['installations']?.toString() ?? '0',
                      icon: Icons.home,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),
            // Management options
            const Text(
              'Management',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            _ManagementTile(
              title: 'Manage Dealers',
              subtitle: 'Add, edit, or deactivate dealer companies',
              icon: Icons.business_outlined,
              color: NexGenPalette.violet,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const DealerManagementScreen()),
              ),
            ),
            const SizedBox(height: 12),
            _ManagementTile(
              title: 'Manage Installers',
              subtitle: 'Add, edit, or deactivate installer PINs',
              icon: Icons.engineering_outlined,
              color: NexGenPalette.cyan,
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (context) => const InstallerManagementScreen()),
              ),
            ),
            const SizedBox(height: 32),
            // Quick actions
            const Text(
              'Quick Actions',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _QuickActionButton(
                    label: 'Add Dealer',
                    icon: Icons.add_business,
                    color: NexGenPalette.violet,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const DealerManagementScreen()),
                      );
                    },
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _QuickActionButton(
                    label: 'Add Installer',
                    icon: Icons.person_add,
                    color: NexGenPalette.cyan,
                    onTap: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(builder: (context) => const InstallerManagementScreen()),
                      );
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 32),
            // Info section
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.info_outline, color: NexGenPalette.textMedium, size: 20),
                      const SizedBox(width: 8),
                      const Text(
                        'PIN Format',
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  RichText(
                    text: TextSpan(
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13, height: 1.5),
                      children: [
                        const TextSpan(text: 'Installer PINs are 4 digits: '),
                        TextSpan(
                          text: 'DD',
                          style: TextStyle(color: NexGenPalette.violet, fontWeight: FontWeight.w600),
                        ),
                        TextSpan(
                          text: 'II',
                          style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: '\n\n'),
                        TextSpan(
                          text: 'DD',
                          style: TextStyle(color: NexGenPalette.violet, fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: ' = Dealer Code (00-99)\n'),
                        TextSpan(
                          text: 'II',
                          style: TextStyle(color: NexGenPalette.cyan, fontWeight: FontWeight.w600),
                        ),
                        const TextSpan(text: ' = Installer Code (00-99)\n\n'),
                        const TextSpan(
                          text: 'Each dealer can have up to 100 installers.',
                          style: TextStyle(fontStyle: FontStyle.italic),
                        ),
                      ],
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

class _StatCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatCard({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 28,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(color: NexGenPalette.textMedium, fontSize: 11),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}

class _ManagementTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _ManagementTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: NexGenPalette.gunmetal90,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: NexGenPalette.line),
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: NexGenPalette.textMedium),
            ],
          ),
        ),
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: color.withValues(alpha: 0.15),
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: color.withValues(alpha: 0.3)),
          ),
          child: Column(
            children: [
              Icon(icon, color: color, size: 32),
              const SizedBox(height: 8),
              Text(
                label,
                style: TextStyle(color: color, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
