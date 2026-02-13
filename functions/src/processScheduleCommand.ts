/**
 * processScheduleCommand — Firebase Cloud Function
 *
 * Receives a natural language scheduling request from the Flutter app,
 * sends it to Claude with full scheduling context, detects conflicts,
 * generates variety for multi-day plans, and returns structured responses.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import {
  checkRateLimit,
  recordUsage,
  sanitizeText,
  ValidationError,
  RateLimitError,
} from "./validators";
import {
  buildSchedulingSystemPrompt,
  ScheduleContext,
  ScheduleEvent,
  TeamInfo,
  AvailableEffect,
} from "./scheduling-system-prompt";
import { detectConflicts, ConflictResult } from "./schedule-conflict-detector";
import { generateVarietyPlan, VarietyConfig } from "./variety-generator";
import { sendMessage, ClaudeClientError } from "./claude-client";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const anthropicApiKey = defineString("ANTHROPIC_API_KEY");

// ---------------------------------------------------------------------------
// Input Types
// ---------------------------------------------------------------------------

interface ScheduleCommandInput {
  text: string;
  conversationHistory: Array<{ role: "user" | "assistant"; content: string }>;
  currentSchedule: ScheduleEvent[];
  userLocation: { timezone: string; latitude?: number; longitude?: number };
  userTeams: TeamInfo[];
  availableZones: string[];
  availableEffects: AvailableEffect[];
  teamColorDatabase: Record<string, TeamInfo>;
  currentDateTime: string;
  sunriseTime?: string;
  sunsetTime?: string;
}

// ---------------------------------------------------------------------------
// Response Types
// ---------------------------------------------------------------------------

type ResponseType =
  | "ready_to_execute"
  | "confirm_plan"
  | "needs_clarification"
  | "confirm_multi_day_plan"
  | "conflict_detected";

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

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_TEXT_LENGTH = 1000;
const MAX_CONVERSATION_TURNS = 10;
const MAX_TURN_LENGTH = 2000;
const MAX_SCHEDULE_EVENTS = 100;
const MAX_TEAMS = 20;
const MAX_ZONES = 20;
const MAX_EFFECTS = 200;

const VALID_RESPONSE_TYPES: ResponseType[] = [
  "ready_to_execute",
  "confirm_plan",
  "needs_clarification",
  "confirm_multi_day_plan",
  "conflict_detected",
];

const VALID_COMPLEXITIES: Complexity[] = ["SIMPLE", "MODERATE", "COMPLEX"];

// ---------------------------------------------------------------------------
// Input Validation
// ---------------------------------------------------------------------------

function validateScheduleInput(data: unknown): ScheduleCommandInput {
  if (!data || typeof data !== "object") {
    throw new ValidationError("Request body must be an object", "root");
  }

  const d = data as Record<string, unknown>;

  // --- text ---
  if (typeof d.text !== "string" || d.text.trim().length === 0) {
    throw new ValidationError(
      "text must be a non-empty string",
      "text"
    );
  }
  let text = sanitizeText(d.text);
  if (text.length > MAX_TEXT_LENGTH) {
    text = text.substring(0, MAX_TEXT_LENGTH);
  }

  // --- conversationHistory ---
  let conversationHistory: Array<{
    role: "user" | "assistant";
    content: string;
  }> = [];
  if (d.conversationHistory !== undefined) {
    if (!Array.isArray(d.conversationHistory)) {
      throw new ValidationError(
        "conversationHistory must be an array",
        "conversationHistory"
      );
    }
    conversationHistory = (d.conversationHistory as unknown[])
      .slice(-MAX_CONVERSATION_TURNS)
      .map((turn, i) => {
        if (!turn || typeof turn !== "object") {
          throw new ValidationError(
            `Turn at index ${i} must be an object`,
            `conversationHistory[${i}]`
          );
        }
        const t = turn as Record<string, unknown>;
        if (t.role !== "user" && t.role !== "assistant") {
          throw new ValidationError(
            `Turn role must be "user" or "assistant"`,
            `conversationHistory[${i}].role`
          );
        }
        let content =
          typeof t.content === "string" ? sanitizeText(t.content) : "";
        if (content.length > MAX_TURN_LENGTH) {
          content = content.substring(0, MAX_TURN_LENGTH);
        }
        return { role: t.role as "user" | "assistant", content };
      });
  }

  // --- currentSchedule ---
  let currentSchedule: ScheduleEvent[] = [];
  if (d.currentSchedule !== undefined) {
    if (!Array.isArray(d.currentSchedule)) {
      throw new ValidationError(
        "currentSchedule must be an array",
        "currentSchedule"
      );
    }
    currentSchedule = (d.currentSchedule as unknown[])
      .slice(0, MAX_SCHEDULE_EVENTS)
      .map((e) => normalizeScheduleEvent(e));
  }

  // --- userLocation ---
  if (!d.userLocation || typeof d.userLocation !== "object") {
    throw new ValidationError(
      "userLocation must be an object with timezone",
      "userLocation"
    );
  }
  const loc = d.userLocation as Record<string, unknown>;
  if (typeof loc.timezone !== "string" || loc.timezone.length === 0) {
    throw new ValidationError(
      "userLocation.timezone must be a non-empty string",
      "userLocation.timezone"
    );
  }
  const userLocation = {
    timezone: loc.timezone,
    latitude: typeof loc.latitude === "number" ? loc.latitude : undefined,
    longitude: typeof loc.longitude === "number" ? loc.longitude : undefined,
  };

  // --- userTeams ---
  let userTeams: TeamInfo[] = [];
  if (d.userTeams !== undefined && Array.isArray(d.userTeams)) {
    userTeams = (d.userTeams as unknown[])
      .slice(0, MAX_TEAMS)
      .filter(
        (t): t is Record<string, unknown> =>
          !!t && typeof t === "object" && typeof (t as Record<string, unknown>).name === "string"
      )
      .map((t) => ({
        name: t.name as string,
        league: (t.league as string) ?? "",
        abbreviation: (t.abbreviation as string) ?? "",
        primaryColor: Array.isArray(t.primaryColor)
          ? (t.primaryColor as number[])
          : [255, 0, 0],
        secondaryColor: Array.isArray(t.secondaryColor)
          ? (t.secondaryColor as number[])
          : [255, 255, 255],
        accentColor: Array.isArray(t.accentColor)
          ? (t.accentColor as number[])
          : undefined,
      }));
  }

  // --- availableZones ---
  let availableZones: string[] = [];
  if (Array.isArray(d.availableZones)) {
    availableZones = (d.availableZones as unknown[])
      .slice(0, MAX_ZONES)
      .filter((z): z is string => typeof z === "string" && z.length > 0);
  }
  if (availableZones.length === 0) {
    availableZones = ["all"];
  }

  // --- availableEffects ---
  let availableEffects: AvailableEffect[] = [];
  if (Array.isArray(d.availableEffects)) {
    availableEffects = (d.availableEffects as unknown[])
      .slice(0, MAX_EFFECTS)
      .filter(
        (e): e is Record<string, unknown> =>
          !!e && typeof e === "object" && typeof (e as Record<string, unknown>).id === "number"
      )
      .map((e) => ({
        id: e.id as number,
        name: (e.name as string) ?? `Effect ${e.id}`,
        category: typeof e.category === "string" ? e.category : undefined,
      }));
  }

  // --- teamColorDatabase ---
  let teamColorDatabase: Record<string, TeamInfo> = {};
  if (d.teamColorDatabase && typeof d.teamColorDatabase === "object") {
    teamColorDatabase = d.teamColorDatabase as Record<string, TeamInfo>;
  }

  // --- currentDateTime ---
  const currentDateTime =
    typeof d.currentDateTime === "string"
      ? d.currentDateTime
      : new Date().toISOString();

  // --- sunriseTime / sunsetTime ---
  const sunriseTime =
    typeof d.sunriseTime === "string" ? d.sunriseTime : undefined;
  const sunsetTime =
    typeof d.sunsetTime === "string" ? d.sunsetTime : undefined;

  return {
    text,
    conversationHistory,
    currentSchedule,
    userLocation,
    userTeams,
    availableZones,
    availableEffects,
    teamColorDatabase,
    currentDateTime,
    sunriseTime,
    sunsetTime,
  };
}

/**
 * Normalize a raw schedule event from the client into a typed ScheduleEvent.
 */
