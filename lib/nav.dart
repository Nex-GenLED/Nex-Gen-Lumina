import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/geofence/geofence_monitor.dart';
import 'dart:ui';
import 'package:go_router/go_router.dart';
import 'package:nexgen_command/features/discovery/device_discovery.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/wled/widgets/neon_color_wheel.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/features/ai/lumina_chat.dart';
import 'package:nexgen_command/features/ai/lumina_chat_screen.dart';
import 'package:nexgen_command/features/site/settings_page.dart';
import 'package:nexgen_command/features/site/user_profile_page.dart';
import 'package:nexgen_command/features/site/user_profile_screen.dart';
import 'package:nexgen_command/features/site/edit_profile_screen.dart';
import 'package:nexgen_command/features/site/security_settings_screen.dart';
import 'package:nexgen_command/features/site/help_center_screen.dart';
import 'package:nexgen_command/features/site/referral_program_screen.dart';
import 'package:nexgen_command/features/site/lumina_studio_screen.dart';
import 'package:nexgen_command/features/geofence/geofence_setup_screen.dart';
import 'package:nexgen_command/features/site/user_profile_providers.dart';
import 'package:nexgen_command/features/permissions/welcome_wizard.dart';
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/signup_page.dart';
import 'package:nexgen_command/features/auth/forgot_password_page.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';
import 'package:nexgen_command/features/wled/wled_service.dart';
import 'package:nexgen_command/features/wled/wled_models.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/ble/controller_setup_wizard.dart';
import 'package:nexgen_command/features/ble/wifi_connect_page_hybrid.dart';
import 'package:nexgen_command/features/ble/wled_ble_setup.dart';
import 'package:nexgen_command/features/ble/wled_http_setup.dart';
import 'package:nexgen_command/features/ble/wled_manual_setup.dart';
import 'package:nexgen_command/widgets/glass_app_bar.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/pattern_providers.dart';
import 'package:nexgen_command/features/wled/zone_configuration_page.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/features/wled/current_colors_editor_screen.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
import 'package:nexgen_command/features/site/manage_controllers_page.dart';
import 'package:nexgen_command/features/site/system_management_screen.dart';
import 'package:nexgen_command/features/site/remote_access_screen.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';
import 'package:nexgen_command/features/schedule/widgets/night_track_bar.dart';
import 'package:nexgen_command/features/schedule/widgets/mini_schedule_list.dart';
import 'package:nexgen_command/features/schedule/schedule_sync.dart';
import 'package:nexgen_command/features/site/site_providers.dart';
import 'package:nexgen_command/features/site/controllers_providers.dart';
import 'package:nexgen_command/features/site/site_models.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/utils/sun_utils.dart';
import 'package:nexgen_command/features/schedule/sun_time_provider.dart';
import 'package:nexgen_command/widgets/pattern_adjustment_panel.dart';
import 'package:nexgen_command/features/design/design_studio_screen.dart';
import 'package:nexgen_command/features/design/my_designs_screen.dart';
import 'package:nexgen_command/features/scenes/my_scenes_screen.dart';
import 'package:nexgen_command/features/voice/voice_assistant_guide_screen.dart';
import 'package:nexgen_command/features/onboarding/feature_tour.dart';
import 'package:nexgen_command/features/properties/my_properties_screen.dart';
import 'package:nexgen_command/widgets/connection_status_indicator.dart';
import 'package:nexgen_command/widgets/animated_roofline_overlay.dart';
import 'package:nexgen_command/features/ar/ar_preview_providers.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/installer/installer_pin_screen.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/admin/admin_dashboard_screen.dart';
import 'package:nexgen_command/features/voice/dashboard_voice_control.dart';
import 'package:nexgen_command/features/voice/widgets/voice_control_fab.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:nexgen_command/features/simple/simple_providers.dart';
import 'package:nexgen_command/features/simple/simple_dashboard.dart';
import 'package:nexgen_command/features/simple/simple_settings.dart';
import 'package:nexgen_command/features/wled/usage_tracking_extension.dart';
import 'package:nexgen_command/widgets/favorites_grid.dart';
import 'package:nexgen_command/widgets/smart_suggestions_list.dart';
import 'package:nexgen_command/features/autopilot/learning_providers.dart';

/// GoRouter configuration for app navigation
///
/// This uses go_router for declarative routing, which provides:
/// - Type-safe navigation
/// - Deep linking support (web URLs, app links)
/// - Easy route parameters
/// - Navigation guards and redirects
///
/// To add a new route:
/// 1. Add a route constant to AppRoutes below
/// 2. Add a GoRoute to the routes list
/// 3. Navigate using context.go() or context.push()
/// 4. Use context.pop() to go back.
/// Listenable that notifies when Firebase Auth state changes.
/// Used to trigger GoRouter redirect checks.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

