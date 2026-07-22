/**
 * deviceResolver — voice-integration device & scene discovery helpers
 *
 * Ports the device/nickname + scene enumeration logic out of the legacy
 * Google Smart Home SYNC handler (functions/index.js `handleGoogleSync`) into
 * standalone, reusable resolvers so the upcoming voice rewire (Google SYNC,
 * and a future Alexa Discovery) can share one source of truth.
 *
 * CONTINUITY GUARANTEE
 * Existing linked Google Home users must see the SAME primary light device
 * after the rewire. Google keys devices by `id`; a changed id or nickname set
 * reads as a device removal + re-add, which forces a re-link and drops the
 * user's room assignments. So the primary (first) controller keeps the legacy
 * device id "lumina-main" AND the legacy nickname set. For single-controller
 * and zero-controller users the output of resolveDevices() is byte-identical
 * to the legacy single "lumina-main" device.
 *
 * MULTI-CONTROLLER UPGRADE
 * Where the legacy handler exposed exactly one "main light", this exposes one
 * LIGHT device per registered controller. The first/primary controller (oldest
 * by created_at — the one the user has had longest) keeps "lumina-main" + the
 * shared nicknames; each additional controller becomes its own LIGHT device
 * named by its controller nickname, with NO shared nicknames — so "outdoor
 * lights" / "house lights" keep resolving to the original primary.
 *
 * NOT WIRED IN YET. The live `handleGoogleSync` is intentionally left
 * unchanged. The rewire will swap its body for:
 *   [...await resolveDevices(uid), ...await resolveScenes(uid)]
 */

import * as admin from "firebase-admin";

/** Google Smart Home device object (SYNC response payload.devices[]). */
export interface SmartHomeDevice {
  id: string;
  type: string;
  traits: string[];
  name: {
    name: string;
    defaultNames: string[];
    nicknames?: string[];
  };
  willReportState: boolean;
  roomHint?: string;
  attributes?: Record<string, unknown>;
  deviceInfo?: {
    manufacturer: string;
    model: string;
    hwVersion: string;
    swVersion: string;
  };
  customData: Record<string, unknown>;
}

const DEVICE_INFO = {
  manufacturer: "Nex-Gen Lumina",
  model: "WLED Controller",
  hwVersion: "1.0",
  swVersion: "1.0",
} as const;

const LIGHT_TRAITS = [
  "action.devices.traits.OnOff",
  "action.devices.traits.Brightness",
];

/** Nicknames the legacy single-device handler attached to "lumina-main". */
function primaryNicknames(propertyName: string): string[] {
  return [propertyName, "outdoor lights", "house lights"];
}

interface ControllerRow {
  id: string;
  ip: string;
  name: string | null;
  sortKey: number;
}

/**
 * Read the user's controllers ordered oldest-first (primary = first).
 * ControllerModel writes `createdAt`; older docs used `created_at` — accept
 * either. Undated controllers sort last, ties break on doc id so the "primary"
 * choice is deterministic across repeated SYNC calls.
 *
 * CONTRACT — DO NOT CHANGE THIS ORDERING SEMANTICS.
 * The primary controller (index 0 of this list) is the one that receives the
 * stable Google device id "lumina-main" in resolveDevices(). Google (and
 * Alexa) hang the user's room assignments, routines, and voice targeting off
 * that device id, so the primary's *identity* must remain the same controller
 * for a given controller set across every SYNC. The primary is therefore
 * pinned to "oldest by created_at, ties broken by doc id" — both stable,
 * controller-intrinsic keys. A future refactor that re-sorts by name, IP,
 * last-seen, or any mutable/reorderable key would silently reassign
 * "lumina-main" to a different controller and churn device identity for every
 * linked household (forced re-link, lost rooms/routines). If you must change
 * the primary-selection key, treat it as a migration, not a refactor.
 */
