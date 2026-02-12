"use strict";
/**
 * processLuminaCommand — Firebase Cloud Function
 *
 * Receives a voice-transcribed command from the Flutter app, sends it to
 * Claude with full lighting context, and returns structured WLED commands.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */
Object.defineProperty(exports, "__esModule", { value: true });
exports.processLuminaCommand = void 0;
const https_1 = require("firebase-functions/v2/https");
const params_1 = require("firebase-functions/params");
const validators_1 = require("./validators");
const system_prompt_1 = require("./system-prompt");
const claude_client_1 = require("./claude-client");
// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------
const anthropicApiKey = (0, params_1.defineString)("ANTHROPIC_API_KEY");
// ---------------------------------------------------------------------------
// Response shape validation
// ---------------------------------------------------------------------------
const VALID_INTENTS = [
    "lighting_command",
    "navigation",
    "question_answer",
    "guided_creation",
];
/**
 * Validate and normalize the JSON response from Claude.
 * Applies sensible defaults for missing optional fields.
 */
function validateLuminaResponse(json) {
    if (!json) {
        throw new Error("Claude did not return valid JSON");
    }
    const intent = json.intent;
    if (!VALID_INTENTS.includes(intent)) {
        throw new Error(`Invalid intent: "${intent}"`);
    }
    const responseText = typeof json.responseText === "string"
        ? json.responseText
        : "Here you go!";
    // Validate commands array if present
    let commands = null;
    if (Array.isArray(json.commands)) {
        commands = json.commands.map((cmd) => ({
            zone: typeof cmd.zone === "string" ? cmd.zone : "all",
            effect: typeof cmd.effect === "number" ? cmd.effect : 0,
            colors: Array.isArray(cmd.colors)
                ? cmd.colors
                : [[255, 255, 255]],
            brightness: typeof cmd.brightness === "number"
                ? Math.max(0, Math.min(255, cmd.brightness))
                : 200,
            speed: typeof cmd.speed === "number"
                ? Math.max(0, Math.min(255, cmd.speed))
                : undefined,
            intensity: typeof cmd.intensity === "number"
                ? Math.max(0, Math.min(255, cmd.intensity))
                : undefined,
        }));
    }
    // Validate previewColors
    let previewColors = null;
    if (Array.isArray(json.previewColors)) {
        previewColors = json.previewColors
            .slice(0, 9)
            .filter((c) => Array.isArray(c) && c.length >= 3 && c.every((v) => typeof v === "number"));
        // Pad to 9 if Claude returned fewer
        while (previewColors.length < 9 && previewColors.length > 0) {
            previewColors.push(previewColors[previewColors.length - 1]);
        }
        if (previewColors.length === 0) {
            previewColors = null;
        }
    }
    // Validate clarificationOptions
    let clarificationOptions = null;
    if (Array.isArray(json.clarificationOptions)) {
        clarificationOptions = json.clarificationOptions
            .filter((o) => typeof o === "string" && o.length > 0)
            .slice(0, 3);
        if (clarificationOptions.length === 0) {
            clarificationOptions = null;
        }
    }
    const navigationTarget = typeof json.navigationTarget === "string"
        ? json.navigationTarget
        : null;
    const saveAsFavorite = typeof json.saveAsFavorite === "string" ? json.saveAsFavorite : null;
    const confidence = typeof json.confidence === "number"
        ? Math.max(0, Math.min(1, json.confidence))
        : 0.8;
    return {
        intent,
        responseText,
        commands,
        previewColors,
        clarificationOptions,
        navigationTarget,
        saveAsFavorite,
        confidence,
    };
}
// ---------------------------------------------------------------------------
// Cloud Function
// ---------------------------------------------------------------------------
exports.processLuminaCommand = (0, https_1.onCall)({
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
        const input = (0, validators_1.validateInput)(request.data);
        // ------ Build System Prompt ------
        const systemPrompt = (0, system_prompt_1.buildSystemPrompt)(input.currentLightingState, input.deviceConfig, input.userFavorites);
        // ------ Build Messages ------
        const messages = [];
        // Add conversation history for context
        for (const turn of input.conversationHistory) {
            messages.push({ role: turn.role, content: turn.content });
        }
        // Add the current user message
        messages.push({ role: "user", content: input.transcribedText });
        // ------ Call Claude ------
        const claudeResponse = await (0, claude_client_1.sendMessage)(apiKey, {
            systemPrompt,
            messages,
            maxTokens: 1024,
            timeoutMs: 25_000, // Leave headroom within the 60s function timeout
        });
        // ------ Parse & Validate Response ------
        const luminaResponse = validateLuminaResponse(claudeResponse.json);
        // ------ Log Usage ------
        const latencyMs = Date.now() - startTime;
        await (0, validators_1.recordUsage)(userId, {
            status: "success",
            latencyMs,
            inputTokens: claudeResponse.usage.inputTokens,
            outputTokens: claudeResponse.usage.outputTokens,
            model: claudeResponse.model,
        });
        // Warn if approaching rate limit
        if (requestCount >= 15) {
            console.warn(`User ${userId} approaching Lumina rate limit: ${requestCount + 1}/20`);
        }
        return luminaResponse;
    }
    catch (error) {
        const latencyMs = Date.now() - startTime;
        // ------ Handle known error types ------
        if (error instanceof validators_1.ValidationError) {
            console.warn(`Validation error for ${userId}: ${error.message} [${error.field}]`);
            throw new https_1.HttpsError("invalid-argument", error.message);
        }
        if (error instanceof validators_1.RateLimitError) {
            console.warn(`Rate limit hit for ${userId}`);
            await (0, validators_1.recordUsage)(userId, {
                status: "failed",
                latencyMs,
                error: "rate_limit",
            });
            throw new https_1.HttpsError("resource-exhausted", error.message);
        }
        if (error instanceof claude_client_1.ClaudeClientError) {
            console.error(`Claude API error for ${userId}: kind=${error.kind} status=${error.statusCode}`);
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
        // Re-throw existing HttpsErrors
        if (error instanceof https_1.HttpsError) {
            throw error;
        }
        // ------ Unknown errors ------
        console.error(`Unexpected error for ${userId}:`, error);
        await (0, validators_1.recordUsage)(userId, {
            status: "failed",
            latencyMs,
            error: error instanceof Error ? error.message : "unknown",
        }).catch(() => { }); // Don't let logging failures mask the real error
        throw new https_1.HttpsError("internal", "Something went wrong. Please try again.");
    }
});
//# sourceMappingURL=processLuminaCommand.js.map