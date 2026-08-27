// THE CRASH. EphemeralGameSession persisted `revert_wled_payload` as a raw
// Map, and that Map is a verbatim `/json/state` read off the controller — so it
// ALWAYS contains `seg[].col: [[r,g,b,w], ...]`, directly-nested arrays.
//
// Firestore does not support nested arrays. On iOS the SDK does not return an
// error for that: FSTUserDataReader raises NSInvalidArgumentException ->
// objc_exception_throw -> abort. That is an EXC_CRASH/SIGABRT below the Dart
// VM, so NO `try/catch` and no Flutter error handler can intercept it — which
// is exactly why the earlier wedge audit's "it's inside a try/catch, therefore
// it cannot close the app" reasoning was wrong. Crash incident
// 51AD90DC-5A9F-4F34-B34C-FB70F82D04B2, build 2.5.10(321).
//
// These tests deliberately use a REAL nested-array shape. A flat mock payload
// would pass against the broken code and prove nothing.

import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/game_day/ephemeral_session/ephemeral_game_session.dart';
import 'package:nexgen_command/services/user_service.dart';

/// A verbatim-shaped `/json/state` read: two segments, each with a `col` that
/// is a LIST OF LISTS. This is the shape that aborts the process.
Map<String, dynamic> _realControllerState() => {
      'on': true,
      'bri': 255,
      'seg': [
        {
          'id': 0,
          'fx': 27,
          'sx': 99,
          'ix': 128,
          'col': [
            [0, 70, 135, 0],
            [192, 154, 91, 0],
            [255, 255, 255, 0],
          ],
        },
        {
          'id': 1,
          'fx': 0,
          'col': [
            [255, 0, 0, 0],
            [0, 0, 0, 0],
          ],
        },
      ],
    };

EphemeralGameSession _session(Map<String, dynamic> revert) =>
    EphemeralGameSession(
      sessionId: 's1',
      teamSlug: 'nfl_chiefs',
      gameId: '401671789',
      gameStart: DateTime.utc(2026, 8, 27, 18),
      revertWledPayload: revert,
      revertLabel: 'Warm White',
      createdAt: DateTime.utc(2026, 8, 27, 17),
    );

