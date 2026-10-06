/**
 * alexaLink — the Alexa account link after the login page: the token endpoint
 * (alexaToken), the refresh-token records, revocation on unlink, and the sweep
 * that clears a stuck "Pending" state. index.js only wires these up.
 *
 * TOKENS (plan §3-§4)
 *   access token   HS256 JWT, 1 hour (alexaJwt.ts), carries `lid`.
 *   refresh token  32 random bytes, opaque. Stored ONLY as its SHA-256 in
 *                  oauth_refresh_tokens/{lid} with
 *                    { userId, provider: "alexa", iss, aud (the client id it
 *                      was issued to), active, createdAt, lastUsedAt,
 *                      expiresAt }.
 *                  expiresAt slides REFRESH_TOKEN_TTL_MS forward on each use;
 *                  a record without one, past it, revoked, or issued to
 *                  another client is refused. B-3b stored the raw token as
 *                  the doc id with no expiry (none exist in production).
 *
 * LINK STATE — users/{uid}/integrations/alexa (rules: clients may write only
 * linkInitiated/initiatedAt). A successful code exchange writes
 * isLinked/linkedAt and DELETES linkInitiated/initiatedAt, so "Pending" ends
 * the moment a link succeeds.
 *
 * UNLINK — the app's Unlink deletes that doc; onVoiceIntegrationDeleted then
 * revokes every refresh token for the user (also on account purge). The next
 * directive fails the per-directive link check at once, and Amazon's next
 * refresh gets invalid_grant.
 *
 * KILL SWITCH — a NEW link (code exchange) needs config/voice_control to allow
 * the uid. Refresh is deliberately NOT gated: flipping the switch must never
 * break existing links; every directive is gated instead (alexaSmartHome).
 */
import * as admin from "firebase-admin";
import { createHash, randomBytes } from "crypto";
import {
  credentialsMatch,
  parseClientCredentials,
  sendInvalidClient,
  setNoStore,
  TokenResponse,
} from "./oauthClientAuth";
import { ACCESS_TOKEN_TTL_SEC, ALEXA_ISSUER, signAlexaAccessToken } from "./alexaJwt";
import { readVoiceControlEnabled } from "./intentCore";

type Firestore = admin.firestore.Firestore;
type Data = admin.firestore.DocumentData;

export const OAUTH_CODES = "oauth_codes";
export const ALEXA_REFRESH_TOKENS = "oauth_refresh_tokens";
export const GOOGLE_REFRESH_TOKENS = "google_oauth_refresh_tokens";
/** Longer-lived refresh token: 90 days, sliding on each use. */
export const REFRESH_TOKEN_TTL_MS = 90 * 24 * 60 * 60 * 1000;
/** A "Pending" link intent older than this is stale. */
export const PENDING_LINK_MAX_AGE_MS = 24 * 60 * 60 * 1000;

const CODE_PATTERN = /^[A-Za-z0-9_-]{20,128}$/;

export function hashRefreshToken(token: string): string {
  return createHash("sha256").update(token, "utf8").digest("hex");
}

function millis(v: unknown): number | null {
  if (v && typeof (v as { toMillis?: unknown }).toMillis === "function") {
    const n = (v as { toMillis(): number }).toMillis();
    return Number.isFinite(n) ? n : null;
  }
  return null;
}

/**
 * The uid a refresh-token record authorises, or null. Checked on EVERY use:
 * active, provider, issuer, audience (when the caller knows the client id),
 * a non-empty uid, and an expiry that exists and has not passed.
 */
export function validRefreshRecord(
  data: Data | undefined,
  nowMs: number,
  clientId?: string
): string | null {
  if (!data) return null;
  if (data.active !== true) return null;
  if (data.provider !== "alexa" || data.iss !== ALEXA_ISSUER) return null;
  if (typeof data.aud !== "string" || data.aud.length === 0) return null;
  if (clientId !== undefined && data.aud !== clientId) return null;
  if (typeof data.userId !== "string" || data.userId.length === 0) return null;
  const exp = millis(data.expiresAt);
  if (exp === null || nowMs >= exp) return null;
  return data.userId;
}

/**
 * Directive-time link check: the integration doc says linked AND the refresh
 * record the access token came from is still valid for this uid.
 */
export function linkIsActive(
  integration: Data | undefined,
  refresh: Data | undefined,
  uid: string,
  nowMs: number
): boolean {
  if (!integration || integration.isLinked !== true) return false;
  return validRefreshRecord(refresh, nowMs) === uid;
}

function integrationRef(db: Firestore, uid: string) {
  return db.collection("users").doc(uid).collection("integrations").doc("alexa");
}

export interface TokenEndpointConfig {
  clientId: string | null | undefined;
  clientSecret: string | null | undefined;
  /** readAlexaJwtSecret() — null means refuse to issue anything. */
  jwtSecret: string | null;
  nowMs?: number;
}

