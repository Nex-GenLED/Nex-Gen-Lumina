// The end guarantee, END TO END — the REAL planner, dispatcher and sweeper ticks
// on the shared in-memory Firestore, with the bridge modelled by the test.
//
// Written from the 2026-10-07 review of 65cb3e4, each scenario first as the
// failure the review found:
//   1. #178 was not fixed end to end. The sweep's end keeps eventId
//      gd_<slug>_<id>, so the dispatcher's #99 config gate re-read the deleted
//      team and skipped it `config_missing_or_disabled`: seven skipped jobs,
//      zero commands, house lit. The fix exempts an end the guarantee wrote.
//   2. An end can fire INTO THE NEXT GAME: with the 90-minute budget, an end
//      whose attempts fail retryably through a live bridge is still being
//      retried when a second team's start on the same controller completes,
//      and its next attempt restores base over that start (the review saw it
//      land 3 minutes after the second start). The fix skips an end, terminal
//      and named, when a later start on the same controller COMPLETED since
//      the end was first due — at dispatch, at retry, at the sweep and at
//      re-mint.
//   4. The teardown rule (a scheduled end is never retracted) is unconditional.
//      Pinned: without the guarantee, a deleted team's scheduled end is skipped
//      `config_missing_or_disabled` at the dispatcher and produces no command.
//   5. (delta review of 31751b2) A start merely DISPATCHED must never close the
//      earlier end: dispatched into a bridge that is away, its command expires
//      and nothing was lit, yet the planner had closed the session for good.
//      Supersession needs the later start completed; a dispatched one defers
//      the end transiently through the one-in-flight guard (S1, S2, S3 below).
//
// Times: Sunday 2026-10-11 → Monday 2026-10-12 UTC. All ids synthetic; the
// controller address is RFC 5737.

jest.mock("../../lib/espnClient", () => ({
  fetchTeamGame: jest.fn(async () => null),
  fetchEventById: jest.fn(async () => ({ kind: "error" })),
  fetchCollegeSlateGame: jest.fn(async () => ({ game: null, onSlate: false, complete: false })),
  fetchCollegeTeamDivision: jest.fn(async () => ({ kind: "error" })),
}));

const { logger } = require("firebase-functions");
const { fetchTeamGame, fetchEventById } = require("../../lib/espnClient");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runPlannerTick } = require("../../lib/planGameDayFires");
const { runDispatchTick } = require("../../lib/dispatchFireJobs");
const { runSweepTick } = require("../../lib/sweepExpiredCommands");

const SEC = 1000;
const MIN = 60 * SEC;
const H = 60 * MIN;
const KICK = Date.parse("2026-10-12T00:15:00Z"); // team A, 19:15 CDT
const FIRE = KICK - 30 * MIN; // 23:45Z
const T0 = FIRE - 5 * H - 45 * MIN; // 18:00Z
const FINAL1 = KICK + 3 * H + 20 * MIN; // 03:35Z
const FINAL2 = FINAL1 + 5 * MIN; // 03:40Z
const B_KICK = KICK + 4 * H + 15 * MIN; // 04:30Z — the second game, same controller
const B_FIRE = B_KICK - 30 * MIN; // 04:00Z
const HOLD_END = FINAL2 + 90 * MIN; // 05:10Z — A's end command is held pickable until here
const B_KICK_LATE = KICK + 5 * H + 15 * MIN; // 05:30Z — the second game when it kicks off after the hold
const B_FIRE_LATE = B_KICK_LATE - 30 * MIN; // 05:00Z

const UID = "u_e2e";
const CTRL = "ctrl_e2e";
const IP = "192.0.2.70";
const A = { slug: "nfl_ateam", espn: "25", game: "9900001", sport: "nfl" };
const B = { slug: "mlb_bteam", espn: "88", game: "9900002", sport: "mlb" };
const EVENT = (t) => `gd_${t.slug}_${t.game}`;
const ARMED = { forcePolicy: { enabled: true, allowlist: [UID] } };
const FLAG = { ...ARMED, forceFlags: { endIgnoresGate: true } };