class AppRouter {
  static final _authListenable = _AuthStateListenable();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    // Refresh route when auth state changes
    refreshListenable: _authListenable,
    // Redirect based on authentication state
    redirect: (context, state) {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;
      final isAuthRoute = state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.signUp ||
          state.matchedLocation == AppRoutes.forgotPassword;

      // If user is logged in and trying to access auth routes, redirect to dashboard
      if (isLoggedIn && isAuthRoute) {
        return AppRoutes.dashboard;
      }

      // If user is not logged in and trying to access protected routes, redirect to login
      // (but allow auth routes and welcome wizard)
      if (!isLoggedIn && !isAuthRoute && state.matchedLocation != AppRoutes.welcome) {
        return AppRoutes.login;
      }

      // No redirect needed
      return null;
    },
    routes: [
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        pageBuilder: (context, state) => const NoTransitionPage(child: LoginPage()),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'signup',
        pageBuilder: (context, state) => const NoTransitionPage(child: SignUpPage()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        pageBuilder: (context, state) => const NoTransitionPage(child: ForgotPasswordPage()),
      ),
      GoRoute(
        path: AppRoutes.discovery,
        name: 'discovery',
        pageBuilder: (context, state) => const NoTransitionPage(child: DiscoveryPage()),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        pageBuilder: (context, state) => const NoTransitionPage(child: WelcomeWizardPage()),
      ),
      GoRoute(
        path: AppRoutes.dashboard,
        name: 'dashboard',
        pageBuilder: (context, state) => const NoTransitionPage(child: MainScaffold()),
      ),
      GoRoute(
        path: AppRoutes.controllerSetupWizard,
        name: 'controller-setup-wizard',
        pageBuilder: (context, state) => MaterialPage(fullscreenDialog: true, child: const ControllerSetupWizard()),
      ),
      GoRoute(
        path: AppRoutes.wifiConnect,
        name: 'wifi-connect',
        pageBuilder: (context, state) => MaterialPage(fullscreenDialog: true, child: const WledManualSetup()),
      ),
      GoRoute(
        path: AppRoutes.patternCategory,
        name: 'pattern-category',
        pageBuilder: (context, state) {
          final id = state.pathParameters['categoryId']!;
          final extra = state.extra;
          String? name;
          if (extra is Map && extra['name'] is String) {
            name = extra['name'] as String;
          } else if (extra is PatternCategory) {
            name = extra.name;
          }
          return NoTransitionPage(child: CategoryDetailScreen(categoryId: id, categoryName: name));
        },
      ),
      GoRoute(
        path: AppRoutes.patternSubCategory,
        name: 'pattern-subcategory',
        pageBuilder: (context, state) {
          final categoryId = state.pathParameters['categoryId']!;
          final subId = state.pathParameters['subId']!;
          String? displayName;
          final extra = state.extra;
          if (extra is Map && extra['name'] is String) displayName = extra['name'] as String;
          return NoTransitionPage(child: ThemeSelectionScreen(categoryId: categoryId, subCategoryId: subId, subCategoryName: displayName));
        },
      ),
      GoRoute(
        path: AppRoutes.settings,
        name: 'settings',
        pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
      ),
      GoRoute(
        path: AppRoutes.settingsSystem,
        name: 'settings-system',
        pageBuilder: (context, state) => const NoTransitionPage(child: SystemManagementScreen()),
      ),
      GoRoute(
        path: AppRoutes.controllersSettings,
        name: 'controllers-settings',
        pageBuilder: (context, state) => const NoTransitionPage(child: ManageControllersPage()),
      ),
      GoRoute(
        path: AppRoutes.profile,
        name: 'profile',
        pageBuilder: (context, state) => const NoTransitionPage(child: UserProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.profileEdit,
        name: 'profile-edit',
        pageBuilder: (context, state) => const NoTransitionPage(child: EditProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.security,
        name: 'security',
        pageBuilder: (context, state) => const NoTransitionPage(child: SecuritySettingsScreen()),
      ),
      GoRoute(
        path: AppRoutes.deviceSetup,
        name: 'device-setup',
        pageBuilder: (context, state) => const NoTransitionPage(child: DeviceSetupPage()),
      ),
      GoRoute(
        path: AppRoutes.wledZones,
        name: 'wled-zones',
        pageBuilder: (context, state) => const NoTransitionPage(child: ZoneConfigurationPage()),
      ),
      GoRoute(
        path: AppRoutes.hardwareConfig,
        name: 'hardware-config',
        pageBuilder: (context, state) => const NoTransitionPage(child: HardwareConfigScreen()),
      ),
      GoRoute(
        path: AppRoutes.helpCenter,
        name: 'help-center',
        pageBuilder: (context, state) => const NoTransitionPage(child: HelpCenterScreen()),
      ),
      GoRoute(
        path: AppRoutes.referrals,
        name: 'referrals',
        pageBuilder: (context, state) => const NoTransitionPage(child: ReferralProgramScreen()),
      ),
      GoRoute(
        path: AppRoutes.luminaStudio,
        name: 'lumina-studio',
        pageBuilder: (context, state) => const NoTransitionPage(child: LuminaStudioScreen()),
      ),
      GoRoute(
        path: AppRoutes.geofenceSetup,
        name: 'geofence-setup',
        pageBuilder: (context, state) => const NoTransitionPage(child: GeofenceSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.remoteAccess,
        name: 'remote-access',
        pageBuilder: (context, state) => const NoTransitionPage(child: RemoteAccessScreen()),
      ),
      GoRoute(
        path: AppRoutes.designStudio,
        name: 'design-studio',
        pageBuilder: (context, state) => const NoTransitionPage(child: DesignStudioScreen()),
      ),
      GoRoute(
        path: AppRoutes.myDesigns,
        name: 'my-designs',
        pageBuilder: (context, state) => const NoTransitionPage(child: MyDesignsScreen()),
      ),
      GoRoute(
        path: AppRoutes.myScenes,
        name: 'my-scenes',
        pageBuilder: (context, state) => const NoTransitionPage(child: MyScenesScreen()),
      ),
      GoRoute(
        path: AppRoutes.voiceAssistants,
        name: 'voice-assistants',
        pageBuilder: (context, state) => const NoTransitionPage(child: VoiceAssistantGuideScreen()),
      ),
      GoRoute(
        path: AppRoutes.myProperties,
        name: 'my-properties',
        pageBuilder: (context, state) => const NoTransitionPage(child: MyPropertiesScreen()),
      ),
      GoRoute(
        path: AppRoutes.rooflineEditor,
        name: 'roofline-editor',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: RooflineEditorScreen()),
      ),
      GoRoute(
        path: AppRoutes.segmentSetup,
        name: 'segment-setup',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: SegmentSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.rooflineSetupWizard,
        name: 'roofline-setup-wizard',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: RooflineSetupWizard()),
      ),
      GoRoute(
        path: AppRoutes.currentColors,
        name: 'current-colors',
        pageBuilder: (context, state) => const NoTransitionPage(child: CurrentColorsEditorScreen()),
      ),
      // Installer mode routes
      GoRoute(
        path: AppRoutes.installerPin,
        name: 'installer-pin',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerPinScreen()),
      ),
      GoRoute(
        path: AppRoutes.installerWizard,
        name: 'installer-wizard',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerSetupWizard()),
      ),
      // Admin management routes
      GoRoute(
        path: AppRoutes.adminPin,
        name: 'admin-pin',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: AdminPinScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminDashboard,
        name: 'admin-dashboard',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: AdminDashboardScreen()),
      ),
    ],
  );
}

