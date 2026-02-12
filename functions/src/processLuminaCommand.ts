/**
 * processLuminaCommand — Firebase Cloud Function
 *
 * Receives a voice-transcribed command from the Flutter app, sends it to
 * Claude with full lighting context, and returns structured WLED commands.
 *
 * Security: authenticated, rate-limited, input-validated, usage-logged.
 */

import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import {
  validateInput,
  checkRateLimit,
  recordUsage,
  ValidationError,
  RateLimitError,
} from "./validators";
import { buildSystemPrompt } from "./system-prompt";
import { sendMessage, ClaudeClientError } from "./claude-client";

// ---------------------------------------------------------------------------
// Config
// ---------------------------------------------------------------------------

const anthropicApiKey = defineString("ANTHROPIC_API_KEY");

// ---------------------------------------------------------------------------
// Response shape validation
// ---------------------------------------------------------------------------

const VALID_INTENTS = [
  "lighting_command",
  "navigation",
  "question_answer",
  "guided_creation",
] as const;

interface LuminaResponse {
  intent: string;
  responseText: string;
  commands: Array<{
    zone: string;
    effect: number;
    colors: number[][];
    brightness: number;
    speed?: number;
    intensity?: number;
  }> | null;
  previewColors: number[][] | null;
  clarificationOptions: string[] | null;
  navigationTarget: string | null;
  saveAsFavorite: string | null;
  confidence: number;
}

/**
 * Validate and normalize the JSON response from Claude.
 * Applies sensible defaults for missing optional fields.
 */
function validateLuminaResponse(
  json: Record<string, unknown> | null
): LuminaResponse {
  if (!json) {
    throw new Error("Claude did not return valid JSON");
  }

  const intent = json.intent as string;
  if (!VALID_INTENTS.includes(intent as (typeof VALID_INTENTS)[number])) {
    throw new Error(`Invalid intent: "${intent}"`);
  }

  const responseText =
    typeof json.responseText === "string"
      ? json.responseText
      : "Here you go!";

  // Validate commands array if present
  let commands: LuminaResponse["commands"] = null;
  if (Array.isArray(json.commands)) {
    commands = (json.commands as Array<Record<string, unknown>>).map((cmd) => ({
      zone: typeof cmd.zone === "string" ? cmd.zone : "all",
      effect: typeof cmd.effect === "number" ? cmd.effect : 0,
      colors: Array.isArray(cmd.colors)
        ? (cmd.colors as number[][])
        : [[255, 255, 255]],
      brightness:
        typeof cmd.brightness === "number"
          ? Math.max(0, Math.min(255, cmd.brightness))
          : 200,
      speed:
        typeof cmd.speed === "number"
          ? Math.max(0, Math.min(255, cmd.speed))
          : undefined,
      intensity:
        typeof cmd.intensity === "number"
          ? Math.max(0, Math.min(255, cmd.intensity))
          : undefined,
    }));
  }

  // Validate previewColors
  let previewColors: number[][] | null = null;
  if (Array.isArray(json.previewColors)) {
    previewColors = (json.previewColors as unknown[])
      .slice(0, 9)
      .filter(
        (c): c is number[] =>
          Array.isArray(c) && c.length >= 3 && c.every((v) => typeof v === "number")
      );

    // Pad to 9 if Claude returned fewer
    while (previewColors.length < 9 && previewColors.length > 0) {
      previewColors.push(previewColors[previewColors.length - 1]);
    }

    if (previewColors.length === 0) {
      previewColors = null;
    }
  }

  // Validate clarificationOptions
  let clarificationOptions: string[] | null = null;
  if (Array.isArray(json.clarificationOptions)) {
    clarificationOptions = (json.clarificationOptions as unknown[])
      .filter((o): o is string => typeof o === "string" && o.length > 0)
      .slice(0, 3);

    if (clarificationOptions.length === 0) {
      clarificationOptions = null;
    }
  }

  const navigationTarget =
    typeof json.navigationTarget === "string"
      ? json.navigationTarget
      : null;

  const saveAsFavorite =
    typeof json.saveAsFavorite === "string" ? json.saveAsFavorite : null;

  const confidence =
    typeof json.confidence === "number"
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

export const processLuminaCommand = onCall(
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
      const input = validateInput(request.data);

      // ------ Build System Prompt ------
      const systemPrompt = buildSystemPrompt(
        input.currentLightingState,
        input.deviceConfig,
        input.userFavorites
      );

      // ------ Build Messages ------
      const messages: Array<{ role: "user" | "assistant"; content: string }> =
        [];

      // Add conversation history for context
      for (const turn of input.conversationHistory) {
        messages.push({ role: turn.role, content: turn.content });
      }

      // Add the current user message
      messages.push({ role: "user", content: input.transcribedText });

      // ------ Call Claude ------
      const claudeResponse = await sendMessage(apiKey, {
        systemPrompt,
        messages,
        maxTokens: 1024,
        timeoutMs: 25_000, // Leave headroom within the 60s function timeout
      });

      // ------ Parse & Validate Response ------
      const luminaResponse = validateLuminaResponse(claudeResponse.json);

      // ------ Log Usage ------
      const latencyMs = Date.now() - startTime;
      await recordUsage(userId, {
        status: "success",
        latencyMs,
        inputTokens: claudeResponse.usage.inputTokens,
        outputTokens: claudeResponse.usage.outputTokens,
        model: claudeResponse.model,
      });

      // Warn if approaching rate limit
      if (requestCount >= 15) {
        console.warn(
          `User ${userId} approaching Lumina rate limit: ${requestCount + 1}/20`
        );
      }

      return luminaResponse;
    } catch (error) {
      const latencyMs = Date.now() - startTime;

      // ------ Handle known error types ------

      if (error instanceof ValidationError) {
        console.warn(`Validation error for ${userId}: ${error.message} [${error.field}]`);
        throw new HttpsError("invalid-argument", error.message);
      }

      if (error instanceof RateLimitError) {
        console.warn(`Rate limit hit for ${userId}`);
        await recordUsage(userId, {
          status: "failed",
          latencyMs,
          error: "rate_limit",
        });
        throw new HttpsError("resource-exhausted", error.message);
      }

      if (error instanceof ClaudeClientError) {
        console.error(
          `Claude API error for ${userId}: kind=${error.kind} status=${error.statusCode}`
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

      // Re-throw existing HttpsErrors
      if (error instanceof HttpsError) {
        throw error;
      }

      // ------ Unknown errors ------
      console.error(`Unexpected error for ${userId}:`, error);
      await recordUsage(userId, {
        status: "failed",
        latencyMs,
        error: error instanceof Error ? error.message : "unknown",
      }).catch(() => {}); // Don't let logging failures mask the real error

      throw new HttpsError(
        "internal",
        "Something went wrong. Please try again."
      );
    }
  }
);
