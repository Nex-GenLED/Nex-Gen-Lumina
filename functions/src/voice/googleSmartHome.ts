/**
 * googleSmartHome — canonical Google Smart Home fulfillment logic.
 *
 * Extracted from index.js's handleGoogle* handlers so SYNC/QUERY/EXECUTE are
 * unit-testable (injectable db) and EXECUTE routes through
 * intentCore.executeIntent. This replaces the legacy write path (a raw-map
 * payload typed power/brightness/scene, a hardcoded primary controller target,
 * and no controllerIp/webhookUrl) that executeWledCommand skipped as bridge
 * mode and the ESP32 bridge only partially ran. index.js's onRequest wrapper
 * keeps the auth + dispatch and delegates each intent here.
 *
 * Device-id contract (from deviceResolver):
 *   "lumina-main"        → the primary controller (customData.controllerId)
 *   "controller-<docId>" → that controller (customData.controllerId)
 *   "scene-<docId>" / "gameday-<slug>" → scene activation (customData.sceneId),
 *                          unscoped → intentCore fans out to all controllers.
 *
 * Flag: every intent checks voice_control.enabled first (intentCore's
 * defensive-false reader). When OFF we return `deviceOffline`, NEVER
 * authFailure/authExpired — per Google's error reference the auth-family codes
 * trigger account UNLINKING, which must never happen for a transient config
 * flag: https://developers.google.com/assistant/smarthome/reference/errors-exceptions
 */

import * as admin from "firebase-admin";
import { resolveDevices, resolveScenes } from "./deviceResolver";
import {
  executeIntent,
  awaitOutcome,
  readVoiceControlEnabled,
  VoiceIntent,
  VoiceErrorCode,
} from "./intentCore";

type Firestore = admin.firestore.Firestore;
// Google request/response payloads are dynamically shaped; treat as opaque JSON.
// eslint-disable-next-line @typescript-eslint/no-explicit-any
type Json = any;

const SOURCE = "voice_google" as const;

// ---------------------------------------------------------------------------
// SYNC — device discovery via the shared resolvers (nickname continuity).
// ---------------------------------------------------------------------------
export async function handleSync(
  requestId: string,
  userId: string,
  db: Firestore = admin.firestore()
): Promise<Json> {
  if (!(await readVoiceControlEnabled(db, userId))) {
    return {
      requestId,
      payload: {
        agentUserId: userId,
        errorCode: "deviceOffline",
        debugString: "voice_control disabled",
      },
    };
  }
  const devices = [
    ...(await resolveDevices(userId, db)),
    ...(await resolveScenes(userId, db)),
  ];
  return { requestId, payload: { agentUserId: userId, devices } };
}

// ---------------------------------------------------------------------------
// QUERY — optimistic/cached whole-system state.
// v1.1 upgrade: a live per-controller getState (round-tripping the device) is
// viable only in Webhook Mode — Bridge Mode has no synchronous read path.
// ---------------------------------------------------------------------------
export async function handleQuery(
  requestId: string,
  userId: string,
  payload: Json,
  db: Firestore = admin.firestore()
): Promise<Json> {
  const devices: Json[] = payload?.devices ?? [];
  const deviceStates: Record<string, Json> = {};

  if (!(await readVoiceControlEnabled(db, userId))) {
    for (const d of devices) {
      deviceStates[d.id] = {
        online: false,
        status: "ERROR",
        errorCode: "deviceOffline",
      };
    }
    return { requestId, payload: { devices: deviceStates } };
  }

  const stateDoc = await db
    .collection("users")
    .doc(userId)
    .collection("device_state")
    .doc("current")
    .get();
  const state = stateDoc.exists
    ? (stateDoc.data() as Json)
    : { on: false, brightness: 200 };

  for (const d of devices) {
    if (d?.customData?.type === "scene") {
      deviceStates[d.id] = { online: true };
      continue;
    }
    deviceStates[d.id] = {
      online: true,
      on: state.on ?? false,
      brightness: Math.round(((state.brightness ?? 200) / 255) * 100),
    };
  }
  return { requestId, payload: { devices: deviceStates } };
}

