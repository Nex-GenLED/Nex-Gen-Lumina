/**
 * alexaSmartHome — Alexa Smart Home directive fulfillment, behind the AWS
 * Lambda shim (Smart Home skills only accept a Lambda ARN as endpoint).
 *
 * EVERY REQUEST, IN ORDER
 *   1. Signing key present (ALEXA_JWT_SECRET) — else INTERNAL_ERROR.
 *   2. Access token (alexaJwt.verifyAlexaAccessToken):
 *        expired → EXPIRED_AUTHORIZATION_CREDENTIAL
 *        anything else wrong → INVALID_AUTHORIZATION_CREDENTIAL
 *      Amazon documents these as "the access token has expired" and "the
 *      access token isn't valid for the customer's account"; it does not
 *      document what Alexa does next, so nothing here relies on a refresh:
 *      https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-errorresponse.html
 *   3. The token carries no uid, only `lid`: read oauth_refresh_tokens/{lid}
 *      for the uid, then ONE batched read of users/{uid}/integrations/alexa and
 *      config/voice_control. Link not active (unlinked, revoked, expired) →
 *      INVALID_AUTHORIZATION_CREDENTIAL.
 *   4. Kill switch (config/voice_control; missing doc = OFF, empty allowlist)
 *      not allowing this uid → INSUFFICIENT_PERMISSIONS ("Alexa doesn't have
 *      permissions to perform the specified action"), for Discover too — it
 *      is one of the five error types Discover accepts:
 *      https://developer.amazon.com/en-US/docs/alexa/device-apis/alexa-discovery.html
 *      Nothing is read or written past this point for a denied account.
 *   5. The directive itself.
 *
 * WHAT AMAZON RECEIVES — and nothing else (the privacy contract, fix 3).
 *   Discover.Response, per endpoint, exactly the fields the Discovery
 *   interface requires: endpointId, manufacturerName, description,
 *   friendlyName, displayCategories, capabilities.
 *     endpointId    "lumina-main" (primary controller) | "ctl-<k>" | "scn-<k>",
 *                   <k> = keyed hash (alexaJwt.opaqueEndpointKey). Never a
 *                   uid, controller doc id, MAC, IP or scene doc id.
 *     friendlyName  the controller's or scene's own name as the user typed it
 *                   in the app (the API needs a spoken name); an unnamed
 *                   primary is "House Lights", others "Lights N". The profile's
 *                   propertyName (often a street address) is never used.
 *     manufacturerName / description  fixed strings.
 *   No cookie, no additionalAttributes, no connections.
 *   Responses: header (fresh messageId, Amazon's correlationToken), the
 *   endpointId Amazon sent (only if it has one of our shapes), and the
 *   powerState / brightness properties. ErrorResponse messages are fixed
 *   strings (Amazon uses them for logging only).
 *
 * COMMANDS go through intentCore.executeIntent: the user's own command queue
 * (users/{uid}/commands), the app's document shape, the same relay-eligibility
 * rule as the app, and executeWledCommand's fail-fast trigger. Nothing here
 * talks to a controller, reads or writes Game Day data, or writes the bridge
 * registry.
 */

import * as admin from "firebase-admin";
import { randomUUID } from "crypto";
import { loadControllersOldestFirst } from "./deviceResolver";
import {
  awaitOutcome,
  executeIntent,
  resolveActivatableScenes,
  voiceControlEnabledFromData,
  VoiceErrorCode,
  VoiceIntent,
} from "./intentCore";
import { opaqueEndpointKey, verifyAlexaAccessToken } from "./alexaJwt";
import { ALEXA_REFRESH_TOKENS, linkIsActive, validRefreshRecord } from "./alexaLink";

type Firestore = admin.firestore.Firestore;
// Alexa directive/response payloads are dynamically shaped; treat as opaque.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

const SOURCE = "voice_alexa" as const;
export const MAIN_ENDPOINT_ID = "lumina-main";
const MANUFACTURER = "Nex-Gen Lumina";
const DESCRIPTION = "Nex-Gen Lumina permanent lighting";
const OUR_ENDPOINT_ID = /^(lumina-main|ctl-[A-Za-z0-9_-]{24}|scn-[A-Za-z0-9_-]{24})$/;

function nowIso(): string {
  return new Date().toISOString();
}

function header(namespace: string, name: string, correlationToken?: string): Json {
  const h: Json = { namespace, name, messageId: randomUUID(), payloadVersion: "3" };
  if (typeof correlationToken === "string") h.correlationToken = correlationToken;
  return h;
}

