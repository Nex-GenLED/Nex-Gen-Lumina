// codemagic.yaml: the staging workflow cannot build from a production tag,
// and the production workflow cannot build staging.
//
// Text checks, no YAML package (it is not a declared dependency): each
// workflow block is the text between its two-space-indented key and the next
// one. The cross-file pins at the bottom keep the workflow's greps in step
// with the Dart constants they look for.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/config/lumina_env.dart';

final _workflowKey = RegExp(r'^  ([a-z][a-z0-9-]*):\s*$', multiLine: true);
final _tagPattern = RegExp(r"^\s*- pattern: '([^']*)'", multiLine: true);

Map<String, String> _workflows(String yaml) {
  final keys = _workflowKey.allMatches(yaml).toList();
  return {
    for (var i = 0; i < keys.length; i++)
      keys[i].group(1)!: _dropTrailingComments(yaml.substring(
          keys[i].start, i + 1 < keys.length ? keys[i + 1].start : yaml.length)),
  };
}

/// The banner comment ABOVE a workflow key belongs to that workflow, not to
/// the one before it.
String _dropTrailingComments(String block) {
  final lines = block.split('\n');
  while (lines.isNotEmpty &&
      (lines.last.trim().isEmpty || lines.last.trimLeft().startsWith('#'))) {
    lines.removeLast();
  }
  return '${lines.join('\n')}\n';
}

List<String> _patterns(String block) =>
    _tagPattern.allMatches(block).map((m) => m.group(1)!).toList();

void main() {
  final yaml = File('codemagic.yaml').readAsStringSync();
  final wf = _workflows(yaml);
  final prod = wf['ios-workflow']!;
  final staging = wf['ios-staging-workflow']!;

  test('exactly the two workflows, production first', () {
    expect(wf.keys.toList(), ['ios-workflow', 'ios-staging-workflow']);
  });

  group('production workflow', () {
    test('still triggers on build-* tags only', () {
      expect(_patterns(prod), ['build-*']);
      expect(prod, contains('        - tag\n'));
    });

    test('still the production bundle id, and nothing of staging', () {
      expect(prod, contains('BUNDLE_ID: com.nexgenled.command\n'));
      expect(prod, isNot(contains('LUMINA_ENV')));
      expect(prod, isNot(contains('com.nexgenled.command.staging')));
      expect(prod, isNot(contains('staging-')));
      expect(prod, contains('submit_to_testflight: true'));
    });
  });

  group('staging workflow', () {
    test('triggers on staging-* tags only — never build-*, never a push', () {
      expect(_patterns(staging), ['staging-*']);
      final events = RegExp(r'events:\n((?:\s+- \w+\n)+)')
          .firstMatch(staging)!
          .group(1)!;
      expect(events.trim(), '- tag');
    });

    test('refuses any build whose tag is not staging-*', () {
      expect(staging, contains(r'case "${CM_TAG:-}" in'));
      expect(staging, contains('staging-*) echo'));
    });

    test('signs, builds and verifies the staging bundle id', () {
      expect(staging, contains('BUNDLE_ID: com.nexgenled.command.staging\n'));
      expect(
          staging,
          contains('flutter build ipa --release '
              '--dart-define=LUMINA_ENV=staging'));
      expect(staging,
          contains(r'if [ "$ID" != "com.nexgenled.command.staging" ]; then'));
    });

    test('verification runs after the build and before publishing', () {
      final build = staging.indexOf('- name: Build IPA');
      final verify = staging.indexOf('- name: Verify the IPA');
      final publish = staging.indexOf('    publishing:');
      expect(build, greaterThan(0));
      expect(verify, greaterThan(build));
      expect(publish, greaterThan(verify));
    });

    test('rewrites the CI clone before use-profiles matches profiles', () {
      expect(staging.indexOf('- name: Rewrite the CI clone'),
          lessThan(staging.indexOf('xcode-project use-profiles')));
      expect(staging.indexOf('- name: Test and analyze'),
          lessThan(staging.indexOf('- name: Rewrite the CI clone')),
          reason: 'the gate tests the commit as checked out');
    });

    test('numbers builds from its own counter, never production\'s', () {
      expect(staging, contains(r'BUILD_NUM=${BUILD_NUMBER:?'));
      expect(staging, isNot(contains(r'${PROJECT_BUILD_NUMBER')));
    });

    test('uploads without requesting beta review', () {
      expect(staging, contains('submit_to_testflight: false'));
    });

    test('same Flutter pin as production', () {
      final pin = RegExp(r'flutter: (\S+)');
      expect(pin.firstMatch(staging)!.group(1),
          pin.firstMatch(prod)!.group(1));
    });
  });

  group('greps in the workflow match the Dart they look for', () {
    test('the IPA marker is the compile-time marker with "staging" folded in',
        () {
      expect(kLuminaEnvMarker, startsWith('LUMINA_ENV_MARKER='));
      expect(staging, contains("'LUMINA_ENV_MARKER=staging'"));
    });

    test('the placeholder grep matches the staging file\'s placeholders', () {
      final opts =
          File('lib/config/firebase_options_staging.dart').readAsStringSync();
      expect(staging, contains("grep -n \"'${kStagingPlaceholderPrefix}_\""));
      // Any placeholder left in the file has the exact shape that grep
      // finds (a quoted literal starting PREFIX_), so none can slip past it.
      final code = opts
          .split('\n')
          .where((l) => !l.trimLeft().startsWith('//'))
          .join('\n');
      final literals =
          RegExp("'([^'\\n]*)'").allMatches(code).map((m) => m[1]!).toList();
      expect(literals, contains(kStagingProjectId));
      for (final v in literals.where((v) => v.contains(kStagingPlaceholderPrefix))) {
        expect(v, startsWith('${kStagingPlaceholderPrefix}_'));
      }
      expect(opts, contains("projectId: '$kStagingProjectId'"));
      expect(opts, contains("iosBundleId: '$kStagingBundleId'"));
    });
  });
}