interface TokenRequest {
  method?: string;
  headers?: Record<string, unknown>;
  body?: unknown;
}

function oauthError(res: TokenResponse, status: number, error: string): void {
  res.status(status).json({ error });
}

/** The whole alexaToken endpoint. */
export async function handleAlexaTokenRequest(
  req: TokenRequest,
  res: TokenResponse,
  db: Firestore,
  cfg: TokenEndpointConfig
): Promise<void> {
  setNoStore(res);
  if (req.method !== "POST") {
    oauthError(res, 405, "invalid_request");
    return;
  }
  const body = (req.body && typeof req.body === "object" ? req.body : {}) as Record<string, unknown>;

  const parsed = parseClientCredentials(req.headers?.authorization, body);
  const expected = { clientId: cfg.clientId, clientSecret: cfg.clientSecret };
  const match = parsed.ok ? credentialsMatch(parsed.creds, expected) : credentialsMatch(
    { clientId: "", clientSecret: "" }, expected);
  if (match === "unconfigured") {
    console.error("alexaToken: ALEXA_CLIENT_ID / ALEXA_CLIENT_SECRET not configured — refusing");
    oauthError(res, 500, "server_error");
    return;
  }
  if (!parsed.ok || match !== true) {
    sendInvalidClient(res);
    return;
  }
  if (!cfg.jwtSecret) {
    console.error("alexaToken: ALEXA_JWT_SECRET missing or too short — refusing to issue tokens");
    oauthError(res, 500, "server_error");
    return;
  }

  const nowMs = cfg.nowMs ?? Date.now();
  const clientId = parsed.creds.clientId;
  try {
    if (body.grant_type === "authorization_code") {
      await authorizationCodeGrant(body, res, db, clientId, cfg.jwtSecret, nowMs);
    } else if (body.grant_type === "refresh_token") {
      await refreshTokenGrant(body, res, db, clientId, cfg.jwtSecret, nowMs);
    } else {
      oauthError(res, 400, "unsupported_grant_type");
    }
  } catch (err) {
    console.error("alexaToken: grant failed", err);
    oauthError(res, 500, "server_error");
  }
}

async function authorizationCodeGrant(
  body: Record<string, unknown>,
  res: TokenResponse,
  db: Firestore,
  clientId: string,
  jwtSecret: string,
  nowMs: number
): Promise<void> {
  const code = body.code;
  if (typeof code !== "string" || !CODE_PATTERN.test(code)) {
    oauthError(res, 400, "invalid_grant");
    return;
  }
  const redirectUri = typeof body.redirect_uri === "string" ? body.redirect_uri : null;
  const codeRef = db.collection(OAUTH_CODES).doc(code);

  // One-time use, atomically: two racing exchanges cannot both succeed.
  const uid = await db.runTransaction(async (tx) => {
    const snap = await tx.get(codeRef);
    const d = snap.data();
    if (!snap.exists || !d) return null;
    if (d.used === true) return null;
    const exp = millis(d.expiresAt);
    if (exp === null || nowMs >= exp) return null;
    if (typeof d.userId !== "string" || d.userId.length === 0) return null;
    // RFC 6749 §4.1.3: a redirect_uri sent here must match the one the code
    // was issued for. Not required when absent: codes only ever go to
    // allowlisted Amazon URLs and redeeming one needs our client secret, so a
    // client that omits it must not break linking.
    if (typeof d.redirectUri === "string" && redirectUri !== null && d.redirectUri !== redirectUri) {
      return null;
    }
    tx.update(codeRef, { used: true, usedAt: admin.firestore.FieldValue.serverTimestamp() });
    return d.userId as string;
  });
  if (!uid) {
    oauthError(res, 400, "invalid_grant");
    return;
  }

  if (!(await readVoiceControlEnabled(db, uid))) {
    console.warn("alexaToken: voice control not enabled for this account — link refused");
    oauthError(res, 400, "invalid_grant");
    return;
  }

  const refreshToken = randomBytes(32).toString("base64url");
  const lid = hashRefreshToken(refreshToken);
  const ts = admin.firestore.FieldValue.serverTimestamp();
  const batch = db.batch();
  batch.set(db.collection(ALEXA_REFRESH_TOKENS).doc(lid), {
    userId: uid,
    provider: "alexa",
    iss: ALEXA_ISSUER,
    aud: clientId,
    active: true,
    createdAt: ts,
    lastUsedAt: ts,
    expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + REFRESH_TOKEN_TTL_MS),
  });
  batch.set(
    integrationRef(db, uid),
    {
      isLinked: true,
      linkedAt: ts,
      linkInitiated: admin.firestore.FieldValue.delete(),
      initiatedAt: admin.firestore.FieldValue.delete(),
    },
    { merge: true }
  );
  await batch.commit();

  res.status(200).json({
    access_token: signAlexaAccessToken({ lid }, jwtSecret, Math.floor(nowMs / 1000)),
    token_type: "Bearer",
    expires_in: ACCESS_TOKEN_TTL_SEC,
    refresh_token: refreshToken,
  });
}