/** Echo an endpointId back only when it is one we issued. */
function safeEndpointId(id: unknown): string | undefined {
  return typeof id === "string" && OUR_ENDPOINT_ID.test(id) ? id : undefined;
}

export function errorResponse(
  endpointId: string | undefined,
  correlationToken: string | undefined,
  type: string,
  message: string
): Json {
  const id = safeEndpointId(endpointId);
  return {
    event: {
      header: header("Alexa", "ErrorResponse", correlationToken),
      ...(id ? { endpoint: { endpointId: id } } : {}),
      payload: { type, message },
    },
  };
}

// ---------------------------------------------------------------------------
// Endpoints — the only device data that leaves for Amazon.
// ---------------------------------------------------------------------------
function alexaIface(): Json {
  return { type: "AlexaInterface", interface: "Alexa", version: "3" };
}
function propIface(iface: string, prop: string): Json {
  return {
    type: "AlexaInterface",
    interface: iface,
    version: "3",
    properties: { supported: [{ name: prop }], retrievable: true, proactivelyReported: false },
  };
}

function lightEndpoint(endpointId: string, friendlyName: string): Json {
  return {
    endpointId,
    manufacturerName: MANUFACTURER,
    description: DESCRIPTION,
    friendlyName,
    displayCategories: ["LIGHT"],
    capabilities: [
      alexaIface(),
      propIface("Alexa.PowerController", "powerState"),
      propIface("Alexa.BrightnessController", "brightness"),
    ],
  };
}

function sceneEndpoint(endpointId: string, friendlyName: string): Json {
  return {
    endpointId,
    manufacturerName: MANUFACTURER,
    description: DESCRIPTION,
    friendlyName,
    displayCategories: ["SCENE_TRIGGER"],
    capabilities: [
      alexaIface(),
      {
        type: "AlexaInterface",
        interface: "Alexa.SceneController",
        version: "3",
        supportsDeactivation: false,
      },
    ],
  };
}

async function handleDiscovery(uid: string, db: Firestore, secret: string): Promise<Json> {
  const controllers = await loadControllersOldestFirst(db, uid);
  const endpoints: Json[] = controllers.map((c, i) =>
    i === 0
      ? lightEndpoint(MAIN_ENDPOINT_ID, c.name ?? "House Lights")
      : lightEndpoint(`ctl-${opaqueEndpointKey(secret, uid, "ctl", c.id)}`, c.name ?? `Lights ${i + 1}`)
  );
  for (const s of await resolveActivatableScenes(db, uid)) {
    endpoints.push(sceneEndpoint(`scn-${opaqueEndpointKey(secret, uid, "scn", s.sceneId)}`, s.name));
  }
  return {
    event: {
      header: header("Alexa.Discovery", "Discover.Response"),
      payload: { endpoints },
    },
  };
}

type Target =
  | { kind: "controller"; controllerId: string }
  | { kind: "scene"; sceneId: string };

/** endpointId → the user's own controller or scene, re-derived server-side. */
async function resolveEndpoint(
  db: Firestore,
  uid: string,
  endpointId: string | undefined,
  secret: string
): Promise<Target | null> {
  if (!endpointId) return null;
  if (endpointId === MAIN_ENDPOINT_ID) {
    const controllers = await loadControllersOldestFirst(db, uid);
    return controllers.length > 0 ? { kind: "controller", controllerId: controllers[0].id } : null;
  }
  if (/^ctl-[A-Za-z0-9_-]{24}$/.test(endpointId)) {
    const key = endpointId.slice(4);
    const controllers = await loadControllersOldestFirst(db, uid);
    const hit = controllers.find((c) => opaqueEndpointKey(secret, uid, "ctl", c.id) === key);
    return hit ? { kind: "controller", controllerId: hit.id } : null;
  }
  if (/^scn-[A-Za-z0-9_-]{24}$/.test(endpointId)) {
    const key = endpointId.slice(4);
    const scenes = await resolveActivatableScenes(db, uid);
    const hit = scenes.find((s) => opaqueEndpointKey(secret, uid, "scn", s.sceneId) === key);
    return hit ? { kind: "scene", sceneId: hit.sceneId } : null;
  }
  return null;
}

function prop(namespace: string, name: string, value: Json, ts: string): Json {
  return { namespace, name, value, timeOfSample: ts, uncertaintyInMilliseconds: 500 };
}

