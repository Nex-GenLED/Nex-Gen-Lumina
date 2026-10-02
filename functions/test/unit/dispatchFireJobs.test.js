// dispatchFireJobs — the REAL dispatcher tick on the shared in-memory
// Firestore. Outcomes are read back with plain .get()s on the production
// paths: users/{uid}/fire_jobs/{id} and users/{uid}/commands/{id}.
//
// A1/A3 (plan step A): an `executing` command older than 180 s no longer blocks
// a controller's fires; the dispatcher terminates it (guarded) before firing,
// so a controller never carries more than one non-terminal command; and a
// reconciled stuck command is named `stuck_executing` on the job.
//
// Runs against compiled lib/ — `npm run build` (npm test does it).

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runDispatchTick } = require("../../lib/dispatchFireJobs");
const { STUCK_EXECUTING_AFTER_MS, fireJobDocId } = require("../../lib/commandSafety");

const S = 1000;
const M = 60 * S;
const NOW = Date.UTC(2026, 9, 11, 17, 25, 0); // Sun 10-11, 12:25 CDT
const UID = "u_disp";
const CTRL = "ctrl_a";
const TEAM = "nfl_testteam";
const EVENT = `gd_${TEAM}_9000001`;
const JOB = (id) => `users/${UID}/fire_jobs/${id}`;
const CMD = (id) => `users/${UID}/commands/${id}`;
const START_PAYLOAD = '{"on":true,"bri":200,"seg":[{"id":0,"on":true,"fx":52,"sx":160,"ix":128,"col":[[1,2,3,0],[4,5,6,0]]}]}';

function world({ job = {}, commands = {}, now = NOW } = {}) {
  const f = makeFakeFirestore({ now });
  f.put(`users/${UID}`, { owner_id: UID });
  f.put(`users/${UID}/controllers/${CTRL}`, { ip: "192.0.2.10" });
  f.put(`users/${UID}/game_day_autopilot/${TEAM}`, { enabled: true, sport: "nfl" });
  f.put(JOB(`${EVENT}_start`), {
    eventId: EVENT,
    seq: "start",
    controllerId: CTRL,
    fireAt: f.ts(now - 10 * S),
    type: "applyJson",
    payload: START_PAYLOAD,
    state: "scheduled",
    source: "game_day",
    ...job,
  });
  for (const [id, data] of Object.entries(commands)) f.put(CMD(id), data);
  return f;
}
const appCmd = (status, ageMs, controllerId = CTRL) => ({
  type: "applyJson",
  payload: "{}",
  controllerId,
  status,
  createdAt: { toMillis: () => NOW - ageMs },
});
const tick = (f, t = f.now()) => runDispatchTick(f.db, t);
const read = async (f, path) => (await f.db.doc(path).get()).data();

describe("A1/A3: the in-flight guard and stuck claims", () => {
  test("a STUCK executing claim no longer blocks the fire — it is terminated first", async () => {
    const f = world({ commands: { old: appCmd("executing", STUCK_EXECUTING_AFTER_MS + 30 * S) } });
    const r = await tick(f);

    const job = await read(f, JOB(`${EVENT}_start`));
    expect(job.state).toBe("dispatched");
    expect(r.dispatched).toBe(1);
    expect(r.stuckCleared).toBe(1);

    const old = await read(f, CMD("old"));
    expect(old.status).toBe("failed");
    expect(old.error).toBe("stuck_executing");

    // The one non-terminal command for the controller is the fire itself.
    const live = (await f.db.collection(`users/${UID}/commands`).where("status", "in", ["pending", "executing"]).get()).docs;
    expect(live.map((d) => d.id)).toEqual([job.commandId]);
  });

  test("a LIVE executing claim (younger than 180 s) still blocks — transient, job stays scheduled", async () => {
    const f = world({ commands: { busy: appCmd("executing", 40 * S) } });
    const r = await tick(f);
    expect((await read(f, JOB(`${EVENT}_start`))).state).toBe("scheduled");
    expect(r.skippedTransient).toEqual({ in_flight: 1 });
    expect((await read(f, CMD("busy"))).status).toBe("executing");
  });

  test("an AGED PENDING command still blocks — the bridge could still run it, unordered", async () => {
    const f = world({ commands: { stale: appCmd("pending", 10 * M) } });
    const r = await tick(f);
    expect((await read(f, JOB(`${EVENT}_start`))).state).toBe("scheduled");
    expect(r.skippedTransient).toEqual({ in_flight: 1 });
    expect((await read(f, CMD("stale"))).status).toBe("pending"); // the sweeper owns pending
  });

  test("a stuck claim on ANOTHER controller is not the dispatcher's to clear", async () => {
    const f = world({ commands: { other: appCmd("executing", 10 * M, "ctrl_b") } });
    const r = await tick(f);
    expect((await read(f, JOB(`${EVENT}_start`))).state).toBe("dispatched");
    expect(r.stuckCleared).toBe(0);
    expect((await read(f, CMD("other"))).status).toBe("executing");
  });

  test("COMPLETED WINS at dispatch too: the bridge reports between the read and the clear", async () => {
    const f = world({ commands: { old: appCmd("executing", 10 * M) } });
    // The first write of the dispatch phase is the guarded clear.
    f.beforeNextWrite(() => f.patch(CMD("old"), { status: "completed", completedAt: f.ts(NOW) }));
    const r = await tick(f);
    expect((await read(f, CMD("old"))).status).toBe("completed");
    expect(r.stuckCleared).toBe(0);
    // Completed is terminal, so the fire still goes out.
    expect((await read(f, JOB(`${EVENT}_start`))).state).toBe("dispatched");
  });

  test("reconcile names a stuck command `stuck_executing` on the job", async () => {
    const cmdId = fireJobDocId(`${EVENT}_start`, Math.floor((NOW - 5 * M) / 1000));
    const f = world({
      job: { state: "dispatched", commandId: cmdId, fireAt: { toMillis: () => NOW - 5 * M } },
      commands: { [cmdId]: { ...appCmd("failed", 5 * M), error: "stuck_executing" } },
    });
    await tick(f);
    const job = await read(f, JOB(`${EVENT}_start`));
    expect(job.outcome).toBe("stuck_executing");
    expect(job.commandError).toBe("stuck_executing");
    expect(job.latencyMs).toBeNull(); // the bridge never finished it
  });

  test("reconcile of a normal completion is unchanged: outcome completed, empty error", async () => {
    const cmdId = fireJobDocId(`${EVENT}_start`, Math.floor((NOW - 2 * M) / 1000));
    const f = world({
      job: { state: "dispatched", commandId: cmdId, fireAt: { toMillis: () => NOW - 2 * M } },
      commands: {
        [cmdId]: {
          ...appCmd("completed", 2 * M),
          completedAt: { toMillis: () => NOW - 2 * M + 1951 },
          // A stuck text that survived a late completion (the bridge's success
          // PATCH carries no `error` in its mask) must not leak into the job.
          error: "stuck_executing",
        },
      },
    });
    await tick(f);
    const job = await read(f, JOB(`${EVENT}_start`));
    expect(job.state).toBe("completed");
    expect(job.outcome).toBe("completed");
    expect(job.commandError).toBe("");
    expect(job.latencyMs).toBe(1951);
  });
});
