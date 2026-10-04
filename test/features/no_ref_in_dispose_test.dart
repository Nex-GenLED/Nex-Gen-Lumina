// #166 — a widget's `ref` must never be read in dispose() or deactivate().
//
// Riverpod marks the element disposed before State.dispose runs, so `ref.read`
// there throws "Cannot use ref after the widget was disposed", reported through
// FlutterError.onError. Symbolicated debug_errors (build 102) put this shape —
// LibraryBrowserScreen.dispose — behind the flood of these records until it was
// fixed in build 109. Capture what dispose needs in initState instead.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('no ConsumerState reads ref in dispose() or deactivate()', () {
    final offenders = <String>[];
    final files = Directory('lib')
        .listSync(recursive: true)
        .whereType<File>()
        .where((f) => f.path.endsWith('.dart'));
    final method = RegExp(r'void\s+(dispose|deactivate)\s*\(\s*\)\s*\{');
    final refUse =
        RegExp(r'\bref\s*\.\s*(read|watch|listen|invalidate|refresh)\b');
    for (final f in files) {
      final src = f.readAsStringSync();
      if (!src.contains('ConsumerState')) continue;
      for (final m in method.allMatches(src)) {
        var depth = 1;
        var i = m.end;
        while (i < src.length && depth > 0) {
          final c = src[i];
          if (c == '{') depth++;
          if (c == '}') depth--;
          i++;
        }
        final body = src
            .substring(m.end, i)
            .split('\n')
            .map((l) => l.split('//').first)
            .join('\n');
        if (refUse.hasMatch(body)) {
          final line = src.substring(0, m.start).split('\n').length;
          offenders.add('${f.path.replaceAll(r'\', '/')}:$line');
        }
      }
    }
    expect(offenders, isEmpty);
  });
}
