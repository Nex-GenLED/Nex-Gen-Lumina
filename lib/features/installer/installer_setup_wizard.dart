import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/installer/installer_providers.dart';
import 'package:nexgen_command/features/installer/screens/customer_info_screen.dart';
import 'package:nexgen_command/features/installer/handoff_screen.dart';
import 'package:nexgen_command/theme.dart';

/// Main wizard shell for installer setup flow
class InstallerSetupWizard extends ConsumerStatefulWidget {
  const InstallerSetupWizard({super.key});

  @override
  ConsumerState<InstallerSetupWizard> createState() => _InstallerSetupWizardState();
}

class _InstallerSetupWizardState extends ConsumerState<InstallerSetupWizard> {
  @override
  void initState() {
    super.initState();
    // Record activity on wizard entry
    ref.read(installerModeActiveProvider.notifier).recordActivity();
  }

  @override
  Widget build(BuildContext context) {
    final isInstallerMode = ref.watch(installerModeActiveProvider);
    final currentStep = ref.watch(installerWizardStepProvider);

    // If not in installer mode, redirect back
    if (!isInstallerMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) context.go('/');
      });
      return const Scaffold(
        backgroundColor: NexGenPalette.matteBlack,
        body: Center(child: CircularProgressIndicator(color: NexGenPalette.cyan)),
      );
    }

    // Get current session info
    final session = ref.watch(installerSessionProvider);
    final installerName = session?.installer.name ?? 'Unknown';
    final dealerName = session?.dealer.companyName ?? 'Unknown Dealer';

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: NexGenPalette.gunmetal90,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close, color: Colors.white),
          onPressed: () => _showExitConfirmation(context),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Installer Setup', style: TextStyle(color: Colors.white, fontSize: 18)),
            Text(
              '$installerName • $dealerName',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 12),
            ),
          ],
        ),
        actions: [
          // Installer mode indicator with PIN display
          Container(
            margin: const EdgeInsets.only(right: 16),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: NexGenPalette.cyan.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.engineering, color: NexGenPalette.cyan, size: 16),
                const SizedBox(width: 6),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('INSTALLER', style: TextStyle(color: NexGenPalette.cyan, fontSize: 10, fontWeight: FontWeight.w600)),
                    Text(
                      session?.pin ?? '----',
                      style: TextStyle(color: NexGenPalette.cyan.withValues(alpha: 0.7), fontSize: 10),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          // Progress indicator
          _buildProgressIndicator(currentStep),
          // Current step content
          Expanded(child: _buildStepContent(currentStep)),
        ],
      ),
    );
  }

  Widget _buildProgressIndicator(InstallerWizardStep currentStep) {
    final steps = InstallerWizardStep.values;
    final currentIndex = steps.indexOf(currentStep);

    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        border: Border(bottom: BorderSide(color: NexGenPalette.line)),
      ),
      child: Row(
        children: List.generate(steps.length, (index) {
          final isCompleted = index < currentIndex;
          final isCurrent = index == currentIndex;
          final stepInfo = _getStepInfo(steps[index]);

          return Expanded(
            child: Row(
              children: [
                // Step circle
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isCompleted
                        ? NexGenPalette.cyan
                        : isCurrent
                            ? NexGenPalette.cyan.withValues(alpha: 0.3)
                            : NexGenPalette.matteBlack,
                    border: Border.all(
                      color: isCompleted || isCurrent ? NexGenPalette.cyan : NexGenPalette.line,
                      width: 2,
                    ),
                  ),
                  child: Center(
                    child: isCompleted
                        ? const Icon(Icons.check, color: Colors.white, size: 16)
                        : Text(
                            '${index + 1}',
                            style: TextStyle(
                              color: isCurrent ? NexGenPalette.cyan : NexGenPalette.textMedium,
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ),
                const SizedBox(width: 8),
                // Step label (only show for current and adjacent steps on small screens)
                Expanded(
                  child: Text(
                    stepInfo.shortLabel,
                    style: TextStyle(
                      color: isCurrent ? Colors.white : NexGenPalette.textMedium,
                      fontSize: 11,
                      fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                // Connector line
                if (index < steps.length - 1)
                  Expanded(
                    child: Container(
                      height: 2,
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      color: isCompleted ? NexGenPalette.cyan : NexGenPalette.line,
                    ),
                  ),
              ],
            ),
          );
        }),
      ),
    );
  }

  Widget _buildStepContent(InstallerWizardStep step) {
    // Record activity when navigating between steps
    ref.read(installerModeActiveProvider.notifier).recordActivity();

    switch (step) {
      case InstallerWizardStep.customerInfo:
        return CustomerInfoScreen(
          onNext: () => _goToStep(InstallerWizardStep.controllerSetup),
        );
      case InstallerWizardStep.controllerSetup:
        return _buildPlaceholderStep(
          'Controller Setup',
          'Configure WLED controllers and network settings.',
          Icons.router_outlined,
          onBack: () => _goToStep(InstallerWizardStep.customerInfo),
          onNext: () => _goToStep(InstallerWizardStep.zoneConfiguration),
        );
      case InstallerWizardStep.zoneConfiguration:
        return _buildPlaceholderStep(
          'Zone Configuration',
          'Define lighting zones and assign controllers.',
          Icons.grid_view_outlined,
          onBack: () => _goToStep(InstallerWizardStep.controllerSetup),
          onNext: () => _goToStep(InstallerWizardStep.scheduleSetup),
        );
      case InstallerWizardStep.scheduleSetup:
        return _buildPlaceholderStep(
          'Schedule Setup',
          'Configure default schedules and automations.',
          Icons.schedule_outlined,
          onBack: () => _goToStep(InstallerWizardStep.zoneConfiguration),
          onNext: () => _goToStep(InstallerWizardStep.handoff),
        );
      case InstallerWizardStep.handoff:
        return HandoffScreen(
          onBack: () => _goToStep(InstallerWizardStep.scheduleSetup),
          onNext: _completeSetup,
        );
    }
  }

  Widget _buildPlaceholderStep(
    String title,
    String description,
    IconData icon, {
    VoidCallback? onBack,
    VoidCallback? onNext,
    String nextLabel = 'Next',
  }) {
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Spacer(),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: NexGenPalette.gunmetal90,
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Icon(icon, size: 64, color: NexGenPalette.cyan),
          ),
          const SizedBox(height: 32),
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 24,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            description,
            style: const TextStyle(color: NexGenPalette.textMedium, fontSize: 16),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.construction, color: Colors.orange, size: 20),
                SizedBox(width: 8),
                Text(
                  'Coming in Phase 2',
                  style: TextStyle(color: Colors.orange, fontWeight: FontWeight.w500),
                ),
              ],
            ),
          ),
          const Spacer(),
          // Navigation buttons
          Row(
            children: [
              if (onBack != null)
                Expanded(
                  child: OutlinedButton(
                    onPressed: onBack,
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      side: const BorderSide(color: NexGenPalette.line),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: const Text('Back', style: TextStyle(color: Colors.white)),
                  ),
                ),
              if (onBack != null) const SizedBox(width: 16),
              if (onNext != null)
                Expanded(
                  child: ElevatedButton(
                    onPressed: onNext,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: NexGenPalette.cyan,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                    child: Text(nextLabel, style: const TextStyle(color: Colors.black, fontWeight: FontWeight.w600)),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _goToStep(InstallerWizardStep step) {
    ref.read(installerWizardStepProvider.notifier).state = step;
  }

  void _completeSetup() {
    // TODO: Save all configuration, create user account, etc.
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Setup Complete!', style: TextStyle(color: Colors.white)),
        content: const Text(
          'The system has been configured successfully. The customer can now use the app.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
              this.context.go('/');
            },
            child: const Text('Done', style: TextStyle(color: NexGenPalette.cyan)),
          ),
        ],
      ),
    );
  }

  void _showExitConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Exit Installer Mode?', style: TextStyle(color: Colors.white)),
        content: const Text(
          'Your progress will be saved, but you will need to re-enter the PIN to continue.',
          style: TextStyle(color: NexGenPalette.textMedium),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Cancel', style: TextStyle(color: NexGenPalette.textMedium)),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              ref.read(installerModeActiveProvider.notifier).exitInstallerMode();
              this.context.go('/');
            },
            child: const Text('Exit', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }

  _StepInfo _getStepInfo(InstallerWizardStep step) {
    switch (step) {
      case InstallerWizardStep.customerInfo:
        return _StepInfo('Customer Info', 'Customer');
      case InstallerWizardStep.controllerSetup:
        return _StepInfo('Controller Setup', 'Controller');
      case InstallerWizardStep.zoneConfiguration:
        return _StepInfo('Zone Configuration', 'Zones');
      case InstallerWizardStep.scheduleSetup:
        return _StepInfo('Schedule Setup', 'Schedule');
      case InstallerWizardStep.handoff:
        return _StepInfo('Customer Handoff', 'Handoff');
    }
  }
}

class _StepInfo {
  final String label;
  final String shortLabel;

  _StepInfo(this.label, this.shortLabel);
}
