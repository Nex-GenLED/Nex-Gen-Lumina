// Pre-flight follow-ups from the +114 app build (fix/gameday-espn-slate):
//   #146 — P4 cannot see a lit-but-black ladder. P4b (flag
//          `preflight_ladder_lit`, default off) reads the +114 app's
//          `base_ladder_restore_lit` / `base_ladder_dark_channels`.
//   #150 — MIN_SERVED_APP_BUILD is 114 (step C shipped as +114), not 113.
// PURE: compiled lib/, no Firestore.

const P = require("../../lib/gameDayPreflight");

const NOW = Date.UTC(2026, 9, 11, 17, 0, 0);
const ts = (ms) => ({ toMillis: () => ms });
const controller = (over = {}) => ({
  participating_channels: [0, 1, 2],
  participating_channels_device_ids: [0, 1, 2],
  participating_channels_at: ts(NOW - 86_400_000),
  base_ladder_asserts_segments: true,
  ...over,
});
const inputs = (over = {}) => ({
  bridgePaired: true,
  bridgeStatusUpdateMs: NOW - 30_000,
  controller: controller(),
  gate: { armed: true },
  p6Unreachable: false,
  appVersion: "2.5.10+114",
  nowMs: NOW,
  ...over,
});

describe("#146 — the flag", () => {
  test("only `true` (on) and \"strict\" arm it; absent and everything else is off", () => {
    expect(P.ladderLitModeFrom(undefined)).toBe("off");
    expect(P.ladderLitModeFrom({})).toBe("off");
    expect(P.ladderLitModeFrom({ preflight_ladder_lit: true })).toBe("on");
    expect(P.ladderLitModeFrom({ preflight_ladder_lit: "strict" })).toBe("strict");
    for (const v of [false, "true", 1, "STRICT", "on", null]) {
      expect(P.ladderLitModeFrom({ preflight_ladder_lit: v })).toBe("off");
    }
  });
});

describe("#146 — P4b checkLadderLit", () => {
  test("off: never evaluated, even for a ladder measured dark", () => {
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: false }), "off")).toEqual({ reason: null, info: null });
  });

  test("on: true passes; false skips as preflight_ladder_dark; absent is informational only", () => {
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: true }), "on")).toEqual({ reason: null, info: null });
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: false }), "on")).toEqual({ reason: "preflight_ladder_dark", info: null });
    expect(P.checkLadderLit(controller(), "on")).toEqual({ reason: null, info: "ladder_lit_unknown" });
    expect(P.checkLadderLit(null, "on")).toEqual({ reason: null, info: "ladder_lit_unknown" });
  });

  test("strict: absent is enforced (preflight_ladder_unknown) — once the fleet has reported", () => {
    expect(P.checkLadderLit(controller(), "strict")).toEqual({ reason: "preflight_ladder_unknown", info: null });
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: false }), "strict").reason).toBe("preflight_ladder_dark");
  });

  test("a non-boolean field is NOT taken as true", () => {
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: "true" }), "on")).toEqual({ reason: null, info: "ladder_lit_unknown" });
    expect(P.checkLadderLit(controller({ base_ladder_restore_lit: "true" }), "strict").reason).toBe("preflight_ladder_unknown");
  });

  test("ladderDarkChannels: the published bus ids, [] when absent or malformed", () => {
    expect(P.ladderDarkChannels(controller({ base_ladder_dark_channels: [1, 2] }))).toEqual([1, 2]);
    expect(P.ladderDarkChannels(controller())).toEqual([]);
    expect(P.ladderDarkChannels(controller({ base_ladder_dark_channels: ["1"] }))).toEqual([]);
    expect(P.ladderDarkChannels(null)).toEqual([]);
  });
});

describe("#146 — inside evaluatePreflight", () => {
  test("no `ladderLit` input = A+B exactly: a ladder measured dark still passes", () => {
    const dark = controller({ base_ladder_restore_lit: false, base_ladder_dark_channels: [1] });
    expect(P.evaluatePreflight(inputs({ controller: dark }))).toEqual({ ok: true, reasons: [], info: [] });
    expect(P.evaluatePreflight(inputs({ controller: dark, ladderLit: "off" }))).toEqual({ ok: true, reasons: [], info: [] });
  });

  test("on: a dark ladder fails in check order (after P4); absent passes with the info", () => {
    const dark = controller({ base_ladder_restore_lit: false });
    expect(P.evaluatePreflight(inputs({ controller: dark, ladderLit: "on" }))).toEqual({ ok: false, reasons: ["preflight_ladder_dark"], info: [] });
    expect(P.evaluatePreflight(inputs({ ladderLit: "on" }))).toEqual({ ok: true, reasons: [], info: ["ladder_lit_unknown"] });
    const both = controller({ base_ladder_asserts_segments: false, base_ladder_restore_lit: false });
    expect(P.evaluatePreflight(inputs({ controller: both, ladderLit: "on", gate: { armed: false } })).reasons).toEqual([
      "preflight_ladder_bad",
      "preflight_ladder_dark",
      "preflight_gated",
    ]);
  });

  test("strict with neither ladder fact published names preflight_ladder_unknown ONCE", () => {
    const none = controller({ base_ladder_asserts_segments: undefined });
    expect(P.evaluatePreflight(inputs({ controller: none, ladderLit: "strict" })).reasons).toEqual(["preflight_ladder_unknown"]);
  });

  test("the ladder info sits ahead of P7's (check order)", () => {
    expect(P.evaluatePreflight(inputs({ ladderLit: "on", appVersion: "2.5.10+113" })).info).toEqual(["ladder_lit_unknown", "lease_hygiene_unknown"]);
  });
});

describe("#150 — the first served app build is 114", () => {
  test("MIN_SERVED_APP_BUILD = 114: +113 is reported, +114 and later are not", () => {
    expect(P.MIN_SERVED_APP_BUILD).toBe(114);
    expect(P.checkAppBuild("2.5.10+113")).toBe("lease_hygiene_unknown");
    expect(P.checkAppBuild("2.5.10+114")).toBeNull();
    expect(P.checkAppBuild("2.5.11+115")).toBeNull();
  });

  test("P7 stays informational: a +113 account is ok, with the info", () => {
    expect(P.evaluatePreflight(inputs({ appVersion: "2.5.10+113" }))).toEqual({ ok: true, reasons: [], info: ["lease_hygiene_unknown"] });
  });
});
