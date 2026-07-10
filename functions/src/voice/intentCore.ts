/**
 * intentCore — the canonical, platform-agnostic voice command core.
 *
 * The Alexa and Google Smart Home handlers (next prompts) both call into this
 * module; it is the ONE place a voice-issued intent becomes a canonical
 * RemoteCommand document. It deliberately mirrors the server-side write pattern
 * of applySyncPattern.ts (the established command enqueuer) and the exact
 * command-doc shape of the Dart CloudRelayRepository (remote_command.dart
 * toFirestore, lib/models/remote_command.dart:94-107):
 *
 *   { type, payload(STRING), controllerId, controllerIp, webhookUrl,
 *     createdAt(serverTimestamp), status, source, voiceRequestId }
 *
 * `payload` is ALWAYS a JSON string — the iOS Firestore SDK aborts on directly
 * nested arrays (#84; see cloud_relay_repository.dart:234-236), so every writer
 * jsonEncodes the WLED body. This module never violates that.
 *
 * Scene execution builds ON deviceResolver.resolveScenes (discovery) — see
 * resolveActivatableScenes below — rather than duplicating the scene listing.
 *
 * NOT WIRED IN. This prompt (B-2) only creates the core + tests. The rewire of
 * handleGoogleSync / a new Alexa Discovery+Directive handler to call it is the
 * NEXT prompt. executeWledCommand, applySyncPattern, handleGoogleSync,
 * executeGoogleCommand and the OAuth functions are untouched.
 */

import * as admin from "firebase-admin";
import { randomUUID } from "crypto";
import { resolveScenes } from "./deviceResolver";

type Firestore = admin.firestore.Firestore;
type DocumentReference = admin.firestore.DocumentReference;

export type VoiceSource = "voice_alexa" | "voice_google";

/** A resolved, ready-to-enqueue voice intent. `level` is 0-100 for brightness. */
export type VoiceIntent =
  | { kind: "POWER_ON" }
  | { kind: "POWER_OFF" }
  | { kind: "SET_BRIGHTNESS"; level: number }
  | { kind: "ACTIVATE_SCENE"; sceneId: string };

export type VoiceErrorCode =
  | "not_enabled"
  | "cross_uid"
  | "unknown_controller"
  | "no_target"
  | "unknown_scene"
  | "unsupported_intent";

export interface VoiceError {
  ok: false;
  code: VoiceErrorCode;
  message: string;
}

export interface ExecuteSuccess {
  ok: true;
  voiceRequestId: string;
  /** One ref per targeted controller (fanout). */
  commandRefs: DocumentReference[];
}

export type ExecuteResult = ExecuteSuccess | VoiceError;

/** awaitOutcome resolution. `optimistic` = timed out before a terminal status. */
export type Outcome =
  | { status: "confirmed" }
  | { status: "failed"; error: string }
  | { status: "optimistic" };

/** A scene the user can activate by voice, with its executable WLED body. */
export interface ActivatableScene {
  /** Addressing id passed back as ACTIVATE_SCENE.sceneId. */
  sceneId: string;
  /** Primary spoken/display name. */
  name: string;
  /** Secondary name (saved_design_name for Game Day), when present. */
  altName?: string;
  /** jsonEncoded WLED body — applied verbatim as an `applyJson` payload. */
  payloadString: string;
  origin: "scene" | "game_day";
}

// Game Day scenes are addressed with this prefix so a raw Firestore scene
// auto-id (20-char alnum, never contains "-") can never collide with one.
const GAME_DAY_PREFIX = "gameday-";

function err(code: VoiceErrorCode, message: string): VoiceError {
  return { ok: false, code, message };
}

function clamp(n: number, lo: number, hi: number): number {
  return Math.max(lo, Math.min(hi, n));
}

// ---------------------------------------------------------------------------
// Feature flag — config/voice_control.enabled, defensive-false.
// Mirrors the sync_fanout flag pattern (applySyncPattern.readSyncFanoutEnabled):
// missing doc / missing field / non-bool / read error → false. Read fresh each
// invocation (no cache beyond the function instance).
// ---------------------------------------------------------------------------
export async function readVoiceControlEnabled(db: Firestore): Promise<boolean> {
  try {
    const doc = await db.collection("config").doc("voice_control").get();
    return doc.data()?.enabled === true;
  } catch (_e) {
    return false;
  }
}