interface Mapping {
  intent: VoiceIntent;
  context: Json[];
}

function mapControl(namespace: string, name: string, payload: Json): Mapping | null {
  const ts = nowIso();
  if (namespace === "Alexa.PowerController" && (name === "TurnOn" || name === "TurnOff")) {
    const on = name === "TurnOn";
    return {
      intent: { kind: on ? "POWER_ON" : "POWER_OFF" },
      context: [prop("Alexa.PowerController", "powerState", on ? "ON" : "OFF", ts)],
    };
  }
  if (namespace === "Alexa.BrightnessController" && name === "SetBrightness") {
    const level = Number(payload?.brightness);
    if (!Number.isFinite(level)) return null;
    return {
      intent: { kind: "SET_BRIGHTNESS", level },
      context: [prop("Alexa.BrightnessController", "brightness", level, ts)],
    };
  }
  return null;
}

function voiceErrorToAlexa(code: VoiceErrorCode): { type: string; message: string } {
  switch (code) {
    case "not_enabled":
      return { type: "INSUFFICIENT_PERMISSIONS", message: "Voice control is not enabled for this account." };
    case "no_bridge":
      return { type: "ENDPOINT_UNREACHABLE", message: "No Lumina Bridge is paired to this account." };
    case "no_target":
      return { type: "ENDPOINT_UNREACHABLE", message: "No controller is available." };
    case "unknown_controller":
    case "unknown_scene":
      return { type: "NO_SUCH_ENDPOINT", message: "Unknown endpoint." };
    case "cross_uid":
      return { type: "INVALID_AUTHORIZATION_CREDENTIAL", message: "Endpoint does not belong to this account." };
    case "unsupported_intent":
    default:
      return { type: "INVALID_DIRECTIVE", message: "Unsupported directive." };
  }
}

