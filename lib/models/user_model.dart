import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:nexgen_command/models/custom_holiday.dart';

/// Annual seasonal color window model
class SeasonalColorWindow {
  final int startMonth; // 1..12
  final int startDay; // 1..31
  final int endMonth; // 1..12
  final int endDay; // 1..31

  const SeasonalColorWindow({
    required this.startMonth,
    required this.startDay,
    required this.endMonth,
    required this.endDay,
  });

  factory SeasonalColorWindow.fromJson(Map<String, dynamic> json) => SeasonalColorWindow(
        startMonth: (json['start_month'] as num).toInt(),
        startDay: (json['start_day'] as num).toInt(),
        endMonth: (json['end_month'] as num).toInt(),
        endDay: (json['end_day'] as num).toInt(),
      );

  Map<String, dynamic> toJson() => {
        'start_month': startMonth,
        'start_day': startDay,
        'end_month': endMonth,
        'end_day': endDay,
      };

  SeasonalColorWindow copyWith({int? startMonth, int? startDay, int? endMonth, int? endDay}) => SeasonalColorWindow(
        startMonth: startMonth ?? this.startMonth,
        startDay: startDay ?? this.startDay,
        endMonth: endMonth ?? this.endMonth,
        endDay: endDay ?? this.endDay,
      );
}

/// User profile data model
class UserModel {
  final String id;
  final String email;
  final String displayName;
  final String? photoUrl;
  final String ownerId;
  final DateTime createdAt;
  final DateTime updatedAt;

  // Profile enrichment for personalization and suggestions
  final String? location; // freeform city/region/country
  final String? timeZone; // e.g., America/Chicago
  final List<String> preferredCategoryIds; // aligns with PatternCategory ids
  final List<String> interestTags; // freeform: teams, holidays, keywords
  final bool allowSuggestions; // enable seasonal/event suggestions
  final List<String> dislikes; // negative preferences (effects, colors, vibes)

  // Extended profile fields
  final String? phoneNumber;
  final String? address; // Home address (multi-line)
  final double? latitude; // Geocoded lat from address
  final double? longitude; // Geocoded lon from address

  // Lumina Lifestyle & HOA Guardian
  final List<String> sportsTeams; // e.g., ["Chiefs", "Royals"]
  final List<String> favoriteHolidays; // e.g., ["Christmas", "Halloween"]
  final double? vibeLevel; // 0.0 (Subtle/Classy) .. 1.0 (Bold/Energetic)
  final bool? hoaComplianceEnabled; // Enforce HOA guardrails
  final int? quietHoursStartMinutes; // minutes from midnight (0..1439)
  final int? quietHoursEndMinutes; // minutes from midnight (0..1439)
  /// 0: Passive, 1: Suggest, 2: Proactive
  final int? autonomyLevel;
  /// Annual windows where colored patterns are allowed; outside windows restrict to white
  final List<SeasonalColorWindow> seasonalColorWindows;

  // Property architecture
  final String? builder; // e.g., "Summit Homes", "Lennar", "Pulte", "Custom Build"
  final String? floorPlan; // e.g., "The Preston", "Willow II", "Oakwood Reverse", "Other"
  final int? buildYear; // e.g., 1950..2025

  // Privacy & Intelligence controls
  /// Opt-in for recommending user's custom designs to community matches (builder/floor plan).
  final bool communityPatternSharing;
  
  /// Preferred dealer contact for sales requests and quotes
  final String? dealerEmail;

  // Remote Access configuration
  /// URL for cloud relay webhook (Dynamic DNS pointing to home network)
  final String? webhookUrl;
  /// WiFi SSID of the user's home network (for detecting local vs remote)
  final String? homeSsid;
  /// Whether remote access via cloud relay is enabled
  final bool remoteAccessEnabled;
  /// Whether to use MQTT relay via Lumina Backend (vs Firestore/webhook)
  final bool mqttRelayEnabled;
  /// Lumina Backend URL (for MQTT relay)
  final String? luminaBackendUrl;

  /// Whether the user has completed the welcome wizard/tutorial
  final bool welcomeCompleted;

  // AR Preview configuration
  /// Serialized roofline mask data for AR preview overlay
  final Map<String, dynamic>? rooflineMask;
  /// Whether user prefers the stock demo house image instead of uploading their own
  final bool useStockHouseImage;
  /// URL of the user's house photo (separate from profile photo)
  final String? housePhotoUrl;

