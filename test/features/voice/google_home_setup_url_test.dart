// Strings proposal item 5: the Google Home setup URL carried a placeholder
// project id. The constant, and the fallback that launched it, are gone.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no placeholder setup URL remains in the app', () {
    final src =
        File('lib/features/voice/google_home_service.dart').readAsStringSync();
    expect(src, isNot(contains('setupWebUrl')));
    expect(src, isNot(contains('YOUR_PROJECT_ID')));
    expect(src, isNot(contains('assistant.google.com/services/invoke')));

    final hits = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'))
        .where((f) => f.readAsStringSync().contains('YOUR_PROJECT_ID'))
        .map((f) => f.path)
        .toList();
    expect(hits, isEmpty);
  });
}