/// Route path constants
/// Use these instead of hard-coding route strings
class AppRoutes {
  static const String login = '/';
  static const String signUp = '/signup';
  static const String forgotPassword = '/forgot-password';
  static const String discovery = '/discovery';
  static const String welcome = '/welcome';
  static const String dashboard = '/dashboard';
  static const String settings = '/settings';
  static const String settingsSystem = '/settings/system';
  static const String controllersSettings = '/settings/controllers';
  static const String profile = '/settings/profile';
  static const String profileEdit = '/settings/profile/edit';
  static const String security = '/settings/security';
  static const String deviceSetup = '/device-setup';
  static const String controllerSetupWizard = '/setup/wizard';
  static const String wifiConnect = '/wifi-connect';
  static const String patternCategory = '/explore/:categoryId';
  static const String patternSubCategory = '/explore/:categoryId/sub/:subId';
  static const String wledZones = '/wled/zones';
  static const String hardwareConfig = '/settings/hardware';
  static const String helpCenter = '/settings/help';
  static const String referrals = '/settings/referrals';
  static const String luminaStudio = '/settings/studio';
  static const String geofenceSetup = '/settings/geofence';
  static const String remoteAccess = '/settings/remote-access';
  static const String designStudio = '/design-studio';
  static const String myDesigns = '/my-designs';
  static const String myScenes = '/my-scenes';
  static const String voiceAssistants = '/settings/voice-assistants';
  static const String myProperties = '/settings/properties';
  static const String rooflineEditor = '/settings/roofline-editor';
  static const String segmentSetup = '/segment-setup';
  static const String rooflineSetupWizard = '/roofline-setup-wizard';
  static const String currentColors = '/settings/current-colors';
  // Installer mode routes
  static const String installerPin = '/installer/pin';
  static const String installerWizard = '/installer/wizard';
  // Admin management routes
  static const String adminPin = '/admin/pin';
  static const String adminDashboard = '/admin/dashboard';
}

// ========================== Pages ============================
class DiscoveryPage extends ConsumerWidget {
  const DiscoveryPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // On first launch, redirect into Welcome Wizard
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      // Avoid redirect loops if we're not on discovery route
      final loc = GoRouter.of(context).routerDelegate.currentConfiguration.uri.toString();
      if (loc != AppRoutes.discovery) return;
      final completed = await isWelcomeCompleted();
      if (!completed && context.mounted) {
        context.go(AppRoutes.welcome);
      }
    });
    final asyncDevices = ref.watch(discoveredDevicesProvider);
    final selectedIp = ref.watch(selectedDeviceIpProvider);

    ref.listen<String?>(selectedDeviceIpProvider, (prev, next) {
      if (next != null && ModalRoute.of(context)?.isCurrent == true) {
        Future.microtask(() => context.go(AppRoutes.dashboard));
      }
    });

    return Scaffold(
      appBar: GlassAppBar(
        title: const Text('Lumina'),
        actions: [
          IconButton(
            tooltip: 'Device Setup',
            icon: const Icon(Icons.bluetooth_searching),
            onPressed: () => context.push(AppRoutes.deviceSetup),
          ),
        ],
      ),
      // Show a subtle action to open settings even from welcome flow
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Device Discovery', style: Theme.of(context).textTheme.headlineMedium),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Theme.of(context).colorScheme.outline.withValues(alpha: 0.2)),
            ),
            child: Row(children: [
              const _NeonDot(),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  asyncDevices.isLoading ? 'Scanning local network for WLED devices…' : (selectedIp != null ? 'Connected to $selectedIp' : 'Select a device to continue'),
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
              ),
              if (asyncDevices.isLoading) const SizedBox(width: 12),
              if (asyncDevices.isLoading) const CircularProgressIndicator(strokeWidth: 2),
            ]),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: asyncDevices.when(
              data: (devices) {
                if (devices.isEmpty) {
                  return _EmptyState(onRetry: () => ref.refresh(discoveredDevicesProvider));
                }
                return ListView.separated(
                  itemCount: devices.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) {
                    final d = devices[i];
                    final ip = d.address.address;
                    final isSel = ip == selectedIp;
                    return ListTile(
                      title: Text(d.name, overflow: TextOverflow.ellipsis),
                      subtitle: Text(ip),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12), side: BorderSide(color: isSel ? NexGenPalette.cyan : Theme.of(context).colorScheme.outline.withValues(alpha: 0.2))),
                      tileColor: isSel ? NexGenPalette.cyan.withValues(alpha: 0.06) : null,
                      trailing: Icon(Icons.chevron_right, color: isSel ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant),
                      onTap: () => ref.read(selectedDeviceIpProvider.notifier).state = ip,
                    );
                  },
                );
              },
              error: (e, st) => _ErrorState(error: '$e', onRetry: () => ref.refresh(discoveredDevicesProvider)),
              loading: () => const SizedBox.shrink(),
            ),
          )
        ]),
      ),
    );
  }
}

