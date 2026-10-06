/**
 * alexaJwt — zero-dependency HS256 JWT sign/verify for Alexa access tokens.
 *
 * B-3b auth decision (a): alexaToken issues a self-signed short-lived JWT
 * (uid + client claims) instead of a Firebase custom token. Amazon replays the
 * access token on every directive, and custom tokens cannot be verified
 * server-side with admin.auth().verifyIdToken (they are meant for client-side
 * exchange, which Amazon never performs). The Smart Home handler verifies this
 * JWT directly — no Admin-SDK coupling.
 *
 * Signed with node:crypto HMAC-SHA256 (no new dependency). The refresh-token
 * rotation in alexaToken is unchanged and format-independent, so already-linked
 * accounts re-issue in the new format on their next refresh.
 */
import { createHmac, timingSafeEqual } from "crypto";

function b64urlJson(obj: unknown): string {
  return Buffer.from(JSON.stringify(obj)).toString("base64url");
}

export interface AlexaJwtClaims {
  uid: string;
  iat: number;
  exp: number;
  iss: string;
  [k: string]: unknown;
}

/** Sign an HS256 JWT. `nowSec` is injectable for deterministic tests. */
export function signAlexaJwt(
  payload: Record<string, unknown>,
  secret: string,
  expiresInSec = 3600,
  nowSec: number = Math.floor(Date.now() / 1000)
): string {
  const header = { alg: "HS256", typ: "JWT" };
  const body = {
    ...payload,
    iat: nowSec,
    exp: nowSec + expiresInSec,
    iss: "lumina-alexa",
  };
  const signingInput = `${b64urlJson(header)}.${b64urlJson(body)}`;
  const sig = createHmac("sha256", secret).update(signingInput).digest("base64url");
  return `${signingInput}.${sig}`;
}

/**
 * Verify an HS256 JWT signed by [signAlexaJwt]. Returns the claims, or null if
 * the token is malformed, tamper/signature-invalid, expired, or lacks a uid.
 * Signature comparison is constant-time.
 */
export function verifyAlexaJwt(
  token: unknown,
  secret: string,
  nowSec: number = Math.floor(Date.now() / 1000)
): AlexaJwtClaims | null {
  if (typeof token !== "string") return null;
  const parts = token.split(".");
  if (parts.length !== 3) return null;
  const [h, p, sig] = parts;

  const expected = createHmac("sha256", secret).update(`${h}.${p}`).digest("base64url");
  const sigBuf = Buffer.from(sig);
  const expBuf = Buffer.from(expected);
  if (sigBuf.length !== expBuf.length || !timingSafeEqual(sigBuf, expBuf)) {
    return null;
  }

  let claims: AlexaJwtClaims;
  try {
    claims = JSON.parse(Buffer.from(p, "base64url").toString("utf8"));
  } catch (_e) {
    return null;
  }
  if (typeof claims.uid !== "string" || claims.uid.length === 0) return null;
  if (typeof claims.exp === "number" && nowSec >= claims.exp) return null;
  return claims;
}
