import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

void main() {
  group('ScheduleItem', () {
    test('creates with required fields', () {
      final schedule = ScheduleItem(
        id: 'test-1',
        timeLabel: '7:00 PM',
        repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri'],
        actionLabel: 'Pattern: Warm White',
        enabled: true,
      );

      expect(schedule.id, 'test-1');
      expect(schedule.timeLabel, '7:00 PM');
      expect(schedule.repeatDays.length, 5);
      expect(schedule.actionLabel, 'Pattern: Warm White');
      expect(schedule.enabled, true);
    });

    test('creates with optional offTimeLabel', () {
      final schedule = ScheduleItem(
        id: 'test-2',
        timeLabel: 'Sunset',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        actionLabel: 'Pattern: Rainbow',
        enabled: true,
      );

      expect(schedule.offTimeLabel, '11:00 PM');
      expect(schedule.hasOffTime, true);
    });

    test('hasOffTime returns false when offTimeLabel is null', () {
      final schedule = ScheduleItem(
        id: 'test-3',
        timeLabel: '8:00 AM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn Off',
        enabled: true,
      );

      expect(schedule.hasOffTime, false);
    });

    test('hasOffTime returns false when offTimeLabel is empty', () {
      final schedule = ScheduleItem(
        id: 'test-4',
        timeLabel: '8:00 AM',
        offTimeLabel: '',
        repeatDays: ['Mon'],
        actionLabel: 'Turn Off',
        enabled: true,
      );

      expect(schedule.hasOffTime, false);
    });

    test('toJson serializes correctly', () {
      final schedule = ScheduleItem(
        id: 'test-5',
        timeLabel: '6:30 PM',
        offTimeLabel: 'Sunrise',
        repeatDays: ['Sat', 'Sun'],
        actionLabel: 'Pattern: Party Mode',
        enabled: false,
      );

      final json = schedule.toJson();

      expect(json['id'], 'test-5');
      expect(json['timeLabel'], '6:30 PM');
      expect(json['offTimeLabel'], 'Sunrise');
      expect(json['repeatDays'], ['Sat', 'Sun']);
      expect(json['actionLabel'], 'Pattern: Party Mode');
      expect(json['enabled'], false);
    });

    test('toJson excludes null offTimeLabel', () {
      final schedule = ScheduleItem(
        id: 'test-6',
        timeLabel: '9:00 PM',
        repeatDays: ['Fri'],
        actionLabel: 'Turn On',
        enabled: true,
      );

      final json = schedule.toJson();

      expect(json.containsKey('offTimeLabel'), false);
    });

    test('fromJson deserializes correctly', () {
      final json = {
        'id': 'test-7',
        'timeLabel': 'Sunset',
        'offTimeLabel': '10:00 PM',
        'repeatDays': ['Mon', 'Wed', 'Fri'],
        'actionLabel': 'Pattern: Candy Cane',
        'enabled': true,
      };

      final schedule = ScheduleItem.fromJson(json);

      expect(schedule.id, 'test-7');
      expect(schedule.timeLabel, 'Sunset');
      expect(schedule.offTimeLabel, '10:00 PM');
      expect(schedule.repeatDays, ['Mon', 'Wed', 'Fri']);
      expect(schedule.actionLabel, 'Pattern: Candy Cane');
      expect(schedule.enabled, true);
    });

    test('fromJson handles null offTimeLabel', () {
      final json = {
        'id': 'test-8',
        'timeLabel': '7:00 AM',
        'repeatDays': ['Tue'],
        'actionLabel': 'Turn Off',
        'enabled': false,
      };

      final schedule = ScheduleItem.fromJson(json);

      expect(schedule.offTimeLabel, isNull);
      expect(schedule.hasOffTime, false);
    });

    test('roundtrip serialization preserves data', () {
      final original = ScheduleItem(
        id: 'roundtrip-test',
        timeLabel: 'Sunset + 30min',
        offTimeLabel: 'Sunrise - 15min',
        repeatDays: ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'],
        actionLabel: 'Pattern: Evening Glow',
        enabled: true,
      );

      final json = original.toJson();
      final restored = ScheduleItem.fromJson(json);

      expect(restored.id, original.id);
      expect(restored.timeLabel, original.timeLabel);
      expect(restored.offTimeLabel, original.offTimeLabel);
      expect(restored.repeatDays, original.repeatDays);
      expect(restored.actionLabel, original.actionLabel);
      expect(restored.enabled, original.enabled);
    });

    test('copyWith creates modified copy', () {
      final original = ScheduleItem(
        id: 'copy-test',
        timeLabel: '8:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn On',
        enabled: true,
      );

      final modified = original.copyWith(
        enabled: false,
        repeatDays: ['Mon', 'Tue'],
      );

      expect(modified.id, original.id);
      expect(modified.timeLabel, original.timeLabel);
      expect(modified.enabled, false);
      expect(modified.repeatDays, ['Mon', 'Tue']);
    });

    test('copyWith clearOffTime removes offTimeLabel', () {
      final original = ScheduleItem(
        id: 'clear-test',
        timeLabel: '8:00 PM',
        offTimeLabel: '11:00 PM',
        repeatDays: ['Mon'],
        actionLabel: 'Turn On',
        enabled: true,
      );

      final modified = original.copyWith(clearOffTime: true);

      expect(modified.offTimeLabel, isNull);
      expect(modified.hasOffTime, false);
    });

    test('fromJson converts repeatDays elements to strings', () {
      final json = {
        'id': 'type-test',
        'timeLabel': '9:00 PM',
        'repeatDays': [1, 2, 3], // Numbers instead of strings
        'actionLabel': 'Test',
        'enabled': true,
      };

      final schedule = ScheduleItem.fromJson(json);

      expect(schedule.repeatDays, ['1', '2', '3']);
    });
  });
}
