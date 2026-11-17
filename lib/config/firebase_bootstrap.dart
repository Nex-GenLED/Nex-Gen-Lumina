// lib/config/firebase_bootstrap.dart
//
// Firebase initialisation plus the fail-closed environment check, called once
// from main() before anything else touches Firebase.
//
// PRODUCTION (the default build) runs the SAME sequence main.dart ran before
// this file existed, moved here unchanged so it can be tested: web
// initialises with Dart options; everything else tries the native config
// first and falls back to Dart options; both failing still starts the app.
// Same calls, same order, same 15 s bounds, same breadcrumb strings.
// test/config/firebase_bootstrap_test.dart pins that sequence.
//
// STAGING never takes the native-config path. On Android that path reads
// google-services.json, which is the production project. Staging initialises
// once with the staging Dart options, with no fallback, because the only
// other options in this app are production's.

import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';

import 'package:nexgen_command/config/firebase_options_staging.dart';
import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/firebase_options.dart';

/// Initialises the default Firebase app. `null` means "from the native config
/// files" (google-services.json / GoogleService-Info.plist).
typedef FirebaseInitializer = Future<void> Function(FirebaseOptions? options);

Future<void> _initializeDefaultApp(FirebaseOptions? options) async {
  if (options == null) {
    await Firebase.initializeApp();
  } else {
    await Firebase.initializeApp(options: options);
  }
}

/// projectId of the default Firebase app, or null when there is none.
String? currentFirebaseProjectId() {
  try {
    if (Firebase.apps.isEmpty) return null;
    return Firebase.app().options.projectId;
  } catch (_) {
    return null;
  }
}

FirebaseOptions _productionOptions() => DefaultFirebaseOptions.currentPlatform;

/// The production Firebase API keys. Staging options must not reuse any.
Iterable<String> productionFirebaseApiKeys() => [
      DefaultFirebaseOptions.web.apiKey,
      DefaultFirebaseOptions.android.apiKey,
      DefaultFirebaseOptions.ios.apiKey,
    ];

/// Initialises Firebase for this build and returns whether the app may start.
///
/// Never throws. The defaults are the real implementations; tests inject
/// fakes.
Future<EnvGuardVerdict> bootstrapFirebase({
  required bool isWeb,
  required TargetPlatform platform,
  required void Function(String message) breadcrumb,
  required void Function(Object error, StackTrace stack) onBothFailed,
  String define = kLuminaEnvDefine,
  FirebaseInitializer initialize = _initializeDefaultApp,
  String? Function() loadedProjectId = currentFirebaseProjectId,
  FirebaseOptions Function() productionOptions = _productionOptions,
  FirebaseOptions Function()? stagingOptions,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final env = parseLuminaEnv(define);

  if (env == null) {
    // Not even an attempt: there is no right project to load.
    breadcrumb('firebase:SKIPPED (LUMINA_ENV not recognised)');
    return evaluateEnvGuard(define: define, loadedProjectId: null);
  }

  if (env == LuminaEnv.staging) {
    breadcrumb('firebase:begin ($kLuminaEnvMarker)');
    final FirebaseOptions options;
    try {
      options = (stagingOptions ??
          () => StagingFirebaseOptions.forPlatform(
                isWeb: isWeb,
                platform: platform,
              ))();
    } catch (e) {
      breadcrumb('firebase:staging options unavailable err=$e');
      return EnvGuardVerdict.refuse('$e');
    }
    final String? preflight;
    try {
      preflight = preflightStagingOptions(
        options,
        productionApiKeys: productionFirebaseApiKeys(),
      );
    } catch (e) {
      return EnvGuardVerdict.refuse('Staging settings could not be checked: $e');
    }
    if (preflight != null) {
      breadcrumb('firebase:staging preflight REFUSED');
      return EnvGuardVerdict.refuse(preflight);
    }
    try {
      await initialize(options).timeout(timeout);
      breadcrumb('firebase:ok (staging)');
    } catch (e) {
      breadcrumb('firebase:staging FAILED err=$e');
      return EnvGuardVerdict.refuse('Firebase did not start for staging: $e');
    }
    return evaluateEnvGuard(define: define, loadedProjectId: loadedProjectId());
  }

  // ── PRODUCTION: the pre-existing sequence from main.dart, unchanged. ──
  //
  // GUARDED for exactly the reason documented on the encryption block in
  // main.dart: a step that blocks runApp() must be protected against BOTH
  // failure modes, and a bare try/catch only covers one of them.
  //
  // This block used to catch a throw from the primary attempt and then call
  // the fallback UNGUARDED — no try/catch, no timeout. A throw from that
  // fallback aborted main() before runApp(), producing a permanent splash
  // with no crash dialog: the exact 2.5.10+55 signature described in
  // main.dart's header comment. Both attempts are now bounded and caught.
  //
  // If both fail the app still starts. That is deliberate: a launched app
  // whose Firebase calls error is diagnosable by the user and by us; a
  // process sitting pre-runApp() forever is neither.
  //
  // TIMEOUTS ARE 15s, matching the project-wide network-timeout standard in
  // CLAUDE.md. They were 10s. 10s is short enough to trip on a cold cellular
  // start or a slow DNS resolve and send a perfectly healthy launch down the
  // fallback path (and then into the degraded both-failed branch), which is
  // the same class of false alarm as the "System Offline" bug. A longer bound
  // costs nothing here because the timeout is a backstop against a HANG, not
  // a latency budget — runApp() is unconditional either way.
  breadcrumb('firebase:begin');
  try {
    if (isWeb) {
      await initialize(productionOptions()).timeout(timeout);
    } else {
      // Prefer native configs from google-services.json / GoogleService-Info.plist when present
      await initialize(null).timeout(timeout);
    }
    breadcrumb('firebase:ok');
  } catch (e) {
    // Fallback to Dart-side options if native config files are missing or misconfigured
    debugPrint('Firebase.initializeApp() without options failed, falling back: $e');
    breadcrumb('firebase:primary FAILED, trying fallback err=$e');
    try {
      await initialize(productionOptions()).timeout(timeout);
      breadcrumb('firebase:ok (via fallback)');
    } catch (e2, st2) {
      // Both paths are gone. Continue to runApp anyway — see above.
      breadcrumb('firebase:FAILED BOTH (continuing) err=$e2');
      onBothFailed(e2, st2);
    }
  }
  // New: refuse only when a project was loaded and it is not production
  // (e.g. a staging google-services.json dropped into android/app). No app
  // at all keeps today's degraded start.
  return evaluateEnvGuard(define: define, loadedProjectId: loadedProjectId());
}
