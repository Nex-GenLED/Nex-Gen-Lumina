# =============================================================================
# LUMINA COMMERCIAL MODE - CLAUDE CODE BUILD SCRIPT
# Nex-Gen LED LLC | nexgen_command Flutter/Dart package
# Run from project root: .\lumina_commercial_build.ps1
# Prompt 1 (Business Profile data layer) already completed - starting at Step 2
# =============================================================================

$ErrorActionPreference = "Continue"

function Run-Prompt {
    param([string]$Step, [string]$Description, [string]$PromptText)
    Write-Host ""
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host " STEP $Step - $Description" -ForegroundColor Cyan
    Write-Host "========================================================" -ForegroundColor Cyan
    Write-Host ""
    $tmpFile = [System.IO.Path]::GetTempFileName()
    [System.IO.File]::WriteAllText($tmpFile, $PromptText, [System.Text.Encoding]::UTF8)
    $promptContent = [System.IO.File]::ReadAllText($tmpFile, [System.Text.Encoding]::UTF8)
    claude --continue --dangerously-skip-permissions --print $promptContent
    Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Step $Step exited with code $LASTEXITCODE - continuing..." -ForegroundColor Yellow
    }
    Write-Host ""
    Write-Host "Step $Step complete." -ForegroundColor Green
    Start-Sleep -Seconds 2
}

# =============================================================================
# STEP 2 - CHANNEL ROLE SYSTEM
# =============================================================================
$p2 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. The Business Profile and Brand Color data models were just created in Step 1. Firestore schema and user profile system already exist in the codebase.

Build the Channel Role system with the following requirements:

1. Create a ChannelRole enum in lib/models/commercial/ with values: INTERIOR, OUTDOOR_FACADE, WINDOW_DISPLAY, PATIO, CANOPY, SIGNAGE_ACCENT. Each role must have: a display name, an icon reference, a default coverage policy, and a daylight suppression default (bool - outdoor roles default true, indoor false).

2. Create a ChannelRoleConfig model that stores per-channel commercial config: channelId (String), friendlyName (String), role (ChannelRole), coveragePolicy (enum: ALWAYS_ON, SMART_FILL, SCHEDULED_ONLY), daylightSuppression (bool), daylightMode (enum: SOFT_DIM, HARD_OFF, DISABLED), defaultDesignId (String nullable). Include toJson/fromJson for Firestore serialization.

3. Create a DaylightSuppressionService in lib/services/commercial/: Accepts a lat/long pulled from business address on the location document. Fetches sunrise/sunset times from the Open-Meteo API (free, no key required): https://api.open-meteo.com/v1/forecast?latitude={lat}&longitude={lng}&daily=sunrise,sunset&timezone=auto&forecast_days=1. Returns a DaylightWindow model with sunrise and sunset as DateTime objects. Caches the result for the calendar day - does not re-fetch until tomorrow. Exposes a bool isDaylightHours() method for current time checks.

4. Create a DaylightBrightnessModifier in lib/services/commercial/: Takes a ChannelRoleConfig and DaylightWindow. If daylightSuppression is true and isDaylightHours() is true: SOFT_DIM returns brightness multiplier of 0.20, HARD_OFF returns 0. Otherwise returns 1.0. Fade transition: brightness ramp uses 10-minute linear interpolation at both sunrise and sunset boundaries - fade in/out over 10 min, do not snap.

5. Register DaylightSuppressionService as a singleton in the existing service locator/provider setup, consistent with how other services are registered in this codebase.

Data layer and services only - no UI in this step. Follow the existing code style, file structure, and naming conventions in the repo."

Run-Prompt -Step "2" -Description "Channel Role Enum Model and Daylight Suppression Logic" -PromptText $p2

# =============================================================================
# STEP 3 - HOURS OF OPERATION MODEL
# =============================================================================
$p3 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. Channel Role system was just built in the previous step. Business Profile and Brand Color models already exist. Firestore schema and user profile system already exist.

Build the Hours of Operation and Holiday Calendar data layer:

1. Create a BusinessHours model in lib/models/commercial/: weeklySchedule as Map<DayOfWeek, DaySchedule>, preOpenBufferMinutes int defaulting to 30, postCloseWindDownMinutes int defaulting to 15. DaySchedule contains: isOpen (bool), openTime (TimeOfDay), closeTime (TimeOfDay). Include helpers: isCurrentlyOpen(), nextOpenTime(), nextCloseTime(). Include toJson/fromJson for Firestore.

