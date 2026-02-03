import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// Steps in the demo experience flow.
enum DemoStep {
  welcome,
  profile,
  photoCapture,
  rooflineSetup,
  patternPreview,
  schedulePreview,
  explorePatterns,
  luminaGuide,
  completion,
}

/// Extension to provide display names and progress values for demo steps.
extension DemoStepExtension on DemoStep {
  String get displayName {
    switch (this) {
      case DemoStep.welcome:
        return 'Welcome';
      case DemoStep.profile:
        return 'Your Info';
      case DemoStep.photoCapture:
        return 'Your Home';
      case DemoStep.rooflineSetup:
        return 'Roofline';
      case DemoStep.patternPreview:
        return 'Preview';
      case DemoStep.schedulePreview:
        return 'Schedule';
      case DemoStep.explorePatterns:
        return 'Explore';
      case DemoStep.luminaGuide:
        return 'Lumina';
      case DemoStep.completion:
        return 'Get Started';
    }
  }

  /// Progress value from 0.0 to 1.0 for progress indicator.
  double get progressValue {
    return (index + 1) / DemoStep.values.length;
  }

  /// Whether this step can be skipped.
  bool get isSkippable {
    switch (this) {
      case DemoStep.photoCapture:
      case DemoStep.rooflineSetup:
        return true;
      default:
        return false;
    }
  }
}

/// Types of homes for lead qualification.
enum HomeType {
  singleFamily,
  townhome,
  condo,
  commercial,
  other,
}

/// Extension for HomeType display labels.
extension HomeTypeExtension on HomeType {
  String get displayName {
    switch (this) {
      case HomeType.singleFamily:
        return 'Single Family Home';
      case HomeType.townhome:
        return 'Townhome';
      case HomeType.condo:
        return 'Condo';
      case HomeType.commercial:
        return 'Commercial Property';
      case HomeType.other:
        return 'Other';
    }
  }
}

/// How the user heard about Nex-Gen.
enum ReferralSource {
  socialMedia,
  searchEngine,
  friendOrFamily,
  neighborhoodInstallation,
  homeShow,
  advertisement,
  other,
}

/// Extension for ReferralSource display labels.
extension ReferralSourceExtension on ReferralSource {
  String get displayName {
    switch (this) {
      case ReferralSource.socialMedia:
        return 'Social Media';
      case ReferralSource.searchEngine:
        return 'Google / Search Engine';
      case ReferralSource.friendOrFamily:
        return 'Friend or Family';
      case ReferralSource.neighborhoodInstallation:
        return 'Saw a Neighbor\'s Installation';
      case ReferralSource.homeShow:
        return 'Home Show / Event';
      case ReferralSource.advertisement:
        return 'Advertisement';
      case ReferralSource.other:
        return 'Other';
    }
  }
}

/// Preferred contact method for follow-up.
enum ContactMethod {
  phone,
  email,
  text,
}

/// Extension for ContactMethod display labels.
extension ContactMethodExtension on ContactMethod {
  String get displayName {
    switch (this) {
      case ContactMethod.phone:
        return 'Phone Call';
      case ContactMethod.email:
        return 'Email';
      case ContactMethod.text:
        return 'Text Message';
    }
  }

  String get iconName {
    switch (this) {
      case ContactMethod.phone:
        return 'phone';
      case ContactMethod.email:
        return 'email';
      case ContactMethod.text:
        return 'sms';
    }
  }
}

/// Preferred time to be contacted.
enum ContactTime {
  morning,
  afternoon,
  evening,
}

/// Extension for ContactTime display labels.
extension ContactTimeExtension on ContactTime {
  String get displayName {
    switch (this) {
      case ContactTime.morning:
        return 'Morning (9am - 12pm)';
      case ContactTime.afternoon:
        return 'Afternoon (12pm - 5pm)';
      case ContactTime.evening:
        return 'Evening (5pm - 8pm)';
    }
  }
}

/// Lead data captured during the demo experience.
///
/// This data is stored in Firestore for outbound marketing contact.
class DemoLead {
  final String id;
  final String? name;
  final String email;
  final String phone;
  final String? city;
  final String? state;
  final String zipCode;
  final HomeType? homeType;
  final ReferralSource? referralSource;
  final DateTime capturedAt;
  final bool demoCompleted;
  final List<String> patternsViewed;
  final List<ContactRequest> contactRequests;

