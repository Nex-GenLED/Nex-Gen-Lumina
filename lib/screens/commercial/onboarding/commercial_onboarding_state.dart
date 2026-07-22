import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:nexgen_command/models/commercial/brand_color.dart';
import 'package:nexgen_command/models/commercial/business_hours.dart';
import 'package:nexgen_command/models/commercial/channel_role.dart';
import 'package:nexgen_command/models/commercial/commercial_team_profile.dart';
import 'package:nexgen_command/models/commercial/day_part.dart';

/// Lightweight location draft for multi-location onboarding (Screen 7).
class LocationDraft {
  final String locationName;
  final String address;
  final String managerName;
  final String managerEmail;
  final String managerRole; // 'storeManager' or 'corporateAdmin'
  final bool useOrgTemplate;

  const LocationDraft({
    this.locationName = '',
    this.address = '',
    this.managerName = '',
    this.managerEmail = '',
    this.managerRole = 'storeManager',
    this.useOrgTemplate = true,
  });

  LocationDraft copyWith({
    String? locationName,
    String? address,
    String? managerName,
    String? managerEmail,
    String? managerRole,
    bool? useOrgTemplate,
  }) {
    return LocationDraft(
      locationName: locationName ?? this.locationName,
      address: address ?? this.address,
      managerName: managerName ?? this.managerName,
      managerEmail: managerEmail ?? this.managerEmail,
      managerRole: managerRole ?? this.managerRole,
      useOrgTemplate: useOrgTemplate ?? this.useOrgTemplate,
    );
  }
}

/// Wizard draft state — holds all data across the 8-screen onboarding flow.
class CommercialOnboardingDraft {
  // Screen 1 — Business Type
  final String businessType;
  final String businessName;
  final String primaryAddress;

  // Screen 2 — Brand Identity
  final List<BrandColor> brandColors;
  final bool applyBrandToDefaults;
  /// brand_id of a /brand_library entry that pre-populated the colors.
  /// Null when the customer entered colors manually with no library
  /// match. Persisted to user.commercial_profile.brand_library_id +
  /// /users/{uid}/brand_profile/brand on go-live so the Brand tab can
  /// resolve back to the library entry.
  final String? brandLibraryId;

  // Screen 3 — Hours of Operation
  final Map<DayOfWeek, DaySchedule> weeklySchedule;
  final int preOpenBufferMinutes;
  final int postCloseWindDownMinutes;
  final bool hoursVary;
  final bool observeStandardHolidays;
  final List<String> observedHolidays;

  // Screen 4 — Channel Setup
  final List<ChannelRoleConfig> channelConfigs;

  // Screen 5 — Your Teams
  final List<CommercialTeamProfile> teams;
  final bool useBrandColorsForAlerts;

  // Screen 6 — Day-Part Config
  final List<DayPart> dayParts;
  final String? defaultAmbientDesignId;

  // Screen 7 — Multi-Location
  final String orgName;
  final List<LocationDraft> locations;
  final bool applyTemplateToAll;
  final bool hasMultipleLocations;

  const CommercialOnboardingDraft({
    this.businessType = '',
    this.businessName = '',
    this.primaryAddress = '',
    this.brandColors = const [],
    this.applyBrandToDefaults = true,
    this.brandLibraryId,
    this.weeklySchedule = const {},
    this.preOpenBufferMinutes = 30,
    this.postCloseWindDownMinutes = 15,
    this.hoursVary = false,
    this.observeStandardHolidays = true,
    this.observedHolidays = const [],
    this.channelConfigs = const [],
    this.teams = const [],
    this.useBrandColorsForAlerts = false,
    this.dayParts = const [],
    this.defaultAmbientDesignId,
    this.orgName = '',
    this.locations = const [],
    this.applyTemplateToAll = true,
    this.hasMultipleLocations = false,
  });

  CommercialOnboardingDraft copyWith({
    String? businessType,
    String? businessName,
    String? primaryAddress,
    List<BrandColor>? brandColors,
    bool? applyBrandToDefaults,
    String? brandLibraryId,
    bool clearBrandLibraryId = false,
    Map<DayOfWeek, DaySchedule>? weeklySchedule,
    int? preOpenBufferMinutes,
    int? postCloseWindDownMinutes,
    bool? hoursVary,
    bool? observeStandardHolidays,
    List<String>? observedHolidays,
    List<ChannelRoleConfig>? channelConfigs,
    List<CommercialTeamProfile>? teams,
    bool? useBrandColorsForAlerts,
    List<DayPart>? dayParts,
    String? defaultAmbientDesignId,
    String? orgName,
    List<LocationDraft>? locations,
    bool? applyTemplateToAll,
    bool? hasMultipleLocations,
  }) {
    return CommercialOnboardingDraft(
      businessType: businessType ?? this.businessType,
      businessName: businessName ?? this.businessName,
      primaryAddress: primaryAddress ?? this.primaryAddress,
      brandColors: brandColors ?? this.brandColors,
      applyBrandToDefaults: applyBrandToDefaults ?? this.applyBrandToDefaults,
      brandLibraryId: clearBrandLibraryId
          ? null
          : (brandLibraryId ?? this.brandLibraryId),
      weeklySchedule: weeklySchedule ?? this.weeklySchedule,
      preOpenBufferMinutes: preOpenBufferMinutes ?? this.preOpenBufferMinutes,
      postCloseWindDownMinutes: postCloseWindDownMinutes ?? this.postCloseWindDownMinutes,
      hoursVary: hoursVary ?? this.hoursVary,
      observeStandardHolidays: observeStandardHolidays ?? this.observeStandardHolidays,
      observedHolidays: observedHolidays ?? this.observedHolidays,
      channelConfigs: channelConfigs ?? this.channelConfigs,
      teams: teams ?? this.teams,
      useBrandColorsForAlerts: useBrandColorsForAlerts ?? this.useBrandColorsForAlerts,
      dayParts: dayParts ?? this.dayParts,
      defaultAmbientDesignId: defaultAmbientDesignId ?? this.defaultAmbientDesignId,
      orgName: orgName ?? this.orgName,
      locations: locations ?? this.locations,
      applyTemplateToAll: applyTemplateToAll ?? this.applyTemplateToAll,
      hasMultipleLocations: hasMultipleLocations ?? this.hasMultipleLocations,
    );
  }
}

/// Notifier for the onboarding wizard draft state.
class CommercialOnboardingNotifier extends Notifier<CommercialOnboardingDraft> {
  @override
  CommercialOnboardingDraft build() => const CommercialOnboardingDraft();

  void update(CommercialOnboardingDraft Function(CommercialOnboardingDraft) fn) {
    state = fn(state);
  }

  void reset() => state = const CommercialOnboardingDraft();
}

final commercialOnboardingProvider =
    NotifierProvider<CommercialOnboardingNotifier, CommercialOnboardingDraft>(
  CommercialOnboardingNotifier.new,
);

/// Tracks the current wizard step (0-based, 0–7).
final commercialOnboardingStepProvider = StateProvider<int>((ref) => 0);