function normalizeScheduleEvent(raw: unknown): ScheduleEvent {
  if (!raw || typeof raw !== "object") {
    return createDefaultEvent();
  }

  const e = raw as Record<string, unknown>;
  return {
    id: typeof e.id === "string" ? e.id : "",
    name: typeof e.name === "string" ? e.name : "Unnamed",
    zone: typeof e.zone === "string" ? e.zone : "all",
    startTime: typeof e.startTime === "string" ? e.startTime : "18:00",
    endTime: typeof e.endTime === "string" ? e.endTime : "22:00",
    days: Array.isArray(e.days)
      ? (e.days as unknown[]).filter((d): d is string => typeof d === "string")
      : [],
    effectId: typeof e.effectId === "number" ? e.effectId : 0,
    colors: Array.isArray(e.colors)
      ? (e.colors as number[][])
      : [[255, 255, 255]],
    brightness: typeof e.brightness === "number" ? e.brightness : 200,
    speed: typeof e.speed === "number" ? e.speed : undefined,
    intensity: typeof e.intensity === "number" ? e.intensity : undefined,
    recurring: typeof e.recurring === "boolean" ? e.recurring : true,
    priority: typeof e.priority === "number" ? e.priority : 50,
    triggerType:
      e.triggerType === "sunrise" || e.triggerType === "sunset"
        ? e.triggerType
        : "clock",
    triggerOffset: typeof e.triggerOffset === "number" ? e.triggerOffset : 0,
  };
}

