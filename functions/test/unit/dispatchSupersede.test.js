// dispatchFireJobs × "an end never fires into the next game" (2026-10-07
// review, item 2) — the REAL dispatcher tick on the shared in-memory Firestore.
//
// An END the planner wrote under the end guarantee (`endGuarantee: true`) can
// outlive its game: a 90-minute budget, a held command, re-mints. Before such
// an end is dispatched or retried, the dispatcher asks whether a START on the
// same controller has COMPLETED since the end was first due. If so the house
// is a newer team's and a base restore would wipe it: the end is skipped,
// terminal, `superseded_by_later_start`, naming the start. A start that is
// merely dispatched (its command pending) has lit nothing yet: it defers the
// end transiently through the one-in-flight guard and never closes it (the
// delta review of 31751b2). A job without the marker (the flag absent) is
// dispatched and retried exactly as rev 00005 does.

const { makeFakeFirestore } = require("./support/fakeFirestore");
const { runDispatchTick } = require("../../lib/dispatchFireJobs");
const { SUPERSEDED_BY_START_REASON } = require("../../lib/fireJobs");

const S = 1000;
const M = 60 * S;
const NOW = Date.UTC(2026, 9, 12, 4, 10, 0); // 23:10 CDT
const END_DUE = NOW - 30 * M; // the final, when the end was first due
const UID = "u_sup";
const CTRL = "ctrl_sup";
const OTHER_CTRL = "ctrl_sup_other";
const A = "nfl_supteam";
const B = "mlb_supteam";
const EVENT_A = `gd_${A}_9800001`;
const EVENT_B = `gd_${B}_9800002`;
const END = `${EVENT_A}_end`;
const B_START = `${EVENT_B}_start`;
const JOB = (id) => `users/${UID}/fire_jobs/${id}`;
const CMD = (id) => `users/${UID}/commands/${id}`;

/** A world with team A's end due and nothing else; `end` overrides the end job. */
function world(end = {}) {
  const f = makeFakeFirestore({ now: NOW });
  f.put(`users/${UID}`, { owner_id: UID });
  f.put("bridge_registry/BR_SUP_01", { pairedUid: UID, status: "paired" });
  f.put(`users/${UID}/controllers/${CTRL}`, { ip: "192.0.2.60" });
  f.put(`users/${UID}/controllers/${OTHER_CTRL}`, { ip: "192.0.2.61" });
  f.put(`users/${UID}/game_day_autopilot/${A}`, { enabled: true, sport: "nfl" });
  f.put(`users/${UID}/game_day_autopilot/${B}`, { enabled: true, sport: "mlb" });
  f.put(JOB(END), {
    eventId: EVENT_A, seq: "end", controllerId: CTRL,
    // Retried once already: due again now, first due at the final.
    fireAt: f.ts(NOW - 10 * S), firstFireAt: f.ts(END_DUE),
    type: "applyJson", payload: '{"ps":1}',
    state: "scheduled", source: "game_day",
    retryUntil: f.ts(END_DUE + 90 * M), holdUntil: f.ts(END_DUE + 90 * M),
    endGuarantee: true,
    ...end,
  });
  return f;
}
/** Team B's start, run by the bridge, on `controllerId`, dispatched at `dispatchedMs`. */
function bStarted(f, dispatchedMs, controllerId = CTRL, extra = {}) {
  f.put(JOB(B_START), {
    eventId: EVENT_B, seq: "start", controllerId,
    fireAt: f.ts(dispatchedMs - 5 * S), type: "applyJson", payload: '{"ps":7}',
    state: "completed", source: "game_day",
    commandId: "cmd_b_start", dispatchedAt: f.ts(dispatchedMs),
    ...extra,
  });
}
const read = async (f, path) => (await f.db.doc(path).get()).data();
const tick = async (f, t = NOW) => { f.setNow(t); return runDispatchTick(f.db, t); };
async function commandsFor(f, jobId) {
  const q = await f.db.collection(`users/${UID}/commands`).get();
  return q.docs.filter((d) => d.get("fireJobId") === jobId);
}

