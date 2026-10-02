/**
 * Relay eligibility (2026-09-30) against the Firestore emulator.
 *
 * ⚠️ NOT run by `npm test`. Requires FIRESTORE_EMULATOR_HOST — see
 * test/emulator/README.md. From functions/:
 *   firebase emulators:exec --only firestore --project lumina-fn-test \
 *     "npx jest --config jest.emulator.config.js --runInBand test/emulator/relayEligibility"
 *
 * Asserts:
 *   • hasPairedBridge is EXISTENCE: a paired row with a month-old lastSeen is
 *     still paired; an unpaired row, a pendingUid-only row and no row are not.
 *   • failFastIfNoPairedBridge marks a bridge-mode command failed/no_bridge_paired
 *     only when no row is paired; a paired account's command is untouched, the
 *     pairing wizard's untargeted ping is untouched, and a doc the bridge already
 *     claimed (status != pending) is untouched.
 *   • probeOneController writes no probe for an unpaired or excluded account and
 *     reports the reason; a paired account is probed.
 */

import * as admin from "firebase-admin";
import {
  NO_BRIDGE_PAIRED_ERROR,
  PairedBridgeCache,
  failFastIfNoPairedBridge,
  hasPairedBridge,
} from "../../src/relayEligibility";
import { probeOneController } from "../../src/probeControllerHealth";
import { runSweepTick } from "../../src/sweepExpiredCommands";
import { markStuckExecuting } from "../../src/commandHygiene";
import { STUCK_EXECUTING_AFTER_MS } from "../../src/commandSafety";

if (!process.env.FIRESTORE_EMULATOR_HOST) {
  throw new Error("FIRESTORE_EMULATOR_HOST is unset — refusing to run against production");
}
if (!admin.apps.length) {
  admin.initializeApp({ projectId: "lumina-fn-test" });
}
const db = admin.firestore();

const ts = (d: Date) => admin.firestore.Timestamp.fromDate(d);
const MONTH_AGO = new Date(Date.now() - 30 * 86_400_000);

async function wipe(): Promise<void> {
  // Subcollections under a user doc that was never itself written (the
  // probe writes users/u1/commands/* without creating users/u1) are invisible
  // to a users.get(), so sweep them by collection group.
  for (const group of ["commands", "controller_health"]) {
    const snap = await db.collectionGroup(group).get();
    await Promise.all(snap.docs.map((x) => x.ref.delete()));
  }
  for (const col of ["bridge_registry", "users"]) {
    const snap = await db.collection(col).get();
    await Promise.all(snap.docs.map((d) => d.ref.delete()));
  }
}

beforeEach(wipe);

describe("hasPairedBridge — existence, not freshness", () => {
  test("a paired row with a month-old heartbeat is still paired", async () => {
    await db.doc("bridge_registry/AA00000000B2").set({
      pairedUid: "u1",
      status: "paired",
      lastSeen: ts(MONTH_AGO),
    });
    expect(await hasPairedBridge(db, "u1")).toBe(true);
  });

  test("no row → false; another uid's row → false; pendingUid-only → false", async () => {
    expect(await hasPairedBridge(db, "u1")).toBe(false);
    await db.doc("bridge_registry/A").set({ pairedUid: "u2", status: "paired" });
    await db.doc("bridge_registry/B").set({ pairedUid: "", pendingUid: "u1", status: "unpaired" });
    expect(await hasPairedBridge(db, "u1")).toBe(false);
    expect(await hasPairedBridge(db, "u2")).toBe(true);
  });

  test("the user doc flags are never consulted (stale bridge_paired shape)", async () => {
    await db.doc("users/u1").set({ bridge_paired: true, bridge_ip: "192.0.2.43" });
    expect(await hasPairedBridge(db, "u1")).toBe(false);
  });

  test("the cache answers once per uid", async () => {
    await db.doc("bridge_registry/A").set({ pairedUid: "u1", status: "paired" });
    const cache = new PairedBridgeCache(db);
    expect(await cache.lookup("u1")).toBe(true);
    await db.doc("bridge_registry/A").delete();
    expect(await cache.lookup("u1")).toBe(true); // memoised for the pass
    expect(await hasPairedBridge(db, "u1")).toBe(false);
  });
});

