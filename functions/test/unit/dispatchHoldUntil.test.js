// dispatchFireJobs × `holdUntil` (the end guarantee, #179) — the REAL dispatcher
// and sweeper ticks on the shared in-memory Firestore.
//
// An END job the planner wrote under `end_ignores_gate` carries `holdUntil`:
// the instant until which its command must stay pickable. The dispatcher sets
// the command's `expiresAt` there (the sweeper honours an explicit expiresAt,
// the bridge checks none), so a bridge that comes back an hour after the final
// finds the restore still waiting instead of an expired command and a job that
// ran out of budget. A job without the field is dispatched exactly as before.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runDispatchTick } = require("../../lib/dispatchFireJobs");
const { runSweepTick } = require("../../lib/sweepExpiredCommands");
const { FIRE_GRACE_MS } = require("../../lib/fireJobs");

const S = 1000;
const M = 60 * S;
const NOW = Date.UTC(2026, 9, 12, 3, 40, 0); // the final, 22:40 CDT
const UID = "u_hold";
const CTRL = "ctrl_hold";
const TEAM = "nfl_holdteam";
const EVENT = `gd_${TEAM}_9700001`;
const JOB = `users/${UID}/fire_jobs/${EVENT}_end`;
const CMD = (id) => `users/${UID}/commands/${id}`;

function world(job = {}) {
  const f = makeFakeFirestore({ now: NOW });
  f.put(`users/${UID}`, { owner_id: UID });
  f.put("bridge_registry/BR_HOLD_01", { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/controllers/${CTRL}`, { ip: "192.0.2.50" });
  f.put(`users/${UID}/game_day_autopilot/${TEAM}`, { enabled: true, sport: "nfl" });
  f.put(JOB, {
    eventId: EVENT, seq: "end", controllerId: CTRL,
    fireAt: f.ts(NOW - 10 * S), type: "applyJson", payload: '{"ps":1}',
    state: "scheduled", source: "game_day",
    retryUntil: f.ts(NOW + 90 * M),
    ...job,
  });
  return f;
}
const read = async (f, path) => (await f.db.doc(path).get()).data();
const at = async (f, t, fn) => { f.setNow(t); return fn(t); };

describe("holdUntil → the command's expiresAt", () => {
  test("with holdUntil the command expires at the hold, not 90 s after dispatch", async () => {
    const f = world({ holdUntil: f0ts(NOW + 90 * M) });
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const job = await read(f, JOB);
    expect(job.state).toBe("dispatched");
    const cmd = await read(f, CMD(job.commandId));
    expect(cmd.status).toBe("pending");
    expect(cmd.expiresAt.toMillis()).toBe(NOW + 90 * M);
  });

  test("without holdUntil: the 90-second grace, exactly as before", async () => {
    const f = world();
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const job = await read(f, JOB);
    const cmd = await read(f, CMD(job.commandId));
    expect(cmd.expiresAt.toMillis()).toBe(NOW + FIRE_GRACE_MS);
  });

  test("a hold already shorter than the grace changes nothing", async () => {
    const f = world({ holdUntil: f0ts(NOW + 30 * S) });
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const job = await read(f, JOB);
    expect((await read(f, CMD(job.commandId))).expiresAt.toMillis()).toBe(NOW + FIRE_GRACE_MS);
  });
});

describe("the sweeper never expires a held end command while its job is within budget", () => {
  test("silent bridge for 75 minutes: the command is still pending at every sweep, then completes when the bridge returns", async () => {
    const f = world({ holdUntil: f0ts(NOW + 90 * M) });
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const { commandId } = await read(f, JOB);
    for (const m of [3, 20, 45, 75]) {
      await at(f, NOW + m * M, (t) => runSweepTick(f.db, t));
      await at(f, NOW + m * M + S, (t) => runDispatchTick(f.db, t));
      expect((await read(f, CMD(commandId))).status).toBe("pending");
      expect((await read(f, JOB)).state).toBe("dispatched");
    }
    // The bridge is back and executes the waiting restore.
    f.patch(CMD(commandId), { status: "completed", completedAt: f.ts(NOW + 76 * M) });
    await at(f, NOW + 77 * M, (t) => runDispatchTick(f.db, t));
    const job = await read(f, JOB);
    expect(job.state).toBe("completed");
    expect(job.attempts).toBe(1);
  });

  test("past the hold the sweeper expires it, and the dispatcher reports the budget exhausted (the planner re-mints from there)", async () => {
    const f = world({ holdUntil: f0ts(NOW + 90 * M) });
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const { commandId } = await read(f, JOB);
    await at(f, NOW + 91 * M, (t) => runSweepTick(f.db, t));
    expect((await read(f, CMD(commandId))).status).toBe("expired");
    const r = await at(f, NOW + 92 * M, (t) => runDispatchTick(f.db, t));
    const job = await read(f, JOB);
    expect(job.state).toBe("expired");
    expect(job.retryVerdict).toBe("retry_budget_exhausted");
    expect(r.retried).toBe(0);
  });

  test("an unheld end (flag absent): expired by the sweeper after its grace and retried within the 15-minute budget, as before", async () => {
    const f = world({ retryUntil: f0ts(NOW + 15 * M) });
    await at(f, NOW, (t) => runDispatchTick(f.db, t));
    const { commandId } = await read(f, JOB);
    await at(f, NOW + 150 * S, (t) => runSweepTick(f.db, t));
    expect((await read(f, CMD(commandId))).status).toBe("expired");
    const r = await at(f, NOW + 180 * S, (t) => runDispatchTick(f.db, t));
    expect(r.retried).toBe(1);
    expect((await read(f, JOB)).state).toBe("scheduled");
  });
});

/** A Timestamp-like for seeding, without a fake instance in scope. */
function f0ts(ms) {
  return makeFakeFirestore({ now: ms }).ts(ms);
}
