/**
 * Relay eligibility (2026-09-30) — the pure parts.
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * The Firestore-backed half (hasPairedBridge, failFastIfNoPairedBridge) is
 * covered by test/emulator/relayEligibility.emulator.test.ts.
 */

const {
  NO_BRIDGE_PAIRED_ERROR,
  EXPIRED_NO_BRIDGE_TEXT,
  EXPIRED_BRIDGE_OFFLINE_TEXT,
  probeSkipReason,
  isPairingPing,
  isMonitoringExcluded,
} = require("../../lib/relayEligibility");
const { expiryErrorText } = require("../../lib/sweepExpiredCommands");

describe("constants the app and the digest match on", () => {
  test("the fail-fast error code is stable", () => {
    expect(NO_BRIDGE_PAIRED_ERROR).toBe("no_bridge_paired");
  });

  test("the two expiry wordings are distinct and name their cause", () => {
    expect(EXPIRED_NO_BRIDGE_TEXT).not.toBe(EXPIRED_BRIDGE_OFFLINE_TEXT);
    expect(EXPIRED_NO_BRIDGE_TEXT).toMatch(/no bridge is paired/);
    expect(EXPIRED_BRIDGE_OFFLINE_TEXT).toMatch(/bridge offline or unreachable/);
  });

  test("the legacy wording is unchanged for paired accounts", () => {
    expect(EXPIRED_BRIDGE_OFFLINE_TEXT).toBe(
      "Command expired before the bridge picked it up (bridge offline or " +
        "unreachable at fire time)."
    );
  });
});

describe("expiryErrorText", () => {
  test("paired → bridge offline; unpaired → no bridge", () => {
    expect(expiryErrorText(true)).toBe(EXPIRED_BRIDGE_OFFLINE_TEXT);
    expect(expiryErrorText(false)).toBe(EXPIRED_NO_BRIDGE_TEXT);
  });
});

describe("probeSkipReason", () => {
  test("monitoring_exclude wins over everything", () => {
    expect(probeSkipReason({ bridgePaired: true, monitoringExcluded: true })).toBe(
      "monitoring_excluded"
    );
    expect(probeSkipReason({ bridgePaired: false, monitoringExcluded: true })).toBe(
      "monitoring_excluded"
    );
  });

  test("no paired bridge → skipped, so no doomed probe is queued", () => {
    expect(probeSkipReason({ bridgePaired: false, monitoringExcluded: false })).toBe(
      "no_paired_bridge"
    );
  });

  test("paired and not excluded → proceed", () => {
    expect(probeSkipReason({ bridgePaired: true, monitoringExcluded: false })).toBeNull();
  });
});

describe("isPairingPing — the wizard's untargeted ping is exempt", () => {
  test("type ping with empty / absent controllerIp", () => {
    expect(isPairingPing({ type: "ping", controllerIp: "" })).toBe(true);
    expect(isPairingPing({ type: "ping" })).toBe(true);
    expect(isPairingPing({ type: "ping", controllerIp: null })).toBe(true);
  });

  test("the launch ping names a controller and is NOT exempt", () => {
    expect(isPairingPing({ type: "ping", controllerIp: "192.0.2.150" })).toBe(false);
  });

  test("other commands are never exempt", () => {
    expect(isPairingPing({ type: "getState", controllerIp: "" })).toBe(false);
    expect(isPairingPing({ type: "getInfo" })).toBe(false);
  });
});

describe("isMonitoringExcluded — read-only flag", () => {
  const doc = (fields) => ({ get: (f) => fields[f] });

  test("true only for an explicit boolean true", () => {
    expect(isMonitoringExcluded(doc({ monitoring_exclude: true }))).toBe(true);
    expect(isMonitoringExcluded(doc({ monitoring_exclude: "true" }))).toBe(false);
    expect(isMonitoringExcluded(doc({ monitoring_exclude: 1 }))).toBe(false);
    expect(isMonitoringExcluded(doc({}))).toBe(false);
    expect(isMonitoringExcluded(null)).toBe(false);
    expect(isMonitoringExcluded(undefined)).toBe(false);
  });
});
