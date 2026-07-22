// Tests for the per-member isParticipating flag on NeighborhoodMember
// (Symptom-2 fix scaffolding for the 3dbca29 cross-member revert regression).
// Covers serialization (toFirestore always emits the key), deserialization
// (absent → false default, present=true/false → preserved), and copyWith
// semantics (set/preserve).

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/neighborhood/neighborhood_models.dart';

void main() {
  group('NeighborhoodMember.isParticipating', () {
    test('default value is false when constructor arg omitted', () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
      );
      expect(member.isParticipating, isFalse);
    });

    test('toFirestore always emits the key (true)', () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: true,
      );
      final map = member.toFirestore();
      expect(map.containsKey('isParticipating'), isTrue);
      expect(map['isParticipating'], isTrue);
    });

    test('toFirestore always emits the key (false)', () {
      final member = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: false,
      );
      final map = member.toFirestore();
      expect(map.containsKey('isParticipating'), isTrue);
      expect(map['isParticipating'], isFalse);
    });

    test('fromFirestore: absent → defaults to false (migration-safe for '
        'existing docs written before this field shipped)', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 30)),
        // intentionally no isParticipating
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.isParticipating, isFalse);
    });

    test('fromFirestore: present=true → true', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 30)),
        'isParticipating': true,
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.isParticipating, isTrue);
    });

    test('fromFirestore: present=false → false', () {
      final snap = _FakeDocumentSnapshot('u1', {
        'displayName': 'House A',
        'positionIndex': 0,
        'lastSeen': Timestamp.fromDate(DateTime.utc(2026, 5, 30)),
        'isParticipating': false,
      });
      final member = NeighborhoodMember.fromFirestore(snap);
      expect(member.isParticipating, isFalse);
    });

    test('toFirestore → fromFirestore roundtrip preserves true', () {
      final original = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: true,
      );
      final snap = _FakeDocumentSnapshot('u1', original.toFirestore());
      final restored = NeighborhoodMember.fromFirestore(snap);
      expect(restored.isParticipating, isTrue);
    });

    test('toFirestore → fromFirestore roundtrip preserves false', () {
      final original = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: false,
      );
      final snap = _FakeDocumentSnapshot('u1', original.toFirestore());
      final restored = NeighborhoodMember.fromFirestore(snap);
      expect(restored.isParticipating, isFalse);
    });

    test('copyWith(isParticipating: true) flips false→true without touching '
        'other fields', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
      );
      final updated = base.copyWith(isParticipating: true);
      expect(updated.isParticipating, isTrue);
      expect(updated.displayName, equals('House A'));
      expect(updated.positionIndex, equals(0));
    });

    test('copyWith(isParticipating: false) flips true→false', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: true,
      );
      final updated = base.copyWith(isParticipating: false);
      expect(updated.isParticipating, isFalse);
    });

    test('copyWith without isParticipating arg preserves existing value', () {
      final base = NeighborhoodMember(
        oderId: 'u1',
        displayName: 'House A',
        positionIndex: 0,
        lastSeen: DateTime.utc(2026, 5, 30),
        isParticipating: true,
      );
      final updated = base.copyWith(displayName: 'House B');
      expect(updated.isParticipating, isTrue);
      expect(updated.displayName, equals('House B'));
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
