// The LUMINA_ENV switch and the fail-closed startup check
// (lib/config/lumina_env.dart).
//
// This suite runs with NO --dart-define, exactly like every build before the
// switch existed, so the "default" group below is the proof that a build made
// without the flag is production: same project, same Functions URL, same
// options objects.

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/config/firebase_bootstrap.dart';
import 'package:nexgen_command/config/firebase_options_staging.dart';
import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/firebase_options.dart';

/// What a filled-in staging file will look like (values invented).
const _goodStaging = FirebaseOptions(
  apiKey: 'staging-test-key',
  appId: '1:431625047151:ios:0000000000000000000000',
  messagingSenderId: '431625047151',
  projectId: 'nex-gen-lumina-22751',
  storageBucket: 'nex-gen-lumina-22751.firebasestorage.app',
  iosBundleId: 'com.nexgenled.command.staging',
);

FirebaseOptions _with(FirebaseOptions o,
        {String? apiKey,
        String? appId,
        String? sender,
        String? projectId,
        String? bucket,
        String? bundle}) =>
    o.copyWith(
      apiKey: apiKey,
      appId: appId,
      messagingSenderId: sender,
      projectId: projectId,
      storageBucket: bucket,
      iosBundleId: bundle,
    );

void main() {
  group('default build (no LUMINA_ENV) is production, unchanged', () {
    test('the define is empty and resolves to prod', () {
      expect(kLuminaEnvDefine, '');
      expect(luminaEnv, LuminaEnv.prod);
      expect(kIsProdBuild, isTrue);
      expect(kIsStagingBuild, isFalse);
      expect(kLuminaEnvMarker, 'LUMINA_ENV_MARKER=');
    });

    test('Functions base URL is the literal the three call sites carried', () {
      // Exactly the string formerly hard-coded in neighborhood_service.dart,
      // sync_event_background_worker.dart and
      // game_day_autopilot_background_worker.dart.
      expect(
        kCloudFunctionsBaseUrl,
        'https://us-central1-icrt6menwsv2d8all8oijs021b06s5.cloudfunctions.net',
      );
      expect(kCloudFunctionsBaseUrl, cloudFunctionsBaseUrlFor(luminaEnv!));
    });

    test('the production constant matches lib/firebase_options.dart', () {
      expect(DefaultFirebaseOptions.ios.projectId, kProductionProjectId);
      expect(DefaultFirebaseOptions.android.projectId, kProductionProjectId);
      expect(DefaultFirebaseOptions.web.projectId, kProductionProjectId);
      expect(DefaultFirebaseOptions.ios.iosBundleId, kProductionBundleId);
      expect(DefaultFirebaseOptions.ios.messagingSenderId,
          kProductionProjectNumber);
    });

    test('a correctly configured production launch is allowed', () {
      expect(
        evaluateEnvGuard(define: '', loadedProjectId: kProductionProjectId)
            .allowed,
        isTrue,
      );
    });
  });

  group('parseLuminaEnv', () {
    test('accepts only "", "prod" and "staging"', () {
      expect(parseLuminaEnv(''), LuminaEnv.prod);
      expect(parseLuminaEnv('prod'), LuminaEnv.prod);
      expect(parseLuminaEnv('staging'), LuminaEnv.staging);
    });

    test('anything else is unrecognised, never quietly production', () {
      for (final raw in [
        'Staging',
        'STAGING',
        'stage',
        'stagin',
        ' staging',
        'staging ',
        'production',
        'Prod',
        'dev',
      ]) {
        expect(parseLuminaEnv(raw), isNull, reason: raw);
      }
    });
  });

  group('cloudFunctionsBaseUrlFor', () {
    test('staging points at the staging project only', () {
      expect(
        cloudFunctionsBaseUrlFor(LuminaEnv.staging),
        'https://us-central1-nex-gen-lumina-22751.cloudfunctions.net',
      );
      expect(cloudFunctionsBaseUrlFor(LuminaEnv.staging),
          isNot(contains(kProductionProjectId)));
    });
  });

  group('evaluateEnvGuard — production build', () {
    test('production project: start', () {
      expect(
          evaluateEnvGuard(define: 'prod', loadedProjectId: kProductionProjectId)
              .allowed,
          isTrue);
    });

    test('NO Firebase app: start degraded, exactly as before the guard', () {
      // main.dart's both-init-attempts-failed path deliberately still runs
      // the app; the default build must keep that.
      expect(evaluateEnvGuard(define: '', loadedProjectId: null).allowed,
          isTrue);
    });

    test('staging project loaded into a production build: refuse', () {
      final v =
          evaluateEnvGuard(define: '', loadedProjectId: kStagingProjectId);
      expect(v.allowed, isFalse);
      expect(v.reason, contains('production build'));
      expect(v.reason, contains(kStagingProjectId));
    });

    test('any other project: refuse', () {
      expect(
          evaluateEnvGuard(define: '', loadedProjectId: 'some-other-project')
              .allowed,
          isFalse);
    });
  });

  group('evaluateEnvGuard — staging build', () {
    test('staging project: start', () {
      expect(
        evaluateEnvGuard(define: 'staging', loadedProjectId: kStagingProjectId)
            .allowed,
        isTrue,
      );
    });

    test('PRODUCTION project loaded into a staging build: refuse', () {
      final v = evaluateEnvGuard(
          define: 'staging', loadedProjectId: kProductionProjectId);
      expect(v.allowed, isFalse);
      expect(v.reason, contains('staging build'));
      expect(v.reason, contains(kProductionProjectId));
    });

    test('no Firebase app: refuse (cannot be verified)', () {
      final v = evaluateEnvGuard(define: 'staging', loadedProjectId: null);
      expect(v.allowed, isFalse);
      expect(v.reason, contains('did not start'));
    });

    test('any other project: refuse', () {
      expect(
          evaluateEnvGuard(define: 'staging', loadedProjectId: 'other')
              .allowed,
          isFalse);
    });
  });

  group('evaluateEnvGuard — unrecognised define', () {
    test('refuses whatever project is loaded', () {
      for (final loaded in [null, kProductionProjectId, kStagingProjectId]) {
        final v = evaluateEnvGuard(define: 'stagin', loadedProjectId: loaded);
        expect(v.allowed, isFalse, reason: '$loaded');
        expect(v.reason, contains('"stagin"'));
      }
    });
  });

  group('staging options file', () {
    test('names the staging project, sender and bundle id', () {
      const o = StagingFirebaseOptions.ios;
      expect(o.projectId, kStagingProjectId);
      expect(o.messagingSenderId, '431625047151');
      expect(o.iosBundleId, kStagingBundleId);
      expect(o.storageBucket, 'nex-gen-lumina-22751.firebasestorage.app');
    });

    test('carries no production value at all', () {
      const o = StagingFirebaseOptions.ios;
      for (final v in [
        o.apiKey,
        o.appId,
        o.messagingSenderId,
        o.projectId,
        o.storageBucket,
        o.iosBundleId,
      ]) {
        expect(v, isNot(contains(kProductionProjectId)));
        expect(v, isNot(contains(kProductionProjectNumber)));
      }
      expect(productionFirebaseApiKeys(), isNot(contains(o.apiKey)));
      expect(o.iosBundleId, isNot(kProductionBundleId));
    });

    test('is iOS only: Android and web throw (and so refuse to start)', () {
      expect(
        () => StagingFirebaseOptions.forPlatform(
            isWeb: false, platform: TargetPlatform.android),
        throwsUnsupportedError,
      );
      expect(
        () => StagingFirebaseOptions.forPlatform(
            isWeb: true, platform: TargetPlatform.iOS),
        throwsUnsupportedError,
      );
      expect(
        StagingFirebaseOptions.forPlatform(
            isWeb: false, platform: TargetPlatform.iOS),
        same(StagingFirebaseOptions.ios),
      );
    });
  });

  group('preflightStagingOptions', () {
    final prodKeys = productionFirebaseApiKeys();

    test('the committed placeholders are refused, naming the fields', () {
      final r = preflightStagingOptions(StagingFirebaseOptions.ios,
          productionApiKeys: prodKeys);
      expect(r, isNotNull);
      expect(r, contains('apiKey'));
      expect(r, contains('appId'));
      expect(r, contains('STAGING_SETUP_CHECKLIST'));
    });

    test('filled-in staging values pass', () {
      expect(
          preflightStagingOptions(_goodStaging, productionApiKeys: prodKeys),
          isNull);
    });

    test('a production API key pasted in is refused', () {
      for (final key in prodKeys) {
        final r = preflightStagingOptions(_with(_goodStaging, apiKey: key),
            productionApiKeys: prodKeys);
        expect(r, contains('apiKey'));
      }
    });

    test('a production appId pasted in is refused', () {
      final r = preflightStagingOptions(
          _with(_goodStaging, appId: DefaultFirebaseOptions.ios.appId),
          productionApiKeys: prodKeys);
      expect(r, contains('appId'));
    });

    test('the production project, sender, bucket or bundle id are refused', () {
      expect(
        preflightStagingOptions(
            _with(_goodStaging, projectId: kProductionProjectId),
            productionApiKeys: prodKeys),
        contains('instead of $kStagingProjectId'),
      );
      expect(
        preflightStagingOptions(
            _with(_goodStaging, sender: kProductionProjectNumber),
            productionApiKeys: prodKeys),
        contains('messagingSenderId'),
      );
      expect(
        preflightStagingOptions(
            _with(_goodStaging,
                bucket: DefaultFirebaseOptions.ios.storageBucket),
            productionApiKeys: prodKeys),
        contains('storageBucket'),
      );
      expect(
        preflightStagingOptions(
            _with(_goodStaging, bundle: kProductionBundleId),
            productionApiKeys: prodKeys),
        contains('iosBundleId'),
      );
    });

    test('some other bundle id is refused', () {
      expect(
        preflightStagingOptions(_with(_goodStaging, bundle: 'com.example.x'),
            productionApiKeys: prodKeys),
        contains(kStagingBundleId),
      );
    });
  });
}