const USER = `users/${UID}`;
const BEAT = `users/${UID}/bridge_status/current`;
const CONFIG = (t) => `users/${UID}/game_day_autopilot/${t.slug}`;
const CONTROLLER = `users/${UID}/controllers/${CTRL}`;
const JOB = (id) => `users/${UID}/fire_jobs/${id}`;
const SESSION = (t) => `users/${UID}/game_day_sessions/${EVENT(t)}`;
const BASE_ON = '{"ps":1}';

const teamConfig = (t) => ({
  enabled: true, team_slug: t.slug, team_name: `Team ${t.slug}`, sport: t.sport, espn_team_id: t.espn,
  primary_color: 0xff102030, secondary_color: 0xff405060, effect_id: 52, speed: 160,
  intensity: 128, brightness: 200,
});

function world({ second = false } = {}) {
  const f = makeFakeFirestore({ now: T0 - H });
  f.put(USER, {
    owner_id: UID, time_zone: "America/Chicago", latitude: 39.0, longitude: -95.0,
    ...(second ? { game_day_team_priority: [A.slug, B.slug] } : {}),
  });
  f.put(CONTROLLER, {
    ip: IP, participating_channels: [0, 1], participating_channels_device_ids: [0, 1],
    participating_channels_at: f.ts(T0 - 2 * 86_400_000), base_ladder_asserts_segments: true,
  });
  f.put(CONFIG(A), teamConfig(A));
  if (second) f.put(CONFIG(B), teamConfig(B));
  f.put(`bridge_registry/BR_${UID}`, { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/debug_errors/d1`, {
    context: "routing_decisions", app_version: "2.5.10+114", timestamp: f.ts(T0 - 2 * H),
  });
  return f;
}

/** ESPN: team A in `aState`; team B (if listed) in `bState`. By-id answers the same. */
function espn(aState = "scheduled", bState = "scheduled", bKick = B_KICK) {
  const shape = (t, kick, s) => ({
    gameId: t.game, startMs: kick, homeTeamId: t.espn, awayTeamId: "0",
    isFinal: s === "final", isInProgress: s === "live",
    statusName: s === "final" ? "STATUS_FINAL" : s === "live" ? "STATUS_IN_PROGRESS" : "STATUS_SCHEDULED",
    statusState: s === "final" ? "post" : s === "live" ? "in" : "pre",
  });
  const games = { [A.espn]: shape(A, KICK, aState), [B.espn]: shape(B, bKick, bState) };
  const byId = { [A.game]: games[A.espn], [B.game]: games[B.espn] };
  fetchTeamGame.mockImplementation(async (_s, id) => games[id] ?? null);
  fetchEventById.mockImplementation(async (_s, id) => (byId[id] ? { kind: "found", game: byId[id] } : { kind: "error" }));
}

function beat(f, ms) {
  const was = f.now();
  f.setNow(ms);
  f.put(BEAT, { uptime: 1, version: "1.2" });
  f.setNow(was);
}
const at = async (f, ms, fn) => { f.setNow(ms); return fn(ms); };
const plan = (f, ms, opts) => { beat(f, ms - 20 * SEC); return at(f, ms, (t) => runPlannerTick(f.db, t, opts)); };
const dispatch = (f, ms) => at(f, ms, (t) => runDispatchTick(f.db, t));
const sweep = (f, ms) => at(f, ms, (t) => runSweepTick(f.db, t));
const read = async (f, path) => (await f.db.doc(path).get()).data();
/** Every command the dispatcher wrote for a fire job, oldest first. */
async function fireCommands(f, jobId) {
  const q = await f.db.collection(`users/${UID}/commands`).get();
  return q.docs.filter((d) => d.get("fireJobId") === jobId).map((d) => ({ id: d.id, ...d.data() }));
}
/** The bridge ran it. */
const bridgeCompletes = (f, cmdId, ms) => f.patch(`users/${UID}/commands/${cmdId}`, { status: "completed", completedAt: f.ts(ms) });
/** The bridge is up but WLED did not answer: a retryable failure. */
const bridgeFails = (f, cmdId, ms) =>
  f.patch(`users/${UID}/commands/${cmdId}`, { status: "failed", error: "ERROR: HTTP -1", completedAt: f.ts(ms) });

async function completeProbes(f) {
  const q = await f.db.collection(`users/${UID}/commands`).where("source", "==", "gameday_preflight").get();
  for (const p of q.docs) f.patch(p.ref.path, { status: "completed" });
}

/** Team A's start: planned, dispatched, run by the bridge, reconciled. */
async function aStartFired(f, opts) {
  espn("scheduled");
  await plan(f, T0, opts);
  await completeProbes(f);
  await dispatch(f, FIRE + 10 * SEC);
  const [c] = await fireCommands(f, `${EVENT(A)}_start`);
  expect(c.status).toBe("pending");
  bridgeCompletes(f, c.id, FIRE + 12 * SEC);
  await dispatch(f, FIRE + 70 * SEC);
  expect((await read(f, JOB(`${EVENT(A)}_start`))).state).toBe("completed");
}

let warn;
beforeEach(() => {
  fetchTeamGame.mockReset();
  fetchEventById.mockReset();
  espn();
  warn = jest.spyOn(logger, "warn").mockImplementation(() => {});
});
afterEach(() => warn.mockRestore());

// ---------------------------------------------------------------------------
describe("#178 end to end: a deleted or disabled team's fired start gets its end COMMAND to the bridge", () => {
  test.each([
    ["deleted", async (f) => { await f.db.doc(CONFIG(A)).delete(); }],
    ["disabled", (f) => { f.patch(CONFIG(A), { enabled: false }); }],
  ])("team %s after the start fired (flag on): the swept end is dispatched, the bridge runs it, the job completes", async (_name, breakFn) => {
    const f = world();
    await aStartFired(f, FLAG);
    await breakFn(f);
    espn("final");
    await plan(f, FINAL1, FLAG);
    const r = await plan(f, FINAL2, FLAG);
    expect(r.endsSwept).toBe(1);
    const end = await read(f, JOB(`${EVENT(A)}_end`));
    expect(end).toMatchObject({ state: "scheduled", payload: BASE_ON, controllerId: CTRL });

    // THE REVIEW'S FAILURE: the dispatcher re-read the team config and skipped it.
    const d = await dispatch(f, FINAL2 + 30 * SEC);
    const afterDispatch = await read(f, JOB(`${EVENT(A)}_end`));
    expect(afterDispatch.state).toBe("dispatched");
    expect(afterDispatch).not.toHaveProperty("skipReason");
    expect(d.skippedTerminal).toEqual({});
    const [cmd] = await fireCommands(f, `${EVENT(A)}_end`);
    expect(cmd).toMatchObject({ status: "pending", payload: BASE_ON, controllerId: CTRL, controllerIp: IP, type: "applyJson" });
    expect(cmd.expiresAt.toMillis()).toBe(end.holdUntil.toMillis());

    // The sweeper leaves the held command alone; the bridge runs it; the job completes.
    await sweep(f, FINAL2 + 5 * MIN);
    expect((await fireCommands(f, `${EVENT(A)}_end`))[0].status).toBe("pending");
    bridgeCompletes(f, cmd.id, FINAL2 + 6 * MIN);
    await dispatch(f, FINAL2 + 7 * MIN);
    expect((await read(f, JOB(`${EVENT(A)}_end`))).state).toBe("completed");
    // …and nothing is re-minted afterwards.
    const later = await plan(f, FINAL2 + 20 * MIN, FLAG);
    expect(later).not.toHaveProperty("endsReminted");
    expect(await read(f, JOB(`${EVENT(A)}_end_r1`))).toBeUndefined();
  });

  test("the re-minted end of a deleted team is dispatched too", async () => {
    const f = world();
    await aStartFired(f, FLAG);
    await f.db.doc(CONFIG(A)).delete();
    espn("final");
    await plan(f, FINAL1, FLAG);
    await plan(f, FINAL2, FLAG);
    f.patch(JOB(`${EVENT(A)}_end`), { state: "expired" }); // the first job died without a restore
    await plan(f, FINAL2 + 15 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT(A)}_end_r1`))).toMatchObject({ state: "scheduled" });
    await dispatch(f, FINAL2 + 16 * MIN);
    expect((await read(f, JOB(`${EVENT(A)}_end_r1`))).state).toBe("dispatched");
    expect(await fireCommands(f, `${EVENT(A)}_end_r1`)).toHaveLength(1);
  });
});

