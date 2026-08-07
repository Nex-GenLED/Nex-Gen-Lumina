/**
 * collectControllerHealth — S6 Parts 2, 3 and 4.
 *
 * Runs 15 minutes after [probeControllerHealth]. Reads each controller's most
 * recent probe command back, folds the outcome into
 * /users/{uid}/controller_health/{controllerId}, evaluates the fleet alerts, and
 * pushes a digest.
 *
 * WHY A SECOND SCHEDULED PASS AND NOT A FIRESTORE TRIGGER
 * -------------------------------------------------------
 * The obvious design is onDocumentWritten on users/{uid}/commands/{commandId},
 * reacting when the bridge flips a probe to completed. It was rejected: that
 * trigger fires on EVERY command write fleet-wide. Steve Stegall alone has 2,854
 * command documents and each one is written 2-3 times (pending → executing →
 * completed), so the trigger would burn tens of thousands of invocations a month
 * to observe ~15 documents a day. A scheduled read-back costs one query per user
 * per day and is trivially idempotent.
 *
 * The 15-minute gap is safe by construction: a probe expires at +90 s and the
 * sweeper flips it within one more minute, so by T+15 every probe is terminal
 * (completed / failed / expired). Nothing is read while still in flight.
 *
 * Deployment:
 *   cd functions
 *   npm run build
 *   firebase deploy --only functions:collectControllerHealth,functions:backfillControllerHealth
 */

import { onSchedule } from "firebase-functions/v2/scheduler";
import { onCall, HttpsError } from "firebase-functions/v2/https";
import { defineString } from "firebase-functions/params";
import { logger } from "firebase-functions";
import * as admin from "firebase-admin";
import { sendEmail } from "./messaging-helpers";
import {
  BridgePresence,
  ControllerHealthRecord,
  HealthAlert,
  PROBE_SOURCE,
  REGISTRY_FRESH_MINUTES,
  RosterEntry,
  ProbeCommandDoc,
  buildRoster,
  classifyProbe,
  evaluateHealthAlerts,
  foldProbeIntoHealth,
  parseWledInfo,
  resolveProbeTarget,
  shouldSendDigest,
} from "./controllerHealth";

// admin.initializeApp() is called in index.js — do not call again here.

/** 09:30 UTC — 15 minutes after the 09:15 probe pass. */
const COLLECT_SCHEDULE = "30 9 * * *";

/**
 * Where the digest goes. REQUIRED for the alert half to do anything.
 *
 * Absence is treated as an ERROR, not a silent no-op: an alerting system that
 * quietly sends nowhere is strictly worse than none, because it manufactures
 * false confidence. This repo has already shipped one scheduled routine that
 * never ran and went unnoticed for months (scheduledDataCleanup — see
 * audit/COMMAND_SAFETY.md D2), which is precisely the mistake not to repeat.
 */
const digestTo = defineString("FLEET_HEALTH_DIGEST_TO");

const HEALTH_COLLECTION = "controller_health";
/** Top-level daily snapshot, for scripting and history. */
const FLEET_SNAPSHOT_COLLECTION = "fleet_health";

// ---------------------------------------------------------------------------
// Shared collection logic (used by the schedule AND the backfill)
// ---------------------------------------------------------------------------

interface CollectedRow {
  uid: string;
  email: string | null;
  displayName: string | null;
  record: ControllerHealthRecord;
}

interface RegistryRow {
  deviceId: string;
  status: string | null;
  pairedUid: string;
  pendingUid: string;
  lastSeenMs: number | null;
  firmwareVersion: string | null;
  email: string | null;
  displayName: string | null;
}

const toMs = (t: unknown): number | null => {
  const v = t as { toMillis?: () => number } | null | undefined;
  return v && typeof v.toMillis === "function" ? v.toMillis() : null;
};

