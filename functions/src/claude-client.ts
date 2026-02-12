/**
 * Claude API Client Wrapper
 *
 * Wraps the Anthropic SDK with:
 * - Exponential-backoff retry logic (up to 3 attempts)
 * - Timeout handling
 * - Structured JSON response parsing
 * - Error classification for the caller
 */

import Anthropic from "@anthropic-ai/sdk";

// ---------------------------------------------------------------------------
// Types
// ---------------------------------------------------------------------------

export interface ClaudeRequestOptions {
  systemPrompt: string;
  messages: Array<{ role: "user" | "assistant"; content: string }>;
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

export type ClaudeErrorKind =
  | "authentication"
  | "rate_limit"
  | "overloaded"
  | "invalid_request"
  | "timeout"
  | "unknown";

export class ClaudeClientError extends Error {
  constructor(
    message: string,
    public readonly kind: ClaudeErrorKind,
    public readonly statusCode?: number,
    public readonly retryable: boolean = false
  ) {
    super(message);
    this.name = "ClaudeClientError";
  }
}

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

let clientInstance: Anthropic | null = null;

function getClient(apiKey: string): Anthropic {
  if (!clientInstance) {
    clientInstance = new Anthropic({ apiKey });
  }
  return clientInstance;
}

/**
 * Sleep helper for retry delays.
 */
function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

/**
 * Classify an error from the Anthropic SDK into a known kind.
 */
function classifyError(error: unknown): {
  kind: ClaudeErrorKind;
  retryable: boolean;
  statusCode?: number;
} {
  if (error instanceof Anthropic.APIError) {
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
export async function sendMessage(
  apiKey: string,
  options: ClaudeRequestOptions
): Promise<ClaudeResponse> {
  const {
    systemPrompt,
    messages,
    maxTokens = DEFAULT_MAX_TOKENS,
    timeoutMs = DEFAULT_TIMEOUT_MS,
  } = options;

  const client = getClient(apiKey);
  let lastError: unknown;

  for (let attempt = 0; attempt < MAX_RETRIES; attempt++) {
    try {
      const response = await client.messages.create(
        {
          model: MODEL,
          max_tokens: maxTokens,
          system: systemPrompt,
          messages: messages.map((m) => ({
            role: m.role,
            content: m.content,
          })),
        },
        {
          timeout: timeoutMs,
        }
      );

      // Extract text from content blocks
      const text = response.content
        .filter((block): block is Anthropic.TextBlock => block.type === "text")
        .map((block) => block.text)
        .join("");

      // Attempt JSON parse
      let json: Record<string, unknown> | null = null;
      try {
        json = JSON.parse(text) as Record<string, unknown>;
      } catch {
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
    } catch (error) {
      lastError = error;
      const classified = classifyError(error);

      console.error(
        `Claude API attempt ${attempt + 1}/${MAX_RETRIES} failed:`,
        `kind=${classified.kind}`,
        `retryable=${classified.retryable}`,
        `status=${classified.statusCode ?? "N/A"}`,
        error instanceof Error ? error.message : error
      );

      // Don't retry non-retryable errors
      if (!classified.retryable) {
        throw new ClaudeClientError(
          error instanceof Error ? error.message : "Claude API error",
          classified.kind,
          classified.statusCode,
          false
        );
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
  throw new ClaudeClientError(
    `Claude API failed after ${MAX_RETRIES} attempts: ${lastError instanceof Error ? lastError.message : "unknown error"}`,
    classified.kind,
    classified.statusCode,
    false
  );
}
