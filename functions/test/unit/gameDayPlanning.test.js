/**
 * Unit tests for the S5 Game Day planning contract.
 * Runs against compiled lib/ — `npm run build` first.
 */

const {
  REQUIRED_FINAL_POLLS,
  MIN_PLAUSIBLE_DURATION_DEFAULT_MS,
  MAX_FIRE_PAYLOAD_BYTES,
  buildParticipatingSegArray,
  toRgbwSlots,
  argbToRgb,
  savedDesignUsable,
  decideEndSignal,
  sunsetUtcMs,
  isDaylightOnlyGame,
  estimatedDurationMs,
} = require("../../lib/gameDayPlanning");

const { assertPayloadIsFireSafe } = require("../../lib/fireJobs");
const { buildGameDayPayload, eventIdFor } = require("../../lib/planGameDayFires");

const T0 = 1_800_000_000_000;
const H = 3600_000;

// ---------------------------------------------------------------------------
// Payload construction — the TS half of S3b
// ---------------------------------------------------------------------------

describe("buildParticipatingSegArray", () => {
  const seg = () =>
    buildParticipatingSegArray({
      participatingChannelIds: [0, 2],
      effectId: 28,
      speed: 180,
      intensity: 200,
      colorSlots: [[255, 0, 0, 0]],
    });

  test("one segment per participating channel", () => {
    expect(seg()).toHaveLength(2);
    expect(seg().map((s) => s.id)).toEqual([0, 2]);
  });

  test("every segment carries on:true — the channel-2-dark fix", () => {
    // A segment left on:false is NOT re-lit by a top-level on:true.
    for (const s of seg()) expect(s.on).toBe(true);
  });

  test("NO start/stop — WLED retains its install-time ranges", () => {
    // Sending ranges risks the Item #82 wrong-range stomp, and the server
    // could not know them anyway (bus ranges are /json/cfg, LAN-only).
    for (const s of seg()) {
      expect(s).not.toHaveProperty("start");
      expect(s).not.toHaveProperty("stop");
    }
  });

  test("REPLICATES the effect doubling — same fx on every channel", () => {
    // Deliberate: fixing it server-side only would make an unattended fire
    // render differently from the same design fired from the app.
    const s = seg();
    expect(s[0].fx).toBe(28);
    expect(s[1].fx).toBe(28);
  });

  test("empty channel list yields an empty array, never a broadcast", () => {
    expect(
      buildParticipatingSegArray({
        participatingChannelIds: [],
        effectId: 1, speed: 1, intensity: 1, colorSlots: [],
      })
    ).toEqual([]);
  });
});

describe("colour conversion", () => {
  test("ARGB int → rgb triplet", () => {
    expect(argbToRgb(0xff123456)).toEqual([0x12, 0x34, 0x56]);
  });
  test("rgb → RGBW with W=0 (WLED's gamma owns white)", () => {
    expect(toRgbwSlots([[1, 2, 3]])).toEqual([[1, 2, 3, 0]]);
  });
});

// ---------------------------------------------------------------------------
// Saved-design carve-out
// ---------------------------------------------------------------------------

describe("savedDesignUsable", () => {
  test("an effect-shaped saved design is USABLE", () => {
    const p = JSON.stringify({ on: true, bri: 200, seg: [{ fx: 12, col: [[255, 0, 0, 0]] }] });
    expect(savedDesignUsable(p).usable).toBe(true);
  });

  test("REFUSES a per-pixel design — the chunking case", () => {
    // Design Studio per-pixel exceeds one command; chunking has no atomicity
    // and a partial run leaves the strip in neither state, unattended.
    const p = JSON.stringify({ seg: [{ i: [0, 255, 0, 0] }] });
    const v = savedDesignUsable(p);
    expect(v.usable).toBe(false);
    expect(v.reason).toBe("saved_payload_per_pixel");
  });

  test("REFUSES an oversized payload, naming the size", () => {
    const p = JSON.stringify({ on: true, blob: "x".repeat(MAX_FIRE_PAYLOAD_BYTES) });
    const v = savedDesignUsable(p);
    expect(v.usable).toBe(false);
    expect(v.reason).toMatch(/^saved_payload_too_large:/);
  });

  test("refuses unparseable / non-object / absent, each distinctly", () => {
    expect(savedDesignUsable("{oops").reason).toBe("saved_payload_unparseable");
    expect(savedDesignUsable("[1,2]").reason).toBe("saved_payload_not_an_object");
    expect(savedDesignUsable(null).reason).toBe("no_saved_payload");
    expect(savedDesignUsable(undefined).reason).toBe("no_saved_payload");
  });

  test("accepts an object as well as a JSON string", () => {
    expect(savedDesignUsable({ on: true, seg: [{ fx: 1 }] }).usable).toBe(true);
  });

  test("it never silently truncates — every refusal has a reason", () => {
    for (const bad of ["{oops", "[1,2]", null, JSON.stringify({ seg: [{ i: [1] }] })]) {
      const v = savedDesignUsable(bad);
      expect(v.usable).toBe(false);
      expect(v.reason.length).toBeGreaterThan(0);
    }
  });
});

