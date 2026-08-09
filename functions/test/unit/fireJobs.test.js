/**
 * Unit tests for the S3 fire-job contract.
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * No emulator, no firebase-admin IO.
 */

const {
  MAX_FIRE_LATENESS_MS,
  FIRE_GRACE_MS,
  ALLOWED_FIRE_TYPES,
  FORBIDDEN_PAYLOAD_KEYS,
  assertPayloadIsFireSafe,
  decideDispatch,
  buildFireCommand,
  jobStateForCommandStatus,
  percentile,
  rollup,
  appendSamples,
  MAX_SAMPLES_PER_DAY,
} = require("../../lib/fireJobs");

const {
  MIN_SWEEPABLE_AGE_MS,
  DEFAULT_COMMAND_TTL_MS,
  fireJobDocId,
} = require("../../lib/commandSafety");

const ts = (ms) => ({ toMillis: () => ms });
const T0 = 1_800_000_000_000;

const job = (over = {}) => ({
  eventId: "evt1",
  seq: "start",
  controllerId: "ctrl1",
  fireAt: ts(T0),
  payload: JSON.stringify({ on: true, bri: 200 }),
  type: "applyJson",
  state: "scheduled",
  ...over,
});

// ---------------------------------------------------------------------------
// Timing constants
// ---------------------------------------------------------------------------

describe("fire timing constants", () => {
  test("grace is at least the sweeper's age floor", () => {
    // Below MIN_SWEEPABLE_AGE_MS the sweeper never queries the command, so the
    // expiry would be a deadline nothing can enforce.
    expect(FIRE_GRACE_MS).toBeGreaterThanOrEqual(MIN_SWEEPABLE_AGE_MS);
  });

  test("grace is BELOW the app-watchdog default", () => {
    // A scheduled fire must not outlive a command a human is waiting on.
    expect(FIRE_GRACE_MS).toBeLessThan(DEFAULT_COMMAND_TTL_MS);
  });

  test("grace comfortably exceeds the measured 30-32s tail", () => {
    expect(FIRE_GRACE_MS).toBeGreaterThan(32_000 * 2);
  });

  test("total worst-case lateness is bounded at 3 minutes", () => {
    expect(MAX_FIRE_LATENESS_MS + FIRE_GRACE_MS).toBeLessThanOrEqual(180_000);
  });
});

// ---------------------------------------------------------------------------
// Payload safety — the §4.2 constraint, enforced in code
// ---------------------------------------------------------------------------

describe("assertPayloadIsFireSafe", () => {
  test("a plain absolute-state payload is allowed", () => {
    expect(assertPayloadIsFireSafe("applyJson", JSON.stringify({ on: true, bri: 200 })).ok).toBe(true);
  });

  test("ping needs no payload", () => {
    expect(assertPayloadIsFireSafe("ping", undefined).ok).toBe(true);
  });

  test("REJECTS psave — the whole point of the §4.2 constraint", () => {
    // type:"applyJson" + payload {"psave":5} sails past a type allowlist and
    // reaches POST /json/state. That is how a preset gets written by a cron.
    const r = assertPayloadIsFireSafe("applyJson", JSON.stringify({ psave: 5, on: true }));
    expect(r.ok).toBe(false);
    expect(r.reason).toMatch(/psave/);
  });

  test("REJECTS pdel and rb", () => {
    expect(assertPayloadIsFireSafe("applyJson", JSON.stringify({ pdel: 3 })).ok).toBe(false);
    expect(assertPayloadIsFireSafe("applyJson", JSON.stringify({ rb: true })).ok).toBe(false);
  });

  test("every forbidden key is actually rejected", () => {
    for (const k of FORBIDDEN_PAYLOAD_KEYS) {
      expect(assertPayloadIsFireSafe("applyJson", JSON.stringify({ [k]: 1 })).ok).toBe(false);
    }
  });

  test("ALLOWS ps — a preset LOAD is an absolute state load, not a mutation", () => {
    expect(assertPayloadIsFireSafe("applyJson", JSON.stringify({ ps: 4 })).ok).toBe(true);
  });

  test("catches a forbidden key even in an UNPARSEABLE payload", () => {
    // The raw scan exists because a malformed body can still carry the key and
    // reach the bridge verbatim.
    const r = assertPayloadIsFireSafe("applyJson", '{"psave": 5, oops');
    expect(r.ok).toBe(false);
    expect(r.reason).toMatch(/raw_payload/);
  });

  test("case-insensitive on the raw scan", () => {
    expect(assertPayloadIsFireSafe("applyJson", '{"PSAVE": 5}').ok).toBe(false);
  });

  test("fails CLOSED on anything unparseable or non-object", () => {
    for (const bad of ["not json", "[1,2,3]", '"str"', "", null, undefined, 42]) {
      expect(assertPayloadIsFireSafe("applyJson", bad).ok).toBe(false);
    }
  });

  test("rejects a type outside the allowlist", () => {
    for (const t of ["applyConfig", "savePreset", "pair", "getState", "", null]) {
      expect(assertPayloadIsFireSafe(t, "{}").ok).toBe(false);
    }
  });

  test("the allowlist is exactly applyJson and ping", () => {
    expect([...ALLOWED_FIRE_TYPES].sort()).toEqual(["applyJson", "ping"]);
  });
});

