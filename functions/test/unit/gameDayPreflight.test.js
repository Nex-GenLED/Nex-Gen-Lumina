// gameDayPreflight — B1 (pre-flight P1–P7), the B2 status key, the B3 scorecard
// identity. PURE: runs against compiled lib/ with no Firestore.

const P = require("../../lib/gameDayPreflight");

const NOW = Date.UTC(2026, 9, 11, 17, 0, 0);
const MIN = 60_000;
const DAY = 86_400_000;
const ts = (ms) => ({ toMillis: () => ms });

const goodController = () => ({
  participating_channels: [0, 1, 2],
  participating_channels_device_ids: [0, 1, 2],
  participating_channels_at: ts(NOW - DAY),
  base_ladder_asserts_segments: true,
});
const goodInputs = (over = {}) => ({
  bridgePaired: true,
  bridgeStatusUpdateMs: NOW - 30_000,
  controller: goodController(),
  gate: { armed: true },
  p6Unreachable: false,
  appVersion: "2.5.10+114",
  nowMs: NOW,
  ...over,
});

describe("flags", () => {
  test("preflight_mode: only exactly 'observe' disarms enforcement", () => {
    expect(P.preflightModeFrom(undefined)).toBe("enforce");
    expect(P.preflightModeFrom({})).toBe("enforce");
    expect(P.preflightModeFrom({ preflight_mode: "observe" })).toBe("observe");
    for (const v of ["Observe", "observe ", "off", true, 1]) {
      expect(P.preflightModeFrom({ preflight_mode: v })).toBe("enforce");
    }
  });

  test("publish_server_status: default on; only an explicit false turns it off", () => {
    expect(P.publishServerStatusFrom(undefined)).toBe(true);
    expect(P.publishServerStatusFrom({})).toBe(true);
    expect(P.publishServerStatusFrom({ publish_server_status: "false" })).toBe(true);
    expect(P.publishServerStatusFrom({ publish_server_status: false })).toBe(false);
  });
});

describe("P1–P5 and P7", () => {
  test("an account that passes everything is ok with no reasons", () => {
    expect(P.evaluatePreflight(goodInputs())).toEqual({ ok: true, reasons: [], info: [] });
  });

  test("P1: no paired bridge fails; a lookup ERROR (null) passes — fail open", () => {
    expect(P.checkBridgePaired(false)).toBe("preflight_no_bridge");
    expect(P.checkBridgePaired(true)).toBeNull();
    expect(P.checkBridgePaired(null)).toBeNull();
  });

  test("P2: heartbeat within 5 min passes; older, or none at all, is stale", () => {
    expect(P.checkBridgeFresh(NOW - 5 * MIN, NOW)).toBeNull();
    expect(P.checkBridgeFresh(NOW - 5 * MIN - 1, NOW)).toBe("preflight_bridge_stale");
    expect(P.checkBridgeFresh(null, NOW)).toBe("preflight_bridge_stale");
  });

  test("P3: channels, device set and a 30-day timestamp are all required", () => {
    expect(P.checkParticipation(goodController(), NOW)).toBeNull();
    const bad = [
      null,
      { ...goodController(), participating_channels: [] },
      { ...goodController(), participating_channels: undefined },
      { ...goodController(), participating_channels: [0, "1"] },
      { ...goodController(), participating_channels_device_ids: [] },
      { ...goodController(), participating_channels_device_ids: undefined },
      { ...goodController(), participating_channels_at: undefined },
      { ...goodController(), participating_channels_at: ts(NOW - 31 * DAY) },
    ];
    for (const c of bad) expect(P.checkParticipation(c, NOW)).toBe("preflight_no_participation");
  });

  test("P3: a deliberate exclusion (a subset of the buses) is still valid", () => {
    expect(P.checkParticipation({ ...goodController(), participating_channels: [0, 2] }, NOW)).toBeNull();
  });

  test("P4: only `true` passes; false is bad, absent is unknown (stricter than the gate)", () => {
    expect(P.checkLadder({ base_ladder_asserts_segments: true })).toBeNull();
    expect(P.checkLadder({ base_ladder_asserts_segments: false })).toBe("preflight_ladder_bad");
    expect(P.checkLadder({})).toBe("preflight_ladder_unknown");
    expect(P.checkLadder(null)).toBe("preflight_ladder_unknown");
  });

  test("P5: the gate", () => {
    expect(P.checkGate({ armed: true })).toBeNull();
    expect(P.checkGate({ armed: false })).toBe("preflight_gated");
  });

  test("P7 is informational: an old or unknown build never fails pre-flight", () => {
    for (const v of ["2.5.10+112", null, "garbage", undefined]) {
      const r = P.evaluatePreflight(goodInputs({ appVersion: v }));
      expect(r.ok).toBe(true);
      expect(r.info).toEqual(["lease_hygiene_unknown"]);
    }
    expect(P.appBuildNumber("2.5.10+112")).toBe(112);
    expect(P.appBuildNumber("2.5.10")).toBeNull();
  });

  test("every failing check is named, in check order", () => {
    const r = P.evaluatePreflight(goodInputs({
      bridgePaired: false,
      bridgeStatusUpdateMs: null,
      controller: { participating_channels: [], base_ladder_asserts_segments: false },
      gate: { armed: false },
      p6Unreachable: true,
    }));
    expect(r.ok).toBe(false);
    expect(r.reasons).toEqual([
      "preflight_no_bridge",
      "preflight_bridge_stale",
      "preflight_no_participation",
      "preflight_ladder_bad",
      "preflight_gated",
      "preflight_controller_unreachable",
    ]);
  });
});