  const DemoLead({
    required this.id,
    this.name,
    required this.email,
    required this.phone,
    this.city,
    this.state,
    required this.zipCode,
    this.homeType,
    this.referralSource,
    required this.capturedAt,
    this.demoCompleted = false,
    this.patternsViewed = const [],
    this.contactRequests = const [],
  });

  DemoLead copyWith({
    String? id,
    String? name,
    String? email,
    String? phone,
    String? city,
    String? state,
    String? zipCode,
    HomeType? homeType,
    ReferralSource? referralSource,
    DateTime? capturedAt,
    bool? demoCompleted,
    List<String>? patternsViewed,
    List<ContactRequest>? contactRequests,
  }) {
    return DemoLead(
      id: id ?? this.id,
      name: name ?? this.name,
      email: email ?? this.email,
      phone: phone ?? this.phone,
      city: city ?? this.city,
      state: state ?? this.state,
      zipCode: zipCode ?? this.zipCode,
      homeType: homeType ?? this.homeType,
      referralSource: referralSource ?? this.referralSource,
      capturedAt: capturedAt ?? this.capturedAt,
      demoCompleted: demoCompleted ?? this.demoCompleted,
      patternsViewed: patternsViewed ?? this.patternsViewed,
      contactRequests: contactRequests ?? this.contactRequests,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        if (name != null) 'name': name,
        'email': email,
        'phone': phone,
        if (city != null) 'city': city,
        if (state != null) 'state': state,
        'zipCode': zipCode,
        if (homeType != null) 'homeType': homeType!.name,
        if (referralSource != null) 'referralSource': referralSource!.name,
        'capturedAt': Timestamp.fromDate(capturedAt),
        'demoCompleted': demoCompleted,
        'patternsViewed': patternsViewed,
        'contactRequests': contactRequests.map((r) => r.toJson()).toList(),
      };

  factory DemoLead.fromJson(Map<String, dynamic> json) => DemoLead(
        id: json['id'] as String,
        name: json['name'] as String?,
        email: json['email'] as String,
        phone: json['phone'] as String,
        city: json['city'] as String?,
        state: json['state'] as String?,
        zipCode: json['zipCode'] as String,
        homeType: json['homeType'] != null
            ? HomeType.values.firstWhere(
                (e) => e.name == json['homeType'],
                orElse: () => HomeType.other,
              )
            : null,
        referralSource: json['referralSource'] != null
            ? ReferralSource.values.firstWhere(
                (e) => e.name == json['referralSource'],
                orElse: () => ReferralSource.other,
              )
            : null,
        capturedAt: (json['capturedAt'] as Timestamp).toDate(),
        demoCompleted: json['demoCompleted'] as bool? ?? false,
        patternsViewed: (json['patternsViewed'] as List?)
                ?.map((e) => e.toString())
                .toList() ??
            const [],
        contactRequests: (json['contactRequests'] as List?)
                ?.map((e) => ContactRequest.fromJson(e as Map<String, dynamic>))
                .toList() ??
            const [],
      );

  @override
  String toString() => describeIdentity(this);
}

/// A request for contact from a demo lead.
class ContactRequest {
  final ContactMethod method;
  final ContactTime preferredTime;
  final String? notes;
  final DateTime requestedAt;

  const ContactRequest({
    required this.method,
    required this.preferredTime,
    this.notes,
    required this.requestedAt,
  });

  Map<String, dynamic> toJson() => {
        'method': method.name,
        'preferredTime': preferredTime.name,
        if (notes != null) 'notes': notes,
        'requestedAt': Timestamp.fromDate(requestedAt),
      };

