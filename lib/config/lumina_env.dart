// lib/config/lumina_env.dart
//
// Which Firebase project this build talks to. Chosen at COMPILE time:
//
//   (no define)                   -> production   (every build before this file)
//   --dart-define=LUMINA_ENV=prod -> production
//   --dart-define=LUMINA_ENV=staging -> staging (Firebase nex-gen-lumina-22751,
//                                    bundle id com.nexgenled.command.staging)
//   any other value               -> the app refuses to start
//
// Compile-time on purpose. `String.fromEnvironment` is a const, so every
// isolate (the Android background service included) sees the same value and
// nothing at runtime can flip it.
//
// The startup check that uses this lives in firebase_bootstrap.dart. The
// owner's setup steps are in docs/staging/STAGING_SETUP_CHECKLIST.md.
//
// LEAK GUARD: test/config/production_identifier_leak_test.dart fails if the
// production project id, a Cloud Functions or Cloud Run host, or a Firebase
// API key appears anywhere under lib/ or ios/ outside the files it allows. A new
// production endpoint goes HERE, switched on the environment, never inline.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;

/// The raw `LUMINA_ENV` define. Empty when the build passed none.
const String kLuminaEnvDefine = String.fromEnvironment('LUMINA_ENV');

/// Folded at compile time, so the built binary carries the literal
/// `LUMINA_ENV_MARKER=staging` only when the define really reached the Dart
/// build. The Codemagic staging workflow greps the IPA for it before upload.
const String kLuminaEnvMarker = 'LUMINA_ENV_MARKER=$kLuminaEnvDefine';

/// Production Firebase project (what lib/firebase_options.dart points at).
const String kProductionProjectId = 'icrt6menwsv2d8all8oijs021b06s5';

/// Staging Firebase project.
const String kStagingProjectId = 'nex-gen-lumina-22751';

/// iOS bundle id of the staging app ("Lumina Staging").
const String kStagingBundleId = 'com.nexgenled.command.staging';

/// The production iOS bundle id. Staging options must never carry it.
const String kProductionBundleId = 'com.nexgenled.command';

/// Production Firebase project number (= messagingSenderId, and the middle
/// field of every production appId).
const String kProductionProjectNumber = '1036323013258';

enum LuminaEnv { prod, staging }

/// Parses the define. `null` means "not recognised" and the app refuses to
/// start: a typo such as `stagin` must never quietly build production.
LuminaEnv? parseLuminaEnv(String raw) {
  switch (raw) {
    case '':
    case 'prod':
      return LuminaEnv.prod;
    case 'staging':
      return LuminaEnv.staging;
    default:
      return null;
  }
}

/// True for a production build, including the default (no define).
const bool kIsProdBuild = kLuminaEnvDefine == '' || kLuminaEnvDefine == 'prod';

/// True only for `--dart-define=LUMINA_ENV=staging`.
const bool kIsStagingBuild = kLuminaEnvDefine == 'staging';

/// The environment of THIS build; `null` when the define is not recognised.
final LuminaEnv? luminaEnv = parseLuminaEnv(kLuminaEnvDefine);

/// Whether this build may offer Alexa / Google Home account linking.
///
/// FALSE in staging (owner decision D3, 2026-11-17). The Alexa skill and the
/// Google Home action are the PRODUCTION ones, and their account linking runs
/// on production Cloud Functions, so linking from staging would link a
/// production account. AlexaService and GoogleHomeService refuse to start a
/// link-out when this is false, and any linking card must not render.
/// (Today no card renders anywhere: they were removed under FACTS T-VA1.)
const bool kVoiceAssistantLinkingEnabled = kIsProdBuild;

/// The Firebase project a build for [env] must have loaded.
String expectedProjectIdFor(LuminaEnv env) =>
    env == LuminaEnv.staging ? kStagingProjectId : kProductionProjectId;

/// Base URL of the HTTP-triggered Cloud Functions (us-central1) for [env].
String cloudFunctionsBaseUrlFor(LuminaEnv env) =>
    'https://us-central1-${expectedProjectIdFor(env)}.cloudfunctions.net';

/// Base URL of the HTTP-triggered Cloud Functions for THIS build.
///
/// A const so the existing `const _functionsBaseUrl = …` sites stay const.
/// Production resolves to exactly the literal those sites carried before.
/// An unrecognised define resolves to a reserved `.invalid` host that never
/// resolves — the app refuses to start in that case anyway, and a background
/// isolate must not reach either real project.
const String kCloudFunctionsBaseUrl = kIsStagingBuild
    ? 'https://us-central1-$kStagingProjectId.cloudfunctions.net'
    : kIsProdBuild
        ? 'https://us-central1-$kProductionProjectId.cloudfunctions.net'
        : 'https://lumina-env-not-recognised.invalid';