2. Create a HolidayCalendar model in lib/models/commercial/: standardHolidaysEnabled (bool), observedHolidays as List<String> with holiday keys from a StandardHoliday enum, customClosures as List<CustomClosure> where each has date and reason (internal only), specialEvents as List<SpecialEvent> where each has startDate, endDate, name, customScheduleId (nullable), designOverrideId (nullable). Include toJson/fromJson for Firestore.

3. Create a StandardHoliday enum covering all major US holidays: New Years Day, MLK Day, Presidents Day, Memorial Day, Independence Day, Labor Day, Thanksgiving, Christmas Eve, Christmas Day, New Years Eve. Each entry has a display name and a method to return its date for a given year.

4. Create a BusinessHoursService in lib/services/commercial/ with these methods: isBusinessOpen(BusinessHours hours, HolidayCalendar calendar) returns bool - checks current time against weekly schedule, respects custom closures, returns false on closure dates. getCurrentDayPart(BusinessHours hours) returns String - returns the name of the active day-part based on current time within open hours. getNextTransition(BusinessHours hours) returns DateTime - returns the next open or close time for autopilot scheduling awareness. upcomingHolidayConflict(HolidayCalendar calendar) returns SpecialEvent nullable - returns a holiday or event in the next 7 days if one exists.

5. Register BusinessHoursService as a singleton consistent with existing service registration patterns in this codebase.

No UI in this step. Data layer and services only. Follow existing code style, file structure, and naming conventions in the repo."

Run-Prompt -Step "3" -Description "Hours of Operation Model and Holiday Calendar" -PromptText $p3

# =============================================================================
# STEP 4 - DAY-PART ENGINE
# =============================================================================
$p4 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. The existing Autopilot system is already built and functional in this codebase. BusinessHours, HolidayCalendar, ChannelRoleConfig models were just created. Firestore schema already exists.

Build the Day-Part Engine that extends the existing Autopilot system for commercial use:

1. Create a DayPart model in lib/models/commercial/: id (String), name (String - example values: Happy Hour, Lunch, Late Night), startTime (TimeOfDay), endTime (TimeOfDay), assignedDesignId (String nullable - falls back to Smart Fill or Default), useBrandColors (bool), coveragePolicy (CoveragePolicy nullable - inherits channel default if null), daysOfWeek (List<DayOfWeek>), isGameDayOverride (bool). Include toJson/fromJson for Firestore.

2. Create a DayPartTemplate class with static methods that generate standard day-part lists by BusinessType. Templates: BAR_NIGHTCLUB generates Pre-Open, Afternoon Ambient, Happy Hour, Dinner/Early Night, Peak Night, Late Night, Post-Close. RESTAURANT_CASUAL generates Pre-Open, Breakfast/Brunch, Lunch Rush, Afternoon, Happy Hour, Dinner Service, Post-Close. RESTAURANT_FINE_DINING generates Pre-Open, Lunch Service, Afternoon, Dinner Prep, Dinner Service, Post-Close. FAST_CASUAL generates Pre-Open, Morning Rush, Midday Rush, Afternoon Lull, Evening, Post-Close. RETAIL_BOUTIQUE generates Pre-Open, Morning Browse, Midday, Afternoon, Evening Wind-Down, Post-Close. RETAIL_CHAIN generates Pre-Open, Morning, Midday Peak, Afternoon, Evening, Post-Close. Each template generates a List<DayPart> with appropriate default time ranges calculated from a provided BusinessHours object.

3. Create a CommercialSchedule model in lib/models/commercial/: locationId (String), dayParts as List<DayPart>, defaultAmbientDesignId (String nullable - used for Smart Fill gaps), coveragePolicy (CoveragePolicy), isLockedByCorporate (bool), lockExpiryDate (DateTime nullable). Include toJson/fromJson for Firestore.

4. Create a DayPartSchedulerService in lib/services/commercial/ that integrates with the EXISTING Autopilot system - extend it, do not replace it. Methods: getActiveDayPart(CommercialSchedule, BusinessHours) returns DayPart nullable. getSmartFillDesign(CommercialSchedule) returns String nullable - returns defaultAmbientDesignId if coverage policy is SMART_FILL and no DayPart covers current time. resolveActiveDesign(CommercialSchedule, BusinessHours, ChannelRoleConfig) returns String nullable - checks if open, gets active day-part, applies smart fill if needed, applies daylight suppression modifier for outdoor channels, returns final designId or null if outside hours with SCHEDULED_ONLY policy. generateScheduleFromTemplate(BusinessType, BusinessHours) returns CommercialSchedule.

