/**
 * Input Validation & Rate Limiting for processLuminaCommand
 *
 * - Schema validation for the request payload
 * - Per-user rate limiting (20 requests/minute) via Firestore
 * - Input sanitization to prevent prompt injection
 */

import * as admin from "firebase-admin";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface LuminaCommandInput {
  transcribedText: string;
  conversationHistory: ConversationTurn[];
  currentLightingState: {
    zones: Array<{
      id: string;
      color: number[];
      brightness: number;
      effect: string;
    }>;
  };
  userFavorites: string[];
  deviceConfig: {
    totalPixels: number;
    zones: Array<{
      id: string;
      startPixel: number;
      endPixel: number;
    }>;
  };
}

export interface ConversationTurn {
  role: "user" | "assistant";
  content: string;
}

export class ValidationError extends Error {
  constructor(
    message: string,
    public readonly field: string
  ) {
    super(message);
    this.name = "ValidationError";
  }
}

// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------

const MAX_TRANSCRIBED_TEXT_LENGTH = 1000;
const MAX_CONVERSATION_TURNS = 10;
const MAX_CONVERSATION_TURN_LENGTH = 2000;
const MAX_ZONES = 20;
const MAX_FAVORITES = 50;
const MAX_FAVORITE_NAME_LENGTH = 100;
const MAX_TOTAL_PIXELS = 10000;

const RATE_LIMIT_WINDOW_MS = 60 * 1000; // 1 minute
const RATE_LIMIT_MAX_REQUESTS = 20;

// ---------------------------------------------------------------------------
// Input Sanitization
// ---------------------------------------------------------------------------

/**
 * Strip characters and patterns that could be used for prompt injection.
 * Preserves natural language while removing control sequences.
 */