function createDefaultEvent(): ScheduleEvent {
  return {
    id: "",
    name: "Unnamed",
    zone: "all",
    startTime: "18:00",
    endTime: "22:00",
    days: [],
    effectId: 0,
    colors: [[255, 255, 255]],
    brightness: 200,
    recurring: true,
    triggerType: "clock",
    triggerOffset: 0,
  };
}

// ---------------------------------------------------------------------------
// Response Validation
// ---------------------------------------------------------------------------

/**
 * Validate and normalize the JSON response from Claude.
 */
function validateScheduleResponse(
  json: Record<string, unknown> | null,
  existingSchedule: ScheduleEvent[]
): ScheduleCommandResponse {
  if (!json) {
    throw new Error("Claude did not return valid JSON");
  }

  // --- responseType ---
  let responseType = json.responseType as string;
  if (
    !VALID_RESPONSE_TYPES.includes(responseType as ResponseType)
  ) {
    // Default based on whether entries exist
    responseType = json.scheduleEntries ? "confirm_plan" : "needs_clarification";
  }

  // --- responseText ---
  const responseText =
    typeof json.responseText === "string"
      ? json.responseText
      : "Here's what I've put together for your schedule.";

  // --- complexity ---
  let complexity = json.complexity as string;
  if (!VALID_COMPLEXITIES.includes(complexity as Complexity)) {
    complexity = "MODERATE";
  }

  // --- confidence ---
  const confidence =
    typeof json.confidence === "number"
      ? Math.max(0, Math.min(1, json.confidence))
      : 0.8;

  // --- scheduleEntries ---
  let scheduleEntries: ScheduleEntryResponse[] | null = null;
  if (Array.isArray(json.scheduleEntries)) {
    scheduleEntries = (
      json.scheduleEntries as Array<Record<string, unknown>>
    ).map((entry) => normalizeEntryResponse(entry));
  }

  // --- Run server-side conflict detection ---
  let conflicts: ConflictResult[] | null = null;
  if (scheduleEntries && scheduleEntries.length > 0) {
    const detected = detectConflicts(
      scheduleEntries.map((e) => ({
        name: e.name,
        zone: e.zone,
        startTime: e.startTime,
        endTime: e.endTime,
        days: e.days,
        recurring: e.recurring,
        priority: e.priority,
      })),
      existingSchedule
    );

    if (detected.length > 0) {
      conflicts = detected;
      // Override response type if Claude didn't detect the conflicts
      if (
        responseType !== "conflict_detected" &&
        responseType !== "needs_clarification"
      ) {
        responseType = "conflict_detected";
      }
    }
  }

  // Also include any conflicts Claude reported
  if (Array.isArray(json.conflicts) && json.conflicts.length > 0) {
    const claudeConflicts = (
      json.conflicts as Array<Record<string, unknown>>
    )
      .filter(
        (c) =>
          typeof c.existingEventId === "string" &&
          typeof c.overlapDescription === "string"
      )
      .map((c) => ({
        existingEventId: c.existingEventId as string,
        existingEventName:
          typeof c.existingEventName === "string"
            ? c.existingEventName
            : "Unknown",
        overlapDescription: c.overlapDescription as string,
        suggestedResolution: (c.suggestedResolution as ConflictResult["suggestedResolution"]) ?? "replace",
      }));

    if (conflicts) {
      // Merge, avoiding duplicates by existingEventId
      const existingIds = new Set(conflicts.map((c) => c.existingEventId));
      for (const cc of claudeConflicts) {
        if (!existingIds.has(cc.existingEventId)) {
          conflicts.push(cc);
        }
      }
    } else if (claudeConflicts.length > 0) {
      conflicts = claudeConflicts;
    }
  }

  // --- Multi-day plan upgrade ---
  // If 4+ entries and Claude said ready_to_execute, upgrade to confirm_multi_day_plan
  if (
    scheduleEntries &&
    scheduleEntries.length >= 4 &&
    responseType === "ready_to_execute"
  ) {
    responseType = "confirm_multi_day_plan";
  }

  // --- previewColors ---
  let previewColors: number[][] | null = null;
  if (Array.isArray(json.previewColors)) {
    previewColors = (json.previewColors as unknown[])
      .slice(0, 9)
      .filter(
        (c): c is number[] =>
          Array.isArray(c) &&
          c.length >= 3 &&
          c.every((v) => typeof v === "number")
      );

    while (previewColors.length < 9 && previewColors.length > 0) {
      previewColors.push(previewColors[previewColors.length - 1]);
    }
    if (previewColors.length === 0) previewColors = null;
  }

  // --- clarificationOptions ---
  let clarificationOptions: string[] | null = null;
  if (Array.isArray(json.clarificationOptions)) {
    clarificationOptions = (json.clarificationOptions as unknown[])
      .filter((o): o is string => typeof o === "string" && o.length > 0)
      .slice(0, 3);
    if (clarificationOptions.length === 0) clarificationOptions = null;
  }

  return {
    responseType: responseType as ResponseType,
    responseText,
    scheduleEntries,
    conflicts,
    clarificationOptions,
    previewColors,
    complexity: complexity as Complexity,
    confidence,
  };
}