5. Extend the existing Autopilot Firestore writes to include CommercialSchedule data when commercial mode is active for a location. The commercial schedule coexists with, does not replace, the existing autopilot document structure.

No UI in this step. Services and models only. Follow existing code style, file structure, and naming conventions in the repo."

Run-Prompt -Step "4" -Description "Day-Part Engine Building on Existing Autopilot System" -PromptText $p4

# =============================================================================
# STEP 5 - YOUR TEAMS SYSTEM
# =============================================================================
$p5 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. The ESPN sports integration already exists in this codebase - build on top of it. Firestore schema, user profile system, and Business Profile model already exist. CommercialSchedule and DayPart models were just created.

Build the Your Teams commercial sports system:

1. Create a CommercialTeamProfile model in lib/models/commercial/: priorityRank (int - 1 is primary, 2 is secondary, 3 and above is tertiary), teamId (String - matches existing ESPN team ID format in this codebase), teamName (String), sport (String), primaryColor (String hex), secondaryColor (String hex), alertIntensity (enum: FULL, MODERATE, SUBTLE), alertChannelScope (enum: ALL_CHANNELS, INDOOR_ONLY, SELECTED_CHANNELS), selectedChannelIds (List<String>), gameDayAutoModeEnabled (bool), gameDayLeadTimeMinutes (int defaulting to 120). Include toJson/fromJson.

2. Create a CommercialTeamsConfig model in lib/models/commercial/: locationId (String), teams as List<CommercialTeamProfile> ordered by priorityRank, useBrandColorsForAlerts (bool). Include toJson/fromJson for Firestore.

3. Create a GeoTeamSuggestionService in lib/services/commercial/: Takes a lat/long from the business address. Returns a List<CommercialTeamProfile> of suggested local teams. Use a static lookup table with no external API required - define geographic regions in the US mapped to their local professional teams across NFL, NBA, MLB, NHL, MLS covering all 30 or more major US markets. Store as a constant map in lib/constants/commercial/geo_team_regions.dart. Suggestions are labeled as Suggested based on your location and are presented as removable, not pre-accepted defaults. Returns empty list for unrecognized regions.

4. Extend the EXISTING ESPN integration service to add: getUpcomingGamesForTeams(List<CommercialTeamProfile> teams) returns List<GameEvent> for games in the next 7 days. isGameActiveNow(CommercialTeamProfile team) returns bool. getTodaysGames(List<CommercialTeamProfile> teams) returns List<GameEvent> sorted by priority rank.

5. Create a GameDayService in lib/services/commercial/: Checks getTodaysGames() on app foreground resume and via background polling using the existing background service pattern in this codebase. When a game is detected for a priority-rank-1 team within the lead time window, triggers a shift to the Game Day day-part in the CommercialSchedule. When the game ends, reverts to the standard day-part for current time. Fires scoring alert events through the existing sports alert system applying CommercialTeamProfile intensity and channel scope settings. Respects useBrandColorsForAlerts and substitutes brand hex colors from BusinessProfile when this flag is true.

No UI in this step. Models and services only. Follow existing code style, file structure, and naming conventions."

Run-Prompt -Step "5" -Description "Your Teams Extending Existing ESPN Integration" -PromptText $p5

# =============================================================================
# STEP 6 - MULTI-LOCATION DATA LAYER
# =============================================================================
$p6 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. Existing systems: Firestore schema, user profile/account system, Business Profile, CommercialSchedule, CommercialTeamsConfig, ChannelRoleConfig all exist.

Build the multi-location organization hierarchy and permission system:

1. Create a CommercialOrganization model in lib/models/commercial/: orgId (String), orgName (String), ownerId (String - maps to existing user profile), brandProfileId (String - references BusinessProfile at org level), locationIds as List<String>, templateScheduleId (String nullable). Include toJson/fromJson for Firestore.

2. Create a CommercialLocation model in lib/models/commercial/: locationId (String), orgId (String), locationName (String), address (String), lat (double), lng (double), controllerId (String - maps to existing WLED controller), businessHoursId (String), scheduleId (String), teamsConfigId (String), isUsingOrgTemplate (bool), channelConfigs as List<ChannelRoleConfig>, managers as List<LocationManagerAssignment> where each has userId, role as CommercialRole, and assignedAt. Include toJson/fromJson for Firestore.