describe("P6 — decideP6", () => {
  const FIRE = NOW + 6 * 60 * MIN;
  const rec = (probes, verdict = "pending") => ({ probes, verdict });
  const p1 = { commandId: "cmd1", writtenAtMs: NOW - 6 * MIN };
  const p2 = { commandId: "cmd2", writtenAtMs: NOW - MIN };
  const decide = (record, statuses, nowMs = NOW, startFireAtMs = FIRE) =>
    P.decideP6({ record, statuses, nowMs, startFireAtMs });

  test("no probe yet → probe 1", () => {
    expect(decide(null, [])).toEqual({ kind: "write_probe", n: 1 });
  });
  test("in flight → wait", () => {
    expect(decide(rec([p1]), ["pending"])).toEqual({ kind: "wait" });
    expect(decide(rec([p1]), ["executing"])).toEqual({ kind: "wait" });
  });
  test("probe 1 completed → ok", () => {
    expect(decide(rec([p1]), ["completed"])).toEqual({ kind: "ok" });
  });
  test("probe 1 failed < 5 min ago → wait; ≥ 5 min → probe 2", () => {
    expect(decide(rec([{ ...p1, writtenAtMs: NOW - 4 * MIN }]), ["failed"])).toEqual({ kind: "wait" });
    for (const st of ["failed", "expired", "timeout"]) {
      expect(decide(rec([p1]), [st])).toEqual({ kind: "write_probe", n: 2 });
    }
  });
  test("probe 2 failed → unreachable; completed → ok; in flight → wait", () => {
    expect(decide(rec([p1, p2]), ["failed", "expired"])).toEqual({ kind: "unreachable" });
    expect(decide(rec([p1, p2]), ["failed", "completed"])).toEqual({ kind: "ok" });
    expect(decide(rec([p1, p2]), ["failed", "pending"])).toEqual({ kind: "wait" });
  });
  test("a MISSING probe document is re-written, never read as a failure", () => {
    expect(decide(rec([p1]), [null])).toEqual({ kind: "write_probe", n: 1 });
    expect(decide(rec([p1, p2]), ["failed", null])).toEqual({ kind: "write_probe", n: 2 });
  });
  test("verdicts are sticky", () => {
    expect(decide(rec([p1], "ok"), ["failed"])).toEqual({ kind: "ok" });
    expect(decide(rec([p1, p2], "unreachable"), ["completed", "completed"])).toEqual({ kind: "unreachable" });
  });
  test("within 3 min of the fire: no probe — a check must not delay what it protects", () => {
    expect(decide(null, [], NOW, NOW + 2 * MIN)).toEqual({ kind: "too_close" });
    // One failure, then no time for a second probe: NOT unreachable.
    expect(decide(rec([p1]), ["failed"], NOW, NOW + 2 * MIN)).toEqual({ kind: "too_close" });
  });
  test("p6RecordFrom tolerates garbage", () => {
    expect(P.p6RecordFrom(undefined)).toBeNull();
    expect(P.p6RecordFrom({ probes: "x", verdict: "weird" })).toEqual({ probes: [], verdict: "pending" });
    expect(P.p6RecordFrom({ probes: [p1, { bad: 1 }, p2, p2], verdict: "ok" }).probes).toEqual([p1, p2]);
  });
  test("p6HoldsAccount: an unreachable verdict holds the account until that game's kickoff", () => {
    const s = { preflight_p6: rec([p1, p2], "unreachable"), gameStartMs: NOW + MIN };
    expect(P.p6HoldsAccount(s, NOW)).toBe(true);
    expect(P.p6HoldsAccount(s, NOW + MIN)).toBe(false);
    expect(P.p6HoldsAccount({ preflight_p6: rec([p1], "pending"), gameStartMs: NOW + MIN }, NOW)).toBe(false);
    expect(P.p6HoldsAccount(undefined, NOW)).toBe(false);
  });
});