// ---------------------------------------------------------------------------
// The three end-signal guards
// ---------------------------------------------------------------------------

describe("decideEndSignal", () => {
  const base = { sport: "mlb", nowMs: T0 + 4 * H };
  // startPlannedAt is present by default because GUARD 0 (#66) now refuses any
  // session this system did not start, and every test below is about a DIFFERENT
  // guard. Without it all eight short-circuit on `no_start` and stop testing
  // what they were written to test. The guard itself is covered in
  // endRequiresStart.test.js, including the case where this field is absent.
  const st = (o = {}) => ({ gameStartMs: T0, startPlannedAt: T0 + 1000, ...o });

  test("GUARD 1 — one final is NOT enough", () => {
    const d = decideEndSignal({ ...base, espnIsFinal: true, state: st() });
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe("awaiting_confirmation:1");
    expect(d.nextConsecutive).toBe(1);
  });

  test("GUARD 1 — two consecutive finals fire", () => {
    const d = decideEndSignal({
      ...base, espnIsFinal: true, state: st({ consecutiveFinalPolls: 1 }),
    });
    expect(d.fireEnd).toBe(true);
    expect(d.reason).toBe("confirmed_final");
  });

  test("GUARD 1 — a non-final RESETS the run", () => {
    // Two finals separated by a non-final are not two CONSECUTIVE finals;
    // treating them as such defeats the guard on exactly the flapping case.
    const d = decideEndSignal({
      ...base, espnIsFinal: false, state: st({ consecutiveFinalPolls: 1 }),
    });
    expect(d.nextConsecutive).toBe(0);
    expect(d.reason).toBe("not_final");
  });

  test("GUARD 2 — never before gameStart + minimum plausible duration", () => {
    // The stale-final-from-the-previous-meeting case: two finals arriving at
    // first pitch must not end the show.
    const d = decideEndSignal({
      espnIsFinal: true, sport: "mlb", nowMs: T0 + 10 * 60_000,
      state: st({ consecutiveFinalPolls: 5 }),
    });
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toMatch(/^too_early:/);
  });

  test("GUARD 2 — the boundary is exact", () => {
    const min = MIN_PLAUSIBLE_DURATION_DEFAULT_MS;
    const justBefore = decideEndSignal({
      espnIsFinal: true, sport: "unknown_sport", nowMs: T0 + min - 1,
      state: st({ consecutiveFinalPolls: 1 }),
    });
    const atBoundary = decideEndSignal({
      espnIsFinal: true, sport: "unknown_sport", nowMs: T0 + min,
      state: st({ consecutiveFinalPolls: 1 }),
    });
    expect(justBefore.fireEnd).toBe(false);
    expect(atBoundary.fireEnd).toBe(true);
  });

  test("GUARD 3 — once per event, from a WRITTEN marker", () => {
    // Function-local state would lose this on a Cloud Functions retry.
    const d = decideEndSignal({
      ...base, espnIsFinal: true,
      state: st({ consecutiveFinalPolls: 9, endFiredAt: "2026-08-08T00:00:00Z" }),
    });
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe("already_fired");
  });

  test("GUARD 3 outranks everything, including a confirmed final", () => {
    const d = decideEndSignal({
      espnIsFinal: true, sport: "mlb", nowMs: T0 + 10 * H,
      state: st({ consecutiveFinalPolls: 50, endFiredAt: 1 }),
    });
    expect(d.fireEnd).toBe(false);
  });

  test("no game start → refuses rather than assuming", () => {
    const d = decideEndSignal({
      espnIsFinal: true, sport: "mlb", nowMs: T0 + 10 * H,
      // startPlannedAt present so this reaches GUARD 2 rather than being caught
      // by GUARD 0 — the point of this test is the MISSING gameStartMs.
      state: { consecutiveFinalPolls: 1, startPlannedAt: T0 + 1000 },
    });
    expect(d.fireEnd).toBe(false);
    expect(d.reason).toBe("no_game_start");
  });

  test("all three guards must pass together", () => {
    const d = decideEndSignal({
      espnIsFinal: true, sport: "mlb", nowMs: T0 + 4 * H,
      state: st({ consecutiveFinalPolls: REQUIRED_FINAL_POLLS - 1 }),
    });
    expect(d.fireEnd).toBe(true);
  });
});

// ---------------------------------------------------------------------------
// Sunset port
// ---------------------------------------------------------------------------

