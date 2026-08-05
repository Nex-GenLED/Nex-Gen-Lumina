// test/unit/firestore_error_no_pii_test.dart
//
// DIAGNOSTICS PRIVACY — audit/DIAGNOSTICS_DECLARATION.md §2,
// audit/DIAGNOSTICS_FIX.md item 1.
//
// FirestoreSerializationError.toString() is persisted VERBATIM to
// users/{uid}/debug_errors by the global uncaught-error sink in main.dart. The
// throw originates in sanitizeForFirestore, which wraps USER-DOCUMENT writes —
// the document holding address, phone_number, home_ssid_encrypted, email and
// coordinates.
//
// _safeShape previously returned value.toString() truncated to 120 chars, i.e.
// the actual value. This suite pins that the message now carries the field PATH
// and the TYPE but NEVER the content, so a serialization failure cannot put
// personal data into a diagnostics collection.
//
// The path is the diagnostic that matters and is asserted present — a scrub
// that also destroyed the ability to locate the offending field would be a bad
// trade, so both halves are pinned here.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/services/user_service.dart';

/// A value the sanitizer cannot encode, whose `toString()` leaks something that
/// looks exactly like the PII the user document actually holds.
class _PiiLeakyLeaf {
  final String secret;
  const _PiiLeakyLeaf(this.secret);
  @override
  String toString() => secret;
}

/// A value whose `toString()` itself throws — the fallback branch.
class _ExplodingLeaf {
  const _ExplodingLeaf();
  @override
  String toString() => throw StateError('toString blew up');
}

void main() {
  group('FirestoreSerializationError must not carry value content', () {
    // Representative of what actually lives in the user document.
    const pii = <String, String>{
      'street address': '742 Evergreen Terrace',
      'phone': '+1 (816) 555-0142',
      'email': 'someone@example.com',
      'coordinates': '38.9934607,-94.2527395',
      'wifi ssid': 'Honeycutt_5G',
    };

    for (final entry in pii.entries) {
      test('a non-encodable ${entry.key} never reaches the message', () {
        try {
          UserService.sanitizeForFirestore({
            'profile': {
              'field': _PiiLeakyLeaf(entry.value),
            },
          });
          fail('expected FirestoreSerializationError');
        } on FirestoreSerializationError catch (e) {
          final msg = e.toString();

          // THE point of this suite.
          expect(msg, isNot(contains(entry.value)),
              reason: 'the raw value must never appear — this message is '
                  'persisted to users/{uid}/debug_errors');
          expect(e.valueShape, isNot(contains(entry.value)));

          // …and the diagnostic value must survive.
          expect(e.path, 'profile.field',
              reason: 'the field path is the useful diagnostic and must remain');
          expect(msg, contains('profile.field'));
          expect(msg, contains('_PiiLeakyLeaf'),
              reason: 'the TYPE is safe and is what identifies the bug');
        }
      });
    }

    test('shape reports type and length only', () {
      try {
        UserService.sanitizeForFirestore({
          'tag': const _PiiLeakyLeaf('742 Evergreen Terrace'),
        });
        fail('expected FirestoreSerializationError');
      } on FirestoreSerializationError catch (e) {
        expect(e.valueShape, contains('_PiiLeakyLeaf'));
        expect(e.valueShape, contains('21'),
            reason: 'length of "742 Evergreen Terrace" — size is a safe, useful '
                'signal (spots an unexpectedly huge blob)');
        expect(e.valueShape, isNot(contains('Evergreen')));
      }
    });

    test('a throwing toString() degrades safely, still without content', () {
      try {
        UserService.sanitizeForFirestore({
          'tag': const _ExplodingLeaf(),
        });
        fail('expected FirestoreSerializationError');
      } on FirestoreSerializationError catch (e) {
        expect(e.valueShape, contains('_ExplodingLeaf'));
        expect(e.valueShape, contains('toString threw'));
        expect(() => e.toString(), returnsNormally);
      }
    });

    test('the nested-list throw carries a constant, not a value', () {
      // The other throw site. Its shape string is a fixed description, so it is
      // safe by construction — pinned so nobody "improves" it into a preview.
      try {
        UserService.sanitizeForFirestore({
          'wledPayload': {
            'seg': [
              {
                'col': [
                  ['742 Evergreen Terrace', 'secret'],
                ],
              },
            ],
          },
        });
        fail('expected FirestoreSerializationError');
      } on FirestoreSerializationError catch (e) {
        expect(e.toString(), isNot(contains('Evergreen')));
        expect(e.valueShape, contains('nested list'));
        expect(e.path, contains('wledPayload.seg[0].col[0]'));
      }
    });
  });
}