class _NeonDot extends StatelessWidget {
  const _NeonDot();
  @override
  Widget build(BuildContext context) {
    return Container(
      width: 14,
      height: 14,
      decoration: BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle, boxShadow: [
        BoxShadow(color: NexGenPalette.cyan.withValues(alpha: 0.6), blurRadius: 12, spreadRadius: 1),
      ]),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final VoidCallback onRetry;
  const _EmptyState({required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.router_outlined, color: NexGenPalette.violet, size: 42),
        const SizedBox(height: 12),
        Text('No devices found', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text('Make sure your phone and the light are on the same network.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Rescan')),
      ]),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String error; final VoidCallback onRetry;
  const _ErrorState({required this.error, required this.onRetry});
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
        Icon(Icons.error_outline, color: Theme.of(context).colorScheme.error, size: 42),
        const SizedBox(height: 12),
        Text('Discovery error', style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(error, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),
        FilledButton.icon(onPressed: onRetry, icon: const Icon(Icons.refresh), label: const Text('Try again')),
      ]),
    );
  }
}

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
    final notifier = ref.read(wledStateProvider.notifier);
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
          Consumer(builder: (context, ref, _) {
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
          }),
          IconButton(
            icon: const Icon(Icons.settings_suggest_outlined),
            tooltip: 'Settings',
            onPressed: () => context.push(AppRoutes.settings),
          )
        ],
      ),
      body: Stack(children: [
        SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 100),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // Section A: Image hero framed, now hosting header + controls overlays
            Container(
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
                    // This prevents the stock image from flashing before user's image loads
                    if (_heroImageProvider != null)
                      Image(image: _heroImageProvider!, fit: BoxFit.cover, alignment: Alignment.topCenter)
                    else if (!profileAsync.isLoading)
                      // Only show stock image after profile has loaded and there's no custom image
                      Image.asset('assets/images/Demohomephoto.jpg', fit: BoxFit.cover, alignment: Alignment.topCenter),
                    // While loading, just show the matte black background (already there above)
                    // AR Roofline overlay - shows animated LED effects on the house
                    if (state.isOn && state.connected)
                      Positioned.fill(
                        child: AnimatedRooflineOverlay(
                          previewColors: [state.color],
                          previewEffectId: state.effectId,
                          previewSpeed: state.speed,
                          brightness: state.brightness,
                          forceOn: state.isOn,
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
                    // Top overlay: Power button (greeting moved to AppBar)
                    Positioned(
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
                    ),
                    // Add Photo button (shown when no custom house image)
                    Consumer(builder: (context, ref, _) {
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
                    }),
                    // Bottom overlay: Glass control bar (pattern + brightness)
                    Positioned(
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
                    ),
                  ]),
                ),
              ),
            ),
            // Expandable Pattern Adjustment Panel
            AnimatedSize(
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
                            // Uses displayColors which prefers Lumina's color sequence over single polled color
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
                                  effectName: state.effectName, // Use stored effect name from Lumina
                                  initialColors: colors,
                                  showColors: true, // Show color sequence for editing
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
            ),
            const SizedBox(height: 12),
            // Section B: Design Studio button
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _GlassActionButton(
                icon: Icons.palette,
                label: 'Design Studio',
                onTap: () => context.push(AppRoutes.designStudio),
              ),
            ),
            const SizedBox(height: 16),
            // Smart Suggestions Section
            SmartSuggestionsList(
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
            ),
            const SizedBox(height: 16),
            // Favorites Section
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
                // from ref access issues or unexpected exceptions
                try {
                  // Check mounted first to avoid accessing disposed widget
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

                  // Check mounted before accessing ref after await
                  if (!mounted) return;

                  if (success) {
                    // Update the active pattern label immediately for UI feedback
                    try {
                      ref.read(activePresetLabelProvider.notifier).state = favorite.patternName;
                    } catch (_) {}

                    // Record favorite usage (don't await - fire and forget)
                    try {
                      ref.read(favoritesNotifierProvider.notifier).recordFavoriteUsage(favorite.id);
                    } catch (_) {}

                    // Track overall usage (wrapped in mounted check)
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
            const SizedBox(height: 16),
            // Section D: Vertical Agenda (Today + next 6 days)
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

  void _showColorPicker(BuildContext context, Color initial, dynamic notifier, bool enabled) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: IgnorePointer(
          ignoring: !enabled,
          child: Opacity(
            opacity: enabled ? 1 : 0.5,
            child: Center(child: NeonColorWheel(size: 240, color: initial, onChanged: notifier.setColor)),
          ),
        ),
      ),
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
      await ref.read(favoritesNotifierProvider.notifier).addFavorite(
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

/// Root shell with persistent 5-item Bottom Navigation (Glass Dock)
class MainScaffold extends ConsumerStatefulWidget {
  const MainScaffold({super.key});

  @override
  ConsumerState<MainScaffold> createState() => _MainScaffoldState();
}

class _MainScaffoldState extends ConsumerState<MainScaffold> {
  bool _tourChecked = false;

  final _pages = const [
    WledDashboardPage(),
    MySchedulePage(),
    _LuminaChatPage(),
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
                ? _SimpleNavBar(index: tabIndex, onTap: _onTap)
                : _GlassDockNavBar(index: tabIndex, onTap: _onTap),
          ),
        ]),
      ),
    );
  }
}