void main() {
  group('the crash shape itself', () {
    test('the fixture really does contain directly-nested arrays', () {
      // Guards the guard: if this fixture ever flattens, every test below
      // becomes vacuous while still passing.
      final seg = (_realControllerState()['seg'] as List).first as Map;
      final col = seg['col'] as List;
      expect(col.first, isA<List>(),
          reason: 'col MUST be a list-of-lists or this suite proves nothing');
    });

    test('sanitizeForFirestore THROWS on the raw payload — the pre-fix shape',
        () {
      // Direct evidence that the old `set(session.toJson())` with a raw Map
      // was handing Firestore an illegal document. The sanitizer is the
      // codebase's own detector for exactly this: on iOS the same input
      // aborts the process instead of throwing.
      expect(
        () => UserService.sanitizeForFirestore(
            {'revert_wled_payload': _realControllerState()}),
        throwsA(isA<FirestoreSerializationError>()),
        reason: 'nested arrays must be rejected before they reach the codec',
      );
    });
  });

  group('the fix — toJson is Firestore-legal', () {
    test('revert_wled_payload is encoded to a String, not a Map', () {
      final json = _session(_realControllerState()).toJson();
      expect(json['revert_wled_payload'], isA<String>(),
          reason: 'the nested array must not survive into the document');
    });

    test('the encoded document passes the sanitizer — no nested list anywhere',
        () {
      // THE LOAD-BEARING ASSERTION. Same input that throws above; after
      // toJson it is clean. This is the difference between a write that
      // aborts the app and one that succeeds.
      final json = _session(_realControllerState()).toJson();
      expect(
        () => UserService.sanitizeForFirestore(json),
        returnsNormally,
        reason: 'the whole document must be Firestore-safe, not just the '
            'field we noticed',
      );
    });

    test('no value anywhere in the document is a nested list', () {
      final json = _session(_realControllerState()).toJson();

      void assertNoNestedList(Object? v, String path) {
        if (v is List) {
          for (var i = 0; i < v.length; i++) {
            expect(v[i], isNot(isA<List>()),
                reason: 'nested list at $path[$i]');
            assertNoNestedList(v[i], '$path[$i]');
          }
        } else if (v is Map) {
          v.forEach((k, val) => assertNoNestedList(val, '$path.$k'));
        }
      }

      json.forEach((k, v) => assertNoNestedList(v, k));
    });
  });

  group('round-trip — the revert payload survives intact', () {
    test('what was captured is what comes back out', () {
      final original = _realControllerState();
      final json = _session(original).toJson();

      // Simulate the Firestore read: Timestamps come back as Timestamps, the
      // encoded field comes back as the String that was stored.
      final restored = EphemeralGameSession.fromJson(json);

      expect(restored.revertWledPayload, equals(original),
          reason: 'a revert that does not round-trip would restore the wrong '
              'lighting — worse than not reverting at all');
      // Spot-check the nested structure specifically, not just deep equality.
      final seg = (restored.revertWledPayload['seg'] as List).first as Map;
      expect((seg['col'] as List).first, equals([0, 70, 135, 0]));
    });

    test('the rest of the session round-trips too', () {
      final s = _session(_realControllerState());
      final r = EphemeralGameSession.fromJson(s.toJson());

      expect(r.sessionId, s.sessionId);
      expect(r.teamSlug, s.teamSlug);
      expect(r.gameId, s.gameId);
      expect(r.revertLabel, s.revertLabel);
      // Timestamp.toDate() returns a LOCAL-zone DateTime for the same
      // instant, so `==` fails on the isUtc flag alone. The instant is what
      // matters here — this is Timestamp behaviour, not anything the fix
      // introduced.
      expect(r.gameStart.isAtSameMomentAs(s.gameStart), isTrue);
      expect(r.phase, s.phase);
    });

    test('an empty revert payload round-trips as empty, not null', () {
      final r = EphemeralGameSession.fromJson(_session(const {}).toJson());
      expect(r.revertWledPayload, isEmpty);
    });
  });

  group('reading documents this app did not write', () {
    test('a LEGACY raw-Map document still decodes', () {
      // Not hypothetical-proofing for its own sake: the abort is the iOS
      // codec's behaviour, so a document written from a platform whose codec
      // accepted the nested array would still be a Map on read. A stored doc
      // must never be able to crash the reader.
      final legacy = <String, dynamic>{
        'session_id': 's1',
        'team_slug': 'nfl_chiefs',
        'game_id': '401671789',
        'game_start': Timestamp.fromDate(DateTime.utc(2026, 8, 27, 18)),
        'revert_wled_payload': _realControllerState(), // raw Map, old shape
        'revert_label': 'Warm White',
        'created_at': Timestamp.fromDate(DateTime.utc(2026, 8, 27, 17)),
        'phase': 'idle',
      };

      final r = EphemeralGameSession.fromJson(legacy);
      expect(r.revertWledPayload, equals(_realControllerState()));
    });

    test('a corrupt blob degrades to empty instead of throwing', () {
      final json = _session(_realControllerState()).toJson();
      json['revert_wled_payload'] = '{not valid json';

      final r = EphemeralGameSession.fromJson(json);
      expect(r.revertWledPayload, isEmpty,
          reason: 'a corrupt field must not take out the session read — the '
              'revert no-ops instead');
    });

    test('a non-JSON-object blob also degrades to empty', () {
      final json = _session(_realControllerState()).toJson();
      json['revert_wled_payload'] = jsonEncode([1, 2, 3]);

      expect(EphemeralGameSession.fromJson(json).revertWledPayload, isEmpty);
    });
  });
}
