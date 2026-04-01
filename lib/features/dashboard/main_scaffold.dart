import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart' show selectedTabIndexProvider;
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/widgets/navigation/navigation.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart';

/// Root shell with persistent Bottom Navigation (Glass Dock).
/// Receives a [StatefulNavigationShell] from GoRouter's StatefulShellRoute
/// to display the correct branch navigator and handle tab switching.
///
/// Branch mapping:
///   0 = Home (/dashboard)
///   1 = Schedule (/schedule)
///   2 = Explore (/explore)
///   3 = System (/settings)
class MainScaffold extends ConsumerStatefulWidget {
  final StatefulNavigationShell navigationShell;

  const MainScaffold({super.key, required this.navigationShell});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _tourChecked = false;

  void _onTap(int index) {
    // If tapping the already-active tab, reset to its root
    widget.navigationShell.goBranch(
      index,
      initialLocation: index == widget.navigationShell.currentIndex,
    );
    // Keep selectedTabIndexProvider in sync for backward compatibility
    ref.read(selectedTabIndexProvider.notifier).state = index;
  }

  /// Quick tap on Lumina button → open full-screen Lumina AI chat.
  void _handleLuminaTap() {
    context.push('/lumina-ai');
  }

  /// Long-press on Lumina button → open listening sheet with haptic.
  void _handleLuminaLongPress() {
    showLuminaSheet(context, ref, mode: LuminaSheetMode.listening);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Only start geofence monitoring if location permission is already
      // granted. Never prompt on launch — the dialog is shown contextually
      // when the user enables geofencing from Settings.
      if (await ref.read(geofenceMonitorProvider.notifier).hasLocationPermission()) {
        await ref.read(geofenceMonitorProvider.notifier).start();
      }

      ref.read(autopilotSchedulerProvider);

      final isSimpleMode = ref.read(simpleModeProvider);
      if (!_tourChecked && !isSimpleMode) {
        _tourChecked = true;
        final tourCompleted = await isFeatureTourCompleted();
        if (!tourCompleted && mounted) {
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            ref.read(featureTourProvider.notifier).startTour(getDefaultTourSteps());
          }
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    ref.watch(autoConnectControllerProvider);

    final isSimpleMode = ref.watch(simpleModeProvider);
    final luminaState = ref.watch(luminaSheetProvider);
    final shellIndex = widget.navigationShell.currentIndex;

    // Sync selectedTabIndexProvider with shell's current index
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (ref.read(selectedTabIndexProvider) != shellIndex) {
        ref.read(selectedTabIndexProvider.notifier).state = shellIndex;
      }
    });

    // Listen for external tab changes (e.g., from Lumina bottom sheet commands)
    ref.listen(selectedTabIndexProvider, (previous, next) {
      if (next != widget.navigationShell.currentIndex) {
        widget.navigationShell.goBranch(next);
      }
    });

    // Reset to Home tab when switching between simple/full mode
    ref.listen(simpleModeProvider, (previous, next) {
      if (previous != next) {
        widget.navigationShell.goBranch(0);
        ref.read(selectedTabIndexProvider.notifier).state = 0;
      }
    });

    return FeatureTourOverlay(
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          // If on a non-Home branch root, switch to Home instead of exiting
          if (shellIndex != 0) {
            _onTap(0);
          }
        },
        child: Scaffold(
          extendBody: true,
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          body: Stack(
            children: [
              Positioned.fill(child: widget.navigationShell),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: isSimpleMode
                    ? SimpleNavBar(
                        index: shellIndex == 3 ? 1 : 0,
                        onTap: (i) => _onTap(i == 0 ? 0 : 3),
                      )
                    : GlassDockNavBar(
                        index: shellIndex,
                        onTap: _onTap,
                        onLuminaTap: _handleLuminaTap,
                        onLuminaLongPress: _handleLuminaLongPress,
                        isVoiceListening: luminaState.isOpen &&
                            luminaState.mode == LuminaSheetMode.listening,
                        hasActiveSession: luminaState.hasActiveSession,
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
