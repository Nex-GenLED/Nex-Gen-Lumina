import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

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
import 'package:nexgen_command/features/design/design_studio_screen.dart';
import 'package:nexgen_command/features/design_studio/screens/ai_design_studio_screen.dart';
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
/// Helper to create an unlinked user profile for new Firebase Auth users.
Future<void> _createUnlinkedUserProfile(User user) async {
  try {
    await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
      'id': user.uid,
      'email': user.email ?? '',
      'display_name': user.displayName ?? user.email?.split('@').first ?? 'User',
      'photo_url': user.photoURL,
      'owner_id': user.uid,
      'created_at': FieldValue.serverTimestamp(),
      'updated_at': FieldValue.serverTimestamp(),
      'installation_role': 'unlinked',
      'welcome_completed': false,
    }, SetOptions(merge: true));
    debugPrint('Created unlinked user profile for ${user.uid}');
  } catch (e) {
    debugPrint('Error creating unlinked user profile: $e');
  }
}

class AppRouter {
  static final _authListenable = _AuthStateListenable();

  static final GoRouter router = GoRouter(
    initialLocation: AppRoutes.login,
    // Refresh route when auth state changes
    refreshListenable: _authListenable,
    // Redirect based on authentication state and installation access
    redirect: (context, state) async {
      final user = FirebaseAuth.instance.currentUser;
      final isLoggedIn = user != null;

      // Define route categories
      final isAuthRoute = state.matchedLocation == AppRoutes.login ||
          state.matchedLocation == AppRoutes.signUp ||
          state.matchedLocation == AppRoutes.forgotPassword;

      final isLinkRoute = state.matchedLocation == AppRoutes.linkAccount ||
          state.matchedLocation == AppRoutes.joinWithCode;

      final isInstallerRoute = state.matchedLocation.startsWith('/installer') ||
          state.matchedLocation.startsWith('/admin');

      // If user is not logged in
      if (!isLoggedIn) {
        // Allow auth routes and welcome wizard
        if (isAuthRoute || state.matchedLocation == AppRoutes.welcome) {
          return null;
        }
        return AppRoutes.login;
      }

      // User is logged in
      // If trying to access auth routes, redirect to dashboard (or link-account if unlinked)
      if (isAuthRoute) {
        // Check if user has installation access
        try {
          final userDoc = await FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .get();

          if (userDoc.exists) {
            final data = userDoc.data()!;
            final role = data['installation_role'] as String?;
            final installationId = data['installation_id'] as String?;

            // Unlinked users go to link-account
            // DEV BYPASS: Skip link-account for testing (remove before production)
            const devBypassLinkAccount = true;
            if (!devBypassLinkAccount && (role == null || role == 'unlinked')) {
              return AppRoutes.linkAccount;
            }

            // Installers and admins don't need an installation
            if (role == 'installer' || role == 'admin') {
              return AppRoutes.dashboard;
            }

            // Primary and subUser need an installation
            // DEV BYPASS: Skip installation check for testing
            if (!devBypassLinkAccount && installationId == null) {
              return AppRoutes.linkAccount;
            }
          } else {
            // User exists in Auth but not Firestore - create unlinked profile
            await _createUnlinkedUserProfile(user);
            return AppRoutes.linkAccount;
          }
        } catch (e) {
          debugPrint('Redirect: Error checking user status: $e');
        }
        return AppRoutes.dashboard;
      }

      // Allow link routes and installer routes without further checks
      if (isLinkRoute || isInstallerRoute || state.matchedLocation == AppRoutes.welcome) {
        return null;
      }

      // For protected routes (dashboard, settings, etc.), verify installation access
      // DEV BYPASS: Skip all installation checks for testing
      const devBypassInstallation = true;
      if (devBypassInstallation) {
        return null; // Allow access to all routes
      }

      try {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(user.uid)
            .get();

        if (!userDoc.exists) {
          await _createUnlinkedUserProfile(user);
          return AppRoutes.linkAccount;
        }

        final data = userDoc.data()!;
        final role = data['installation_role'] as String?;
        final installationId = data['installation_id'] as String?;

        // Unlinked users must go to link-account
        if (role == null || role == 'unlinked') {
          return AppRoutes.linkAccount;
        }

        // Installers and admins have unrestricted access
        if (role == 'installer' || role == 'admin') {
          return null;
        }

        // Primary and subUser need a valid installation
        if (installationId == null) {
          return AppRoutes.linkAccount;
        }

        // Check if installation is still active
        final installDoc = await FirebaseFirestore.instance
            .collection('installations')
            .doc(installationId)
            .get();

        if (installDoc.exists && installDoc.data()?['is_active'] == false) {
          // Installation deactivated - show error (for now, redirect to link-account)
          return AppRoutes.linkAccount;
        }
      } catch (e) {
        debugPrint('Redirect: Error checking installation access: $e');
        // On error, allow access (fail open for better UX, security handled by Firestore rules)
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
      // Installation access control routes
      GoRoute(
        path: AppRoutes.linkAccount,
        name: 'link-account',
        pageBuilder: (context, state) => const NoTransitionPage(child: LinkAccountScreen()),
      ),
      GoRoute(
        path: AppRoutes.joinWithCode,
        name: 'join-with-code',
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: JoinWithCodeScreen(),
        ),
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
      // Library hierarchy routes
      GoRoute(
        path: AppRoutes.libraryRoot,
        name: 'library-root',
        pageBuilder: (context, state) => const NoTransitionPage(child: LibraryBrowserScreen()),
      ),
      GoRoute(
        path: AppRoutes.libraryNode,
        name: 'library-node',
        pageBuilder: (context, state) {
          final nodeId = state.pathParameters['nodeId']!;
          final extra = state.extra;
          String? nodeName;
          if (extra is Map && extra['name'] is String) {
            nodeName = extra['name'] as String;
          } else if (extra is LibraryNode) {
            nodeName = extra.name;
          }
          return NoTransitionPage(child: LibraryBrowserScreen(nodeId: nodeId, nodeName: nodeName));
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
        path: AppRoutes.subUsers,
        name: 'sub-users',
        pageBuilder: (context, state) => const NoTransitionPage(child: SubUsersScreen()),
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
        pageBuilder: (context, state) => const NoTransitionPage(child: AIDesignStudioScreen()),
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
        path: AppRoutes.installerLanding,
        name: 'installer-landing',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerLandingScreen()),
      ),
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
      // Media mode routes
      GoRoute(
        path: AppRoutes.mediaLanding,
        name: 'media-landing',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaLandingScreen()),
      ),
      GoRoute(
        path: AppRoutes.mediaAccessCode,
        name: 'media-access-code',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaAccessCodeScreen()),
      ),
      GoRoute(
        path: AppRoutes.mediaDashboard,
        name: 'media-dashboard',
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: MediaDashboardScreen()),
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
  // Library hierarchy routes
  static const String libraryRoot = '/library';
  static const String libraryNode = '/library/:nodeId';
  // Installation access control routes
  static const String linkAccount = '/link-account';
  static const String joinWithCode = '/join-with-code';
  static const String systemDeactivated = '/system-deactivated';
  static const String subUsers = '/settings/users';
}
