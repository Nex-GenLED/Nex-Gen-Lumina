import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/estimate_wizard_notifier.dart';
import 'package:nexgen_command/theme.dart';

/// Total number of steps in the Estimate Wizard. Used to compute the
/// progress bar fill on the step indicator.
const int kEstimateWizardStepCount = 5;

/// Shared chrome for every step screen in the Estimate Wizard.
///
/// Renders the AppBar, "Save & Exit" action, step indicator, body, and
/// a sticky bottom action bar (typically a "Continue" button supplied
/// by the step). Each step screen builds its body content and passes
/// it through this shell.
class WizardShell extends ConsumerStatefulWidget {
  /// 1-based step number this screen represents.
  final int stepNumber;

  /// Short label for this step (e.g. "Home photo", "Controller").
  final String stepTitle;

  /// AppBar title (typically "New Estimate").
  final String appBarTitle;

  /// Job id used to look up the wizard notifier and route back to job
  /// detail on Save & Exit.
  final String jobId;

  /// Body of the step. Sits between the step indicator and the bottom
  /// action bar in a scroll view.
  final Widget body;

  /// Optional bottom action bar (usually a "Continue" button).
  final Widget? bottomAction;

  /// Optional override for the back button. Defaults to `Navigator.pop`.
  final VoidCallback? onBack;

  const WizardShell({
    super.key,
    required this.stepNumber,
    required this.stepTitle,
    required this.jobId,
    required this.body,
    this.appBarTitle = 'New Estimate',
    this.bottomAction,
    this.onBack,
  });

  @override
  ConsumerState<WizardShell> createState() => _WizardShellState();
}

class _WizardShellState extends ConsumerState<WizardShell> {
  bool _isSaving = false;

  Future<void> _saveAndExit() async {
    if (_isSaving) return;
    setState(() => _isSaving = true);
    try {
      await ref
          .read(estimateWizardProvider(widget.jobId).notifier)
          .saveProgress();
      if (!mounted) return;
      // Pop back to job detail. The wizard always launches from there.
      context.go(
        AppRoutes.salesJobDetail.replaceFirst(':jobId', widget.jobId),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final progress = widget.stepNumber / kEstimateWizardStepCount;

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: Text(widget.appBarTitle),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: widget.onBack ?? () => Navigator.of(context).maybePop(),
        ),
        actions: [
          TextButton(
            onPressed: _isSaving ? null : _saveAndExit,
            child: _isSaving
                ? const SizedBox(
                    height: 16,
                    width: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: NexGenPalette.cyan,
                    ),
                  )
                : Text(
                    'Save & Exit',
                    style: TextStyle(
                      color: NexGenPalette.cyan.withValues(alpha: 0.9),
                      fontWeight: FontWeight.w500,
                    ),
                  ),
          ),
          const SizedBox(width: 8),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Step ${widget.stepNumber} of $kEstimateWizardStepCount — '
                  '${widget.stepTitle}',
                  style: TextStyle(
                    color: Colors.white.withValues(alpha: 0.6),
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(4),
                  child: LinearProgressIndicator(
                    value: progress,
                    backgroundColor: Colors.white.withValues(alpha: 0.1),
                    color: NexGenPalette.cyan,
                    minHeight: 4,
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
          Expanded(child: widget.body),
          if (widget.bottomAction != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: widget.bottomAction!,
            ),
        ],
      ),
    );
  }
}

/// Standardized "Continue →" primary button used at the bottom of every
/// step. Disabled state is left to the caller.
class WizardContinueButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String label;
  final bool isLoading;

  const WizardContinueButton({
    super.key,
    required this.onPressed,
    this.label = 'Continue →',
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        onPressed: isLoading ? null : onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: NexGenPalette.cyan,
          disabledBackgroundColor: NexGenPalette.cyan.withValues(alpha: 0.3),
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        child: isLoading
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.black,
                ),
              )
            : Text(
                label,
                style: const TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
      ),
    );
  }
}
