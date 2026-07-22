import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/firebase_options.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/services/connection_method_migration.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/background_learning_service.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_notification_service.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_providers.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_sync_engine.dart';
import 'package:nexgen_command/features/sports_alerts/services/sports_background_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/bridge_health_service.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:timezone/data/latest.dart' as tz;

/// Main entry point for the application
///
/// This sets up:
/// - Firebase initialization
/// - go_router navigation
/// - Material 3 theming with light/dark modes
/// Re-entry guard: if the sink itself throws (e.g. Firestore unreachable),
/// we must not recurse into ourselves and feedback-loop.
bool _errorSinkActive = false;

/// Global uncaught-error sink. #84 hardening.
///
/// Without this the app has no error reporting surface — Tyler can't read
/// Crashlytics (no Mac) and TestFlight crash logs aren't accessible from
/// the device. Writes a capped record to /users/{uid}/debug_errors/{autoId}
/// so the next uncaught error in a TestFlight build is readable from the
/// Firestore console.
///
/// Must never throw. Sink failures are swallowed.
Future<void> _reportUncaughtError({
  required Object error,
  required StackTrace? stack,
  required String context,
}) async {
  if (_errorSinkActive) return;
  _errorSinkActive = true;
  try {
    debugPrint('🛑 UNCAUGHT [$context]: $error\n$stack');
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final errStr = error.toString();
    final stackStr = stack?.toString() ?? '';
    const cap = 3000;
    await FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .collection('debug_errors')
        .add({
      'timestamp': FieldValue.serverTimestamp(),
      'context': context,
      'error_type': error.runtimeType.toString(),
      'error': errStr.length > cap ? errStr.substring(0, cap) : errStr,
      'stack': stackStr.length > cap ? stackStr.substring(0, cap) : stackStr,
      'platform': Platform.isIOS
          ? 'ios'
          : Platform.isAndroid
              ? 'android'
              : 'other',
    });
  } catch (_) {
    // Sink must never crash the app. Swallow.
  } finally {
    _errorSinkActive = false;
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Install global error sinks IMMEDIATELY — before anything else can throw.
  // Firestore writes inside the sink fail silently until Firebase init below
  // completes; in the meantime, debugPrint still records (silenced in
  // release, but always running on debug builds).
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details); // keep default console rendering
    _reportUncaughtError(
      error: details.exception,
      stack: details.stack,
      context: 'FlutterError.onError',
    );
  };
  WidgetsBinding.instance.platformDispatcher.onError = (error, stack) {
    _reportUncaughtError(
      error: error,
      stack: stack,
      context: 'PlatformDispatcher.onError',
    );
    return true; // signal handled — don't escalate to the OS
  };

  // Silence all debugPrint output in release builds
  if (kReleaseMode) {
    debugPrint = (String? message, {int? wrapWidth}) {};
  }
  try {
    if (kIsWeb) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    } else {
      // Prefer native configs from google-services.json / GoogleService-Info.plist when present
      await Firebase.initializeApp();
    }
  } catch (e) {
    // Fallback to Dart-side options if native config files are missing or misconfigured
    debugPrint('Firebase.initializeApp() without options failed, falling back: $e');
    await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  }

  // Reviewer seed is now triggered post-login in login_page.dart — writing
  // the profile under the reviewer's actual Firebase Auth UID. Startup-time
  // seeding against a hardcoded UID produced an orphan doc the signed-in
  // reviewer could never read.

  // SECURITY: Initialize encryption service for sensitive data
  await EncryptionService.initialize();

  // Initialize timezone database for autopilot scheduling
  tz.initializeTimeZones();

  // Wire navigator key for notification deep-link navigation
  NotificationsService.navigatorKey = AppRouter.rootNavigatorKey;

  // Initialize local notifications (no prompts on web)
  await NotificationsService.init();

  // Initialize FCM for Neighborhood Sync push notifications (no-op on web)
  if (!kIsWeb) {
    SyncNotificationService().initialize().catchError((e) {
      debugPrint('FCM initialization failed: $e');
    });
  }

  // Register sports alerts background service (Android foreground + iOS BGFetch)
  if (!kIsWeb) {
    initialiseSportsBackgroundService().catchError((e) {
      debugPrint('Sports background service init failed: $e');
    });
  }

  // Initialize background learning service and run startup check
  final learningService = BackgroundLearningService();
  learningService.onAppStartup().catchError((e) {
    debugPrint('Background learning startup failed: $e');
  });

  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends ConsumerStatefulWidget {
  const MyApp({super.key});

  @override
  ConsumerState<MyApp> createState() => _MyAppState();
}

