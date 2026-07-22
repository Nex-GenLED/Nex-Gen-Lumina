import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/services/commercial/business_hours_service.dart';
import 'package:nexgen_command/services/commercial/commercial_espn_service.dart';
import 'package:nexgen_command/services/commercial/commercial_permissions_service.dart';
import 'package:nexgen_command/services/commercial/corporate_push_service.dart';
import 'package:nexgen_command/services/commercial/day_part_scheduler_service.dart';
import 'package:nexgen_command/services/commercial/daylight_brightness_modifier.dart';
import 'package:nexgen_command/services/commercial/daylight_suppression_service.dart';
import 'package:nexgen_command/services/commercial/game_day_service.dart';
import 'package:nexgen_command/services/commercial/geo_team_suggestion_service.dart';

/// Singleton daylight suppression service — fetches sunrise/sunset from
/// Open-Meteo and caches for the calendar day.
final daylightSuppressionServiceProvider =
    Provider<DaylightSuppressionService>((ref) => DaylightSuppressionService());

/// Singleton daylight brightness modifier — calculates brightness multiplier
/// for outdoor channels based on daylight window and channel config.
final daylightBrightnessModifierProvider =
    Provider<DaylightBrightnessModifier>((ref) => const DaylightBrightnessModifier());

/// Singleton business hours service — evaluates open/closed state,
/// day-part labels, next transitions, and holiday conflicts.
final businessHoursServiceProvider =
    Provider<BusinessHoursService>((ref) => const BusinessHoursService());

/// Singleton day-part scheduler service — resolves active designs,
/// generates schedules from templates, and persists commercial schedules
/// to Firestore alongside the existing autopilot document structure.
final dayPartSchedulerServiceProvider =
    Provider<DayPartSchedulerService>((ref) {
  final hoursService = ref.watch(businessHoursServiceProvider);
  return DayPartSchedulerService(hoursService: hoursService);
});

/// Singleton geo team suggestion service — suggests local sports teams
/// based on business lat/long using a static US metro lookup table.
final geoTeamSuggestionServiceProvider =
    Provider<GeoTeamSuggestionService>((ref) => const GeoTeamSuggestionService());

/// Singleton commercial ESPN service — extends the existing ESPN integration
/// with multi-team lookups sorted by priority rank.
final commercialEspnServiceProvider =
    Provider<CommercialEspnService>((ref) => CommercialEspnService());

/// Singleton game day service — polls for today's games, activates Game Day
/// mode for priority-1 teams, and bridges scoring alerts to the commercial
/// channel scope and intensity settings.
final gameDayServiceProvider =
    Provider<GameDayService>((ref) {
  final espnService = ref.watch(commercialEspnServiceProvider);
  return GameDayService(espnService: espnService);
});

/// Singleton commercial permissions service — resolves the current user's
/// role at a location and evaluates permissions against the role map.
final commercialPermissionsServiceProvider =
    Provider<CommercialPermissionsService>(
        (ref) => CommercialPermissionsService());

/// Singleton corporate push service — pushes schedules and campaigns
/// from corporate admin to one or more locations via Firestore batch writes.
final corporatePushServiceProvider =
    Provider<CorporatePushService>((ref) => CorporatePushService());
