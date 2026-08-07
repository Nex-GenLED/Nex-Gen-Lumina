/**
 * probeControllerHealth — S6 Part 1. The daily probe.
 *
 * Writes ONE `getInfo` command per controller per day, at a quiet hour. The
 * bridge picks it up on its 1 s poll, GETs /json/info from the controller, and
 * writes WLED's own response body into the command document's `result` field.
 * [collectControllerHealth] reads those back 15 minutes later.
 *
 * WHY getInfo AND NOT getState. Both are GETs and neither mutates the strip,
 * but /json/info carries the version, vid, LED count and rgbw flag — the fleet
 * signal that has never existed (audit/OFF_LAN_CAPABILITY.md §3.3) — while
 * /json/state carries only what the lights are doing right now, which the daily
 * probe has no use for. getInfo is also the exact command that demonstrated
 * this mechanism unprompted on 2026-08-05 (audit/BRIDGE_TRIAGE.md §0a).
 *
 * SAFETY: a probe is READ-ONLY on the device. It is a GET. It cannot change a
 * light, a preset, a timer or a config. This matters because
 * audit/COMMAND_SAFETY.md §4.2 imposes a standing constraint on anything routed
 * through a scheduled path — "never a state-mutating operation, where 'executed
 * 60 s late' is not equivalent to 'executed'". A GET satisfies that trivially,
 * which is why the cloud half of controller health is safe to schedule and the
 * app half (cfg digests) is not.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:probeControllerHealth
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { fireJobDocId } from "./commandSafety";
import {
  ControllerHealthRecord,
  PROBE_GRACE_MS,
  PROBE_SOURCE,
  PROBE_TYPE,
  hasInFlightCommand,
  resolveProbeTarget,
  shouldProbeToday,
} from "./controllerHealth";

// admin.initializeApp() is called in index.js — do not call again here.

/**
 * 09:15 UTC ≈ 04:15 US Central. Chosen for three reasons:
 *   - The command queue is empty; a probe must never compete with customer
 *     traffic (audit/SCHEDULING_ARCHITECTURE_V2.md §5's measured 30-32 s tail).
 *   - It does not collide with scheduledDataCleanup (04:00 UTC) or with the
 *     1-minute sweeper's steady state.
 *   - Controllers are mains-powered and always on, so "lights are off" is
 *     irrelevant to a GET.
 */
const PROBE_SCHEDULE = "15 9 * * *";

/** Hard ceiling per run. Far above the fleet (15 controllers); a runaway guard. */
const MAX_PROBES_PER_RUN = 2000;

/**
 * Write one probe for one controller. Returns what happened, for the run log.
 *
 * Every decision that could silently skip a controller returns a distinct
 * reason string. A probe pass that quietly covers 6 of 15 controllers and
 * reports success is precisely the failure mode this system exists to remove,
 * so the counts are reported per-reason and the totals must reconcile.
 */
export async function probeOneController(args: {
  db: admin.firestore.Firestore;
  uid: string;
  controllerId: string;
  controllerIp: string | null;
  totalControllersForUser: number;
  pendingCommands: Array<{ controllerId?: unknown; status?: unknown }>;
  nowMs: number;
}): Promise<{ written: boolean; reason: string }> {
  const { db, uid, controllerId, controllerIp, totalControllersForUser, pendingCommands, nowMs } =
    args;

  // ── Q3 backoff: a persistently dark controller drops to weekly ───────────
  // One extra read per controller per day (15/day at today's fleet). Cheap, and
  // it is what stops a permanently-dark controller costing a write every day
  // forever while still catching a repair inside a week.
  const healthSnap = await db
    .collection("users")
    .doc(uid)
    .collection("controller_health")
    .doc(controllerId)
    .get();
  const previous = healthSnap.exists
    ? (healthSnap.data() as Partial<ControllerHealthRecord>)
    : null;
  const due = shouldProbeToday(previous, nowMs);
  if (!due.probe) return { written: false, reason: due.reason };

  // ── One-in-flight-per-controller (audit/COMMAND_SAFETY.md §3.4) ──────────
  if (hasInFlightCommand(pendingCommands, controllerId)) {
    return { written: false, reason: "in_flight" };
  }

  // ── Targeting: omit vs server-resolve. See resolveProbeTarget's docstring ──
  const target = resolveProbeTarget({
    controllerId,
    controllerIp,
    totalControllersForUser,
  });
  if (target.targeting === null || target.controllerIp === null) {
    // No IP on the controller document. Refuse rather than fall back to the
    // bridge's paired IP, which the bench proved can be silently stale
    // (see resolveProbeTarget). A skipped probe is honest; a probe sent to a
    // stale address manufactures a false "controller unreachable" alert.
    return { written: false, reason: "unresolvable_target" };
  }

  const fireAtSeconds = Math.floor(nowMs / 1000);
  const docId = fireJobDocId(`health_${controllerId}`, fireAtSeconds);

  const payload: Record<string, unknown> = {
    type: PROBE_TYPE,
    // `payload` is unused by the bridge for a GET (it builds no body), but every
    // other writer sets it and the field's absence would be the odd one out.
    payload: "{}",
    controllerId,
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    // EXPLICIT, not inherited. V2 §4 Layer 2: expiresAt = fireAt + grace. The
    // 120 s DEFAULT_COMMAND_TTL_MS is sized for an app command with a user
    // waiting; a probe is a liveness measurement and a late one is worthless.
    expiresAt: admin.firestore.Timestamp.fromMillis(nowMs + PROBE_GRACE_MS),
    source: PROBE_SOURCE,
    webhookUrl: null,
  };

  // ALWAYS name the target, and always from the user's OWN controllers
  // subcollection — never client input. Safety here is provenance, not omission
  // (audit/COMMAND_SAFETY.md §1.3; and see resolveProbeTarget for why omission
  // was tried and abandoned).
  payload.controllerIp = target.controllerIp;

  const ref = db.collection("users").doc(uid).collection("commands").doc(docId);

  try {
    // .create() — NOT .set(). Fails with already-exists rather than overwriting,
    // so the write itself is the idempotency barrier and a retried invocation
    // cannot double-probe (commandSafety.fireJobDocId's contract).
    await ref.create(payload);
    return { written: true, reason: target.targeting };
  } catch (err) {
    const code = (err as { code?: unknown })?.code;
    // 6 / "already-exists" — a retry of this same tick. Treat as success: the
    // probe exists, which is the outcome we wanted.
    if (code === 6 || code === "already-exists") {
      return { written: false, reason: "already_exists_idempotent" };
    }
    throw err;
  }
}

