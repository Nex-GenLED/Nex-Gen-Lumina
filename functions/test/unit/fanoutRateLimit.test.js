// SYNC-2 — coverage for the EXISTING anti-strobe rate limiter (not a rewrite):
// evaluateRateLimit (pure) + reserveFanoutSlot (transactional). Locks the
// deliberate policy — per-initiator 18s cooldown, per-group 5/60s ceiling — so a
// future refactor can't silently weaken it. Runs against tsc-compiled lib/.

const {
  evaluateRateLimit,
  reserveFanoutSlot,
  GROUP_CEILING_PER_MIN,
  INITIATOR_COOLDOWN_MS,
  RATE_WINDOW_MS,
} = require("../../lib/applySyncPattern");

const NOW = 1_000_000_000;

describe("evaluateRateLimit (pure decision)", () => {
  test("policy constants are the documented anti-strobe values", () => {
    expect(GROUP_CEILING_PER_MIN).toBe(5);
    expect(RATE_WINDOW_MS).toBe(60000);
    expect(INITIATOR_COOLDOWN_MS).toBe(18000);
  });

  test("first fanout in an empty window → allowed, reserves the slot", () => {
    const d = evaluateRateLimit({}, "u1", NOW);
    expect(d.allowed).toBe(true);
    expect(d.retryAfterMs).toBe(0);
    expect(d.windowStarts).toEqual([NOW]);
    expect(d.lastByInitiator).toEqual({ u1: NOW });
  });

  test("second within the 18s initiator cooldown → rejected with retryAfterMs", () => {
    const state = { windowStarts: [NOW - 1000], lastByInitiator: { u1: NOW - 1000 } };
    const d = evaluateRateLimit(state, "u1", NOW);
    expect(d.allowed).toBe(false);
    expect(d.retryAfterMs).toBe(INITIATOR_COOLDOWN_MS - 1000); // 17000
  });

  test("6th group fanout within 60s (ceiling) → rejected", () => {
    // 5 fanouts already in the window; a FRESH initiator (no cooldown) is the
    // 6th → only the group ceiling can reject it.
    const state = {
      windowStarts: [NOW - 5000, NOW - 4000, NOW - 3000, NOW - 2000, NOW - 1000],
      lastByInitiator: {},
    };
    const d = evaluateRateLimit(state, "fresh", NOW);
    expect(d.allowed).toBe(false);
    expect(d.retryAfterMs).toBe(NOW - 5000 + RATE_WINDOW_MS - NOW); // 55000
  });

  test("group window expiry (>60s) → allowed again, stale starts trimmed", () => {
    const state = {
      windowStarts: [NOW - 61000, NOW - 70000], // both outside the 60s window
      lastByInitiator: {},
    };
    const d = evaluateRateLimit(state, "u1", NOW);
    expect(d.allowed).toBe(true);
    expect(d.windowStarts).toEqual([NOW]); // trimmed to empty, then this one
  });

  test("initiator cooldown expiry (>18s) → allowed again", () => {
    const state = {
      windowStarts: [NOW - 19000],
      lastByInitiator: { u1: NOW - 19000 },
    };
    const d = evaluateRateLimit(state, "u1", NOW);
    expect(d.allowed).toBe(true);
  });

  test("accept prunes stale lastByInitiator entries (bounded growth)", () => {
    const state = {
      windowStarts: [],
      lastByInitiator: { stale: NOW - 999999, u1: NOW - 30000 },
    };
    const d = evaluateRateLimit(state, "u1", NOW);
    expect(d.allowed).toBe(true);
    expect(d.lastByInitiator.stale).toBeUndefined(); // pruned
    expect(d.lastByInitiator.u1).toBe(NOW);
  });
});

// ── reserveFanoutSlot: transactional wrapper over evaluateRateLimit ──────────
// In-memory db whose runTransaction SERIALIZES (mutex) — modeling Firestore's
// contention resolution: each transaction sees the committed state of the prior,
// so two racing reservations cannot both book a slot.
function makeDb(initial) {
  let state = initial; // rate_limits/state data (undefined = doc absent)
  let mutex = Promise.resolve();
  const chainable = { collection: () => chainable, doc: () => chainable };
  const db = {
    collection: () => chainable,
    runTransaction: async (fn) => {
      const prev = mutex;
      let release;
      mutex = new Promise((r) => (release = r));
      await prev; // serialize
      try {
        let staged = null;
        const tx = {
          get: async () => ({ exists: state !== undefined, data: () => state }),
          set: (_ref, data) => {
            staged = data;
          },
        };
        const result = await fn(tx);
        if (staged) state = { ...(state || {}), ...staged }; // merge semantics
        return result;
      } finally {
        release();
      }
    },
  };
  return { db, getState: () => state };
}

describe("reserveFanoutSlot (transactional)", () => {
  test("first reserve → allowed and records exactly one window slot", async () => {
    const { db, getState } = makeDb(undefined);
    const r = await reserveFanoutSlot(db, "g1", "u1", NOW);
    expect(r.allowed).toBe(true);
    expect(getState().windowStarts).toEqual([NOW]);
    expect(getState().lastByInitiator.u1).toBe(NOW);
  });

  test("second within cooldown → rejected AND writes nothing (no extra slot)", async () => {
    const { db, getState } = makeDb(undefined);
    await reserveFanoutSlot(db, "g1", "u1", NOW);
    const r2 = await reserveFanoutSlot(db, "g1", "u1", NOW + 1000);
    expect(r2.allowed).toBe(false);
    expect(r2.retryAfterMs).toBeGreaterThan(0);
    // reject consumed no slot — still exactly the one from the first reserve.
    expect(getState().windowStarts).toEqual([NOW]);
  });

  test("concurrent double-fanout → exactly one commits", async () => {
    const { db, getState } = makeDb(undefined);
    const [a, b] = await Promise.all([
      reserveFanoutSlot(db, "g1", "u1", NOW),
      reserveFanoutSlot(db, "g1", "u1", NOW),
    ]);
    const allowed = [a, b].filter((x) => x.allowed);
    expect(allowed).toHaveLength(1); // the other saw the updated state and rejected
    expect(getState().windowStarts).toEqual([NOW]);
  });

  test("after the window + cooldown expire → reserved again", async () => {
    const { db, getState } = makeDb(undefined);
    await reserveFanoutSlot(db, "g1", "u1", NOW);
    const later = NOW + RATE_WINDOW_MS + 1000; // >60s (and >18s cooldown)
    const r = await reserveFanoutSlot(db, "g1", "u1", later);
    expect(r.allowed).toBe(true);
    expect(getState().windowStarts).toEqual([later]); // stale start trimmed
  });
});
