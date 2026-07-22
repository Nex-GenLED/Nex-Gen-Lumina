import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';

/// A full commercial lighting schedule for a single location.
///
/// Contains day-parts, a fallback ambient design for Smart Fill gaps,
/// a coverage policy, and corporate lock state.
class CommercialSchedule {
  final String locationId;
  final List<DayPart> dayParts;
  final String? defaultAmbientDesignId;
  final CoveragePolicy coveragePolicy;
  final bool isLockedByCorporate;
  final DateTime? lockExpiryDate;

  const CommercialSchedule({
    required this.locationId,
    this.dayParts = const [],
    this.defaultAmbientDesignId,
    this.coveragePolicy = CoveragePolicy.smartFill,
    this.isLockedByCorporate = false,
    this.lockExpiryDate,
  });

  factory CommercialSchedule.fromJson(Map<String, dynamic> json) {
    return CommercialSchedule(
      locationId: json['location_id'] as String,
      dayParts: (json['day_parts'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => DayPart.fromJson(e))
              .toList() ??
          const [],
      defaultAmbientDesignId:
          json['default_ambient_design_id'] as String?,
      coveragePolicy:
          _parseCoveragePolicy(json['coverage_policy'] as String?),
      isLockedByCorporate:
          (json['is_locked_by_corporate'] as bool?) ?? false,
      lockExpiryDate: json['lock_expiry_date'] != null
          ? DateTime.tryParse(json['lock_expiry_date'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'location_id': locationId,
        'day_parts': dayParts.map((e) => e.toJson()).toList(),
        if (defaultAmbientDesignId != null)
          'default_ambient_design_id': defaultAmbientDesignId,
        'coverage_policy': _coveragePolicyStr(coveragePolicy),
        'is_locked_by_corporate': isLockedByCorporate,
        if (lockExpiryDate != null)
          'lock_expiry_date': lockExpiryDate!.toIso8601String(),
      };

  CommercialSchedule copyWith({
    String? locationId,
    List<DayPart>? dayParts,
    String? defaultAmbientDesignId,
    CoveragePolicy? coveragePolicy,
    bool? isLockedByCorporate,
    DateTime? lockExpiryDate,
  }) {
    return CommercialSchedule(
      locationId: locationId ?? this.locationId,
      dayParts: dayParts ?? this.dayParts,
      defaultAmbientDesignId:
          defaultAmbientDesignId ?? this.defaultAmbientDesignId,
      coveragePolicy: coveragePolicy ?? this.coveragePolicy,
      isLockedByCorporate:
          isLockedByCorporate ?? this.isLockedByCorporate,
      lockExpiryDate: lockExpiryDate ?? this.lockExpiryDate,
    );
  }

  // -- helpers ---------------------------------------------------------------

  static CoveragePolicy _parseCoveragePolicy(String? v) {
    switch (v) {
      case 'always_on':
        return CoveragePolicy.alwaysOn;
      case 'smart_fill':
        return CoveragePolicy.smartFill;
      case 'scheduled_only':
        return CoveragePolicy.scheduledOnly;
      default:
        return CoveragePolicy.smartFill;
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