// ---------------------------------------------------------------------------
// Scene payload assembly — TS ports of Dart Scene.toWledPayload()
// (lib/features/scenes/scene_models.dart:234-256) and CustomDesign.toWledPayload()
// (lib/features/design/design_models.dart:217-261). Key insertion order matches
// the Dart map literals so JSON.stringify() is byte-identical to Dart jsonEncode.
// ---------------------------------------------------------------------------

/** Port of CustomDesign.toWledPayload → jsonEncoded string. */
function customDesignToPayloadString(cd: admin.firestore.DocumentData): string {
  const channels = Array.isArray(cd.channels) ? cd.channels : [];
  const brightness = typeof cd.brightness === "number" ? cd.brightness : 128;

  const seg: Record<string, unknown>[] = [];
  for (const ch of channels) {
    // `included` defaults true (only an explicit false skips).
    if (ch?.included === false) continue;

    const groups = Array.isArray(ch?.color_groups) ? ch.color_groups : [];
    let colors = groups.slice(0, 3).map((g: admin.firestore.DocumentData) => g?.color);
    if (colors.length === 0) colors = [[255, 255, 255, 0]];

    const effectId = typeof ch?.effect_id === "number" ? ch.effect_id : 0;
    // Solid (0) with >1 color group → Solid Pattern (83), matching Dart.
    const fx = effectId === 0 && groups.length > 1 ? 83 : effectId;

    const segObj: Record<string, unknown> = {
      id: typeof ch?.channel_id === "number" ? ch.channel_id : 0,
      col: colors,
      fx,
      sx: typeof ch?.speed === "number" ? ch.speed : 128,
      ix: typeof ch?.intensity === "number" ? ch.intensity : 128,
    };
    // Emit `rev` ONLY when explicitly reversed (Dart omits it otherwise so the
    // controller's manual per-segment direction is preserved).
    if (ch?.reverse === true) segObj.rev = true;
    seg.push(segObj);
  }

  return JSON.stringify({ on: true, bri: brightness, seg });
}

/** Decode a color matrix stored either as a jsonEncoded string (#84) or raw. */
function decodeColors(raw: unknown): unknown {
  if (typeof raw === "string") {
    try {
      return JSON.parse(raw);
    } catch (_e) {
      return [];
    }
  }
  return Array.isArray(raw) ? raw : [];
}

type ScenePayload = { payloadString: string } | { skip: string };

/**
 * Derive the executable jsonEncoded WLED body for ONE scene by its addressing
 * id. Never guesses: a type that cannot be faithfully produced returns a
 * `{skip}` (logged by the caller) instead of a fabricated payload.
 */
async function resolveScenePayload(
  db: Firestore,
  uid: string,
  sceneId: string
): Promise<ScenePayload | null> {
  // Game Day team → its stored, already-jsonEncoded design body (verbatim).
  if (sceneId.startsWith(GAME_DAY_PREFIX)) {
    const teamSlug = sceneId.slice(GAME_DAY_PREFIX.length);
    const doc = await db
      .collection("users")
      .doc(uid)
      .collection("game_day_autopilot")
      .doc(teamSlug)
      .get();
    if (!doc.exists) return null;
    const payload = doc.data()?.saved_design_payload;
    if (typeof payload === "string" && payload.length > 0) {
      return { payloadString: payload };
    }
    return { skip: `game_day ${teamSlug} has no saved_design_payload` };
  }

  const doc = await db
    .collection("users")
    .doc(uid)
    .collection("scenes")
    .doc(sceneId)
    .get();
  if (!doc.exists) return null;

  const data = doc.data() as admin.firestore.DocumentData;
  switch (data.type) {
    case "system":
    case "snapshot": {
      const wp = data.wled_payload;
      // Stored jsonEncoded by every current writer → verbatim, never re-encode.
      if (typeof wp === "string" && wp.length > 0) return { payloadString: wp };
      if (wp && typeof wp === "object") return { payloadString: JSON.stringify(wp) };
      return { skip: `scene ${sceneId} (${data.type}) has no wled_payload` };
    }
    case "custom": {
      const cd = data.custom_design;
      if (cd && typeof cd === "object") {
        return { payloadString: customDesignToPayloadString(cd) };
      }
      return { skip: `scene ${sceneId} (custom) has no custom_design` };
    }
    case "library": {
      const lp = data.library_pattern;
      if (!lp || typeof lp !== "object") {
        return { skip: `scene ${sceneId} (library) has no library_pattern` };
      }
      // Scene.toWledPayload library branch uses the Scene's own brightness.
      const brightness = typeof data.brightness === "number" ? data.brightness : 128;
      const payload = {
        on: true,
        bri: brightness,
        seg: [
          {
            col: decodeColors(lp.colors),
            fx: typeof lp.effect_id === "number" ? lp.effect_id : 0,
            sx: typeof lp.speed === "number" ? lp.speed : 128,
            ix: typeof lp.intensity === "number" ? lp.intensity : 128,
          },
        ],
      };
      return { payloadString: JSON.stringify(payload) };
    }
    default:
      return { skip: `scene ${sceneId} has unsupported type "${data.type}"` };
  }
}

