// lib/config/environment_widgets.dart
//
// The visible side of the environment switch (lumina_env.dart):
//   * the STAGING ribbon over every screen of a staging build, and
//   * the screen shown instead of the app when the startup check refuses.

import 'package:flutter/material.dart';

import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/shared/accessibility/text_scale_clamp.dart';

/// Ribbon colour: deep orange, nothing like the app's cyan accent.
const Color kStagingBannerColor = Color(0xFFE65100);

/// `MaterialApp.builder` for [env].
///
/// Production returns [TextScaleClamp.appBuilder] itself — the very function
/// main.dart passed before — so the default build's widget tree is unchanged.
TransitionBuilder luminaAppBuilderFor(LuminaEnv? env) =>
    env == LuminaEnv.staging ? stagingAppBuilder : TextScaleClamp.appBuilder;

/// The production builder wrapped in the STAGING ribbon.
Widget stagingAppBuilder(BuildContext context, Widget? child) =>
    StagingBanner(child: TextScaleClamp.appBuilder(context, child));

/// A corner ribbon reading STAGING.
///
/// Wraps the app's Navigator, so it paints over every route, dialog and
/// bottom sheet. It only paints: taps go through to whatever is under it.
class StagingBanner extends StatelessWidget {
  const StagingBanner({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Banner(
      message: 'STAGING',
      location: BannerLocation.topStart,
      color: kStagingBannerColor,
      textDirection: TextDirection.ltr,
      layoutDirection: TextDirection.ltr,
      child: child,
    );
  }
}

/// Shown INSTEAD of the app when the startup environment check refuses.
///
/// Uses no Firebase, no providers and no router: once the check has failed,
/// the loaded Firebase project is the wrong one, and nothing may use it.
class EnvironmentRefusedApp extends StatelessWidget {
  const EnvironmentRefusedApp({super.key, required this.reason});

  final String reason;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lumina',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF121212),
      ),
      builder: kIsStagingBuild ? stagingAppBuilder : null,
      home: Scaffold(
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.block, size: 48, color: kStagingBannerColor),
                const SizedBox(height: 16),
                const Text(
                  'This build cannot start',
                  style: TextStyle(fontSize: 22, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 12),
                Text(reason, style: const TextStyle(fontSize: 15)),
                const SizedBox(height: 12),
                const Text(
                  'Lumina stopped before signing in or loading any data. '
                  'Install the right build for this environment.',
                  style: TextStyle(fontSize: 15),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
