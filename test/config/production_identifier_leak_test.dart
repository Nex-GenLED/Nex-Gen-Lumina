// LEAK GUARD for the staging build.
//
// A staging build must be unable to reach production. Everything Firebase
// SDK-based follows the default app, which bootstrapFirebase verifies at
// startup — so the only ways left to reach production are identifiers
// written straight into the source: the project id inside a URL, a
// cloudfunctions.net / run.app host, an API key, a second Firebase app.
//
// This test fails when one of them appears under lib/ or ios/ outside the
// files that switch on LUMINA_ENV. If it fails on your change, route the
// value through lib/config/lumina_env.dart (see kCloudFunctionsBaseUrl) — do
// not add the file to an allow-list without that.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// [pattern] may appear only in [allowed] (paths relative to the repo root).
class _Rule {
  const _Rule(this.name, this.pattern, this.allowed);
  final String name;
  final Pattern pattern;
  final Set<String> allowed;
}

const _options = 'lib/firebase_options.dart';
const _env = 'lib/config/lumina_env.dart';
const _stagingOptions = 'lib/config/firebase_options_staging.dart';
const _bootstrap = 'lib/config/firebase_bootstrap.dart';

final _rules = <_Rule>[
  const _Rule('production project id', 'icrt6menwsv2d8all8oijs021b06s5',
      {_options, _env}),
  const _Rule('production project number', '1036323013258', {_options, _env}),
  const _Rule('Cloud Functions host', 'cloudfunctions.net', {_env}),
  const _Rule('Cloud Run host', 'run.app', {}),
  const _Rule('Realtime Database host', 'firebaseio.com', {}),
  const _Rule('legacy bucket / App Engine host', 'appspot.com', {}),
  const _Rule('Firestore REST host', 'firestore.googleapis.com', {}),
  const _Rule('Storage REST host', 'firebasestorage.googleapis.com', {}),
  const _Rule('Storage bucket', 'firebasestorage.app', {_options, _stagingOptions}),
  const _Rule('auth domain', 'firebaseapp.com', {_options}),
  _Rule('Google API key', RegExp(r'AIza[0-9A-Za-z_\-]{35}'),
      {_options, _stagingOptions}),
  // The production options object. Geocoding keeps its production lines
  // verbatim behind `if (!kIsProdBuild)` (staging uses the staging key).
  const _Rule('DefaultFirebaseOptions', 'DefaultFirebaseOptions',
      {_options, _bootstrap, 'lib/features/schedule/geocoding_service.dart'}),
  // One init path only, the one that checks the environment.
  const _Rule('Firebase.initializeApp(', 'Firebase.initializeApp(',
      {_bootstrap, _options}),
  // A second Firebase app would bypass the startup check.
  _Rule('instanceFor(app:', RegExp(r'instanceFor\(\s*app\s*:'), const {}),
  _Rule('named Firebase app', RegExp(r"Firebase\.app\(\s*'"), const {}),
];

Iterable<File> _files(String root, bool Function(String) keep) sync* {
  final dir = Directory(root);
  if (!dir.existsSync()) return;
  for (final e in dir.listSync(recursive: true, followLinks: false)) {
    if (e is! File) continue;
    final p = e.path.replaceAll('\\', '/');
    if (p.contains('/Pods/') || p.contains('/.symlinks/') ||
        p.contains('/build/') || p.contains('/Flutter/ephemeral/')) {
      continue;
    }
    if (keep(p)) yield e;
  }
}

/// Repo-relative path: the scan lists relative directories from the package
/// root (flutter test's cwd), so only the separator needs normalising.
String _rel(File f) => f.path.replaceAll('\\', '/');

void main() {
  final sources = <String, String>{
    for (final f in _files('lib', (p) => p.endsWith('.dart')))
      _rel(f): f.readAsStringSync(),
    for (final f in _files(
        'ios',
        (p) => RegExp(r'\.(plist|swift|pbxproj|entitlements|xcconfig|h|m|json)$')
                .hasMatch(p) ||
            p.endsWith('/Podfile')))
      _rel(f): f.readAsStringSync(),
  };

  test('the scan sees the tree', () {
    expect(sources.keys, contains('lib/main.dart'));
    expect(sources.keys, contains(_env));
    expect(sources.keys, contains('ios/Runner/Info.plist'));
    expect(sources.length, greaterThan(500));
  });

  for (final rule in _rules) {
    test('${rule.name} appears only where LUMINA_ENV switches it', () {
      final offenders = <String>[];
      sources.forEach((path, text) {
        if (rule.allowed.contains(path)) return;
        final lines = text.split('\n');
        for (var i = 0; i < lines.length; i++) {
          if (rule.pattern.allMatches(lines[i]).isNotEmpty) {
            offenders.add('$path:${i + 1}');
          }
        }
      });
      expect(offenders, isEmpty,
          reason: '${rule.name} found outside ${rule.allowed}. A staging '
              'build would still send this to production. Route it through '
              'lib/config/lumina_env.dart.');
    });
  }

  test('every allow-listed file still exists (no stale exemptions)', () {
    for (final rule in _rules) {
      for (final path in rule.allowed) {
        expect(sources.keys, contains(path), reason: '${rule.name}: $path');
      }
    }
  });
}
