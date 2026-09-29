import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:nexgen_command/theme.dart';

/// Key for tracking tour completion
const String kFeatureTourCompletedKey = 'feature_tour_completed_v1';

/// Check if user has completed the feature tour.
/// Checks Firestore first (for cross-device sync), falls back to SharedPreferences.
Future<bool> isFeatureTourCompleted() async {
  try {
    // First, check Firestore if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();

      if (doc.exists) {
        final tourCompleted = doc.data()?['feature_tour_completed'] as bool?;
        if (tourCompleted == true) {
          // Also update local storage for offline access
          final prefs = await SharedPreferences.getInstance();
          await prefs.setBool(kFeatureTourCompletedKey, true);
          return true;
        }
      }
    }

    // Fall back to local SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(kFeatureTourCompletedKey) ?? false;
  } catch (e) {
    debugPrint('Feature tour completed check error: $e');
    // Fall back to local storage on error
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(kFeatureTourCompletedKey) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Mark the feature tour as completed in both Firestore and locally.
Future<void> markFeatureTourCompleted() async {
  try {
    // Mark locally first
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(kFeatureTourCompletedKey, true);

    // Then update Firestore if user is logged in
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .update({
        'feature_tour_completed': true,
        'updated_at': Timestamp.now(),
      });
      debugPrint('Feature tour marked complete in Firestore');
    }
  } catch (e) {
    debugPrint('Mark feature tour completed error: $e');
  }
}

/// Reset tour for testing or re-viewing
Future<void> resetFeatureTour() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(kFeatureTourCompletedKey);
    debugPrint('Feature tour reset locally');
  } catch (e) {
    debugPrint('Reset feature tour error: $e');
  }
}

/// Represents a single step in the feature tour
class TourStep {
  final String id;
  final String title;
  final String description;
  final IconData icon;
  final GlobalKey? targetKey;
  final Alignment spotlightAlignment;
  final Alignment tooltipAlignment;
  final bool showSkip;

  const TourStep({
    required this.id,
    required this.title,
    required this.description,
    required this.icon,
    this.targetKey,
    this.spotlightAlignment = Alignment.center,
    this.tooltipAlignment = Alignment.bottomCenter,
    this.showSkip = true,
  });
}

/// Provider for the current tour state
final featureTourProvider = StateNotifierProvider<FeatureTourNotifier, FeatureTourState>((ref) {
  return FeatureTourNotifier();
});

/// Tour state
class FeatureTourState {
  final bool isActive;
  final int currentStepIndex;
  final List<TourStep> steps;

  const FeatureTourState({
    this.isActive = false,
    this.currentStepIndex = 0,
    this.steps = const [],
  });

  TourStep? get currentStep =>
      isActive && currentStepIndex < steps.length ? steps[currentStepIndex] : null;

  bool get isLastStep => currentStepIndex >= steps.length - 1;

  double get progress => steps.isEmpty ? 0 : (currentStepIndex + 1) / steps.length;

  FeatureTourState copyWith({
    bool? isActive,
    int? currentStepIndex,
    List<TourStep>? steps,
  }) {
    return FeatureTourState(
      isActive: isActive ?? this.isActive,
      currentStepIndex: currentStepIndex ?? this.currentStepIndex,
      steps: steps ?? this.steps,
    );
  }
}

/// Notifier for managing tour state
class FeatureTourNotifier extends StateNotifier<FeatureTourState> {
  FeatureTourNotifier() : super(const FeatureTourState());

  /// Start the tour with the given steps
  void startTour(List<TourStep> steps) {
    state = FeatureTourState(
      isActive: true,
      currentStepIndex: 0,
      steps: steps,
    );
  }

  /// Move to the next step
  void nextStep() {
    if (state.isLastStep) {
      endTour();
    } else {
      state = state.copyWith(currentStepIndex: state.currentStepIndex + 1);
    }
  }

  /// Move to the previous step
  void previousStep() {
    if (state.currentStepIndex > 0) {
      state = state.copyWith(currentStepIndex: state.currentStepIndex - 1);
    }
  }

  /// Skip to a specific step
  void goToStep(int index) {
    if (index >= 0 && index < state.steps.length) {
      state = state.copyWith(currentStepIndex: index);
    }
  }

  /// End the tour
  void endTour() {
    markFeatureTourCompleted();
    state = const FeatureTourState();
  }

  /// Skip the tour without completing
  void skipTour() {
    markFeatureTourCompleted();
    state = const FeatureTourState();
  }
}

/// Overlay widget that displays the tour spotlight and tooltip
class FeatureTourOverlay extends ConsumerWidget {
  final Widget child;

  const FeatureTourOverlay({super.key, required this.child});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tourState = ref.watch(featureTourProvider);

