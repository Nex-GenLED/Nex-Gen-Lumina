import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/app_colors.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_state.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/business_type_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/brand_identity_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/hours_of_operation_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/channel_setup_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/your_teams_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/day_part_config_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/multi_location_screen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/screens/review_go_live_screen.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';

/// Full-screen 8-step commercial onboarding wizard.
///
/// Screens 1–4 are built in this step; screens 5–8 are placeholders
/// until the next build step fills them in.
class CommercialOnboardingWizard extends ConsumerStatefulWidget {
  const CommercialOnboardingWizard({super.key});

  @override
  ConsumerState<CommercialOnboardingWizard> createState() =>
      _CommercialOnboardingWizardState();
}

class _CommercialOnboardingWizardState
    extends ConsumerState<CommercialOnboardingWizard> {
  static const _totalSteps = 8;
  late final PageController _pageController;

  @override
  void initState() {
    super.initState();
    final initial = ref.read(commercialOnboardingStepProvider);
    _pageController = PageController(initialPage: initial);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _goToStep(int step) {
    if (step < 0 || step >= _totalSteps) return;
    ref.read(commercialOnboardingStepProvider.notifier).state = step;
    _pageController.animateToPage(
      step,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
    );
  }

  void _next() => _goToStep(ref.read(commercialOnboardingStepProvider) + 1);
  void _back() {
    final step = ref.read(commercialOnboardingStepProvider);
    if (step == 0) {
      Navigator.of(context).pop();
    } else {
      _goToStep(step - 1);
    }
  }

  void _saveAndContinueLater() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Progress saved. You can resume anytime.'),
        backgroundColor: NexGenPalette.gunmetal,
      ),
    );
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final step = ref.watch(commercialOnboardingStepProvider);

    return Scaffold(
      backgroundColor: NexGenPalette.matteBlack,
      appBar: GlassAppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _back,
        ),
        title: Text(
          'Commercial Setup',
          style: Theme.of(context)
              .textTheme
              .titleMedium
              ?.copyWith(color: NexGenPalette.textHigh),
        ),
        actions: [
          if (step >= 2)
            TextButton(
              onPressed: _saveAndContinueLater,
              child: Text(
                'Save & Exit',
                style: TextStyle(
                  color: NexGenPalette.cyan.withValues(alpha: 0.8),
                  fontSize: 13,
                ),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          _StepProgressBar(currentStep: step, totalSteps: _totalSteps),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                BusinessTypeScreen(onNext: _next),
                BrandIdentityScreen(onNext: _next),
                HoursOfOperationScreen(onNext: _next),
                ChannelSetupScreen(onNext: _next),
                YourTeamsScreen(onNext: _next),
                DayPartConfigScreen(onNext: _next),
                MultiLocationScreen(onNext: _next),
                ReviewGoLiveScreen(onGoToStep: _goToStep),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Step Progress Bar
// ---------------------------------------------------------------------------

class _StepProgressBar extends StatelessWidget {
  const _StepProgressBar({required this.currentStep, required this.totalSteps});
  final int currentStep;
  final int totalSteps;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      child: Column(
        children: [
          Row(
            children: List.generate(totalSteps, (i) {
              final isComplete = i < currentStep;
              final isCurrent = i == currentStep;
              return Expanded(
                child: Container(
                  height: 3,
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(2),
                    color: isComplete
                        ? NexGenPalette.cyan
                        : isCurrent
                            ? NexGenPalette.cyan.withValues(alpha: 0.5)
                            : NexGenPalette.line,
                  ),
                ),
              );
            }),
          ),
          const SizedBox(height: 6),
          Text(
            'Step ${currentStep + 1} of $totalSteps',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
        ],
      ),
    );
  }
}