describe("B2 — gameday_server change key", () => {
  const core = {
    served: false,
    teams: ["nfl_b", "nfl_a"],
    preflight: { ok: false, reasons: ["preflight_bridge_stale"], info: [], mode: "enforce" },
    next_fire: null,
  };
  test("the stored map round-trips to the same key, ignoring clocks and last_fire", () => {
    const stored = {
      served: false,
      teams: ["nfl_a", "nfl_b"],
      checked_at: ts(NOW),
      preflight: { ok: false, reasons: ["preflight_bridge_stale"], info: [], mode: "enforce", at: ts(NOW) },
      next_fire: null,
      last_fire: { event_id: "gd_nfl_a_1", seq: "start" },
    };
    expect(P.storedServerStatusKey(stored)).toBe(P.serverStatusKey(core));
  });
  test("a changed reason, team or next fire changes the key", () => {
    const k = P.serverStatusKey(core);
    expect(P.serverStatusKey({ ...core, preflight: { ...core.preflight, reasons: [] } })).not.toBe(k);
    expect(P.serverStatusKey({ ...core, teams: ["nfl_a"] })).not.toBe(k);
    expect(P.serverStatusKey({
      ...core,
      next_fire: { event_id: "gd_nfl_a_1", team_slug: "nfl_a", seq: "start", fire_at_ms: NOW },
    })).not.toBe(k);
  });
  test("an absent field has no key (first tick always writes)", () => {
    expect(P.storedServerStatusKey(undefined)).toBeNull();
  });
});

describe("B3 — scorecard identity", () => {
  test("a Thursday-night game belongs to Thursday, not to its UTC date", () => {
    expect(P.scorecardDateKey(Date.parse("2026-10-02T00:15:00Z"), -5)).toBe("2026-10-01");
    expect(P.scorecardDateKey(Date.parse("2026-10-04T17:00:00Z"), -5)).toBe("2026-10-04");
  });
  test("entry id is uid_eventId", () => {
    expect(P.scorecardEntryId("u1", "gd_nfl_a_1")).toBe("u1_gd_nfl_a_1");
  });
});
