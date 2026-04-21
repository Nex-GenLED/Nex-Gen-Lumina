import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:nexgen_command/features/ai/lumina_brain.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/usage_tracking_extension.dart';
import 'package:nexgen_command/features/wled/zone_providers.dart';
import 'package:nexgen_command/features/wled/wled_payload_utils.dart';
import 'package:nexgen_command/features/dashboard/widgets/channel_selector_bar.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/design/design_providers.dart';
import 'package:nexgen_command/features/design/roofline_config_providers.dart';
import 'package:nexgen_command/features/installer/media_access_providers.dart';
import 'package:nexgen_command/features/wled/display_pattern_providers.dart';
import 'package:nexgen_command/features/wled/save_custom_pattern_dialog.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/calendar_providers.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/smart_suggestions_list.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart' hide FavoritePattern;
import 'package:nexgen_command/features/autopilot/learning_providers.dart' show favoritePatternsProvider;
import 'package:nexgen_command/models/usage_analytics_models.dart' show FavoritePattern;

/// Extract colors and effect parameters from a WLED JSON payload so the
/// local preview can be updated immediately without waiting for the next poll.
({List<Color> colors, int effectId, int speed, int intensity, int colorGroupSize, int spacing}) _extractPreviewFromPayload(
    Map<String, dynamic> payload) {
  var effectId = 0;
  var speed = 128;
  var intensity = 128;
  var colorGroupSize = 1;
  var spacing = 0;
  final colors = <Color>[];

  try {
    final seg = payload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map) {
        effectId = (first['fx'] as int?) ?? 0;
        speed = (first['sx'] as int?) ?? 128;
        intensity = (first['ix'] as int?) ?? 128;
        colorGroupSize = (first['grp'] as int?) ?? 1;
        spacing = (first['spc'] as int?) ?? 0;
        final cols = first['col'];
        if (cols is List) {
          for (final col in cols) {
            if (col is List && col.length >= 3) {
              colors.add(Color.fromARGB(
                255,
                (col[0] as num).toInt().clamp(0, 255),
                (col[1] as num).toInt().clamp(0, 255),
                (col[2] as num).toInt().clamp(0, 255),
              ));
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint('Error in _extractPreviewFromPayload: $e');
  }

  return (
    colors: colors.isNotEmpty ? colors : [Colors.white],
    effectId: effectId,
    speed: speed,
    intensity: intensity,
    colorGroupSize: colorGroupSize,
    spacing: spacing,
  );
}

/// Main dashboard page for WLED control
class WledDashboardPage extends ConsumerStatefulWidget {
  const WledDashboardPage({super.key});

  @override
  ConsumerState<WledDashboardPage> createState() => _WledDashboardPageState();
}

class _WledDashboardPageState extends ConsumerState<WledDashboardPage> {
  bool _checkedFirstRun = false;
  bool _pushedSetup = false;
  ImageProvider? _heroImageProvider;
  String? _heroImageId;
  bool _adjustmentPanelExpanded = false;
  Timer? _skyRefreshTimer;
  final TextEditingController _luminaCtrl = TextEditingController();
  bool _luminaLoading = false;
  bool _luminaListening = false;
  late final stt.SpeechToText _luminaSpeech;

  _SkyTheme get _currentSkyTheme => _getSkyTheme(DateTime.now());

  Future<void> _showSaveCustomDialog(BuildContext context, WidgetRef ref) async {
    final name = await showDialog<String>(
      context: context,
      builder: (_) => const SaveCustomPatternDialog(),
    );
    if (name == null || name.isEmpty || !mounted) return;

    final designId = await ref.read(saveCurrentAsDesignProvider)(name);
    if (designId != null) {
      ref.read(activePresetLabelProvider.notifier).state = name;
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Saved "$name" to My Designs')),
        );
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _luminaSpeech = stt.SpeechToText();
    _skyRefreshTimer = Timer.periodic(
      const Duration(minutes: 1),
      (_) => setState(() {}),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkControllersAndMaybeLaunchWizard());
  }

  @override
  void dispose() {
    _luminaCtrl.dispose();
    _luminaSpeech.stop();
    _skyRefreshTimer?.cancel();
    super.dispose();
  }

  Future<bool> _checkSyncWarning() async {
    // Auto-pause sync silently — user actions always take priority.
    // The WledNotifier._postUpdate also handles this, but this catches
    // dashboard-specific actions that may not route through _postUpdate.
    return SyncWarningDialog.checkAndProceed(context, ref);
  }

  Future<void> _checkControllersAndMaybeLaunchWizard() async {
    if (_checkedFirstRun || _pushedSetup) return;
    _checkedFirstRun = true;
    try {
      final current = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
      if (!current.startsWith(AppRoutes.dashboard)) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      // Reviewer account uses DemoWledRepository (see wled_providers.dart);
      // its users/{uid}/controllers subcollection is intentionally empty
      // and must NOT trigger the first-run wifi-connect flow.
      if (ReviewerSeedService.isReviewer(user)) return;

      final col = FirebaseFirestore.instance.collection('users').doc(user.uid).collection('controllers');
      final snap = await col.limit(1).get();
      if (snap.docs.isEmpty && mounted) {
        _pushedSetup = true;
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
        stream.removeListener(listener);
      }, onError: (error, stack) {
        debugPrint('Hero image resolve failed: $error');
      });
      stream.addListener(listener);
    } catch (e) {
      debugPrint('Error resolving hero aspect: $e');
    }
  }

  Widget _buildViewAsBanner(BuildContext context, WidgetRef ref, String customerName) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.cyan.withValues(alpha: 0.9),
            NexGenPalette.blue.withValues(alpha: 0.9),
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: NexGenPalette.cyan.withValues(alpha: 0.3),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.visibility, color: Colors.white, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Viewing customer system: $customerName',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                ref.read(viewAsControllerProvider).exitViewAsMode();
              },
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.close, size: 16),
              label: const Text('Exit', style: TextStyle(fontSize: 12)),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () => context.push(AppRoutes.mediaDashboard),
              style: TextButton.styleFrom(
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                backgroundColor: Colors.white.withValues(alpha: 0.2),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
              ),
              icon: const Icon(Icons.search, size: 16),
              label: const Text('Switch', style: TextStyle(fontSize: 12)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Activate one-shot legacy roofline migration (runs silently in background).
    ref.watch(rooflineLegacyMigrationProvider);

    final state = ref.watch(wledStateProvider);
    ref.watch(selectedDeviceIpProvider);
    final profileAsync = ref.watch(activeUserProfileProvider);
    ref.watch(isRemoteModeProvider);
    final isViewingAsCustomer = ref.watch(isViewingAsCustomerProvider);

    final userName = profileAsync.maybeWhen(data: (u) => u?.displayName ?? 'User', orElse: () => 'User');

    final profileLoaded = profileAsync.hasValue;
    final houseImageUrl = profileAsync.maybeWhen(data: (u) => u?.housePhotoUrl, orElse: () => null);
    final rooflineMaskVersion = profileAsync.maybeWhen(
      data: (u) => u?.rooflineMask?.toString(),
      orElse: () => null,
    );
    if (profileLoaded) {
      _updateHeroImage(houseImageUrl, rooflineMaskVersion: rooflineMaskVersion);
    }

    return Scaffold(
      appBar: GlassAppBar(
        title: Text(
          isViewingAsCustomer ? 'Viewing: $userName' : 'Hello, $userName',
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          _buildControllerSelector(context, ref, state),
          IconButton(
            icon: const Icon(Icons.settings_suggest_outlined),
            tooltip: 'Settings',
            onPressed: () => context.go(AppRoutes.settings),
          ),
        ],
      ),
      body: Stack(children: [
        if (isViewingAsCustomer)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _buildViewAsBanner(context, ref, userName),
          ),
        SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(0, isViewingAsCustomer ? 56 : 0, 0, navBarTotalHeight(context)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildHeroSection(context, ref, state, profileAsync),
            _buildLuminaBar(context, ref),
            _buildAdjustmentPanel(context, ref, state),
            const SizedBox(height: 12),
            // Design Studio + Neighborhood Sync — side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FeatureButton(icon: Icons.brush_outlined, label: 'Design Studio', onTap: () => context.push(AppRoutes.designStudio)),
                  const SizedBox(width: 12),
                  _FeatureButton(icon: Icons.groups_rounded, label: 'Neighborhood Sync', onTap: () => context.push(AppRoutes.neighborhoodSync)),
                ],
              ),
            ),
            const SizedBox(height: 10),
            // Game Day + Audio Mode — side by side
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  _FeatureButton(icon: Icons.stadium_rounded, label: 'Game Day', onTap: () => context.push(AppRoutes.gameDay)),
                  const SizedBox(width: 12),
                  _FeatureButton(icon: Icons.graphic_eq_rounded, label: 'Audio Mode', onTap: () => context.push(AppRoutes.audioReactive)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSmartSuggestions(context, ref),
            const SizedBox(height: 16),
            _buildFavoritesSection(context, ref),
            const SizedBox(height: 16),
            _buildTonightCard(context, ref),
          ]),
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

    ControllerInfo? selectedController;
    if (selectedIp != null && controllers.isNotEmpty) {
      selectedController = controllers.cast<ControllerInfo?>().firstWhere(
        (c) => c?.ip == selectedIp,
        orElse: () => null,
      );
    }

    if (controllers.isEmpty) return const SizedBox.shrink();

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
              Builder(builder: (_) {
                final isRemote = ref.watch(isRemoteModeProvider);
                final bridgeOk = ref.watch(bridgeReachableProvider) == true;
                // Three states:
                //   local + connected        → cyan
                //   remote + bridge reachable → teal (bridge active)
                //   anything else             → red (offline)
                final Color dotColor;
                if (state.connected) {
                  dotColor = isRemote
                      ? const Color(0xFF26A69A) // teal — connected via bridge
                      : NexGenPalette.cyan;     // cyan — local
                } else if (isRemote && bridgeOk) {
                  dotColor = const Color(0xFF26A69A); // teal — bridge confirmed
                } else {
                  dotColor = Colors.red.withValues(alpha: 0.8);
                }
                return Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: dotColor),
                );
              }),
              const SizedBox(width: 5),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 120),
                child: Builder(builder: (_) {
                  final isRemote = ref.watch(isRemoteModeProvider);
                  final bridgeOk = ref.watch(bridgeReachableProvider) == true;
                  final String label;
                  final Color textColor;
                  if (state.connected) {
                    label = isRemote ? '$displayName (bridge)' : displayName;
                    textColor = Colors.white;
                  } else if (isRemote && bridgeOk) {
                    label = '$displayName (bridge)';
                    textColor = Colors.white70;
                  } else {
                    label = displayName;
                    textColor = Colors.grey;
                  }
                  return Text(
                    label,
                    style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: textColor,
                    ),
                    overflow: TextOverflow.ellipsis,
                  );
                }),
              ),
              if (controllers.length > 1) ...[
                const SizedBox(width: 4),
                const Icon(Icons.arrow_drop_down, size: 16, color: Colors.white70),
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
                          style: const TextStyle(fontSize: 11, color: Colors.white54),
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

  void _toggleLuminaVoice() {
    if (_luminaListening) {
      _luminaSpeech.stop();
      setState(() => _luminaListening = false);
      return;
    }
    _luminaSpeech.initialize().then((available) {
      if (!available || !mounted) return;
      setState(() => _luminaListening = true);
      _luminaSpeech.listen(
        onResult: (result) {
          setState(() {
            _luminaCtrl.text = result.recognizedWords;
            if (result.finalResult) _luminaListening = false;
          });
        },
        listenMode: stt.ListenMode.confirmation,
        pauseFor: const Duration(seconds: 2),
        partialResults: true,
      );
    });
  }

  Future<void> _submitLuminaCommand() async {
    final text = _luminaCtrl.text.trim();
    if (text.isEmpty || _luminaLoading) return;
    setState(() => _luminaLoading = true);
    try {
      final result = await LuminaBrain.chat(ref, text);
      if (mounted && result.isNotEmpty) {
        // If the result looks like a pattern name (short, no markdown), set as active preset
        if (result.length < 60 && !result.contains('\n') && !result.startsWith('{')) {
          ref.read(activePresetLabelProvider.notifier).state = result;
        }
      }
    } catch (e) {
      debugPrint('Lumina command error: $e');
    } finally {
      if (mounted) {
        setState(() => _luminaLoading = false);
        _luminaCtrl.clear();
      }
    }
  }

  Widget _buildLuminaBar(BuildContext context, WidgetRef ref) {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            NexGenPalette.cyan.withValues(alpha: 0.08),
            NexGenPalette.violet.withValues(alpha: 0.06),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3), width: 1),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [NexGenPalette.violet, NexGenPalette.cyan]),
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.4), blurRadius: 8),
              ],
            ),
            child: const Icon(Icons.auto_awesome_rounded, color: Colors.black, size: 14),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _luminaCtrl,
              minLines: 1,
              maxLines: 2,
              style: const TextStyle(color: NexGenPalette.textHigh, fontSize: 14),
              decoration: InputDecoration(
                hintText: LuminaBrain.contextualPlaceholder(),
                hintStyle: const TextStyle(color: NexGenPalette.textMedium, fontSize: 13),
                border: InputBorder.none,
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(vertical: 4),
              ),
              onSubmitted: (_) => _submitLuminaCommand(),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _toggleLuminaVoice,
            child: Container(
              width: 32,
              height: 32,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _luminaListening
                    ? NexGenPalette.cyan.withValues(alpha: 0.2)
                    : Colors.white.withValues(alpha: 0.06),
                border: Border.all(
                  color: _luminaListening ? NexGenPalette.cyan : NexGenPalette.line,
                ),
              ),
              child: Icon(
                _luminaListening ? Icons.mic : Icons.mic_none,
                size: 16,
                color: _luminaListening ? NexGenPalette.cyan : NexGenPalette.violet,
              ),
            ),
          ),
          const SizedBox(width: 6),
          _luminaLoading
              ? const SizedBox(
                  width: 32,
                  height: 32,
                  child: Padding(
                    padding: EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 2, color: NexGenPalette.cyan),
                  ),
                )
              : GestureDetector(
                  onTap: _submitLuminaCommand,
                  child: Container(
                    width: 32,
                    height: 32,
                    decoration: const BoxDecoration(
                      color: NexGenPalette.cyan,
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.arrow_upward_rounded, size: 16, color: Colors.black),
                  ),
                ),
        ],
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
        child: AspectRatio(
          aspectRatio: 994 / 492,
          child: Stack(fit: StackFit.expand, children: [
            Container(color: NexGenPalette.matteBlack),
            if (_heroImageProvider != null)
              Image(image: _heroImageProvider!, fit: BoxFit.cover, alignment: Alignment.center)
            else if (!profileAsync.isLoading)
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: Alignment.center),
            // Sky color overlay — sits above photo, below controls
            Positioned.fill(
              child: _SkyGradientOverlay(skyTheme: _currentSkyTheme),
            ),
            if (state.isOn)
              Positioned.fill(
                child: Consumer(builder: (context, ref, _) {
                  final isFresh = ref.watch(wledStateFreshProvider);
                  return LayoutBuilder(
                    builder: (context, constraints) {
                      final targetAspectRatio = constraints.maxWidth / constraints.maxHeight;
                      return AnimatedOpacity(
                        opacity: isFresh ? 1.0 : 0.5,
                        duration: const Duration(milliseconds: 400),
                        child: AnimatedRooflineOverlay(
                          previewColors: state.displayColors,
                          previewEffectId: state.effectId,
                          previewSpeed: state.speed,
                          brightness: state.brightness,
                          forceOn: state.isOn,
                          targetAspectRatio: targetAspectRatio,
                          imageAlignment: Offset.zero,
                          useBoxFitCover: true,
                          colorGroupSize: state.colorGroupSize,
                          spacing: state.spacing,
                        ),
                      );
                    },
                  );
                }),
              ),
            // Gradient overlay for legibility — anchored above the lifted
            // Now Playing bar so the newly exposed bottom strip of photo
            // isn't darkened.
            Positioned(
              left: 0,
              right: 0,
              bottom: 24,
              height: 130,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.bottomCenter,
                    end: Alignment.topCenter,
                    colors: [Colors.black.withValues(alpha: 0.45), Colors.transparent],
                  ),
                ),
              ),
            ),
            // Ambient LED glow at bottom edge reflecting active WLED color
            if (state.isOn)
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: _AmbientLedGlow(
                  color: state.displayColors.isNotEmpty
                      ? state.displayColors.first
                      : const Color(0xFF00D4FF),
                ),
              ),
            // "Last Known State" indicator when stale data is showing
            Consumer(builder: (context, ref, _) {
              final isFresh = ref.watch(wledStateFreshProvider);
              final isConnected = state.connected;
              if (isFresh || !state.isOn) return const SizedBox.shrink();
              return Positioned(
                top: 12,
                left: 16,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.black54,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    isConnected ? 'Syncing...' : 'Last Known State',
                    style: const TextStyle(color: Colors.grey, fontSize: 11, fontWeight: FontWeight.w500),
                  ),
                ),
              );
            }),
            _buildPresetChips(context, ref),
            _buildAddPhotoButton(context, ref),
            // Now Playing bar — owns the full bottom chrome including brightness + tune
            _buildNowPlayingBar(context, ref, state),
          ]),
        ),
      ),
    );
  }

  
  Widget _buildPresetChips(BuildContext context, WidgetRef ref) {
    return Positioned(
      top: 68,
      right: 12,
      child: Consumer(builder: (context, ref, _) {
        final favoritesAsync = ref.watch(favoritePatternsProvider);
        final activePreset = ref.watch(activePresetLabelProvider);
        return favoritesAsync.when(
          data: (favorites) {
            if (favorites.isEmpty) return const SizedBox.shrink();
            final chips = favorites.take(4).toList();
            return Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (int i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(height: 5),
                  _PresetChip(
                    favorite: chips[i],
                    isActive: activePreset == chips[i].patternName,
                    onTap: () => _applyPresetChip(context, ref, chips[i]),
                  ),
                ],
              ],
            );
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      }),
    );
  }

  Future<void> _applyPresetChip(BuildContext context, WidgetRef ref, FavoritePattern favorite) async {
    try {
      final repo = ref.read(wledRepositoryProvider);
      if (repo == null) return;
      var payload = favorite.patternData;
      final channels = ref.read(effectiveChannelIdsProvider);
      if (channels.isNotEmpty) {
        payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
      }
      final success = await repo.applyJson(payload);
      if (!mounted) return;
      if (success) {
        try {
          final preview = _extractPreviewFromPayload(payload);
          ref.read(wledStateProvider.notifier).applyLocalPreview(
            colors: preview.colors,
            effectId: preview.effectId,
            speed: preview.speed,
            intensity: preview.intensity,
            effectName: favorite.patternName,
            colorGroupSize: preview.colorGroupSize,
            spacing: preview.spacing,
          );
        } catch (e) {
          debugPrint('Error in preset chip applyLocalPreview: $e');
        }
        try { ref.read(activePresetLabelProvider.notifier).state = favorite.patternName; } catch (e) {
          debugPrint('Error in preset chip set active label: $e');
        }
        try { ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id); } catch (e) {
          debugPrint('Error in preset chip recordFavoriteUsage: $e');
        }
        try {
          if (mounted) {
            ref.trackWledPayload(payload: payload, patternName: favorite.patternName, source: 'favorite');
          }
        } catch (e) {
          debugPrint('Error in preset chip trackWledPayload: $e');
        }
      }
    } catch (e) {
      debugPrint('Preset chip apply error: $e');
    }
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
            onTap: () => context.go(AppRoutes.profileEdit),
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

  /// Unified Now Playing bar — owns pattern name, brightness slider, tune toggle, and power.
  Widget _buildNowPlayingBar(BuildContext context, WidgetRef ref, WledStateModel state) {
    return Positioned(
      left: 10,
      right: 10,
      bottom: 10,
      child: Consumer(builder: (context, ref, _) {
        final wledState = ref.watch(wledStateProvider);
        final isOn = wledState.isOn;
        final effectName = ref.watch(displayPatternNameProvider);
        final isUnsaved = ref.watch(isUnsavedCustomConfigProvider);

        return ClipRRect(
          borderRadius: BorderRadius.circular(16),
          child: BackdropFilter(
            filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
            child: Container(
              padding: const EdgeInsets.fromLTRB(14, 10, 10, 12),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Colors.transparent,
                    const Color(0xFF050812).withValues(alpha: 0.92),
                  ],
                ),
                border: Border(
                  top: BorderSide(color: NexGenPalette.line.withValues(alpha: 0.4)),
                ),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // ── Row 1: NOW PLAYING label + effect name | tune + power ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      // Left: label + name + channel badge
                      Expanded(
                        child: isOn
                            ? Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    'NOW PLAYING',
                                    style: TextStyle(
                                      color: Colors.white.withValues(alpha: 0.45),
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 1.4,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Row(
                                    children: [
                                      Flexible(
                                        child: GestureDetector(
                                          onTap: isUnsaved ? () => _showSaveCustomDialog(context, ref) : null,
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Flexible(
                                                child: Text(
                                                  effectName,
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(
                                                    color: Colors.white,
                                                    fontSize: 14,
                                                    fontWeight: FontWeight.w700,
                                                  ),
                                                ),
                                              ),
                                              if (isUnsaved) ...[
                                                const SizedBox(width: 4),
                                                Icon(
                                                  Icons.bookmark_add_outlined,
                                                  size: 13,
                                                  color: Colors.white.withValues(alpha: 0.45),
                                                ),
                                              ],
                                            ],
                                          ),
                                        ),
                                      ),
                                      // Channel filter badge
                                      Consumer(builder: (context, ref, _) {
                                        final isFiltered = ref.watch(isChannelFilterActiveProvider);
                                        final segments = ref.watch(zoneSegmentsProvider).valueOrNull ?? [];
                                        final selectedIds = ref.watch(selectedChannelIdsProvider);
                                        if (!isFiltered || segments.length <= 1) return const SizedBox.shrink();
                                        final count = selectedIds?.length ?? segments.length;
                                        return Padding(
                                          padding: const EdgeInsets.only(left: 6),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: NexGenPalette.cyan.withValues(alpha: 0.2),
                                              borderRadius: BorderRadius.circular(5),
                                              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.4)),
                                            ),
                                            child: Text(
                                              '$count/${segments.length} CH',
                                              style: const TextStyle(
                                                fontSize: 9,
                                                fontWeight: FontWeight.w700,
                                                color: NexGenPalette.cyan,
                                              ),
                                            ),
                                          ),
                                        );
                                      }),
                                    ],
                                  ),
                                ],
                              )
                            : Text(
                                'Lights Off',
                                style: TextStyle(
                                  color: Colors.white.withValues(alpha: 0.35),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),

                      // Tune toggle
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () => setState(() => _adjustmentPanelExpanded = !_adjustmentPanelExpanded),
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _adjustmentPanelExpanded
                                ? NexGenPalette.cyan.withValues(alpha: 0.18)
                                : Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: _adjustmentPanelExpanded
                                  ? NexGenPalette.cyan.withValues(alpha: 0.6)
                                  : Colors.white.withValues(alpha: 0.18),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            _adjustmentPanelExpanded ? Icons.tune : Icons.tune_outlined,
                            size: 17,
                            color: _adjustmentPanelExpanded
                                ? NexGenPalette.cyan
                                : Colors.white.withValues(alpha: 0.75),
                          ),
                        ),
                      ),

                      // Power circle
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: wledState.connected
                            ? () async {
                                final shouldProceed = await SyncWarningDialog.checkAndProceed(context, ref);
                                if (!shouldProceed) return;
                                try {
                                  final current = ref.read(wledStateProvider);
                                  await ref.read(wledStateProvider.notifier).togglePower(!current.isOn);
                                  final currentIps = ref.read(activeAreaControllerIpsProvider);
                                  if (currentIps.isNotEmpty) {
                                    await Future.wait(currentIps.map((ip) async {
                                      try {
                                        final svc = WledService('http://$ip');
                                        return await svc.setState(on: !current.isOn);
                                      } catch (_) {
                                        return false;
                                      }
                                    }));
                                  }
                                } catch (e) {
                                  debugPrint('Now Playing power toggle error: $e');
                                }
                              }
                            : null,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white.withValues(alpha: 0.06),
                            border: Border.all(
                              color: isOn
                                  ? Colors.white.withValues(alpha: 0.30)
                                  : Colors.red.withValues(alpha: 0.35),
                              width: 1,
                            ),
                          ),
                          child: Icon(
                            Icons.power_settings_new,
                            size: 17,
                            color: isOn
                                ? Colors.white.withValues(alpha: 0.85)
                                : Colors.red.withValues(alpha: 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),

                  // ── Row 2: Brightness slider ──
                  const SizedBox(height: 6),
                  Consumer(builder: (context, ref, _) {
                    final st = ref.watch(wledStateProvider);
                    return Row(
                      children: [
                        Icon(
                          Icons.brightness_low,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                        Expanded(
                          child: SliderTheme(
                            data: Theme.of(context).sliderTheme.copyWith(
                              trackHeight: 3,
                              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                              overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            ),
                            child: Slider(
                              value: st.brightness.toDouble(),
                              min: 0,
                              max: 255,
                              onChangeStart: st.connected
                                  ? (v) async {
                                      final canProceed = await _checkSyncWarning();
                                      if (!canProceed && mounted) setState(() {});
                                    }
                                  : null,
                              onChanged: st.connected
                                  ? (v) => ref.read(wledStateProvider.notifier).setBrightness(v.round())
                                  : null,
                              activeColor: NexGenPalette.cyan,
                              inactiveColor: Colors.white.withValues(alpha: 0.15),
                            ),
                          ),
                        ),
                        Icon(
                          Icons.brightness_high,
                          size: 13,
                          color: Colors.white.withValues(alpha: 0.35),
                        ),
                      ],
                    );
                  }),
                ],
              ),
            ),
          ),
        );
      }),
    );
  }

  Widget _buildAdjustmentPanel(BuildContext context, WidgetRef ref, WledStateModel state) {
    return AnimatedSize(
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
      child: _adjustmentPanelExpanded
          ? Container(
              margin: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.3), width: 1),
                boxShadow: [
                  BoxShadow(
                    color: NexGenPalette.cyan.withValues(alpha: 0.15),
                    blurRadius: 20,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: [
                          NexGenPalette.gunmetal90.withValues(alpha: 0.85),
                          NexGenPalette.matteBlack.withValues(alpha: 0.9),
                        ],
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Container(
                          height: 3,
                          margin: const EdgeInsets.only(bottom: 12),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              colors: [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.0)],
                            ),
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                gradient: LinearGradient(
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                  colors: [NexGenPalette.cyan, NexGenPalette.cyan.withValues(alpha: 0.6)],
                                ),
                                borderRadius: BorderRadius.circular(10),
                                boxShadow: [
                                  BoxShadow(
                                    color: NexGenPalette.cyan.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: const Icon(Icons.tune, color: Colors.white, size: 18),
                            ),
                            const SizedBox(width: 12),
                            Text('Adjust Pattern', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600, color: Colors.white)),
                            const Spacer(),
                            Material(
                              color: Colors.transparent,
                              child: InkWell(
                                onTap: () => setState(() => _adjustmentPanelExpanded = false),
                                borderRadius: BorderRadius.circular(20),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: Colors.white.withValues(alpha: 0.1),
                                    shape: BoxShape.circle,
                                  ),
                                  child: const Icon(Icons.close, color: Colors.white70, size: 18),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Consumer(builder: (context, ref, _) {
                          final state = ref.watch(wledStateProvider);
                          List<List<int>>? colors;
                          if (state.connected) {
                            final displayColors = state.displayColors;
                            colors = displayColors.map((c) => rgbToRgbw(
                              (c.r * 255.0).round().clamp(0, 255),
                              (c.g * 255.0).round().clamp(0, 255),
                              (c.b * 255.0).round().clamp(0, 255),
                            )).toList();
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
                                  ref.read(wledStateProvider.notifier).clearLuminaPatternMetadata();
                                  ref.read(activePresetLabelProvider.notifier).state = 'Custom';
                                },
                              ),
                              const Divider(height: 24),
                              const Padding(
                                padding: EdgeInsets.only(bottom: 8),
                                child: ChannelSelectorBar(),
                              ),
                              const SizedBox(height: 16),
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
                  ),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }


  Widget _buildSmartSuggestions(BuildContext context, WidgetRef ref) {
    return SmartSuggestionsList(
      maxSuggestions: 3,
      onSuggestionAction: (suggestion) async {
        final repo = ref.read(wledRepositoryProvider);
        if (repo == null) return;
        try {
          switch (suggestion.type.name) {
            case 'applyPattern':
              final patternName = suggestion.actionData['pattern_name'] as String?;
              if (patternName != null) {
                final library = ref.read(publicPatternLibraryProvider);
                if (library.all.isEmpty) return;
                final pattern = library.all.firstWhere(
                  (p) => p.name.toLowerCase() == patternName.toLowerCase(),
                  orElse: () => library.all.first,
                );
                var payload = pattern.toWledPayload();
                final channels = ref.read(effectiveChannelIdsProvider);
                if (channels.isNotEmpty) {
                  payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
                }
                final success = await repo.applyJson(payload);
                if (success) {
                  try {
                    final preview = _extractPreviewFromPayload(payload);
                    ref.read(wledStateProvider.notifier).applyLocalPreview(
                      colors: preview.colors,
                      effectId: preview.effectId,
                      speed: preview.speed,
                      intensity: preview.intensity,
                      effectName: patternName,
                      colorGroupSize: preview.colorGroupSize,
                      spacing: preview.spacing,
                    );
                    ref.read(activePresetLabelProvider.notifier).state = patternName;
                  } catch (e) {
                    debugPrint('Error in AI suggestion applyLocalPreview: $e');
                  }
                }
                ref.trackPatternUsage(pattern: pattern, source: 'suggestion');
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: $patternName')));
                }
              }
              break;
            case 'createSchedule':
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
            try {
              if (!mounted) return;
              final repo = ref.read(wledRepositoryProvider);
              if (repo == null) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('No controller connected')));
                return;
              }
              var payload = favorite.patternData;
              final channels = ref.read(effectiveChannelIdsProvider);
              if (channels.isNotEmpty) {
                payload = applyChannelFilter(payload, channels, ref.read(deviceChannelsProvider));
              }
              final success = await repo.applyJson(payload);
              if (!mounted) return;
              if (success) {
                try {
                  final preview = _extractPreviewFromPayload(payload);
                  ref.read(wledStateProvider.notifier).applyLocalPreview(
                    colors: preview.colors,
                    effectId: preview.effectId,
                    speed: preview.speed,
                    intensity: preview.intensity,
                    effectName: favorite.patternName,
                    colorGroupSize: preview.colorGroupSize,
                    spacing: preview.spacing,
                  );
                } catch (e) {
                  debugPrint('Error in favorite grid applyLocalPreview: $e');
                }
                try { ref.read(activePresetLabelProvider.notifier).state = favorite.patternName; } catch (e) {
                  debugPrint('Error in favorite grid set active label: $e');
                }
                try { ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id); } catch (e) {
                  debugPrint('Error in favorite grid recordFavoriteUsage: $e');
                }
                try {
                  if (mounted) ref.trackWledPayload(payload: payload, patternName: favorite.patternName, source: 'favorite');
                } catch (e) {
                  debugPrint('Error in favorite grid trackWledPayload: $e');
                }
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Applied: ${favorite.patternName}'), backgroundColor: Colors.green.shade700),
                  );
                }
              } else {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Failed to apply pattern'), backgroundColor: Colors.orange),
                  );
                }
              }
            } catch (e) {
              debugPrint('Apply favorite failed: $e');
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: const Text('Error applying pattern'), backgroundColor: Colors.red),
                );
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildTonightCard(BuildContext context, WidgetRef ref) {
    return Consumer(builder: (context, ref, _) {
      final schedules = ref.watch(schedulesProvider);
      final calEntries = ref.watch(calendarScheduleProvider);
      final today = DateTime.now();
      final todayKey = '${today.year}-${today.month.toString().padLeft(2, '0')}-${today.day.toString().padLeft(2, '0')}';
      final calEntry = calEntries[todayKey];
      final wd = today.weekday % 7;
      final recurring = schedules.where((s) {
        if (!s.enabled) return false;
        final dl = s.repeatDays.map((e) => e.toLowerCase()).toSet();
        if (dl.contains('daily')) return true;
        const map = {
          0: {'sun', 'sunday'},
          1: {'mon', 'monday'},
          2: {'tue', 'tues', 'tuesday'},
          3: {'wed', 'wednesday'},
          4: {'thu', 'thurs', 'thursday'},
          5: {'fri', 'friday'},
          6: {'sat', 'saturday'},
        };
        return (map[wd] ?? {}).any(dl.contains);
      }).toList();
      final first = recurring.isNotEmpty ? recurring.first : null;

      final patternName = calEntry?.patternName ??
          (first != null
              ? (first.actionLabel.contains(':') ? first.actionLabel.split(':').last.trim() : first.actionLabel)
              : null);
      final onTime = calEntry?.onTime ?? first?.timeLabel;
      final offTime = calEntry?.offTime ?? first?.offTimeLabel;
      final accentColor = calEntry?.color ?? NexGenPalette.cyan;

      final bool hasSchedule = patternName != null || onTime != null;

      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: GestureDetector(
          onTap: () => context.go(AppRoutes.schedule),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: hasSchedule ? accentColor.withValues(alpha: 0.35) : NexGenPalette.line),
              boxShadow: hasSchedule ? [BoxShadow(color: accentColor.withValues(alpha: 0.12), blurRadius: 12)] : null,
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: hasSchedule ? accentColor.withValues(alpha: 0.15) : Colors.white.withValues(alpha: 0.06),
                    border: Border.all(color: hasSchedule ? accentColor.withValues(alpha: 0.4) : NexGenPalette.line),
                  ),
                  child: Icon(
                    hasSchedule ? Icons.schedule_rounded : Icons.add_alarm_rounded,
                    size: 18,
                    color: hasSchedule ? accentColor : NexGenPalette.textMedium,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TONIGHT',
                        style: TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: Colors.white.withValues(alpha: 0.4),
                          letterSpacing: 1.3,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        hasSchedule
                            ? '${patternName ?? 'Scheduled'}${onTime != null ? ' · $onTime' : ''}${offTime != null ? ' → $offTime' : ''}'
                            : 'No schedule — tap to add one',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: hasSchedule ? NexGenPalette.textHigh : NexGenPalette.textMedium,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right_rounded, size: 18, color: NexGenPalette.textMedium),
              ],
            ),
          ),
        ),
      );
    });
  }

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
              if (name.isNotEmpty) Navigator.pop(ctx, name);
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

    final c = state.color;
    final payload = {
      'on': true,
      'bri': state.brightness,
      'seg': [
        {
          'fx': state.effectId,
          'sx': state.speed,
          'ix': state.intensity,
          'pal': 0,
          'col': [[
            (c.r * 255.0).round().clamp(0, 255),
            (c.g * 255.0).round().clamp(0, 255),
            (c.b * 255.0).round().clamp(0, 255),
            state.warmWhite,
          ]],
        }
      ],
    };

    try {
      final patternId = 'custom_${DateTime.now().millisecondsSinceEpoch}';
      await ref.read(favoritesNotifierProvider.notifier).addFavorite(
        patternId: patternId,
        patternName: patternName,
        patternData: payload,
        autoAdded: false,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Pattern "$patternName" saved to favorites'), backgroundColor: Colors.green.shade700),
        );
        setState(() => _adjustmentPanelExpanded = false);
      }
    } catch (e) {
      debugPrint('Failed to save pattern: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to save pattern: $e'), backgroundColor: Colors.red.shade700),
        );
      }
    }
  }

  static _SkyTheme _getSkyTheme(DateTime now) {
    final hour = now.hour;
    final minuteFraction = now.minute / 59.0;

    // Define time slot boundaries and their themes
    final slots = <_SkySlot>[
      _SkySlot(0, [const Color(0xFF000000), const Color(0xFF020818)], 0.22, 'Night'),
      _SkySlot(5, [const Color(0xFF1A0533), const Color(0xFF8B3A62), const Color(0xFFE8855A)], 0.18, 'Dawn'),
      _SkySlot(7, [const Color(0xFF1A6BAD), const Color(0xFF7EC8E3), const Color(0xFFFFD89B)], 0.10, 'Morning'),
      _SkySlot(10, [const Color(0xFF2980B9), const Color(0xFF87CEEB)], 0.00, 'Midday'),
      _SkySlot(15, [const Color(0xFF1A6BAD), const Color(0xFFFFB347)], 0.08, 'Afternoon'),
      _SkySlot(18, [const Color(0xFFFF6B35), const Color(0xFFFF4500), const Color(0xFF8B1A8B)], 0.18, 'Sunset'),
      _SkySlot(20, [const Color(0xFF2C1654), const Color(0xFF0D0D2B)], 0.20, 'Dusk'),
      _SkySlot(22, [const Color(0xFF000000), const Color(0xFF020818)], 0.22, 'Night'),
    ];

    // Find current and next slot
    int currentIdx = 0;
    for (int i = slots.length - 1; i >= 0; i--) {
      if (hour >= slots[i].startHour) {
        currentIdx = i;
        break;
      }
    }

    final current = slots[currentIdx];
    final next = currentIdx + 1 < slots.length ? slots[currentIdx + 1] : slots[0];

    // Calculate how far through the current slot we are
    final slotDurationHours = (next.startHour > current.startHour)
        ? next.startHour - current.startHour
        : (24 - current.startHour + next.startHour);
    final hoursIntoSlot = (hour - current.startHour + (hour < current.startHour ? 24 : 0));
    final t = ((hoursIntoSlot + minuteFraction) / slotDurationHours).clamp(0.0, 1.0);

    // Lerp colors
    final maxColors = current.colors.length > next.colors.length
        ? current.colors.length
        : next.colors.length;
    final lerpedColors = List<Color>.generate(maxColors, (i) {
      final c1 = current.colors[i.clamp(0, current.colors.length - 1)];
      final c2 = next.colors[i.clamp(0, next.colors.length - 1)];
      return Color.lerp(c1, c2, t)!;
    });

    final lerpedOpacity = current.opacity + (next.opacity - current.opacity) * t;
    final label = t < 0.5 ? current.label : next.label;

    return _SkyTheme(
      skyColors: lerpedColors,
      overlayOpacity: lerpedOpacity,
      label: label,
    );
  }
}

