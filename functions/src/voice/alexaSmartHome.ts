/**
 * alexaSmartHome — Alexa Smart Home directive fulfillment (net-new).
 *
 * Alexa previously had OAuth account-linking only (no execute path). This adds
 * Discovery + PowerController/BrightnessController/SceneController/ReportState,
 * all routed through the same deviceResolver + intentCore as Google — so the
 * canonical RemoteCommand shape and device-id contract are shared:
 *   "lumina-main" / "controller-<id>" / "scene-<id>" / "gameday-<slug>".
 *
 * Auth: verifies the self-signed JWT issued by alexaToken (see alexaJwt.ts). A
 * missing/expired/tampered token → INVALID_AUTHORIZATION_CREDENTIAL, which
 * signals Amazon to refresh the access token (also heals the one-time
 * custom-token→JWT format transition, since the refresh token is
 * format-independent). Flag OFF → ENDPOINT_UNREACHABLE, which does NOT disable
 * the skill (Alexa error reference):
 *   https://developer.amazon.com/docs/device-apis/alexa-errorresponse.html
 */

import * as admin from "firebase-admin";
import { randomUUID } from "crypto";
import { resolveDevices, resolveScenes, SmartHomeDevice } from "./deviceResolver";
import {
  executeIntent,
  awaitOutcome,
  readVoiceControlEnabled,
  VoiceIntent,
  VoiceErrorCode,
} from "./intentCore";
import { verifyAlexaJwt } from "./alexaJwt";

type Firestore = admin.firestore.Firestore;
// Alexa directive/response payloads are dynamically shaped; treat as opaque.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

const SOURCE = "voice_alexa" as const;

function nowIso(): string {
  return new Date().toISOString();
}

function header(namespace: string, name: string, correlationToken?: string): Json {
  const h: Json = { namespace, name, messageId: randomUUID(), payloadVersion: "3" };
  if (correlationToken) h.correlationToken = correlationToken;
  return h;
}

function errorResponse(
  endpointId: string | undefined,
  correlationToken: string | undefined,
  type: string,
  message: string
): Json {
  return {
    event: {
      header: header("Alexa", "ErrorResponse", correlationToken),
      ...(endpointId ? { endpoint: { endpointId } } : {}),
      payload: { type, message },
    },
  };
}

// ---------------------------------------------------------------------------
// Discovery — map shared resolver devices to Alexa endpoints.
// ---------------------------------------------------------------------------
function alexaIface(): Json {
  return { type: "AlexaInterface", interface: "Alexa", version: "3" };
}
function propIface(iface: string, prop: string): Json {
  return {
    type: "AlexaInterface",
    interface: iface,
    version: "3",
    properties: {
      supported: [{ name: prop }],
      retrievable: true,
      proactivelyReported: false,
    },
  };
}

