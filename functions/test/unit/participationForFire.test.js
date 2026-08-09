/**
 * Unit tests for the S3b server-side participation contract.
 * Runs against compiled lib/ — `npm run build` first.
 */

const {
  PARTICIPATION_MAX_AGE_MS,
  participationForFire,
  isEmptyParticipation,
} = require("../../lib/participationForFire");

const ts = (ms) => ({ toMillis: () => ms });
const T0 = 1_800_000_000_000;
const DAY = 86_400_000;

const doc = (over = {}) => ({
  participating_channels: [0, 1],
  participating_channels_at: ts(T0 - DAY),
  participating_channels_device_ids: [0, 1, 2],
  participating_channels_source: "game_day",
  ...over,
});

describe("participationForFire", () => {
  test("a fresh, well-formed set is usable", () => {
    const v = participationForFire(doc(), T0);
    expect(v.usable).toBe(true);
    expect(v.channels).toEqual([0, 1]);
    expect(v.reason).toBe("ok");
    expect(v.ageMs).toBe(DAY);
  });

  test("NEVER RESOLVED — absent controller, absent field, or null", () => {
    for (const c of [
      null,
      undefined,
      {},
      doc({ participating_channels: undefined }),
      doc({ participating_channels: null }),
    ]) {
      const v = participationForFire(c, T0);
      expect(v.usable).toBe(false);
      expect(v.reason).toBe("never_resolved");
      expect(v.channels).toBeNull();
    }
  });

  test("never_resolved is the EXPECTED state for every controller until the app publishes", () => {
    // There is no server-side backfill: the input (the hardware bus list) is
    // only readable over /json/cfg, which is LAN-only.
    expect(participationForFire({}, T0).reason).toBe("never_resolved");
  });

  test("MALFORMED is distinct from never_resolved", () => {
    for (const bad of [
      "0,1",
      [0, "1"],
      [0, 1.5],
      [-1],
      [null],
      {},
      [[0]],
    ]) {
      const v = participationForFire(doc({ participating_channels: bad }), T0);
      expect(v.usable).toBe(false);
      expect(v.reason).toBe("malformed");
    }
  });

  test("NO TIMESTAMP → unusable, never assumed fresh", () => {
    for (const at of [undefined, null, "yesterday", {}]) {
      const v = participationForFire(doc({ participating_channels_at: at }), T0);
      expect(v.usable).toBe(false);
      expect(v.reason).toBe("no_timestamp");
    }
  });

  test("STALE past the horizon → refused, with the age named", () => {
    const v = participationForFire(
      doc({ participating_channels_at: ts(T0 - 100 * DAY) }),
      T0
    );
    expect(v.usable).toBe(false);
    expect(v.reason).toBe("stale:100d");
    expect(v.ageMs).toBe(100 * DAY);
  });

  test("the horizon boundary is exact", () => {
    const atLimit = participationForFire(
      doc({ participating_channels_at: ts(T0 - PARTICIPATION_MAX_AGE_MS) }),
      T0
    );
    expect(atLimit.usable).toBe(true);
    const past = participationForFire(
      doc({ participating_channels_at: ts(T0 - PARTICIPATION_MAX_AGE_MS - 1) }),
      T0
    );
    expect(past.usable).toBe(false);
  });

  test("an EMPTY set is USABLE and means 'nothing to light'", () => {
    // Distinct from "we do not know". They look identical at the fire — no
    // command — and are completely different to explain to an operator.
    const v = participationForFire(doc({ participating_channels: [] }), T0);
    expect(v.usable).toBe(true);
    expect(v.channels).toEqual([]);
    expect(isEmptyParticipation(v)).toBe(true);
  });

  test("a non-empty usable set is not 'empty participation'", () => {
    expect(isEmptyParticipation(participationForFire(doc(), T0))).toBe(false);
  });

  test("an unusable verdict is never reported as empty participation", () => {
    expect(isEmptyParticipation(participationForFire({}, T0))).toBe(false);
  });

  test("clock skew does not produce a negative age", () => {
    const v = participationForFire(
      doc({ participating_channels_at: ts(T0 + DAY) }),
      T0
    );
    expect(v.ageMs).toBe(0);
    expect(v.usable).toBe(true);
  });

  test("every refusal reason is distinct, so the operator learns WHY", () => {
    const reasons = new Set([
      participationForFire({}, T0).reason,
      participationForFire(doc({ participating_channels: "x" }), T0).reason,
      participationForFire(doc({ participating_channels_at: null }), T0).reason,
      participationForFire(
        doc({ participating_channels_at: ts(T0 - 200 * DAY) }),
        T0
      ).reason,
    ]);
    expect(reasons.size).toBe(4);
  });

  test("the horizon matches the Dart-side constant (90 days)", () => {
    expect(PARTICIPATION_MAX_AGE_MS).toBe(90 * DAY);
  });
});
