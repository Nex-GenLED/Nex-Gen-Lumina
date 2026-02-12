/**
 * Input Validation & Rate Limiting for processLuminaCommand
 *
 * - Schema validation for the request payload
 * - Per-user rate limiting (20 requests/minute) via Firestore
 * - Input sanitization to prevent prompt injection
 */
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
export declare class ValidationError extends Error {
    readonly field: string;
    constructor(message: string, field: string);
}
/**
 * Strip characters and patterns that could be used for prompt injection.
 * Preserves natural language while removing control sequences.
 */
export declare function sanitizeText(input: string): string;
/**
 * Validate and sanitize the full request payload.
 * Returns a cleaned copy of the input.
 */
export declare function validateInput(data: unknown): LuminaCommandInput;
/**
 * Check and enforce per-user rate limits using Firestore.
 *
 * @returns The number of requests made in the current window.
 * @throws Error if the rate limit is exceeded.
 */
export declare function checkRateLimit(userId: string): Promise<number>;
/**
 * Record a request for rate-limiting and analytics.
 */
export declare function recordUsage(userId: string, data: {
    status: "success" | "failed";
    latencyMs: number;
    inputTokens?: number;
    outputTokens?: number;
    model?: string;
    error?: string;
}): Promise<void>;
export declare class RateLimitError extends Error {
    constructor(message: string);
}
