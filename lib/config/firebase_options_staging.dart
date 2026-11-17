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
// WHERE THE VALUES CAME FROM (2026-11-17, read-only, staging project only):
// the iOS app "Lumina Staging" (registered in checklist step F5), read with
// `firebase apps:sdkconfig IOS 1:431625047151:ios:551ebf5c641337eccb919a
// --project nex-gen-lumina-22751`. Every field was checked against that
// config: apiKey = API_KEY, appId = GOOGLE_APP_ID, messagingSenderId =
// GCM_SENDER_ID, projectId, storageBucket (the default bucket, owner decision
// 2026-11-17; created in step F6) and iosBundleId = BUNDLE_ID. The plist
// itself is NOT added to the Xcode project; only these strings are copied.
//
// The apiKey is committed here like production's (owner decision D4,
// 2026-11-17), restricted to this bundle id and to the APIs the app uses
// (checklist step F7, REQUIRED).
//
// If a value is ever put back to a placeholder, a staging build refuses to
// start (lumina_env.dart preflightStagingOptions) and the Codemagic staging
// workflow stops before it builds anything.

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
    apiKey: 'AIzaSyCQRc6w-GH0EGbeh-tLJIbWzVMcyXKwZXQ',
    appId: '1:431625047151:ios:551ebf5c641337eccb919a',
    messagingSenderId: '431625047151',
    projectId: 'nex-gen-lumina-22751',
    storageBucket: 'nex-gen-lumina-22751.firebasestorage.app',
    iosBundleId: 'com.nexgenled.command.staging',
  );
}
