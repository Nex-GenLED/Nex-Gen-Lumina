/**
 * processScheduleCommand — Firebase Cloud Function
 *
 * Receives a natural language scheduling request from the Flutter app,
 * sends it to Claude with full scheduling context, detects conflicts,
 * generates variety for multi-day plans, and returns structured responses.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */
import { ConflictResult } from "./schedule-conflict-detector";
type ResponseType = "ready_to_execute" | "confirm_plan" | "needs_clarification" | "confirm_multi_day_plan" | "conflict_detected";
type Complexity = "SIMPLE" | "MODERATE" | "COMPLEX";
interface ScheduleEntryResponse {
    name: string;
    zone: string;
    startTime: string | null;
    endTime: string | null;
    days: string[];
    effectId: number;
    colors: number[][];
    brightness: number;
    speed: number;
    intensity: number;
    recurring: boolean;
    triggerType: "clock" | "sunrise" | "sunset";
    triggerOffset: number;
    priority: number;
}
interface ScheduleCommandResponse {
    responseType: ResponseType;
    responseText: string;
    scheduleEntries: ScheduleEntryResponse[] | null;
    conflicts: ConflictResult[] | null;
    clarificationOptions: string[] | null;
    previewColors: number[][] | null;
    complexity: Complexity;
    confidence: number;
}
export declare const processScheduleCommand: import("firebase-functions/v2/https").CallableFunction<any, Promise<ScheduleCommandResponse>, unknown>;
export {};