3. Create a CommercialRole enum with values: STORE_STAFF, STORE_MANAGER, REGIONAL_MANAGER, CORPORATE_ADMIN. Include a permissions map per role defining: canViewOwnLocation, canEditOwnSchedule, canOverrideNow, canViewAllLocations, canPushToRegion, canPushToAll, canApplyCorporateLock, canManageUsers, canEditBrandColors.

4. Create a CommercialPermissionsService in lib/services/commercial/: getCurrentUserRole(locationId) returns CommercialRole. hasPermission(CommercialRole role, String permission) returns bool. canEditLocation(String locationId) returns bool. canPushToAll() returns bool. canUnlock(String locationId) returns bool. Integrate with the existing user profile/account system for user identity.

5. Create a CorporatePushService in lib/services/commercial/: pushScheduleToLocations(CommercialSchedule schedule, List<String> locationIds, bool locked defaulting to false, DateTime lockExpiry nullable) returns Future<void> - writes the schedule to each target location Firestore document, sets isLockedByCorporate and lockExpiryDate if locked is true, uses the existing Firestore batch write pattern. pushCampaign(String campaignName, CommercialSchedule schedule, List<String> locationIds, DateTime startDate, DateTime endDate) returns Future<void>. unlockLocation(String locationId) returns Future<void>. getActiveLocks() returns Future<List<LocationLockStatus>>.

6. Add a comment block in lib/services/commercial/commercial_permissions_service.dart documenting the required Firestore rules for each collection to enforce role-based access. Do not modify actual Firebase console rules.

No UI in this step. Models and services only. Follow existing code style, file structure, and naming conventions."

Run-Prompt -Step "6" -Description "Multi-Location Org Hierarchy and Permission System" -PromptText $p6

# =============================================================================
# STEP 7 - ONBOARDING WIZARD SCREENS 1-4
# =============================================================================
$p7 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. All commercial data models and services are now built: BusinessProfile, BrandColorProfile, ChannelRoleConfig, DaylightSuppressionService, BusinessHours, HolidayCalendar, CommercialSchedule, DayPart, CommercialOrganization, CommercialLocation, CommercialTeamsConfig, CommercialPermissionsService.

The existing app uses the Lumina brand palette: VOID #07091A dark background, LUMINA #00D4FF cyan primary, PULSE #6E2FFF purple accent, CARBON #111527, FROST #DCF0FF.

Build the Commercial Onboarding Wizard Screens 1 through 4. Create a CommercialOnboardingWizard widget as a full-screen flow in lib/screens/commercial/onboarding/ with a persistent step progress indicator showing 8 steps total and a Save and Continue Later option available after step 2.

SCREEN 1 - BusinessTypeScreen: Large tap-friendly grid of business type tiles with icons for these 8 types: Bar/Nightclub, Restaurant Casual, Restaurant Fine Dining, Fast Casual/QSR, Retail Boutique, Retail Chain/Multi-Unit, Entertainment Venue, Other. Include a Business Name text field and a Primary Address text field labeled as Used to suggest your local sports teams. Selected tile highlights in Lumina cyan #00D4FF. Other selection reveals a free-text descriptor field. Stores to CommercialLocation and CommercialOrganization draft in local wizard state.

SCREEN 2 - BrandIdentityScreen: Section header Brand Colors with an Add Color button. Per color entry shows: Color Name text field, Hex Code input with live color swatch preview rendered immediately beside the field, and Role Tag chip selector with Primary, Secondary, Accent options. Up to 8 colors with minimum 1 to enable Apply to Defaults toggle. Apply to Defaults toggle labeled Use these colors in design suggestions and autopilot. Skip option labeled I will add brand colors later. Stores to BrandColorProfile in local wizard state.

SCREEN 3 - HoursOfOperationScreen: Day-of-week row Monday through Sunday as expandable tiles. Each expanded day shows Open/Closed toggle, Open time picker, Close time picker. Copy to weekdays and Copy to all shortcut buttons. Holiday section with We observe standard US holidays checkbox plus selectable list of StandardHoliday entries. Optional fields for Pre-open buffer defaulting to 30 min and Post-close wind-down defaulting to 15 min. Our hours vary fallback option that disables the structured fields. Week-at-a-glance preview strip at bottom showing open/closed per day. Stores to BusinessHours in local wizard state.

