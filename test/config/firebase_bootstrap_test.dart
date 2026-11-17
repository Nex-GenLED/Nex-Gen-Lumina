// Firebase init + environment check (lib/config/firebase_bootstrap.dart).
//
// The production group pins the sequence main.dart ran before the staging
// switch existed — which options each attempt used, in what order, the
// fallback, the degraded start, and every breadcrumb string — so "the default
// build behaves exactly as production does today" is a test, not a claim.
//
// The staging group proves the other direction: a staging build initialises
// once, with the staging options only, never via the native config files
// (google-services.json on Android IS production), and refuses on anything
// it cannot verify.

import 'dart:async';

import 'package:firebase_core/firebase_core.dart' show FirebaseOptions;
import 'package:flutter/foundation.dart' show TargetPlatform;
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/config/firebase_bootstrap.dart';
import 'package:nexgen_command/config/firebase_options_staging.dart';
import 'package:nexgen_command/config/lumina_env.dart';
import 'package:nexgen_command/firebase_options.dart';

const _goodStaging = FirebaseOptions(
  apiKey: 'staging-test-key',
  appId: '1:431625047151:ios:0000000000000000000000',
  messagingSenderId: '431625047151',
  projectId: 'nex-gen-lumina-22751',
  storageBucket: 'nex-gen-lumina-22751.firebasestorage.app',
  iosBundleId: 'com.nexgenled.command.staging',
);

/// Records every init attempt. `failures` lists, per attempt, the error to
/// throw (or null to succeed). An attempt past the end succeeds.
class _FakeFirebase {
  _FakeFirebase({this.failures = const [], this.loaded});

  final List<Object?> failures;
  final List<FirebaseOptions?> calls = [];

  /// projectId the fake reports after init. `null` = no app.
  String? loaded;

  Future<void> initialize(FirebaseOptions? options) async {
    final i = calls.length;
    calls.add(options);
    if (i < failures.length && failures[i] != null) throw failures[i]!;
  }
}

class _Run {
  final breadcrumbs = <String>[];
  final bothFailed = <Object>[];
}

Future<(EnvGuardVerdict, _Run)> _run(
  _FakeFirebase fb, {
  String define = '',
  bool isWeb = false,
  TargetPlatform platform = TargetPlatform.iOS,
  FirebaseOptions Function()? productionOptions,
  FirebaseOptions Function()? stagingOptions,
  Duration timeout = const Duration(seconds: 15),
}) async {
  final run = _Run();
  final verdict = await bootstrapFirebase(
    define: define,
    isWeb: isWeb,
    platform: platform,
    breadcrumb: run.breadcrumbs.add,
    onBothFailed: (e, _) => run.bothFailed.add(e),
    initialize: fb.initialize,
    loadedProjectId: () => fb.loaded,
    productionOptions:
        productionOptions ?? () => DefaultFirebaseOptions.currentPlatform,
    stagingOptions: stagingOptions,
    timeout: timeout,
  );
  return (verdict, run);
}