// ---------------------------------------------------------------------------
// Dispatch decision — terminal vs transient is the load-bearing distinction
// ---------------------------------------------------------------------------

describe("decideDispatch", () => {
  test("a due job dispatches", () => {
    expect(decideDispatch({ job: job(), nowMs: T0 })).toEqual({
      dispatch: true,
      reason: "due",
      terminal: false,
    });
  });

  test("a future job is NOT due, and NOT terminal", () => {
    const d = decideDispatch({ job: job(), nowMs: T0 - 60_000 });
    expect(d.dispatch).toBe(false);
    expect(d.reason).toBe("not_yet_due");
    expect(d.terminal).toBe(false);
  });

  test("late but inside the window still fires", () => {
    expect(decideDispatch({ job: job(), nowMs: T0 + MAX_FIRE_LATENESS_MS }).dispatch).toBe(true);
  });

  test("past the lateness bound is TERMINAL, not retried forever", () => {
    const d = decideDispatch({ job: job(), nowMs: T0 + MAX_FIRE_LATENESS_MS + 1 });
    expect(d.dispatch).toBe(false);
    expect(d.terminal).toBe(true);
    expect(d.reason).toMatch(/^too_late:/);
  });

  test("an unsafe payload is TERMINAL — never retried into a preset write", () => {
    const d = decideDispatch({
      job: job({ payload: JSON.stringify({ psave: 2 }) }),
      nowMs: T0,
    });
    expect(d.dispatch).toBe(false);
    expect(d.terminal).toBe(true);
    expect(d.reason).toMatch(/unsafe/);
  });

  test("a missing controllerId is terminal", () => {
    for (const bad of ["", null, undefined, 5]) {
      const d = decideDispatch({ job: job({ controllerId: bad }), nowMs: T0 });
      expect(d.dispatch).toBe(false);
      expect(d.terminal).toBe(true);
    }
  });

  test("a missing fireAt is terminal rather than firing immediately", () => {
    const d = decideDispatch({ job: job({ fireAt: null }), nowMs: T0 });
    expect(d.dispatch).toBe(false);
    expect(d.terminal).toBe(true);
    expect(d.reason).toBe("no_fireAt");
  });

  test("a job already dispatched is never re-dispatched", () => {
    for (const s of ["dispatched", "completed", "failed", "expired", "skipped"]) {
      expect(decideDispatch({ job: job({ state: s }), nowMs: T0 }).dispatch).toBe(false);
    }
  });

  test("a non-scheduled state is NOT terminalized again", () => {
    // Re-terminalizing would churn writes on every tick forever.
    expect(decideDispatch({ job: job({ state: "completed" }), nowMs: T0 }).terminal).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// Command construction
// ---------------------------------------------------------------------------

describe("buildFireCommand", () => {
  const base = {
    type: "applyJson",
    payload: JSON.stringify({ on: true }),
    controllerId: "ctrl1",
    controllerIp: "192.168.1.150",
    jobId: "job1",
    eventId: "evt1",
    dispatchAtMs: T0,
  };

  test("ALWAYS names controllerIp — the omit path is bench-refuted", () => {
    const { doc } = buildFireCommand(base);
    expect(doc.controllerIp).toBe("192.168.1.150");
  });

  test("payload is a STRING, not a map (the #84 nested-array class)", () => {
    const { doc } = buildFireCommand(base);
    expect(typeof doc.payload).toBe("string");
  });

  test("expiry is measured from DISPATCH time, so the bridge budget is constant", () => {
    // A job 80s late still gives the bridge a full FIRE_GRACE_MS. Under V2's
    // literal `fireAt + grace` it would have had only 10s — below the measured
    // tail — and a healthy bridge would have been blamed for the cron's lateness.
    const late = buildFireCommand({ ...base, dispatchAtMs: T0 + 80_000 });
    expect(late.expiresAtMs - (T0 + 80_000)).toBe(FIRE_GRACE_MS);
  });

  test("ping carries an empty body regardless of the job's payload", () => {
    const { doc } = buildFireCommand({ ...base, type: "ping", payload: '{"on":true}' });
    expect(doc.payload).toBe("{}");
  });

  test("carries the job and event identity for reconciliation", () => {
    const { doc } = buildFireCommand(base);
    expect(doc.fireJobId).toBe("job1");
    expect(doc.eventId).toBe("evt1");
    expect(doc.source).toBe("fire_job");
    expect(doc.status).toBe("pending");
  });
});

describe("deterministic command id", () => {
  test("the SAME job at the SAME fireAt yields the SAME id — retry cannot double-fire", () => {
    const a = fireJobDocId("job1", Math.floor(T0 / 1000));
    const b = fireJobDocId("job1", Math.floor(T0 / 1000));
    expect(a).toBe(b);
  });

  test("keying on `now` instead of fireAt WOULD have double-fired", () => {
    // Documents the trap: a retry one minute later mints a different id, and
    // .create() no longer collides, so the bridge sees two commands.
    const atDispatch = fireJobDocId("job1", Math.floor(T0 / 1000));
    const atRetry = fireJobDocId("job1", Math.floor((T0 + 60_000) / 1000));
    expect(atDispatch).not.toBe(atRetry);
  });

  test("different jobs never collide", () => {
    expect(fireJobDocId("job1", 1)).not.toBe(fireJobDocId("job2", 1));
  });
});

// ---------------------------------------------------------------------------
// Reconciliation
// ---------------------------------------------------------------------------

describe("jobStateForCommandStatus", () => {
  test("maps terminal statuses", () => {
    expect(jobStateForCommandStatus("completed")).toBe("completed");
    expect(jobStateForCommandStatus("failed")).toBe("failed");
    expect(jobStateForCommandStatus("expired")).toBe("expired");
  });

  test("app-written timeout records as failed, not silently ignored", () => {
    expect(jobStateForCommandStatus("timeout")).toBe("failed");
  });

  test("in-flight statuses return null so the job is left alone", () => {
    expect(jobStateForCommandStatus("pending")).toBeNull();
    expect(jobStateForCommandStatus("executing")).toBeNull();
    expect(jobStateForCommandStatus(undefined)).toBeNull();
  });

  test("expired stays distinct from failed all the way through", () => {
    expect(jobStateForCommandStatus("expired")).not.toBe(jobStateForCommandStatus("failed"));
  });
});

// ---------------------------------------------------------------------------
// Metrics
// ---------------------------------------------------------------------------

describe("percentile / rollup", () => {
  test("p50 and p95 over a known set", () => {
    const s = Array.from({ length: 100 }, (_, i) => i + 1); // 1..100
    expect(percentile(s, 50)).toBe(50);
    expect(percentile(s, 95)).toBe(95);
  });

  test("single sample", () => {
    expect(percentile([7], 50)).toBe(7);
    expect(percentile([7], 95)).toBe(7);
  });

  test("EMPTY returns null, never a fabricated zero", () => {
    // A zero would read as "instant" rather than "unmeasured".
    expect(percentile([], 50)).toBeNull();
    expect(rollup([]).p50).toBeNull();
    expect(rollup([]).count).toBe(0);
  });

  test("ignores junk and negatives rather than skewing", () => {
    expect(rollup([10, -5, NaN, Infinity, 20, "x"]).count).toBe(2);
  });

  test("rollup reports min and max", () => {
    const r = rollup([5, 100, 50]);
    expect(r.min).toBe(5);
    expect(r.max).toBe(100);
  });

  test("unsorted input is handled", () => {
    expect(percentile([100, 1, 50], 50)).toBe(50);
  });
});

describe("appendSamples", () => {
  test("appends to an existing array", () => {
    expect(appendSamples([1, 2], [3])).toEqual([1, 2, 3]);
  });

  test("tolerates a missing or malformed prior value", () => {
    expect(appendSamples(undefined, [1])).toEqual([1]);
    expect(appendSamples("nonsense", [1])).toEqual([1]);
    expect(appendSamples([1, "x", 2], [3])).toEqual([1, 2, 3]);
  });

  test("caps at MAX_SAMPLES_PER_DAY keeping the MOST RECENT", () => {
    // A path that degrades through the day must show in that day's percentiles
    // rather than being masked by the healthy morning.
    const prev = Array.from({ length: MAX_SAMPLES_PER_DAY }, () => 1);
    const out = appendSamples(prev, [999]);
    expect(out).toHaveLength(MAX_SAMPLES_PER_DAY);
    expect(out[out.length - 1]).toBe(999);
    expect(out[0]).toBe(1);
  });
});