SCREEN 4 - ChannelSetupScreen: List of connected WLED channels pulled from the existing controller/WLED data using the existing channel fetch pattern. Each channel displayed as a card with the current WLED name as an editable friendly name field and a role selector that opens a role picker bottom sheet with 6 role options and icons. After role selection show a smart default policy chip with brief explanation and lightbulb icon. Coverage Policy selector per channel with Always On, Smart Fill with a recommended badge, and Scheduled Only. Daylight Suppression toggle per outdoor role pre-enabled with explanation tooltip. Color coding: interior role cards use blue accent, outdoor role cards use amber accent, display and signage role cards use green accent.

Each screen must use the existing app navigation/routing pattern, persist wizard state across screens using a CommercialOnboardingCubit or equivalent state management pattern already in use in this codebase, show validation errors inline before allowing Next, and match the existing Lumina dark theme."

Run-Prompt -Step "7" -Description "Commercial Onboarding Wizard Screens 1 through 4" -PromptText $p7

# =============================================================================
# STEP 8 - ONBOARDING WIZARD SCREENS 5-8
# =============================================================================
$p8 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. Onboarding Wizard Screens 1-4 were just built. Continue the same wizard flow. All commercial models, services, and CommercialOnboardingCubit exist.

Build Screens 5 through 8 of the Commercial Onboarding Wizard:

SCREEN 5 - YourTeamsScreen: Header labeled Your Teams (not Local Teams). Geo-suggested teams shown as removable chips labeled Suggested based on your location - tap X to remove any that are not yours. Pull suggestions from GeoTeamSuggestionService using the address from Screen 1. Add a team search field that searches by city, team name, or sport against the existing ESPN teams data. Each team entry shows sport icon, team name, and primary/secondary color swatches. Drag-to-reorder list with drag handles where rank equals position in list. Priority labels on first 3 items: number 1 Primary with full intensity, number 2 Secondary, number 3 Tertiary. Per-team intensity selector with Full, Moderate, Subtle options. Per-team channel scope selector with All Channels, Indoor Only, Selected Channels options. No sports alerts needed skip option at bottom as a secondary non-prominent option. For non-sports business types Fine Dining and Boutique show Use brand colors for alert pulses instead of team colors toggle prominently at top of screen. Stores to CommercialTeamsConfig in wizard state.

SCREEN 6 - DayPartConfigScreen: Auto-generated day-parts shown on a horizontal scrollable visual timeline generated by DayPartTemplate for the BusinessType selected on Screen 1, calculated against BusinessHours from Screen 3. Each day-part shown as a labeled colored block on the timeline. Tap a block to open a bottom sheet with rename, adjust start/end times, and remove options. Add a custom period FAB button. Per day-part: design assignment field optional showing Default Ambient if unset, and Use brand colors toggle. Times shown only when a block is tapped, not by default. Day selector at top to preview Monday through Sunday configurations. Stores to CommercialSchedule day-parts in wizard state.

SCREEN 7 - MultiLocationScreen: Only shown if BusinessType is RETAIL_CHAIN or if user tapped I have multiple locations on any prior screen. Organization Name field. Add Location flow with location name, address, optional hours override per location. Location cards in a scrollable list. Location Manager assignment per location with name, email, and role selector for Store Manager or Corporate Admin. Apply this setup as the template for all locations checkbox explaining that channels, day-parts, and coverage policies will be copied to all locations while hours can still differ per location. Template Applied badge on location cards where org default is active. Stores to CommercialOrganization and CommercialLocation list in wizard state. Skip option for single-location users labeled Just one location for now.

SCREEN 8 - ReviewAndGoLiveScreen: Summary cards for each completed section showing Business Profile, Brand Colors with live swatches, Hours with week-at-a-glance strip, Channels with role badge chips, Your Teams with priority list and color dots, Day-Parts with mini read-only timeline. Each summary card has an Edit button that navigates back to that screen. Preview Your Week expandable section showing a 7-day animated schedule preview of what design or mode runs at what time for each channel. Pro Tier Coming info banner as a non-blocking card with Lumina cyan border displaying: Multi-location management and advanced commercial features are currently included in Lumina at no additional cost. A Lumina Commercial subscription is coming - users who set up now will be grandfathered. Go Live CTA as a full-width Lumina cyan button labeled Activate Commercial Mode. On Go Live: commit all wizard state to Firestore via the commercial services using batch write, activate CommercialSchedule in the autopilot system, and navigate to the main commercial dashboard. Show a success animation consistent with existing onboarding success states in the codebase.

Match Lumina dark theme throughout. Use CommercialOnboardingCubit for all state."

Run-Prompt -Step "8" -Description "Commercial Onboarding Wizard Screens 5 through 8" -PromptText $p8

