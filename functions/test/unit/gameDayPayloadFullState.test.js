// payload_full_state (default off) — the server start payload states every
// segment field the app's Game Day paths send, so no channel inherits pal, grp,
// spc, frz, its own bri or col[2] from whatever ran on it last.
// audit/MULTICHANNEL_GAMEDAY_AUDIT_2026-10-02.md §1.1 and §4.1
// (fix/115-multichannel-and-design-card).
//
// The 3-bus golden below is the 115 branch's multichannel contract test
// (test/features/game_day/multichannel_seg_array_contract_test.dart,
// "Light it Up Now — the exact array"), the app's wire for the same look: the
// server array must equal it field for field. Synthetic colours only.

const P = require("../../lib/gameDayPlanning");
const { buildGameDayPayload, runPlannerTick } = require("../../lib/planGameDayFires");
const { assertPayloadIsFireSafe } = require("../../lib/fireJobs");
const { makeFakeFirestore } = require("./support/fakeFirestore");
const { installFetchStub } = require("./support/espnFixtures");
const S = require("./support/plannerScenario");

const PRIMARY = [255, 0, 0, 0];
const SECONDARY = [0, 0, 255, 0];
const BLACK = [0, 0, 0, 0];
const FULL_KEYS = ["bri", "col", "frz", "fx", "grp", "id", "ix", "on", "pal", "spc", "sx"];
const config = (over = {}) => ({
  effect_id: 52, speed: 160, intensity: 128, brightness: 200,
  primary_color: 0xffff0000, secondary_color: 0xff0000ff, design_mode: "fallback", ...over,
});
const segsOf = (built) => JSON.parse(built.payload).seg;

// The app's wire for the 3-bus controller (the 115 contract test), all channels.
const APP_GOLDEN_THREE_BUS = [0, 1, 2].map((id) => ({
  id, grp: 1, spc: 0, fx: 52, sx: 160, ix: 128, pal: 0,
  col: [PRIMARY, SECONDARY, BLACK], on: true, bri: 255, frz: false,
}));

describe("the palette an app Game Day fire puts on the wire", () => {
  test("the default fx 52 and every TeamDesignCatalog look are colour-reading → 0", () => {
    for (const fx of [52, 0, 28, 2, 12]) expect(P.gameDayPaletteFor(fx)).toBe(0);
  });

  test("palette-reading: 5 on the bench-verified four, 4 on the rest (the app's wire guard)", () => {
    for (const fx of [64, 42, 90, 89]) expect(P.gameDayPaletteFor(fx)).toBe(5);
    for (const fx of [9, 66, 110]) expect(P.gameDayPaletteFor(fx)).toBe(4);
  });

  test("an id the app catalog does not have → 0, as in the app; the mirrored set is the catalog's 120", () => {
    expect(P.gameDayPaletteFor(999)).toBe(0);
    expect(P.PALETTE_READING_EFFECT_IDS.size).toBe(120);
  });
});

describe("flag OFF — the shipped shape, byte for byte", () => {
  test("absent and false build the same bytes", () => {
    const base = { config: config(), participatingChannels: [0, 1, 2], deviceChannelIds: [0, 1, 2] };
    const a = buildGameDayPayload(base);
    const b = buildGameDayPayload({ ...base, fullState: false });
    expect(b.payload).toBe(a.payload);
    expect(a.payload).toBe(
      '{"on":true,"bri":200,"seg":[' +
        '{"id":0,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]},' +
        '{"id":1,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]},' +
        '{"id":2,"on":true,"fx":52,"sx":160,"ix":128,"col":[[255,0,0,0],[0,0,255,0]]}]}'
    );
  });
});