function tokenOf(namespace: string, directive: Json): unknown {
  if (namespace === "Alexa.Discovery") return directive.payload?.scope?.token;
  if (namespace === "Alexa.Authorization") return directive.payload?.grantee?.token;
  return directive.endpoint?.scope?.token;
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
export async function handleAlexaDirective(
  body: Json,
  secret: string | null,
  db: Firestore = admin.firestore(),
  outcomeWaitMs = 4000,
  nowMs: number = Date.now()
): Promise<Json> {
  const directive = body?.directive ?? {};
  const h = directive.header ?? {};
  const namespace: string = typeof h.namespace === "string" ? h.namespace : "";
  const name: string = typeof h.name === "string" ? h.name : "";
  const correlationToken: string | undefined =
    typeof h.correlationToken === "string" ? h.correlationToken : undefined;
  const endpointId: string | undefined = safeEndpointId(directive.endpoint?.endpointId);

  if (!secret) {
    console.error("alexaSmartHome: ALEXA_JWT_SECRET missing or too short — refusing");
    return errorResponse(endpointId, correlationToken, "INTERNAL_ERROR", "Service not configured.");
  }

  const check = verifyAlexaAccessToken(tokenOf(namespace, directive), secret, Math.floor(nowMs / 1000));
  if (!check.ok) {
    return check.reason === "expired"
      ? errorResponse(endpointId, correlationToken, "EXPIRED_AUTHORIZATION_CREDENTIAL", "Access token expired.")
      : errorResponse(endpointId, correlationToken, "INVALID_AUTHORIZATION_CREDENTIAL", "Access token invalid.");
  }
  // The token names only the link; the link names the user.
  const refresh = await db.collection(ALEXA_REFRESH_TOKENS).doc(check.claims.lid).get();
  const uid = validRefreshRecord(refresh.data(), nowMs);
  if (!uid) {
    return errorResponse(endpointId, correlationToken, "INVALID_AUTHORIZATION_CREDENTIAL", "Account link is not active.");
  }
  const [integration, config] = await db.getAll(
    db.collection("users").doc(uid).collection("integrations").doc("alexa"),
    db.collection("config").doc("voice_control")
  );
  if (!linkIsActive(integration.data(), refresh.data(), uid, nowMs)) {
    return errorResponse(endpointId, correlationToken, "INVALID_AUTHORIZATION_CREDENTIAL", "Account link is not active.");
  }

  if (!voiceControlEnabledFromData(config.data(), uid)) {
    if (namespace === "Alexa.Authorization") {
      return {
        event: {
          header: header("Alexa.Authorization", "ErrorResponse"),
          payload: { type: "ACCEPT_GRANT_FAILED", message: "Voice control is not enabled for this account." },
        },
      };
    }
    return errorResponse(endpointId, correlationToken, "INSUFFICIENT_PERMISSIONS",
      "Voice control is not enabled for this account.");
  }

  if (namespace === "Alexa.Authorization" && name === "AcceptGrant") {
    // No proactive events are sent, so the grant code is not stored.
    return { event: { header: header("Alexa.Authorization", "AcceptGrant.Response"), payload: {} } };
  }

  if (namespace === "Alexa.Discovery" && name === "Discover") {
    return handleDiscovery(uid, db, secret);
  }

  const target = await resolveEndpoint(db, uid, endpointId, secret);
  if (!target) {
    return errorResponse(endpointId, correlationToken, "NO_SUCH_ENDPOINT", "Unknown endpoint.");
  }

  if (namespace === "Alexa" && name === "ReportState") {
    return reportState(uid, endpointId as string, correlationToken, target, db);
  }

  let intent: VoiceIntent;
  let context: Json[] = [];
  let controllerId: string | null;
  if (namespace === "Alexa.SceneController" && name === "Activate") {
    if (target.kind !== "scene") {
      return errorResponse(endpointId, correlationToken, "INVALID_DIRECTIVE", "Unsupported directive.");
    }
    intent = { kind: "ACTIVATE_SCENE", sceneId: target.sceneId };
    controllerId = null; // a scene applies to every controller
  } else {
    const mapping = target.kind === "controller" ? mapControl(namespace, name, directive.payload ?? {}) : null;
    if (!mapping || target.kind !== "controller") {
      return errorResponse(endpointId, correlationToken, "INVALID_DIRECTIVE", "Unsupported directive.");
    }
    intent = mapping.intent;
    context = mapping.context;
    controllerId = target.controllerId;
  }

  const res = await executeIntent({ uid, controllerId, intent, source: SOURCE, db });
  if (!res.ok) {
    const e = voiceErrorToAlexa(res.code);
    return errorResponse(endpointId, correlationToken, e.type, e.message);
  }

  // 'confirmed' and 'optimistic' → success; 'failed' → ErrorResponse.
  const outcomes = await Promise.all(res.commandRefs.map((r) => awaitOutcome(r, outcomeWaitMs)));
  const failed = outcomes.find((o) => o.status === "failed");
  if (failed && failed.status === "failed") {
    const type = /timeout|offline|unreachable|no_bridge_paired/i.test(failed.error)
      ? "ENDPOINT_UNREACHABLE"
      : "INTERNAL_ERROR";
    return errorResponse(endpointId, correlationToken, type, "Device did not confirm the command.");
  }

  if (intent.kind === "ACTIVATE_SCENE") {
    return {
      context: {},
      event: {
        header: header("Alexa.SceneController", "ActivationStarted", correlationToken),
        endpoint: { endpointId },
        payload: { cause: { type: "VOICE_INTERACTION" }, timestamp: nowIso() },
      },
    };
  }
  return {
    context: { properties: context },
    event: {
      header: header("Alexa", "Response", correlationToken),
      endpoint: { endpointId },
      payload: {},
    },
  };
}

async function reportState(
  uid: string,
  endpointId: string,
  correlationToken: string | undefined,
  target: Target,
  db: Firestore
): Promise<Json> {
  const props: Json[] = [];
  if (target.kind === "controller") {
    const stateDoc = await db.collection("users").doc(uid).collection("device_state").doc("current").get();
    const state = stateDoc.exists ? (stateDoc.data() as Json) : { on: false, brightness: 200 };
    const ts = nowIso();
    props.push(prop("Alexa.PowerController", "powerState", state.on ? "ON" : "OFF", ts));
    props.push(
      prop("Alexa.BrightnessController", "brightness", Math.round(((state.brightness ?? 200) / 255) * 100), ts)
    );
  }
  return {
    context: { properties: props },
    event: {
      header: header("Alexa", "StateReport", correlationToken),
      endpoint: { endpointId },
      payload: {},
    },
  };
}

/** Well-formed fallback for unexpected exceptions (index.js catch). */
export function internalError(body: Json): Json {
  const h = body?.directive?.header ?? {};
  return errorResponse(
    body?.directive?.endpoint?.endpointId,
    typeof h.correlationToken === "string" ? h.correlationToken : undefined,
    "INTERNAL_ERROR",
    "Internal error."
  );
}