# =============================================================================
# STEP 9 - DAY-PART SCHEDULING UI
# =============================================================================
$p9 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. All commercial models, services, and onboarding wizard are complete. CommercialSchedule, DayPart, ChannelRoleConfig, BusinessHours all exist. Existing app has the Lumina dark theme: VOID #07091A, LUMINA #00D4FF, CARBON #111527.

Build the main Day-Part Scheduling UI for commercial accounts. Create lib/screens/commercial/schedule/CommercialScheduleScreen.dart.

LAYOUT: Day selector at top as Monday through Sunday tab row with Copy Day button on the right. Horizontal scrollable timeline below spanning full business hours only - the open window plus pre-open and post-close buffers, not 24 hours. One row per channel labeled by ChannelRole friendly name. Timeline rows are vertically scrollable if more than 4 channels. Quick Actions panel pinned at bottom and collapsible.

TIMELINE BLOCK VISUAL LANGUAGE: Scheduled block as solid tile with role-color fill and design name truncated to fit. Smart Fill auto block as hatched/striped pattern with Auto label and subdued color. Gap/lights off block in Scheduled Only mode as empty tile with dashed border and dark background. Brand Color active shown as small color dot badge in top-right corner of tile. Game Day override shown with gold border and sport icon badge. Holiday override shown as amber banner spanning the full day row above the timeline. Corporate Lock shown as lock icon overlay with muted color where tapping shows Set by Corporate tooltip.

BLOCK INTERACTIONS: Tap a block opens a bottom sheet showing design name, day-part name, start/end times, brand color status, and edit/delete options. Tap an empty gap opens a bottom sheet to assign a design or enable Smart Fill. Long-press a block enters drag/resize mode snapping to 15-minute increments. Locked blocks show info on tap with no edit options.

QUICK ACTIONS PANEL pinned at bottom and collapsible: Override Now button opens design picker and runs selected design immediately on user-selected channels with an expiry selector for Until next day-part or a specific end time, using the existing manual override pattern. Pause All button stops all channels and shows resume options. Run Default button immediately pushes defaultAmbientDesignId to all active channels. Copy Day button copies current day schedule to a selected target day. Push to All Locations button only shown when current user has CORPORATE_ADMIN role checked via CommercialPermissionsService, opens location selector, then calls CorporatePushService.pushScheduleToLocations().

STATE MANAGEMENT: Use existing state management pattern. Optimistic local updates with Firestore write-behind. If Firestore write fails revert local state and show error snackbar. Respect isLockedByCorporate and disable edit interactions showing a banner: This schedule is managed by the org name. Contact your admin.

Match Lumina dark theme. Consistent with existing screen patterns in the codebase."

Run-Prompt -Step "9" -Description "Day-Part Scheduling UI Timeline Interface" -PromptText $p9

# =============================================================================
# STEP 10 - FLEET DASHBOARD UI
# =============================================================================
$p10 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. All commercial models, services, onboarding wizard, and scheduling UI are complete. CommercialOrganization, CommercialLocation, CommercialPermissionsService, CorporatePushService, and CommercialScheduleScreen all exist.

Build the Multi-Location Fleet Dashboard. Create lib/screens/commercial/fleet/FleetDashboardScreen.dart. This is the home screen for CORPORATE_ADMIN and REGIONAL_MANAGER users with multiple locations.

TOP NAVIGATION: App bar title shows org name from CommercialOrganization. View toggle in app bar for List View and Map View. Filter button for status (Online/Warning/Offline), active override, and game-day mode. Sort button for List View only with options alphabetical, status with alerts first, and region.

LIST VIEW - each location as an expandable card: Collapsed state shows location name and city, status indicator dot color-coded per spec below, currently running design name per channel with role labels, and next scheduled event or day-part name. Expanded state shows full channel status with role labels and current design, last controller sync time from existing WLED controller data, active alerts with brief description, quick action buttons for Override/View Schedule/Edit, and a Game Day badge if GameDayService reports an active game.

STATUS INDICATORS as colored dot plus label: Green Online Running means all channels active autopilot running no alerts. Yellow Online Warning means at least one channel offline or override active or config issue. Red Offline means controller not responding using existing controller status check. Gray Inactive means outside business hours no channels expected to run. Lock icon Corporate Lock Active means one or more channels have a locked corporate schedule. Sport icon Game Day Mode means GameDayService reports sports event active.

MAP VIEW: Display location pins on a map using the existing map package in this codebase. If no map package exists use flutter_map with OpenStreetMap tiles and add the dependency. Pin color matches status indicator colors. Tap a pin opens a bottom sheet with collapsed card content. Map auto-fits bounds to show all locations on initial load.

