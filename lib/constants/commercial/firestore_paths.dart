/// Canonical Firestore collection paths for the commercial mode system.
///
/// All commercial services and screens should reference these constants
/// instead of hardcoded path strings to ensure consistency.
///
/// Document hierarchy:
/// ```
/// /users/{uid}/
///   ├── commercial_schedule/{locationId}   ← CommercialSchedule (day-parts)
///   └── commercial_locations/{locationId}  ← CommercialLocation (channels, hours)
///
/// /commercial_organizations/{orgId}
///   ├── locations/{locationId}
///   │   ├── channel_configs/{channelId}
///   │   ├── schedule                       ← org-level schedule (corporate push)
///   │   ├── teams_config
///   │   └── business_hours
///   └── brand_profile
///
/// /campaigns/{campaignId}
/// ```
class CommercialFirestorePaths {
  const CommercialFirestorePaths._();

  // ── User-level collections (single-location and local edits) ──────────

  /// `/users/{uid}/commercial_schedule`
  static String userSchedules(String uid) =>
      'users/$uid/commercial_schedule';

  /// `/users/{uid}/commercial_schedule/{locationId}`
  static String userScheduleDoc(String uid, String locationId) =>
      'users/$uid/commercial_schedule/$locationId';

  /// `/users/{uid}/commercial_locations`
  static String userLocations(String uid) =>
      'users/$uid/commercial_locations';

  /// `/users/{uid}/commercial_locations/{locationId}`
  static String userLocationDoc(String uid, String locationId) =>
      'users/$uid/commercial_locations/$locationId';

  // ── Organization-level collections (multi-location) ───────────────────

  /// `/commercial_organizations/{orgId}`
  static const String organizationsCollection = 'commercial_organizations';

  /// `/commercial_organizations/{orgId}`
  static String organization(String orgId) =>
      'commercial_organizations/$orgId';

  /// `/commercial_organizations/{orgId}/locations/{locationId}`
  static String orgLocation(String orgId, String locationId) =>
      'commercial_organizations/$orgId/locations/$locationId';

  /// `/commercial_organizations/{orgId}/locations/{locationId}/channel_configs/{channelId}`
  static String orgChannelConfig(
          String orgId, String locationId, String channelId) =>
      'commercial_organizations/$orgId/locations/$locationId/channel_configs/$channelId';

  /// `/commercial_organizations/{orgId}/locations/{locationId}/schedule`
  static String orgSchedule(String orgId, String locationId) =>
      'commercial_organizations/$orgId/locations/$locationId/schedule';

  /// `/commercial_organizations/{orgId}/locations/{locationId}/teams_config`
  static String orgTeamsConfig(String orgId, String locationId) =>
      'commercial_organizations/$orgId/locations/$locationId/teams_config';

  /// `/commercial_organizations/{orgId}/locations/{locationId}/business_hours`
  static String orgBusinessHours(String orgId, String locationId) =>
      'commercial_organizations/$orgId/locations/$locationId/business_hours';

  /// `/commercial_organizations/{orgId}/brand_profile`
  static String orgBrandProfile(String orgId) =>
      'commercial_organizations/$orgId/brand_profile';

  // ── Root-level collections ────────────────────────────────────────────

  /// `/campaigns/{campaignId}`
  static const String campaignsCollection = 'campaigns';

  /// `/campaigns/{campaignId}`
  static String campaign(String campaignId) =>
      'campaigns/$campaignId';

  // ── Collection names (for .collection() calls) ────────────────────────

  /// Sub-collection name for commercial schedules under a user doc.
  static const String scheduleSubcollection = 'commercial_schedule';

  /// Sub-collection name for commercial locations under a user doc.
  static const String locationsSubcollection = 'commercial_locations';

  /// Sub-collection name for channel configs under an org location.
  static const String channelConfigsSubcollection = 'channel_configs';
}