  // Lumina Autopilot configuration
  /// Whether autopilot scheduling is enabled
  final bool autopilotEnabled;
  /// How often patterns should change (0-5 scale: minimal to maximum)
  final int changeToleranceLevel;
  /// Preferred effect styles for autopilot: 'static', 'animated', 'chase', 'twinkle', 'rainbow'
  final List<String> preferredEffectStyles;
  /// When the autopilot schedule was last generated
  final DateTime? autopilotLastGenerated;
  /// User-added custom holidays (birthdays, anniversaries, etc.)
  final List<CustomHoliday> customHolidays;
  /// Ordered list of sports teams by preference (first = highest priority)
  final List<String> sportsTeamPriority;
  /// Whether to receive weekly schedule preview notifications (Sunday evenings)
  final bool weeklySchedulePreviewEnabled;

  UserModel({
    required this.id,
    required this.email,
    required this.displayName,
    this.photoUrl,
    required this.ownerId,
    required this.createdAt,
    required this.updatedAt,
    this.location,
    this.timeZone,
    this.preferredCategoryIds = const [],
    this.interestTags = const [],
    this.allowSuggestions = true,
    this.dislikes = const [],
    this.phoneNumber,
    this.address,
    this.latitude,
    this.longitude,
    this.sportsTeams = const [],
    this.favoriteHolidays = const [],
    this.vibeLevel,
    this.hoaComplianceEnabled,
    this.quietHoursStartMinutes,
    this.quietHoursEndMinutes,
    this.autonomyLevel,
    this.builder,
    this.floorPlan,
    this.buildYear,
    this.seasonalColorWindows = const [],
    this.communityPatternSharing = false,
    this.dealerEmail,
    this.webhookUrl,
    this.homeSsid,
    this.remoteAccessEnabled = false,
    this.mqttRelayEnabled = false,
    this.luminaBackendUrl,
    this.welcomeCompleted = false,
    this.rooflineMask,
    this.useStockHouseImage = false,
    this.housePhotoUrl,
    this.autopilotEnabled = false,
    this.changeToleranceLevel = 2,
    this.preferredEffectStyles = const ['static', 'animated'],
    this.autopilotLastGenerated,
    this.customHolidays = const [],
    this.sportsTeamPriority = const [],
    this.weeklySchedulePreviewEnabled = true,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    return UserModel(
      id: json['id'] as String,
      email: json['email'] as String,
      displayName: json['display_name'] as String,
      photoUrl: json['photo_url'] as String?,
      ownerId: json['owner_id'] as String,
      createdAt: (json['created_at'] as Timestamp).toDate(),
      updatedAt: (json['updated_at'] as Timestamp).toDate(),
      location: json['location'] as String?,
      timeZone: json['time_zone'] as String?,
      preferredCategoryIds: (json['preferred_category_ids'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      interestTags: (json['interest_tags'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      allowSuggestions: (json['allow_suggestions'] as bool?) ?? true,
      dislikes: (json['dislikes'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      phoneNumber: json['phone_number'] as String?,
      address: json['address'] as String?,
      latitude: (json['latitude'] is num) ? (json['latitude'] as num).toDouble() : null,
      longitude: (json['longitude'] is num) ? (json['longitude'] as num).toDouble() : null,
      sportsTeams: (json['sports_teams'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      favoriteHolidays: (json['favorite_holidays'] as List?)?.map((e) => e.toString()).toList() ?? const [],
      vibeLevel: (json['vibe_level'] is num) ? (json['vibe_level'] as num).toDouble() : null,
      hoaComplianceEnabled: json['hoa_compliance_enabled'] as bool?,
      quietHoursStartMinutes: (json['quiet_hours_start_minutes'] is num) ? (json['quiet_hours_start_minutes'] as num).toInt() : null,
      quietHoursEndMinutes: (json['quiet_hours_end_minutes'] is num) ? (json['quiet_hours_end_minutes'] as num).toInt() : null,
      autonomyLevel: (json['autonomy_level'] is num) ? (json['autonomy_level'] as num).toInt() : null,
      builder: json['builder'] as String?,
      floorPlan: json['floor_plan'] as String?,
      buildYear: (json['build_year'] is num) ? (json['build_year'] as num).toInt() : null,
      seasonalColorWindows: (json['seasonal_color_windows'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => SeasonalColorWindow.fromJson(e))
              .toList() ??
          const [],
      communityPatternSharing: (json['community_pattern_sharing'] as bool?) ?? false,
      dealerEmail: json['dealer_email'] as String?,
      webhookUrl: json['webhook_url'] as String?,
      homeSsid: json['home_ssid'] as String?,
      remoteAccessEnabled: (json['remote_access_enabled'] as bool?) ?? false,
      mqttRelayEnabled: (json['mqtt_relay_enabled'] as bool?) ?? false,
      luminaBackendUrl: json['lumina_backend_url'] as String?,
      welcomeCompleted: (json['welcome_completed'] as bool?) ?? false,
      rooflineMask: json['roofline_mask'] as Map<String, dynamic>?,
      useStockHouseImage: (json['use_stock_house_image'] as bool?) ?? false,
      housePhotoUrl: json['house_photo_url'] as String?,
      autopilotEnabled: (json['autopilot_enabled'] as bool?) ?? false,
      changeToleranceLevel: (json['change_tolerance_level'] as num?)?.toInt() ?? 2,
      preferredEffectStyles: (json['preferred_effect_styles'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const ['static', 'animated'],
      autopilotLastGenerated: json['autopilot_last_generated'] != null
          ? (json['autopilot_last_generated'] as Timestamp).toDate()
          : null,
      customHolidays: (json['custom_holidays'] as List?)
              ?.whereType<Map<String, dynamic>>()
              .map((e) => CustomHoliday.fromJson(e))
              .toList() ??
          const [],
      sportsTeamPriority: (json['sports_team_priority'] as List?)
              ?.map((e) => e.toString())
              .toList() ??
          const [],
      weeklySchedulePreviewEnabled: (json['weekly_schedule_preview_enabled'] as bool?) ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'email': email,
      'display_name': displayName,
      'photo_url': photoUrl,
      'owner_id': ownerId,
      'created_at': Timestamp.fromDate(createdAt),
      'updated_at': Timestamp.fromDate(updatedAt),
      'location': location,
      'time_zone': timeZone,
      'preferred_category_ids': preferredCategoryIds,
      'interest_tags': interestTags,
      'allow_suggestions': allowSuggestions,
      'dislikes': dislikes,
      'phone_number': phoneNumber,
      'address': address,
      'latitude': latitude,
      'longitude': longitude,
      'sports_teams': sportsTeams,
      'favorite_holidays': favoriteHolidays,
      'vibe_level': vibeLevel,
      'hoa_compliance_enabled': hoaComplianceEnabled,
      'quiet_hours_start_minutes': quietHoursStartMinutes,
      'quiet_hours_end_minutes': quietHoursEndMinutes,
      'autonomy_level': autonomyLevel,
      'builder': builder,
      'floor_plan': floorPlan,
      'build_year': buildYear,
      'seasonal_color_windows': seasonalColorWindows.map((e) => e.toJson()).toList(),
      'community_pattern_sharing': communityPatternSharing,
      'dealer_email': dealerEmail,
      'webhook_url': webhookUrl,
      'home_ssid': homeSsid,
      'remote_access_enabled': remoteAccessEnabled,
      'mqtt_relay_enabled': mqttRelayEnabled,
      'lumina_backend_url': luminaBackendUrl,
      'welcome_completed': welcomeCompleted,
      'roofline_mask': rooflineMask,
      'use_stock_house_image': useStockHouseImage,
      'house_photo_url': housePhotoUrl,
      'autopilot_enabled': autopilotEnabled,
      'change_tolerance_level': changeToleranceLevel,
      'preferred_effect_styles': preferredEffectStyles,
      if (autopilotLastGenerated != null)
        'autopilot_last_generated': Timestamp.fromDate(autopilotLastGenerated!),
      'custom_holidays': customHolidays.map((e) => e.toJson()).toList(),
      'sports_team_priority': sportsTeamPriority,
      'weekly_schedule_preview_enabled': weeklySchedulePreviewEnabled,
    };
  }

  UserModel copyWith({
    String? id,
    String? email,
    String? displayName,
    String? photoUrl,
    String? ownerId,
    DateTime? createdAt,
    DateTime? updatedAt,
    String? location,
    String? timeZone,
    List<String>? preferredCategoryIds,
    List<String>? interestTags,
    bool? allowSuggestions,
    List<String>? dislikes,
    String? phoneNumber,
    String? address,
    double? latitude,
    double? longitude,
    List<String>? sportsTeams,
    List<String>? favoriteHolidays,
    double? vibeLevel,
    bool? hoaComplianceEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    int? autonomyLevel,
    String? builder,
    String? floorPlan,
    int? buildYear,
    List<SeasonalColorWindow>? seasonalColorWindows,
    bool? communityPatternSharing,
    String? dealerEmail,
    String? webhookUrl,
    String? homeSsid,
    bool? remoteAccessEnabled,
    bool? mqttRelayEnabled,
    String? luminaBackendUrl,
    bool? welcomeCompleted,
    Map<String, dynamic>? rooflineMask,
    bool? useStockHouseImage,
    String? housePhotoUrl,
    bool? autopilotEnabled,
    int? changeToleranceLevel,
    List<String>? preferredEffectStyles,
    DateTime? autopilotLastGenerated,
    List<CustomHoliday>? customHolidays,
    List<String>? sportsTeamPriority,
    bool? weeklySchedulePreviewEnabled,
  }) {
    return UserModel(
      id: id ?? this.id,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      photoUrl: photoUrl ?? this.photoUrl,
      ownerId: ownerId ?? this.ownerId,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      location: location ?? this.location,
      timeZone: timeZone ?? this.timeZone,
      preferredCategoryIds: preferredCategoryIds ?? this.preferredCategoryIds,
      interestTags: interestTags ?? this.interestTags,
      allowSuggestions: allowSuggestions ?? this.allowSuggestions,
      dislikes: dislikes ?? this.dislikes,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      address: address ?? this.address,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      sportsTeams: sportsTeams ?? this.sportsTeams,
      favoriteHolidays: favoriteHolidays ?? this.favoriteHolidays,
      vibeLevel: vibeLevel ?? this.vibeLevel,
      hoaComplianceEnabled: hoaComplianceEnabled ?? this.hoaComplianceEnabled,
      quietHoursStartMinutes: quietHoursStartMinutes ?? this.quietHoursStartMinutes,
      quietHoursEndMinutes: quietHoursEndMinutes ?? this.quietHoursEndMinutes,
      autonomyLevel: autonomyLevel ?? this.autonomyLevel,
      builder: builder ?? this.builder,
      floorPlan: floorPlan ?? this.floorPlan,
      buildYear: buildYear ?? this.buildYear,
      seasonalColorWindows: seasonalColorWindows ?? this.seasonalColorWindows,
      communityPatternSharing: communityPatternSharing ?? this.communityPatternSharing,
      dealerEmail: dealerEmail ?? this.dealerEmail,
      webhookUrl: webhookUrl ?? this.webhookUrl,
      homeSsid: homeSsid ?? this.homeSsid,
      remoteAccessEnabled: remoteAccessEnabled ?? this.remoteAccessEnabled,
      mqttRelayEnabled: mqttRelayEnabled ?? this.mqttRelayEnabled,
      luminaBackendUrl: luminaBackendUrl ?? this.luminaBackendUrl,
      welcomeCompleted: welcomeCompleted ?? this.welcomeCompleted,
      rooflineMask: rooflineMask ?? this.rooflineMask,
      useStockHouseImage: useStockHouseImage ?? this.useStockHouseImage,
      housePhotoUrl: housePhotoUrl ?? this.housePhotoUrl,
      autopilotEnabled: autopilotEnabled ?? this.autopilotEnabled,
      changeToleranceLevel: changeToleranceLevel ?? this.changeToleranceLevel,
      preferredEffectStyles: preferredEffectStyles ?? this.preferredEffectStyles,
      autopilotLastGenerated: autopilotLastGenerated ?? this.autopilotLastGenerated,
      customHolidays: customHolidays ?? this.customHolidays,
      sportsTeamPriority: sportsTeamPriority ?? this.sportsTeamPriority,
      weeklySchedulePreviewEnabled: weeklySchedulePreviewEnabled ?? this.weeklySchedulePreviewEnabled,
    );
  }
}
