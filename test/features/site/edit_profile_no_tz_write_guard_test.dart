// test/features/site/edit_profile_no_tz_write_guard_test.dart
//
// Source-level guard for TD-7. The profile editor wrote
// `timeZone: DateTime.now().timeZoneName` on every save — an abbreviation
// ("CDT") and the EDITOR's zone — over the IANA zone the install captured.
// This test reads the screen as text and fails if it becomes a timezone writer
// again.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

const _screen = 'lib/features/site/edit_profile_screen.dart';

void main() {
  test('the profile editor never writes the profile time zone', () {
    final src = File(_screen).readAsStringSync();
    expect(src.contains('timeZoneName'), false,
        reason: '$_screen must not read the phone zone abbreviation');
    expect(RegExp(r'\btimeZone\s*:').hasMatch(src), false,
        reason: '$_screen must not pass timeZone: to copyWith');
  });
}