/// A single frosted preset chip for the hero overlay.
class _PresetChip extends StatelessWidget {
  final FavoritePattern favorite;
  final bool isActive;
  final VoidCallback onTap;

  const _PresetChip({
    required this.favorite,
    required this.isActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final primaryColor = _extractPrimaryColor();

    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFF080C18).withValues(alpha: 0.60),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                color: isActive
                    ? Colors.white.withValues(alpha: 0.45)
                    : Colors.white.withValues(alpha: 0.12),
                width: 0.5,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor,
                    boxShadow: [
                      BoxShadow(color: primaryColor.withValues(alpha: 0.6), blurRadius: 5),
                    ],
                  ),
                ),
                const SizedBox(width: 7),
                Text(
                  favorite.patternName,
                  style: TextStyle(
                    color: isActive ? Colors.white : Colors.white.withValues(alpha: 0.75),
                    fontSize: 11,
                    fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Color _extractPrimaryColor() {
    try {
      final seg = favorite.patternData['seg'];
      if (seg is List && seg.isNotEmpty) {
        final col = (seg[0] as Map)['col'];
        if (col is List && col.isNotEmpty) {
          final c = col[0];
          if (c is List && c.length >= 3) {
            return Color.fromARGB(
              255,
              (c[0] as num).toInt().clamp(0, 255),
              (c[1] as num).toInt().clamp(0, 255),
              (c[2] as num).toInt().clamp(0, 255),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error in _extractPrimaryColor: $e');
    }
    return NexGenPalette.cyan;
  }
}

/// Flat uniform color wash representing the sky tint for the current
/// time of day. No gradient — a single color with low opacity is applied
/// evenly across the image, so the tint reads as ambient atmosphere
/// rather than a vignette.
///
/// Transitions between time slots use AnimatedContainer's 90-second
/// tween so the sky shift is gradual and imperceptible during use.
class _SkyGradientOverlay extends StatelessWidget {
  final _SkyTheme skyTheme;

  const _SkyGradientOverlay({required this.skyTheme});

  @override
  Widget build(BuildContext context) {
    // Use the dominant (first) sky color at the slot's opacity.
    // If a slot ever has zero colors, fall back to transparent.
    final baseColor = skyTheme.skyColors.isNotEmpty
        ? skyTheme.skyColors.first
        : Colors.transparent;
    final washColor = baseColor.withValues(alpha: skyTheme.overlayOpacity);

    return AnimatedContainer(
      duration: const Duration(seconds: 90),
      curve: Curves.linear,
      color: washColor,
    );
  }
}

/// Pulsing ambient LED glow at the bottom edge of the hero image.
/// Oscillates opacity between 0.4 and 0.7 over 3 seconds using a sine curve.
class _AmbientLedGlow extends StatefulWidget {
  final Color color;

  const _AmbientLedGlow({required this.color});

  @override
  State<_AmbientLedGlow> createState() => _AmbientLedGlowState();
}

class _AmbientLedGlowState extends State<_AmbientLedGlow>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        // Sine curve: oscillate opacity between 0.4 and 0.7
        final t = _controller.value;
        final sine = math.sin(t * math.pi); // 0→1→0 half sine over forward pass
        final opacity = 0.4 + 0.3 * sine;

        return Container(
          height: 18,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Colors.transparent,
                widget.color.withValues(alpha: 0.6 * opacity / 0.7),
                Colors.transparent,
              ],
              stops: const [0.0, 0.5, 1.0],
            ),
            boxShadow: [
              BoxShadow(
                color: widget.color.withValues(alpha: opacity),
                blurRadius: 16,
                spreadRadius: 2,
              ),
            ],
          ),
        );
      },
    );
  }
}

class _SkyTheme {
  final List<Color> skyColors;
  final double overlayOpacity;
  final String label;

  const _SkyTheme({
    required this.skyColors,
    required this.overlayOpacity,
    required this.label,
  });
}

class _SkySlot {
  final int startHour;
  final List<Color> colors;
  final double opacity;
  final String label;

  const _SkySlot(this.startHour, this.colors, this.opacity, this.label);
}

class _FeatureButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _FeatureButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(16),
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90.withValues(alpha: 0.7),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: NexGenPalette.cyan.withValues(alpha: 0.25)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, size: 20, color: NexGenPalette.cyan),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: NexGenPalette.textPrimary,
                      letterSpacing: 0.3,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
