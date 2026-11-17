// lib/config/firebase_options_staging.dart
//
// Firebase options for the STAGING project, nex-gen-lumina-22751, used only
// by a build made with --dart-define=LUMINA_ENV=staging (lumina_env.dart).
//
// Written by hand, NOT by the FlutterFire CLI, so that the production
// lib/firebase_options.dart is never regenerated or edited. Do not run
// `flutterfire configure` to fill this in.
//
// iOS ONLY. Staging is the separate iPhone app "Lumina Staging"
// (com.nexgenled.command.staging). There is no staging Android or web app:
// a staging build on either refuses to start (see [forPlatform]).
//
// FILLED IN SO FAR (read with the Firebase CLI, 2026-11-17):
//   projectId          nex-gen-lumina-22751
//   messagingSenderId  431625047151 (the staging project number)
//   storageBucket      the default bucket name for a project created after
//                      Oct 2024. Confirm it once Storage is enabled
//                      (checklist step F6).
//
// STILL TO FILL IN: apiKey and appId. They exist only after the iOS app is
// registered in the staging project (checklist step F5). Both come from that
// app's GoogleService-Info.plist: API_KEY and GOOGLE_APP_ID. The plist itself
// is NOT added to the Xcode project; only these two strings are copied here.
//
// While any value still starts with the placeholder prefix, a staging build
// refuses to start (lumina_env.dart preflightStagingOptions) and the
// Codemagic staging workflow stops before it builds anything.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform;

class StagingFirebaseOptions {
  StagingFirebaseOptions._();

  /// The staging options for this platform. Throws [UnsupportedError] off
  /// iOS; the startup check turns that into a refusal to start.
  static FirebaseOptions forPlatform({
    required bool isWeb,
    required TargetPlatform platform,
  }) {
    if (isWeb) {
      throw UnsupportedError(
        'Staging has no web app. Staging builds are iOS only.',
      );
    }
    if (platform == TargetPlatform.iOS) return ios;
    throw UnsupportedError(
      'Staging has no ${platform.name} app. Staging builds are iOS only.',
    );
  }

  static const FirebaseOptions ios = FirebaseOptions(
    apiKey: 'REPLACE_ME_STAGING_IOS_API_KEY',
    appId: 'REPLACE_ME_STAGING_IOS_GOOGLE_APP_ID',
    messagingSenderId: '431625047151',
    projectId: 'nex-gen-lumina-22751',
    storageBucket: 'nex-gen-lumina-22751.firebasestorage.app',
    iosBundleId: 'com.nexgenled.command.staging',
  );
}
