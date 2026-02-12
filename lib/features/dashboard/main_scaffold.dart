import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/site/settings_page.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/simple/simple_dashboard.dart';
import 'package:nexgen_command/features/simple/simple_settings.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/widgets/navigation/navigation.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/services/autopilot_scheduler.dart';
import 'package:nexgen_command/features/ai/lumina_sheet_controller.dart';
import 'package:nexgen_command/features/ai/lumina_bottom_sheet.dart';

/// Global provider for the selected tab index.
/// With the Lumina tab removed, the mapping is:
///   0 = Home, 1 = Schedule, 2 = Explore, 3 = System
/// (Index 2 was Lumina — now replaced by the bottom sheet overlay.)
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);

/// Root shell with persistent Bottom Navigation (Glass Dock).
/// The center Lumina button now opens a draggable bottom sheet
/// instead of navigating to a dedicated tab.
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _tourChecked = false;

  // Pages without Lumina (it's now a bottom sheet overlay)
  final _pages = const [
    WledDashboardPage(),     // 0 — Home
    MySchedulePage(),        // 1 — Schedule
    ExplorePatternsScreen(), // 2 — Explore
    SettingsPage(),          // 3 — System
  ];

  final _simplePages = const [
    SimpleDashboard(),
    SimpleSettings(),
  ];

  void _onTap(int i) {
    ref.read(selectedTabIndexProvider.notifier).state = i;
  }

  /// Quick tap on Lumina button → open compact sheet.
  void _handleLuminaTap() {
    showLuminaSheet(context, ref, mode: LuminaSheetMode.compact);
  }

  /// Long-press on Lumina button → open listening sheet with haptic.
  void _handleLuminaLongPress() {
    showLuminaSheet(context, ref, mode: LuminaSheetMode.listening);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(geofenceMonitorProvider.notifier);
      await notifier.ensurePermissionsWithDialog(context);
      await notifier.start();

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
    final tabIndex = ref.watch(selectedTabIndexProvider);
    final luminaState = ref.watch(luminaSheetProvider);

    ref.listen(simpleModeProvider, (previous, next) {
      if (previous != next) {
        ref.read(selectedTabIndexProvider.notifier).state = 0;
      }
    });

    return FeatureTourOverlay(
      child: Scaffold(
        extendBody: true,
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Stack(children: [
          Positioned.fill(
            child: IndexedStack(
              index: tabIndex,
              children: isSimpleMode ? _simplePages : _pages,
            ),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: isSimpleMode
                ? SimpleNavBar(index: tabIndex, onTap: _onTap)
                : GlassDockNavBar(
                    index: tabIndex,
                    onTap: _onTap,
                    onLuminaTap: _handleLuminaTap,
                    onLuminaLongPress: _handleLuminaLongPress,
                    isVoiceListening: luminaState.isOpen &&
                        luminaState.mode == LuminaSheetMode.listening,
                    hasActiveSession: luminaState.hasActiveSession,
                  ),
          ),
        ]),
      ),
    );
  }
}