describe("sunsetUtcMs / daylight filter", () => {
  test("KC in mid-June sets in the evening, not the morning", () => {
    const june = Date.UTC(2026, 5, 21, 12);
    const s = sunsetUtcMs(39.0997, -94.5786, june, -5);
    expect(s).not.toBeNull();
    const localHour = new Date(s - 5 * H).getUTCHours();
    expect(localHour).toBeGreaterThanOrEqual(19);
    expect(localHour).toBeLessThanOrEqual(21);
  });

  test("summer sunset is later than winter sunset at the same place", () => {
    const jun = sunsetUtcMs(39.1, -94.6, Date.UTC(2026, 5, 21, 12), -5);
    const dec = sunsetUtcMs(39.1, -94.6, Date.UTC(2026, 11, 21, 12), -6);
    const h = (ms, off) => new Date(ms - off * H).getUTCHours();
    expect(h(jun, -5)).toBeGreaterThan(h(dec, -6));
  });

  test("polar day returns null rather than a wrong time", () => {
    expect(sunsetUtcMs(78.0, 15.0, Date.UTC(2026, 5, 21, 12), 1)).toBeNull();
  });

  test("a 1pm game that ends well before sunset is daylight-only", () => {
    const start = Date.UTC(2026, 5, 21, 18); // 1pm CDT
    expect(
      isDaylightOnlyGame({
        gameStartMs: start, estimatedDurationMs: 3 * H,
        latitude: 39.1, longitude: -94.6, tzOffsetHours: -5,
      })
    ).toBe(true);
  });

  test("a 7pm game is NOT daylight-only", () => {
    const start = Date.UTC(2026, 5, 22, 0); // 7pm CDT
    expect(
      isDaylightOnlyGame({
        gameStartMs: start, estimatedDurationMs: 3 * H,
        latitude: 39.1, longitude: -94.6, tzOffsetHours: -5,
      })
    ).toBe(false);
  });
});

describe("estimatedDurationMs", () => {
  test("mirrors the client per sport", () => {
    expect(estimatedDurationMs("nfl")).toBe(3.5 * H);
    expect(estimatedDurationMs("mlb")).toBe(3 * H);
    expect(estimatedDurationMs("nba")).toBe(2.5 * H);
    expect(estimatedDurationMs("anything_else")).toBe(3 * H);
  });
});

// ---------------------------------------------------------------------------
// Planner payload — and the fire-safety assertion
// ---------------------------------------------------------------------------

describe("buildGameDayPayload", () => {
  const cfg = (o = {}) => ({
    primary_color: 0xffff0000, secondary_color: 0xff0000ff,
    effect_id: 28, speed: 180, intensity: 200, brightness: 200,
    design_mode: "fallback", ...o,
  });

  test("builds inline state scoped to the participating channels", () => {
    const r = buildGameDayPayload({ config: cfg(), participatingChannels: [0, 1] });
    expect("payload" in r).toBe(true);
    const p = JSON.parse(r.payload);
    expect(p.on).toBe(true);
    expect(p.seg).toHaveLength(2);
    expect(p.seg[0].col[0]).toEqual([255, 0, 0, 0]);
  });

  test("EVERY built payload passes assertPayloadIsFireSafe", () => {
    // Game Day is inline state everywhere — zero presets in the feature. This
    // asserts it rather than trusting the grep.
    const r = buildGameDayPayload({ config: cfg(), participatingChannels: [0] });
    expect(assertPayloadIsFireSafe("applyJson", r.payload).ok).toBe(true);
    expect(r.payload).not.toContain("psave");
    expect(r.payload).not.toContain('"ps"');
  });

  test("refuses when no channels participate rather than broadcasting", () => {
    const r = buildGameDayPayload({ config: cfg(), participatingChannels: [] });
    expect(r.refuse).toBe("no_participating_channels");
  });

  test("a usable saved design ships verbatim, NOT re-expanded", () => {
    // Re-expanding a multi-seg saved design would flatten it onto bus 0.
    const saved = JSON.stringify({ on: true, seg: [{ id: 0, fx: 5 }, { id: 1, fx: 9 }] });
    const r = buildGameDayPayload({
      config: cfg({ design_mode: "saved", saved_design_payload: saved }),
      participatingChannels: [0, 1],
    });
    expect(r.payload).toBe(saved);
  });

  test("a per-pixel saved design is REFUSED, not truncated", () => {
    const r = buildGameDayPayload({
      config: cfg({ design_mode: "saved", saved_design_payload: JSON.stringify({ seg: [{ i: [1, 2] }] }) }),
      participatingChannels: [0],
    });
    expect(r.refuse).toBe("saved_payload_per_pixel");
  });

  test("a saved refusal wins over falling back to a generated design", () => {
    // Silently generating a different design than the customer saved would be
    // worse than not firing: they would see lighting they never chose.
    const r = buildGameDayPayload({
      config: cfg({ design_mode: "saved", saved_design_payload: "{oops" }),
      participatingChannels: [0, 1],
    });
    expect("refuse" in r).toBe(true);
  });
});

describe("eventIdFor", () => {
  test("stable per team+game", () => {
    expect(eventIdFor("nfl_chiefs", "401")).toBe("gd_nfl_chiefs_401");
    expect(eventIdFor("nfl_chiefs", "401")).toBe(eventIdFor("nfl_chiefs", "401"));
  });
  test("different games never collide", () => {
    expect(eventIdFor("nfl_chiefs", "401")).not.toBe(eventIdFor("nfl_chiefs", "402"));
  });
});
