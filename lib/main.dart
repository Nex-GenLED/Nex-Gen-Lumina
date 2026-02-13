import 'dart:io';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/firebase_options.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/notifications_service.dart';
import 'package:nexgen_command/services/encryption_service.dart';
import 'package:nexgen_command/features/autopilot/background_learning_service.dart';
import 'package:nexgen_command/features/wled/wled_providers.dart';
import 'package:nexgen_command/features/voice/voice_providers.dart';

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
  // SECURITY: Initialize encryption service for sensitive data
  await EncryptionService.initialize();

  // Initialize local notifications (no prompts on web)
  await NotificationsService.init();

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Voice services will be initialized after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeVoiceServices();
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
    return MaterialApp.router(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,

      // Theme configuration: Nex‑Gen Premium Dark
      theme: nexGenPremiumDarkTheme,
      darkTheme: nexGenPremiumDarkTheme,
      themeMode: ThemeMode.dark,

      // Router configuration
      routerConfig: AppRouter.router,
    );
  }
}