describe("at dispatch: a guaranteed end is skipped when a later start lit the controller", () => {
  test("THE REVIEW'S CASE: B's start dispatched since A's end was first due → skipped, terminal, naming B; no command", async () => {
    const f = world();
    bStarted(f, END_DUE + 12 * M);
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("skipped");
    expect(end.skipReason).toBe(SUPERSEDED_BY_START_REASON);
    expect(end.supersededBy).toBe(B_START);
    expect(end).not.toHaveProperty("commandId");
    expect(await commandsFor(f, END)).toHaveLength(0);
  });

  test("a start dispatched BEFORE the end was first due is the game this end belongs to: the end fires", async () => {
    const f = world();
    bStarted(f, END_DUE - 3 * 60 * M); // A's own start, in effect
    await tick(f);
    expect((await read(f, JOB(END))).state).toBe("dispatched");
    expect(await commandsFor(f, END)).toHaveLength(1);
  });

  test("a later start on ANOTHER controller does not supersede", async () => {
    const f = world();
    bStarted(f, END_DUE + 12 * M, OTHER_CTRL);
    await tick(f);
    expect((await read(f, JOB(END))).state).toBe("dispatched");
  });

  test("a later start merely `dispatched` (its command pending) does NOT close the end: the in-flight guard defers it, and it fires once that start's command expires having lit nothing", async () => {
    const f = world();
    bStarted(f, END_DUE + 12 * M, CTRL, { state: "dispatched" });
    // Its command is still pending on the bridge (a dispatched job always has one).
    f.put(CMD("cmd_b_start"), {
      fireJobId: B_START, uid: UID, controllerId: CTRL, status: "pending", createdAt: f.ts(END_DUE + 12 * M),
    });
    const d = await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("scheduled");
    expect(end).not.toHaveProperty("skipReason");
    expect(d.skippedTransient).toMatchObject({ in_flight: 1 });
    // The bridge is away: B's command expires and B never lit the house.
    f.patch(CMD("cmd_b_start"), { status: "expired" });
    f.patch(JOB(B_START), { state: "expired" });
    await tick(f, NOW + M);
    expect((await read(f, JOB(END))).state).toBe("dispatched");
    expect(await commandsFor(f, END)).toHaveLength(1);
  });

  test("a hand-off END to a DIFFERENT team lit that team: it supersedes", async () => {
    const f = world();
    f.put(JOB(`gd_nfl_relinquisher_9800003_end`), {
      eventId: "gd_nfl_relinquisher_9800003", seq: "end", controllerId: CTRL,
      handoffTo: EVENT_B, handoffToTeam: B, // the planner's shape: the survivor's event id and slug
      fireAt: f.ts(END_DUE + 10 * M), type: "applyJson", payload: '{"ps":7}',
      state: "completed", source: "game_day", commandId: "cmd_handoff", dispatchedAt: f.ts(END_DUE + 10 * M),
    });
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.skipReason).toBe(SUPERSEDED_BY_START_REASON);
    expect(end.supersededBy).toBe("gd_nfl_relinquisher_9800003_end");
  });

  test("a re-minted end carries the chain's first due instant (`firstDueAt`) and is judged by it", async () => {
    const f = world({ firstFireAt: undefined, firstDueAt: undefined });
    // The re-mint: fireAt is now; the chain was first due at the final.
    f.put(JOB(`${EVENT_A}_end_r1`), {
      eventId: EVENT_A, seq: "end", controllerId: CTRL,
      fireAt: f.ts(NOW - 10 * S), firstDueAt: f.ts(END_DUE),
      type: "applyJson", payload: '{"ps":1}', state: "scheduled", source: "game_day",
      retryUntil: f.ts(NOW + 90 * M), holdUntil: f.ts(NOW + 90 * M), endGuarantee: true,
      remintOf: END, remint: 1,
    });
    f.patch(JOB(END), { state: "expired" });
    bStarted(f, END_DUE + 12 * M); // before the re-mint's own fireAt, after the chain's first due
    await tick(f);
    expect((await read(f, JOB(`${EVENT_A}_end_r1`))).skipReason).toBe(SUPERSEDED_BY_START_REASON);
  });
});