class _GlassDockNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _GlassDockNavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = NexGenPalette.cyan;
    const unselected = Color(0xFF808080);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _DockItem(
                  label: 'Home',
                  icon: Icons.home_filled,
                  active: index == 0,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(0),
                ),
                _DockItem(
                  label: 'Schedule',
                  icon: Icons.schedule_rounded,
                  active: index == 1,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(1),
                ),
                _DockCenter(
                  active: index == 2,
                  selected: selected,
                  onTap: () => onTap(2),
                ),
                _DockItem(
                  label: 'Explore',
                  icon: Icons.explore_rounded,
                  active: index == 3,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(3),
                ),
                _DockItem(
                  label: 'System',
                  icon: Icons.tune_rounded,
                  active: index == 4,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(4),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Simplified 2-tab navigation bar for Simple Mode
class _SimpleNavBar extends StatelessWidget {
  final int index;
  final ValueChanged<int> onTap;
  const _SimpleNavBar({required this.index, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final selected = NexGenPalette.cyan;
    const unselected = Color(0xFF808080);
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _SimpleNavItem(
                  label: 'Home',
                  icon: Icons.home_filled,
                  active: index == 0,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(0),
                ),
                _SimpleNavItem(
                  label: 'Settings',
                  icon: Icons.settings_rounded,
                  active: index == 1,
                  selected: selected,
                  unselected: unselected,
                  onTap: () => onTap(1),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Larger nav item for Simple Mode (easier to tap)
class _SimpleNavItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color selected;
  final Color unselected;
  final VoidCallback onTap;

  const _SimpleNavItem({
    required this.label,
    required this.icon,
    required this.active,
    required this.selected,
    required this.unselected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
        decoration: BoxDecoration(
          color: active ? selected.withOpacity(0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              color: active ? selected : unselected,
              size: 32,
            ),
            const SizedBox(height: 6),
            Text(
              label,
              style: TextStyle(
                fontSize: 16,
                fontWeight: active ? FontWeight.w600 : FontWeight.normal,
                color: active ? selected : unselected,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DockItem extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool active;
  final Color selected;
  final Color unselected;
  final VoidCallback onTap;
  const _DockItem({required this.label, required this.icon, required this.active, required this.selected, required this.unselected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final color = active ? selected : unselected;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 24),
            const SizedBox(height: 4),
            Text(label, style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 10, color: color)),
          ]),
        ),
      ),
    );
  }
}

class _DockCenter extends StatelessWidget {
  final bool active;
  final Color selected;
  final VoidCallback onTap;
  const _DockCenter({required this.active, required this.selected, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: GestureDetector(
          onTap: onTap,
          child: SizedBox(
            width: 84,
            height: 84,
            child: Container(
              decoration: BoxDecoration(
                color: NexGenPalette.matteBlack,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(color: selected.withValues(alpha: active ? 0.8 : 0.35), blurRadius: active ? 20 : 12, spreadRadius: 1),
                ],
                border: Border.all(color: selected.withValues(alpha: 0.7), width: 1.5),
              ),
              alignment: Alignment.center,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Image.asset(
                    'assets/images/Gemini_Generated_Image_n4fr1en4fr1en4fr.png',
                    height: 32.0,
                    fit: BoxFit.contain,
                    errorBuilder: (context, error, stackTrace) => Icon(Icons.auto_awesome_rounded, color: selected, size: 32),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'Lumina',
                    style: TextStyle(color: Colors.white, fontSize: 12.0, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _GlassActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  const _GlassActionButton({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
          child: Container(
            height: 48,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: NexGenPalette.gunmetal90,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: NexGenPalette.line),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, mainAxisSize: MainAxisSize.max, children: [
              Icon(icon, color: NexGenPalette.cyan, size: 20),
              const SizedBox(width: 8),
              Flexible(child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.labelLarge)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _CurrentPatternBar extends ConsumerWidget {
  const _CurrentPatternBar();

  String _labelFromAction(String actionLabel) {
    final a = actionLabel.trim();
    if (a.toLowerCase().startsWith('pattern')) {
      final idx = a.indexOf(':');
      return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
    }
    return a;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wledStateProvider);
    final schedules = ref.watch(schedulesProvider);
    final activePreset = ref.watch(activePresetLabelProvider);

    String valueText;
    if (!state.connected) {
      valueText = 'System Offline';
    } else if (activePreset != null) {
      // If user manually selected a preset, show that
      valueText = activePreset;
    } else {
      // Try to infer from today's first schedule item
      final now = DateTime.now();
      final weekdayIndex0Sun = now.weekday % 7; // Sun=0..Sat=6
      List<String> keys;
      switch (weekdayIndex0Sun) {
        case 0:
          keys = const ['sun', 'sunday'];
          break;
        case 1:
          keys = const ['mon', 'monday'];
          break;
        case 2:
          keys = const ['tue', 'tues', 'tuesday'];
          break;
        case 3:
          keys = const ['wed', 'wednesday'];
          break;
        case 4:
          keys = const ['thu', 'thurs', 'thursday'];
          break;
        case 5:
          keys = const ['fri', 'friday'];
          break;
        case 6:
        default:
          keys = const ['sat', 'saturday'];
      }
      final dayItems = schedules.where((s) {
        if (!s.enabled) return false;
        final dl = s.repeatDays.map((e) => e.toLowerCase());
        return dl.contains('daily') || dl.any(keys.contains);
      }).toList(growable: false);

      if (dayItems.isNotEmpty) {
        valueText = _labelFromAction(dayItems.first.actionLabel);
      } else if (state.supportsRgbw && state.warmWhite > 0) {
        valueText = 'Warm White';
      } else {
        valueText = 'Active Pattern';
      }
    }

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: NexGenPalette.gunmetal90,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: NexGenPalette.line),
      ),
      child: Row(children: [
        Icon(Icons.palette, color: state.color, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
            Text('ACTIVE PATTERN', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 9, fontWeight: FontWeight.w700, letterSpacing: 0.8)),
            const SizedBox(height: 2),
            Text(valueText, maxLines: 1, overflow: TextOverflow.ellipsis, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w700)),
          ]),
        ),
        if (state.connected && state.isOn) const _LiveIndicator(),
      ]),
    );
  }
}

class _LiveIndicator extends StatefulWidget {
  const _LiveIndicator();
  @override
  State<_LiveIndicator> createState() => _LiveIndicatorState();
}

class _LiveIndicatorState extends State<_LiveIndicator> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
    _scale = Tween<double>(begin: 0.85, end: 1.15).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Row(mainAxisSize: MainAxisSize.min, children: [
      ScaleTransition(
        scale: _scale,
        child: Container(width: 8, height: 8, decoration: const BoxDecoration(color: NexGenPalette.cyan, shape: BoxShape.circle)),
      ),
      const SizedBox(width: 6),
      Text('ON', style: Theme.of(context).textTheme.labelMedium?.copyWith(color: NexGenPalette.cyan)),
    ]);
  }
}

class _VerticalAgenda extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(wledStateProvider);
    final schedules = ref.watch(schedulesProvider);
    final String fallbackPatternLabel = (state.supportsRgbw && state.warmWhite > 0) ? 'Warm White' : 'Active Pattern';
    // Get user coordinates (if available) to fetch sunrise/sunset times
    final userAsync = ref.watch(currentUserProfileProvider);
    final user = userAsync.maybeWhen(data: (u) => u, orElse: () => null);
    final hasCoords = (user?.latitude != null && user?.longitude != null);
    final sunAsync = hasCoords
        ? ref.watch(sunTimeProvider((lat: user!.latitude!, lon: user.longitude!)))
        : const AsyncValue.data(null);

    bool appliesTo(ScheduleItem s, int weekdayIndex0Sun) {
      final dl = s.repeatDays.map((e) => e.toLowerCase()).toList(growable: false);
      if (dl.contains('daily')) return true;
      Set<String> keys;
      switch (weekdayIndex0Sun) {
        case 0:
          keys = {'sun', 'sunday'};
          break;
        case 1:
          keys = {'mon', 'monday'};
          break;
        case 2:
          keys = {'tue', 'tues', 'tuesday'};
          break;
        case 3:
          keys = {'wed', 'wednesday'};
          break;
        case 4:
          keys = {'thu', 'thurs', 'thursday'};
          break;
        case 5:
          keys = {'fri', 'friday'};
          break;
        case 6:
          keys = {'sat', 'saturday'};
          break;
        default:
          keys = {};
      }
      return dl.any(keys.contains);
    }

    List<ScheduleItem> itemsForDay(int weekdayIndex0Sun) => schedules.where((s) => s.enabled && appliesTo(s, weekdayIndex0Sun)).toList(growable: false);
    String _labelFromAction(String actionLabel) {
      final a = actionLabel.trim();
      if (a.toLowerCase().startsWith('pattern')) {
        final idx = a.indexOf(':');
        return idx != -1 && idx + 1 < a.length ? a.substring(idx + 1).trim() : a;
      }
      return a;
    }

    // Build list of 7 days starting from today
    final now = DateTime.now();
    final List<DateTime> days = List.generate(7, (i) => DateTime(now.year, now.month, now.day).add(Duration(days: i)));
    final List<String> abbr = const ['SUN', 'MON', 'TUE', 'WED', 'THU', 'FRI', 'SAT'];

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // Time Axis Header to mirror My Schedule page
      Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Row(children: [
          const SizedBox(width: 50),
          const SizedBox(width: 10),
          Expanded(
            child: SizedBox(
              height: 22,
              child: Stack(children: [
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(8),
                      gradient: LinearGradient(begin: Alignment.centerLeft, end: Alignment.centerRight, colors: [NexGenPalette.matteBlack.withValues(alpha: 0.15), NexGenPalette.matteBlack.withValues(alpha: 0.05)]),
                    ),
                  ),
                ),
                Align(alignment: Alignment.center, child: Container(width: 1, color: NexGenPalette.textMedium.withValues(alpha: 0.25))),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    sunAsync.when(
                      data: (s) => Text(
                        (s?.sunsetLabel ?? 'Sunset (—)').toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNSET (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNSET (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                    sunAsync.when(
                      data: (s) => Text(
                        (s?.sunriseLabel ?? 'Sunrise (—)').toUpperCase(),
                        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8),
                      ),
                      loading: () => Text('SUNRISE (…)'.toUpperCase(), style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                      error: (e, st) => Text('SUNRISE (—)', style: Theme.of(context).textTheme.labelSmall?.copyWith(color: NexGenPalette.textMedium, fontSize: 10, letterSpacing: 0.8)),
                    ),
                  ]),
                ),
              ]),
            ),
          ),
        ]),
      ),
      ...List.generate(7, (i) {
      final d = days[i];
      final isToday = i == 0;
      final int weekdayIndex0Sun = d.weekday % 7; // Sun=0..Sat=6
        final dayItems = itemsForDay(weekdayIndex0Sun);
        final String label = dayItems.isNotEmpty ? _labelFromAction(dayItems.first.actionLabel) : fallbackPatternLabel;

      return InkWell(
        onTap: () => showScheduleEditor(context, ref, preselectedDayIndex: weekdayIndex0Sun),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(children: [
            // Leading Day Abbreviation
            SizedBox(
              width: 50,
              child: Text(
                abbr[weekdayIndex0Sun],
                textAlign: TextAlign.left,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(color: isToday ? NexGenPalette.cyan : NexGenPalette.textMedium, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
              ),
            ),
            const SizedBox(width: 10),
              // Night Track Bar
              Expanded(child: NightTrackBar(label: label, items: dayItems)),
          ]),
        ),
      );
      }),
    ]);
  }
}

