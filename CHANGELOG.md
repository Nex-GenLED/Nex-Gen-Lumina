# Lumina Changelog

## [2.1.0] - 2026-03-10

### Fixed
- Warm White and Bright White home screen favorites no longer crash the app
- Full RGBW W-channel audit across all color definitions — all missing W channels patched
- Location permission prompt no longer appears on every app launch
- Bottom navigation bar is now flush with screen edges on all devices
- Page content no longer renders underneath the navigation bar on any screen
- Pattern name on home screen no longer defaults to "Lumina Pattern"

### Added
- Neighborhood Sync: full Explore Patterns library access (removed 7-effect / 6-colorway cap)
- Neighborhood Sync: per-house manual pattern assignment
- Neighborhood Sync: local user override always takes priority over active sync session
- Neighborhood Sync: Game Day team selection with dynamic team colors
- Neighborhood Sync: live score celebration propagation to all group members
- Neighborhood Sync + Autopilot: Sync Events — automated group sessions triggered by game schedule
- Autopilot Sync Events: FCM push notification delivery
- Autopilot Sync Events: background execution via flutter_background_service
- Autopilot Sync Events: full season schedule support via GameScheduleService
- Live scoring: FIFA World Cup 2026 support (48 nations, ESPN integration)
- Live scoring: UEFA Champions League support
- Live scoring: NCAA Division I FBS Football support
- Live scoring: NCAA Division I Men's Basketball support
- Explore Patterns: Soccer folder restructure (Ligue 1 removed, Champions League and FIFA WC 2026 added)
- Explore Patterns: Global & Cultural category with National Colors (100 countries)
- Explore Patterns: College Football and College Basketball subfolders
- Home screen: unified For You strip (favorites + smart suggestions merged)
- Onboarding: Preferred White selection with live hardware preview
- Speed control: per-effect logarithmic speed profiles with soft ceiling and extended range
- Pattern naming: smart fallback hierarchy replacing hardcoded "Lumina Pattern" default
- Pattern naming: tap-to-save custom configurations from home screen

### Removed
- Simple Mode (replaced by unified experience with smart defaults)
- Ligue 1 folder (was empty, no team data)
- Legacy sports_alert_service.dart (replaced by live ScoreMonitorService pipeline)

### Architecture
- rgbw_validation.dart: new shared RGBW validation utility
- TeamColorResolver: unified lookup bridge between two team color databases
- Single transmission chokepoint at wled_payload_utils.dart for all RGBW validation
- NWSL duplication resolved — now appears under Soccer only
