/**
 * Schedule Conflict Detector
 *
 * Checks proposed schedule entries against existing events to identify
 * time overlaps, zone conflicts, and priority resolution suggestions.
 */
import { ScheduleEvent } from "./scheduling-system-prompt";
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
/**
 * Detect scheduling conflicts between proposed entries and existing schedule.
 *
 * @param proposed  - The new entries the user wants to add
 * @param existing  - The current schedule events
 * @returns Array of detected conflicts with resolution suggestions
 */
export declare function detectConflicts(proposed: ProposedEntry[], existing: ScheduleEvent[]): ConflictResult[];