async function loadControllersOldestFirst(
  db: admin.firestore.Firestore,
  userId: string
): Promise<ControllerRow[]> {
  const snap = await db
    .collection("users")
    .doc(userId)
    .collection("controllers")
    .get();

  const rows: ControllerRow[] = snap.docs.map((doc) => {
    const data = doc.data();
    const rawName = data.name;
    const created = data.created_at ?? data.createdAt;
    let sortKey = Number.MAX_SAFE_INTEGER;
    if (created && typeof created.toMillis === "function") {
      sortKey = created.toMillis();
    }
    return {
      id: doc.id,
      ip: typeof data.ip === "string" ? data.ip : "",
      name:
        typeof rawName === "string" && rawName.trim().length > 0
          ? rawName.trim()
          : null,
      sortKey,
    };
  });

  rows.sort((a, b) => a.sortKey - b.sortKey || a.id.localeCompare(b.id));
  return rows;
}

/**
 * Resolve the user's controllable LIGHT devices for a Smart Home SYNC.
 *
 * - Zero controllers → one legacy "lumina-main" device (exact legacy shape).
 * - One+ controllers → primary keeps "lumina-main" + nicknames; each extra
 *   controller is its own LIGHT device.
 */
export async function resolveDevices(
  userId: string
): Promise<SmartHomeDevice[]> {
  const db = admin.firestore();

  const userDoc = await db.collection("users").doc(userId).get();
  const profile = (userDoc.data() ?? {}) as admin.firestore.DocumentData;
  const propertyName =
    typeof profile.propertyName === "string" && profile.propertyName.length > 0
      ? profile.propertyName
      : "House Lights";

  const controllers = await loadControllersOldestFirst(db, userId);

  const primaryDevice = (
    customData: Record<string, unknown>
  ): SmartHomeDevice => ({
    id: "lumina-main",
    type: "action.devices.types.LIGHT",
    traits: LIGHT_TRAITS,
    name: {
      name: propertyName,
      defaultNames: ["Lumina Lights", "House Lights"],
      nicknames: primaryNicknames(propertyName),
    },
    willReportState: true,
    roomHint: "Outside",
    deviceInfo: { ...DEVICE_INFO },
    customData,
  });

  // Zero controllers: preserve the exact legacy single-device output so a user
  // who linked before registering any controller still sees their main light.
  if (controllers.length === 0) {
    return [primaryDevice({ userId, type: "main" })];
  }

  return controllers.map((c, index) => {
    if (index === 0) {
      // Primary controller — keep the legacy id + nickname set for continuity.
      return primaryDevice({
        userId,
        type: "main",
        controllerId: c.id,
        controllerIp: c.ip,
      });
    }

    // Additional controllers — own device, own name, no shared nicknames.
    const deviceName = c.name ?? `Controller ${index + 1}`;
    return {
      id: `controller-${c.id}`,
      type: "action.devices.types.LIGHT",
      traits: LIGHT_TRAITS,
      name: {
        name: deviceName,
        defaultNames: [deviceName],
      },
      willReportState: true,
      roomHint: "Outside",
      deviceInfo: { ...DEVICE_INFO },
      customData: {
        userId,
        type: "controller",
        controllerId: c.id,
        controllerIp: c.ip,
      },
    };
  });
}

/**
 * Resolve the user's saved scenes as Smart Home SCENE devices.
 * Mirrors handleGoogleSync: reads /users/{uid}/scenes, skips type:"system".
 */
export async function resolveScenes(
  userId: string
): Promise<SmartHomeDevice[]> {
  const db = admin.firestore();

  const scenesSnap = await db
    .collection("users")
    .doc(userId)
    .collection("scenes")
    .get();

  const scenes: SmartHomeDevice[] = [];
  for (const doc of scenesSnap.docs) {
    const scene = doc.data();
    if (scene.type === "system") continue;
    const sceneName = typeof scene.name === "string" ? scene.name : "Scene";
    scenes.push({
      id: `scene-${doc.id}`,
      type: "action.devices.types.SCENE",
      traits: ["action.devices.traits.Scene"],
      name: {
        name: sceneName,
        defaultNames: [sceneName],
      },
      willReportState: false,
      attributes: { sceneReversible: false },
      customData: { userId, type: "scene", sceneId: doc.id },
    });
  }
  return scenes;
}
