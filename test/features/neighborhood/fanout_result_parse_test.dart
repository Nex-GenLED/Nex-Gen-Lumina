// Tests for FanoutResult.parse — the pure parser over the applySyncPattern
// HTTP response (Slice 1 Commit 2). rate_limited is the only state that
// suppresses the app-open broadcast; every other outcome (including plain
// failures) must NOT be rate-limited so the broadcast still proceeds.
//
// Sync Start window (2026-11-02): every outcome now carries a reason (and the
// server's text when it sent one) so the user can be told why, and a success
// carries the server's counts so a host-only answer (no fan-out) is visible.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_service.dart';

void main() {
  group('FanoutResult.parse', () {
    test('200 + {ok:true, ...} → ok, not rate-limited, counts carried', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': true, 'memberCount': 3, 'commandCount': 3, 'skipped': 1}),
      );
      expect(r.ok, isTrue);
      expect(r.rateLimited, isFalse);
      expect(r.retryAfterMs, 0);
      expect(r.reason, isNull);
      expect(r.memberCount, 3);
      expect(r.commandCount, 3);
      expect(r.skipped, 1);
      expect(r.hostOnly, isFalse);
    });

    test('200 + {ok:true, commandCount} WITHOUT memberCount → the host-only path '
        '(server did not fan out) is visible as hostOnly', () {
      final r = FanoutResult.parse(200, jsonEncode({'ok': true, 'commandCount': 1}));
      expect(r.ok, isTrue);
      expect(r.memberCount, isNull);
      expect(r.commandCount, 1);
      expect(r.hostOnly, isTrue);
    });

    test('200 + {ok:false, reason:rate_limited, retryAfterMs} → rateLimited', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': false, 'reason': 'rate_limited', 'retryAfterMs': 8200}),
      );
      expect(r.ok, isFalse);
      expect(r.rateLimited, isTrue);
      expect(r.retryAfterMs, 8200);
      expect(r.reason, 'rate_limited');
    });

    test('rate_limited with missing retryAfterMs → 0 (defensive)', () {
      final r = FanoutResult.parse(
        200,
        jsonEncode({'ok': false, 'reason': 'rate_limited'}),
      );
      expect(r.rateLimited, isTrue);
      expect(r.retryAfterMs, 0);
    });

    test('non-200 → plain failure (broadcast still proceeds) with http_<status>', () {
      final r = FanoutResult.parse(500, 'Internal Server Error');
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.reason, 'http_500');
      expect(r.detail, isNull);
    });

    test('non-200 with the server\'s {error} text → reason http_<status>, detail = text', () {
      final r = FanoutResult.parse(
        403,
        jsonEncode({'error': 'Initiator is not a member of the named sync group.'}),
      );
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.reason, 'http_403');
      expect(r.detail, 'Initiator is not a member of the named sync group.');
    });

    test('401 {error} (expired token) → http_401 with the text', () {
      final r = FanoutResult.parse(401, jsonEncode({'error': 'Invalid or expired ID token'}));
      expect(r.reason, 'http_401');
      expect(r.detail, 'Invalid or expired ID token');
    });

    test('200 + malformed body → plain failure, not rate-limited, reason malformed', () {
      final r = FanoutResult.parse(200, 'not json{{{');
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.reason, 'malformed');
    });

    test('200 + {ok:false} with no reason → plain failure, reason not_ok', () {
      final r = FanoutResult.parse(200, jsonEncode({'ok': false}));
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.reason, 'not_ok');
    });

    test('200 + {ok:false, reason:<other>} → plain failure carrying that reason', () {
      final r = FanoutResult.parse(200, jsonEncode({'ok': false, 'reason': 'not_in_group_member_uids'}));
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.reason, 'not_in_group_member_uids');
    });

    test('const failed() constructor is a plain non-rate-limited failure with a reason', () {
      const r = FanoutResult.failed();
      expect(r.ok, isFalse);
      expect(r.rateLimited, isFalse);
      expect(r.retryAfterMs, 0);
      expect(r.reason, 'failed');
      const n = FanoutResult.failed(reason: 'no_auth');
      expect(n.reason, 'no_auth');
      expect(n.hostOnly, isFalse);
    });
  });
}
