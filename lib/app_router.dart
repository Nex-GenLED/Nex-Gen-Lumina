import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// Feature imports
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/signup_page.dart';
import 'package:nexgen_command/features/auth/forgot_password_page.dart';
import 'package:nexgen_command/features/auth/link_account_screen.dart';
import 'package:nexgen_command/features/auth/join_with_code_screen.dart';
import 'package:nexgen_command/features/users/sub_users_screen.dart';
import 'package:nexgen_command/features/permissions/welcome_wizard.dart';
import 'package:nexgen_command/features/discovery/discovery_page.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/ble/controller_setup_wizard.dart';
import 'package:nexgen_command/features/ble/wled_manual_setup.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
import 'package:nexgen_command/features/wled/library_hierarchy_models.dart';
import 'package:nexgen_command/features/wled/zone_configuration_page.dart';
import 'package:nexgen_command/features/wled/hardware_config_screen.dart';
import 'package:nexgen_command/features/wled/current_colors_editor_screen.dart';
import 'package:nexgen_command/features/site/settings_page.dart';
import 'package:nexgen_command/features/site/user_profile_screen.dart';
import 'package:nexgen_command/features/site/edit_profile_screen.dart';
import 'package:nexgen_command/features/site/security_settings_screen.dart';
import 'package:nexgen_command/features/site/help_center_screen.dart';
import 'package:nexgen_command/features/site/referral_program_screen.dart';
import 'package:nexgen_command/features/site/lumina_studio_screen.dart';
import 'package:nexgen_command/features/site/manage_controllers_page.dart';
import 'package:nexgen_command/features/site/system_management_screen.dart';
import 'package:nexgen_command/features/site/remote_access_screen.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/geofence/geofence_setup_screen.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/design/my_designs_screen.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/scenes/my_scenes_screen.dart';
import 'package:nexgen_command/features/voice/voice_assistant_guide_screen.dart';
import 'package:nexgen_command/features/properties/my_properties_screen.dart';
import 'package:nexgen_command/features/installer/installer_pin_screen.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/installer_landing_screen.dart';
import 'package:nexgen_command/features/installer/media_landing_screen.dart';
import 'package:nexgen_command/features/installer/media_access_code_screen.dart';
import 'package:nexgen_command/features/installer/admin/admin_dashboard_screen.dart';
import 'package:nexgen_command/features/installer/media_dashboard_screen.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';
import 'package:nexgen_command/features/ai/lumina_ai_screen.dart';
import 'package:nexgen_command/features/autopilot/autopilot_weekly_preview.dart';
import 'package:nexgen_command/features/onboarding/first_run_screen.dart';
// Dashboard pages for branch wrappers
import 'package:nexgen_command/features/dashboard/wled_dashboard_page.dart';
import 'package:nexgen_command/features/schedule/my_schedule_page.dart';
// Demo experience imports
import 'package:nexgen_command/features/demo/demo_code_screen.dart';
import 'package:nexgen_command/features/demo/demo_welcome_screen.dart';
import 'package:nexgen_command/features/demo/demo_profile_screen.dart';
import 'package:nexgen_command/features/demo/demo_photo_screen.dart';
import 'package:nexgen_command/features/demo/demo_roofline_screen.dart';
import 'package:nexgen_command/features/demo/demo_completion_screen.dart';
import 'package:nexgen_command/route_guards.dart';

/// Slide + fade transition for Explore sub-routes.
CustomTransitionPage<void> _exploreFadeSlide({
  required Widget child,
  required GoRouterState state,
}) {
  return CustomTransitionPage<void>(
    key: state.pageKey,
    child: child,
    transitionDuration: const Duration(milliseconds: 280),
    reverseTransitionDuration: const Duration(milliseconds: 280),
    transitionsBuilder: (context, animation, secondaryAnimation, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
      );
      return FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.06, 0),
            end: Offset.zero,
          ).animate(curved),
          child: child,
        ),
      );
    },
  );
}

class AppRouter {
  static final _authListenable = AuthStateListenable();