/** Read every bridge_registry row once, resolving the paired account's identity. */
async function readRegistry(
  db: admin.firestore.Firestore,
  identity: Map<string, { email: string | null; displayName: string | null }>
): Promise<RegistryRow[]> {
  const snap = await db.collection("bridge_registry").get();
  return snap.docs.map((d) => {
    const pairedUid = typeof d.get("pairedUid") === "string" ? d.get("pairedUid") : "";
    const who = identity.get(pairedUid);
    return {
      deviceId: d.id,
      status: typeof d.get("status") === "string" ? d.get("status") : null,
      pairedUid,
      pendingUid: typeof d.get("pendingUid") === "string" ? d.get("pendingUid") : "",
      lastSeenMs: toMs(d.get("lastSeen")),
      firmwareVersion:
        typeof d.get("firmwareVersion") === "string" ? d.get("firmwareVersion") : null,
      email: who?.email ?? null,
      displayName: who?.displayName ?? null,
    };
  });
}

/**
 * Fold the newest probe for every controller into its health document.
 *
 * `seedOnly` (the backfill path, Part 4) skips the probe read entirely and
 * records only what is knowable WITHOUT a probe — bridge liveness from the
 * registry. That gives the first alert run a real baseline instead of treating
 * a three-week-dark bridge as a brand-new controller with zero failures.
 */
