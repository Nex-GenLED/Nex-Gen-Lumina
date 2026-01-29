import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/wled_repository.dart';

void main() {
  group('WledSegment.fromMap', () {
    test('parses valid segment data correctly', () {
      final segment = WledSegment.fromMap({
        'id': 0,
        'n': 'Front Lights',
        'start': 0,
        'stop': 150,
      }, 0);

      expect(segment.id, 0);
      expect(segment.name, 'Front Lights');
      expect(segment.start, 0);
      expect(segment.stop, 150);
      expect(segment.ledCount, 150);
    });

    test('uses fallback name when name is missing', () {
      final segment = WledSegment.fromMap({
        'id': 2,
        'start': 0,
        'stop': 100,
      }, 2);

      expect(segment.name, 'Channel 3'); // 1-indexed for display
    });

    test('uses fallback name when name is empty string', () {
      final segment = WledSegment.fromMap({
        'id': 1,
        'n': '   ',
        'start': 0,
        'stop': 50,
      }, 1);

      expect(segment.name, 'Channel 2');
    });

    test('uses fallbackIndex when id is missing', () {
      final segment = WledSegment.fromMap({
        'n': 'Roof',
        'start': 100,
        'stop': 200,
      }, 5);

      expect(segment.id, 5);
    });

    test('handles malformed data without crashing', () {
      final segment = WledSegment.fromMap({
        'garbage': true,
        'random': 'data',
      }, 0);

      expect(segment.id, 0);
      expect(segment.name, 'Channel 1');
      expect(segment.ledCount, 0);
    });

    test('handles null map values gracefully', () {
      final segment = WledSegment.fromMap({
        'id': null,
        'n': null,
        'start': null,
        'stop': null,
      }, 3);

      expect(segment.id, 3);
      expect(segment.name, 'Channel 4');
    });

    test('calculates ledCount correctly', () {
      final segment = WledSegment.fromMap({
        'id': 0,
        'start': 50,
        'stop': 200,
      }, 0);

      expect(segment.ledCount, 150); // 200 - 50
    });

    test('clamps negative ledCount to zero', () {
      final segment = WledSegment.fromMap({
        'id': 0,
        'start': 200,
        'stop': 50, // Invalid: stop < start
      }, 0);

      expect(segment.ledCount, 0);
    });

    test('handles numeric id as double', () {
      final segment = WledSegment.fromMap({
        'id': 2.0,
        'n': 'Test',
      }, 0);

      expect(segment.id, 2);
    });
  });
}
