/// Reserved preset ID ranges in WLED's 1-250 preset
/// slot space. These ranges MUST NOT overlap.
///
/// Coordination across multiple Lumina subsystems
/// that allocate preset IDs:
///
///   1, 2          — System presets (ON, OFF) per
///                   WLED defaults
///   10-25         — ScheduleItem recurring slots
///                   (16 slots, allocated by
///                   ScheduleSyncService)
///   26-41         — CalendarEntry lease slots
///                   (16 slots, allocated by
///                   CalendarEntryLeaseManager
///                   per Item #61 Workstream B)
///   100-200       — User-created patterns from
///                   EditPattern flow (101 slots,
///                   allocated by hash modulo this
///                   range)
///
/// Gaps (3-9, 42-99, 201-250) are intentional
/// breathing room for future feature ranges. Don't
/// fill them without updating this file's docs and
/// auditing all allocators.
///
/// Item #65 — EditPattern previously allocated
/// across 1-250, which could silently overwrite any
/// of the above ranges. Restricting to 100-200
/// eliminates the collision.
library;

/// The WLED preset that kills master power. Every
/// OFF boundary — clock, solar, global sunrise-off —
/// fires this macro. Mirrors
/// `ScheduleSyncService.kNglOffPresetId`; a test
/// asserts the two agree.
const int kSystemOffPresetId = 2;

/// The system ON preset slots. Mirrors the keys of
/// `ScheduleSyncService.kOnPresetSpecs`; a test
/// asserts the two agree, so this file can stay pure
/// Dart without the tables drifting apart.
const Set<int> kSystemOnPresetIds = {1, 3, 4, 5};

/// First / last preset ID allocated to a recurring
/// [ScheduleItem] by ScheduleSyncService.
const int kFirstSchedulePresetId = 10;
const int kLastSchedulePresetId = 25;

/// First / last preset ID allocated to a CalendarEntry
/// lease by CalendarEntryLeaseManager. NOTE: this is a
/// preset-id convention, NOT a timer-slot reservation —
/// lease timers live in the general slots 0-7.
const int kFirstLeasePresetId = 26;
const int kLastLeasePresetId = 41;

/// What a WLED timer's `macro` (a preset id) means, as
/// a stable snake_case tag.
///
/// This exists so a SERVER-side reader does not have
/// to re-derive the allocation table above. The device
/// publishes raw macros; only the app knows which
/// range allocated them, and a Cloud Function that
/// guessed would be re-implementing this file from
/// memory — the exact failure mode this codebase keeps
/// hitting with device conventions.
///
/// `unknown` is returned rather than guessed: a macro
/// in one of the intentional gaps (3-9 aside from the
/// ON slots, 42-99, 201-250) was written by something
/// outside Lumina's allocators — a customer using the
/// WLED web UI directly, most likely — and mislabeling
/// it would be worse than admitting we don't know.
String wledPresetRole(int macro) {
  if (macro == kSystemOffPresetId) return 'system_off';
  if (kSystemOnPresetIds.contains(macro)) return 'system_on';
  if (macro >= kFirstSchedulePresetId && macro <= kLastSchedulePresetId) {
    return 'schedule';
  }
  if (macro >= kFirstLeasePresetId && macro <= kLastLeasePresetId) {
    return 'lease';
  }
  if (macro >= kUserPatternPresetRangeStart &&
      macro <= kUserPatternPresetRangeEnd) {
    return 'user_pattern';
  }
  return 'unknown';
}

/// First preset ID reserved for user-created
/// patterns from the EditPattern flow.
const int kUserPatternPresetRangeStart = 100;

/// Last preset ID reserved for user-created
/// patterns (inclusive).
const int kUserPatternPresetRangeEnd = 200;

/// Total count of slots in the user-pattern range.
const int kUserPatternPresetRangeSize =
    kUserPatternPresetRangeEnd - kUserPatternPresetRangeStart + 1;

/// Compute a preset ID for a user-created pattern
/// by hashing its stable ID into the reserved range.
///
/// Returns a value in [kUserPatternPresetRangeStart,
/// kUserPatternPresetRangeEnd]. Deterministic — the
/// same patternId always returns the same preset ID,
/// so saves to the same pattern overwrite themselves
/// rather than creating duplicate presets.
///
/// Two patterns whose IDs hash to the same modulo
/// will collide — that's an acceptable trade-off
/// given 101 available slots; users rarely have
/// more than a few dozen custom patterns. A future
/// "next free slot" allocator could replace this
/// if collision becomes a real issue.
int presetIdForUserPattern(String patternId) {
  final modValue = patternId.hashCode.abs() % kUserPatternPresetRangeSize;
  return kUserPatternPresetRangeStart + modValue;
}