    return Stack(
      children: [
        child,
        if (tourState.isActive && tourState.currentStep != null)
          _TourOverlayContent(
            step: tourState.currentStep!,
            stepIndex: tourState.currentStepIndex,
            totalSteps: tourState.steps.length,
            progress: tourState.progress,
            isLastStep: tourState.isLastStep,
            onNext: () => ref.read(featureTourProvider.notifier).nextStep(),
            onPrevious: () => ref.read(featureTourProvider.notifier).previousStep(),
            onSkip: () => ref.read(featureTourProvider.notifier).skipTour(),
          ),
      ],
    );
  }
}

class _TourOverlayContent extends StatelessWidget {
  final TourStep step;
  final int stepIndex;
  final int totalSteps;
  final double progress;
  final bool isLastStep;
  final VoidCallback onNext;
  final VoidCallback onPrevious;
  final VoidCallback onSkip;

  const _TourOverlayContent({
    required this.step,
    required this.stepIndex,
    required this.totalSteps,
    required this.progress,
    required this.isLastStep,
    required this.onNext,
    required this.onPrevious,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.of(context).size;

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Semi-transparent backdrop
          GestureDetector(
            onTap: () {}, // Absorb taps
            child: Container(
              width: size.width,
              height: size.height,
              color: Colors.black.withValues(alpha: 0.85),
            ),
          ),

          // Tooltip card. Scrolls when a step (or large text) is taller than
          // the screen — the Next button used to be pushed off-screen, which
          // left the tour with no way forward.
          Positioned.fill(
            child: SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  padding: const EdgeInsets.all(24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: (constraints.maxHeight - 48).clamp(0, double.infinity),
                    ),
                    child: Align(
                      alignment: _cardAlignment(),
                      child: _buildTooltipCard(context),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Alignment _cardAlignment() {
    if (step.tooltipAlignment == Alignment.topCenter) {
      return Alignment.topCenter;
    } else if (step.tooltipAlignment == Alignment.bottomCenter) {
      return Alignment.bottomCenter;
    }
    return Alignment.center;
  }

  Widget _buildTooltipCard(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(maxWidth: 400),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            NexGenPalette.gunmetal90,
            NexGenPalette.gunmetal90.withValues(alpha: 0.95),
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: NexGenPalette.cyan.withValues(alpha: 0.3),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: NexGenPalette.cyan.withValues(alpha: 0.2),
            blurRadius: 30,
            spreadRadius: 5,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Progress indicator
            _buildProgressBar(),
            const SizedBox(height: 20),

            // Icon
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [NexGenPalette.violet, NexGenPalette.cyan],
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: NexGenPalette.cyan.withValues(alpha: 0.3),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Icon(
                step.icon,
                color: Colors.white,
                size: 32,
              ),
            ),
            const SizedBox(height: 20),

            // Title
            Text(
              step.title,
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 12),

            // Description
            Text(
              step.description,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Colors.white70,
                height: 1.5,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),

            // Navigation buttons
            _buildNavigationButtons(context),
          ],
        ),
      ),
    );
  }

  Widget _buildProgressBar() {
    return Column(
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          spacing: 12,
          children: [
            Text(
              'Step ${stepIndex + 1} of $totalSteps',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.6),
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
            Text(
              '${(progress * 100).round()}%',
              style: TextStyle(
                color: NexGenPalette.cyan.withValues(alpha: 0.8),
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            backgroundColor: Colors.white.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(NexGenPalette.cyan),
            minHeight: 4,
          ),
        ),
      ],
    );
  }

  Widget _buildNavigationButtons(BuildContext context) {
    // Wraps rather than overflowing when large text makes the three buttons
    // wider than the card.
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.center,
      spacing: 12,
      runSpacing: 8,
      children: [
        // Skip button
        if (step.showSkip && !isLastStep)
          TextButton(
            onPressed: onSkip,
            child: Text(
              'Skip Tour',
              style: TextStyle(
                color: Colors.white.withValues(alpha: 0.5),
              ),
            ),
          ),

        // Back button
        if (stepIndex > 0)
          TextButton.icon(
            onPressed: onPrevious,
            icon: const Icon(Icons.arrow_back, size: 18),
            label: const Text('Back'),
            style: TextButton.styleFrom(
              foregroundColor: Colors.white70,
            ),
          ),

        // Next/Done button
        FilledButton.icon(
          onPressed: onNext,
          icon: Icon(
            isLastStep ? Icons.check : Icons.arrow_forward,
            size: 18,
          ),
          label: Text(isLastStep ? 'Get Started' : 'Next'),
          style: FilledButton.styleFrom(
            backgroundColor: NexGenPalette.cyan,
            foregroundColor: Colors.black,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
          ),
        ),
      ],
    );
  }
}

