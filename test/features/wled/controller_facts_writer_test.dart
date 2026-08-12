// The shared device-facts writer: one write for two families, one timestamp
// discipline, and the publish history that makes dedup auditable in production.
//
// Runs against fake_cloud_firestore so the actual document that lands is
// asserted, not just the map that was built.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/base_boundary_denormalizer.dart';
import 'package:nexgen_command/features/wled/controller_facts_publisher.dart';
import 'package:nexgen_command/features/wled/controller_facts_writer.dart';
import 'package:nexgen_command/features/wled/participation_denormalizer.dart';

const _uid = 'u1';
const _ctrl = '192_168_1_150';

DocumentReference<Map<String, dynamic>> _doc(FakeFirebaseFirestore db) => db
    .collection('users')
    .doc(_uid)
    .collection('controllers')
    .doc(_ctrl);

Future<Map<String, dynamic>> _read(FakeFirebaseFirestore db) async =>
    (await _doc(db).get()).data() ?? <String, dynamic>{};

List<BaseBoundaryRow> _rows({int hour = 20}) => [
      BaseBoundaryRow(
        index: 0,
        kind: kBoundaryKindClock,
        hour: hour,
        minute: 23,
        dow: 127,
        macro: 10,
        role: 'schedule',
      ),
    ];

/// [timersReadable] false models an unreadable timer table (relay, failed cfg
/// read) — distinct from a readable-but-empty one, which is `rows: const []`.
Future<bool> _publishBoth(
  FakeFirebaseFirestore db, {
  List<int>? participation = const [0, 1],
  List<int> deviceChannelIds = const [0, 1, 2],
  List<BaseBoundaryRow>? rows,
  bool timersReadable = true,
  int slotsRead = 10,
  String source = 'healer',
}) {
  return writeControllerFacts(
    controllerId: _ctrl,
    families: [
      prepareParticipationFacts(
        controllerId: _ctrl,
        resolved: participation,
        deviceChannelIds: deviceChannelIds,
        source: source,
      ),
      prepareBaseBoundaryFacts(
        controllerId: _ctrl,
        rows: timersReadable ? (rows ?? _rows()) : null,
        slotsRead: slotsRead,
        source: source,
      ),
    ],
    label: source,
    firestore: db,
    uidOverride: _uid,
  );
}