PUSH TO ALL AND CAMPAIGN FLOW: FAB visible to CORPORATE_ADMIN only via CommercialPermissionsService. FAB opens Push Schedule and Push Campaign options. Push Schedule flow: Step 1 select a schedule from existing saved schedules. Step 2 select scope as All Locations or Selected Locations. Step 3 lock options as Advisory or Locked with optional lock expiry date picker if Locked. Step 4 impact summary listing what changes at each location. Step 5 confirm calls CorporatePushService.pushScheduleToLocations() and shows progress then success. Push Campaign flow collects campaign name, schedule, location scope, start date, end date then calls CorporatePushService.pushCampaign().

ACTIVE LOCKS PANEL: Accessible from a Manage Locks overflow menu option. Lists all locations with active locks. Shows lock expiry date or No expiry if indefinite. Unlock button per location for CORPORATE_ADMIN users.

Real-time updates: listen to Firestore snapshot streams for location status changes rather than polling, using the existing Firestore stream pattern in this codebase. Match Lumina dark theme throughout."

Run-Prompt -Step "10" -Description "Multi-Location Fleet Dashboard List and Map Views" -PromptText $p10

# =============================================================================
# STEP 11 - COMMERCIAL NAVIGATION AND MODE SWITCHING
# =============================================================================
$p11 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. All commercial screens are now built: CommercialOnboardingWizard Screens 1-8, CommercialScheduleScreen, FleetDashboardScreen. All commercial services and models exist. The existing app has its own navigation/routing system and a residential mode.

Wire up Commercial Mode into the existing app:

1. COMMERCIAL MODE DETECTION AND ROUTING: On app launch after auth, check if the current user profile has commercialModeEnabled (bool on the existing user profile document) and if a CommercialLocation exists for this user in Firestore. If yes route to CommercialHomeScreen. If no route to existing residential home as normal.

2. COMMERCIAL HOME SCREEN in lib/screens/commercial/CommercialHomeScreen.dart: For single-location commercial users show CommercialScheduleScreen as primary home view with bottom nav or side drawer providing access to Schedule, Your Teams, Business Profile, Channels, and Alerts/Notifications. For multi-location users with CORPORATE_ADMIN or REGIONAL_MANAGER role show FleetDashboardScreen as primary home with Fleet Dashboard as the first tab.

3. MODE SWITCHER: In the existing app settings or profile screen add a Switch to Residential Mode option for commercial users and Switch to Commercial Mode for residential users who have a commercial profile. Switching mode updates a local preference and re-routes without deleting data. If a residential user taps Set Up Commercial Mode launch the CommercialOnboardingWizard.

4. COMMERCIAL BOTTOM NAVIGATION for CommercialHomeScreen - single-location items: Schedule with timeline icon, Your Teams with sport icon, Channels with lights icon navigating to channel role management, Profile with business icon navigating to Business Profile edit screen. Multi-location adds Fleet with grid icon as the first tab with Schedule accessible by tapping into an individual location from Fleet view.

5. BUSINESS PROFILE EDIT SCREEN in lib/screens/commercial/profile/: Allows editing of all Business Profile fields post-onboarding. Brand color section reuses the widget from onboarding Screen 2. Hours section reuses the widget from onboarding Screen 3. Save writes directly to Firestore and triggers autopilot schedule recalculation via DayPartSchedulerService.

6. COMMERCIAL NOTIFICATIONS: Integrate with the existing FCM push notification system. Add these commercial notification types: CONTROLLER_OFFLINE saying A controller at [Location] is not responding. HOLIDAY_CONFLICT saying Upcoming holiday on [date] - confirm your schedule. GAME_DAY_ALERT saying [Team] game today at [time] - Game Day mode activating at lead time. CORPORATE_PUSH_RECEIVED saying [Org] has updated your schedule. LOCK_EXPIRING saying Corporate schedule lock at [Location] expires in 24 hours. Each notification type deep-links to the relevant commercial screen on tap.

7. PRO TIER BANNER COMPONENT: Create a reusable CommercialProBanner widget in lib/widgets/commercial/. Text: Multi-location management and advanced commercial features are currently included. A Lumina Commercial subscription is coming - set up now to be grandfathered. Style: subtle card with Lumina cyan left border, frost text, dismissible. Show on FleetDashboardScreen on first launch only, ReviewAndGoLiveScreen always, and Business Profile screen for first 3 opens then permanently dismissible. Dismissed state persisted to local SharedPreferences.