async function refreshTokenGrant(
  body: Record<string, unknown>,
  res: TokenResponse,
  db: Firestore,
  clientId: string,
  jwtSecret: string,
  nowMs: number
): Promise<void> {
  const token = body.refresh_token;
  if (typeof token !== "string" || token.length === 0) {
    oauthError(res, 400, "invalid_grant");
    return;
  }
  const lid = hashRefreshToken(token);
  const ref = db.collection(ALEXA_REFRESH_TOKENS).doc(lid);
  const snap = await ref.get();
  const uid = validRefreshRecord(snap.exists ? snap.data() : undefined, nowMs, clientId);
  if (!uid) {
    oauthError(res, 400, "invalid_grant");
    return;
  }
  await ref.update({
    lastUsedAt: admin.firestore.FieldValue.serverTimestamp(),
    expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + REFRESH_TOKEN_TTL_MS),
  });
  res.status(200).json({
    access_token: signAlexaAccessToken({ lid }, jwtSecret, Math.floor(nowMs / 1000)),
    token_type: "Bearer",
    expires_in: ACCESS_TOKEN_TTL_SEC,
    refresh_token: token,
  });
}

/**
 * Revoke every refresh token a user holds for one provider. Called by the
 * onVoiceIntegrationDeleted trigger (app Unlink, account purge). Returns how
 * many records changed.
 */
export async function revokeVoiceLink(
  db: Firestore,
  uid: string,
  provider: string
): Promise<number> {
  const coll =
    provider === "alexa" ? ALEXA_REFRESH_TOKENS
    : provider === "google_home" ? GOOGLE_REFRESH_TOKENS
    : null;
  if (!coll || !uid) return 0;
  const snap = await db.collection(coll).where("userId", "==", uid).get();
  const live = snap.docs.filter((d) => d.get("active") !== false);
  for (let i = 0; i < live.length; i += 450) {
    const batch = db.batch();
    for (const d of live.slice(i, i + 450)) {
      batch.update(d.ref, {
        active: false,
        revokedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
    }
    await batch.commit();
  }
  return live.length;
}

export type PendingAction = "keep" | "delete" | "strip";

/**
 * What the sweep does with one integration doc:
 *   no linkInitiated            keep
 *   linked + linkInitiated      strip the flag (the link already succeeded)
 *   pending younger than 24 h   keep (the user may be mid-flow)
 *   pending older / undated     delete when the doc holds only the two intent
 *                               fields, otherwise strip them (e.g. a Google
 *                               DISCONNECT left isLinked:false beside them)
 */
export function classifyPendingIntent(data: Data | undefined, nowMs: number): PendingAction {
  if (!data || data.linkInitiated !== true) return "keep";
  if (data.isLinked === true) return "strip";
  const at = millis(data.initiatedAt);
  if (at !== null && nowMs - at < PENDING_LINK_MAX_AGE_MS) return "keep";
  const others = Object.keys(data).filter((k) => k !== "linkInitiated" && k !== "initiatedAt");
  return others.length === 0 ? "delete" : "strip";
}

const PROVIDERS = new Set(["alexa", "google_home"]);

/**
 * Clear stuck "Pending" link intents (users/{uid}/integrations/{alexa|
 * google_home}). The app sets linkInitiated before opening the assistant app
 * and nothing ever cleared it, so an abandoned or failed flow showed Pending
 * forever — including the bench account's. Daily; touches only those docs.
 */
export async function sweepStalePendingLinks(
  db: Firestore,
  nowMs: number = Date.now()
): Promise<{ scanned: number; deleted: number; stripped: number }> {
  const snap = await db.collectionGroup("integrations").get();
  let deleted = 0;
  let stripped = 0;
  for (const doc of snap.docs) {
    const userRef = doc.ref.parent.parent;
    if (!userRef || userRef.parent.id !== "users" || userRef.parent.parent !== null) continue;
    if (!PROVIDERS.has(doc.id)) continue;
    const action = classifyPendingIntent(doc.data(), nowMs);
    if (action === "delete") {
      await doc.ref.delete();
      deleted++;
    } else if (action === "strip") {
      await doc.ref.update({
        linkInitiated: admin.firestore.FieldValue.delete(),
        initiatedAt: admin.firestore.FieldValue.delete(),
      });
      stripped++;
    }
  }
  return { scanned: snap.size, deleted, stripped };
}
