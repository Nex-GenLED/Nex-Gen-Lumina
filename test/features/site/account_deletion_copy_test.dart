// Store readiness 3f: the account-deletion dialog says what is deleted AND
// what is kept.
//
// purgeUserAccount removes everything under users/{uid} plus the account's
// Storage folder. It leaves records kept outside that tree: the installation
// record (name, contact details, address), support and design requests, and
// Neighborhood Sync crew membership. The old dialog promised "Your profile,
// address and contact details" and "Neighborhood Sync settings" were deleted.
// The screen needs Firebase to pump, so this pins the copy at the source,
// like siri_shortcuts_strings_test.dart.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  final src =
      File('lib/features/site/security_settings_screen.dart').readAsStringSync();

  test('no longer promises what the purge does not delete', () {
    expect(src, isNot(contains("'Your profile, address and contact details'")));
    expect(src,
        isNot(contains("'Game Day, Autopilot and Neighborhood Sync settings'")));
  });

  test('names what is kept and how to have it removed', () {
    expect(src, contains("'This does not delete:'"));
    expect(src, contains('Your installation record held for your installer'));
    expect(src, contains('Support messages and design requests you sent us'));
    expect(src, contains('Neighborhood Sync crew you joined'));
    expect(src, contains(r'email $kNexGenCorporateEmail'));
  });
}
