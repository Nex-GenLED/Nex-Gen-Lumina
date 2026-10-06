/**
 * oauthClientAuth — client authentication at the Alexa token endpoint.
 *
 * Amazon calls alexaToken with the skill's client id and secret in ONE of two
 * forms, chosen in the developer console (Build > Account Linking > Security
 * Provider Information > "Your Client Authentication Scheme"; SMAPI
 * `accessTokenScheme`):
 *   HTTP_BASIC                Authorization: Basic base64(id ":" secret), each
 *                             half form-urlencoded first (RFC 6749 §2.3.1)
 *   REQUEST_BODY_CREDENTIALS  client_id and client_secret as body fields
 * https://developer.amazon.com/en-US/docs/alexa/smapi/account-linking-schemas.html
 *
 * B-3b read the body only, so the console's recommended scheme got a 401.
 * Both forms are accepted here. Missing and wrong credentials are refused
 * identically (same status, body and headers), and the comparison is constant
 * time. An unconfigured server refuses everything instead of skipping the
 * check, which is what B-3b did when the expected values were unset.
 */
import { createHmac, randomBytes, timingSafeEqual } from "crypto";

export interface ClientCredentials {
  clientId: string;
  clientSecret: string;
}

export type CredentialParse = { ok: true; creds: ClientCredentials } | { ok: false };

const NO_CREDENTIALS: CredentialParse = { ok: false };

/** application/x-www-form-urlencoded decoding of one Basic half. */
function formDecode(s: string): string {
  return decodeURIComponent(s.replace(/\+/g, " "));
}

function fromBasicHeader(authorization: string): ClientCredentials | null {
  const m = /^basic[ \t]+([A-Za-z0-9+/]+={0,2})[ \t]*$/i.exec(authorization);
  if (!m) return null;
  const decoded = Buffer.from(m[1], "base64").toString("utf8");
  const colon = decoded.indexOf(":");
  if (colon < 0) return null;
  try {
    return {
      clientId: formDecode(decoded.slice(0, colon)),
      clientSecret: formDecode(decoded.slice(colon + 1)),
    };
  } catch (_e) {
    return null; // malformed percent-encoding
  }
}

/**
 * Read client credentials from the Authorization header and/or the body.
 * Header present: it must be well-formed Basic, and any body client_id /
 * client_secret must agree with it. No header: the body must carry both.
 */
export function parseClientCredentials(authorization: unknown, body: unknown): CredentialParse {
  const b = (body && typeof body === "object" ? body : {}) as Record<string, unknown>;
  const bodyId = typeof b.client_id === "string" ? b.client_id : undefined;
  const bodySecret = typeof b.client_secret === "string" ? b.client_secret : undefined;

  if (authorization !== undefined && authorization !== null && authorization !== "") {
    if (typeof authorization !== "string") return NO_CREDENTIALS;
    const header = fromBasicHeader(authorization);
    if (!header) return NO_CREDENTIALS;
    if (bodyId !== undefined && bodyId !== header.clientId) return NO_CREDENTIALS;
    if (bodySecret !== undefined && bodySecret !== header.clientSecret) return NO_CREDENTIALS;
    return { ok: true, creds: header };
  }

  if (bodyId !== undefined && bodySecret !== undefined) {
    return { ok: true, creds: { clientId: bodyId, clientSecret: bodySecret } };
  }
  return NO_CREDENTIALS;
}

// Per-instance key: equal-length digests make timingSafeEqual safe to call on
// inputs of any length, and nothing about the secret leaks through timing.
const COMPARE_KEY = randomBytes(32);

function digest(s: string): Buffer {
  return createHmac("sha256", COMPARE_KEY).update(s, "utf8").digest();
}

/**
 * true / false for configured servers; "unconfigured" when the expected id or
 * secret is missing (callers answer server_error — never skip the check).
 * Both halves are always compared, so a wrong id costs the same as a wrong
 * secret.
 */
export function credentialsMatch(
  given: ClientCredentials,
  expected: { clientId?: string | null; clientSecret?: string | null }
): boolean | "unconfigured" {
  if (!expected.clientId || !expected.clientSecret) return "unconfigured";
  const idOk = timingSafeEqual(digest(given.clientId), digest(expected.clientId));
  const secretOk = timingSafeEqual(digest(given.clientSecret), digest(expected.clientSecret));
  return idOk && secretOk;
}

/** Minimal response surface (Express-compatible). */
export interface TokenResponse {
  set(field: string, value: string): unknown;
  status(code: number): { json(body: unknown): unknown };
}

/** RFC 6749 §5.1: token responses must not be cached. */
export function setNoStore(res: TokenResponse): void {
  res.set("Cache-Control", "no-store");
  res.set("Pragma", "no-cache");
}

/** The one refusal for missing AND wrong credentials (RFC 6749 §5.2). */
export function sendInvalidClient(res: TokenResponse): void {
  setNoStore(res);
  res.set("WWW-Authenticate", 'Basic realm="lumina-alexa"');
  res.status(401).json({ error: "invalid_client" });
}