/**
 * Normalize a single schedule entry from Claude's response.
 */
function normalizeEntryResponse(
  entry: Record<string, unknown>
): ScheduleEntryResponse {
  return {
    name:
      typeof entry.name === "string" ? entry.name : "Scheduled Lighting",
    zone: typeof entry.zone === "string" ? entry.zone : "all",
    startTime:
      typeof entry.startTime === "string" ? entry.startTime : null,
    endTime:
      typeof entry.endTime === "string" ? entry.endTime : null,
    days: Array.isArray(entry.days)
      ? (entry.days as unknown[]).filter(
          (d): d is string => typeof d === "string"
        )
      : [],
    effectId:
      typeof entry.effectId === "number" ? entry.effectId : 0,
    colors: Array.isArray(entry.colors)
      ? (entry.colors as number[][]).slice(0, 3)
      : [[255, 180, 100]],
    brightness:
      typeof entry.brightness === "number"
        ? Math.max(0, Math.min(255, entry.brightness))
        : 200,
    speed:
      typeof entry.speed === "number"
        ? Math.max(0, Math.min(255, entry.speed))
        : 128,
    intensity:
      typeof entry.intensity === "number"
        ? Math.max(0, Math.min(255, entry.intensity))
        : 128,
    recurring:
      typeof entry.recurring === "boolean" ? entry.recurring : true,
    triggerType:
      entry.triggerType === "sunrise" || entry.triggerType === "sunset"
        ? entry.triggerType
        : "clock",
    triggerOffset:
      typeof entry.triggerOffset === "number" ? entry.triggerOffset : 0,
    priority:
      typeof entry.priority === "number" ? entry.priority : 50,
  };
}