class _WeeklyScheduleOverview extends StatelessWidget {
  final List<double> values; // 7 entries, Sunday..Saturday, 0..1
  const _WeeklyScheduleOverview({required this.values});

  @override
  Widget build(BuildContext context) {
    final letters = const ['S', 'M', 'T', 'W', 'T', 'F', 'S'];
    final todayIndex = DateTime.now().weekday % 7; // Sun=0
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: List.generate(7, (i) {
      final v = values[i].clamp(0.0, 1.0);
      final isToday = i == todayIndex;
      return Column(children: [
        Container(
          width: 12,
          height: 60,
          decoration: BoxDecoration(color: NexGenPalette.gunmetal50, borderRadius: BorderRadius.circular(6)),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              width: 12,
              height: 60 * v,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(6),
                gradient: const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [NexGenPalette.cyan, NexGenPalette.blue]),
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          letters[i],
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: isToday ? NexGenPalette.cyan : Colors.white, fontWeight: isToday ? FontWeight.w700 : FontWeight.w500),
        )
      ]);
    }));
  }
}

// ------------------------ Placeholder Tab Pages ------------------------
class _SchedulePage extends StatelessWidget {
  const _SchedulePage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('My Schedule')),
      body: const Center(child: Text('Timers & Automation coming soon')),
    );
  }
}

