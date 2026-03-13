import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/firebase_options.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/app_providers.dart';
import 'package:nexgen_command/features/autopilot/autopilot_providers.dart';
import 'package:nexgen_command/features/autopilot/background_learning_service.dart';
import 'package:nexgen_command/features/schedule/schedule_providers.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_notification_service.dart';
import 'package:nexgen_command/features/sports_alerts/services/sports_background_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/services/reviewer_seed_service.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest.dart' as tz;

/// One-time Firestore persistence cache clear for iOS crash recovery.
///
/// If a previous session queued a Firestore write containing a data type the
/// native iOS SDK cannot serialize (e.g. Color objects, raw DateTime, typed
/// lists), the SDK crashes with SIGABRT every launch while trying to flush
/// the offline queue. Clearing persistence once breaks the crash loop.
///
/// Version-gated via SharedPreferences so it only runs once per recovery.
const _kFirestoreCacheClearVersion = 2; // bump to re-trigger after a new fix

Future<void> _clearFirestoreCacheIfNeeded() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final lastClear = prefs.getInt('firestore_cache_clear_version') ?? 0;
    if (lastClear >= _kFirestoreCacheClearVersion) return;

    debugPrint('🔧 Clearing Firestore persistence cache (recovery v$_kFirestoreCacheClearVersion)');
    await FirebaseFirestore.instance.clearPersistence();
    await prefs.setInt('firestore_cache_clear_version', _kFirestoreCacheClearVersion);
    debugPrint('✅ Firestore cache cleared');
  } catch (e) {
    debugPrint('⚠️ Firestore cache clear failed (non-fatal): $e');
  }
}

/// Main entry point for the application
///
/// This sets up:
/// - Firebase initialization
/// - go_router navigation
/// - Material 3 theming with light/dark modes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

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

  // iOS crash recovery: clear Firestore persistence cache if a previous session
  // queued a write with an unsupported data type. The native iOS Firestore SDK
  // (FSTUserDataReader) crashes with SIGABRT on startup when it encounters
  // invalid types in the offline queue — this one-time flush prevents the
  // crash-on-launch loop. Gated by a version flag so it only runs once.
  if (!kIsWeb && Platform.isIOS) {
    await _clearFirestoreCacheIfNeeded();
  }

  // Seed reviewer account for App Store review (no-op if already exists)
  ReviewerSeedService.ensureReviewerAccount().catchError((e) {
    debugPrint('Reviewer seed failed: $e');
  });

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

      // Refresh WLED connection immediately
      try {
        ref.read(wledStateProvider.notifier).refreshConnection();
      } catch (e) {
        debugPrint('WLED refresh on resume failed: $e');
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
    // Auto-regenerate autopilot schedule when it becomes stale
    ref.listen<bool>(needsScheduleRegenerationProvider, (prev, next) {
      if (next == true) {
        BackgroundLearningService.runAutopilotRegenIfNeeded(ref);
      }
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

