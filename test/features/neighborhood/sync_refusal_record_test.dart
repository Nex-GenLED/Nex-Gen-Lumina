// W1 — #73: a server refusal the customer can actually see.
//
// initiateSyncSession refuses legibly (consent_missing / consent_blocked /
// skip_next_active, each naming the category). Its ONLY caller is the
// background worker, which read `result['sessionId']` on 200 — null for a
// refusal — and debugPrinted on non-200. Both discarded the reason, and there
// is no foreground caller, so at the moment of refusal there is no user, no
// BuildContext and no Riverpod.
//
// DECIDED 2026-08-13: persist always, notify only for the two causes the
// customer can act on, silent for skip_next_active (they asked to skip it).

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/services/sync_refusal_record.dart';

SyncRefusal r(String reason, {String eventId = 'evt_1'}) => SyncRefusal(
      eventId: eventId,
      reason: reason,
      category: 'gameDay',
      message: 'because reasons',
      atMillis: 1,
    );

void main() {
  group('fromResponseBody — a refusal is only ever explicit', () {
    test('success:false + reason -> a refusal carrying the category', () {
      final x = SyncRefusal.fromResponseBody(
        {
          'success': false,
          'reason': kRefusalConsentBlocked,
          'category': 'gameDay',
          'message': 'Your sync consent for "gameDay" is off...',
        },
        eventId: 'evt_9',
        nowMillis: 123,
      );
      expect(x, isNotNull);
      expect(x!.reason, kRefusalConsentBlocked);
      expect(x.category, 'gameDay');
      expect(x.eventId, 'evt_9');
    });

    // A transport hiccup must never manufacture a refusal the server did not
    // issue — the mirror of the client-side rule in gate_status.dart.
    test('a SUCCESS is not a refusal', () {
      expect(
        SyncRefusal.fromResponseBody(
          {'success': true, 'sessionId': 'abc'},
          eventId: 'e',
          nowMillis: 1,
        ),
        isNull,
      );
    });

    test('success:false with NO reason is not actionable, so not a refusal', () {
      expect(
        SyncRefusal.fromResponseBody(
          {'success': false, 'message': 'No eligible participants.'},
          eventId: 'e',
          nowMillis: 1,
        ),
        isNull,
      );
    });

    test('an empty or malformed body yields nothing', () {
      for (final body in <Map<String, Object?>>[
        {},
        {'reason': 'x'},
        {'success': false, 'reason': ''},
        {'success': false, 'reason': 7},
      ]) {
        expect(
          SyncRefusal.fromResponseBody(body, eventId: 'e', nowMillis: 1),
          isNull,
        );
      }
    });
  });

  group('warrantsNotification — silence is a decision', () {
    test('consent_blocked and consent_missing interrupt', () {
      expect(r(kRefusalConsentBlocked).warrantsNotification, isTrue);
      expect(r(kRefusalConsentMissing).warrantsNotification, isTrue);
    });

    // They asked to skip this one. Telling them would be the bug.
    test('skip_next_active is SILENT', () {
      expect(r(kRefusalSkipNext).warrantsNotification, isFalse);
    });

    test('but a silent refusal is still persisted and still titled', () {
      expect(r(kRefusalSkipNext).title, isNotEmpty);
    });
  });

  // CONSTRAINT 1 — NON-REPEATING PER CAUSE. The notification announces the
  // TRANSITION into a refusal state; the banner shows the standing state. The
  // worker retries on its own cadence, so without this one blocked game night
  // would be a stream of identical notifications.
  group('shouldAnnounce — dedup keyed (eventId, reason)', () {
    test('first time announces', () {
      expect(shouldAnnounce(r(kRefusalConsentBlocked), <String>{}), isTrue);
    });

    test('THE PIN: the same event failing the same way announces ONCE', () {
      final x = r(kRefusalConsentBlocked);
      final seen = <String>{};
      var announcements = 0;
      // Ten worker attempts across one blocked game night.
      for (var i = 0; i < 10; i++) {
        if (shouldAnnounce(x, seen)) {
          announcements++;
          seen.add(x.dedupKey);
        }
      }
      expect(announcements, 1);
    });

    test('a DIFFERENT event is news again', () {
      final seen = {r(kRefusalConsentBlocked).dedupKey};
      expect(
        shouldAnnounce(r(kRefusalConsentBlocked, eventId: 'evt_2'), seen),
        isTrue,
      );
    });

    // The same night failing a different way is a different problem with a
    // different fix, so it earns its own notification.
    test('the same event failing a DIFFERENT way is news again', () {
      final seen = {r(kRefusalConsentBlocked).dedupKey};
      expect(shouldAnnounce(r(kRefusalConsentMissing), seen), isTrue);
    });

    test('a silent cause is never announced, seen or not', () {
      expect(shouldAnnounce(r(kRefusalSkipNext), <String>{}), isFalse);
      expect(
        shouldAnnounce(r(kRefusalSkipNext), {r(kRefusalSkipNext).dedupKey}),
        isFalse,
      );
    });

    test('the dedup key is exactly (eventId, reason)', () {
      expect(r(kRefusalConsentBlocked).dedupKey,
          'evt_1::$kRefusalConsentBlocked');
      // Not the message or timestamp: a reworded server message must not
      // re-notify for a problem the customer already knows about.
      final reworded = SyncRefusal(
        eventId: 'evt_1',
        reason: kRefusalConsentBlocked,
        category: 'gameDay',
        message: 'completely different wording',
        atMillis: 999,
      );
      expect(reworded.dedupKey, r(kRefusalConsentBlocked).dedupKey);
    });
  });

  group('round-trip — the banner reads what the worker wrote', () {
    test('toJson/fromJson preserves every field', () {
      final x = r(kRefusalConsentMissing);
      expect(SyncRefusal.fromJson(x.toJson()), x);
    });

    test('a corrupt record yields null rather than a half-refusal', () {
      expect(SyncRefusal.fromJson({'eventId': 1, 'reason': 'x'}), isNull);
      expect(SyncRefusal.fromJson({}), isNull);
    });

    test('missing optional fields degrade to empty, not to a crash', () {
      final x = SyncRefusal.fromJson({'eventId': 'e', 'reason': 'r'});
      expect(x, isNotNull);
      expect(x!.category, '');
      expect(x.message, '');
    });
  });
}