class _ExplorePage extends StatelessWidget {
  const _ExplorePage();
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GlassAppBar(title: Text('Explore Patterns')),
      body: const Center(child: Text('Pattern Library preview coming soon')),
    );
  }
}

class _LuminaChatPage extends StatelessWidget {
  const _LuminaChatPage();
  @override
  Widget build(BuildContext context) {
    return const LuminaChatScreen();
  }
}

class _StatusCard extends StatelessWidget {
  final bool connected;
  const _StatusCard({required this.connected});
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(connected ? Icons.wifi_tethering : Icons.wifi_off_rounded, color: connected ? NexGenPalette.cyan : Theme.of(context).colorScheme.onSurfaceVariant),
          const SizedBox(width: 12),
          Expanded(child: Text(connected ? 'Live' : 'Disconnected', style: Theme.of(context).textTheme.titleMedium)),
        ]),
      ),
    );
  }
}

class _ControlsCard extends ConsumerWidget {
  final dynamic state;
  const _ControlsCard({required this.state});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wledStateProvider.notifier);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Power', style: Theme.of(context).textTheme.titleMedium)),
            Switch(
              value: state.isOn,
              onChanged: state.connected ? (v) => notifier.togglePower(v) : null,
              activeColor: NexGenPalette.cyan,
            )
          ]),
          const SizedBox(height: 12),
          Text('Brightness', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: state.brightness.toDouble(),
            min: 0,
            max: 255,
            onChanged: state.connected ? (v) => notifier.setBrightness(v.round()) : null,
            activeColor: NexGenPalette.cyan,
            inactiveColor: Colors.white.withValues(alpha: 0.2),
          ),
          const SizedBox(height: 8),
          Text('Speed', style: Theme.of(context).textTheme.labelLarge),
          Slider(
            value: state.speed.toDouble(),
            min: 0,
            max: 255,
            onChanged: state.connected ? (v) => notifier.setSpeed(v.round()) : null,
            activeColor: NexGenPalette.violet,
            inactiveColor: Colors.white.withValues(alpha: 0.2),
          ),
        ]),
      ),
    );
  }
}