void main() {
  group('production (default build): the pre-existing sequence', () {
    test('native config first, no options; success stops there', () async {
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      final (v, run) = await _run(fb);
      expect(fb.calls, [null]);
      expect(run.breadcrumbs, ['firebase:begin', 'firebase:ok']);
      expect(run.bothFailed, isEmpty);
      expect(v.allowed, isTrue);
    });

    test('native config fails -> fallback with DefaultFirebaseOptions', () async {
      final fb = _FakeFirebase(
          failures: [StateError('no plist')], loaded: kProductionProjectId);
      final (v, run) = await _run(fb);
      expect(fb.calls, hasLength(2));
      expect(fb.calls[0], isNull);
      // The real production default, not a stand-in: flutter_test runs as
      // Android, so currentPlatform is the android const itself.
      expect(fb.calls[1], same(DefaultFirebaseOptions.android));
      expect(run.breadcrumbs, [
        'firebase:begin',
        'firebase:primary FAILED, trying fallback err=Bad state: no plist',
        'firebase:ok (via fallback)',
      ]);
      expect(v.allowed, isTrue);
    });

    test('both fail -> reported once, and the app STILL starts', () async {
      final fb = _FakeFirebase(
          failures: [StateError('one'), StateError('two')], loaded: null);
      final (v, run) = await _run(fb);
      expect(fb.calls, [null, same(DefaultFirebaseOptions.android)]);
      expect(run.breadcrumbs, [
        'firebase:begin',
        'firebase:primary FAILED, trying fallback err=Bad state: one',
        'firebase:FAILED BOTH (continuing) err=Bad state: two',
      ]);
      expect(run.bothFailed, hasLength(1));
      expect('${run.bothFailed.single}', 'Bad state: two');
      expect(v.allowed, isTrue, reason: 'degraded start is kept');
    });

    test('web initialises with Dart options first', () async {
      const webSentinel = FirebaseOptions(
          apiKey: 'w', appId: 'w', messagingSenderId: 'w', projectId: 'w');
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      final (v, run) =
          await _run(fb, isWeb: true, productionOptions: () => webSentinel);
      expect(fb.calls, [same(webSentinel)]);
      expect(run.breadcrumbs, ['firebase:begin', 'firebase:ok']);
      expect(v.allowed, isTrue);
    });

    test('a hang is bounded by the timeout, then falls back', () async {
      var attempt = 0;
      final never = Completer<void>();
      final run = _Run();
      final calls = <FirebaseOptions?>[];
      final v = await bootstrapFirebase(
        define: '',
        isWeb: false,
        platform: TargetPlatform.iOS,
        breadcrumb: run.breadcrumbs.add,
        onBothFailed: (e, _) => run.bothFailed.add(e),
        initialize: (o) {
          calls.add(o);
          return attempt++ == 0 ? never.future : Future.value();
        },
        loadedProjectId: () => kProductionProjectId,
        timeout: const Duration(milliseconds: 20),
      );
      expect(calls, [null, same(DefaultFirebaseOptions.android)]);
      expect(run.breadcrumbs.last, 'firebase:ok (via fallback)');
      expect(v.allowed, isTrue);
    });

    testWidgets('the production default timeout is still 15 s',
        (tester) async {
      // Fake clock (testWidgets): a first attempt still pending at 14.9 s has
      // NOT fallen back; at 15.1 s it has.
      final calls = <FirebaseOptions?>[];
      final first = Completer<void>();
      final done = bootstrapFirebase(
        define: '',
        isWeb: false,
        platform: TargetPlatform.iOS,
        breadcrumb: (_) {},
        onBothFailed: (_, __) {},
        initialize: (o) {
          calls.add(o);
          return calls.length == 1 ? first.future : Future<void>.value();
        },
        loadedProjectId: () => kProductionProjectId,
      );
      await tester.pump(const Duration(seconds: 14, milliseconds: 900));
      expect(calls, [null]);
      await tester.pump(const Duration(milliseconds: 200));
      expect(calls, [null, same(DefaultFirebaseOptions.android)]);
      expect((await done).allowed, isTrue);
    });

    test('LUMINA_ENV=prod behaves exactly like no define', () async {
      final a = _FakeFirebase(
          failures: [StateError('x')], loaded: kProductionProjectId);
      final b = _FakeFirebase(
          failures: [StateError('x')], loaded: kProductionProjectId);
      final (va, ra) = await _run(a);
      final (vb, rb) = await _run(b, define: 'prod');
      expect(b.calls, a.calls);
      expect(rb.breadcrumbs, ra.breadcrumbs);
      expect(vb.allowed, va.allowed);
    });

    test('NEW: a non-production project in a production build refuses',
        () async {
      // e.g. a staging google-services.json dropped into android/app.
      final fb = _FakeFirebase(loaded: kStagingProjectId);
      final (v, _) = await _run(fb);
      expect(fb.calls, [null], reason: 'same sequence; only the verdict differs');
      expect(v.allowed, isFalse);
    });

    test('never touches the staging options', () async {
      var stagingRead = false;
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      await _run(fb, stagingOptions: () {
        stagingRead = true;
        return _goodStaging;
      });
      expect(stagingRead, isFalse);
    });
  });

  group('staging build', () {
    test('one init, with the staging options, never the native config',
        () async {
      final fb = _FakeFirebase(loaded: kStagingProjectId);
      final (v, run) = await _run(fb,
          define: 'staging', stagingOptions: () => _goodStaging);
      expect(fb.calls, [same(_goodStaging)]);
      expect(fb.calls, isNot(contains(null)));
      expect(run.breadcrumbs.first,
          'firebase:begin (LUMINA_ENV_MARKER=)',
          reason: 'this test binary has no define, so the marker is empty');
      expect(v.allowed, isTrue);
    });

    test('init failure refuses, with NO fallback attempt', () async {
      final fb = _FakeFirebase(
          failures: [StateError('boom')], loaded: kProductionProjectId);
      final (v, run) = await _run(fb,
          define: 'staging', stagingOptions: () => _goodStaging);
      expect(fb.calls, [same(_goodStaging)]);
      expect(v.allowed, isFalse);
      expect(v.reason, contains('boom'));
      expect(run.bothFailed, isEmpty);
    });

    test('production project loaded anyway (e.g. a native plist) refuses',
        () async {
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      final (v, _) = await _run(fb,
          define: 'staging', stagingOptions: () => _goodStaging);
      expect(v.allowed, isFalse);
      expect(v.reason, contains(kProductionProjectId));
    });

    test('placeholder values refuse BEFORE Firebase is called', () async {
      final placeholders = _goodStaging.copyWith(
        apiKey: '${kStagingPlaceholderPrefix}_STAGING_IOS_API_KEY',
        appId: '${kStagingPlaceholderPrefix}_STAGING_IOS_GOOGLE_APP_ID',
      );
      final fb = _FakeFirebase(loaded: kStagingProjectId);
      final (v, _) = await _run(fb,
          define: 'staging', stagingOptions: () => placeholders);
      expect(fb.calls, isEmpty);
      expect(v.allowed, isFalse);
      expect(v.reason, contains('not filled in'));
    });

    test('the committed staging file initialises once, as itself', () async {
      final fb = _FakeFirebase(loaded: kStagingProjectId);
      final (v, _) = await _run(fb, define: 'staging'); // real staging file
      expect(fb.calls, [same(StagingFirebaseOptions.ios)]);
      expect(v.allowed, isTrue);
    });

    test('production values pasted into staging refuse before init', () async {
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      final (v, _) = await _run(fb,
          define: 'staging',
          stagingOptions: () => DefaultFirebaseOptions.ios);
      expect(fb.calls, isEmpty);
      expect(v.allowed, isFalse);
    });

    test('Android and web have no staging app: refuse, no init', () async {
      for (final (isWeb, platform) in [
        (false, TargetPlatform.android),
        (true, TargetPlatform.iOS),
      ]) {
        final fb = _FakeFirebase(loaded: kStagingProjectId);
        final (v, _) = await _run(fb,
            define: 'staging', isWeb: isWeb, platform: platform);
        expect(fb.calls, isEmpty, reason: '$platform web=$isWeb');
        expect(v.allowed, isFalse);
        expect(v.reason, contains('iOS only'));
      }
    });
  });

  group('unrecognised define', () {
    test('no init at all, and refuse', () async {
      final fb = _FakeFirebase(loaded: kProductionProjectId);
      final (v, run) = await _run(fb, define: 'stagin');
      expect(fb.calls, isEmpty);
      expect(v.allowed, isFalse);
      expect(run.breadcrumbs, ['firebase:SKIPPED (LUMINA_ENV not recognised)']);
    });
  });
}