export async function collectAll(
  db: admin.firestore.Firestore,
  nowMs: number,
  opts: { seedOnly: boolean; dryRun: boolean; onlyUid?: string }
): Promise<{
  rows: CollectedRow[];
  registry: RegistryRow[];
  knownUids: Set<string>;
  stats: Record<string, number>;
}> {
  const users = await db.collection("users").get();
  const knownUids = new Set(users.docs.map((u) => u.id));

  const identity = new Map<string, { email: string | null; displayName: string | null }>();
  for (const u of users.docs) {
    identity.set(u.id, {
      // snake_case — the user doc's convention. A camelCase read returns null
      // for every account in the fleet (audit/BRIDGE_TRIAGE.md, Caveat 1).
      displayName: typeof u.get("display_name") === "string" ? u.get("display_name") : null,
      email: typeof u.get("email") === "string" ? u.get("email") : null,
    });
  }

  // ── Identity of record is Firebase AUTH, not the user document ──────────
  //
  // The seed dry run on 2026-08-06 surfaced a real disagreement: one customer's
  // `users/{uid}.email` differs from their Auth email (…@gmail.com vs
  // …1@gmail.com). The digest is a CALL LIST, so it must carry the address that
  // actually reaches the person — which is the Auth record, the thing they sign
  // in with and the thing password resets go to. The doc field is a copy and can
  // drift.
  //
  // Batched: getUsers takes up to 100 identifiers per call, so this is a handful
  // of round-trips for the whole fleet, not one per user. A lookup failure
  // degrades to the doc email rather than throwing — a digest with a slightly
  // stale address beats no digest.
  const uids = Array.from(identity.keys());
  for (let i = 0; i < uids.length; i += 100) {
    const chunk = uids.slice(i, i + 100).map((uid) => ({ uid }));
    try {
      const res = await admin.auth().getUsers(chunk);
      for (const rec of res.users) {
        const prev = identity.get(rec.uid);
        if (!prev) continue;
        if (rec.email && rec.email !== prev.email) {
          logger.info(
            `collectControllerHealth: identity mismatch for ${rec.uid} — ` +
              `auth=${rec.email} doc=${prev.email ?? "(none)"}; using auth`
          );
        }
        identity.set(rec.uid, {
          displayName: prev.displayName,
          email: rec.email ?? prev.email,
        });
      }
    } catch (err) {
      logger.warn("collectControllerHealth: auth identity lookup failed", err);
    }
  }

  const registry = await readRegistry(db, identity);
  const registryByUid = new Map<string, RegistryRow>();
  for (const r of registry) {
    if (!r.pairedUid) continue;
    // A uid with two paired rows (the 2026-08-05 Brooke Rozenberg shape: a live
    // replacement alongside a superseded unit) must resolve to the LIVE one, or
    // the health record would inherit the orphan's 22-day-old heartbeat and
    // report a healthy account as dark.
    const prev = registryByUid.get(r.pairedUid);
    if (!prev || (r.lastSeenMs ?? 0) > (prev.lastSeenMs ?? 0)) {
      registryByUid.set(r.pairedUid, r);
    }
  }

  const rows: CollectedRow[] = [];
  const stats: Record<string, number> = {
    controllers: 0,
    probed: 0,
    missing: 0,
    seeded: 0,
    written: 0,
  };

  for (const userDoc of users.docs) {
    const uid = userDoc.id;
    // onlyUid scopes a collection pass to a single account. Used by the bench
    // verification harness so an end-to-end test cannot touch customer data,
    // and available for targeted re-collection after a repair.
    if (opts.onlyUid && uid !== opts.onlyUid) continue;
    const controllers = await db
      .collection("users")
      .doc(uid)
      .collection("controllers")
      .get();
    if (controllers.empty) continue;

    // Newest probe per controller. Equality on a single field → auto-indexed;
    // 7-day retention keeps this to a handful of documents per controller.
    const probesByController = new Map<string, ProbeCommandDoc & { createdMs: number }>();
    if (!opts.seedOnly) {
      const probeSnap = await db
        .collection("users")
        .doc(uid)
        .collection("commands")
        .where("source", "==", PROBE_SOURCE)
        .get();
      for (const p of probeSnap.docs) {
        const cid = typeof p.get("controllerId") === "string" ? p.get("controllerId") : "";
        const createdMs = toMs(p.get("createdAt")) ?? 0;
        const prev = probesByController.get(cid);
        if (!prev || createdMs > prev.createdMs) {
          probesByController.set(cid, {
            status: p.get("status"),
            result: p.get("result"),
            error: p.get("error"),
            createdAt: p.get("createdAt"),
            completedAt: p.get("completedAt"),
            controllerId: cid,
            controllerIp: p.get("controllerIp"),
            createdMs,
          });
        }
      }
    }

    const bridgeRow = registryByUid.get(uid) ?? null;

    for (const c of controllers.docs) {
      stats.controllers++;
      const controllerId = c.id;
      const healthRef = db
        .collection("users")
        .doc(uid)
        .collection(HEALTH_COLLECTION)
        .doc(controllerId);

      const prevSnap = await healthRef.get();
      const previous = prevSnap.exists
        ? (prevSnap.data() as Partial<ControllerHealthRecord>)
        : null;

      const probe = probesByController.get(controllerId) ?? null;
      const classification = classifyProbe(probe);
      if (classification.outcome === "missing") stats.missing++;
      else stats.probed++;

      const info = parseWledInfo(probe?.result);

      const ipRaw = c.get("ip");
      const targeting = resolveProbeTarget({
        controllerId,
        controllerIp: typeof ipRaw === "string" ? ipRaw : null,
        totalControllersForUser: controllers.size,
      }).targeting;

      // Q1 — bridge presence. `never` requires BOTH no registry row AND no
      // bridge_status/current that has ever existed. The second half matters:
      // bridge_status/current is written only once a bridge has adopted this
      // uid, so its `createTime` is the definitive "a bridge once reported here"
      // signal — the same one the 2026-08-05 triage relied on. An account with a
      // deleted registry row but a historic bridge_status is `silent`, not
      // `never`, and must not have its alerts suppressed.
      const bsSnap = await db
        .collection("users")
        .doc(uid)
        .collection("bridge_status")
        .doc("current")
        .get();
      const everReported = bsSnap.exists;
      const bridgeFresh =
        bridgeRow?.lastSeenMs != null &&
        nowMs - bridgeRow.lastSeenMs <= REGISTRY_FRESH_MINUTES * 60_000;
      const bridgePresence: BridgePresence = bridgeFresh
        ? "live"
        : bridgeRow || everReported
          ? "silent"
          : "never";

      const record = foldProbeIntoHealth({
        controllerId,
        previous,
        classification,
        info,
        probedAtMs: nowMs,
        bridge: {
          deviceId: bridgeRow?.deviceId ?? null,
          lastSeenMs: bridgeRow?.lastSeenMs ?? null,
          firmwareVersion: bridgeRow?.firmwareVersion ?? null,
          status: bridgeRow?.status ?? null,
        },
        targeting,
        bridgePresence,
      });

      // SEED MODE (Part 4): there is no probe, so a `missing` outcome must not
      // masquerade as a measurement. Record the bridge facts and the baseline
      // failure count derived from registry staleness, and leave the probe
      // fields null so the first real probe is unambiguously the first.
      if (opts.seedOnly) {
        record.lastProbeAt = null;
        record.lastProbeOutcome = null;
        record.lastProbeBlame = null;
        const silentMs =
          bridgeRow?.lastSeenMs == null ? null : nowMs - bridgeRow.lastSeenMs;
        // A bridge silent for over a day is already known-bad; seeding 1 makes
        // it a WARNING on the first digest and an ALERT after one failed probe,
        // rather than starting it at zero and hiding a 21-day outage for two
        // more days.
        const knownBad = silentMs !== null && silentMs > 86_400_000;
        record.consecutiveFailures = knownBad ? 1 : 0;
        // Seed the DURATION too, from the bridge's last heartbeat — the best
        // available estimate of when it went dark. Without this the first
        // digest reports a known 23-day outage as "duration unknown", which is
        // exactly the baseline the seed exists to avoid.
        record.firstFailureAt = knownBad ? bridgeRow!.lastSeenMs : null;
        stats.seeded++;
      }

      rows.push({
        uid,
        email: identity.get(uid)?.email ?? null,
        displayName: identity.get(uid)?.displayName ?? null,
        record,
      });

      if (!opts.dryRun) {
        await healthRef.set(
          { ...record, updatedAt: admin.firestore.FieldValue.serverTimestamp() },
          { merge: true }
        );
        stats.written++;
      }
    }
  }

  return { rows, registry, knownUids, stats };
}

