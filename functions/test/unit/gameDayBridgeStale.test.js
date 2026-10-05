// gameDayPreflight × the bridge write gap (2026-10-05) — PURE.
//
//   A   `preflight_bridge_grace`  P2's window: 5 min → 15 min
//   B2  `served_sticky`           `served` rides through < 30 min of P2 failure
//
// The planner-level behaviour (what is minted, what is published, tick by
// tick) is in plannerBridgeStale.test.js. All ids here are synthetic.

const P = require("../../lib/gameDayPreflight");

const SEC = 1000;
const MIN = 60 * SEC;
const NOW = Date.parse("2026-10-11T16:00:00Z");
const ts = (ms) => ({ toMillis: () => ms });

function goodInputs(over = {}) {
  return {
    bridgePaired: true,
    bridgeStatusUpdateMs: NOW - 20 * SEC,
    controller: {
      participating_channels: [0, 1],
      participating_channels_device_ids: [0, 1],
      participating_channels_at: ts(NOW - 86_400_000),
      base_ladder_asserts_segments: true,
    },
    gate: { armed: true },
    p6Unreachable: false,
    appVersion: "2.5.10+114",
    nowMs: NOW,
    ...over,
  };
}

const STALE = { ok: false, reasons: ["preflight_bridge_stale"], info: [] };
const OK = { ok: true, reasons: [], info: [] };

// ---------------------------------------------------------------------------
describe("the windows", () => {
  test("5 min shipped, 15 min with grace, 30 min of hold", () => {
    expect(P.BRIDGE_STALE_MS).toBe(5 * MIN);
    expect(P.BRIDGE_STALE_GRACE_MS).toBe(15 * MIN);
    expect(P.SERVED_STICKY_MS).toBe(30 * MIN);
    expect(P.bridgeStaleMsFor(false)).toBe(5 * MIN);
    expect(P.bridgeStaleMsFor(true)).toBe(15 * MIN);
  });
});

// ---------------------------------------------------------------------------
describe("A — P2's window", () => {
  test("with no window passed, P2 is the 5 minutes it always was", () => {
    expect(P.checkBridgeFresh(NOW - 4 * MIN - 59 * SEC, NOW)).toBeNull();
    expect(P.checkBridgeFresh(NOW - 5 * MIN, NOW)).toBeNull();
    expect(P.checkBridgeFresh(NOW - 5 * MIN - 1 * SEC, NOW)).toBe("preflight_bridge_stale");
    expect(P.checkBridgeFresh(null, NOW)).toBe("preflight_bridge_stale");
  });

  test("the boundary with grace: 14:59 is fresh, 15:00 is fresh, 15:01 is stale", () => {
    const w = P.bridgeStaleMsFor(true);
    expect(P.checkBridgeFresh(NOW - 14 * MIN - 59 * SEC, NOW, w)).toBeNull();
    expect(P.checkBridgeFresh(NOW - 15 * MIN, NOW, w)).toBeNull();
    expect(P.checkBridgeFresh(NOW - 15 * MIN - 1 * SEC, NOW, w)).toBe("preflight_bridge_stale");
  });

  test("no heartbeat document at all is stale under either window", () => {
    expect(P.checkBridgeFresh(null, NOW, P.bridgeStaleMsFor(true))).toBe("preflight_bridge_stale");
  });

  test("evaluatePreflight: a 10-minute-old heartbeat fails without the window and passes with it", () => {
    const beat = { bridgeStatusUpdateMs: NOW - 10 * MIN };
    expect(P.evaluatePreflight(goodInputs(beat))).toMatchObject({ ok: false, reasons: ["preflight_bridge_stale"] });
    expect(
      P.evaluatePreflight(goodInputs({ ...beat, bridgeStaleMs: P.BRIDGE_STALE_MS }))
    ).toMatchObject({ ok: false, reasons: ["preflight_bridge_stale"] });
    expect(
      P.evaluatePreflight(goodInputs({ ...beat, bridgeStaleMs: P.bridgeStaleMsFor(true) }))
    ).toEqual({ ok: true, reasons: [], info: [] });
  });

  test("the grace window touches P2 only: every other check still names itself", () => {
    const r = P.evaluatePreflight(goodInputs({
      bridgeStatusUpdateMs: NOW - 10 * MIN,
      bridgeStaleMs: P.bridgeStaleMsFor(true),
      bridgePaired: false,
      controller: { participating_channels: [], base_ladder_asserts_segments: false },
      gate: { armed: false },
    }));
    expect(r.reasons).toEqual([
      "preflight_no_bridge",
      "preflight_no_participation",
      "preflight_ladder_bad",
      "preflight_gated",
    ]);
  });
});

// ---------------------------------------------------------------------------
describe("the two flags parse like every other planner flag: true, or a uid list", () => {
  const cases = [
    ["preflight_bridge_grace", P.bridgeGraceScopeFrom],
    ["served_sticky", P.servedStickyScopeFrom],
  ];
  test.each(cases)("%s", (key, from) => {
    expect(from(undefined)).toBeNull();
    expect(from({})).toBeNull();
    expect(from({ [key]: true })).toEqual({ all: true });
    const list = from({ [key]: ["u_bench"] });
    expect(list.all).toBe(false);
    expect([...list.uids]).toEqual(["u_bench"]);
    expect([...from({ [key]: [] }).uids]).toEqual([]);
    for (const v of [false, null, "true", 1, {}, ["u_bench", 7], [""], [["u_bench"]]]) {
      expect(from({ [key]: v })).toBeNull();
    }
  });

  test("one flag's field never arms the other", () => {
    expect(P.servedStickyScopeFrom({ preflight_bridge_grace: true })).toBeNull();
    expect(P.bridgeGraceScopeFrom({ served_sticky: true })).toBeNull();
  });
});