function toAlexaEndpoint(d: SmartHomeDevice): Json {
  const cd = (d.customData || {}) as Json;
  const cookie: Record<string, string> = {};
  for (const k of ["userId", "type", "controllerId", "controllerIp", "sceneId"]) {
    if (typeof cd[k] === "string") cookie[k] = cd[k];
  }
  const base = {
    endpointId: d.id,
    manufacturerName: "Nex-Gen Lumina",
    friendlyName: d.name.name,
    description: "Nex-Gen Lumina WLED",
    cookie,
  };
  if (d.type === "action.devices.types.SCENE") {
    return {
      ...base,
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
  return {
    ...base,
    displayCategories: ["LIGHT"],
    capabilities: [
      alexaIface(),
      propIface("Alexa.PowerController", "powerState"),
      propIface("Alexa.BrightnessController", "brightness"),
    ],
  };
}

async function handleDiscovery(uid: string, db: Firestore): Promise<Json> {
  const devices = [
    ...(await resolveDevices(uid, db)),
    ...(await resolveScenes(uid, db)),
  ];
  return {
    event: {
      header: header("Alexa.Discovery", "Discover.Response"),
      payload: { endpoints: devices.map(toAlexaEndpoint) },
    },
  };
}

// ---------------------------------------------------------------------------
// Control directive → intent mapping
// ---------------------------------------------------------------------------
interface Mapping {
  intent: VoiceIntent;
  controllerId: string | null;
  context: Json[];
  scene?: boolean;
}

function prop(namespace: string, name: string, value: Json, ts: string): Json {
  return {
    namespace,
    name,
    value,
    timeOfSample: ts,
    uncertaintyInMilliseconds: 500,
  };
}

function mapDirective(
  namespace: string,
  name: string,
  payload: Json,
  cookie: Json
): Mapping | null {
  const ts = nowIso();
  const controllerId = typeof cookie?.controllerId === "string" ? cookie.controllerId : null;
  switch (namespace) {
    case "Alexa.PowerController": {
      const on = name === "TurnOn";
      return {
        intent: { kind: on ? "POWER_ON" : "POWER_OFF" },
        controllerId,
        context: [prop("Alexa.PowerController", "powerState", on ? "ON" : "OFF", ts)],
      };
    }
    case "Alexa.BrightnessController": {
      if (name !== "SetBrightness") return null;
      const level = Number(payload?.brightness ?? 0);
      return {
        intent: { kind: "SET_BRIGHTNESS", level },
        controllerId,
        context: [prop("Alexa.BrightnessController", "brightness", level, ts)],
      };
    }
    case "Alexa.SceneController": {
      if (name !== "Activate") return null;
      const sceneId = cookie?.sceneId;
      if (typeof sceneId !== "string") return null;
      // Unscoped scene → intentCore fans out to every controller.
      return { intent: { kind: "ACTIVATE_SCENE", sceneId }, controllerId: null, context: [], scene: true };
    }
    default:
      return null;
  }
}

function successResponse(
  endpointId: string,
  correlationToken: string | undefined,
  context: Json[]
): Json {
  return {
    context: { properties: context },
    event: {
      header: header("Alexa", "Response", correlationToken),
      endpoint: { endpointId },
      payload: {},
    },
  };
}

function sceneActivatedResponse(
  endpointId: string,
  correlationToken: string | undefined
): Json {
  return {
    event: {
      header: header("Alexa.SceneController", "ActivationStarted", correlationToken),
      endpoint: { endpointId },
      payload: { cause: { type: "VOICE_INTERACTION" }, timestamp: nowIso() },
    },
  };
}

function voiceErrorToAlexa(code: VoiceErrorCode): { type: string; message: string } {
  switch (code) {
    case "not_enabled":
    case "no_target":
      return { type: "ENDPOINT_UNREACHABLE", message: "The endpoint is currently unavailable." };
    case "cross_uid":
      return { type: "INVALID_AUTHORIZATION_CREDENTIAL", message: "Device does not belong to this account." };
    case "unknown_controller":
    case "unknown_scene":
      return { type: "NO_SUCH_ENDPOINT", message: "Unknown endpoint." };
    case "unsupported_intent":
    default:
      return { type: "INVALID_DIRECTIVE", message: "Unsupported directive." };
  }
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
export async function handleAlexaDirective(
  body: Json,
  secret: string,
  db: Firestore = admin.firestore(),
  outcomeWaitMs = 4000
): Promise<Json> {
  const directive = body?.directive ?? {};
  const h = directive.header ?? {};
  const namespace: string = h.namespace ?? "";
  const name: string = h.name ?? "";
  const correlationToken: string | undefined = h.correlationToken;
  const endpoint = directive.endpoint ?? {};
  const endpointId: string | undefined = endpoint.endpointId;

  // Discovery carries the token in payload.scope; directives in endpoint.scope.
  const token =
    namespace === "Alexa.Discovery"
      ? directive.payload?.scope?.token
      : endpoint.scope?.token;

  const claims = verifyAlexaJwt(token, secret);
  if (!claims) {
    // Invalid/expired token → Amazon refreshes (also heals the one-time
    // custom-token→JWT transition). Never disables the skill.
    return errorResponse(
      endpointId,
      correlationToken,
      "INVALID_AUTHORIZATION_CREDENTIAL",
      "Invalid or expired access token."
    );
  }
  const uid = claims.uid;
  const enabled = await readVoiceControlEnabled(db, uid);

  // Discovery
  if (namespace === "Alexa.Discovery" && name === "Discover") {
    // Flag OFF: report zero endpoints (non-unlinking) rather than an error.
    if (!enabled) {
      return {
        event: {
          header: header("Alexa.Discovery", "Discover.Response"),
          payload: { endpoints: [] },
        },
      };
    }
    return handleDiscovery(uid, db);
  }

  // ReportState → optimistic/cached (v1.1: live getState, Webhook Mode only).
  if (namespace === "Alexa" && name === "ReportState") {
    if (!enabled) {
      return errorResponse(endpointId, correlationToken, "ENDPOINT_UNREACHABLE", "Voice control is disabled.");
    }
    return reportState(uid, endpointId, correlationToken, endpoint.cookie ?? {}, db);
  }

  // Control directives — flag gate first.
  if (!enabled) {
    return errorResponse(endpointId, correlationToken, "ENDPOINT_UNREACHABLE", "Voice control is disabled.");
  }

  const cookie = endpoint.cookie ?? {};
  const mapping = mapDirective(namespace, name, directive.payload ?? {}, cookie);
  if (!mapping) {
    return errorResponse(endpointId, correlationToken, "INVALID_DIRECTIVE", `Unsupported: ${namespace}/${name}`);
  }

  const res = await executeIntent({
    uid,
    controllerId: mapping.controllerId,
    intent: mapping.intent,
    source: SOURCE,
    deviceUserId: typeof cookie.userId === "string" ? cookie.userId : undefined,
    db,
  });
  if (!res.ok) {
    const e = voiceErrorToAlexa(res.code);
    return errorResponse(endpointId, correlationToken, e.type, e.message);
  }

  // 'confirmed' + 'optimistic' → success; 'failed' → ErrorResponse.
  const outcomes = await Promise.all(res.commandRefs.map((r) => awaitOutcome(r, outcomeWaitMs)));
  const failed = outcomes.find((o) => o.status === "failed");
  if (failed) {
    const errText = failed.status === "failed" ? failed.error : "";
    const type = /timeout|offline|unreachable/i.test(errText) ? "ENDPOINT_UNREACHABLE" : "INTERNAL_ERROR";
    return errorResponse(endpointId, correlationToken, type, "Device did not confirm the command.");
  }

  if (mapping.scene) return sceneActivatedResponse(endpointId ?? "", correlationToken);
  return successResponse(endpointId ?? "", correlationToken, mapping.context);
}

async function reportState(
  uid: string,
  endpointId: string | undefined,
  correlationToken: string | undefined,
  cookie: Json,
  db: Firestore
): Promise<Json> {
  const stateDoc = await db
    .collection("users")
    .doc(uid)
    .collection("device_state")
    .doc("current")
    .get();
  const state = stateDoc.exists ? (stateDoc.data() as Json) : { on: false, brightness: 200 };
  const ts = nowIso();
  const props: Json[] = [];
  if (cookie?.type !== "scene") {
    props.push(prop("Alexa.PowerController", "powerState", state.on ? "ON" : "OFF", ts));
    props.push(
      prop(
        "Alexa.BrightnessController",
        "brightness",
        Math.round(((state.brightness ?? 200) / 255) * 100),
        ts
      )
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

/** Well-formed fallback error for unexpected exceptions (index.js catch). */
export function internalError(body: Json): Json {
  const h = body?.directive?.header ?? {};
  return errorResponse(
    body?.directive?.endpoint?.endpointId,
    h.correlationToken,
    "INTERNAL_ERROR",
    "Internal error."
  );
}