// ---------------------------------------------------------------------------
// Variety Enhancement
// ---------------------------------------------------------------------------

/**
 * If Claude returned a multi-day plan, apply the variety generator to
 * ensure consecutive nights aren't identical.
 */
function applyVarietyIfNeeded(
  entries: ScheduleEntryResponse[]
): ScheduleEntryResponse[] {
  if (entries.length < 3) return entries;

  // Check if entries share the same zone and have different days
  // (indicating a multi-day plan for the same zone)
  const zoneGroups = new Map<string, ScheduleEntryResponse[]>();
  for (const entry of entries) {
    const zone = entry.zone.toLowerCase();
    if (!zoneGroups.has(zone)) {
      zoneGroups.set(zone, []);
    }
    zoneGroups.get(zone)!.push(entry);
  }

  const enhanced: ScheduleEntryResponse[] = [];

  for (const [, group] of zoneGroups) {
    if (group.length < 3) {
      // Not enough entries for variety concern
      enhanced.push(...group);
      continue;
    }

    // Check for consecutive duplicate looks
    let needsVariety = false;
    for (let i = 1; i < group.length; i++) {
      if (
        group[i].effectId === group[i - 1].effectId &&
        colorsMatch(group[i].colors[0], group[i - 1].colors[0])
      ) {
        needsVariety = true;
        break;
      }
    }

    if (!needsVariety) {
      enhanced.push(...group);
      continue;
    }

    // Generate variety
    const days = group.map((e) => e.days[0] ?? "monday");
    const themeColors = group[0].colors;
    const config: VarietyConfig = {
      themeColors,
      brightness: group[0].brightness,
    };

    const varietyPlan = generateVarietyPlan(days, config);

    for (let i = 0; i < group.length; i++) {
      const variety = varietyPlan[i];
      if (variety) {
        enhanced.push({
          ...group[i],
          effectId: variety.effectId,
          colors: variety.colors,
          speed: variety.speed,
          intensity: variety.intensity,
          brightness: variety.brightness,
        });
      } else {
        enhanced.push(group[i]);
      }
    }
  }

  return enhanced;
}

function colorsMatch(a: number[] | undefined, b: number[] | undefined): boolean {
  if (!a || !b) return false;
  if (a.length !== b.length) return false;
  return a.every((v, i) => v === b[i]);
}

// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------