class _MyAppState extends ConsumerState<MyApp> with WidgetsBindingObserver {
  bool _voiceServicesInitialized = false;
  bool _schedulePersistenceChecked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Voice services will be initialized after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVoiceServices();
      // Check for today's game-day items and start monitoring
      BackgroundLearningService.startTodayGameDayMonitoring(ref);
      // One-time bridge health check — triggers the FutureProvider which
      // writes a ping doc and watches for the ESP32 to acknowledge it.
      _runBridgeHealthCheck();
    });
  }

  Future<void> _initializeVoiceServices() async {
    if (_voiceServicesInitialized) return;
    _voiceServicesInitialized = true;

    // Initialize voice assistant services (Siri, deep links)
    if (!kIsWeb) {
      // Touch providers to initialize them
      ref.read(deepLinkServiceProvider);

      if (Platform.isIOS) {
        ref.read(siriShortcutServiceProvider);
        // Donate system shortcuts (power on/off)
        final donateSystem = ref.read(donateSystemShortcutsProvider);
        await donateSystem();
        debugPrint('Siri: System shortcuts donated');
      } else if (Platform.isAndroid) {
        ref.read(androidShortcutServiceProvider);
      }
    }
  }

  /// Kick off the one-time bridge health check by reading the FutureProvider.
  /// The provider handles all Firestore writes, snapshot listening, and logging.
  void _runBridgeHealthCheck() {
    // Reading the provider is enough — Riverpod runs the future on first read.
    // We listen so we can update bridgeReachableProvider with the result.
    ref.listenManual(bridgeHealthProvider, (prev, next) {
      next.whenData((health) {
        if (health == BridgeHealth.alive) {
          ref.read(bridgeReachableProvider.notifier).state = true;
        } else if (health == BridgeHealth.unreachable) {
          ref.read(bridgeReachableProvider.notifier).state = false;
        }
      });
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (state == AppLifecycleState.resumed) {
      debugPrint('🔄 App resumed from background');

      // Re-check network location (local vs remote) so the correct
      // repository (WledService vs CloudRelayRepository) is used.
      refreshConnectivityStatus(ref);

      // Re-run bridge health check so the status indicator reflects
      // current reality, not a stale startup result.
      ref.invalidate(bridgeHealthProvider);

      // Refresh WLED connection immediately
      try {
        ref.read(wledStateProvider.notifier).refreshConnection();
      } catch (e) {
        debugPrint('WLED refresh on resume failed: $e');
      }

      // Neighborhood Sync: returning from background must recover live
      // propagation WITHOUT a full relaunch. Refresh the user's group list
      // (so a sync that STARTED while suspended is detected and auto-tuned
      // by the app-level resolver below) and re-subscribe the command stream
      // (so a design CHANGED while suspended — or a stream that closed in the
      // background — is re-applied to the lights via fireImmediately replay).
      try {
        ref.invalidate(userNeighborhoodsProvider);
        ref.read(neighborhoodSyncEngineProvider).handleAppResume();
      } catch (e) {
        debugPrint('Neighborhood sync resume re-apply failed: $e');
      }

      // App came to foreground - run learning service tasks
      final learningService = BackgroundLearningService();

      // Check if we should run daily maintenance
      if (learningService.shouldRunDaily()) {
        debugPrint('🔄 App resumed - running daily maintenance');
        learningService.runDailyMaintenance().catchError((e) {
          debugPrint('Daily maintenance failed: $e');
        });
      } else {
        // Just check for contextual suggestions
        learningService.onAppStartup().catchError((e) {
          debugPrint('Contextual check failed: $e');
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── Neighborhood Sync: APP-LEVEL listener scope ──────────────────────
    // The sync receive-and-apply listener used to be mounted only by
    // NeighborhoodSyncScreen, so a member not on that screen never applied
    // live design changes (the restart-required bug). Watching the controller
    // here — in the always-mounted root — keeps the listener alive whenever
    // the app is foregrounded, regardless of the active route. The controller
    // returns void and its trigger condition (manuallyActive || iAmParticipating
    // || hasActiveGroup) still gates whether it actually subscribes, so this
    // is inert until the user has real sync involvement.
    ref.watch(syncEngineControllerProvider);

    // Resolve the active group app-wide. activeNeighborhoodIdProvider defaults
    // to null and was only set on the sync screen; the command stream keys off
    // it, so without this an off-screen receiver had nothing to watch. Only
    // ever broadens (never clobbers an explicit on-screen selection) — see
    // resolveAutoActiveGroupId.
    // No fireImmediately: the StreamProvider is still loading at first build,
    // so its initial value arrives as a normal change (outside build) — a
    // fireImmediately callback would mutate activeNeighborhoodIdProvider
    // synchronously during build, which Riverpod disallows.
    ref.listen<AsyncValue<List<NeighborhoodGroup>>>(
      userNeighborhoodsProvider,
      (prev, next) {
        final groups = next.valueOrNull;
        if (groups == null) return;
        final currentId = ref.read(activeNeighborhoodIdProvider);
        final resolved = resolveAutoActiveGroupId(currentId, groups);
        if (resolved != currentId) {
          ref.read(activeNeighborhoodIdProvider.notifier).state = resolved;
        }
      },
    );

    // Auto-regenerate autopilot schedule when it becomes stale
    ref.listen<bool>(needsScheduleRegenerationProvider, (prev, next) {
      if (next == true) {
        BackgroundLearningService.runAutopilotRegenIfNeeded(ref);
      }
    });

    // One-time connection-method backfill — fires when a non-anonymous
    // user signs in. Internal SharedPreferences guard makes the call
    // idempotent across sign-out/sign-in cycles. Errors are swallowed
    // inside the migration so a failure here cannot block app startup
    // or the UI from rendering.
    ref.listen<AsyncValue<User?>>(authStateProvider, (prev, next) {
      next.whenData((user) {
        ConnectionMethodMigration.tryRunForUid(
          uid: user?.uid,
          isAnonymous: user?.isAnonymous ?? true,
          runner: ConnectionMethodMigration.runOnce,
        );
      });
    });

    // Run schedule persistence health check once after auth is ready
    if (!_schedulePersistenceChecked) {
      final user = ref.read(authStateProvider).maybeWhen(
            data: (u) => u,
            orElse: () => null,
          );
      if (user != null) {
        _schedulePersistenceChecked = true;
        Future.microtask(() {
          ref.read(schedulesProvider.notifier).verifyPersistence().catchError((e) {
            debugPrint('Schedule persistence check failed: $e');
          });
        });
      }
    }

    return MaterialApp.router(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,

      // Global scaffold messenger key for showing snackbars from services
      scaffoldMessengerKey: AppRouter.scaffoldMessengerKey,

      // Theme configuration: Nex‑Gen Premium Dark
      theme: nexGenPremiumDarkTheme,
      darkTheme: nexGenPremiumDarkTheme,
      themeMode: ThemeMode.dark,

      // Router configuration
      routerConfig: AppRouter.router,
    );
  }
}