/**
 * Enumerate every scene the user can activate by voice, each carrying its
 * executable payloadString. Wraps deviceResolver.resolveScenes for the /scenes
 * listing (reusing its system-scene skip), then appends Game Day teams that
 * have a saved design. Scenes/teams whose payload cannot be produced faithfully
 * are logged and excluded (never guessed) — voice v1 exposes only activatable
 * entries.
 */
export async function resolveActivatableScenes(
  db: Firestore,
  uid: string
): Promise<ActivatableScene[]> {
  const out: ActivatableScene[] = [];

  // /scenes — reuse discovery listing, attach executable payloads.
  const devices = await resolveScenes(uid, db);
  for (const d of devices) {
    const sceneId = (d.customData?.sceneId as string | undefined) ?? "";
    if (!sceneId) continue;
    const payload = await resolveScenePayload(db, uid, sceneId);
    if (!payload) continue;
    if ("skip" in payload) {
      console.warn(`voice: skipping scene "${d.name.name}" — ${payload.skip}`);
      continue;
    }
    out.push({
      sceneId,
      name: d.name.name,
      payloadString: payload.payloadString,
      origin: "scene",
    });
  }

  // Game Day teams with a saved design → activatable by team / design name.
  const gdSnap = await db
    .collection("users")
    .doc(uid)
    .collection("game_day_autopilot")
    .get();
  for (const doc of gdSnap.docs) {
    const data = doc.data();
    const payload = data.saved_design_payload;
    if (typeof payload !== "string" || payload.length === 0) {
      console.warn(
        `voice: skipping Game Day "${doc.id}" — no saved_design_payload`
      );
      continue;
    }
    const teamName =
      typeof data.team_name === "string" && data.team_name.length > 0
        ? data.team_name
        : doc.id;
    const savedName =
      typeof data.saved_design_name === "string" && data.saved_design_name.length > 0
        ? data.saved_design_name
        : undefined;
    out.push({
      sceneId: `${GAME_DAY_PREFIX}${doc.id}`,
      name: teamName,
      altName: savedName,
      payloadString: payload,
      origin: "game_day",
    });
  }

  return out;
}

// ---------------------------------------------------------------------------
// Target resolution + ownership guard
// ---------------------------------------------------------------------------

interface Target {
  id: string;
  ip: string;
}

/**
 * Resolve target controllers. A specified controllerId is fetched under the
 * authenticated uid ONLY — a foreign/unknown id simply does not exist there, so
 * cross-uid access is structurally impossible. A null/absent controllerId fans
 * out to ALL the user's controllers (one command each), matching applySyncPattern.
 */
async function resolveTargets(
  db: Firestore,
  uid: string,
  controllerId: string | null
): Promise<Target[] | VoiceError> {
  const controllersRef = db.collection("users").doc(uid).collection("controllers");

  if (controllerId && controllerId.length > 0) {
    const doc = await controllersRef.doc(controllerId).get();
    if (!doc.exists) {
      return err(
        "unknown_controller",
        `Controller "${controllerId}" not found for this account.`
      );
    }
    const ip = (doc.data()?.ip as string | undefined) ?? "";
    return [{ id: doc.id, ip }];
  }

  const snap = await controllersRef.get();
  return snap.docs
    .map((d) => ({ id: d.id, ip: (d.data().ip as string | undefined) ?? "" }))
    .filter((t) => t.ip.length > 0);
}

// ---------------------------------------------------------------------------
// executeIntent — the enqueuer
// ---------------------------------------------------------------------------

export interface ExecuteParams {
  uid: string;
  /** Real controller doc id (from device customData), or null to fan out. */
  controllerId: string | null;
  intent: VoiceIntent;
  source: VoiceSource;
  /** Device customData.userId, when the platform provides it — cross-uid guard. */
  deviceUserId?: string;
  /** Injectable for tests; defaults to the app Firestore. */
  db?: Firestore;
  /** Injectable for deterministic tests; defaults to a random UUID. */
  voiceRequestId?: string;
}

/**
 * Turn a resolved voice intent into canonical RemoteCommand document(s).
 * One doc per targeted controller. Returns the refs (for awaitOutcome) or a
 * structured error the platform handlers map to their own auth/error shapes.
 */