// ---------------------------------------------------------------------------
describe("B2 sticky — decideServedSticky", () => {
  const SINCE = NOW - 10 * MIN;
  const base = (over = {}) => ({
    stickyOn: true,
    preflight: STALE,
    startsWithheld: true,
    stored: { served: true },
    nowMs: NOW,
    ...over,
  });

  test("flag off: never a hold, and stale_since is not to exist", () => {
    for (const stored of [undefined, { served: true }, { served: true, stale_since: ts(SINCE) }]) {
      expect(P.decideServedSticky(base({ stickyOn: false, stored }))).toEqual({
        hold: false, expired: false, staleSinceMs: null,
      });
    }
  });

  test("the first failing tick starts the run at this tick's clock, and holds", () => {
    expect(P.decideServedSticky(base())).toEqual({ hold: true, expired: false, staleSinceMs: NOW });
  });

  test("a later failing tick carries the stored start unchanged", () => {
    expect(P.decideServedSticky(base({ stored: { served: true, stale_since: ts(SINCE) } }))).toEqual({
      hold: true, expired: false, staleSinceMs: SINCE,
    });
  });

  test("the boundary: 29:59 of failure holds; 30:00 does not, and says it expired", () => {
    const at = (elapsed) =>
      P.decideServedSticky(base({ stored: { served: true, stale_since: ts(NOW - elapsed) } }));
    expect(at(29 * MIN + 59 * SEC)).toMatchObject({ hold: true, expired: false });
    expect(at(30 * MIN)).toEqual({ hold: false, expired: true, staleSinceMs: NOW - 30 * MIN });
    expect(at(31 * MIN)).toEqual({ hold: false, expired: true, staleSinceMs: NOW - 31 * MIN });
  });

  test("after the flip the stored served is false: no hold, and no second expiry", () => {
    expect(
      P.decideServedSticky(base({ stored: { served: false, stale_since: ts(NOW - 35 * MIN) } }))
    ).toEqual({ hold: false, expired: false, staleSinceMs: NOW - 35 * MIN });
  });

  test("P2 passing ends the run: no hold, stale_since removed", () => {
    expect(
      P.decideServedSticky(base({ preflight: OK, startsWithheld: false, stored: { served: true, stale_since: ts(SINCE) } }))
    ).toEqual({ hold: false, expired: false, staleSinceMs: null });
  });

  test("pre-flight did not run (not allowlisted): nothing held, nothing tracked", () => {
    expect(
      P.decideServedSticky(base({ preflight: null, startsWithheld: false, stored: { served: true, stale_since: ts(SINCE) } }))
    ).toEqual({ hold: false, expired: false, staleSinceMs: null });
  });

  test("any reason beside the stale bridge is not a write gap: served follows at once", () => {
    for (const other of [
      "preflight_no_bridge", "preflight_no_participation", "preflight_ladder_unknown",
      "preflight_ladder_bad", "preflight_ladder_dark", "preflight_gated", "preflight_controller_unreachable",
    ]) {
      const preflight = { ok: false, reasons: ["preflight_bridge_stale", other], info: [] };
      // …while the run itself is still tracked: P2 IS failing.
      expect(P.decideServedSticky(base({ preflight }))).toEqual({ hold: false, expired: false, staleSinceMs: NOW });
    }
  });

  test("a failure that is not P2 at all holds nothing and tracks nothing", () => {
    const preflight = { ok: false, reasons: ["preflight_ladder_unknown"], info: [] };
    expect(P.decideServedSticky(base({ preflight }))).toEqual({ hold: false, expired: false, staleSinceMs: null });
  });

  test("an account that was not served is never made served by a hold", () => {
    for (const stored of [undefined, null, {}, { served: false }, { served: "true" }, "served"]) {
      expect(P.decideServedSticky(base({ stored }))).toMatchObject({ hold: false, expired: false });
    }
  });

  test("observe mode withholds nothing, so there is nothing to hold", () => {
    expect(P.decideServedSticky(base({ startsWithheld: false }))).toEqual({
      hold: false, expired: false, staleSinceMs: NOW,
    });
  });

  test("a stored start later than this tick is not continued: the run starts now", () => {
    expect(
      P.decideServedSticky(base({ stored: { served: true, stale_since: ts(NOW + 5 * MIN) } }))
    ).toEqual({ hold: true, expired: false, staleSinceMs: NOW });
  });

  test("a malformed stored start reads as no start", () => {
    for (const bad of ["2026-10-11", 12345, {}, null]) {
      expect(
        P.decideServedSticky(base({ stored: { served: true, stale_since: bad } }))
      ).toEqual({ hold: true, expired: false, staleSinceMs: NOW });
    }
  });

  test("informational lines never affect the hold", () => {
    const preflight = { ok: false, reasons: ["preflight_bridge_stale"], info: ["lease_hygiene_unknown"] };
    expect(P.decideServedSticky(base({ preflight }))).toMatchObject({ hold: true });
  });
});