/// Result of the startup environment check.
class EnvGuardVerdict {
  const EnvGuardVerdict.allow() : allowed = true, reason = null;
  const EnvGuardVerdict.refuse(String this.reason) : allowed = false;

  final bool allowed;

  /// Why the app refused to start. Null when [allowed].
  final String? reason;

  @override
  String toString() =>
      allowed ? 'EnvGuardVerdict.allow' : 'EnvGuardVerdict.refuse($reason)';
}

/// Decides, AFTER Firebase init was attempted, whether the app may start.
///
/// [loadedProjectId] is the default Firebase app's projectId, or null when no
/// Firebase app exists.
///
/// * Unrecognised define: refuse.
/// * Staging: start only when the staging project is loaded. No Firebase app,
///   or any other project, refuses.
/// * Production: a non-production project refuses. NO Firebase app at all is
///   ALLOWED — that is today's deliberate degraded start when both init
///   attempts fail (see main.dart), and the default build must behave exactly
///   as it did before this check existed.
EnvGuardVerdict evaluateEnvGuard({
  required String define,
  required String? loadedProjectId,
}) {
  final env = parseLuminaEnv(define);
  if (env == null) {
    return EnvGuardVerdict.refuse(
      'LUMINA_ENV="$define" is not a known environment. Build with '
      '--dart-define=LUMINA_ENV=staging, or with no LUMINA_ENV for production.',
    );
  }
  switch (env) {
    case LuminaEnv.prod:
      if (loadedProjectId == null || loadedProjectId == kProductionProjectId) {
        return const EnvGuardVerdict.allow();
      }
      return EnvGuardVerdict.refuse(
        'This is a production build, but it loaded Firebase project '
        '"$loadedProjectId" instead of $kProductionProjectId.',
      );
    case LuminaEnv.staging:
      if (loadedProjectId == kStagingProjectId) {
        return const EnvGuardVerdict.allow();
      }
      if (loadedProjectId == null) {
        return const EnvGuardVerdict.refuse(
          'This is a staging build, and Firebase did not start, so the '
          'project could not be checked.',
        );
      }
      return EnvGuardVerdict.refuse(
        'This is a staging build, but it loaded Firebase project '
        '"$loadedProjectId" instead of $kStagingProjectId.',
      );
  }
}

/// Marker that every unfilled value in firebase_options_staging.dart starts
/// with.
const String kStagingPlaceholderPrefix = 'REPLACE_ME';

/// Checks staging [options] BEFORE they are handed to Firebase.
///
/// Runs first because a malformed appId makes the native iOS SDK raise while
/// configuring, which no Dart catch can stop. Also rejects any production
/// identifier copied into the staging file. [productionApiKeys] are the keys
/// from lib/firebase_options.dart.
///
/// Returns null when the options may be used, otherwise the reason.
String? preflightStagingOptions(
  FirebaseOptions options, {
  required Iterable<String> productionApiKeys,
}) {
  final fields = <String, String?>{
    'apiKey': options.apiKey,
    'appId': options.appId,
    'messagingSenderId': options.messagingSenderId,
    'projectId': options.projectId,
    'storageBucket': options.storageBucket,
    'iosBundleId': options.iosBundleId,
  };
  final unfilled = [
    for (final e in fields.entries)
      if ((e.value ?? '').startsWith(kStagingPlaceholderPrefix)) e.key,
  ];
  if (unfilled.isNotEmpty) {
    return 'Staging Firebase settings are not filled in yet '
        '(${unfilled.join(', ')}). See docs/staging/STAGING_SETUP_CHECKLIST.md.';
  }
  if (options.projectId != kStagingProjectId) {
    return 'Staging Firebase settings name project "${options.projectId}" '
        'instead of $kStagingProjectId.';
  }
  final carriesProduction = <String>[
    if (productionApiKeys.contains(options.apiKey)) 'apiKey',
    if (options.appId.contains(kProductionProjectNumber)) 'appId',
    if (options.messagingSenderId == kProductionProjectNumber)
      'messagingSenderId',
    if ((options.storageBucket ?? '').contains(kProductionProjectId))
      'storageBucket',
    if (options.iosBundleId == kProductionBundleId) 'iosBundleId',
  ];
  if (carriesProduction.isNotEmpty) {
    return 'Staging Firebase settings carry production values '
        '(${carriesProduction.join(', ')}).';
  }
  if (options.iosBundleId != null && options.iosBundleId != kStagingBundleId) {
    return 'Staging Firebase settings name bundle id "${options.iosBundleId}" '
        'instead of $kStagingBundleId.';
  }
  return null;
}
