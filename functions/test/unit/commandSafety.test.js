/**
 * Unit tests for the command-expiry contract (S2).
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * No emulator, no firebase-admin IO.
 */

const {
  DEFAULT_COMMAND_TTL_MS,
  MIN_SWEEPABLE_AGE_MS,
  STATUS_EXPIRED,
  effectiveExpiryMs,
  isExpiredCommand,
  fireJobDocId,
  controllerIpsFrom,
} = require("../../lib/commandSafety");

/** Stand-in for a Firestore Timestamp. */
const ts = (ms) => ({ toMillis: () => ms });

const T0 = 1_800_000_000_000; // fixed epoch; no wall-clock dependence

describe("effectiveExpiryMs", () => {
  test("explicit expiresAt wins over the default TTL", () => {
    // The voice writers' 60s must NOT be widened to the 120s default.
    const doc = { createdAt: ts(T0), expiresAt: ts(T0 + 60_000) };
    expect(effectiveExpiryMs(doc)).toBe(T0 + 60_000);
  });

  test("falls back to createdAt + default TTL when expiresAt is absent", () => {
    expect(effectiveExpiryMs({ createdAt: ts(T0) })).toBe(
      T0 + DEFAULT_COMMAND_TTL_MS
    );
  });

  test("honours a caller-supplied TTL", () => {
    expect(effectiveExpiryMs({ createdAt: ts(T0) }, 5_000)).toBe(T0 + 5_000);
  });

  test("returns null when neither field is readable — never guess", () => {
    expect(effectiveExpiryMs({})).toBeNull();
    expect(effectiveExpiryMs({ createdAt: null, expiresAt: null })).toBeNull();
    // A serverTimestamp not yet resolved reads as null, not as a Timestamp.
    expect(effectiveExpiryMs({ createdAt: undefined })).toBeNull();
  });

  test("ignores a malformed field rather than throwing", () => {
    expect(effectiveExpiryMs({ createdAt: { nope: 1 } })).toBeNull();
    expect(effectiveExpiryMs({ expiresAt: "2026-01-01" })).toBeNull();
  });
});

describe("isExpiredCommand", () => {
  test("not expired one ms before the boundary", () => {
    const doc = { createdAt: ts(T0) };
    expect(isExpiredCommand(doc, T0 + DEFAULT_COMMAND_TTL_MS - 1)).toBe(false);
  });

  test("not expired exactly at the boundary (strict <)", () => {
    const doc = { createdAt: ts(T0) };
    expect(isExpiredCommand(doc, T0 + DEFAULT_COMMAND_TTL_MS)).toBe(false);
  });

  test("expired one ms after the boundary", () => {
    const doc = { createdAt: ts(T0) };
    expect(isExpiredCommand(doc, T0 + DEFAULT_COMMAND_TTL_MS + 1)).toBe(true);
  });

  test("undeterminable age is NEVER expired", () => {
    expect(isExpiredCommand({}, T0 + 10 * 365 * 86_400_000)).toBe(false);
  });

  test("the 60s voice TTL expires earlier than the 120s default would", () => {
    const voice = { createdAt: ts(T0), expiresAt: ts(T0 + 60_000) };
    const app = { createdAt: ts(T0) };
    const at90s = T0 + 90_000;
    expect(isExpiredCommand(voice, at90s)).toBe(true);
    expect(isExpiredCommand(app, at90s)).toBe(false);
  });

  test("the default TTL outlives the app's 45s command watchdog", () => {
    // The property that makes expiry invisible to users: the sweeper only ever
    // acts on commands the app already gave up on.
    const APP_WATCHDOG_MS = 45_000;
    expect(DEFAULT_COMMAND_TTL_MS).toBeGreaterThan(APP_WATCHDOG_MS);
    const doc = { createdAt: ts(T0) };
    expect(isExpiredCommand(doc, T0 + APP_WATCHDOG_MS)).toBe(false);
  });

  test("the sweeper's age floor cannot exceed the smallest TTL in use", () => {
    // If it did, a 60s voice command would slip past the query forever.
    expect(MIN_SWEEPABLE_AGE_MS).toBeLessThanOrEqual(60_000);
  });

  test("a bridge offline for hours has everything expired", () => {
    const sixHours = T0 + 6 * 3_600_000;
    expect(isExpiredCommand({ createdAt: ts(T0) }, sixHours)).toBe(true);
    expect(
      isExpiredCommand({ createdAt: ts(T0), expiresAt: ts(T0 + 60_000) }, sixHours)
    ).toBe(true);
  });
});

describe("STATUS_EXPIRED", () => {
  test('is "expired" and is distinct from "failed"', () => {
    // expired = the bridge was unreachable; failed = the controller was.
    // Telemetry depends on the distinction (V2 §6).
    expect(STATUS_EXPIRED).toBe("expired");
    expect(STATUS_EXPIRED).not.toBe("failed");
  });
});

describe("fireJobDocId", () => {
  test("is deterministic for the same event and instant", () => {
    expect(fireJobDocId("evt_abc", 1800000000)).toBe(
      fireJobDocId("evt_abc", 1800000000)
    );
  });

  test("differs across instants and across events", () => {
    expect(fireJobDocId("evt_abc", 1800000000)).not.toBe(
      fireJobDocId("evt_abc", 1800000060)
    );
    expect(fireJobDocId("evt_abc", 1800000000)).not.toBe(
      fireJobDocId("evt_xyz", 1800000000)
    );
  });

  test("sanitizes characters that are illegal in a Firestore doc id", () => {
    const id = fireJobDocId("users/u1/events/e1", 1800000000);
    expect(id).not.toContain("/");
    expect(id).toMatch(/^fire_[A-Za-z0-9_-]+_\d+$/);
  });

  test("floors fractional seconds so a re-derivation cannot drift", () => {
    expect(fireJobDocId("e", 1800000000.9)).toBe(fireJobDocId("e", 1800000000));
  });
});

describe("controllerIpsFrom", () => {
  test("extracts, dedupes and sorts", () => {
    expect(
      controllerIpsFrom([
        { ip: "192.168.1.151" },
        { ip: "192.168.1.150" },
        { ip: "192.168.1.151" },
      ])
    ).toEqual(["192.168.1.150", "192.168.1.151"]);
  });

  test("drops empty, missing and non-string ip fields", () => {
    expect(
      controllerIpsFrom([
        { ip: "" },
        {},
        { ip: null },
        { ip: 42 },
        { ip: "10.0.0.5" },
      ])
    ).toEqual(["10.0.0.5"]);
  });

  test("is stable across input order — no needless user-doc writes", () => {
    const a = controllerIpsFrom([{ ip: "b" }, { ip: "a" }]);
    const b = controllerIpsFrom([{ ip: "a" }, { ip: "b" }]);
    expect(a).toEqual(b);
  });

  test("empty input yields an empty allowlist, denying every targeted write", () => {
    expect(controllerIpsFrom([])).toEqual([]);
  });
});