class _ColorCard extends ConsumerWidget {
  final Color color;
  const _ColorCard({required this.color});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notifier = ref.read(wledStateProvider.notifier);
    final state = ref.watch(wledStateProvider);
    final connected = state.connected;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Primary Color', style: Theme.of(context).textTheme.titleMedium)),
            Container(width: 20, height: 20, decoration: BoxDecoration(shape: BoxShape.circle, color: color, boxShadow: [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 12)])),
          ]),
          const SizedBox(height: 12),
          Center(
            child: IgnorePointer(
              ignoring: !connected,
              child: Opacity(
                opacity: connected ? 1 : 0.5,
                child: NeonColorWheel(size: 220, color: color, onChanged: notifier.setColor),
              ),
            ),
          ),
          if (state.supportsRgbw) ...[
            const SizedBox(height: 16),
            Row(children: [
              Expanded(child: Text('Warm White', style: Theme.of(context).textTheme.labelLarge)),
              Text('${state.warmWhite}', style: Theme.of(context).textTheme.labelMedium),
            ]),
            Slider(
              value: state.warmWhite.toDouble(),
              min: 0,
              max: 255,
              onChanged: connected ? (v) => notifier.setWarmWhite(v.round()) : null,
              activeColor: NexGenPalette.cyan,
              inactiveColor: Colors.white.withValues(alpha: 0.2),
            ),
          ],
        ]),
      ),
    );
  }
}

// NexVision AR card removed per requirement

class _ZonesCard extends StatelessWidget {
  const _ZonesCard();
  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(children: [
          Icon(Icons.view_week_rounded, color: NexGenPalette.cyan),
          const SizedBox(width: 12),
          Expanded(child: Text('Zones & Segments', style: Theme.of(context).textTheme.titleMedium)),
          FilledButton.icon(onPressed: () => context.push(AppRoutes.wledZones), icon: const Icon(Icons.tune), label: const Text('Configure'))
        ]),
      ),
    );
  }
}

class _ScenesCard extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isDemo = ref.watch(demoModeProvider);
    final repo = ref.watch(wledRepositoryProvider);
    final presets = repo?.getPresets() ?? const <WledPreset>[];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('Scenes & Presets', style: Theme.of(context).textTheme.titleMedium)),
            if (!isDemo) ...[
              const SizedBox(width: 8),
              FilledButton.icon(onPressed: () => _showBackendPrompt(context), icon: const Icon(Icons.cloud_upload), label: const Text('Save')),
            ]
          ]),
          const SizedBox(height: 8),
          if (isDemo && presets.isNotEmpty) ...[
            Text('Nex-Gen Signature Presets (Demo)', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: presets.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (_, i) {
                final p = presets[i];
                return ListTile(
                  title: Text(p.name),
                  trailing: FilledButton(
                    onPressed: () async {
                      if (repo == null) return;
                      await repo.applyJson(p.json);
                      final notifier = ref.read(wledStateProvider.notifier);
                      // attempt to immediately reflect bri/color/speed
                      final colList = (p.json['seg'] is List && (p.json['seg'] as List).isNotEmpty) ? ((p.json['seg'] as List).first as Map)['col'] : null;
                      if (colList is List && colList.isNotEmpty && colList.first is List) {
                        final c = colList.first as List;
                        if (c.length >= 3) {
                          notifier.setColor(Color.fromARGB(255, (c[0] as num).toInt(), (c[1] as num).toInt(), (c[2] as num).toInt()));
                        }
                      }
                      final bri = p.json['bri'];
                      if (bri is int) notifier.setBrightness(bri);
                      final seg = p.json['seg'];
                      if (seg is List && seg.isNotEmpty && seg.first is Map) {
                        final sx = (seg.first as Map)['sx'];
                        if (sx is int) notifier.setSpeed(sx);
                      }
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Applied: ${p.name}')));
                      }
                    },
                    child: const Text('Apply'),
                  ),
                );
              },
            ),
          ] else ...[
            Text(
              'To sync scenes across devices, connect Firebase in the Firebase panel (left sidebar). After connecting, I can wire Firebase Auth and Firestore here.',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ]
        ]),
      ),
    );
  }

  void _showBackendPrompt(BuildContext context) {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      builder: (_) => Padding(
        padding: const EdgeInsets.all(16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(Icons.cloud_sync, color: NexGenPalette.cyan),
            const SizedBox(width: 8),
            Text('Connect Firebase', style: Theme.of(context).textTheme.titleMedium),
          ]),
          const SizedBox(height: 12),
          Text('Open the Firebase panel in Dreamflow (left sidebar) and complete setup. Then ask me to integrate Firebase Auth and Firestore for Scenes/Presets.', style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 12),
          Align(alignment: Alignment.centerRight, child: TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('Close'))),
        ]),
      ),
    );
  }
}
