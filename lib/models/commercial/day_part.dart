import 'package:flutter/material.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';

/// A named time window within a business day (e.g. "Happy Hour", "Late Night").
///
/// Day-parts slot into a [CommercialSchedule] and drive the Day-Part Engine.
/// Each part can optionally assign a design, inherit or override coverage
/// policy, and flag itself as a Game Day override.
class DayPart {
  final String id;
  final String name;
  final TimeOfDay startTime;
  final TimeOfDay endTime;
  final String? assignedDesignId;
  final bool useBrandColors;
  final CoveragePolicy? coveragePolicy;
  final List<DayOfWeek> daysOfWeek;
  final bool isGameDayOverride;

  const DayPart({
    required this.id,
    required this.name,
    required this.startTime,
    required this.endTime,
    this.assignedDesignId,
    this.useBrandColors = true,
    this.coveragePolicy,
    this.daysOfWeek = const [],
    this.isGameDayOverride = false,
  });

  factory DayPart.fromJson(Map<String, dynamic> json) {
    return DayPart(
      id: json['id'] as String,
      name: json['name'] as String,
      startTime: _parseTime(json['start_time'] as String?) ??
          const TimeOfDay(hour: 0, minute: 0),
      endTime: _parseTime(json['end_time'] as String?) ??
          const TimeOfDay(hour: 0, minute: 0),
      assignedDesignId: json['assigned_design_id'] as String?,
      useBrandColors: (json['use_brand_colors'] as bool?) ?? true,
      coveragePolicy: _parseCoveragePolicyNullable(
          json['coverage_policy'] as String?),
      daysOfWeek: (json['days_of_week'] as List?)
              ?.map((e) => _parseDow(e.toString()))
              .toList() ??
          const [],
      isGameDayOverride:
          (json['is_game_day_override'] as bool?) ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'start_time': _timeStr(startTime),
        'end_time': _timeStr(endTime),
        if (assignedDesignId != null) 'assigned_design_id': assignedDesignId,
        'use_brand_colors': useBrandColors,
        if (coveragePolicy != null)
          'coverage_policy': _coveragePolicyStr(coveragePolicy!),
        'days_of_week': daysOfWeek.map((d) => d.name).toList(),
        'is_game_day_override': isGameDayOverride,
      };

  DayPart copyWith({
    String? id,
    String? name,
    TimeOfDay? startTime,
    TimeOfDay? endTime,
    String? assignedDesignId,
    bool? useBrandColors,
    CoveragePolicy? coveragePolicy,
    List<DayOfWeek>? daysOfWeek,
    bool? isGameDayOverride,
  }) {
    return DayPart(
      id: id ?? this.id,
      name: name ?? this.name,
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
      assignedDesignId: assignedDesignId ?? this.assignedDesignId,
      useBrandColors: useBrandColors ?? this.useBrandColors,
      coveragePolicy: coveragePolicy ?? this.coveragePolicy,
      daysOfWeek: daysOfWeek ?? this.daysOfWeek,
      isGameDayOverride: isGameDayOverride ?? this.isGameDayOverride,
    );
  }

  /// Whether [now] falls within this day-part's time window.
  bool isActiveAt(DateTime now) {
    final day = dayOfWeekFromIso(now.weekday);
    if (daysOfWeek.isNotEmpty && !daysOfWeek.contains(day)) return false;
    final nowMin = now.hour * 60 + now.minute;
    final startMin = startTime.hour * 60 + startTime.minute;
    final endMin = endTime.hour * 60 + endTime.minute;
    if (endMin > startMin) {
      return nowMin >= startMin && nowMin < endMin;
    }
    // Overnight span.
    return nowMin >= startMin || nowMin < endMin;
  }

  // -- serialization helpers -------------------------------------------------

  static TimeOfDay? _parseTime(String? hhmm) {
    if (hhmm == null) return null;
    final parts = hhmm.split(':');
    if (parts.length != 2) return null;
    final h = int.tryParse(parts[0]);
    final m = int.tryParse(parts[1]);
    if (h == null || m == null) return null;
    return TimeOfDay(hour: h, minute: m);
  }

  static String _timeStr(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static DayOfWeek _parseDow(String v) {
    for (final d in DayOfWeek.values) {
      if (d.name == v) return d;
    }
    return DayOfWeek.monday;
  }

  static CoveragePolicy? _parseCoveragePolicyNullable(String? v) {
    switch (v) {
      case 'always_on':
        return CoveragePolicy.alwaysOn;
      case 'smart_fill':
        return CoveragePolicy.smartFill;
      case 'scheduled_only':
        return CoveragePolicy.scheduledOnly;
      default:
        return null;
    }
  }

  static String _coveragePolicyStr(CoveragePolicy p) {
    switch (p) {
      case CoveragePolicy.alwaysOn:
        return 'always_on';
      case CoveragePolicy.smartFill:
        return 'smart_fill';
      case CoveragePolicy.scheduledOnly:
        return 'scheduled_only';
    }
  }
}