export async function executeIntent(p: ExecuteParams): Promise<ExecuteResult> {
  const db = p.db ?? admin.firestore();

  // Ownership guard: a device linked to another uid must never drive this uid.
  if (p.deviceUserId && p.deviceUserId !== p.uid) {
    return err(
      "cross_uid",
      "Device does not belong to the authenticated account."
    );
  }

  // Feature flag (defensive-false).
  if (!(await readVoiceControlEnabled(db))) {
    return err("not_enabled", "Voice control is not enabled for this account.");
  }

  const voiceRequestId = p.voiceRequestId ?? randomUUID();

  // Build the command type + string payload.
  let type: string;
  let payloadString: string;
  switch (p.intent.kind) {
    case "POWER_ON":
      type = "setState";
      payloadString = JSON.stringify({ on: true });
      break;
    case "POWER_OFF":
      type = "setState";
      payloadString = JSON.stringify({ on: false });
      break;
    case "SET_BRIGHTNESS": {
      const level = clamp(p.intent.level, 0, 100);
      type = "setState";
      payloadString = JSON.stringify({ bri: Math.round((level * 255) / 100) });
      break;
    }
    case "ACTIVATE_SCENE": {
      const scene = await resolveScenePayload(db, p.uid, p.intent.sceneId);
      if (!scene) {
        return err("unknown_scene", `Scene "${p.intent.sceneId}" not found.`);
      }
      if ("skip" in scene) {
        console.warn(`voice: cannot activate scene — ${scene.skip}`);
        return err(
          "unknown_scene",
          `Scene "${p.intent.sceneId}" cannot be activated.`
        );
      }
      type = "applyJson";
      payloadString = scene.payloadString;
      break;
    }
    default:
      return err("unsupported_intent", "Unsupported voice intent.");
  }

  // Resolve targets.
  const targets = await resolveTargets(db, p.uid, p.controllerId);
  if (!Array.isArray(targets)) return targets; // VoiceError
  if (targets.length === 0) {
    return err("no_target", "No controllers are available for this account.");
  }

  // Webhook URL from the profile ('' ⇒ Bridge Mode), matching applySyncPattern.
  const userDoc = await db.collection("users").doc(p.uid).get();
  const webhookUrl = (userDoc.data()?.webhookUrl as string | undefined) || "";

  // One canonical RemoteCommand doc per target.
  const commandsRef = db.collection("users").doc(p.uid).collection("commands");
  const commandRefs: DocumentReference[] = [];
  for (const t of targets) {
    const ref = commandsRef.doc();
    await ref.set({
      type,
      payload: payloadString, // ALWAYS a string (#84)
      controllerId: t.id,
      controllerIp: t.ip,
      webhookUrl,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      status: "pending",
      source: p.source,
      voiceRequestId,
    });
    commandRefs.push(ref);
  }

  return { ok: true, voiceRequestId, commandRefs };
}

// ---------------------------------------------------------------------------
// awaitOutcome — bounded wait on a command doc
// ---------------------------------------------------------------------------

/**
 * Listen for a command's terminal status, capped at maxWaitMs. Voice platforms
 * allow ~8s total; the 4s default leaves headroom. On timeout resolves
 * `optimistic` — callers translate that to a spoken success ("Okay") since the
 * command is queued and will run. The listener + timer are always cleaned up.
 */
export function awaitOutcome(
  commandRef: DocumentReference,
  maxWaitMs = 4000
): Promise<Outcome> {
  return new Promise<Outcome>((resolve) => {
    let settled = false;
    let unsubscribe: (() => void) | null = null;
    let timer: ReturnType<typeof setTimeout> | null = null;

    const cleanup = () => {
      if (unsubscribe) {
        unsubscribe();
        unsubscribe = null;
      }
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    };

    const finish = (outcome: Outcome) => {
      if (settled) return;
      settled = true;
      cleanup();
      resolve(outcome);
    };

    timer = setTimeout(() => finish({ status: "optimistic" }), maxWaitMs);

    unsubscribe = commandRef.onSnapshot(
      (snap) => {
        const data = snap.data();
        if (!data) return;
        if (data.status === "completed") {
          finish({ status: "confirmed" });
        } else if (data.status === "failed") {
          finish({
            status: "failed",
            error: typeof data.error === "string" ? data.error : "unknown",
          });
        }
      },
      // A listener error must not hang the caller — let the timer drive optimistic.
      (_err) => {
        /* swallow; timeout resolves optimistic */
      }
    );
  });
}
