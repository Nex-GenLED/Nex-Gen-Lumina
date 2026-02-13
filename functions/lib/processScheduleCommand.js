"use strict";
/**
 * processScheduleCommand — Firebase Cloud Function
 *
 * Receives a natural language scheduling request from the Flutter app,
 * sends it to Claude with full scheduling context, detects conflicts,
 * generates variety for multi-day plans, and returns structured responses.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.processScheduleCommand = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const validators_1 = require("./validators");
const scheduling_system_prompt_1 = require("./scheduling-system-prompt");
const schedule_conflict_detector_1 = require("./schedule-conflict-detector");
const variety_generator_1 = require("./variety-generator");
const claude_client_1 = require("./claude-client");
// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const anthropicApiKey = (0, params_1.defineString)("ANTHROPIC_API_KEY");
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
const VALID_RESPONSE_TYPES = [
    "ready_to_execute",
    "confirm_plan",
    "needs_clarification",
    "confirm_multi_day_plan",
    "conflict_detected",
];
const VALID_COMPLEXITIES = ["SIMPLE", "MODERATE", "COMPLEX"];
// ---------------------------------------------------------------------------
// Input Validation
// ---------------------------------------------------------------------------
function validateScheduleInput(data) {
    if (!data || typeof data !== "object") {
        throw new validators_1.ValidationError("Request body must be an object", "root");
    }
    const d = data;
    // --- text ---
    if (typeof d.text !== "string" || d.text.trim().length === 0) {
        throw new validators_1.ValidationError("text must be a non-empty string", "text");
    }
    let text = (0, validators_1.sanitizeText)(d.text);
    if (text.length > MAX_TEXT_LENGTH) {
        text = text.substring(0, MAX_TEXT_LENGTH);
    }
    // --- conversationHistory ---
    let conversationHistory = [];
    if (d.conversationHistory !== undefined) {
        if (!Array.isArray(d.conversationHistory)) {
            throw new validators_1.ValidationError("conversationHistory must be an array", "conversationHistory");
        }
        conversationHistory = d.conversationHistory
            .slice(-MAX_CONVERSATION_TURNS)
            .map((turn, i) => {
            if (!turn || typeof turn !== "object") {
                throw new validators_1.ValidationError(`Turn at index ${i} must be an object`, `conversationHistory[${i}]`);
            }
            const t = turn;
            if (t.role !== "user" && t.role !== "assistant") {
                throw new validators_1.ValidationError(`Turn role must be "user" or "assistant"`, `conversationHistory[${i}].role`);
            }
            let content = typeof t.content === "string" ? (0, validators_1.sanitizeText)(t.content) : "";
            if (content.length > MAX_TURN_LENGTH) {
                content = content.substring(0, MAX_TURN_LENGTH);
            }
            return { role: t.role, content };
        });
    }
    // --- currentSchedule ---
    let currentSchedule = [];
    if (d.currentSchedule !== undefined) {
        if (!Array.isArray(d.currentSchedule)) {
            throw new validators_1.ValidationError("currentSchedule must be an array", "currentSchedule");
        }
        currentSchedule = d.currentSchedule
            .slice(0, MAX_SCHEDULE_EVENTS)
            .map((e) => normalizeScheduleEvent(e));
    }
    // --- userLocation ---
    if (!d.userLocation || typeof d.userLocation !== "object") {
        throw new validators_1.ValidationError("userLocation must be an object with timezone", "userLocation");
    }
    const loc = d.userLocation;
    if (typeof loc.timezone !== "string" || loc.timezone.length === 0) {
        throw new validators_1.ValidationError("userLocation.timezone must be a non-empty string", "userLocation.timezone");
    }
    const userLocation = {
        timezone: loc.timezone,
        latitude: typeof loc.latitude === "number" ? loc.latitude : undefined,
        longitude: typeof loc.longitude === "number" ? loc.longitude : undefined,
    };
    // --- userTeams ---
    let userTeams = [];
    if (d.userTeams !== undefined && Array.isArray(d.userTeams)) {
        userTeams = d.userTeams
            .slice(0, MAX_TEAMS)
            .filter((t) => !!t && typeof t === "object" && typeof t.name === "string")
            .map((t) => ({
            name: t.name,
            league: t.league ?? "",
            abbreviation: t.abbreviation ?? "",
            primaryColor: Array.isArray(t.primaryColor)
                ? t.primaryColor
                : [255, 0, 0],
            secondaryColor: Array.isArray(t.secondaryColor)
                ? t.secondaryColor
                : [255, 255, 255],
            accentColor: Array.isArray(t.accentColor)
                ? t.accentColor
                : undefined,
        }));
    }
    // --- availableZones ---
    let availableZones = [];
    if (Array.isArray(d.availableZones)) {
        availableZones = d.availableZones
            .slice(0, MAX_ZONES)
            .filter((z) => typeof z === "string" && z.length > 0);
    }
    if (availableZones.length === 0) {
        availableZones = ["all"];
    }
    // --- availableEffects ---
    let availableEffects = [];
    if (Array.isArray(d.availableEffects)) {
        availableEffects = d.availableEffects
            .slice(0, MAX_EFFECTS)
            .filter((e) => !!e && typeof e === "object" && typeof e.id === "number")
            .map((e) => ({
            id: e.id,
            name: e.name ?? `Effect ${e.id}`,
            category: typeof e.category === "string" ? e.category : undefined,
        }));
    }
    // --- teamColorDatabase ---
    let teamColorDatabase = {};
    if (d.teamColorDatabase && typeof d.teamColorDatabase === "object") {
        teamColorDatabase = d.teamColorDatabase;
    }
    // --- currentDateTime ---
    const currentDateTime = typeof d.currentDateTime === "string"
        ? d.currentDateTime
        : new Date().toISOString();
    // --- sunriseTime / sunsetTime ---
    const sunriseTime = typeof d.sunriseTime === "string" ? d.sunriseTime : undefined;
    const sunsetTime = typeof d.sunsetTime === "string" ? d.sunsetTime : undefined;
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
function normalizeScheduleEvent(raw) {
    if (!raw || typeof raw !== "object") {
        return createDefaultEvent();
    }
    const e = raw;
    return {
        id: typeof e.id === "string" ? e.id : "",
        name: typeof e.name === "string" ? e.name : "Unnamed",
        zone: typeof e.zone === "string" ? e.zone : "all",
        startTime: typeof e.startTime === "string" ? e.startTime : "18:00",
        endTime: typeof e.endTime === "string" ? e.endTime : "22:00",
        days: Array.isArray(e.days)
            ? e.days.filter((d) => typeof d === "string")
            : [],
        effectId: typeof e.effectId === "number" ? e.effectId : 0,
        colors: Array.isArray(e.colors)
            ? e.colors
            : [[255, 255, 255]],
        brightness: typeof e.brightness === "number" ? e.brightness : 200,
        speed: typeof e.speed === "number" ? e.speed : undefined,
        intensity: typeof e.intensity === "number" ? e.intensity : undefined,
        recurring: typeof e.recurring === "boolean" ? e.recurring : true,
        priority: typeof e.priority === "number" ? e.priority : 50,
        triggerType: e.triggerType === "sunrise" || e.triggerType === "sunset"
            ? e.triggerType
            : "clock",
        triggerOffset: typeof e.triggerOffset === "number" ? e.triggerOffset : 0,
    };
}
function createDefaultEvent() {
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
function validateScheduleResponse(json, existingSchedule) {
    if (!json) {
        throw new Error("Claude did not return valid JSON");
    }
    // --- responseType ---
    let responseType = json.responseType;
    if (!VALID_RESPONSE_TYPES.includes(responseType)) {
        // Default based on whether entries exist
        responseType = json.scheduleEntries ? "confirm_plan" : "needs_clarification";
    }
    // --- responseText ---
    const responseText = typeof json.responseText === "string"
        ? json.responseText
        : "Here's what I've put together for your schedule.";
    // --- complexity ---
    let complexity = json.complexity;
    if (!VALID_COMPLEXITIES.includes(complexity)) {
        complexity = "MODERATE";
    }
    // --- confidence ---
    const confidence = typeof json.confidence === "number"
        ? Math.max(0, Math.min(1, json.confidence))
        : 0.8;
    // --- scheduleEntries ---
    let scheduleEntries = null;
    if (Array.isArray(json.scheduleEntries)) {
        scheduleEntries = json.scheduleEntries.map((entry) => normalizeEntryResponse(entry));
    }
    // --- Run server-side conflict detection ---
    let conflicts = null;
    if (scheduleEntries && scheduleEntries.length > 0) {
        const detected = (0, schedule_conflict_detector_1.detectConflicts)(scheduleEntries.map((e) => ({
            name: e.name,
            zone: e.zone,
            startTime: e.startTime,
            endTime: e.endTime,
            days: e.days,
            recurring: e.recurring,
            priority: e.priority,
        })), existingSchedule);
        if (detected.length > 0) {
            conflicts = detected;
            // Override response type if Claude didn't detect the conflicts
            if (responseType !== "conflict_detected" &&
                responseType !== "needs_clarification") {
                responseType = "conflict_detected";
            }
        }
    }
    // Also include any conflicts Claude reported
    if (Array.isArray(json.conflicts) && json.conflicts.length > 0) {
        const claudeConflicts = json.conflicts
            .filter((c) => typeof c.existingEventId === "string" &&
            typeof c.overlapDescription === "string")
            .map((c) => ({
            existingEventId: c.existingEventId,
            existingEventName: typeof c.existingEventName === "string"
                ? c.existingEventName
                : "Unknown",
            overlapDescription: c.overlapDescription,
            suggestedResolution: c.suggestedResolution ?? "replace",
        }));
        if (conflicts) {
            // Merge, avoiding duplicates by existingEventId
            const existingIds = new Set(conflicts.map((c) => c.existingEventId));
            for (const cc of claudeConflicts) {
                if (!existingIds.has(cc.existingEventId)) {
                    conflicts.push(cc);
                }
            }
        }
        else if (claudeConflicts.length > 0) {
            conflicts = claudeConflicts;
        }
    }
    // --- Multi-day plan upgrade ---
    // If 4+ entries and Claude said ready_to_execute, upgrade to confirm_multi_day_plan
    if (scheduleEntries &&
        scheduleEntries.length >= 4 &&
        responseType === "ready_to_execute") {
        responseType = "confirm_multi_day_plan";
    }
    // --- previewColors ---
    let previewColors = null;
    if (Array.isArray(json.previewColors)) {
        previewColors = json.previewColors
            .slice(0, 9)
            .filter((c) => Array.isArray(c) &&
            c.length >= 3 &&
            c.every((v) => typeof v === "number"));
        while (previewColors.length < 9 && previewColors.length > 0) {
            previewColors.push(previewColors[previewColors.length - 1]);
        }
        if (previewColors.length === 0)
            previewColors = null;
    }
    // --- clarificationOptions ---
    let clarificationOptions = null;
    if (Array.isArray(json.clarificationOptions)) {
        clarificationOptions = json.clarificationOptions
            .filter((o) => typeof o === "string" && o.length > 0)
            .slice(0, 3);
        if (clarificationOptions.length === 0)
            clarificationOptions = null;
    }
    return {
        responseType: responseType,
        responseText,
        scheduleEntries,
        conflicts,
        clarificationOptions,
        previewColors,
        complexity: complexity,
        confidence,
    };
}
/**
 * Normalize a single schedule entry from Claude's response.
 */