// ---------------------------------------------------------------------------
// Digest rendering
// ---------------------------------------------------------------------------

function renderDigest(
  alerts: HealthAlert[],
  rows: CollectedRow[],
  roster: { never: RosterEntry[]; silent: RosterEntry[] },
  nowIso: string
): { subject: string; html: string; text: string } {
  const acts = alerts.filter((a) => a.severity === "alert");
  const warns = alerts.filter((a) => a.severity === "warn");

  const reachable = rows.filter((r) => r.record.lastProbeOutcome === "completed").length;
  const subject =
    acts.length > 0
      ? `Lumina fleet: ${acts.length} alert(s), ${warns.length} warning(s)`
      : warns.length > 0
        ? `Lumina fleet: ${warns.length} warning(s)`
        : "Lumina fleet: all clear";

  const line = (a: HealthAlert) => {
    const who = a.email ?? a.displayName ?? a.uid ?? "(unattributed)";
    const dev = a.deviceId ? ` [${a.deviceId}]` : "";
    return `${a.severity.toUpperCase()} · ${a.kind} · ${who}${dev} — ${a.detail}`;
  };

  const textLines = [
    `Lumina controller health — ${nowIso}`,
    `Probed OK: ${reachable}/${rows.length} controllers`,
    "",
  ];
  if (acts.length) {
    textLines.push("ALERTS — act on these:");
    acts.forEach((a) => textLines.push("  " + line(a)));
    textLines.push("");
  }
  if (warns.length) {
    textLines.push("WARNINGS — first miss, watch:");
    warns.forEach((a) => textLines.push("  " + line(a)));
    textLines.push("");
  }
  if (!acts.length && !warns.length) {
    textLines.push("No alerts. Every probed controller answered.");
    textLines.push("");
    textLines.push(
      "(This is the weekly all-clear. If these stop arriving entirely, the " +
        "monitor itself has failed — that is what the all-clear is for.)"
    );
    textLines.push("");
  }

  // ── Q1 roster — the only place `never` accounts appear ──────────────────
  const rosterLine = (e: RosterEntry) =>
    `${e.who} · ${e.controllerId}` +
    (e.presence === "never"
      ? " — no bridge on record (never reported)"
      : ` — bridge ${e.deviceId ?? "?"} silent ${e.silentDays ?? "?"}d`);

  if (roster.never.length || roster.silent.length) {
    textLines.push(
      `ROSTER — ${roster.never.length + roster.silent.length} controller(s) ` +
        "without a live bridge:"
    );
    if (roster.never.length) {
      textLines.push(
        `  NEVER HAD A BRIDGE (${roster.never.length}) — alerts suppressed; ` +
          "sales/records question, not a support call:"
      );
      roster.never.forEach((e) => textLines.push("    " + rosterLine(e)));
    }
    if (roster.silent.length) {
      textLines.push(
        `  HAD ONE, NOW SILENT (${roster.silent.length}) — these are the ` +
          "support calls, and they alert above:"
      );
      roster.silent.forEach((e) => textLines.push("    " + rosterLine(e)));
    }
    textLines.push("");
  }

  const esc = (s: string) =>
    s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
  const section = (title: string, list: HealthAlert[], colour: string) =>
    list.length
      ? `<h3 style="color:${colour};margin:16px 0 6px">${title}</h3><ul>` +
        list.map((a) => `<li>${esc(line(a))}</li>`).join("") +
        "</ul>"
      : "";

  const html =
    `<div style="font-family:system-ui,-apple-system,sans-serif;font-size:14px">` +
    `<h2 style="margin:0 0 4px">Lumina controller health</h2>` +
    `<p style="color:#666;margin:0 0 12px">${esc(nowIso)} · probed OK ` +
    `${reachable}/${rows.length}</p>` +
    section("Alerts — act on these", acts, "#b00020") +
    section("Warnings — first miss, watch", warns, "#a06000") +
    (acts.length || warns.length
      ? ""
      : `<p>No alerts. Every probed controller answered.</p>` +
        `<p style="color:#666">This is the weekly all-clear. If these stop ` +
        `arriving entirely, the monitor itself has failed — that is what the ` +
        `all-clear is for.</p>`) +
    (roster.never.length
      ? `<h3 style="margin:16px 0 6px">Never had a bridge (${roster.never.length}) — ` +
        `alerts suppressed; sales/records question</h3><ul>` +
        roster.never.map((e) => `<li>${esc(rosterLine(e))}</li>`).join("") +
        "</ul>"
      : "") +
    (roster.silent.length
      ? `<h3 style="margin:16px 0 6px">Had one, now silent (${roster.silent.length}) — ` +
        `these are the support calls</h3><ul>` +
        roster.silent.map((e) => `<li>${esc(rosterLine(e))}</li>`).join("") +
        "</ul>"
      : "") +
    `</div>`;

  return { subject, html, text: textLines.join("\n") };
}

