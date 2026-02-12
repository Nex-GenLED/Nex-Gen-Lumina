"use strict";
/**
 * Claude API Client Wrapper
 *
 * Wraps the Anthropic SDK with:
 * - Exponential-backoff retry logic (up to 3 attempts)
 * - Timeout handling
 * - Structured JSON response parsing
 * - Error classification for the caller
 */
var __importDefault = (this && this.__importDefault) || function (mod) {
    return (mod && mod.__esModule) ? mod : { "default": mod };
};
Object.defineProperty(exports, "__esModule", { value: true });
exports.ClaudeClientError = void 0;
exports.sendMessage = sendMessage;
const sdk_1 = __importDefault(require("@anthropic-ai/sdk"));
class ClaudeClientError extends Error {
    kind;
    statusCode;
    retryable;
    constructor(message, kind, statusCode, retryable = false) {
        super(message);
        this.kind = kind;
        this.statusCode = statusCode;
        this.retryable = retryable;
        this.name = "ClaudeClientError";
    }
}
exports.ClaudeClientError = ClaudeClientError;
// ---------------------------------------------------------------------------
// Constants
// ---------------------------------------------------------------------------
const MODEL = "claude-sonnet-4-5-20250929";
const MAX_RETRIES = 3;
const BASE_DELAY_MS = 1000; // 1s, 2s, 4s exponential backoff
const DEFAULT_MAX_TOKENS = 1024;
const DEFAULT_TIMEOUT_MS = 30_000;
// ---------------------------------------------------------------------------
// Client
// ---------------------------------------------------------------------------
let clientInstance = null;
function getClient(apiKey) {
    if (!clientInstance) {
        clientInstance = new sdk_1.default({ apiKey });
    }
    return clientInstance;
}
/**
 * Sleep helper for retry delays.
 */
function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}
/**
 * Classify an error from the Anthropic SDK into a known kind.
 */
function classifyError(error) {
    if (error instanceof sdk_1.default.APIError) {
        const status = error.status;
        if (status === 401) {
            return { kind: "authentication", retryable: false, statusCode: status };
        }
        if (status === 429) {
            return { kind: "rate_limit", retryable: true, statusCode: status };
        }
        if (status === 529 || status === 503) {
            return { kind: "overloaded", retryable: true, statusCode: status };
        }
        if (status === 400) {
            return { kind: "invalid_request", retryable: false, statusCode: status };
        }
        // 5xx errors are generally retryable
        if (status >= 500) {
            return { kind: "overloaded", retryable: true, statusCode: status };
        }
        return { kind: "unknown", retryable: false, statusCode: status };
    }
    // Network / timeout errors
    if (error instanceof Error) {
        const msg = error.message.toLowerCase();
        if (msg.includes("timeout") || msg.includes("timed out") || msg.includes("aborted")) {
            return { kind: "timeout", retryable: true };
        }
        if (msg.includes("econnrefused") || msg.includes("enotfound") || msg.includes("fetch failed")) {
            return { kind: "overloaded", retryable: true };
        }
    }
    return { kind: "unknown", retryable: false };
}
/**
 * Send a request to Claude with automatic retry on transient failures.
 */
async function sendMessage(apiKey, options) {
    const { systemPrompt, messages, maxTokens = DEFAULT_MAX_TOKENS, timeoutMs = DEFAULT_TIMEOUT_MS, } = options;
    const client = getClient(apiKey);
    let lastError;
    for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
        try {
            const response = await client.messages.create({
                model: MODEL,
                max_tokens: maxTokens,
                system: systemPrompt,
                messages: messages.map((m) => ({
                    role: m.role,
                    content: m.content,
                })),
            }, {
                timeout: timeoutMs,
            });
            // Extract text from content blocks
            const text = response.content
                .filter((block) => block.type === "text")
                .map((block) => block.text)
                .join("");
            // Attempt JSON parse
            let json = null;
            try {
                json = JSON.parse(text);
            }
            catch {
                // Response wasn't valid JSON — caller will handle
            }
            return {
                text,
                json,
                usage: {
                    inputTokens: response.usage.input_tokens,
                    outputTokens: response.usage.output_tokens,
                },
                model: response.model,
            };
        }
        catch (error) {
            lastError = error;
            const classified = classifyError(error);
            console.error(`Claude API attempt ${attempt + 1}/${MAX_RETRIES} failed:`, `kind=${classified.kind}`, `retryable=${classified.retryable}`, `status=${classified.statusCode ?? "N/A"}`, error instanceof Error ? error.message : error);
            // Don't retry non-retryable errors
            if (!classified.retryable) {
                throw new ClaudeClientError(error instanceof Error ? error.message : "Claude API error", classified.kind, classified.statusCode, false);
            }
            // Don't sleep after the last attempt
            if (attempt < MAX_RETRIES - 1) {
                const delay = BASE_DELAY_MS * Math.pow(2, attempt);
                const jitter = Math.random() * delay * 0.1; // 10% jitter
                console.log(`Retrying in ${Math.round(delay + jitter)}ms...`);
                await sleep(delay + jitter);
            }
        }
    }
    // All retries exhausted
    const classified = classifyError(lastError);
    throw new ClaudeClientError(`Claude API failed after ${MAX_RETRIES} attempts: ${lastError instanceof Error ? lastError.message : "unknown error"}`, classified.kind, classified.statusCode, false);
}
//# sourceMappingURL=claude-client.js.map