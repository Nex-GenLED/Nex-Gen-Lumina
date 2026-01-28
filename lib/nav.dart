import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';

// Feature imports
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/signup_page.dart';
import 'package:nexgen_command/features/auth/forgot_password_page.dart';
import 'package:nexgen_command/features/permissions/welcome_wizard.dart';
import 'package:nexgen_command/features/discovery/discovery_page.dart';
import 'package:nexgen_command/features/dashboard/main_scaffold.dart';
import 'package:nexgen_command/features/ble/device_setup_page.dart';
import 'package:nexgen_command/features/ble/controller_setup_wizard.dart';
import 'package:nexgen_command/features/ble/wled_manual_setup.dart';
import 'package:nexgen_command/features/wled/pattern_library_pages.dart';
import 'package:nexgen_command/features/wled/pattern_models.dart';
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
import 'package:nexgen_command/features/design/design_studio_screen.dart';
import 'package:nexgen_command/features/design/my_designs_screen.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/scenes/my_scenes_screen.dart';
import 'package:nexgen_command/features/voice/voice_assistant_guide_screen.dart';
import 'package:nexgen_command/features/properties/my_properties_screen.dart';
import 'package:nexgen_command/features/installer/installer_pin_screen.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/admin/admin_dashboard_screen.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';

/// Listenable that notifies when Firebase Auth state changes.
/// Used to trigger GoRouter redirect checks.
class _AuthStateListenable extends ChangeNotifier {
  _AuthStateListenable() {
    FirebaseAuth.instance.authStateChanges().listen((_) {
      notifyListeners();
    });
  }
}

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
        path: AppRoutes.neighborhoodSync,
        name: 'neighborhood-sync',
        pageBuilder: (context, state) => const NoTransitionPage(child: NeighborhoodSyncScreen()),
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
  // Neighborhood sync
  static const String neighborhoodSync = '/settings/neighborhood-sync';
}