void main() {
  late FakeFirebaseFirestore db;

  setUp(() {
    db = FakeFirebaseFirestore();
    resetParticipationMemo();
    resetBaseBoundariesMemo();
  });

  group('one write, both families', () {
    test('a connect lands participation AND base boundaries together', () {
      // The whole reason the two share a writer: they come from ONE /json/cfg
      // read and land on ONE document, so they should cost ONE write.
      return _publishBoth(db).then((ok) async {
        expect(ok, isTrue);
        final d = await _read(db);
        expect(d[kParticipatingChannelsField], [0, 1]);
        expect(d[kParticipatingChannelsDeviceIdsField], [0, 1, 2]);
        expect((d[kBaseBoundariesField] as List).single['hour'], 20);
        expect(d[kBaseBoundariesSlotsReadField], 10);
      });
    });

    test('both families get their own timestamp and source', () async {
      await _publishBoth(db);
      final d = await _read(db);
      expect(d[factAtField(kParticipatingChannelsField)], isNotNull);
      expect(d[factAtField(kBaseBoundariesField)], isNotNull);
      expect(d[factSourceField(kParticipatingChannelsField)], 'healer');
      expect(d[factSourceField(kBaseBoundariesField)], 'healer');
    });

    test('a family that abstains does not block the other', () async {
      // Unreadable timer table, readable bus list → participation still lands.
      await _publishBoth(db, timersReadable: false);
      final d = await _read(db);
      expect(d[kParticipatingChannelsField], [0, 1]);
      expect(d.containsKey(kBaseBoundariesField), isFalse);
    });

    test('when BOTH abstain there is no write at all', () async {
      final ok = await _publishBoth(db, participation: null, timersReadable: false);
      expect(ok, isFalse);
      expect((await _doc(db).get()).exists, isFalse);
    });
  });

  group('STEP 6 — both families ride ONE set(merge:true)', () {
    // Counted by DOCUMENT MUTATIONS, not by inspecting the result: a snapshot
    // listener fires once per write, so two writes are visible even though
    // they would leave the document looking identical. Until the ordering fix
    // this was untestable in practice — participation always abstained, so a
    // real connect only ever exercised one family.
    Future<int> mutationsDuring(Future<void> Function() body) async {
      var n = 0;
      final sub = _doc(db).snapshots().listen((_) => n++);
      await pumpEventQueue();
      n = 0; // discard the initial emission
      await body();
      await pumpEventQueue();
      await sub.cancel();
      return n;
    }

    test('two populated families produce exactly ONE document mutation',
        () async {
      final n = await mutationsDuring(() => _publishBoth(db));
      expect(n, 1, reason: 'one set(merge:true), not one per family');

      final d = await _read(db);
      expect(d[kParticipatingChannelsField], isNotNull);
      expect(d[kBaseBoundariesField], isNotNull);
      expect(d[factPublishCountField(kParticipatingChannelsField)], 1);
      expect(d[factPublishCountField(kBaseBoundariesField)], 1);
    });

    test('both families share the SAME server timestamp', () async {
      // Different timestamps would mean two writes even if the count matched.
      await _publishBoth(db);
      final d = await _read(db);
      expect(d[factAtField(kParticipatingChannelsField)],
          equals(d[factAtField(kBaseBoundariesField)]));
    });

    test('one family deduped still costs exactly one mutation, not zero and '
        'not two', () async {
      await _publishBoth(db);
      final n = await mutationsDuring(
          () => _publishBoth(db, participation: [0]));
      expect(n, 1);
      final d = await _read(db);
      expect(d[factPublishCountField(kParticipatingChannelsField)], 2);
      expect(d[factPublishCountField(kBaseBoundariesField)], 1,
          reason: 'deduped — carried along by the write but not rewritten');
    });

    test('both deduped produces ZERO mutations', () async {
      await _publishBoth(db);
      final n = await mutationsDuring(() => _publishBoth(db));
      expect(n, 0);
    });
  });

  group('publish history — part 3', () {
    test('the counter increments once per write, per family', () async {
      await _publishBoth(db);
      expect((await _read(db))[factPublishCountField(kParticipatingChannelsField)],
          1);

      // Change both families so neither dedups.
      await _publishBoth(db, participation: [0], rows: _rows(hour: 21));
      final d = await _read(db);
      expect(d[factPublishCountField(kParticipatingChannelsField)], 2);
      expect(d[factPublishCountField(kBaseBoundariesField)], 2);
    });

    test('a DEDUPED family does not increment — this is what makes dedup '
        'auditable', () async {
      // Without the counter, last-wins cannot tell "deduped" from
      // "republished with identical content". Here participation changes and
      // base boundaries do not; only one counter moves.
      await _publishBoth(db);
      await _publishBoth(db, participation: [0]);
      final d = await _read(db);
      expect(d[factPublishCountField(kParticipatingChannelsField)], 2);
      expect(d[factPublishCountField(kBaseBoundariesField)], 1);
    });

    test('_previous carries the value that was superseded', () async {
      await _publishBoth(db, participation: [0, 1]);
      await _publishBoth(db, participation: [0]);
      expect((await _read(db))[factPreviousField(kParticipatingChannelsField)],
          [0, 1]);
    });

    test('_previous is ABSENT on the first write of a session, not stale',
        () async {
      // The memo is process-scoped and never reads Firestore, so the app
      // genuinely does not know what a prior session left. Leaving a
      // two-sessions-old _previous beside a fresh _at would read as a change
      // that never happened, so the key is deleted instead.
      await _publishBoth(db, participation: [0, 1]);
      expect(
        (await _read(db)).containsKey(
            factPreviousField(kParticipatingChannelsField)),
        isFalse,
      );

      await _publishBoth(db, participation: [0]); // writes _previous
      expect(
        (await _read(db)).containsKey(
            factPreviousField(kParticipatingChannelsField)),
        isTrue,
      );

      // New session: memo cold, value unchanged from what Firestore holds.
      resetParticipationMemo();
      await _publishBoth(db, participation: [0]);
      final d = await _read(db);
      expect(d[factPublishCountField(kParticipatingChannelsField)], 3,
          reason: 'a cold memo republishes — the deliberate self-heal');
      expect(d.containsKey(factPreviousField(kParticipatingChannelsField)),
          isFalse,
          reason: 'the stale _previous must be cleared, not carried forward');
    });
  });

  group('memo commits only on a successful write', () {
    test('a write that never happened leaves the memo cold, so the next '
        'attempt retries', () async {
      // No uid → the write is refused. If prepare had committed the memo
      // eagerly, the retry would dedup against a value that was never stored.
      final ok = await writeControllerFacts(
        controllerId: _ctrl,
        families: [
          prepareParticipationFacts(
            controllerId: _ctrl,
            resolved: [0, 1],
            deviceChannelIds: [0, 1],
            source: 'healer',
          ),
        ],
        label: 'healer',
        firestore: db,
        uidOverride: '',
      );
      expect(ok, isFalse);
      expect(publishedParticipationMemo.containsKey(_ctrl), isFalse);

      expect(await _publishBoth(db), isTrue);
      expect((await _read(db))[kParticipatingChannelsField], [0, 1]);
    });
  });

  group('participation refuses an unknown device shape', () {
    test('an empty bus list publishes NOTHING, even though the resolver '
        'returned a set', () async {
      // deviceHardwareConfigProvider is a FutureProvider fed by the same
      // /json/cfg and is routinely still in flight early in a session.
      // Resolving against an empty bus list yields [], and [] is a USABLE
      // verdict server-side meaning "light nothing" — so publishing it would
      // silently darken a house that expected a show.
      expect(participationShapeIsKnown(const []), isFalse);
      final ok = await _publishBoth(
        db,
        participation: const [],
        deviceChannelIds: const [],
        timersReadable: false,
      );
      expect(ok, isFalse);
      expect((await _doc(db).get()).exists, isFalse);
    });

    test('a real bus list publishes an empty resolution — that IS an answer',
        () async {
      await _publishBoth(
        db,
        participation: const [],
        deviceChannelIds: const [0, 1],
        timersReadable: false,
      );
      expect((await _read(db))[kParticipatingChannelsField], isEmpty);
    });
  });

  group('the writer never throws', () {
    test('no controller id → false, no write, no throw', () async {
      expect(
        await writeControllerFacts(
          controllerId: null,
          families: [PreparedFacts({'x': 1}, () {})],
          label: 't',
          firestore: db,
          uidOverride: _uid,
        ),
        isFalse,
      );
    });

    test('a commit that throws does not fail the write or skip the OTHER '
        "family's commit", () async {
      // Commits are bookkeeping that runs after the document has landed. One
      // throwing must not (a) surface as an exception into a heal, (b) report
      // a successful write as failed, or (c) skip a sibling's memo update —
      // which would leave that family republishing forever.
      var siblingCommitted = false;
      final ok = await writeControllerFacts(
        controllerId: _ctrl,
        families: [
          PreparedFacts({'probe': 1}, () => throw StateError('boom')),
          PreparedFacts({'sibling': 2}, () => siblingCommitted = true),
        ],
        label: 't',
        firestore: db,
        uidOverride: _uid,
      );
      expect(ok, isTrue);
      expect(siblingCommitted, isTrue);
      final d = await _read(db);
      expect(d['probe'], 1);
      expect(d['sibling'], 2);
    });
  });

  group('FirestoreControllerFactsPublisher', () {
    test('is the healer source tag', () {
      expect(kHealerPublishSource, 'healer');
    });

    test('does nothing without a controller id', () async {
      final wrote = await const FirestoreControllerFactsPublisher()
          .publishDeviceFacts(
        controllerId: null,
        participation: const ParticipationInput(
            resolved: [0], deviceChannelIds: [0]),
        baseBoundaries: const [],
        slotsRead: 10,
        source: kHealerPublishSource,
      );
      expect(wrote, isFalse);
      // No throw, no Firestore touched (the real instance has no injected db;
      // reaching Firestore here would blow up on an uninitialized app).
    });
  });

  group('single-family entry point still works for the resolve sites', () {
    test('publishParticipatingChannels writes only its own family', () async {
      await publishParticipatingChannels(
        controllerId: _ctrl,
        resolved: [0, 1],
        deviceChannelIds: [0, 1],
        source: 'game_day',
        firestore: db,
        uidOverride: _uid,
      );
      final d = await _read(db);
      expect(d[kParticipatingChannelsField], [0, 1]);
      expect(d[factSourceField(kParticipatingChannelsField)], 'game_day');
      expect(d.containsKey(kBaseBoundariesField), isFalse);
    });

    test('a null resolution is still not published', () async {
      await publishParticipatingChannels(
        controllerId: _ctrl,
        resolved: null,
        deviceChannelIds: [0, 1],
        source: 'game_day',
        firestore: db,
        uidOverride: _uid,
      );
      expect((await _doc(db).get()).exists, isFalse);
    });
  });
}