// ---------------------------------------------------------------------------
describe("the unconditional teardown rule, pinned (flag ABSENT)", () => {
  test("a deleted team's scheduled end is skipped config_missing_or_disabled at the dispatcher and produces zero commands", async () => {
    const f = world();
    await aStartFired(f, ARMED);
    espn("final");
    await plan(f, FINAL1, ARMED);
    await plan(f, FINAL2, ARMED); // the loop's own end, gate armed, flag off
    const end = await read(f, JOB(`${EVENT(A)}_end`));
    expect(end).toMatchObject({ state: "scheduled" });
    expect(end).not.toHaveProperty("endGuarantee");
    // The team is deleted before the dispatcher's next minute. The teardown no
    // longer retracts a scheduled end (its one unconditional change), so the
    // row is still `scheduled` when the dispatcher reads it…
    await f.db.doc(CONFIG(A)).delete();
    const d = await dispatch(f, FINAL2 + 30 * SEC);
    // …and the #99 config gate skips it, exactly as the review found.
    expect(await read(f, JOB(`${EVENT(A)}_end`))).toMatchObject({ state: "skipped", skipReason: "config_missing_or_disabled" });
    expect(d.skippedTerminal).toEqual({ config_missing_or_disabled: 1 });
    expect(await fireCommands(f, `${EVENT(A)}_end`)).toHaveLength(0);
  });
});

