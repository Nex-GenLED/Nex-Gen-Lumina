import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
// Feature imports
import 'package:nexgen_command/features/auth/login_page.dart';
import 'package:nexgen_command/features/auth/signup_page.dart';
import 'package:nexgen_command/features/auth/forgot_password_page.dart';
import 'package:nexgen_command/features/auth/forced_password_reset_screen.dart';
import 'package:nexgen_command/features/auth/link_account_screen.dart';
import 'package:nexgen_command/features/auth/join_with_code_screen.dart';
import 'package:nexgen_command/features/users/sub_users_screen.dart';
import 'package:nexgen_command/features/whites/preferred_white_selection_page.dart';
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
import 'package:nexgen_command/features/audio/audio_mode_page.dart';
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
import 'package:nexgen_command/features/site/bridge_setup_screen.dart';
import 'package:nexgen_command/features/site/roofline_editor_screen.dart';
import 'package:nexgen_command/features/geofence/geofence_setup_screen.dart';
import 'package:nexgen_command/features/wled/edit_pattern_screen.dart';
import 'package:nexgen_command/features/wled/editable_pattern_model.dart';
import 'package:nexgen_command/features/design/screens/ai_design_studio_screen.dart';
import 'package:nexgen_command/features/design/my_designs_screen.dart';
import 'package:nexgen_command/features/design/segment_setup_screen.dart';
import 'package:nexgen_command/features/design/roofline_setup_wizard.dart';
import 'package:nexgen_command/features/voice/voice_assistant_guide_screen.dart';
import 'package:nexgen_command/features/properties/my_properties_screen.dart';
import 'package:nexgen_command/features/auth/staff_pin_screen.dart';
import 'package:nexgen_command/features/installer/installer_pin_screen.dart';
import 'package:nexgen_command/features/installer/installer_setup_wizard.dart';
import 'package:nexgen_command/features/installer/installer_landing_screen.dart';
import 'package:nexgen_command/features/installer/media_landing_screen.dart';
import 'package:nexgen_command/features/installer/media_access_code_screen.dart';
import 'package:nexgen_command/features/installer/admin/admin_dashboard_screen.dart';
import 'package:nexgen_command/features/installer/admin/dealer_dashboard_screen.dart';
import 'package:nexgen_command/features/installer/admin/brand_library_admin_screen.dart';
import 'package:nexgen_command/features/sports_alerts/ui/sports_alerts_screen.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_pin_screen.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_dashboard_screen.dart';
import 'package:nexgen_command/features/corporate/screens/dealer_detail_screen.dart';
import 'package:nexgen_command/features/corporate/screens/corporate_job_detail_screen.dart';
import 'package:nexgen_command/features/installer/media_dashboard_screen.dart';
import 'package:nexgen_command/features/sales/screens/sales_pin_screen.dart';
import 'package:nexgen_command/features/sales/screens/sales_landing_screen.dart';
import 'package:nexgen_command/features/sales/screens/prospect_info_screen.dart';
import 'package:nexgen_command/features/sales/screens/zone_builder_screen.dart';
import 'package:nexgen_command/features/sales/screens/visit_review_screen.dart';
import 'package:nexgen_command/features/sales/screens/estimate_preview_screen.dart';
import 'package:nexgen_command/features/sales/screens/customer_signature_screen.dart';
import 'package:nexgen_command/features/sales/screens/sales_jobs_screen.dart';
import 'package:nexgen_command/features/sales/screens/job_detail_screen.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/wizard_step1_home_photo.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/wizard_step2_controller.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/wizard_step3_channels.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/wizard_step4_injections.dart';
import 'package:nexgen_command/features/sales/screens/estimate_wizard/wizard_step5_summary.dart';
import 'package:nexgen_command/features/sales/screens/day1_queue_screen.dart';
import 'package:nexgen_command/features/sales/screens/day1_blueprint_screen.dart';
import 'package:nexgen_command/features/sales/screens/day2_queue_screen.dart';
import 'package:nexgen_command/features/sales/screens/day2_blueprint_screen.dart';
import 'package:nexgen_command/features/sales/screens/day2_wrap_up_screen.dart';
import 'package:nexgen_command/features/referrals/screens/payout_approval_screen.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_screen.dart';
import 'package:nexgen_command/features/game_day/game_day_screen.dart';
import 'package:nexgen_command/features/ai/lumina_ai_screen.dart';
import 'package:nexgen_command/features/autopilot/autopilot_weekly_preview.dart';
import 'package:nexgen_command/features/autopilot/screens/first_week_reveal_screen.dart';
import 'package:nexgen_command/features/autopilot/screens/autopilot_calendar_screen.dart';
import 'package:nexgen_command/features/zones/screens/zone_setup_screen.dart';
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
// Commercial mode imports
import 'package:nexgen_command/screens/commercial/CommercialHomeScreen.dart';
import 'package:nexgen_command/screens/commercial/onboarding/commercial_onboarding_wizard.dart';
import 'package:nexgen_command/features/commercial/brand/brand_search_screen.dart';
import 'package:nexgen_command/features/commercial/brand/brand_setup_screen.dart';
import 'package:nexgen_command/features/commercial/brand/brand_correction_review_screen.dart';
import 'package:nexgen_command/features/commercial/events/events_screen.dart';
import 'package:nexgen_command/features/commercial/events/create_event_screen.dart';

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

  /// Global scaffold messenger key — allows showing snackbars from
  /// non-widget code (e.g., Riverpod notifiers, services).
  static final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();
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
      GoRoute(
        path: AppRoutes.forcedPasswordReset,
        name: 'forced-password-reset',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const NoTransitionPage(child: ForcedPasswordResetScreen()),
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
      // ===== DEMO REDIRECTS (placeholder routes → main app sections) =====
      GoRoute(
        path: AppRoutes.demoPatterns,
        redirect: (context, state) => AppRoutes.explore,
      ),
      GoRoute(
        path: AppRoutes.demoSchedule,
        redirect: (context, state) => AppRoutes.schedule,
      ),
      GoRoute(
        path: AppRoutes.demoExplore,
        redirect: (context, state) => AppRoutes.explore,
      ),
      GoRoute(
        path: AppRoutes.demoLumina,
        redirect: (context, state) => AppRoutes.dashboard,
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
      // ===== AUTOPILOT REVEAL + CALENDAR (root navigator) =====
      GoRoute(
        path: AppRoutes.firstWeekReveal,
        name: 'first-week-reveal',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: FirstWeekRevealScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.autopilotCalendar,
        name: 'autopilot-calendar',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: AutopilotCalendarScreen(),
        ),
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
      // ===== STAFF PIN (root navigator) =====
      // Unified PIN entry — reachable only via the hidden 5-tap gesture
      // on the Lumina logo on the login screen. Routes the user to
      // Corporate / Sales / Installer mode based on which PIN store
      // matches. The legacy single-purpose PIN routes
      // (/installer/pin, /sales/pin, /corporate/pin) remain registered
      // below for now, but nothing on the login screen navigates to
      // them directly anymore.
      GoRoute(
        path: AppRoutes.staffPin,
        name: 'staff-pin',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: StaffPinScreen()),
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
        path: AppRoutes.zoneSetup,
        name: 'zone-setup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(child: ZoneSetupScreen()),
      ),
      GoRoute(
        path: AppRoutes.installerWizard,
        name: 'installer-wizard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: InstallerSetupWizard()),
      ),

      // ── Sales Mode ────────────────────────────────────────────
      GoRoute(
        path: AppRoutes.salesPin,
        name: 'sales-pin',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: SalesPinScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesLanding,
        name: 'sales-landing',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: SalesLandingScreen()),
      ),
      // Sales wizard screens
      GoRoute(
        path: AppRoutes.salesProspect,
        name: 'sales-prospect',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: ProspectInfoScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesZones,
        name: 'sales-zones',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: ZoneBuilderScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesReview,
        name: 'sales-review',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: VisitReviewScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesEstimate,
        name: 'sales-estimate',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: EstimatePreviewScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesEstimateSign,
        name: 'sales-estimate-sign',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: CustomerSignatureScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesJobs,
        name: 'sales-jobs',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: SalesJobsScreen()),
      ),
      GoRoute(
        path: AppRoutes.salesJobDetail,
        name: 'sales-job-detail',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: JobDetailScreen(jobId: state.pathParameters['jobId'] ?? ''),
        ),
      ),
      // Estimate Wizard (5 steps) — parallel to the legacy zone builder.
      GoRoute(
        path: AppRoutes.salesWizardStep1,
        name: 'sales-wizard-step1',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: WizardStep1HomePhoto(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.salesWizardStep2,
        name: 'sales-wizard-step2',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: WizardStep2Controller(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.salesWizardStep3,
        name: 'sales-wizard-step3',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: WizardStep3Channels(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.salesWizardStep4,
        name: 'sales-wizard-step4',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: WizardStep4Injections(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.salesWizardStep5,
        name: 'sales-wizard-step5',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: WizardStep5Summary(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      // Day 1 dispatch — electrician queue + per-job blueprint stub.
      // Both screens are role-gated behind installerModeActiveProvider
      // and bounce to AppRoutes.installerPin if no session is active.
      GoRoute(
        path: AppRoutes.day1Queue,
        name: 'day1-queue',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: Day1QueueScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.day1JobBlueprint,
        name: 'day1-job-blueprint',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: Day1BlueprintScreen(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      // Day 2 install dispatch — queue + per-job blueprint + wrap-up.
      // All three screens are role-gated behind installerModeActiveProvider
      // (the queue checks; the blueprint and wrap-up trust the queue gate).
      GoRoute(
        path: AppRoutes.day2Queue,
        name: 'day2-queue',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: Day2QueueScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.day2JobBlueprint,
        name: 'day2-job-blueprint',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: Day2BlueprintScreen(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
      ),
      GoRoute(
        path: AppRoutes.day2WrapUp,
        name: 'day2-wrap-up',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          fullscreenDialog: true,
          child: Day2WrapUpScreen(
            jobId: state.pathParameters['jobId'] ?? '',
          ),
        ),
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
      GoRoute(
        path: AppRoutes.dealerDashboard,
        name: 'dealer-dashboard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final dealerCode = state.uri.queryParameters['dealerCode'];
          return MaterialPage(
            fullscreenDialog: true,
            child: DealerDashboardScreen(dealerCodeOverride: dealerCode),
          );
        },
      ),
      // Corporate-admin brand library management (Part 9). Both screens
      // gate access in-screen via isUserRoleAdminProvider — the
      // /brand_library and /brand_library_corrections firestore rules
      // are the security boundary; the in-screen check is UX.
      GoRoute(
        path: AppRoutes.adminBrandLibrary,
        name: 'admin-brand-library',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: BrandLibraryAdminScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.adminBrandCorrections,
        name: 'admin-brand-corrections',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: BrandCorrectionReviewScreen(),
        ),
      ),
      GoRoute(
        path: AppRoutes.dealerPayouts,
        name: 'dealer-payouts',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(fullscreenDialog: true, child: PayoutApprovalScreen()),
      ),

      // ===== CORPORATE MODE ROUTES (root navigator) =====
      GoRoute(
        path: AppRoutes.corporatePin,
        name: 'corporate-pin',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(fullscreenDialog: true, child: CorporatePinScreen()),
      ),
      GoRoute(
        path: AppRoutes.corporateDashboard,
        name: 'corporate-dashboard',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: CorporateDashboardScreen(),
        ),
      ),
      GoRoute(
        path: '${AppRoutes.corporateDealerDetailBase}/:dealerCode',
        name: 'corporate-dealer-detail',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final code = state.pathParameters['dealerCode'] ?? '';
          final name = state.extra is String ? state.extra as String : null;
          return MaterialPage(
            child: DealerDetailScreen(
              dealerCode: code,
              dealerName: name,
            ),
          );
        },
      ),
      GoRoute(
        path: '${AppRoutes.corporateJobDetailBase}/:jobId',
        name: 'corporate-job-detail',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) {
          final id = state.pathParameters['jobId'] ?? '';
          return MaterialPage(child: CorporateJobDetailScreen(jobId: id));
        },
      ),

      // ===== COMMERCIAL MODE ROUTES (root navigator) =====
      GoRoute(
        path: AppRoutes.commercialHome,
        name: 'commercial-home',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(child: CommercialHomeScreen()),
      ),
      GoRoute(
        path: AppRoutes.commercialOnboarding,
        name: 'commercial-onboarding',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(fullscreenDialog: true, child: CommercialOnboardingWizard()),
      ),
      // Brand library — search, setup, and corporate correction review.
      // Setup accepts either a BrandLibraryEntry (from search → pre-selected)
      // or a Map {preSelected, isEditing} (from the Brand tab edit button)
      // via state.extra. The corrections route's admin gate is enforced
      // in-screen against user_role == 'admin' (the firestore rule on
      // /brand_library_corrections.update enforces the same predicate).
      GoRoute(
        path: AppRoutes.commercialBrandSearch,
        name: 'commercial-brand-search',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(child: BrandSearchScreen()),
      ),
      GoRoute(
        path: AppRoutes.commercialBrandSetup,
        name: 'commercial-brand-setup',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => MaterialPage(
          child: BrandSetupScreen.fromExtra(state.extra),
        ),
      ),
      GoRoute(
        path: AppRoutes.commercialBrandCorrections,
        name: 'commercial-brand-corrections',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: BrandCorrectionReviewScreen(),
        ),
      ),
      // Sales & Events. The list screen is reachable from the
      // commercial home screen; the create screen is pushed from the
      // FAB on the list and from the empty-state CTA.
      GoRoute(
        path: AppRoutes.commercialEvents,
        name: 'commercial-events',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) =>
            const MaterialPage(child: EventsScreen()),
      ),
      GoRoute(
        path: AppRoutes.commercialEventsCreate,
        name: 'commercial-events-create',
        parentNavigatorKey: _rootNavigatorKey,
        pageBuilder: (context, state) => const MaterialPage(
          fullscreenDialog: true,
          child: CreateEventScreen(),
        ),
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
                routes: [
                  // /dashboard/game-day — Game Day hub. Nested here so the
                  // bottom nav bar stays visible and back navigation pops
                  // to the dashboard via the home branch navigator.
                  GoRoute(
                    path: 'game-day',
                    name: 'game-day',
                    parentNavigatorKey: _homeNavigatorKey,
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: GameDayScreen()),
                  ),
                  // /dashboard/audio-reactive — Audio Mode. Nested here for
                  // the same reason as Game Day: keep the nav bar visible
                  // and provide normal back navigation in the home branch.
                  GoRoute(
                    path: 'audio-reactive',
                    name: 'audio-reactive',
                    parentNavigatorKey: _homeNavigatorKey,
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: AudioModePage()),
                  ),
                  // /dashboard/design-studio — AI Design Studio (home variant).
                  // Design Studio is registered under each branch so the
                  // bottom nav bar persists no matter which tab the user
                  // launched it from. Use designStudioPathFor(context) to
                  // resolve the right branch path.
                  GoRoute(
                    path: 'design-studio',
                    name: 'home-design-studio',
                    parentNavigatorKey: _homeNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(
                        child: AIDesignStudioScreen()),
                  ),
                  // /dashboard/my-designs — saved designs library. Nested
                  // here so its "create new design" push lands inside the
                  // home branch and the nav bar stays visible.
                  GoRoute(
                    path: 'my-designs',
                    name: 'my-designs',
                    parentNavigatorKey: _homeNavigatorKey,
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: MyDesignsScreen()),
                  ),
                  // /dashboard/neighborhood-sync — Neighborhood Sync hub.
                  // Pushed from the home dashboard with the nav bar visible
                  // and a back button (added in the screen).
                  GoRoute(
                    path: 'neighborhood-sync',
                    name: 'home-neighborhood-sync',
                    parentNavigatorKey: _homeNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(
                        child: NeighborhoodSyncScreen()),
                  ),
                ],
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
                  // /explore/design-studio — Design Studio (explore variant).
                  // Literal path; must come before the :categoryId wildcard.
                  GoRoute(
                    path: 'design-studio',
                    name: 'explore-design-studio',
                    parentNavigatorKey: _exploreNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(
                        child: AIDesignStudioScreen()),
                  ),
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
                    path: 'bridge-setup',
                    name: 'bridge-setup',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: BridgeSetupScreen()),
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
                  GoRoute(
                    path: 'my-whites',
                    name: 'my-whites',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(child: PreferredWhiteSelectionPage()),
                  ),
                  // Sports Alerts — registered as a proper system-shell
                  // child route (was previously pushed via raw Navigator,
                  // which left the screen unreachable-to-back-out-of when
                  // the user switched bottom-nav branches and came back).
                  // The screen now also has an explicit BackButton in its
                  // GlassAppBar — see sports_alerts_screen.dart.
                  GoRoute(
                    path: 'sports-alerts',
                    name: 'sports-alerts',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) =>
                        const NoTransitionPage(child: SportsAlertsScreen()),
                  ),
                  // /settings/design-studio — Design Studio (system variant).
                  // Registered here so callers from the System branch (e.g.
                  // zone configuration) keep the bottom nav bar visible.
                  GoRoute(
                    path: 'design-studio',
                    name: 'system-design-studio',
                    parentNavigatorKey: _systemNavigatorKey,
                    pageBuilder: (context, state) => const NoTransitionPage(
                        child: AIDesignStudioScreen()),
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
  static const String forcedPasswordReset = '/forced-password-reset';
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
  static const String bridgeSetup = '/settings/bridge-setup';
  static const String luminaAI = '/lumina-ai';
  // Design Studio is registered as a nested route under each shell branch
  // so the bottom nav bar persists no matter which tab launched it.
  // Use [designStudioPathFor] to pick the right one based on current location.
  static const String homeDesignStudio = '/dashboard/design-studio';
  static const String exploreDesignStudio = '/explore/design-studio';
  static const String systemDesignStudio = '/settings/design-studio';
  // Default = home variant. Branch-aware callers should use the helper.
  static const String designStudio = homeDesignStudio;
  static const String editPattern = '/edit-pattern';
  // My Designs nested under home branch so its "create new" push lands
  // inside the same branch with the bottom nav bar still visible.
  static const String myDesigns = '/dashboard/my-designs';
  static const String voiceAssistants = '/settings/voice-assistants';
  static const String sportsAlerts = '/settings/sports-alerts';
  static const String myProperties = '/settings/properties';
  static const String rooflineEditor = '/settings/roofline-editor';
  static const String segmentSetup = '/segment-setup';
  static const String rooflineSetupWizard = '/roofline-setup-wizard';
  static const String currentColors = '/settings/current-colors';
  // Unified staff PIN entry — reachable only via the hidden 5-tap
  // gesture on the Lumina logo on the login screen. Routes the user to
  // Corporate / Sales / Installer mode based on which PIN store matches
  // (see lib/features/auth/staff_pin_screen.dart for the routing order).
  static const String staffPin = '/staff/pin';
  // Installer mode routes
  static const String installerLanding = '/installer';
  static const String installerPin = '/installer/pin';
  static const String installerWizard = '/installer/wizard';
  // Sales mode routes
  static const String salesPin = '/sales/pin';
  static const String salesLanding = '/sales';
  static const String salesProspect = '/sales/visit/prospect';
  static const String salesZones = '/sales/visit/zones';
  static const String salesReview = '/sales/visit/review';
  static const String salesEstimate = '/sales/estimate';
  static const String salesEstimateSign = '/sales/estimate/sign';
  static const String salesJobs = '/sales/jobs';
  static const String salesJobDetail = '/sales/jobs/:jobId';
  // Estimate wizard — :jobId pulls the in-progress SalesJob from
  // activeJobProvider via EstimateWizardNotifier.
  static const String salesWizardStep1 = '/sales/jobs/:jobId/wizard/home-photo';
  static const String salesWizardStep2 = '/sales/jobs/:jobId/wizard/controller';
  static const String salesWizardStep3 = '/sales/jobs/:jobId/wizard/channels';
  static const String salesWizardStep4 = '/sales/jobs/:jobId/wizard/injections';
  static const String salesWizardStep5 = '/sales/jobs/:jobId/wizard/summary';
  // Day 1 electrician dispatch — gated behind installerModeActiveProvider.
  static const String day1Queue = '/day1/queue';
  static const String day1JobBlueprint = '/day1/jobs/:jobId/blueprint';
  // Day 2 install dispatch — gated behind installerModeActiveProvider.
  static const String day2Queue = '/day2/queue';
  static const String day2JobBlueprint = '/day2/jobs/:jobId/blueprint';
  static const String day2WrapUp = '/day2/jobs/:jobId/wrap-up';
  // Media mode routes
  static const String mediaLanding = '/media';
  static const String mediaAccessCode = '/media/code';
  static const String mediaDashboard = '/media/dashboard';
  // Admin management routes
  static const String adminPin = '/admin/pin';
  static const String adminDashboard = '/admin/dashboard';
  // Corporate-admin brand library management (Part 9)
  static const String adminBrandLibrary = '/admin/brand-library';
  static const String adminBrandCorrections = '/admin/brand-corrections';
  // Dealer dashboard
  static const String dealerDashboard = '/dealer/dashboard';

  // ===== CORPORATE MODE =====
  static const String corporatePin = '/corporate/pin';
  static const String corporateDashboard = '/corporate/dashboard';
  /// Base path for the dealer detail screen — full route is
  /// `/corporate/dealers/:dealerCode` (declared with the path parameter
  /// in the GoRouter config above).
  static const String corporateDealerDetailBase = '/corporate/dealers';
  /// Base path for the corporate read-only job detail screen — full
  /// route is `/corporate/jobs/:jobId`.
  static const String corporateJobDetailBase = '/corporate/jobs';
  // Dealer payout approval
  static const String dealerPayouts = '/dealer/payouts';
  // Neighborhood sync — nested under /dashboard so the dashboard button
  // can context.push() it without switching tabs and the bottom nav bar
  // stays visible.
  static const String neighborhoodSync = '/dashboard/neighborhood-sync';
  // Game Day hub — nested under /dashboard so the bottom nav bar persists
  // and back navigation pops within the home branch.
  static const String gameDay = '/dashboard/game-day';
  // Library hierarchy routes (nested under /explore for persistent nav bar)
  static const String libraryNode = '/explore/library/:nodeId';
  // Installation access control routes
  static const String linkAccount = '/link-account';
  static const String joinWithCode = '/join-with-code';
  static const String systemDeactivated = '/system-deactivated';
  static const String subUsers = '/settings/users';
  static const String myWhites = '/settings/my-whites';
  static const String autopilotSchedule = '/autopilot-schedule';
  // Audio Mode — nested under /dashboard so the bottom nav bar persists.
  static const String audioReactive = '/dashboard/audio-reactive';
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
  // Autopilot generation reveal + unified calendar
  static const String firstWeekReveal = '/autopilot/first-week';
  static const String autopilotCalendar = '/autopilot/calendar';

  static const String zoneSetup = '/installer/zone-setup';
  // Commercial mode routes
  static const String commercialHome = '/commercial';
  static const String commercialOnboarding = '/commercial/onboarding';
  // Brand library routes (admin-gated for corrections)
  static const String commercialBrandSearch = '/commercial/brand/search';
  static const String commercialBrandSetup = '/commercial/brand/setup';
  static const String commercialBrandCorrections =
      '/commercial/brand/corrections';
  // Sales & Events routes
  static const String commercialEvents = '/commercial/events';
  static const String commercialEventsCreate = '/commercial/events/create';
}

/// Returns the Design Studio path nested under the current shell branch so
/// `context.push(designStudioPathFor(context))` keeps the bottom nav bar
/// visible no matter which tab the caller lives in. Falls back to the home
/// branch path for callers outside any known branch (e.g. root-level routes
/// or AI commands without a branch context).
String designStudioPathFor(BuildContext context) {
  final loc = GoRouterState.of(context).matchedLocation;
  if (loc.startsWith('/explore')) return AppRoutes.exploreDesignStudio;
  if (loc.startsWith('/settings')) return AppRoutes.systemDesignStudio;
  return AppRoutes.homeDesignStudio;
}
