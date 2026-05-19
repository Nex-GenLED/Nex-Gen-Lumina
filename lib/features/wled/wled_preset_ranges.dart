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