function normalizeEntryResponse(entry) {
    return {
        name: typeof entry.name === "string" ? entry.name : "Scheduled Lighting",
        zone: typeof entry.zone === "string" ? entry.zone : "all",
        startTime: typeof entry.startTime === "string" ? entry.startTime : null,
        endTime: typeof entry.endTime === "string" ? entry.endTime : null,
        days: Array.isArray(entry.days)
            ? entry.days.filter((d) => typeof d === "string")
            : [],
        effectId: typeof entry.effectId === "number" ? entry.effectId : 0,
        colors: Array.isArray(entry.colors)
            ? entry.colors.slice(0, 3)
            : [[255, 180, 100]],
        brightness: typeof entry.brightness === "number"
            ? Math.max(0, Math.min(255, entry.brightness))
            : 200,
        speed: typeof entry.speed === "number"
            ? Math.max(0, Math.min(255, entry.speed))
            : 128,
        intensity: typeof entry.intensity === "number"
            ? Math.max(0, Math.min(255, entry.intensity))
            : 128,
        recurring: typeof entry.recurring === "boolean" ? entry.recurring : true,
        triggerType: entry.triggerType === "sunrise" || entry.triggerType === "sunset"
            ? entry.triggerType
            : "clock",
        triggerOffset: typeof entry.triggerOffset === "number" ? entry.triggerOffset : 0,
        priority: typeof entry.priority === "number" ? entry.priority : 50,
    };
}
// ---------------------------------------------------------------------------
// Variety Enhancement
// ---------------------------------------------------------------------------
/**
 * If Claude returned a multi-day plan, apply the variety generator to
 * ensure consecutive nights aren't identical.
 */