export const processScheduleCommand = onCall(
  {
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 60,
  },
  async (request) => {
    // ------ Authentication ------
    if (!request.auth) {
      throw new HttpsError("unauthenticated", "User must be authenticated");
    }

    const userId = request.auth.uid;
    const apiKey = anthropicApiKey.value();

    if (!apiKey || apiKey === "YOUR_ANTHROPIC_API_KEY_HERE") {
      console.error("Anthropic API key not configured");
      throw new HttpsError(
        "failed-precondition",
        "AI service not configured. Please contact support."
      );
    }

    const startTime = Date.now();

    try {
      // ------ Rate Limiting ------
      const requestCount = await checkRateLimit(userId);

      // ------ Input Validation ------
      const input = validateScheduleInput(request.data);

      // ------ Build System Prompt ------
      const context: ScheduleContext = {
        currentSchedule: input.currentSchedule,
        userLocation: input.userLocation,
        userTeams: input.userTeams,
        availableZones: input.availableZones,
        availableEffects: input.availableEffects,
        teamColorDatabase: input.teamColorDatabase,
        currentDateTime: input.currentDateTime,
        sunriseTime: input.sunriseTime,
        sunsetTime: input.sunsetTime,
      };

      const systemPrompt = buildSchedulingSystemPrompt(context);

      // ------ Build Messages ------
      const messages: Array<{ role: "user" | "assistant"; content: string }> =
        [];

      for (const turn of input.conversationHistory) {
        messages.push({ role: turn.role, content: turn.content });
      }

      messages.push({ role: "user", content: input.text });

      // ------ Call Claude ------
      const claudeResponse = await sendMessage(apiKey, {
        systemPrompt,
        messages,
        maxTokens: 2048, // Larger than Lumina command — schedules have more data
        timeoutMs: 30_000,
      });

      // ------ Parse & Validate Response ------
      let response = validateScheduleResponse(
        claudeResponse.json,
        input.currentSchedule
      );

      // ------ Apply Variety Enhancement ------
      if (response.scheduleEntries && response.scheduleEntries.length >= 3) {
        response = {
          ...response,
          scheduleEntries: applyVarietyIfNeeded(response.scheduleEntries),
        };
      }

      // ------ Log Usage ------
      const latencyMs = Date.now() - startTime;
      await recordUsage(userId, {
        status: "success",
        latencyMs,
        inputTokens: claudeResponse.usage.inputTokens,
        outputTokens: claudeResponse.usage.outputTokens,
        model: claudeResponse.model,
      });

      if (requestCount >= 15) {
        console.warn(
          `User ${userId} approaching schedule rate limit: ${requestCount + 1}/20`
        );
      }

      return response;
    } catch (error) {
      const latencyMs = Date.now() - startTime;

      if (error instanceof ValidationError) {
        console.warn(
          `Schedule validation error for ${userId}: ${error.message} [${error.field}]`
        );
        throw new HttpsError("invalid-argument", error.message);
      }

      if (error instanceof RateLimitError) {
        console.warn(`Rate limit hit for ${userId} (schedule)`);
        await recordUsage(userId, {
          status: "failed",
          latencyMs,
          error: "rate_limit",
        });
        throw new HttpsError("resource-exhausted", error.message);
      }

      if (error instanceof ClaudeClientError) {
        console.error(
          `Claude API error for ${userId} (schedule): kind=${error.kind} status=${error.statusCode}`
        );
        await recordUsage(userId, {
          status: "failed",
          latencyMs,
          error: `claude_${error.kind}`,
        });

        if (error.kind === "authentication") {
          throw new HttpsError(
            "failed-precondition",
            "AI service authentication failed. Please contact support."
          );
        }
        if (error.kind === "rate_limit" || error.kind === "overloaded") {
          throw new HttpsError(
            "unavailable",
            "AI service is temporarily busy. Please try again in a moment."
          );
        }
        throw new HttpsError(
          "internal",
          "AI service encountered an error. Please try again."
        );
      }

      if (error instanceof HttpsError) {
        throw error;
      }

      console.error(`Unexpected error for ${userId} (schedule):`, error);
      await recordUsage(userId, {
        status: "failed",
        latencyMs,
        error: error instanceof Error ? error.message : "unknown",
      }).catch(() => {});

      throw new HttpsError(
        "internal",
        "Something went wrong. Please try again."
      );
    }
  }
);