  factory ContactRequest.fromJson(Map<String, dynamic> json) => ContactRequest(
        method: ContactMethod.values.firstWhere(
          (e) => e.name == json['method'],
          orElse: () => ContactMethod.phone,
        ),
        preferredTime: ContactTime.values.firstWhere(
          (e) => e.name == json['preferredTime'],
          orElse: () => ContactTime.afternoon,
        ),
        notes: json['notes'] as String?,
        requestedAt: (json['requestedAt'] as Timestamp).toDate(),
      );
}

/// Simplified segment model for demo roofline setup.
///
/// This is a stripped-down version of [RooflineSegment] for the demo experience.
class DemoSegment {
  final String id;
  final String name;
  final int pixelCount;
  final DemoSegmentType type;

  const DemoSegment({
    required this.id,
    required this.name,
    required this.pixelCount,
    required this.type,
  });

  DemoSegment copyWith({
    String? id,
    String? name,
    int? pixelCount,
    DemoSegmentType? type,
  }) {
    return DemoSegment(
      id: id ?? this.id,
      name: name ?? this.name,
      pixelCount: pixelCount ?? this.pixelCount,
      type: type ?? this.type,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'pixelCount': pixelCount,
        'type': type.name,
      };

  factory DemoSegment.fromJson(Map<String, dynamic> json) => DemoSegment(
        id: json['id'] as String,
        name: json['name'] as String,
        pixelCount: json['pixelCount'] as int,
        type: DemoSegmentType.values.firstWhere(
          (e) => e.name == json['type'],
          orElse: () => DemoSegmentType.run,
        ),
      );
}

/// Simplified segment types for demo.
enum DemoSegmentType {
  run,
  corner,
  peak,
}

/// Extension for DemoSegmentType display labels.
extension DemoSegmentTypeExtension on DemoSegmentType {
  String get displayName {
    switch (this) {
      case DemoSegmentType.run:
        return 'Run (Straight Section)';
      case DemoSegmentType.corner:
        return 'Corner';
      case DemoSegmentType.peak:
        return 'Peak / Gable';
    }
  }

  String get shortName {
    switch (this) {
      case DemoSegmentType.run:
        return 'Run';
      case DemoSegmentType.corner:
        return 'Corner';
      case DemoSegmentType.peak:
        return 'Peak';
    }
  }

  /// Default LED count for this segment type.
  int get defaultPixelCount {
    switch (this) {
      case DemoSegmentType.run:
        return 50;
      case DemoSegmentType.corner:
        return 15;
      case DemoSegmentType.peak:
        return 30;
    }
  }
}

/// A simplified schedule item for demo preview.
class DemoScheduleItem {
  final String id;
  final String timeLabel;
  final String? offTimeLabel;
  final List<String> repeatDays;
  final String patternName;
  final String? patternImageUrl;

  const DemoScheduleItem({
    required this.id,
    required this.timeLabel,
    this.offTimeLabel,
    required this.repeatDays,
    required this.patternName,
    this.patternImageUrl,
  });

  /// Whether this schedule runs every day.
  bool get isDaily => repeatDays.length == 7;

  /// Whether this schedule runs only on weekends.
  bool get isWeekendOnly =>
      repeatDays.length == 2 &&
      repeatDays.contains('Sat') &&
      repeatDays.contains('Sun');

  /// Whether this schedule runs only on weekdays.
  bool get isWeekdaysOnly =>
      repeatDays.length == 5 &&
      !repeatDays.contains('Sat') &&
      !repeatDays.contains('Sun');

  String get repeatLabel {
    if (isDaily) return 'Daily';
    if (isWeekendOnly) return 'Weekends';
    if (isWeekdaysOnly) return 'Weekdays';
    return repeatDays.join(', ');
  }
}

/// Pre-defined demo schedules based on common use cases.
class DemoSchedulePresets {
  static List<DemoScheduleItem> generateForProfile({
    required String? zipCode,
    required DateTime currentDate,
  }) {
    final schedules = <DemoScheduleItem>[];

    // Daily warm white at sunset
    schedules.add(const DemoScheduleItem(
      id: 'demo-sunset',
      timeLabel: 'Sunset',
      offTimeLabel: '11:00 PM',
      repeatDays: ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
      patternName: 'Warm White',
      patternImageUrl: null,
    ));

    // Weekend accent lighting
    schedules.add(const DemoScheduleItem(
      id: 'demo-weekend',
      timeLabel: '6:00 PM',
      offTimeLabel: 'Midnight',
      repeatDays: ['Fri', 'Sat'],
      patternName: 'Weekend Vibes',
      patternImageUrl: null,
    ));

    // Add holiday-specific schedule if applicable
    final holiday = _getUpcomingHoliday(currentDate);
    if (holiday != null) {
      schedules.add(DemoScheduleItem(
        id: 'demo-holiday',
        timeLabel: 'Sunset',
        offTimeLabel: '11:30 PM',
        repeatDays: const ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'],
        patternName: holiday.patternName,
        patternImageUrl: null,
      ));
    }

    return schedules;
  }

