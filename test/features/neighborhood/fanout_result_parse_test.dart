// Tests for FanoutResult.parse — the pure parser over the applySyncPattern
// HTTP response (Slice 1 Commit 2). rate_limited is the only state that
// suppresses the app-open broadcast; every other outcome (including plain
// failures) must NOT be rate-limited so the broadcast still proceeds.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';

void main() {
  group('FanoutResult.parse', () {
    test('200 + {ok:true, ...} → ok, not rate-limited', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': true, 'memberCount': 3, 'commandCount': 3}),
      );
      expect(r.ok, isTrue);
      expect(r.rateLimited, isFalse);
      expect(r.retryAfterMs, 0);
    });

    test('200 + {ok:false, reason:rate_limited, retryAfterMs} → rateLimited', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': false, 'reason': 'rate_limited', 'retryAfterMs': 8200}),
      );
      expect(r.ok, isFalse);
      expect(r.rateLimited, isTrue);
      expect(r.retryAfterMs, 8200);
    });

    test('rate_limited with missing retryAfterMs → 0 (defensive)', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': false, 'reason': 'rate_limited'}),
      );
      expect(r.rateLimited, isTrue);
      expect(r.retryAfterMs, 0);
    });

    test('non-200 → plain failure (broadcast still proceeds)', () {
      final r = FanoutResult.parse(500, 'Internal Server Error');
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
    });

    test('200 + malformed body → plain failure, not rate-limited', () {
      final r = FanoutResult.parse(200, 'not json{{{');
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
    });

    test('200 + {ok:false} with no reason → plain failure', () {
      final r = FanoutResult.parse(200, jsonEncode({'ok': false}));
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
    });

    test('const failed() constructor is a plain non-rate-limited failure', () {
      const r = FanoutResult.failed();
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.retryAfterMs, 0);
    });
  });
}