  // Navigator keys for StatefulShellRoute branches
  /// Root navigator key — exposed for notification deep-link navigation.
  static final rootNavigatorKey = GlobalKey<NavigatorState>();
  static GlobalKey<NavigatorState> get _rootNavigatorKey => rootNavigatorKey;
  static final _homeNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'home');
  static final _scheduleNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'schedule');
  static final _exploreNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'explore');
  static final _systemNavigatorKey = GlobalKey<NavigatorState>(debugLabel: 'system');

  static final GoRouter router = GoRouter(
    navigatorKey: _rootNavigatorKey,
    initialLocation: AppRoutes.login,
    refreshListenable: _authListenable,
    redirect: appRedirect,
    routes: [
      // ===== AUTH ROUTES (root navigator, no shell) =====
      GoRoute(
        path: AppRoutes.login,
        name: 'login',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: LoginPage()),
      ),
      GoRoute(
        path: AppRoutes.signUp,
        name: 'signup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: SignUpPage()),
      ),
      GoRoute(
        path: AppRoutes.forgotPassword,
        name: 'forgot-password',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: ForgotPasswordPage()),
      ),
      // ===== INSTALLATION ACCESS CONTROL (root navigator) =====
      GoRoute(
        path: AppRoutes.linkAccount,
        name: 'link-account',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: LinkAccountScreen()),
      ),
      GoRoute(
        path: AppRoutes.joinWithCode,
        name: 'join-with-code',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: JoinWithCodeScreen()),
      ),
      // ===== DEMO ROUTES (root navigator) =====
      GoRoute(
        path: AppRoutes.demoCode,
        name: 'demo-code',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: DemoCodeScreen()),
      ),
      GoRoute(
        path: AppRoutes.demoWelcome,
        name: 'demo-welcome',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: DemoWelcomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.demoProfile,
        name: 'demo-profile',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: DemoProfileScreen()),
      ),
      GoRoute(
        path: AppRoutes.demoPhoto,
        name: 'demo-photo',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: DemoPhotoScreen()),
      ),
      GoRoute(
        path: AppRoutes.demoRoofline,
        name: 'demo-roofline',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: DemoRooflineScreen()),
      ),
      GoRoute(
        path: AppRoutes.demoComplete,
        name: 'demo-complete',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: DemoCompletionScreen()),
      ),
      // ===== ONBOARDING (root navigator) =====
      GoRoute(
        path: AppRoutes.discovery,
        name: 'discovery',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: DiscoveryPage()),
      ),
      GoRoute(
        path: AppRoutes.welcome,
        name: 'welcome',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: WelcomeWizardPage()),
      ),
      // ===== FIRST-RUN ONBOARDING (root navigator) =====
      GoRoute(
        path: AppRoutes.firstRun,
        name: 'first-run',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: FirstRunScreen()),
      ),
      // ===== SETUP / FULLSCREEN MODAL ROUTES (root navigator) =====
      GoRoute(
        path: AppRoutes.controllerSetupWizard,
        name: 'controller-setup-wizard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(fullscreenDialog: true, child: const ControllerSetupWizard()),
      ),
      GoRoute(
        path: AppRoutes.wifiConnect,
        name: 'wifi-connect',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(fullscreenDialog: true, child: const WledManualSetup()),
      ),
      GoRoute(
        path: AppRoutes.deviceSetup,
        name: 'device-setup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: DeviceSetupPage()),
      ),
      GoRoute(
        path: AppRoutes.editPattern,
        name: 'edit-pattern',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final pattern = state.extra as EditablePattern?;
          return MaterialPage(child: EditPatternScreen(initialPattern: pattern));
        },
      ),
      GoRoute(
        path: AppRoutes.luminaAI,
        name: 'lumina-ai',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: LuminaAIScreen()),
      ),
      GoRoute(
        path: AppRoutes.autopilotSchedule,
        name: 'autopilot-schedule',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final initialDate = state.extra as DateTime?;
          return MaterialPage(
            fullscreenDialog: true,
            child: AutopilotScheduleScreen(initialDate: initialDate),
          );
        },
      ),
      GoRoute(
        path: AppRoutes.designStudio,
        name: 'design-studio',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: AIDesignStudioScreen()),
      ),
      GoRoute(
        path: AppRoutes.myDesigns,
        name: 'my-designs',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const NoTransitionPage(child: MyDesignsScreen()),
      ),
      GoRoute(
        path: AppRoutes.rooflineEditor,
        name: 'roofline-editor',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: RooflineEditorScreen()),
      ),
      GoRoute(
        path: AppRoutes.segmentSetup,
        name: 'segment-setup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: SegmentSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.rooflineSetupWizard,
        name: 'roofline-setup-wizard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: RooflineSetupWizard()),
      ),
      // ===== INSTALLER / MEDIA / ADMIN (root navigator) =====
      GoRoute(
        path: AppRoutes.installerLanding,
        name: 'installer-landing',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerLandingScreen()),
      ),
      GoRoute(
        path: AppRoutes.installerPin,
        name: 'installer-pin',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerPinScreen()),
      ),
      GoRoute(
        path: AppRoutes.installerWizard,
        name: 'installer-wizard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerSetupWizard()),
      ),
      GoRoute(
        path: AppRoutes.mediaLanding,
        name: 'media-landing',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaLandingScreen()),
      ),
      GoRoute(
        path: AppRoutes.mediaAccessCode,
        name: 'media-access-code',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaAccessCodeScreen()),
      ),
      GoRoute(
        path: AppRoutes.mediaDashboard,
        name: 'media-dashboard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaDashboardScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminPin,
        name: 'admin-pin',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: AdminPinScreen()),
      ),
      GoRoute(
        path: AppRoutes.adminDashboard,
        name: 'admin-dashboard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: AdminDashboardScreen()),
      ),

      // ===== STATEFUL SHELL ROUTE (persistent bottom nav) =====
      StatefulShellRoute.indexedStack(
        parentNavigatorKey: _rootNavigatorKey,
        builder: (context, state, navigationShell) {
          return MainScaffold(navigationShell: navigationShell);
        },
        branches: [
          // ── Branch 0: HOME ──
          StatefulShellBranch(
            navigatorKey: _homeNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.dashboard,
                name: 'dashboard',
                pageBuilder: (context, state) => const NoTransitionPage(child: WledDashboardPage()),
              ),
            ],
          ),
          // ── Branch 1: SCHEDULE ──
          StatefulShellBranch(
            navigatorKey: _scheduleNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.schedule,
                name: 'schedule',
                pageBuilder: (context, state) => const NoTransitionPage(child: MySchedulePage()),
              ),
            ],
          ),
          // ── Branch 2: EXPLORE ──
          // All sub-routes nested under /explore so context.go() keeps the
          // shell visible and back-navigation (pop) works naturally.
          // Literal child paths (library, scenes) MUST come before :categoryId
          // to prevent the wildcard from matching "library" or "scenes".
          StatefulShellBranch(
            navigatorKey: _exploreNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.explore,
                name: 'explore',
                pageBuilder: (context, state) => const NoTransitionPage(child: ExplorePatternsScreen()),
                routes: [
                  // /explore/library/:nodeId — library node browser
                  GoRoute(
                    path: 'library/:nodeId',
                    name: 'library-node',
                    parentNavigatorKey: _exploreNavigatorKey,
                    pageBuilder: (context, state) {
                      final nodeId = state.pathParameters['nodeId']!;
                      final extra = state.extra;
                      String? nodeName;
                      Color? parentAccent;
                      List<Color>? parentGradient;
                      if (extra is Map) {
                        if (extra['name'] is String) nodeName = extra['name'] as String;
                        if (extra['accentColor'] is int) {
                          parentAccent = Color(extra['accentColor'] as int);
                        }
                        if (extra['gradient0'] is int && extra['gradient1'] is int) {
                          parentGradient = [
                            Color(extra['gradient0'] as int),
                            Color(extra['gradient1'] as int),
                          ];
                        }
                      } else if (extra is LibraryNode) {
                        nodeName = extra.name;
                      }
                      return _exploreFadeSlide(
                        state: state,
                        child: LibraryBrowserScreen(
                          nodeId: nodeId,
                          nodeName: nodeName,
                          parentAccent: parentAccent,
                          parentGradient: parentGradient,
                        ),
                      );
                    },
                  ),
                  // /explore/scenes — saved scenes list
                  GoRoute(
                    path: 'scenes',
                    name: 'my-scenes',
                    parentNavigatorKey: _exploreNavigatorKey,
                    pageBuilder: (context, state) => _exploreFadeSlide(state: state, child: const MyScenesScreen()),
                  ),
                  // /explore/:categoryId — pattern category detail (wildcard LAST)
                  GoRoute(
                    path: ':categoryId',
                    name: 'pattern-category',
                    parentNavigatorKey: _exploreNavigatorKey,
                    pageBuilder: (context, state) {
                      final id = state.pathParameters['categoryId']!;
                      final extra = state.extra;
                      String? name;
                      if (extra is Map && extra['name'] is String) {
                        name = extra['name'] as String;
                      } else if (extra is PatternCategory) {
                        name = extra.name;
                      }
                      return _exploreFadeSlide(state: state, child: CategoryDetailScreen(categoryId: id, categoryName: name));
                    },
                    routes: [
                      // /explore/:categoryId/sub/:subId
                      GoRoute(
                        path: 'sub/:subId',
                        name: 'pattern-subcategory',
                        parentNavigatorKey: _exploreNavigatorKey,
                        pageBuilder: (context, state) {
                          final categoryId = state.pathParameters['categoryId']!;
                          final subId = state.pathParameters['subId']!;
                          String? displayName;
                          final extra = state.extra;
                          if (extra is Map && extra['name'] is String) displayName = extra['name'] as String;
                          return _exploreFadeSlide(state: state, child: ThemeSelectionScreen(categoryId: categoryId, subCategoryId: subId, subCategoryName: displayName));
                        },
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
          // ── Branch 3: SYSTEM ──
          StatefulShellBranch(
            navigatorKey: _systemNavigatorKey,
            routes: [
              GoRoute(
                path: AppRoutes.settings,
                name: 'settings',
                pageBuilder: (context, state) => const NoTransitionPage(child: SettingsPage()),
                routes: [
                  GoRoute(
                    path: 'system',
                    name: 'settings-system',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: SystemManagementScreen()),
                  ),
                  GoRoute(
                    path: 'controllers',
                    name: 'controllers-settings',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: ManageControllersPage()),
                  ),
                  GoRoute(
                    path: 'profile',
                    name: 'profile',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: UserProfileScreen()),
                    routes: [
                      GoRoute(
                        path: 'edit',
                        name: 'profile-edit',
                        parentNavigatorKey: _systemNavigatorKey,
                        pageBuilder: (context, state) => const NoTransitionPage(child: EditProfileScreen()),
                      ),
                    ],
                  ),
                  GoRoute(
                    path: 'security',
                    name: 'security',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: SecuritySettingsScreen()),
                  ),
                  GoRoute(
                    path: 'hardware',
                    name: 'hardware-config',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: HardwareConfigScreen()),
                  ),
                  GoRoute(
                    path: 'help',
                    name: 'help-center',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: HelpCenterScreen()),
                  ),
                  GoRoute(
                    path: 'referrals',
                    name: 'referrals',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: ReferralProgramScreen()),
                  ),
                  GoRoute(
                    path: 'studio',
                    name: 'lumina-studio',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: LuminaStudioScreen()),
                  ),
                  GoRoute(
                    path: 'geofence',
                    name: 'geofence-setup',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: GeofenceSetupScreen()),
                  ),
                  GoRoute(
                    path: 'remote-access',
                    name: 'remote-access',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: RemoteAccessScreen()),
                  ),
                  GoRoute(
                    path: 'voice-assistants',
                    name: 'voice-assistants',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: VoiceAssistantGuideScreen()),
                  ),
                  GoRoute(
                    path: 'properties',
                    name: 'my-properties',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: MyPropertiesScreen()),
                  ),
                  GoRoute(
                    path: 'neighborhood-sync',
                    name: 'neighborhood-sync',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: NeighborhoodSyncScreen()),
                  ),
                  GoRoute(
                    path: 'current-colors',
                    name: 'current-colors',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: CurrentColorsEditorScreen()),
                  ),
                  GoRoute(
                    path: 'users',
                    name: 'sub-users',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: SubUsersScreen()),
                  ),
                  // Note: roofline-editor is intentionally a root-level fullscreen route,
                  // not nested here. See the root GoRoute for /settings/roofline-editor.
                ],
              ),
              // /wled/zones (in System branch)
              GoRoute(
                path: AppRoutes.wledZones,
                name: 'wled-zones',
                pageBuilder: (context, state) => const NoTransitionPage(child: ZoneConfigurationPage()),
              ),
            ],
          ),
        ],
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
  static const String schedule = '/schedule';
  static const String explore = '/explore';
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
  static const String luminaAI = '/lumina-ai';
  static const String designStudio = '/design-studio';
  static const String editPattern = '/edit-pattern';
  static const String myDesigns = '/my-designs';
  static const String myScenes = '/explore/scenes';
  static const String voiceAssistants = '/settings/voice-assistants';
  static const String myProperties = '/settings/properties';
  static const String rooflineEditor = '/settings/roofline-editor';
  static const String segmentSetup = '/segment-setup';
  static const String rooflineSetupWizard = '/roofline-setup-wizard';
  static const String currentColors = '/settings/current-colors';
  // Installer mode routes
  static const String installerLanding = '/installer';
  static const String installerPin = '/installer/pin';
  static const String installerWizard = '/installer/wizard';
  // Media mode routes
  static const String mediaLanding = '/media';
  static const String mediaAccessCode = '/media/code';
  static const String mediaDashboard = '/media/dashboard';
  // Admin management routes
  static const String adminPin = '/admin/pin';
  static const String adminDashboard = '/admin/dashboard';
  // Neighborhood sync
  static const String neighborhoodSync = '/settings/neighborhood-sync';
  // Library hierarchy routes (nested under /explore for persistent nav bar)
  static const String libraryNode = '/explore/library/:nodeId';
  // Installation access control routes
  static const String linkAccount = '/link-account';
  static const String joinWithCode = '/join-with-code';
  static const String systemDeactivated = '/system-deactivated';
  static const String subUsers = '/settings/users';
  static const String autopilotSchedule = '/autopilot-schedule';
  // Demo experience routes
  static const String demoCode = '/demo-code';
  static const String demoWelcome = '/demo';
  static const String demoProfile = '/demo/profile';
  static const String demoPhoto = '/demo/photo';
  static const String demoRoofline = '/demo/roofline';
  static const String demoPatterns = '/demo/patterns';
  static const String demoSchedule = '/demo/schedule';
  static const String demoExplore = '/demo/explore';
  static const String demoLumina = '/demo/lumina';
  static const String demoComplete = '/demo/complete';
  // First-run onboarding (post-installer handoff)
  static const String firstRun = '/first-run';
}
