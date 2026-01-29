import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/usage_tracking_extension.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/widgets/mini_schedule_list.dart';
import 'package:nexgen_command/features/voice/dashboard_voice_control.dart';
import 'package:nexgen_command/features/voice/widgets/voice_control_fab.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/connection_status_indicator.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/smart_suggestions_list.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart';
import 'package:nexgen_command/features/dashboard/widgets/glass_action_button.dart';

/// Main dashboard page for WLED control
class WledDashboardPage extends ConsumerStatefulWidget {
  const WledDashboardPage({super.key});

  @override
  ConsumerState<WledDashboardPage> createState() => _WledDashboardPageState();
}

class _WledDashboardPageState extends ConsumerState<WledDashboardPage> {
  bool _checkedFirstRun = false;
  bool _pushedSetup = false;
  // Dynamically size the hero image to its natural aspect ratio to avoid cropping
  double? _heroAspectRatio; // width / height
  ImageProvider? _heroImageProvider;
  String? _heroImageId;
  // Pattern adjustment panel expanded state
  bool _adjustmentPanelExpanded = false;

  // Voice control state
  bool _voiceListening = false;
  late final stt.SpeechToText _speech;
  String? _voiceFeedbackMessage;

  // Track if user has acknowledged sync warning during this session
  bool _syncWarningAcknowledged = false;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    // Defer the check to after first frame to ensure context/router are ready
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkControllersAndMaybeLaunchWizard());
  }

  @override
  void dispose() {
    _speech.stop();
    super.dispose();
  }

  /// Checks for active sync and shows warning if needed.
  /// Returns true if user can proceed, false if they cancelled.
  Future<bool> _checkSyncWarning() async {
    // If already acknowledged during this session, skip
    if (_syncWarningAcknowledged) return true;

    final syncStatus = ref.read(userSyncStatusProvider);

    // No warning needed if not in active sync or already paused
    if (!syncStatus.isInActiveSync || syncStatus.isPaused) return true;

    // Show warning dialog
    final result = await SyncWarningDialog.showIfNeeded(context, ref);

    // No active sync (shouldn't happen, but safe check)
    if (result == null) return true;

    // User cancelled
    if (result == SyncWarningResult.cancel) return false;

    // User acknowledged - remember for this session
    _syncWarningAcknowledged = true;

    // If they chose to pause, do it now
    if (result == SyncWarningResult.pauseAndContinue) {
      await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
    }

    return true;
  }

  Future<void> _checkControllersAndMaybeLaunchWizard() async {
    if (_checkedFirstRun || _pushedSetup) return;
    _checkedFirstRun = true;
    try {
      // Only run this on the Dashboard route to avoid accidental triggers elsewhere
      final current = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
      if (!current.startsWith(AppRoutes.dashboard)) return;

      // If no authenticated user, skip.
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final col = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('controllers');
      final snap = await col.limit(1).get();
      if (snap.docs.isEmpty && mounted) {
        _pushedSetup = true;
        // Push Wi-Fi Connect page for users with existing controllers on their network
        context.push(AppRoutes.wifiConnect);
      }
    } catch (e) {
      debugPrint('First-run controller check failed: $e');
    }
  }

  void _updateHeroImage(String? url, {String? rooflineMaskVersion}) {
    try {
      final provider = (url != null && url.isNotEmpty)
          ? NetworkImage(url)
          : const AssetImage('assets/images/Demohomephoto.jpg') as ImageProvider;
      // Include roofline mask version in the ID to force reload when mask changes
      final id = (url != null && url.isNotEmpty)
          ? '$url#${rooflineMaskVersion ?? ""}'
          : 'asset:Demohomephoto';
      if (_heroImageId == id && _heroImageProvider != null) return;
      _heroImageId = id;
      _heroImageProvider = provider;
      _resolveHeroAspect(provider);
    } catch (e) {
      debugPrint('Failed to update hero image: $e');
    }
  }

  void _resolveHeroAspect(ImageProvider provider) {
    try {
      final stream = provider.resolve(createLocalImageConfiguration(context));
      late final ImageStreamListener listener;
      listener = ImageStreamListener((info, _) {
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          if (mounted) setState(() => _heroAspectRatio = w / h);
        }
        stream.removeListener(listener);
      }, onError: (error, stack) {
        debugPrint('Hero image resolve failed: $error');
        // keep default aspect ratio fallback
      });
      stream.addListener(listener);
    } catch (e) {
      debugPrint('Error resolving hero aspect: $e');
    }
  }

  /// Toggle voice listening and process the command when speech is recognized
  Future<void> _toggleVoice() async {
    if (_voiceListening) {
      await _speech.stop();
      setState(() => _voiceListening = false);
      return;
    }

    try {
      final available = await _speech.initialize(
        onStatus: (status) {
          debugPrint('Voice status: $status');
        },
        onError: (error) {
          debugPrint('Voice error: ${error.errorMsg}');
          if (mounted) {
            setState(() {
              _voiceListening = false;
              _voiceFeedbackMessage = 'Voice recognition error';
            });
          }
        },
      );

      if (!available) {
        if (mounted) {
          setState(() {
            _voiceFeedbackMessage = 'Voice recognition not available';
          });
        }
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

            // Process the voice command
            final handler = ref.read(voiceCommandHandlerProvider);
            final feedback = await handler.processCommand(recognizedWords);

            if (mounted) {
              setState(() {
                _voiceFeedbackMessage = feedback;
              });

              // Clear feedback after 2.5 seconds
              Future.delayed(const Duration(milliseconds: 2500), () {
                if (mounted) {
                  setState(() {
                    _voiceFeedbackMessage = null;
                  });
                }
              });
            }
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
        setState(() {
          _voiceListening = false;
          _voiceFeedbackMessage = 'Failed to start voice recognition';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(wledStateProvider);
    final ip = ref.watch(selectedDeviceIpProvider);
    final profileAsync = ref.watch(currentUserProfileProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);

    // Debug: Log connection state
    debugPrint('📊 Dashboard build: ip=$ip, connected=${state.connected}, isOn=${state.isOn}, remote=$isRemoteMode');
    final userName = profileAsync.maybeWhen(data: (u) => u?.displayName ?? 'User', orElse: () => 'User');

    // Only update hero image once profile has actually loaded to avoid flashing stock image
    final profileLoaded = profileAsync.hasValue;
    final houseImageUrl = profileAsync.maybeWhen(data: (u) => u?.housePhotoUrl, orElse: () => null);
    // Get roofline mask version to detect when mask is updated
    final rooflineMaskVersion = profileAsync.maybeWhen(
      data: (u) => u?.rooflineMask?.toString(),
      orElse: () => null,
    );
    // Ensure hero uses the latest image and compute aspect ratio once resolved
    // Pass null while loading to prevent stock image flash
    if (profileLoaded) {
      _updateHeroImage(houseImageUrl, rooflineMaskVersion: rooflineMaskVersion);
    }

    return Scaffold(
      appBar: GlassAppBar(
        title: Text('Hello, $userName'),
        actions: [
          // Enhanced connection status indicator
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: ConnectionStatusIndicator(showLabel: true, compact: false),
          ),
          // Controller selector dropdown
          _buildControllerSelector(context, ref, state),
          IconButton(
            icon: const Icon(Icons.settings_suggest_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          )
        ],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 0, 0, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Section A: Image hero framed, now hosting header + controls overlays
            _buildHeroSection(context, ref, state, profileAsync),
            // Expandable Pattern Adjustment Panel
            _buildAdjustmentPanel(context, ref, state),
            const SizedBox(height: 12),
            // Section B: Design Studio & Neighborhood Sync buttons side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  Expanded(
                    child: GlassActionButton(
                      icon: Icons.palette,
                      label: 'Design Studio',
                      onTap: () => context.push(AppRoutes.designStudio),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: GlassActionButton(
                      icon: Icons.groups_outlined,
                      label: 'Neighborhood Sync',
                      onTap: () => context.push(AppRoutes.neighborhoodSync),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Smart Suggestions Section
            _buildSmartSuggestions(context, ref),
            const SizedBox(height: 16),
            // Favorites Section
            _buildFavoritesSection(context, ref),
            const SizedBox(height: 16),
            // Section D: My Schedule
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('My Schedule'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, letterSpacing: 1.1)),
                const SizedBox(height: 10),
                const MiniScheduleList(height: 300),
              ]),
            ),
          ]),
        ),
        // Voice control FAB - giant microphone button with glow animation
        Positioned(
          right: 20,
          bottom: 120, // Position above the bottom nav bar
          child: VoiceControlFab(
            onTap: _toggleVoice,
            isListening: _voiceListening,
          ),
        ),
        // Voice feedback overlay - shows confirmation messages
        if (_voiceFeedbackMessage != null)
          Positioned(
            left: 20,
            right: 20,
            bottom: 220, // Position above the voice FAB
            child: Center(
              child: VoiceCommandFeedback(
                message: _voiceFeedbackMessage!,
                onDismiss: () {
                  setState(() {
                    _voiceFeedbackMessage = null;
                  });
                },
              ),
            ),
          ),
      ]),
    );
  }

  Widget _buildControllerSelector(BuildContext context, WidgetRef ref, WledStateModel state) {
    final controllers = ref.watch(controllersStreamProvider).maybeWhen(
      data: (list) => list,
      orElse: () => <ControllerInfo>[],
    );
    final selectedIp = ref.watch(selectedDeviceIpProvider);

    // Find the currently selected controller
    ControllerInfo? selectedController;
    if (selectedIp != null && controllers.isNotEmpty) {
      selectedController = controllers.cast<ControllerInfo?>().firstWhere(
        (c) => c?.ip == selectedIp,
        orElse: () => null,
      );
    }

    // If no controllers or nothing selected, show nothing
    if (controllers.isEmpty) return const SizedBox.shrink();

    // Display name for current selection
    final displayName = selectedController?.name ??
                       selectedController?.ip ??
                       (selectedIp ?? 'Select Controller');

    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: PopupMenuButton<String>(
        tooltip: 'Select Controller',
        offset: const Offset(0, 40),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        color: NexGenPalette.gunmetal90,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: NexGenPalette.gunmetal90.withValues(alpha: 0.6),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: NexGenPalette.line.withValues(alpha: 0.5)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.lightbulb_outline,
                size: 14,
                color: state.connected ? NexGenPalette.cyan : Colors.grey,
              ),
              const SizedBox(width: 6),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Text(
                  displayName,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: state.connected ? Colors.white : Colors.grey,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (controllers.length > 1) ...[
                const SizedBox(width: 4),
                Icon(Icons.arrow_drop_down, size: 16, color: Colors.white70),
              ],
            ],
          ),
        ),
        itemBuilder: (context) => controllers.map((controller) {
          final isSelected = controller.ip == selectedIp;
          final name = controller.name ?? controller.ip;
          return PopupMenuItem<String>(
            value: controller.ip,
            child: Row(
              children: [
                Icon(
                  isSelected ? Icons.check_circle : Icons.lightbulb_outline,
                  size: 18,
                  color: isSelected ? NexGenPalette.cyan : Colors.white54,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        name,
                        style: TextStyle(
                          color: isSelected ? NexGenPalette.cyan : Colors.white,
                          fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                      if (controller.name != null)
                        Text(
                          controller.ip,
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.white54,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
        onSelected: (newIp) {
          ref.read(selectedDeviceIpProvider.notifier).state = newIp;
        },
      ),
    );
  }

  Widget _buildHeroSection(BuildContext context, WidgetRef ref, WledStateModel state, AsyncValue profileAsync) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 10, offset: Offset(0, 4))],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: SizedBox(
          height: 275,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: NexGenPalette.matteBlack),
            // Show image only when we have a provider (either user's image or stock after profile loads)
            if (_heroImageProvider != null)
              Image(image: _heroImageProvider!, fit: BoxFit.cover, alignment: const Alignment(0, 0.3))
            else if (!profileAsync.isLoading)
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: const Alignment(0, 0.3)),
            // AR Roofline overlay - shows animated LED effects on the house
            if (state.isOn && state.connected)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // Calculate the target aspect ratio for proper roofline positioning
                    final targetAspectRatio = constraints.maxWidth / constraints.maxHeight;
                    return AnimatedRooflineOverlay(
                      previewColors: state.displayColors,
                      previewEffectId: state.effectId,
                      previewSpeed: state.speed,
                      brightness: state.brightness,
                      forceOn: state.isOn,
                      // Pass BoxFit.cover parameters for correct roofline positioning
                      targetAspectRatio: targetAspectRatio,
                      imageAlignment: const Offset(0, 0.3), // Matches hero image alignment
                      useBoxFitCover: true,
                    );
                  },
                ),
              ),
            // Gradient overlay for legibility
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.55), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Top overlay: Power button
            _buildPowerButton(context, ref, state),
            // Add Photo button (shown when no custom house image)
            _buildAddPhotoButton(context, ref),
            // Bottom overlay: Glass control bar (pattern + brightness)
            _buildControlBar(context, ref, state),
          ]),
        ),
      ),
    );
  }

  Widget _buildPowerButton(BuildContext context, WidgetRef ref, WledStateModel state) {
    return Positioned(
      top: 16,
      right: 16,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
          child: Container(
            decoration: BoxDecoration(color: NexGenPalette.gunmetal90, borderRadius: BorderRadius.circular(20), border: Border.all(color: NexGenPalette.line)),
            child: Consumer(builder: (context, ref, _) {
              // Use wledStateProvider directly for immediate UI feedback
              final wledState = ref.watch(wledStateProvider);
              final ips = ref.watch(activeAreaControllerIpsProvider);
              // Use the local state directly - it updates immediately on toggle
              final bool isOn = wledState.isOn;
              return IconButton(
                icon: Icon(isOn ? Icons.power_settings_new : Icons.power_settings_new_outlined, color: isOn ? NexGenPalette.cyan : Colors.white),
                onPressed: wledState.connected
                    ? () async {
                        // Check for active neighborhood sync before changing lights
                        final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
                        if (!shouldProceed) return;

                        try {
                          final currentState = ref.read(wledStateProvider);
                          final newValue = !currentState.isOn;
                          debugPrint('🔌 Power toggle: currentOn=${currentState.isOn}, newValue=$newValue');

                          // Always use the notifier - it updates local state immediately
                          await ref.read(wledStateProvider.notifier).togglePower(newValue);

                          // If there are multiple IPs, also send to those
                          final currentIps = ref.read(activeAreaControllerIpsProvider);
                          if (currentIps.isNotEmpty) {
                            await Future.wait(currentIps.map((ip) async {
                              try {
                                final svc = WledService('http://'+ip);
                                return await svc.setState(on: newValue);
                              } catch (e) {
                                debugPrint('Area toggle failed for '+ip+': '+e.toString());
                                return false;
                              }
                            }));
                          }
                        } catch (e) {
                          debugPrint('Area toggle error: $e');
                        }
                      }
                    : null,
              );
            }),
          ),
        ),
      ),
    );
  }

  Widget _buildAddPhotoButton(BuildContext context, WidgetRef ref) {
    return Consumer(builder: (context, ref, _) {
      final hasCustomImage = ref.watch(hasCustomHouseImageProvider);
      if (hasCustomImage) return const SizedBox.shrink();
      return Positioned(
        top: 16,
        left: 16,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => context.push(AppRoutes.profileEdit),
            borderRadius: BorderRadius.circular(10),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: NexGenPalette.cyan.withValues(alpha: 0.9),
                borderRadius: BorderRadius.circular(10),
                boxShadow: [
                  BoxShadow(
                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                    blurRadius: 8,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.add_a_photo, size: 16, color: Colors.black),
                  const SizedBox(width: 6),
                  Text(
                    'Add Your Home',
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: Colors.black,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    });
  }

  Widget _buildControlBar(BuildContext context, WidgetRef ref, WledStateModel state) {
    return Positioned(
      left: 0,
      right: 0,
      bottom: 0,
      child: ClipRRect(
        borderRadius: const BorderRadius.only(topLeft: Radius.circular(20), topRight: Radius.circular(20)),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: NexGenPalette.gunmetal90, border: Border(top: BorderSide(color: NexGenPalette.line))),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Main control row
                Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                  const Icon(Icons.lightbulb, color: NexGenPalette.cyan, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Consumer(builder: (context, ref, _) {
                      // Use activePresetLabelProvider for immediate feedback
                      final state = ref.watch(wledStateProvider);
                      final activePreset = ref.watch(activePresetLabelProvider);
                      String label;
                      if (!state.connected) {
                        label = 'System Offline';
                      } else if (activePreset != null) {
                        // User selected a preset - show its name
                        label = activePreset;
                      } else if (state.supportsRgbw && state.warmWhite > 0) {
                        label = 'Warm White';
                      } else {
                        // Show the current effect name from device state
                        label = state.effectName;
                      }
                      return Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700));
                    }),
                  ),
                  const SizedBox(width: 12),
                  // Brightness label + slider grouped tightly
                  Row(mainAxisSize: MainAxisSize.min, children: [
                    Text('Brightness', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: Colors.white)),
                    const SizedBox(width: 8),
                    SizedBox(
                      width: 100,
                      child: Consumer(builder: (context, ref, _) {
                        final state = ref.watch(wledStateProvider);
                        final notifier = ref.read(wledStateProvider.notifier);
                        return SliderTheme(
                          data: Theme.of(context).sliderTheme.copyWith(trackHeight: 4),
                          child: Slider(
                            value: state.brightness.toDouble(),
                            min: 0,
                            max: 255,
                            onChangeStart: state.connected ? (v) async {
                              // Check sync warning on first touch
                              final canProceed = await _checkSyncWarning();
                              if (!canProceed && mounted) {
                                // Reset slider to current value by forcing rebuild
                                setState(() {});
                              }
                            } : null,
                            onChanged: state.connected ? (v) => notifier.setBrightness(v.round()) : null,
                            activeColor: NexGenPalette.cyan,
                            inactiveColor: Colors.white.withValues(alpha: 0.2),
                          ),
                        );
                      }),
                    ),
                  ]),
                  const SizedBox(width: 4),
                  // Expand/collapse button for adjustment panel
                  InkWell(
                    onTap: () => setState(() => _adjustmentPanelExpanded = !_adjustmentPanelExpanded),
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: _adjustmentPanelExpanded ? NexGenPalette.cyan.withValues(alpha: 0.2) : Colors.transparent,
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _adjustmentPanelExpanded ? NexGenPalette.cyan : NexGenPalette.line),
                      ),
                      child: Icon(
                        _adjustmentPanelExpanded ? Icons.tune : Icons.tune_outlined,
                        color: _adjustmentPanelExpanded ? NexGenPalette.cyan : Colors.white,
                        size: 20,
                      ),
                    ),
                  ),
                ]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildAdjustmentPanel(BuildContext context, WidgetRef ref, WledStateModel state) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: _adjustmentPanelExpanded
          ? Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: NexGenPalette.gunmetal90,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NexGenPalette.line),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.tune, color: NexGenPalette.cyan, size: 18),
                      const SizedBox(width: 8),
                      Text('Adjust Pattern', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                      const Spacer(),
                      InkWell(
                        onTap: () => setState(() => _adjustmentPanelExpanded = false),
                        child: const Icon(Icons.close, color: Colors.white54, size: 20),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Consumer(builder: (context, ref, _) {
                    final state = ref.watch(wledStateProvider);
                    // Extract full color sequence from device state
                    List<List<int>>? colors;
                    if (state.connected) {
                      final displayColors = state.displayColors;
                      colors = displayColors.map((c) => [
                        (c.r * 255.0).round().clamp(0, 255),
                        (c.g * 255.0).round().clamp(0, 255),
                        (c.b * 255.0).round().clamp(0, 255),
                      ]).toList();
                    }
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        PatternAdjustmentPanel(
                          initialSpeed: state.speed,
                          initialIntensity: state.intensity,
                          initialReverse: false,
                          initialEffectId: state.effectId,
                          effectName: state.effectName,
                          initialColors: colors,
                          showColors: true,
                          showPixelLayout: false,
                          onCustomized: () {
                            // When colors are customized, clear Lumina metadata and change to "Custom"
                            ref.read(wledStateProvider.notifier).clearLuminaPatternMetadata();
                            ref.read(activePresetLabelProvider.notifier).state = 'Custom';
                          },
                        ),
                        const SizedBox(height: 16),
                        // Save As button
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton.icon(
                            onPressed: () => _showSavePatternDialog(context, ref, state),
                            icon: const Icon(Icons.save_alt_rounded),
                            label: const Text('Save As Custom Pattern'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: NexGenPalette.cyan,
                              side: BorderSide(color: NexGenPalette.cyan.withValues(alpha: 0.5)),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                            ),
                          ),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            )
          : const SizedBox.shrink(),
    );
  }

  Widget _buildSmartSuggestions(BuildContext context, WidgetRef ref) {
    return SmartSuggestionsList(
      maxSuggestions: 3,
      onSuggestionAction: (suggestion) async {
        // Handle suggestion actions based on type
        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) return;

        try {
          switch (suggestion.type.name) {
            case 'applyPattern':
              final patternName = suggestion.actionData['pattern_name'] as String?;
              if (patternName != null) {
                final library = ref.read(publicPatternLibraryProvider);
                final pattern = library.all.firstWhere(
                  (p) => p.name.toLowerCase() == patternName.toLowerCase(),
                  orElse: () => library.all.first,
                );
                await repo.applyJson(pattern.toWledPayload());
                ref.trackPatternUsage(pattern: pattern, source: 'suggestion');

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Applied: $patternName')),
                  );
                }
              }
              break;
            case 'createSchedule':
              // Navigate to schedule tab (tab index 1 in bottom nav)
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Create your schedule on the Schedule tab')),
                );
              }
              break;
            default:
              break;
          }
        } catch (e) {
          debugPrint('Suggestion action failed: $e');
        }
      },
    );
  }

  Widget _buildFavoritesSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('My Favorites'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, letterSpacing: 1.1)),
            const SizedBox(height: 10),
          ]),
        ),
        FavoritesGrid(
          onPatternTap: (favorite) async {
            // Wrap entire callback in try-catch to prevent crashes
            try {
              if (!mounted) return;

              final repo = ref.read(wledRepositoryProvider);
              if (repo == null) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('No controller connected')),
                  );
                }
                return;
              }

              debugPrint('Applying favorite: ${favorite.patternName}');
              debugPrint('Pattern data: ${favorite.patternData}');

              final payload = favorite.patternData;
              final success = await repo.applyJson(payload);

              if (!mounted) return;

              if (success) {
                try {
                  ref.read(activePresetLabelProvider.notifier).state = favorite.patternName;
                } catch (_) {}

                try {
                  ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id);
                } catch (_) {}

                try {
                  if (mounted) {
                    ref.trackWledPayload(
                      payload: payload,
                      patternName: favorite.patternName,
                      source: 'favorite',
                    );
                  }
                } catch (_) {}

                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('Applied: ${favorite.patternName}'),
                      backgroundColor: Colors.green.shade700,
                    ),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Failed to apply pattern'),
                      backgroundColor: Colors.orange,
                    ),
                  );
                }
              }
            } catch (e) {
              debugPrint('Apply favorite failed: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text('Error applying pattern'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          },
        ),
      ],
    );
  }

  /// Show dialog to save current pattern configuration as a custom pattern
  Future<void> _showSavePatternDialog(BuildContext context, WidgetRef ref, WledStateModel state) async {
    final nameController = TextEditingController();

    final patternName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: NexGenPalette.gunmetal90,
        title: const Text('Save Custom Pattern'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Save the current settings as a new custom pattern that you can apply anytime.',
              style: TextStyle(color: Colors.white70, fontSize: 14),
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Pattern Name',
                hintText: 'e.g., My Evening Glow',
                filled: true,
                fillColor: Colors.black26,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: NexGenPalette.cyan),
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () {
              final name = nameController.text.trim();
              if (name.isNotEmpty) {
                Navigator.pop(ctx, name);
              }
            },
            style: FilledButton.styleFrom(
              backgroundColor: NexGenPalette.cyan,
              foregroundColor: Colors.black,
            ),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (patternName == null || patternName.isEmpty) return;

    // Build the WLED payload from current state
    final c = state.color;
    final payload = {
      'on': true,
      'bri': state.brightness,
      'seg': [
        {
          'fx': state.effectId,
          'sx': state.speed,
          'ix': state.intensity,
          'pal': 0,  // Use direct colors, no palette
          'col': [[
            (c.r * 255.0).round().clamp(0, 255),
            (c.g * 255.0).round().clamp(0, 255),
            (c.b * 255.0).round().clamp(0, 255),
            state.warmWhite,
          ]],
        }
      ],
    };

    // Save to favorites
    try {
      // Generate a unique ID for this custom pattern
      final patternId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      await ref.read(favoritesNotifierProvider.notifier).addFavorite(
        patternId: patternId,
        patternName: patternName,
        patternData: payload,
        autoAdded: false,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Pattern "$patternName" saved to favorites'),
            backgroundColor: Colors.green.shade700,
          ),
        );
        // Close the adjustment panel
        setState(() => _adjustmentPanelExpanded = false);
      }
    } catch (e) {
      debugPrint('Failed to save pattern: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to save pattern: $e'),
            backgroundColor: Colors.red.shade700,
          ),
        );
      }
    }
  }
}
