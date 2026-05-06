import 'dart:async' show unawaited;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/app_router.dart';
import 'package:nexgen_command/features/demo/demo_lead_service.dart';
import 'package:nexgen_command/features/demo/demo_providers.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/widgets/installer_mode_banner.dart';
import 'package:nexgen_command/widgets/navigation/navigation.dart';
import 'package:nexgen_command/features/autopilot/game_day_autopilot_providers.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart';
import 'package:nexgen_command/theme.dart';

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
    ref.watch(installationConfigLoaderProvider);
    ref.watch(gameDayBackgroundPersistenceKeepAliveProvider);

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

    final isBrowsing = ref.watch(demoBrowsingProvider);

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
        child: Column(
          children: [
            // Installer-impersonation banner — visible whenever an
            // installer entered a customer's account from the existing-
            // customer search. Renders an empty SizedBox.shrink when no
            // session is active, so it's always safe to mount.
            const InstallerModeBanner(),
            if (isBrowsing) _DemoBanner(onExit: () => _showExitDemoSheet(context)),
            Expanded(
              child: Scaffold(
                extendBody: true,
                backgroundColor: Theme.of(context).scaffoldBackgroundColor,
                body: Stack(
                  children: [
                    Positioned.fill(
                      child: _ShellBranchHost(
                          navigationShell: widget.navigationShell),
                    ),
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
          ],
        ),
      ),
    );
  }

  void _showExitDemoSheet(BuildContext context) {
    showDemoExitSheet(context, ref);
  }
}

/// Wraps the StatefulNavigationShell with two app-wide keyboard-dismiss
/// behaviors that every screen inherits automatically.
///
/// **Note on bottom nav inset**: The dock-height inset is NOT applied
/// here via MediaQuery injection. The codebase already has an
/// established `navBarTotalHeight(context)` helper in `app_colors.dart`
/// (used by 30+ screens) that returns `kNavBarContentHeight + bottom
/// device inset`. Injecting an additional 100px into MediaQuery here
/// would double-pad every screen that already calls that helper. New
/// screens with hidden bottom buttons should be fixed by adding
/// `padding: EdgeInsets.only(bottom: navBarTotalHeight(context))`
/// to their scrollable, matching the existing convention.
///
/// 1. **Tap-outside keyboard dismiss** — translucent GestureDetector
///    that calls `unfocus()` when the user taps an inert area. The
///    `HitTestBehavior.translucent` flag is critical: without it the
///    detector either swallows taps to interactive children
///    (`opaque`) or never receives taps in empty regions (default).
///
/// 2. **Scroll-triggered keyboard dismiss** — listens for
///    [ScrollStartNotification] anywhere in the descendant tree and
///    calls `unfocus()` when scrolling begins. This is functionally
///    equivalent to setting
///    `keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag`
///    on every scroll view in the app, applied once at the shell.
///    Dropdowns and autocomplete overlays use the root Overlay (a
///    sibling of this Navigator), so their internal scrolls do NOT
///    bubble up here and will not interfere with autocomplete UX.
class _ShellBranchHost extends StatelessWidget {
  final Widget navigationShell;
  const _ShellBranchHost({required this.navigationShell});

  @override
  Widget build(BuildContext context) {
    return NotificationListener<ScrollStartNotification>(
      onNotification: (notification) {
        // Only dismiss for user-initiated drags, not programmatic
        // scrolls (e.g., scrollToIndex animations).
        if (notification.dragDetails != null) {
          FocusManager.instance.primaryFocus?.unfocus();
        }
        // Return false so the notification continues bubbling.
        return false;
      },
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusManager.instance.primaryFocus?.unfocus(),
        child: navigationShell,
      ),
    );
  }
}

/// Persistent gradient banner shown at the top of the scaffold during demo browsing.
class _DemoBanner extends StatelessWidget {
  final VoidCallback onExit;
  const _DemoBanner({required this.onExit});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 44,
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF6E2FFF), Color(0xFF00D4FF)],
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SafeArea(
        bottom: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.white.withValues(alpha: 0.9),
                  ),
                ),
                const SizedBox(width: 8),
                const Text(
                  'Demo mode \u2014 simulated lighting',
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            GestureDetector(
              onTap: onExit,
              child: Text(
                'Exit demo',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.white.withValues(alpha: 0.85),
                  decoration: TextDecoration.underline,
                  decorationColor: Colors.white.withValues(alpha: 0.85),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Shows the demo exit bottom sheet with conversion options.
/// Reusable from any screen during demo browsing.
void showDemoExitSheet(BuildContext context, WidgetRef ref) {
  void logExit(String path) {
    try {
      final leadId = ref.read(demoLeadProvider)?.id;
      if (leadId != null) {
        final svc = ref.read(demoLeadServiceProvider);
        unawaited(svc.logExitDemoTapped(leadId, path)
            .catchError((e) => debugPrint('Demo analytics: $e')));
      }
    } catch (_) {}
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: NexGenPalette.gunmetal,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (sheetCtx) => Padding(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle bar
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white24,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Ready for your own lights?',
            style: Theme.of(sheetCtx).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            'Talk to a Nex-Gen dealer about your home',
            style: Theme.of(sheetCtx).textTheme.bodySmall?.copyWith(
                  color: NexGenPalette.textMedium,
                ),
          ),
          const SizedBox(height: 20),
          // Request consultation
          SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton(
              onPressed: () {
                logExit('consultation');
                Navigator.pop(sheetCtx);
                exitDemoMode(ref);
                context.go(AppRoutes.demoComplete);
              },
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF00D4FF),
                foregroundColor: const Color(0xFF07091A),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Request a free consultation'),
            ),
          ),
          const SizedBox(height: 12),
          // Create account
          SizedBox(
            width: double.infinity,
            height: 48,
            child: OutlinedButton(
              onPressed: () {
                logExit('signup');
                Navigator.pop(sheetCtx);
                exitDemoMode(ref);
                context.go(AppRoutes.signUp);
              },
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: NexGenPalette.line),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Create an account'),
            ),
          ),
          const SizedBox(height: 8),
          // Keep exploring
          TextButton(
            onPressed: () {
              logExit('keep_exploring');
              Navigator.pop(sheetCtx);
            },
            child: Text(
              'Keep exploring',
              style: TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
            ),
          ),
        ],
      ),
    ),
  );
}
