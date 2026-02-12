/**
 * Claude API Client Wrapper
 *
 * Wraps the Anthropic SDK with:
 * - Exponential-backoff retry logic (up to 3 attempts)
 * - Timeout handling
 * - Structured JSON response parsing
 * - Error classification for the caller
 */
export interface ClaudeRequestOptions {
    systemPrompt: string;
    messages: Array<{
        role: "user" | "assistant";
        content: string;
    }>;
    /** Max tokens for the response. Default 1024. */
    maxTokens?: number;
    /** Request timeout in ms. Default 30 000. */
    timeoutMs?: number;
}
export interface ClaudeResponse {
    /** The raw text content returned by Claude. */
    text: string;
    /** Parsed JSON if the response is valid JSON, otherwise null. */
    json: Record<string, unknown> | null;
    /** Token usage from the API. */
    usage: {
        inputTokens: number;
        outputTokens: number;
    };
    /** Which model was actually used. */
    model: string;
}
export type ClaudeErrorKind = "authentication" | "rate_limit" | "overloaded" | "invalid_request" | "timeout" | "unknown";
export declare class ClaudeClientError extends Error {
    readonly kind: ClaudeErrorKind;
    readonly statusCode?: number | undefined;
    readonly retryable: boolean;
    constructor(message: string, kind: ClaudeErrorKind, statusCode?: number | undefined, retryable?: boolean);
}
/**
 * Send a request to Claude with automatic retry on transient failures.
 */
export declare function sendMessage(apiKey: string, options: ClaudeRequestOptions): Promise<ClaudeResponse>;