// ---------------------------------------------------------------------------
describe("an end never fires into the next game", () => {
  /**
   * The reproduction. Team A's end is dispatched at its final; the bridge is up
   * but WLED does not answer, so the command fails retryably and the dispatcher
   * reschedules it (90-minute budget). Team B's start on the SAME controller
   * then fires and completes. A's rescheduled end comes due three minutes later.
   */
  async function reproduction(f) {
    espn("scheduled", "scheduled");
    await aStartFired(f, FLAG);
    espn("final", "scheduled");
    await plan(f, FINAL1, FLAG);
    await plan(f, FINAL2, FLAG);
    // B's start was minted on that tick (A's window closed): its P6 probe is
    // answered, as a live bridge answers it in seconds.
    await completeProbes(f);
    const endId = `${EVENT(A)}_end`;
    expect(await read(f, JOB(endId))).toMatchObject({ state: "scheduled", payload: BASE_ON });
    expect(await read(f, JOB(endId))).not.toHaveProperty("handoffTo");

    await dispatch(f, FINAL2 + 30 * SEC);
    const [c1] = await fireCommands(f, endId);
    bridgeFails(f, c1.id, FINAL2 + 40 * SEC);
    const r = await dispatch(f, FINAL2 + 90 * SEC); // reconcile: retryable → rescheduled
    expect(r.retried).toBe(1);
    expect((await read(f, JOB(endId))).state).toBe("scheduled");
    // A few backoffs later the next attempt is due just after B's start.
    f.patch(JOB(endId), { fireAt: f.ts(B_FIRE + 2 * MIN) });

    // Team B's start: minted when A's window has closed, dispatched, run.
    espn("final", "scheduled");
    await plan(f, B_FIRE + 20 * SEC, FLAG);
    const bStart = `${EVENT(B)}_start`;
    expect(await read(f, JOB(bStart))).toMatchObject({ state: "scheduled" });
    await dispatch(f, B_FIRE + 40 * SEC);
    const [bc] = await fireCommands(f, bStart);
    expect(bc.status).toBe("pending");
    bridgeCompletes(f, bc.id, B_FIRE + 50 * SEC);
    await dispatch(f, B_FIRE + 100 * SEC);
    expect((await read(f, JOB(bStart))).state).toBe("completed");
    return endId;
  }

  test("THE REVIEW'S FAILURE, fixed: the rescheduled end is skipped as superseded, and no base restore lands on team B", async () => {
    const f = world({ second: true });
    const endId = await reproduction(f);

    const d = await dispatch(f, B_FIRE + 3 * MIN); // A's end comes due
    const end = await read(f, JOB(endId));
    expect(end.state).toBe("skipped");
    expect(end.skipReason).toBe("superseded_by_later_start");
    expect(end.supersededBy).toBe(`${EVENT(B)}_start`);
    expect(d.skippedTerminal).toEqual({ superseded_by_later_start: 1 });
    // Exactly the one failed attempt: nothing was written after B's start.
    const cmds = await fireCommands(f, endId);
    expect(cmds).toHaveLength(1);
    expect(cmds[0].status).toBe("failed");

    // …and the planner does not re-mint it either: the session is closed as superseded.
    const p = await plan(f, B_FIRE + 10 * MIN, FLAG);
    expect(p).not.toHaveProperty("endsReminted");
    expect(await read(f, JOB(`${endId}_r1`))).toBeUndefined();
    expect(p.logRows.find((x) => x.action === "skip" && x.reason === "end_remint_skipped:superseded_by_later_start")).toMatchObject({ eventId: EVENT(A) });
    expect((await read(f, SESSION(A))).endSuperseded).toBe(true);
    const again = await plan(f, B_FIRE + 25 * MIN, FLAG);
    expect(again.logRows.find((x) => x.reason === "end_remint_skipped:superseded_by_later_start")).toBeUndefined(); // once
  });

  test("the retry path too: a retryable failure after B's start is not rescheduled but skipped", async () => {
    const f = world({ second: true });
    espn("scheduled", "scheduled");
    await aStartFired(f, FLAG);
    espn("final", "scheduled");
    await plan(f, FINAL1, FLAG);
    await plan(f, FINAL2, FLAG);
    await completeProbes(f);
    const endId = `${EVENT(A)}_end`;
    await dispatch(f, FINAL2 + 30 * SEC);
    const [c1] = await fireCommands(f, endId);
    expect(c1.status).toBe("pending");
    // The command is still pending (held) when B's start fires and completes…
    await plan(f, B_FIRE + 20 * SEC, FLAG);
    await completeProbes(f);
    const bStart = `${EVENT(B)}_start`;
    // (A's held end command is in flight on the controller: B waits behind it,
    // the right order; so the bridge runs A's end FIRST — and it fails.)
    bridgeFails(f, c1.id, B_FIRE + 30 * SEC);
    await dispatch(f, B_FIRE + 40 * SEC);
    // Reconcile saw the failure; B's start is dispatched the same tick or the next.
    let bc = (await fireCommands(f, bStart))[0];
    if (!bc) { await dispatch(f, B_FIRE + 100 * SEC); bc = (await fireCommands(f, bStart))[0]; }
    bridgeCompletes(f, bc.id, B_FIRE + 110 * SEC);
    await dispatch(f, B_FIRE + 160 * SEC);
    expect((await read(f, JOB(bStart))).state).toBe("completed");
    // A's end: it was rescheduled before B completed (allowed), but its next
    // attempt, due now, is superseded.
    f.patch(JOB(endId), { fireAt: f.ts(B_FIRE + 3 * MIN) });
    await dispatch(f, B_FIRE + 3 * MIN + 10 * SEC);
    expect(await read(f, JOB(endId))).toMatchObject({ state: "skipped", skipReason: "superseded_by_later_start" });
    expect(await fireCommands(f, endId)).toHaveLength(1);
  });

  test("the normal case: no later start, the retried end completes on its second attempt", async () => {
    const f = world();
    await aStartFired(f, FLAG);
    espn("final");
    await plan(f, FINAL1, FLAG);
    await plan(f, FINAL2, FLAG);
    const endId = `${EVENT(A)}_end`;
    await dispatch(f, FINAL2 + 30 * SEC);
    const [c1] = await fireCommands(f, endId);
    bridgeFails(f, c1.id, FINAL2 + 40 * SEC);
    await dispatch(f, FINAL2 + 90 * SEC);
    expect((await read(f, JOB(endId))).state).toBe("scheduled");
    await dispatch(f, FINAL2 + 3 * MIN);
    const cmds = await fireCommands(f, endId);
    expect(cmds).toHaveLength(2);
    bridgeCompletes(f, cmds[1].id, FINAL2 + 3 * MIN + 10 * SEC);
    await dispatch(f, FINAL2 + 4 * MIN);
    expect((await read(f, JOB(endId)))).toMatchObject({ state: "completed", attempts: 2 });
    const p = await plan(f, FINAL2 + 10 * MIN, FLAG);
    expect(p).not.toHaveProperty("endsReminted");
  });

  test("a swept end is not minted at all when a later start already lit the controller since the final was seen", async () => {
    const f = world({ second: true });
    espn("scheduled", "scheduled");
    await aStartFired(f, FLAG);
    // A's team is deleted; its final is seen; B's start fires before the sweep
    // gets to end A (the by-id lookup is down for a while).
    await f.db.doc(CONFIG(A)).delete();
    espn("final", "scheduled");
    fetchEventById.mockImplementation(async () => ({ kind: "error" }));
    await plan(f, FINAL1, FLAG); // A: clock-only, not final
    await plan(f, B_FIRE + 20 * SEC, FLAG); // B's start mints (A's window: no final seen, cap not reached)
    await completeProbes(f);
    const bStart = `${EVENT(B)}_start`;
    expect(await read(f, JOB(bStart))).toMatchObject({ state: "scheduled" });
    await dispatch(f, B_FIRE + 40 * SEC);
    const [bc] = await fireCommands(f, bStart);
    bridgeCompletes(f, bc.id, B_FIRE + 50 * SEC);
    await dispatch(f, B_FIRE + 100 * SEC);
    // ESPN is back and says A is final. The sweep must NOT restore base over B.
    espn("final", "scheduled");
    await plan(f, B_FIRE + 5 * MIN, FLAG);
    const p = await plan(f, B_FIRE + 10 * MIN, FLAG);
    expect(await read(f, JOB(`${EVENT(A)}_end`))).toBeUndefined();
    expect(p).not.toHaveProperty("endsSwept");
    expect(p.logRows.find((x) => x.reason === "end_sweep_skipped:superseded_by_later_start")).toMatchObject({ eventId: EVENT(A) });
    expect((await read(f, SESSION(A))).endSuperseded).toBe(true);
  });
});