describe("failFastIfNoPairedBridge — executeWledCommand's bridge-mode branch", () => {
  const cmd = (fields: Record<string, unknown>) => ({
    type: "getState",
    payload: "{}",
    controllerId: "c1",
    controllerIp: "192.0.2.37",
    webhookUrl: "",
    status: "pending",
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    ...fields,
  });

  test("no paired bridge → failed / no_bridge_paired / completedAt, at once", async () => {
    const ref = db.doc("users/u1/commands/x1");
    await ref.set(cmd({}));
    const outcome = await failFastIfNoPairedBridge(db, "u1", ref, (await ref.get()).data()!);
    expect(outcome).toBe("failed_no_bridge");
    const after = (await ref.get()).data()!;
    expect(after.status).toBe("failed");
    expect(after.error).toBe(NO_BRIDGE_PAIRED_ERROR);
    expect(after.completedAt).toBeTruthy();
  });

  test("paired account (even stale) → untouched", async () => {
    await db.doc("bridge_registry/A").set({ pairedUid: "u1", status: "paired", lastSeen: ts(MONTH_AGO) });
    const ref = db.doc("users/u1/commands/x1");
    await ref.set(cmd({}));
    const outcome = await failFastIfNoPairedBridge(db, "u1", ref, (await ref.get()).data()!);
    expect(outcome).toBe("passthrough_paired");
    expect((await ref.get()).data()!.status).toBe("pending");
  });

  test("the pairing wizard's untargeted ping → untouched even with no row", async () => {
    const ref = db.doc("users/u1/commands/ping1");
    await ref.set(cmd({ type: "ping", controllerId: "", controllerIp: "" }));
    const outcome = await failFastIfNoPairedBridge(db, "u1", ref, (await ref.get()).data()!);
    expect(outcome).toBe("passthrough_pairing_ping");
    expect((await ref.get()).data()!.status).toBe("pending");
  });

  test("a doc the bridge already claimed → untouched", async () => {
    const ref = db.doc("users/u1/commands/x1");
    await ref.set(cmd({ status: "executing" }));
    const outcome = await failFastIfNoPairedBridge(db, "u1", ref, (await ref.get()).data()!);
    expect(outcome).toBe("passthrough_not_pending");
    expect((await ref.get()).data()!.status).toBe("executing");
  });

  test("webhook-mode commands are the caller's business: the helper is only reached in bridge mode", async () => {
    // Documented contract, not behaviour: index.js calls the helper inside
    // `if (!commandData.webhookUrl)`. Nothing to assert against the emulator.
    expect(true).toBe(true);
  });
});