Ensure all routing integrates cleanly with the existing navigation system. Do not break any existing residential mode screens or routing."

Run-Prompt -Step "11" -Description "Commercial Mode Routing Navigation and Mode Switching" -PromptText $p11

# =============================================================================
# STEP 12 - INTEGRATION AND SMOKE TEST
# =============================================================================
$p12 = "We are building Lumina Commercial Mode for the nexgen_command Flutter/Dart package. All commercial models, services, screens, and navigation are now built. This is the final integration and verification step.

1. SERVICE REGISTRATION AUDIT: Review lib/ for any commercial services not yet registered in the app dependency injection or service locator setup. Register any missing services as singletons: DaylightSuppressionService, BusinessHoursService, DayPartSchedulerService, GeoTeamSuggestionService, GameDayService, CommercialPermissionsService, CorporatePushService. Ensure correct injection order for all dependencies.

2. FIRESTORE COLLECTION STRUCTURE VERIFICATION: Verify all commercial models use consistent Firestore collection paths. Establish and document these paths as constants in lib/constants/commercial/firestore_paths.dart: organizations/{orgId}, organizations/{orgId}/locations/{locationId}, organizations/{orgId}/locations/{locationId}/channelConfigs/{channelId}, organizations/{orgId}/locations/{locationId}/schedule, organizations/{orgId}/locations/{locationId}/teamsConfig, organizations/{orgId}/locations/{locationId}/businessHours, organizations/{orgId}/brandProfile, campaigns/{campaignId}. Update any service using hardcoded path strings to use these constants.

3. AUTOPILOT INTEGRATION VERIFICATION: Confirm DayPartSchedulerService correctly hands off to the existing Autopilot system when a commercial schedule is active. The commercial schedule should be the authority when commercialModeEnabled is true. Add a guard where needed: if commercialModeEnabled use commercial schedule, else use standard autopilot. Verify the existing autopilot Firestore writes do not conflict with commercial schedule writes.

4. DAYLIGHT SUPPRESSION INTEGRATION: Verify DaylightSuppressionService is called in the main design-resolution loop for outdoor channel roles. Brightness modifier must be applied before the design command is sent to the WLED controller. Confirm the 10-minute fade ramp at sunrise/sunset boundaries works correctly.

5. SPORTS INTEGRATION VERIFICATION: Confirm GameDayService background polling uses the existing background service execution pattern - extend the existing one, do not add a second background isolate. Verify scoring alerts from commercial locations use the channel scope settings from CommercialTeamProfile, not residential-mode defaults.

6. NULL SAFETY AND ERROR HANDLING AUDIT: Review all new commercial Dart files for missing null checks on nullable Firestore fields, missing error handling on async Firestore reads/writes, and missing fallbacks when a service dependency is unavailable. Add try/catch with meaningful error logging using the existing logger pattern to all Firestore read/write operations in commercial services.

7. CREATE SMOKE TEST CHECKLIST: Create docs/commercial_mode_smoke_test.md with a step-by-step manual test checklist covering: complete onboarding wizard flow for a single-location bar, complete onboarding wizard flow for a multi-location chain, verify day-part transitions fire correctly at scheduled times, verify Smart Fill activates for unscheduled gaps, verify outdoor channel dims at sunrise and restores at sunset, verify sports alert fires on scoring event with correct channel scope, verify Game Day mode activates at lead time and reverts after game ends, verify corporate push propagates to all locations, verify locked schedule cannot be edited at location level, verify Pro Tier banner appears and dismisses correctly, verify mode switch between commercial and residential works cleanly.

8. FINAL CLEANUP: Remove any debug print statements. Ensure all new files have the standard file header comment used in this codebase. Run flutter analyze and resolve any warnings or errors in the new commercial files. Confirm the app builds without errors in both debug and release configurations."

Run-Prompt -Step "12" -Description "Integration Service Wiring and End-to-End Smoke Test" -PromptText $p12

# =============================================================================
# DONE
# =============================================================================
Write-Host ""
Write-Host "========================================================" -ForegroundColor Green
Write-Host " ALL STEPS COMPLETE" -ForegroundColor Green
Write-Host " Lumina Commercial Mode build sequence finished." -ForegroundColor Green
Write-Host " Review docs/commercial_mode_smoke_test.md" -ForegroundColor Green
Write-Host " to verify the full feature set end-to-end." -ForegroundColor Green
Write-Host "========================================================" -ForegroundColor Green