describe("flag ON — every segment states the full field set", () => {
  const full = (over = {}) =>
    buildGameDayPayload({ config: config(), participatingChannels: [0, 1, 2], deviceChannelIds: [0, 1, 2], fullState: true, ...over });

  test("3 buses: equals the app's wire field for field", () => {
    expect(segsOf(full())).toEqual(APP_GOLDEN_THREE_BUS);
  });

  test("every participating segment: exactly the full key set, three colour slots, no geometry", () => {
    for (const s of segsOf(full())) {
      expect(Object.keys(s).sort()).toEqual(FULL_KEYS);
      expect(s.col).toHaveLength(3);
      expect(s).toMatchObject({ on: true, grp: 1, spc: 0, bri: 255, frz: false });
      for (const k of P.SEGMENT_GEOMETRY_KEYS) expect(s).not.toHaveProperty(k);
    }
  });

  test("an excluded channel: {id, on:false, frz:false} and nothing else (look kept, #67)", () => {
    const segs = segsOf(full({ participatingChannels: [0, 2] }));
    expect(segs[1]).toEqual({ id: 1, on: false, frz: false });
    expect(segs[0]).toEqual(APP_GOLDEN_THREE_BUS[0]);
    expect(segs[2]).toEqual(APP_GOLDEN_THREE_BUS[2]);
  });

  test("no device set known: the participating-only fallback states the full set too", () => {
    const segs = segsOf(full({ deviceChannelIds: null }));
    expect(segs).toEqual(APP_GOLDEN_THREE_BUS);
  });

  test("a palette-reading effect carries its wire palette", () => {
    expect(segsOf(full({ config: config({ effect_id: 9 }) })).map((s) => s.pal)).toEqual([4, 4, 4]);
  });

  test("under the 4,096-byte cap for a 3-bus controller, and fire-safe", () => {
    const built = full();
    expect(built.payload.length).toBeLessThan(P.MAX_FIRE_PAYLOAD_BYTES);
    expect(assertPayloadIsFireSafe("applyJson", built.payload).ok).toBe(true);
    // The root is unchanged: on + the config's brightness.
    expect(JSON.parse(built.payload)).toMatchObject({ on: true, bri: 200 });
  });

  test("a saved design is not touched (it carries its own shape)", () => {
    const saved = '{"on":true,"seg":[{"id":0,"fx":2,"col":[[1,2,3]]}]}';
    const c = config({ design_mode: "saved", saved_design_payload: saved });
    expect(full({ config: c }).payload).toBe(saved);
  });
});

describe("in a real tick — per account (true or a uid list)", () => {
  async function mint(flags) {
    const f = makeFakeFirestore({ now: S.T.T1 });
    S.seedWorld(f);
    S.heartbeat(f);
    const stub = installFetchStub(S.espnRoute("T1"));
    try {
      await runPlannerTick(f.db, S.T.T1, { forcePolicy: { enabled: true, allowlist: S.ALLOWLIST }, forceFlags: flags });
    } finally {
      stub.restore();
    }
    return {
      alpha: JSON.parse(f.get(`users/u_alpha/fire_jobs/gd_nfl_alpha_${S.EV.nfl}_start`).payload),
      delta: JSON.parse(f.get(`users/u_delta/fire_jobs/gd_mlb_mariner_${S.EV.mlb}_start`).payload),
    };
  }

  test("payload_full_state: [u_alpha] — that account's start states the full set; another's is unchanged", async () => {
    const on = await mint({ payloadFullState: ["u_alpha"] });
    const off = await mint({});
    for (const s of on.alpha.seg) expect(Object.keys(s).sort()).toEqual(FULL_KEYS);
    expect(on.delta).toEqual(off.delta);
    expect(Object.keys(off.alpha.seg[0]).sort()).toEqual(["col", "fx", "id", "ix", "on", "sx"]);
  });

  test("true — every armed account's start states it", async () => {
    const on = await mint({ payloadFullState: true });
    for (const p of [on.alpha, on.delta]) for (const s of p.seg) expect(Object.keys(s).sort()).toEqual(FULL_KEYS);
  });
});