describe("which later completed jobs supersede (second delta review, S6): only a job that lit a DIFFERENT team", () => {
  const RELINQ = "gd_nfl_relinquisher_9800003";
  const handoff = (f, to, toTeam, atMs, id = `${RELINQ}_end`) =>
    f.put(JOB(id), {
      eventId: RELINQ, seq: "end", controllerId: CTRL, handoffTo: to, handoffToTeam: toTeam,
      fireAt: f.ts(atMs), type: "applyJson", payload: '{"ps":7}', state: "completed",
      source: "game_day", commandId: `cmd_${id}`, dispatchedAt: f.ts(atMs),
    });

  test("a hand-off end TO the team whose end is judged re-lit that team: it never supersedes, the end fires", async () => {
    const f = world();
    handoff(f, EVENT_A, A, END_DUE + 10 * M);
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("dispatched");
    expect(end).not.toHaveProperty("skipReason");
    expect(await commandsFor(f, END)).toHaveLength(1);
  });

  test("an older job that stored the survivor's SLUG in handoffTo is read the same way", async () => {
    const f = world();
    handoff(f, A, undefined, END_DUE + 10 * M);
    await tick(f);
    expect((await read(f, JOB(END))).state).toBe("dispatched");
  });

  test("a start of the SAME team (another game, or a re-minted id) never supersedes its own end", async () => {
    const f = world();
    f.put(JOB(`gd_${A}_9800009_start_r1`), {
      eventId: `gd_${A}_9800009`, seq: "start", controllerId: CTRL,
      fireAt: f.ts(END_DUE + 12 * M), type: "applyJson", payload: '{"ps":7}', state: "completed",
      source: "game_day", commandId: "cmd_a_again", dispatchedAt: f.ts(END_DUE + 12 * M),
    });
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("dispatched");
    expect(end).not.toHaveProperty("skipReason");
  });

  test("a different team's start completed BEFORE the hand-off that re-lit this team does not supersede: the team was lit again after it", async () => {
    const f = world();
    bStarted(f, END_DUE + 5 * M); // B lit the house…
    handoff(f, EVENT_A, A, END_DUE + 20 * M); // …then a hand-off re-lit A
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("dispatched");
    expect(end).not.toHaveProperty("skipReason");
  });

  test("a different team's start completed AFTER the hand-off that re-lit this team supersedes", async () => {
    const f = world();
    handoff(f, EVENT_A, A, END_DUE + 5 * M); // a hand-off re-lit A…
    bStarted(f, END_DUE + 20 * M); // …then B lit the house
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("skipped");
    expect(end.supersededBy).toBe(B_START);
  });
});

describe("the flag absent: no marker, no supersede — rev 00005 exactly", () => {
  test("B's start dispatched since A's end was first due: the end still fires (the shipped 15-minute end cannot outlive its game by much)", async () => {
    const f = world({ endGuarantee: undefined, holdUntil: undefined, retryUntil: undefined });
    f.patch(JOB(END), { retryUntil: f.ts(NOW + 5 * M) });
    bStarted(f, END_DUE + 12 * M);
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("dispatched");
    expect(end).not.toHaveProperty("skipReason");
    expect(await commandsFor(f, END)).toHaveLength(1);
  });
});

describe("at retry: a failed guaranteed end is not retried into the next game", () => {
  function failedOnce(f) {
    f.patch(JOB(END), { state: "dispatched", commandId: "cmd_a_end_1", attempts: 1, dispatchedAt: f.ts(NOW - 2 * M) });
    f.put(CMD("cmd_a_end_1"), {
      fireJobId: END, uid: UID, status: "failed", error: "ERROR: HTTP -1",
      createdAt: f.ts(NOW - 2 * M), completedAt: f.ts(NOW - M),
    });
  }

  test("THE REVIEW'S REPRODUCTION: the end failed (retryable) while B's start landed → skipped, not rescheduled", async () => {
    const f = world();
    failedOnce(f);
    bStarted(f, NOW - 90 * S); // B's start dispatched after the end's first due, before this tick
    const r = await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("skipped");
    expect(end.skipReason).toBe(SUPERSEDED_BY_START_REASON);
    expect(end.supersededBy).toBe(B_START);
    expect(end.outcomeClass).toBe("http_transport");
    expect(end).not.toHaveProperty("rescheduledAt");
    expect(r.skippedTerminal).toMatchObject({ [SUPERSEDED_BY_START_REASON]: 1 });
    expect(await commandsFor(f, END)).toHaveLength(1); // the one that failed; no second
  });

  test("a later start merely dispatched (not completed): the same failure is rescheduled, not closed", async () => {
    const f = world();
    failedOnce(f);
    bStarted(f, NOW - 90 * S, CTRL, { state: "dispatched" });
    f.put(CMD("cmd_b_start"), {
      fireJobId: B_START, uid: UID, controllerId: CTRL, status: "pending", createdAt: f.ts(NOW - 90 * S),
    });
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("scheduled");
    expect(end.retries).toBe(1);
    expect(end).not.toHaveProperty("skipReason");
  });

  test("the normal case, no later start: the same failure is rescheduled on the A2 backoff", async () => {
    const f = world();
    failedOnce(f);
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("scheduled");
    expect(end.retries).toBe(1);
    expect(end.lastOutcome).toBe("http_transport");
    expect(end.firstFireAt.toMillis()).toBe(END_DUE);
  });

  test("the flag absent (no marker): the same failure is rescheduled, as rev 00005", async () => {
    const f = world({ endGuarantee: undefined, holdUntil: undefined });
    failedOnce(f);
    bStarted(f, NOW - 90 * S);
    await tick(f);
    const end = await read(f, JOB(END));
    expect(end.state).toBe("scheduled");
    expect(end.retries).toBe(1);
  });
});