// ---------------------------------------------------------------------------
// The scheduled collector
// ---------------------------------------------------------------------------

export const collectControllerHealth = onSchedule(
  {
    schedule: COLLECT_SCHEDULE,
    timeZone: "UTC",
    region: "us-central1",
    timeoutSeconds: 540,
    memory: "256MiB",
  },
  async () => {
    const db = admin.firestore();
    const nowMs = Date.now();
    const nowIso = new Date(nowMs).toISOString();

    const { rows, registry, knownUids, stats } = await collectAll(db, nowMs, {
      seedOnly: false,
      dryRun: false,
    });

    const alerts = evaluateHealthAlerts({
      health: rows,
      registry: registry.map((r) => ({
        deviceId: r.deviceId,
        status: r.status,
        pairedUid: r.pairedUid,
        pendingUid: r.pendingUid,
        lastSeenMs: r.lastSeenMs,
        email: r.email,
        displayName: r.displayName,
      })),
      knownUids,
      nowMs,
    });

    const roster = buildRoster(rows, nowMs);

    // Daily snapshot — the pull surface. Scriptable, historical, and the thing
    // a future in-app dealer dashboard would read.
    const dayKey = nowIso.slice(0, 10);
    await db
      .collection(FLEET_SNAPSHOT_COLLECTION)
      .doc(dayKey)
      .set({
        generatedAt: admin.firestore.FieldValue.serverTimestamp(),
        controllers: rows.length,
        probedOk: rows.filter((r) => r.record.lastProbeOutcome === "completed").length,
        alertCount: alerts.filter((a) => a.severity === "alert").length,
        warnCount: alerts.filter((a) => a.severity === "warn").length,
        alerts: alerts.map((a) => ({ ...a })),
        roster: {
          neverHadBridge: roster.never.map((e) => ({ ...e })),
          hadOneNowSilent: roster.silent.map((e) => ({ ...e })),
        },
        stats,
      });

    logger.info(
      `collectControllerHealth: ${JSON.stringify(stats)} alerts=${alerts.length}`
    );

    // ── The push surface ──────────────────────────────────────────────────
    const utcDay = new Date(nowMs).getUTCDay();
    if (!shouldSendDigest(alerts.length, utcDay)) {
      logger.info("collectControllerHealth: nothing to report, not a Monday — no digest");
      return;
    }

    const to = digestTo.value();
    if (!to || to.trim().length === 0) {
      // LOUD, deliberately. See the digestTo docstring.
      logger.error(
        "collectControllerHealth: FLEET_HEALTH_DIGEST_TO is not configured — " +
          `${alerts.length} alert(s) were computed and SENT NOWHERE. The ` +
          `snapshot at ${FLEET_SNAPSHOT_COLLECTION}/${dayKey} still holds them.`
      );
      return;
    }

    const { subject, html, text } = renderDigest(alerts, rows, roster, nowIso);
    try {
      await sendEmail({ to, subject, htmlBody: html, textBody: text });
      logger.info(`collectControllerHealth: digest sent to ${to} — ${subject}`);
    } catch (err) {
      // Never throw: a failed email must not fail the collection, whose writes
      // already landed. The snapshot doc is the durable record either way.
      logger.error("collectControllerHealth: digest send failed", err);
    }
  }
);