export function sanitizeText(input: string): string {
  return input
    // Remove null bytes
    .replace(/\0/g, "")
    // Remove common prompt-injection delimiters
    .replace(/```/g, "")
    .replace(/<\/?system>/gi, "")
    .replace(/<\/?user>/gi, "")
    .replace(/<\/?assistant>/gi, "")
    .replace(/<\/?human>/gi, "")
    // Collapse excessive whitespace
    .replace(/\s{3,}/g, "  ")
    .trim();
}

// ---------------------------------------------------------------------------
// Schema Validation
// ---------------------------------------------------------------------------

function isRGBArray(arr: unknown): arr is number[] {
  if (!Array.isArray(arr)) return false;
  if (arr.length < 3 || arr.length > 4) return false; // RGB or RGBW
  return arr.every(
    (v) => typeof v === "number" && Number.isInteger(v) && v >= 0 && v <= 255
  );
}

function validateZoneState(zone: unknown, index: number): void {
  if (!zone || typeof zone !== "object") {
    throw new ValidationError(
      `Zone at index ${index} must be an object`,
      `currentLightingState.zones[${index}]`
    );
  }

  const z = zone as Record<string, unknown>;

  if (typeof z.id !== "string" || z.id.length === 0) {
    throw new ValidationError(
      `Zone at index ${index} must have a non-empty string id`,
      `currentLightingState.zones[${index}].id`
    );
  }

  if (!isRGBArray(z.color)) {
    throw new ValidationError(
      `Zone "${z.id}" color must be an RGB [R,G,B] or RGBW [R,G,B,W] array with values 0-255`,
      `currentLightingState.zones[${index}].color`
    );
  }

  if (
    typeof z.brightness !== "number" ||
    z.brightness < 0 ||
    z.brightness > 255
  ) {
    throw new ValidationError(
      `Zone "${z.id}" brightness must be a number 0-255`,
      `currentLightingState.zones[${index}].brightness`
    );
  }

  if (typeof z.effect !== "string") {
    throw new ValidationError(
      `Zone "${z.id}" effect must be a string`,
      `currentLightingState.zones[${index}].effect`
    );
  }
}

function validateZoneConfig(zone: unknown, index: number): void {
  if (!zone || typeof zone !== "object") {
    throw new ValidationError(
      `Device zone at index ${index} must be an object`,
      `deviceConfig.zones[${index}]`
    );
  }

  const z = zone as Record<string, unknown>;

  if (typeof z.id !== "string" || z.id.length === 0) {
    throw new ValidationError(
      `Device zone at index ${index} must have a non-empty string id`,
      `deviceConfig.zones[${index}].id`
    );
  }

  if (typeof z.startPixel !== "number" || z.startPixel < 0) {
    throw new ValidationError(
      `Zone "${z.id}" startPixel must be a non-negative number`,
      `deviceConfig.zones[${index}].startPixel`
    );
  }

  if (typeof z.endPixel !== "number" || z.endPixel < z.startPixel) {
    throw new ValidationError(
      `Zone "${z.id}" endPixel must be >= startPixel`,
      `deviceConfig.zones[${index}].endPixel`
    );
  }
}

/**
 * Validate and sanitize the full request payload.
 * Returns a cleaned copy of the input.
 */
export function validateInput(data: unknown): LuminaCommandInput {
  if (!data || typeof data !== "object") {
    throw new ValidationError("Request body must be an object", "root");
  }

  const d = data as Record<string, unknown>;

  // --- transcribedText ---
  if (typeof d.transcribedText !== "string" || d.transcribedText.trim().length === 0) {
    throw new ValidationError(
      "transcribedText must be a non-empty string",
      "transcribedText"
    );
  }

  let transcribedText = sanitizeText(d.transcribedText as string);
  if (transcribedText.length > MAX_TRANSCRIBED_TEXT_LENGTH) {
    transcribedText = transcribedText.substring(0, MAX_TRANSCRIBED_TEXT_LENGTH);
  }

  // --- conversationHistory ---
  let conversationHistory: ConversationTurn[] = [];
  if (d.conversationHistory !== undefined) {
    if (!Array.isArray(d.conversationHistory)) {
      throw new ValidationError(
        "conversationHistory must be an array",
        "conversationHistory"
      );
    }

    // Take only the last N turns
    const rawHistory = (d.conversationHistory as unknown[]).slice(
      -MAX_CONVERSATION_TURNS
    );

    conversationHistory = rawHistory.map((turn, i) => {
      if (!turn || typeof turn !== "object") {
        throw new ValidationError(
          `Conversation turn at index ${i} must be an object`,
          `conversationHistory[${i}]`
        );
      }

      const t = turn as Record<string, unknown>;

      if (t.role !== "user" && t.role !== "assistant") {
        throw new ValidationError(
          `Conversation turn role must be "user" or "assistant"`,
          `conversationHistory[${i}].role`
        );
      }

      if (typeof t.content !== "string") {
        throw new ValidationError(
          `Conversation turn content must be a string`,
          `conversationHistory[${i}].content`
        );
      }

      let content = sanitizeText(t.content);
      if (content.length > MAX_CONVERSATION_TURN_LENGTH) {
        content = content.substring(0, MAX_CONVERSATION_TURN_LENGTH);
      }

      return { role: t.role as "user" | "assistant", content };
    });
  }

  // --- currentLightingState ---
  if (
    !d.currentLightingState ||
    typeof d.currentLightingState !== "object"
  ) {
    throw new ValidationError(
      "currentLightingState must be an object",
      "currentLightingState"
    );
  }

  const stateObj = d.currentLightingState as Record<string, unknown>;
  if (!Array.isArray(stateObj.zones)) {
    throw new ValidationError(
      "currentLightingState.zones must be an array",
      "currentLightingState.zones"
    );
  }

  if (stateObj.zones.length > MAX_ZONES) {
    throw new ValidationError(
      `Too many zones (max ${MAX_ZONES})`,
      "currentLightingState.zones"
    );
  }

  (stateObj.zones as unknown[]).forEach(validateZoneState);

  // --- userFavorites ---
  let userFavorites: string[] = [];
  if (d.userFavorites !== undefined) {
    if (!Array.isArray(d.userFavorites)) {
      throw new ValidationError(
        "userFavorites must be an array of strings",
        "userFavorites"
      );
    }

    userFavorites = (d.userFavorites as unknown[])
      .slice(0, MAX_FAVORITES)
      .map((f, i) => {
        if (typeof f !== "string") {
          throw new ValidationError(
            `Favorite at index ${i} must be a string`,
            `userFavorites[${i}]`
          );
        }
        return sanitizeText(f).substring(0, MAX_FAVORITE_NAME_LENGTH);
      });
  }

  // --- deviceConfig ---
  if (!d.deviceConfig || typeof d.deviceConfig !== "object") {
    throw new ValidationError(
      "deviceConfig must be an object",
      "deviceConfig"
    );
  }

  const dcObj = d.deviceConfig as Record<string, unknown>;

  if (
    typeof dcObj.totalPixels !== "number" ||
    dcObj.totalPixels < 1 ||
    dcObj.totalPixels > MAX_TOTAL_PIXELS
  ) {
    throw new ValidationError(
      `totalPixels must be a number between 1 and ${MAX_TOTAL_PIXELS}`,
      "deviceConfig.totalPixels"
    );
  }

  if (!Array.isArray(dcObj.zones)) {
    throw new ValidationError(
      "deviceConfig.zones must be an array",
      "deviceConfig.zones"
    );
  }

  if (dcObj.zones.length > MAX_ZONES) {
    throw new ValidationError(
      `Too many device zones (max ${MAX_ZONES})`,
      "deviceConfig.zones"
    );
  }

  (dcObj.zones as unknown[]).forEach(validateZoneConfig);

  return {
    transcribedText,
    conversationHistory,
    currentLightingState: stateObj as LuminaCommandInput["currentLightingState"],
    userFavorites,
    deviceConfig: dcObj as LuminaCommandInput["deviceConfig"],
  };
}

// ---------------------------------------------------------------------------
// Rate Limiting
// ---------------------------------------------------------------------------

/**
 * Check and enforce per-user rate limits using Firestore.
 *
 * @returns The number of requests made in the current window.
 * @throws Error if the rate limit is exceeded.
 */
export async function checkRateLimit(userId: string): Promise<number> {
  const db = admin.firestore();
  const windowStart = new Date(Date.now() - RATE_LIMIT_WINDOW_MS);

  const usageRef = db
    .collection("users")
    .doc(userId)
    .collection("lumina_usage");

  const recentRequests = await usageRef
    .where("timestamp", ">", admin.firestore.Timestamp.fromDate(windowStart))
    .get();

  const count = recentRequests.size;

  if (count >= RATE_LIMIT_MAX_REQUESTS) {
    throw new RateLimitError(
      `Rate limit exceeded: ${count}/${RATE_LIMIT_MAX_REQUESTS} requests per minute. Please wait a moment.`
    );
  }

  return count;
}

/**
 * Record a request for rate-limiting and analytics.
 */
export async function recordUsage(
  userId: string,
  data: {
    status: "success" | "failed";
    latencyMs: number;
    inputTokens?: number;
    outputTokens?: number;
    model?: string;
    error?: string;
  }
): Promise<void> {
  const db = admin.firestore();

  await db
    .collection("users")
    .doc(userId)
    .collection("lumina_usage")
    .add({
      timestamp: admin.firestore.FieldValue.serverTimestamp(),
      ...data,
    });
}

export class RateLimitError extends Error {
  constructor(message: string) {
    super(message);
    this.name = "RateLimitError";
  }
}
