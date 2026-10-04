// #166 — every debug_errors record says which build threw.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/app_version.dart';
import 'package:nexgen_command/services/debug_error_record.dart';

void main() {
  test('the record carries the app version and the existing fields', () {
    final r = debugErrorRecord(
      error: StateError('Cannot use "ref" after the widget was disposed.'),
      stack: StackTrace.fromString('#00 frame'),
      context: 'PlatformDispatcher.onError',
      platform: 'ios',
    );
    expect(r['app_version'], kAppVersion);
    expect(r.keys.toSet(), {
      'timestamp',
      'context',
      'error_type',
      'error',
      'stack',
      'app_version',
      'platform',
    }, reason: 'nothing else about what is logged changed');
    expect(r['error_type'], 'StateError');
    expect(r['context'], 'PlatformDispatcher.onError');
    expect(r['platform'], 'ios');
  });

  test('error and stack stay capped', () {
    final long = 'x' * (kDebugErrorFieldCap + 50);
    final r = debugErrorRecord(
      error: long,
      stack: StackTrace.fromString(long),
      context: 'c',
      platform: 'android',
    );
    expect((r['error'] as String).length, kDebugErrorFieldCap);
    expect((r['stack'] as String).length, kDebugErrorFieldCap);
  });
}