  static _HolidayInfo? _getUpcomingHoliday(DateTime date) {
    final month = date.month;
    final day = date.day;

    // Check for upcoming holidays within next 30 days
    if (month == 12 || (month == 11 && day > 15)) {
      return const _HolidayInfo('Christmas Classic', 'Christmas');
    }
    if (month == 10) {
      return const _HolidayInfo('Spooky Halloween', 'Halloween');
    }
    if (month == 11 && day <= 15) {
      return const _HolidayInfo('Autumn Harvest', 'Thanksgiving');
    }
    if (month == 7 && day <= 10) {
      return const _HolidayInfo('Patriotic Sparkle', '4th of July');
    }
    if (month == 2 && day <= 14) {
      return const _HolidayInfo('Valentine\'s Glow', 'Valentine\'s Day');
    }
    if (month == 3 && day >= 10 && day <= 17) {
      return const _HolidayInfo('Lucky Green', 'St. Patrick\'s Day');
    }
    if (month == 4 && day <= 20) {
      return const _HolidayInfo('Easter Pastels', 'Easter');
    }

    return null;
  }
}

class _HolidayInfo {
  final String patternName;
  final String holidayName;

  const _HolidayInfo(this.patternName, this.holidayName);
}

/// Curated patterns for the demo explore screen.
class DemoCuratedPatterns {
  /// Quick picks - universal appeal patterns.
  static const List<DemoPatternInfo> quickPicks = [
    DemoPatternInfo(
      id: 'warm-white',
      name: 'Warm White',
      category: 'Quick Picks',
      description: 'Classic warm glow for everyday elegance',
    ),
    DemoPatternInfo(
      id: 'cool-white',
      name: 'Cool White',
      category: 'Quick Picks',
      description: 'Crisp modern white for architectural accent',
    ),
    DemoPatternInfo(
      id: 'soft-amber',
      name: 'Soft Amber',
      category: 'Quick Picks',
      description: 'Gentle amber for cozy evenings',
    ),
  ];

  /// Holiday patterns.
  static const List<DemoPatternInfo> holiday = [
    DemoPatternInfo(
      id: 'christmas-classic',
      name: 'Christmas Classic',
      category: 'Holiday',
      description: 'Traditional red and green with chase effect',
    ),
    DemoPatternInfo(
      id: 'halloween-spooky',
      name: 'Spooky Halloween',
      category: 'Holiday',
      description: 'Orange and purple with flicker effect',
    ),
    DemoPatternInfo(
      id: 'july-4th',
      name: 'Patriotic Sparkle',
      category: 'Holiday',
      description: 'Red, white, and blue celebration',
    ),
  ];

  /// Seasonal patterns.
  static const List<DemoPatternInfo> seasonal = [
    DemoPatternInfo(
      id: 'spring-bloom',
      name: 'Spring Bloom',
      category: 'Seasonal',
      description: 'Soft pinks and greens for spring',
    ),
    DemoPatternInfo(
      id: 'autumn-harvest',
      name: 'Autumn Harvest',
      category: 'Seasonal',
      description: 'Warm oranges and golds for fall',
    ),
  ];

  /// Get all demo patterns.
  static List<DemoPatternInfo> get all => [
        ...quickPicks,
        ...holiday,
        ...seasonal,
      ];
}

/// Pattern info for demo display.
class DemoPatternInfo {
  final String id;
  final String name;
  final String category;
  final String description;

  const DemoPatternInfo({
    required this.id,
    required this.name,
    required this.category,
    required this.description,
  });
}