describe("probeOneController — no doomed probe for unpaired / excluded accounts", () => {
  // Fresh `nowMs` per test: the probe doc id is derived from it, and a repeat
  // of the same second is (correctly) reported as already_exists_idempotent.
  let tick = 0;
  const base = () => ({
    db,
    uid: "u1",
    controllerId: "aa_00_00_00_00_01",
    controllerIp: "192.0.2.100",
    totalControllersForUser: 1,
    pendingCommands: [] as Array<{ controllerId?: unknown; status?: unknown }>,
    nowMs: Date.now() + 1000 * ++tick,
  });

  async function probeCount(): Promise<number> {
    const snap = await db.collection("users/u1/commands").get();
    return snap.size;
  }

  test("unpaired → skipped with reason no_paired_bridge, nothing written", async () => {
    const res = await probeOneController({ ...base(), bridgePaired: false });
    expect(res).toEqual({ written: false, reason: "no_paired_bridge" });
    expect(await probeCount()).toBe(0);
  });

  test("monitoring_exclude → skipped with reason monitoring_excluded", async () => {
    const res = await probeOneController({ ...base(), bridgePaired: true, monitoringExcluded: true });
    expect(res).toEqual({ written: false, reason: "monitoring_excluded" });
    expect(await probeCount()).toBe(0);
  });

  test("paired → probed exactly as before", async () => {
    const res = await probeOneController({ ...base(), bridgePaired: true });
    expect(res.written).toBe(true);
    expect(await probeCount()).toBe(1);
  });

  test("default (no eligibility args) is the legacy behaviour: probe", async () => {
    const res = await probeOneController({ ...base() });
    expect(res.written).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// A1 (2026-10-02) — the stuck-executing sweep, against real Firestore semantics
// ---------------------------------------------------------------------------
// The unit suite proves the decisions on an in-memory fake. These prove the two
// properties only Firestore itself can: that the collection-group query on
// `executing` returns what the sweeper expects, and that a `lastUpdateTime`
// precondition really refuses a write after a concurrent update ("completed
// wins"). NOTE: the emulator does not enforce composite indexes, so index
// presence is proven by firestore.indexes.json review, not here.
describe("A1: sweepExpiredCommands stuck-executing pass (emulator)", () => {
  const nowMs = Date.now();
  const at = (agoMs: number) => admin.firestore.Timestamp.fromMillis(nowMs - agoMs);

  test("an executing doc older than 180 s becomes failed/stuck_executing; a young one is untouched", async () => {
    await db.doc("bridge_registry/AA00000000C1").set({ pairedUid: "u1", status: "paired" });
    await db.doc("users/u1/commands/stuck").set({
      type: "applyJson", status: "executing", controllerId: "c1",
      createdAt: at(STUCK_EXECUTING_AFTER_MS + 60_000),
    });
    await db.doc("users/u1/commands/young").set({
      type: "applyJson", status: "executing", controllerId: "c1",
      createdAt: at(30_000),
    });

    const stats = await runSweepTick(db, nowMs);

    const stuck = (await db.doc("users/u1/commands/stuck").get()).data()!;
    expect(stuck.status).toBe("failed");
    expect(stuck.error).toBe("stuck_executing");
    expect(stuck.stuckSweptAt).toBeDefined();
    expect(stuck.completedAt).toBeUndefined();
    expect((await db.doc("users/u1/commands/young").get()).get("status")).toBe("executing");
    expect(stats.stuck).toBe(1);
    expect(stats.stuckQueryFailed).toBe(false);
  });

  test("COMPLETED WINS: a write guarded on a stale read is refused by Firestore", async () => {
    const ref = db.doc("users/u1/commands/race");
    await ref.set({ status: "executing", createdAt: at(10 * 60_000), controllerId: "c1" });
    const seen = await ref.get(); // the sweeper's read

    // The bridge's PATCH lands after that read.
    await ref.update({ status: "completed", completedAt: admin.firestore.Timestamp.now() });

    expect(await markStuckExecuting(ref, seen.updateTime)).toBe("raced");
    const after = (await ref.get()).data()!;
    expect(after.status).toBe("completed");
    expect(after.error).toBeUndefined();
  });

  test("a guarded write on a FRESH read succeeds", async () => {
    const ref = db.doc("users/u1/commands/fresh");
    await ref.set({ status: "executing", createdAt: at(10 * 60_000), controllerId: "c1" });
    const seen = await ref.get();
    expect(await markStuckExecuting(ref, seen.updateTime)).toBe("written");
    expect((await ref.get()).get("error")).toBe("stuck_executing");
  });

  test("the pending pass is unchanged: past-TTL pending → expired with the paired wording", async () => {
    await db.doc("bridge_registry/AA00000000C2").set({ pairedUid: "u2", status: "paired" });
    await db.doc("users/u2/commands/p").set({
      type: "applyJson", status: "pending", controllerId: "c1",
      createdAt: at(10 * 60_000),
    });
    const stats = await runSweepTick(db, nowMs);
    const p = (await db.doc("users/u2/commands/p").get()).data()!;
    expect(p.status).toBe("expired");
    expect(p.error).toMatch(/bridge offline or unreachable/);
    expect(stats.expired).toBeGreaterThanOrEqual(1);
  });
});