// ---------------------------------------------------------------------------
// Part 4 — backfill / seed
// ---------------------------------------------------------------------------

/**
 * Seed controller_health from currently-knowable state so the first alert run
 * has a baseline rather than treating a three-week-dark bridge as a brand-new
 * controller.
 *
 * Derived LIVE from bridge_registry and the controllers subcollections — NOT
 * hardcoded from the 2026-08-05 triage. Hardcoded findings rot the moment a
 * bridge is repaired, and one was repaired the same evening the triage was
 * written (The Iron Reserve, audit/BRIDGE_TRIAGE.md §0a). Re-deriving means the
 * seed is correct whenever it is run.
 *
 * Auth: `admin` custom claim, same convention as backfillControllerIps. Note
 * that zero of the fleet's auth users hold that claim (COMMAND_SAFETY D3), so
 * invoking this requires minting a short-lived custom token — see
 * scripts/_run_backfill_controller_ips.js for the established pattern.
 *
 * Contract:
 *   request.data: { dryRun?: boolean }   // defaults to FALSE
 */
export const backfillControllerHealth = onCall(
  { region: "us-central1", timeoutSeconds: 540, memory: "512MiB" },
  async (request) => {
    if (!request.auth) throw new HttpsError("unauthenticated", "Sign in required.");
    if (request.auth.token.admin !== true) {
      throw new HttpsError(
        "permission-denied",
        "backfillControllerHealth requires the admin custom claim."
      );
    }

    const dryRun = request.data?.dryRun === true;
    const db = admin.firestore();
    const nowMs = Date.now();

    const { rows, registry, knownUids, stats } = await collectAll(db, nowMs, {
      seedOnly: true,
      dryRun,
    });

    const alerts = evaluateHealthAlerts({
      health: rows,
      registry: registry.map((r) => ({
        deviceId: r.deviceId,
        status: r.status,
        pairedUid: r.pairedUid,
        pendingUid: r.pendingUid,
        lastSeenMs: r.lastSeenMs,
        email: r.email,
        displayName: r.displayName,
      })),
      knownUids,
      nowMs,
    });

    const summary = {
      dryRun,
      ...stats,
      alertCount: alerts.filter((a) => a.severity === "alert").length,
      warnCount: alerts.filter((a) => a.severity === "warn").length,
      alerts: alerts.map((a) => ({
        kind: a.kind,
        severity: a.severity,
        who: a.email ?? a.displayName ?? a.uid,
        deviceId: a.deviceId,
        ageDays: a.ageDays,
        detail: a.detail,
      })),
    };
    logger.info("backfillControllerHealth: complete", summary);
    return summary;
  }
);
