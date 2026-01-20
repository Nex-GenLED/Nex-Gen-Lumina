import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/firebase_options.dart';
import 'package:nexgen_command/theme.dart';
import 'package:nexgen_command/nav.dart';
import 'package:nexgen_command/services/notifications_service.dart';

/// Main entry point for the application
///
/// This sets up:
/// - Firebase initialization
/// - go_router navigation
/// - Material 3 theming with light/dark modes
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
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
  // Initialize local notifications (no prompts on web)
  await NotificationsService.init();
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

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