// ---------------------------------------------------------------------------
// EXECUTE — each command mapped to a VoiceIntent and enqueued via intentCore.
// ---------------------------------------------------------------------------
export async function handleExecute(
  requestId: string,
  userId: string,
  payload: Json,
  db: Firestore = admin.firestore(),
  outcomeWaitMs = 4000
): Promise<Json> {
  const commands: Json[] = payload?.commands ?? [];

  if (!(await readVoiceControlEnabled(db, userId))) {
    const results = commands.map((c: Json) => ({
      ids: (c.devices ?? []).map((d: Json) => d.id),
      status: "ERROR",
      errorCode: "deviceOffline",
    }));
    return { requestId, payload: { commands: results } };
  }

  const results: Json[] = [];
  for (const command of commands) {
    for (const device of command.devices ?? []) {
      for (const execution of command.execution ?? []) {
        results.push(
          await runExecution(userId, device, execution, db, outcomeWaitMs)
        );
      }
    }
  }
  return { requestId, payload: { commands: results } };
}

interface Mapping {
  intent: VoiceIntent;
  controllerId: string | null;
  states: Json;
}

/** Google command → (VoiceIntent, target, optimistic reported state). */
function mapCommand(execution: Json, cd: Json): Mapping | null {
  const params = execution?.params ?? {};
  switch (execution?.command) {
    case "action.devices.commands.OnOff":
      return {
        intent: { kind: params.on ? "POWER_ON" : "POWER_OFF" },
        controllerId: cd?.controllerId ?? null,
        states: { on: !!params.on },
      };
    case "action.devices.commands.BrightnessAbsolute":
      return {
        intent: { kind: "SET_BRIGHTNESS", level: params.brightness },
        controllerId: cd?.controllerId ?? null,
        states: { on: true, brightness: params.brightness },
      };
    case "action.devices.commands.ActivateScene": {
      const sceneId = cd?.sceneId;
      if (!sceneId) return null;
      // Unscoped scene → intentCore fans out to every controller.
      return {
        intent: { kind: "ACTIVATE_SCENE", sceneId },
        controllerId: null,
        states: {},
      };
    }
    default:
      return null;
  }
}

async function runExecution(
  userId: string,
  device: Json,
  execution: Json,
  db: Firestore,
  outcomeWaitMs: number
): Promise<Json> {
  const ids = [device?.id];
  const cd = device?.customData ?? {};
  const mapping = mapCommand(execution, cd);
  if (!mapping) return { ids, status: "ERROR", errorCode: "notSupported" };

  const res = await executeIntent({
    uid: userId,
    controllerId: mapping.controllerId,
    intent: mapping.intent,
    source: SOURCE,
    deviceUserId: typeof cd.userId === "string" ? cd.userId : undefined,
    db,
  });
  if (!res.ok) {
    return { ids, status: "ERROR", errorCode: voiceErrorToGoogle(res.code) };
  }

  // 'confirmed' + 'optimistic' → SUCCESS (queued and will run); 'failed' → ERROR.
  const outcomes = await Promise.all(
    res.commandRefs.map((r) => awaitOutcome(r, outcomeWaitMs))
  );
  const failed = outcomes.find((o) => o.status === "failed");
  if (failed) {
    const errText = failed.status === "failed" ? failed.error : "";
    const errorCode = /timeout|offline|unreachable/i.test(errText)
      ? "deviceOffline"
      : "hardError";
    return { ids, status: "ERROR", errorCode };
  }
  return { ids, status: "SUCCESS", states: mapping.states };
}

/**
 * Map an intentCore VoiceError to a Google errorCode. Deliberately avoids
 * authFailure/authExpired (which unlink the account).
 */
function voiceErrorToGoogle(code: VoiceErrorCode): string {
  switch (code) {
    case "unknown_scene":
    case "unknown_controller":
    case "unsupported_intent":
      return "notSupported";
    case "not_enabled":
    case "cross_uid":
    case "no_target":
    default:
      return "deviceOffline";
  }
}