export const probeControllerHealth = onSchedule(
  {
    schedule: PROBE_SCHEDULE,
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();

    const users = await db.collection("users").get();

    let controllersSeen = 0;
    let written = 0;
    const skipped: Record<string, number> = {};
    const errors: Array<{ uid: string; controllerId: string; reason: string }> = [];

    for (const userDoc of users.docs) {
      const uid = userDoc.id;

      const controllers = await db
        .collection("users")
        .doc(uid)
        .collection("controllers")
        .get();
      if (controllers.empty) continue;

      // One read per user, reused for every controller. `in` on a single field
      // uses the single-field auto-index — no composite index required.
      let pendingCommands: Array<{ controllerId?: unknown; status?: unknown }> = [];
      try {
        const snap = await db
          .collection("users")
          .doc(uid)
          .collection("commands")
          .where("status", "in", ["pending", "executing"])
          .get();
        pendingCommands = snap.docs.map(
          (d) => d.data() as { controllerId?: unknown; status?: unknown }
        );
      } catch (err) {
        // Fail CLOSED on the guard: if we cannot prove the queue is clear, do
        // not add to it. A missed probe is cheap; competing with a customer's
        // command is not.
        logger.warn(
          `probeControllerHealth: in-flight read failed for ${uid}; skipping user`,
          err
        );
        skipped.guard_read_failed = (skipped.guard_read_failed ?? 0) + controllers.size;
        continue;
      }

      for (const c of controllers.docs) {
        if (written >= MAX_PROBES_PER_RUN) break;
        controllersSeen++;
        const controllerId = c.id;
        const ipRaw = c.get("ip");
        const controllerIp = typeof ipRaw === "string" && ipRaw.length > 0 ? ipRaw : null;

        try {
          const res = await probeOneController({
            db,
            uid,
            controllerId,
            controllerIp,
            totalControllersForUser: controllers.size,
            pendingCommands,
            nowMs,
          });
          if (res.written) written++;
          else skipped[res.reason] = (skipped[res.reason] ?? 0) + 1;
        } catch (err) {
          errors.push({
            uid,
            controllerId,
            reason: err instanceof Error ? err.message : String(err),
          });
        }
      }
    }

    // Totals must reconcile: seen == written + skipped + errors. A pass that
    // covered less than it thought is the defect class this whole feature
    // exists to eliminate, so it is asserted in the log rather than assumed.
    const skippedTotal = Object.values(skipped).reduce((a, b) => a + b, 0);
    const reconciled = controllersSeen === written + skippedTotal + errors.length;

    logger.info(
      `probeControllerHealth: controllers=${controllersSeen} written=${written} ` +
        `skipped=${JSON.stringify(skipped)} errors=${errors.length} ` +
        `reconciled=${reconciled}`
    );
    if (!reconciled) {
      logger.error(
        "probeControllerHealth: COUNTS DO NOT RECONCILE — some controllers were " +
          "neither probed nor accounted for. Investigate before trusting the digest."
      );
    }
    if (errors.length > 0) {
      logger.error("probeControllerHealth: per-controller errors", errors);
    }
    if (written >= MAX_PROBES_PER_RUN) {
      logger.warn(
        `probeControllerHealth: hit the ${MAX_PROBES_PER_RUN}-probe cap; ` +
          "coverage was truncated this run."
      );
    }
  }
);