function applyVarietyIfNeeded(entries) {
    if (entries.length < 3)
        return entries;
    // Check if entries share the same zone and have different days
    // (indicating a multi-day plan for the same zone)
    const zoneGroups = new Map();
    for (const entry of entries) {
        const zone = entry.zone.toLowerCase();
        if (!zoneGroups.has(zone)) {
            zoneGroups.set(zone, []);
        }
        zoneGroups.get(zone).push(entry);
    }
    const enhanced = [];
    for (const [, group] of zoneGroups) {
        if (group.length < 3) {
            // Not enough entries for variety concern
            enhanced.push(...group);
            continue;
        }
        // Check for consecutive duplicate looks
        let needsVariety = false;
        for (let i = 1; i < group.length; i++) {
            if (group[i].effectId === group[i - 1].effectId &&
                colorsMatch(group[i].colors[0], group[i - 1].colors[0])) {
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
        const config = {
            themeColors,
            brightness: group[0].brightness,
        };
        const varietyPlan = (0, variety_generator_1.generateVarietyPlan)(days, config);
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
            }
            else {
                enhanced.push(group[i]);
            }
        }
    }
    return enhanced;
}
function colorsMatch(a, b) {
    if (!a || !b)
        return false;
    if (a.length !== b.length)
        return false;
    return a.every((v, i) => v === b[i]);
}
// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------
exports.processScheduleCommand = (0, https_1.onCall)({
    region: "us-central1",
    memory: "512MiB",
    timeoutSeconds: 60,
}, async (request) => {
    // ------ Authentication ------
    if (!request.auth) {
        throw new https_1.HttpsError("unauthenticated", "User must be authenticated");
    }
    const userId = request.auth.uid;
    const apiKey = anthropicApiKey.value();
    if (!apiKey || apiKey === "YOUR_ANTHROPIC_API_KEY_HERE") {
        console.error("Anthropic API key not configured");
        throw new https_1.HttpsError("failed-precondition", "AI service not configured. Please contact support.");
    }
    const startTime = Date.now();
    try {
        // ------ Rate Limiting ------
        const requestCount = await (0, validators_1.checkRateLimit)(userId);
        // ------ Input Validation ------
        const input = validateScheduleInput(request.data);
        // ------ Build System Prompt ------
        const context = {
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
        const systemPrompt = (0, scheduling_system_prompt_1.buildSchedulingSystemPrompt)(context);
        // ------ Build Messages ------
        const messages = [];
        for (const turn of input.conversationHistory) {
            messages.push({ role: turn.role, content: turn.content });
        }
        messages.push({ role: "user", content: input.text });
        // ------ Call Claude ------
        const claudeResponse = await (0, claude_client_1.sendMessage)(apiKey, {
            systemPrompt,
            messages,
            maxTokens: 2048, // Larger than Lumina command — schedules have more data
            timeoutMs: 30_000,
        });
        // ------ Parse & Validate Response ------
        let response = validateScheduleResponse(claudeResponse.json, input.currentSchedule);
        // ------ Apply Variety Enhancement ------
        if (response.scheduleEntries && response.scheduleEntries.length >= 3) {
            response = {
                ...response,
                scheduleEntries: applyVarietyIfNeeded(response.scheduleEntries),
            };
        }
        // ------ Log Usage ------
        const latencyMs = Date.now() - startTime;
        await (0, validators_1.recordUsage)(userId, {
            status: "success",
            latencyMs,
            inputTokens: claudeResponse.usage.inputTokens,
            outputTokens: claudeResponse.usage.outputTokens,
            model: claudeResponse.model,
        });
        if (requestCount >= 15) {
            console.warn(`User ${userId} approaching schedule rate limit: ${requestCount + 1}/20`);
        }
        return response;
    }
    catch (error) {
        const latencyMs = Date.now() - startTime;
        if (error instanceof validators_1.ValidationError) {
            console.warn(`Schedule validation error for ${userId}: ${error.message} [${error.field}]`);
            throw new https_1.HttpsError("invalid-argument", error.message);
        }
        if (error instanceof validators_1.RateLimitError) {
            console.warn(`Rate limit hit for ${userId} (schedule)`);
            await (0, validators_1.recordUsage)(userId, {
                status: "failed",
                latencyMs,
                error: "rate_limit",
            });
            throw new https_1.HttpsError("resource-exhausted", error.message);
        }
        if (error instanceof claude_client_1.ClaudeClientError) {
            console.error(`Claude API error for ${userId} (schedule): kind=${error.kind} status=${error.statusCode}`);
            await (0, validators_1.recordUsage)(userId, {
                status: "failed",
                latencyMs,
                error: `claude_${error.kind}`,
            });
            if (error.kind === "authentication") {
                throw new https_1.HttpsError("failed-precondition", "AI service authentication failed. Please contact support.");
            }
            if (error.kind === "rate_limit" || error.kind === "overloaded") {
                throw new https_1.HttpsError("unavailable", "AI service is temporarily busy. Please try again in a moment.");
            }
            throw new https_1.HttpsError("internal", "AI service encountered an error. Please try again.");
        }
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        console.error(`Unexpected error for ${userId} (schedule):`, error);
        await (0, validators_1.recordUsage)(userId, {
            status: "failed",
            latencyMs,
            error: error instanceof Error ? error.message : "unknown",
        }).catch(() => { });
        throw new https_1.HttpsError("internal", "Something went wrong. Please try again.");
    }
});
//# sourceMappingURL=processScheduleCommand.js.map