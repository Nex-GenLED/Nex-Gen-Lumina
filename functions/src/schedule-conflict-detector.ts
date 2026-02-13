/**
 * Schedule Conflict Detector
 *
 * Checks proposed schedule entries against existing events to identify
 * time overlaps, zone conflicts, and priority resolution suggestions.
 */

import { ScheduleEvent } from "./scheduling-system-prompt";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ConflictResult {
  existingEventId: string;
  existingEventName: string;
  overlapDescription: string;
  suggestedResolution: "replace" | "adjust_time" | "merge" | "keep_both";
}

export interface ProposedEntry {
  name: string;
  zone: string;
  startTime: string | null;
  endTime: string | null;
  days: string[];
  recurring: boolean;
  priority?: number;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Parse "HH:mm" into minutes since midnight.
 * Returns null if the format is unrecognizable.
 */
function parseTimeToMinutes(time: string | null | undefined): number | null {
  if (!time || time === "manual") return null;

  const match = time.match(/^(\d{1,2}):(\d{2})$/);
  if (!match) return null;

  const hours = parseInt(match[1], 10);
  const minutes = parseInt(match[2], 10);
  if (hours < 0 || hours > 23 || minutes < 0 || minutes > 59) return null;

  return hours * 60 + minutes;
}

/**
 * Normalize day strings to lowercase for comparison.
 */
function normalizeDays(days: string[]): Set<string> {
  return new Set(days.map((d) => d.toLowerCase().trim()));
}

/**
 * Check whether two time ranges overlap.
 * Handles wrap-around midnight (e.g., 22:00 → 02:00).
 */
function timeRangesOverlap(
  startA: number,
  endA: number,
  startB: number,
  endB: number
): boolean {
  // Handle "all night" / wrap-around cases
  // If end < start, the range wraps past midnight
  const rangesA = normalizeRange(startA, endA);
  const rangesB = normalizeRange(startB, endB);

  for (const a of rangesA) {
    for (const b of rangesB) {
      if (a.start < b.end && b.start < a.end) {
        return true;
      }
    }
  }
  return false;
}

/**
 * Normalize a time range that may wrap past midnight into 1-2 non-wrapping ranges.
 */
function normalizeRange(
  start: number,
  end: number
): Array<{ start: number; end: number }> {
  if (end > start) {
    return [{ start, end }];
  }
  // Wraps past midnight: split into two ranges
  return [
    { start, end: 24 * 60 },
    { start: 0, end },
  ];
}

/**
 * Format minutes back to "HH:mm" for human-readable output.
 */
function formatMinutes(minutes: number): string {
  const h = Math.floor(minutes / 60) % 24;
  const m = minutes % 60;
  return `${h.toString().padStart(2, "0")}:${m.toString().padStart(2, "0")}`;
}

// ---------------------------------------------------------------------------
// Conflict Detection
// ---------------------------------------------------------------------------

/**
 * Detect scheduling conflicts between proposed entries and existing schedule.
 *
 * @param proposed  - The new entries the user wants to add
 * @param existing  - The current schedule events
 * @returns Array of detected conflicts with resolution suggestions
 */
export function detectConflicts(
  proposed: ProposedEntry[],
  existing: ScheduleEvent[]
): ConflictResult[] {
  const conflicts: ConflictResult[] = [];

  for (const entry of proposed) {
    const entryStart = parseTimeToMinutes(entry.startTime);
    const entryEnd = parseTimeToMinutes(entry.endTime);
    const entryDays = normalizeDays(entry.days);

    for (const event of existing) {
      // Check zone overlap: "all" conflicts with everything
      const zoneOverlap =
        entry.zone === "all" ||
        event.zone === "all" ||
        entry.zone.toLowerCase() === event.zone.toLowerCase();

      if (!zoneOverlap) continue;

      // Check day overlap
      const eventDays = normalizeDays(event.days);
      const sharedDays: string[] = [];
      for (const day of entryDays) {
        if (eventDays.has(day)) {
          sharedDays.push(day);
        }
      }

      // Also check specific dates against day-of-week
      // (a date like "2025-12-25" might fall on a "thursday" recurring event)
      // For simplicity, we flag overlaps on matching day strings only

      if (sharedDays.length === 0) continue;

      // Check time overlap
      const eventStart = parseTimeToMinutes(event.startTime);
      const eventEnd = parseTimeToMinutes(event.endTime);

      // If either event has no parseable times, we can't check time overlap
      // but flag a potential day+zone conflict
      if (
        entryStart === null ||
        entryEnd === null ||
        eventStart === null ||
        eventEnd === null
      ) {
        // Potential conflict — same zone and day but can't determine times
        conflicts.push({
          existingEventId: event.id,
          existingEventName: event.name,
          overlapDescription: `"${entry.name}" and "${event.name}" are on the same ${sharedDays.length === 1 ? "day" : "days"} (${sharedDays.join(", ")}) for zone "${event.zone}" but times could not be fully compared.`,
          suggestedResolution: "keep_both",
        });
        continue;
      }

      if (timeRangesOverlap(entryStart, entryEnd, eventStart, eventEnd)) {
        // Determine resolution suggestion
        const resolution = suggestResolution(entry, event);
        const daysLabel =
          sharedDays.length <= 3
            ? sharedDays.join(", ")
            : `${sharedDays.length} days`;

        conflicts.push({
          existingEventId: event.id,
          existingEventName: event.name,
          overlapDescription: `"${entry.name}" (${formatMinutes(entryStart)}–${formatMinutes(entryEnd)}) overlaps with "${event.name}" (${formatMinutes(eventStart)}–${formatMinutes(eventEnd)}) on ${daysLabel} for zone "${event.zone}".`,
          suggestedResolution: resolution,
        });
      }
    }
  }

  return deduplicateConflicts(conflicts);
}

/**
 * Suggest the best conflict resolution based on event characteristics.
 */
function suggestResolution(
  proposed: ProposedEntry,
  existing: ScheduleEvent
): ConflictResult["suggestedResolution"] {
  const proposedPriority = proposed.priority ?? 50;
  const existingPriority = existing.priority ?? 50;

  // If the new event is temporary (non-recurring) and existing is recurring,
  // suggest keeping both (temporary overrides for its specific dates)
  if (!proposed.recurring && existing.recurring) {
    return "keep_both";
  }

  // If the new event has higher priority, suggest replacing
  if (proposedPriority > existingPriority) {
    return "replace";
  }

  // If the existing event has higher priority, suggest adjusting the new event's time
  if (existingPriority > proposedPriority) {
    return "adjust_time";
  }

  // Same priority, recurring vs recurring → suggest replacing
  if (proposed.recurring && existing.recurring) {
    return "replace";
  }

  // Default: let the user decide
  return "replace";
}

/**
 * Remove duplicate conflicts (same existing event flagged multiple times).
 */
function deduplicateConflicts(conflicts: ConflictResult[]): ConflictResult[] {
  const seen = new Set<string>();
  return conflicts.filter((c) => {
    const key = `${c.existingEventId}:${c.overlapDescription}`;
    if (seen.has(key)) return false;
    seen.add(key);
    return true;
  });
}