// ---------------------------------------------------------------------------
describe("a dispatched start that never lights the house does not close the earlier end (delta review of 31751b2)", () => {
  /**
   * The finding: `startSupersedesEnd` counted a start in state `dispatched` as
   * owning the house. The dispatcher's use was recoverable (the next re-mint
   * re-checks); the planner's was not — the re-mint path wrote
   * `endSuperseded: true`, the sweep path wrote it with `endFiredAt`, and every
   * later tick skipped the session on that field. A start dispatched while the
   * bridge is away, whose command then expires, lit nothing: team A's colours
   * stayed up with no restore pending when the bridge returned. Supersession
   * now needs the later start COMPLETED; a merely dispatched one defers the end
   * transiently through the one-in-flight guard.
   */
  const CMD = (id) => `users/${UID}/commands/${id}`;

  test("S1 — re-mint path: A's held end expires, B dispatches into the free slot while the bridge is away, B expires; A's end is re-minted and runs when the bridge returns", async () => {
    const f = world({ second: true });
    espn("scheduled", "scheduled", B_KICK_LATE);
    await aStartFired(f, FLAG);
    espn("final", "scheduled", B_KICK_LATE);
    await plan(f, FINAL1, FLAG);
    await plan(f, FINAL2, FLAG);
    await completeProbes(f);
    const endId = `${EVENT(A)}_end`;
    const bStart = `${EVENT(B)}_start`;
    expect(await read(f, JOB(endId))).toMatchObject({ state: "scheduled", endGuarantee: true });
    expect(await read(f, JOB(bStart))).toMatchObject({ state: "scheduled" });

    // A's end is dispatched and held to 05:10Z. From here the bridge is away.
    await dispatch(f, FINAL2 + 30 * SEC);
    const [c1] = await fireCommands(f, endId);
    expect(c1.status).toBe("pending");
    expect(c1.expiresAt.toMillis()).toBe(HOLD_END);

    // B's start falls due at 05:00Z behind the held end: deferred, not dispatched.
    await sweep(f, B_FIRE_LATE);
    let d = await dispatch(f, B_FIRE_LATE + 10 * SEC);
    expect(d.skippedTransient).toMatchObject({ in_flight: 1 });
    expect(await fireCommands(f, bStart)).toHaveLength(0);

    // 05:10Z: the hold runs out. The sweeper expires A's command, the dispatcher
    // terminalises A's end (budget exhausted) and dispatches B into the free slot.
    await sweep(f, HOLD_END + 30 * SEC);
    expect((await read(f, CMD(c1.id))).status).toBe("expired");
    await dispatch(f, HOLD_END + 60 * SEC);
    expect((await read(f, JOB(endId))).state).toBe("expired");
    const [bc] = await fireCommands(f, bStart);
    expect(bc.status).toBe("pending");
    expect((await read(f, JOB(bStart))).state).toBe("dispatched");

    // The planner's next tick: A's end is terminal. B has NOT lit the house —
    // its command is pending on a bridge that is away. A must not be closed.
    const p = await plan(f, HOLD_END + 5 * MIN, FLAG);
    expect((await read(f, SESSION(A))).endSuperseded).not.toBe(true);
    expect(p.logRows.find((x) => x.reason === "end_remint_skipped:superseded_by_later_start")).toBeUndefined();
    expect(await read(f, JOB(`${endId}_r1`))).toMatchObject({ state: "scheduled", endGuarantee: true });

    // B runs out of its budget (kickoff 05:30Z) with the bridge still away: it
    // never lit anything. A's re-minted end takes the free slot and is held.
    await sweep(f, B_KICK_LATE + 2 * MIN);
    await dispatch(f, B_KICK_LATE + 3 * MIN);
    expect((await read(f, JOB(bStart))).state).toBe("expired");
    const [rc] = await fireCommands(f, `${endId}_r1`);
    expect(rc.status).toBe("pending");

    // The bridge returns: a restore is waiting, and it runs.
    bridgeCompletes(f, rc.id, B_KICK_LATE + 30 * MIN);
    await dispatch(f, B_KICK_LATE + 31 * MIN);
    expect((await read(f, JOB(`${endId}_r1`))).state).toBe("completed");
    const again = await plan(f, B_KICK_LATE + 35 * MIN, FLAG);
    expect(again).not.toHaveProperty("endsReminted");
    expect((await read(f, SESSION(A))).endSuperseded).not.toBe(true);
  });

  test("S2 — sweep path: A's team deleted, ESPN by-id down, B dispatched while the bridge is away; ESPN returns and the sweep decides A's end while B is dispatched; A's end runs when the bridge returns", async () => {
    const f = world({ second: true });
    espn("scheduled", "scheduled");
    await aStartFired(f, FLAG);
    await f.db.doc(CONFIG(A)).delete();
    espn("final", "scheduled");
    fetchEventById.mockImplementation(async () => ({ kind: "error" }));
    await plan(f, FINAL1, FLAG); // A: clock-only, not final
    await plan(f, B_FIRE + 20 * SEC, FLAG); // B's start mints
    await completeProbes(f);
    const bStart = `${EVENT(B)}_start`;
    await dispatch(f, B_FIRE + 40 * SEC);
    const [bc] = await fireCommands(f, bStart);
    expect(bc.status).toBe("pending"); // the bridge is away: nothing runs it

    // ESPN is back and says A is final (confirmed on the second poll). The
    // sweep decides A's end while B is merely dispatched: A must not be
    // closed, its end must be written.
    espn("final", "scheduled");
    await plan(f, B_FIRE + 5 * MIN, FLAG);
    const p = await plan(f, B_FIRE + 10 * MIN, FLAG);
    const endId = `${EVENT(A)}_end`;
    expect((await read(f, SESSION(A))).endSuperseded).not.toBe(true);
    expect(p.logRows.find((x) => x.reason === "end_sweep_skipped:superseded_by_later_start")).toBeUndefined();
    expect(await read(f, JOB(endId))).toMatchObject({ state: "scheduled", endGuarantee: true, endVia: "session_sweep" });

    // A's end waits behind B's pending command, transiently.
    let d = await dispatch(f, B_FIRE + 11 * MIN);
    expect(d.skippedTransient).toMatchObject({ in_flight: 1 });
    expect(await fireCommands(f, endId)).toHaveLength(0);

    // B runs out of its budget (kickoff 04:30Z) with the bridge still away:
    // expired, never lit. A's end is dispatched into the free slot and held.
    await sweep(f, B_KICK + 2 * MIN);
    await dispatch(f, B_KICK + 3 * MIN);
    expect((await read(f, JOB(bStart))).state).toBe("expired");
    const [ac] = await fireCommands(f, endId);
    expect(ac.status).toBe("pending");
    expect(ac.expiresAt.toMillis()).toBe(B_FIRE + 10 * MIN + 90 * MIN); // held to the sweep's mint + 90 min

    // The bridge returns: the restore is pending, and it runs.
    bridgeCompletes(f, ac.id, B_KICK + 30 * MIN);
    await dispatch(f, B_KICK + 31 * MIN);
    expect((await read(f, JOB(endId))).state).toBe("completed");
    const again = await plan(f, B_KICK + 35 * MIN, FLAG);
    expect(again).not.toHaveProperty("endsReminted");
    expect((await read(f, SESSION(A))).endSuperseded).not.toBe(true);
  });

  test("S3 — control, sweep path: B merely dispatched at the sweep, then the bridge returns and COMPLETES B first; A's swept end is closed at dispatch as superseded by B, and the planner closes the session instead of re-minting", async () => {
    const f = world({ second: true });
    espn("scheduled", "scheduled");
    await aStartFired(f, FLAG);
    await f.db.doc(CONFIG(A)).delete();
    espn("final", "scheduled");
    fetchEventById.mockImplementation(async () => ({ kind: "error" }));
    await plan(f, FINAL1, FLAG);
    await plan(f, B_FIRE + 20 * SEC, FLAG);
    await completeProbes(f);
    const bStart = `${EVENT(B)}_start`;
    await dispatch(f, B_FIRE + 40 * SEC);
    const [bc] = await fireCommands(f, bStart);
    espn("final", "scheduled");
    await plan(f, B_FIRE + 5 * MIN, FLAG);
    await plan(f, B_FIRE + 10 * MIN, FLAG); // the final, confirmed: the sweep writes A's end
    const endId = `${EVENT(A)}_end`;
    expect(await read(f, JOB(endId))).toMatchObject({ state: "scheduled" });

    // The bridge returns and runs B's start first (it was pending first): B lit
    // the house. A's end, judged from the instant A's own start lit the house,
    // is superseded by a COMPLETED later start — closed, no command.
    bridgeCompletes(f, bc.id, B_FIRE + 11 * MIN);
    await dispatch(f, B_FIRE + 12 * MIN);
    expect((await read(f, JOB(bStart))).state).toBe("completed");
    expect(await read(f, JOB(endId))).toMatchObject({ state: "skipped", skipReason: "superseded_by_later_start", supersededBy: bStart });
    expect(await fireCommands(f, endId)).toHaveLength(0);

    // The planner then closes the session rather than re-minting (the chain's
    // first-due instant is the one the sweep used, not the sweep's own time).
    const p = await plan(f, B_FIRE + 21 * MIN, FLAG);
    expect(await read(f, JOB(`${endId}_r1`))).toBeUndefined();
    expect(p.logRows.find((x) => x.reason === "end_remint_skipped:superseded_by_later_start")).toMatchObject({ eventId: EVENT(A) });
    expect((await read(f, SESSION(A))).endSuperseded).toBe(true);
  });
});
