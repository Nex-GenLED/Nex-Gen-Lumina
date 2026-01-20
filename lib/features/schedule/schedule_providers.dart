import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/features/schedule/schedule_models.dart';

class SchedulesNotifier extends StateNotifier<List<ScheduleItem>> {
  SchedulesNotifier() : super(_mockData);

  static final List<ScheduleItem> _mockData = [
    const ScheduleItem(
      id: 'sch-1',
      timeLabel: '7:00 PM',
      repeatDays: ['Mon', 'Wed', 'Fri'],
      actionLabel: 'Pattern: Candy Cane',
      enabled: true,
    ),
    const ScheduleItem(
      id: 'sch-2',
      timeLabel: 'Sunset',
      repeatDays: ['Daily'],
      actionLabel: 'Turn On',
      enabled: false,
    ),
  ];

  void toggle(String id, bool value) {
    state = [
      for (final s in state)
        if (s.id == id) s.copyWith(enabled: value) else s,
    ];
    debugPrint('Schedule $id toggled to $value');
  }

  void add(ScheduleItem item) {
    state = [...state, item];
    debugPrint('Schedule added: ${item.toJson()}');
  }

  void remove(String id) {
    state = state.where((s) => s.id != id).toList(growable: false);
    debugPrint('Schedule removed: $id');
  }

  void update(ScheduleItem item) {
    state = [for (final s in state) if (s.id == item.id) item else s];
    debugPrint('Schedule updated: ${item.toJson()}');
  }
}

final schedulesProvider = StateNotifierProvider<SchedulesNotifier, List<ScheduleItem>>((ref) => SchedulesNotifier());
