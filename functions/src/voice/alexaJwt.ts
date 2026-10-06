/**
 * alexaJwt — the Alexa access token: an HS256 JWT that alexaToken issues and
 * alexaSmartHome verifies. Nothing else accepts it and it accepts nothing else.
 *
 * WHY A SELF-ISSUED JWT (plan §3). Amazon replays the access token on every
 * directive. A Firebase custom token cannot be verified server-side, and a
 * Firebase ID token is a full app-session credential that would also open
 * Firestore as the user. This token is bound to one audience (the Alexa smart
 * home endpoint) and is useless anywhere else.
 *
 * B-3c HARDENING over B-3b:
 *   1. ONE dedicated key, ALEXA_JWT_SECRET, read from the function environment.
 *      No fallback to ALEXA_CLIENT_SECRET (a value Amazon also holds). Missing
 *      or shorter than MIN_SECRET_BYTES → readAlexaJwtSecret() returns null and
 *      the callers refuse to issue or accept tokens.
 *   2. Every token carries iss, aud, iat and exp. Verification requires all of
 *      them, pins the header (HS256/JWT), and refuses a lifetime longer than
 *      ACCESS_TOKEN_TTL_SEC — a token without exp is rejected, never accepted
 *      forever.
 *   3. The result says WHY a token failed: "expired" (well-signed, past exp)
 *      or "invalid" (anything else), so the handler can return the documented
 *      Alexa error type for each.
 *
 * NO USER ID IN THE TOKEN. A JWT payload is only base64, and Amazon holds the
 * token, so the claims carry no uid. `lid` (link id) is the SHA-256 of the
 * refresh token the access token was minted from — random, meaningless
 * outside our database. alexaSmartHome reads that refresh record on every
 * directive to find the uid, so revoking a link stops its outstanding access
 * tokens at once.
 */
import { createHmac, timingSafeEqual } from "crypto";

export const ALEXA_ISSUER = "lumina-alexa";
export const ALEXA_AUDIENCE = "alexa-smart-home";
/** Short-lived access token: one hour. */
export const ACCESS_TOKEN_TTL_SEC = 3600;
/** Allowed clock skew for iat, in seconds. */
const CLOCK_SKEW_SEC = 60;
/** Minimum key length (bytes, UTF-8). */
export const MIN_SECRET_BYTES = 32;

export interface AlexaAccessClaims {
  lid: string;
  iss: string;
  aud: string;
  iat: number;
  exp: number;
}

export type AlexaTokenCheck =
  | { ok: true; claims: AlexaAccessClaims }
  | { ok: false; reason: "expired" | "invalid" };

/**
 * The signing key from the function environment, or null when it is missing
 * or too short. Never falls back to any other variable.
 */
export function readAlexaJwtSecret(
  env: Record<string, string | undefined> = process.env
): string | null {
  const s = env.ALEXA_JWT_SECRET;
  if (typeof s !== "string") return null;
  return Buffer.byteLength(s, "utf8") >= MIN_SECRET_BYTES ? s : null;
}

function usableSecret(secret: unknown): secret is string {
  return typeof secret === "string" && Buffer.byteLength(secret, "utf8") >= MIN_SECRET_BYTES;
}

function b64urlJson(obj: unknown): string {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

function hmac(secret: string, input: string): string {
  return createHmac("sha256", secret).update(input).digest("base64url");
}

/** Sign an access token. Throws when the secret is unusable. */
export function signAlexaAccessToken(
  subject: { lid: string },
  secret: string,
  nowSec: number = Math.floor(Date.now() / 1000)
): string {
  if (!usableSecret(secret)) throw new Error("ALEXA_JWT_SECRET missing or too short");
  if (!subject.lid) throw new Error("lid is required");
  const header = { alg: "HS256", typ: "JWT" };
  const claims: AlexaAccessClaims = {
    lid: subject.lid,
    iss: ALEXA_ISSUER,
    aud: ALEXA_AUDIENCE,
    iat: nowSec,
    exp: nowSec + ACCESS_TOKEN_TTL_SEC,
  };
  const signingInput = `${b64urlJson(header)}.${b64urlJson(claims)}`;
  return `${signingInput}.${hmac(secret, signingInput)}`;
}

function parseJson(part: string): Record<string, unknown> | null {
  try {
    const v = JSON.parse(Buffer.from(part, "base64url").toString("utf8"));
    return v && typeof v === "object" && !Array.isArray(v) ? v : null;
  } catch (_e) {
    return null;
  }
}

/**
 * Verify an access token. Signature first (constant time), then the header,
 * then every claim. Only a token whose signature, header and other claims are
 * all good but whose exp has passed is reported as "expired".
 */
export function verifyAlexaAccessToken(
  token: unknown,
  secret: string | null,
  nowSec: number = Math.floor(Date.now() / 1000)
): AlexaTokenCheck {
  const invalid: AlexaTokenCheck = { ok: false, reason: "invalid" };
  if (!usableSecret(secret)) return invalid;
  if (typeof token !== "string") return invalid;
  const parts = token.split(".");
  if (parts.length !== 3) return invalid;
  const [h, p, sig] = parts;

  const expected = Buffer.from(hmac(secret, `${h}.${p}`));
  const given = Buffer.from(sig);
  if (given.length !== expected.length || !timingSafeEqual(given, expected)) return invalid;

  const header = parseJson(h);
  if (!header || header.alg !== "HS256" || header.typ !== "JWT") return invalid;

  const c = parseJson(p);
  if (!c) return invalid;
  if (c.iss !== ALEXA_ISSUER || c.aud !== ALEXA_AUDIENCE) return invalid;
  if (typeof c.lid !== "string" || c.lid.length === 0) return invalid;
  if (typeof c.iat !== "number" || typeof c.exp !== "number") return invalid;
  if (!Number.isFinite(c.iat) || !Number.isFinite(c.exp)) return invalid;
  if (c.iat > nowSec + CLOCK_SKEW_SEC) return invalid;
  if (c.exp <= c.iat || c.exp - c.iat > ACCESS_TOKEN_TTL_SEC) return invalid;
  if (nowSec >= c.exp) return { ok: false, reason: "expired" };

  return { ok: true, claims: c as unknown as AlexaAccessClaims };
}

/**
 * Opaque, stable endpoint id for one of the user's controllers or scenes.
 * Alexa needs a stable endpointId per device; the raw controller doc id (often
 * MAC-derived) or scene doc id must never reach Amazon, so the id is a keyed
 * hash of (uid, kind, id). Keyed, not a plain hash: a MAC-shaped id is cheap
 * to brute-force from an unkeyed hash. Domain-separated from token signing.
 * Rotating ALEXA_JWT_SECRET therefore also re-keys endpoint ids (devices are
 * re-discovered as new) — see the plan's rotation note.
 */
export function opaqueEndpointKey(
  secret: string,
  uid: string,
  kind: "ctl" | "scn",
  id: string
): string {
  if (!usableSecret(secret)) throw new Error("ALEXA_JWT_SECRET missing or too short");
  return createHmac("sha256", secret)
    .update(`lumina-alexa/endpoint-id/v1\n${uid}\n${kind}\n${id}`)
    .digest("base64url")
    .slice(0, 24);
}
