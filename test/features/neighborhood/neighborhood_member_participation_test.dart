// Tests for the participatingChannelIndices field on NeighborhoodMember.
// Covers serialization (toFirestore omits when null, includes when set),
// deserialization (absent → null, present → parsed), and copyWith semantics
// (set value, clear back to null via the explicit flag).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

void main() {
  group('NeighborhoodMember.participatingChannelIndices', () {
    test('toFirestore omits the key when participatingChannelIndices is null',
        () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
      );
      expect(member.participatingChannelIndices, isNull);
      final map = member.toFirestore();
      expect(map.containsKey('participatingChannelIndices'), isFalse);
    });

    test('toFirestore includes the key when participatingChannelIndices is set',
        () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
        participatingChannelIndices: const [0, 2],
      );
      final map = member.toFirestore();
      expect(map['participatingChannelIndices'], equals([0, 2]));
    });

    test('toFirestore includes an empty list explicitly (distinct from null)',
        () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
        participatingChannelIndices: const [],
      );
      final map = member.toFirestore();
      expect(map.containsKey('participatingChannelIndices'), isTrue);
      expect(map['participatingChannelIndices'], isEmpty);
    });

    test('fromFirestore returns null when the field is absent (legacy doc)',
        () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
        // intentionally no participatingChannelIndices
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.participatingChannelIndices, isNull);
    });

    test('fromFirestore parses a present list of ints', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
        'participatingChannelIndices': [0, 2],
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.participatingChannelIndices, equals([0, 2]));
    });

    test('fromFirestore parses an empty list as []', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 21)),
        'participatingChannelIndices': <int>[],
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.participatingChannelIndices, isNotNull);
      expect(member.participatingChannelIndices, isEmpty);
    });

    test('copyWith sets a value when supplied', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
      );
      final updated = base.copyWith(participatingChannelIndices: [1]);
      expect(updated.participatingChannelIndices, equals([1]));
    });

    test('copyWith without arg preserves the existing non-null value', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
        participatingChannelIndices: const [0, 1],
      );
      final updated = base.copyWith(displayName: 'House B');
      expect(updated.participatingChannelIndices, equals([0, 1]));
    });

    test(
        'copyWith with clearParticipatingChannelIndices: true sets it back to '
        'null (the picker "clear my override" operation)', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 21),
        participatingChannelIndices: const [0, 1],
      );
      final cleared = base.copyWith(clearParticipatingChannelIndices: true);
      expect(cleared.participatingChannelIndices, isNull);
    });
  });
}

// DocumentSnapshot is sealed in cloud_firestore; implementing it for a
// scoped test fake is intentional. Only `id` and `data()` are exercised.
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