/// Default tour steps for the Lumina app
List<TourStep> getDefaultTourSteps() {
  return [
    // Welcome
    const TourStep(
      id: 'welcome',
      title: 'Welcome to Lumina',
      description: 'Let\'s take a quick tour of your new lighting control system. '
          'This will only take a minute and will help you get the most out of your premium outdoor lighting.',
      icon: Icons.auto_awesome,
      tooltipAlignment: Alignment.center,
      showSkip: true,
    ),

    // Power Control
    const TourStep(
      id: 'power',
      title: 'Power Control',
      description: 'Tap the power button to turn your lights on or off instantly. '
          'The button glows cyan when your system is on.',
      icon: Icons.power_settings_new,
      tooltipAlignment: Alignment.bottomCenter,
    ),

    // Brightness
    const TourStep(
      id: 'brightness',
      title: 'Brightness Slider',
      description: 'Drag the brightness slider to adjust the intensity of your lights. '
          'Changes apply in real-time so you can find the perfect level.',
      icon: Icons.brightness_6,
      tooltipAlignment: Alignment.bottomCenter,
    ),

    // My Favorites. Row 84 (+110): this step described "Quick Presets"
    // buttons (Run Schedule / Warm White / Bright White / Holiday Mode) that
    // do not exist on Home in this build.
    const TourStep(
      id: 'favorites',
      title: 'My Favorites',
      description: 'Your favorite looks live under My Favorites on Home. '
          'Tap one to put it on your lights.\n\n'
          'To add a look, tap the heart on it in Explore.',
      icon: Icons.favorite_border,
      tooltipAlignment: Alignment.center,
    ),

    // Design Studio
    const TourStep(
      id: 'design_studio',
      title: 'Design Studio',
      description: 'Create your own custom lighting designs with precise per-LED color control. '
          'Paint colors directly onto your light strips, choose effects, and save your creations.',
      icon: Icons.palette,
      tooltipAlignment: Alignment.center,
    ),

    // Lighting Areas
    const TourStep(
      id: 'zone_control',
      title: 'Lighting Areas',
      description: 'Fine-tune individual lighting areas around your home. '
          'Adjust colors, effects, speed, and intensity for each area independently.',
      icon: Icons.tune,
      tooltipAlignment: Alignment.center,
    ),

    // Schedule
    const TourStep(
      id: 'schedule',
      title: 'Smart Scheduling',
      description: 'Set up automatic schedules so your lights turn on and off at the right times. '
          'Supports sunrise/sunset timing that adjusts throughout the year.',
      icon: Icons.schedule,
      tooltipAlignment: Alignment.center,
    ),

    // Lumina AI
    const TourStep(
      id: 'lumina_ai',
      title: 'Meet Lumina',
      description: 'Your AI lighting assistant. Just tell Lumina what you want:\n\n'
          '"Set my lights to Chiefs colors"\n'
          '"Make it look like Christmas"\n'
          '"Something warm and relaxing"\n\n'
          'Lumina learns your preferences over time.',
      icon: Icons.auto_awesome,
      tooltipAlignment: Alignment.topCenter,
    ),

    // Channels. Row 84 (+110): this step described a green/yellow
    // connection-status indicator that is not on Home in this build.
    const TourStep(
      id: 'channels',
      title: 'Choose Your Channels',
      description: 'The channel chips on Home choose which parts of your '
          'roofline a change goes to. Leave them all selected to change the '
          'whole house, or pick one to change just that part.',
      icon: Icons.linear_scale,
      tooltipAlignment: Alignment.center,
    ),

    // Completion
    const TourStep(
      id: 'complete',
      title: 'You\'re All Set!',
      description: 'You now know the essentials of controlling your Lumina lighting system. '
          'Explore the app to discover more features, and remember - Lumina AI is always here to help.\n\n'
          'Enjoy your beautiful new lights!',
      icon: Icons.celebration,
      tooltipAlignment: Alignment.center,
      showSkip: false,
    ),
  ];
}

/// Widget to trigger the tour from settings or help menu
class TourLaunchButton extends ConsumerWidget {
  const TourLaunchButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListTile(
      leading: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [NexGenPalette.violet, NexGenPalette.cyan],
          ),
          borderRadius: BorderRadius.circular(8),
        ),
        child: const Icon(Icons.school, color: Colors.white, size: 20),
      ),
      title: const Text(
        'Take the Tour',
        style: TextStyle(color: Colors.white),
      ),
      subtitle: Text(
        'Learn about all Lumina features',
        style: TextStyle(color: Colors.white.withValues(alpha: 0.6)),
      ),
      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white54, size: 16),
      onTap: () {
        ref.read(featureTourProvider.notifier).startTour(getDefaultTourSteps());
      },
    );
  }
}
