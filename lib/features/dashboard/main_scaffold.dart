import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'package:nexgen_command/features/ai/lumina_chat_screen.dart';
import 'package:nexgen_command/features/site/settings_page.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/simple/simple_dashboard.dart';
import 'package:nexgen_command/features/simple/simple_settings.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/widgets/navigation/navigation.dart';
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';

/// Global provider for the selected tab index
final selectedTabIndexProvider = StateProvider<int>((ref) => 0);

/// Wrapper page for Lumina chat
class LuminaChatPage extends StatelessWidget {
  const LuminaChatPage({super.key});

  @override
  Widget build(BuildContext context) {
    return const LuminaChatScreen();
  }
}

/// Root shell with persistent 5-item Bottom Navigation (Glass Dock)
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _tourChecked = false;

  // Voice recognition state
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _voiceListening = false;

  final _pages = const [
    WledDashboardPage(),
    MySchedulePage(),
    LuminaChatPage(),
    ExplorePatternsScreen(),
    SettingsPage(),
  ];

  final _simplePages = const [
    SimpleDashboard(),
    SimpleSettings(),
  ];

  void _onTap(int i) {
    ref.read(selectedTabIndexProvider.notifier).state = i;
  }

  @override
  void initState() {
    super.initState();
    // Start geofence monitoring after first frame so dialogs can show safely.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final notifier = ref.read(geofenceMonitorProvider.notifier);
      await notifier.ensurePermissionsWithDialog(context);
      await notifier.start();

      // Check if we should show the feature tour (only in full mode)
      final isSimpleMode = ref.read(simpleModeProvider);
      if (!_tourChecked && !isSimpleMode) {
        _tourChecked = true;
        final tourCompleted = await isFeatureTourCompleted();
        if (!tourCompleted && mounted) {
          // Small delay to let the UI settle before showing tour
          await Future.delayed(const Duration(milliseconds: 500));
          if (mounted) {
            ref.read(featureTourProvider.notifier).startTour(getDefaultTourSteps());
          }
        }
      }
    });
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  /// Handle long-press on Lumina button to start voice recognition
  Future<void> _handleVoiceLongPress() async {
    if (_voiceListening) {
      await _speech.stop();
      setState(() => _voiceListening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Voice status: $status');
          if (status == 'done' || status == 'notListening') {
            if (mounted) {
              setState(() => _voiceListening = false);
            }
          }
        },
        onError: (error) {
          debugPrint('Voice error: ${error.errorMsg}');
          if (mounted) {
            setState(() => _voiceListening = false);
          }
        },
      );

      if (!available) {
        debugPrint('Voice recognition not available');
        return;
      }

      setState(() => _voiceListening = true);

      await _speech.listen(
        onResult: (result) async {
          if (!mounted) return;

          final recognizedWords = result.recognizedWords;
          debugPrint('Voice recognized: $recognizedWords (final: ${result.finalResult})');

          // Only process final results
          if (result.finalResult && recognizedWords.isNotEmpty) {
            setState(() => _voiceListening = false);
            await _speech.stop();

            // Set the pending voice message for Lumina to consume
            ref.read(pendingVoiceMessageProvider.notifier).state = recognizedWords;

            // Navigate to Lumina tab (index 2)
            ref.read(selectedTabIndexProvider.notifier).state = 2;
          }
        },
        listenOptions: stt.SpeechListenOptions(
          listenMode: stt.ListenMode.confirmation,
          partialResults: true,
        ),
      );
    } catch (e) {
      debugPrint('Voice initialization failed: $e');
      if (mounted) {
        setState(() => _voiceListening = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Auto-connect to saved controller on app load
    ref.watch(autoConnectControllerProvider);

    // Watch Simple Mode state
    final isSimpleMode = ref.watch(simpleModeProvider);

    // Watch the global tab index provider
    final tabIndex = ref.watch(selectedTabIndexProvider);

    // Reset tab index to 0 when switching modes
    ref.listen(simpleModeProvider, (previous, next) {
      if (previous != next) {
        ref.read(selectedTabIndexProvider.notifier).state = 0;
      }
    });

    // Use an overlayed dock to guarantee bottom pinning across platforms
    // and avoid any layout quirks with Scaffold.bottomNavigationBar.
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
                    onLuminaLongPress: _handleVoiceLongPress,
                    isVoiceListening: _voiceListening,
                  ),
          ),
        ]),
      ),
    );
  }
}
