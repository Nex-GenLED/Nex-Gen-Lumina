import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/installer/media_access_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/widgets/mini_schedule_list.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/widgets/sync_warning_dialog.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/widgets/connection_status_indicator.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/smart_suggestions_list.dart';
import 'package:nexgen_command/features/favorites/favorites_providers.dart' hide FavoritePattern;
import 'package:nexgen_command/features/dashboard/widgets/glass_action_button.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart' show favoritePatternsProvider;
import 'package:nexgen_command/models/usage_analytics_models.dart' show FavoritePattern;

/// Extract colors and effect parameters from a WLED JSON payload so the
/// local preview can be updated immediately without waiting for the next poll.
({List<Color> colors, int effectId, int speed, int intensity}) _extractPreviewFromPayload(
    Map<String, dynamic> payload) {
  var effectId = 0;
  var speed = 128;
  var intensity = 128;
  final colors = <Color>[];

  try {
    final seg = payload['seg'];
    if (seg is List && seg.isNotEmpty) {
      final first = seg.first;
      if (first is Map) {
        effectId = (first['fx'] as int?) ?? 0;
        speed = (first['sx'] as int?) ?? 128;
        intensity = (first['ix'] as int?) ?? 128;
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
  } catch (_) {}

  return (
    colors: colors.isNotEmpty ? colors : [Colors.white],
    effectId: effectId,
    speed: speed,
    intensity: intensity,
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
  double? _heroAspectRatio;
  ImageProvider? _heroImageProvider;
  String? _heroImageId;
  bool _adjustmentPanelExpanded = false;
  bool _syncWarningAcknowledged = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _checkControllersAndMaybeLaunchWizard());
  }

  Future<bool> _checkSyncWarning() async {
    if (_syncWarningAcknowledged) return true;
    final syncStatus = ref.read(userSyncStatusProvider);
    if (!syncStatus.isInActiveSync || syncStatus.isPaused) return true;
    final result = await SyncWarningDialog.showIfNeeded(context, ref);
    if (result == null) return true;
    if (result == SyncWarningResult.cancel) return false;
    _syncWarningAcknowledged = true;
    if (result == SyncWarningResult.pauseAndContinue) {
      await ref.read(neighborhoodNotifierProvider.notifier).pauseMySync();
    }
    return true;
  }

  Future<void> _checkControllersAndMaybeLaunchWizard() async {
    if (_checkedFirstRun || _pushedSetup) return;
    _checkedFirstRun = true;
    try {
      final current = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
      if (!current.startsWith(AppRoutes.dashboard)) return;
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;
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
        final w = info.image.width.toDouble();
        final h = info.image.height.toDouble();
        if (w > 0 && h > 0) {
          if (mounted) setState(() => _heroAspectRatio = w / h);
        }
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
    final state = ref.watch(wledStateProvider);
    final ip = ref.watch(selectedDeviceIpProvider);
    final profileAsync = ref.watch(activeUserProfileProvider);
    final isRemoteMode = ref.watch(isRemoteModeProvider);
    final isViewingAsCustomer = ref.watch(isViewingAsCustomerProvider);

    debugPrint('📊 Dashboard build: ip=$ip, connected=${state.connected}, isOn=${state.isOn}, remote=$isRemoteMode');
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
        title: Text(isViewingAsCustomer ? 'Viewing: $userName' : 'Hello, $userName'),
        actions: [
          const Padding(
            padding: EdgeInsets.only(right: 8),
            child: ConnectionStatusIndicator(showLabel: true, compact: false),
          ),
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
          padding: EdgeInsets.fromLTRB(0, isViewingAsCustomer ? 56 : 0, 0, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            _buildHeroSection(context, ref, state, profileAsync),
            _buildAdjustmentPanel(context, ref, state),
            const SizedBox(height: 8),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: ChannelSelectorBar(),
            ),
            const SizedBox(height: 12),
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
                      onTap: () => context.go(AppRoutes.neighborhoodSync),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSmartSuggestions(context, ref),
            const SizedBox(height: 16),
            _buildFavoritesSection(context, ref),
            const SizedBox(height: 16),
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
            if (_heroImageProvider != null)
              Image(image: _heroImageProvider!, fit: BoxFit.cover, alignment: const Alignment(0, 0.3))
            else if (!profileAsync.isLoading)
              Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: const Alignment(0, 0.3)),
            if (state.isOn)
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final targetAspectRatio = constraints.maxWidth / constraints.maxHeight;
                    return AnimatedRooflineOverlay(
                      previewColors: state.displayColors,
                      previewEffectId: state.effectId,
                      previewSpeed: state.speed,
                      brightness: state.brightness,
                      forceOn: state.isOn,
                      targetAspectRatio: targetAspectRatio,
                      imageAlignment: const Offset(0, 0.3),
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
          );
        } catch (_) {}
        try { ref.read(activePresetLabelProvider.notifier).state = favorite.patternName; } catch (_) {}
        try { ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id); } catch (_) {}
        try {
          if (mounted) {
            ref.trackWledPayload(payload: payload, patternName: favorite.patternName, source: 'favorite');
          }
        } catch (_) {}
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
      left: 0,
      right: 0,
      bottom: 0,
      child: Consumer(builder: (context, ref, _) {
        final wledState = ref.watch(wledStateProvider);
        final activePreset = ref.watch(activePresetLabelProvider);
        final isOn = wledState.isOn;

        String effectName;
        if (activePreset != null) {
          effectName = activePreset;
        } else if (wledState.supportsRgbw && wledState.warmWhite > 0) {
          effectName = 'Warm White';
        } else {
          effectName = wledState.effectName;
        }

        return ClipRRect(
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(20),
            topRight: Radius.circular(20),
          ),
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
                                'System Off',
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
                    final notifier = ref.read(wledStateProvider.notifier);
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
                                  ? (v) => notifier.setBrightness(v.round())
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
                    );
                    ref.read(activePresetLabelProvider.notifier).state = patternName;
                  } catch (_) {}
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
              debugPrint('Applying favorite: ${favorite.patternName}');
              debugPrint('Pattern data: ${favorite.patternData}');
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
                  );
                } catch (_) {}
                try { ref.read(activePresetLabelProvider.notifier).state = favorite.patternName; } catch (_) {}
                try { ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id); } catch (_) {}
                try {
                  if (mounted) ref.trackWledPayload(payload: payload, patternName: favorite.patternName, source: 'favorite');
                } catch (_) {}
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
    } catch (_) {}
    return NexGenPalette.cyan;
  }
}