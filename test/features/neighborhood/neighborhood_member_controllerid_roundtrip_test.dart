// Tests for the denormalized controllerId[] field on NeighborhoodMember
// (Slice 1 — server-side fanout target resolution). Covers default, toFirestore
// emission, fromFirestore (absent → [], present → preserved, garbage → []),
// roundtrip, and copyWith. Additive + migration-safe: existing docs with no
// controllerId deserialize to an empty list.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

void main() {
  group('NeighborhoodMember.controllerId', () {
    NeighborhoodMember base({List<String>? controllerId}) => NeighborhoodMember(
          oderId: 'u1',
          displayName: 'House A',
          positionIndex: 0,
          lastSeen: DateTime.utc(2026, 6, 30),
          controllerId: controllerId ?? const [],
        );

    test('default is empty list when constructor arg omitted', () {
      final m = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 6, 30),
      );
      expect(m.controllerId, isEmpty);
    });

    test('toFirestore always emits the key', () {
      final map = base(controllerId: ['c1', 'c2']).toFirestore();
      expect(map.containsKey('controllerId'), isTrue);
      expect(map['controllerId'], ['c1', 'c2']);
    });

    test('fromFirestore: absent → empty (migration-safe for existing docs)', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 6, 30)),
        // intentionally no controllerId
      });
      expect(NeighborhoodMember.fromFirestore(snap).controllerId, isEmpty);
    });

    test('fromFirestore: present list preserved (coerced to String)', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 6, 30)),
        'controllerId': ['c1', 'c2', 'c3'],
      });
      expect(NeighborhoodMember.fromFirestore(snap).controllerId,
          ['c1', 'c2', 'c3']);
    });

    test('fromFirestore: non-list garbage → empty (defensive)', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 6, 30)),
        'controllerId': 'not-a-list',
      });
      expect(NeighborhoodMember.fromFirestore(snap).controllerId, isEmpty);
    });

    test('toFirestore → fromFirestore roundtrip preserves the list', () {
      final original = base(controllerId: ['ctrl-a', 'ctrl-b']);
      final snap = _FakeDocumentSnapshot('u1', original.toFirestore());
      expect(NeighborhoodMember.fromFirestore(snap).controllerId,
          ['ctrl-a', 'ctrl-b']);
    });

    test('copyWith sets controllerId; omitting it preserves existing', () {
      final b = base(controllerId: ['x']);
      expect(b.copyWith(controllerId: ['y', 'z']).controllerId, ['y', 'z']);
      expect(b.copyWith(displayName: 'House B').controllerId, ['x']);
    });
  });
}

// ignore: subtype_of_sealed_class
class _FakeDocumentSnapshot implements DocumentSnapshot<Map<String, dynamic>> {
  _FakeDocumentSnapshot(this._id, this._data);

  final String _id;
  final Map<String, dynamic> _data;

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('Not needed by the test surface');
}
