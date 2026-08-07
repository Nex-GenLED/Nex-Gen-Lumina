/**
 * Unit tests for the S6 controller-health contract.
 *
 * Runs against the tsc-compiled output in lib/ — `npm run build` first.
 * No emulator, no firebase-admin IO.
 *
 * Several cases below are anchored to REAL production shapes observed on
 * 2026-08-05 (audit/BRIDGE_TRIAGE.md) rather than invented ones, so a future
 * refactor that breaks the parse of an actual customer payload fails here.
 */

const {
  PROBE_GRACE_MS,
  COLLECT_DELAY_MINUTES,
  WARN_AFTER_CONSECUTIVE_FAILURES,
  ALERT_AFTER_CONSECUTIVE_FAILURES,
  BACKOFF_AFTER_CONSECUTIVE_FAILURES,
  BACKOFF_RETRY_INTERVAL_MS,
  classifyProbe,
  parseWledInfo,
  foldProbeIntoHealth,
  resolveProbeTarget,
  hasInFlightCommand,
  evaluateHealthAlerts,
  shouldSendDigest,
  shouldProbeToday,
  darkForMs,
  buildRoster,
  truncate,
} = require("../../lib/controllerHealth");

const { MIN_SWEEPABLE_AGE_MS, DEFAULT_COMMAND_TTL_MS } = require("../../lib/commandSafety");

const ts = (ms) => ({ toMillis: () => ms });
const T0 = 1_800_000_000_000;
const DAY = 86_400_000;

// ---------------------------------------------------------------------------
// Constants — properties that must not drift
// ---------------------------------------------------------------------------

describe("probe timing constants", () => {
  test("PROBE_GRACE_MS is at least the sweeper's age floor", () => {
    // The sweeper will not even QUERY a command younger than MIN_SWEEPABLE_AGE_MS.
    // A grace below that would be an expiry nothing can enforce — the probe would
    // claim a deadline the sweeper cannot act on.
    expect(PROBE_GRACE_MS).toBeGreaterThanOrEqual(MIN_SWEEPABLE_AGE_MS);
  });

  test("PROBE_GRACE_MS is TIGHTER than the app-watchdog default", () => {
    // The whole point of setting it explicitly: a probe is a liveness
    // measurement, so it must NOT inherit a TTL sized to outlive a user's wait.
    expect(PROBE_GRACE_MS).toBeLessThan(DEFAULT_COMMAND_TTL_MS);
  });

  test("collection happens well after grace + one sweeper tick", () => {
    const requiredMs = PROBE_GRACE_MS + 60_000;
    expect(COLLECT_DELAY_MINUTES * 60_000).toBeGreaterThan(requiredMs * 2);
  });

  test("warn tier fires before alert tier", () => {
    expect(WARN_AFTER_CONSECUTIVE_FAILURES).toBeLessThan(ALERT_AFTER_CONSECUTIVE_FAILURES);
  });
});

// ---------------------------------------------------------------------------
// classifyProbe
// ---------------------------------------------------------------------------

describe("classifyProbe", () => {
  test("completed → success, blame none, latency measured", () => {
    const c = classifyProbe({
      status: "completed",
      createdAt: ts(T0),
      completedAt: ts(T0 + 1_400),
    });
    expect(c.outcome).toBe("completed");
    expect(c.success).toBe(true);
    expect(c.blame).toBe("none");
    expect(c.latencyMs).toBe(1_400);
  });

  test("failed → blame CONTROLLER (bridge picked it up, WLED refused)", () => {
    const c = classifyProbe({ status: "failed", error: "ERROR: HTTP 404" });
    expect(c.outcome).toBe("failed");
    expect(c.success).toBe(false);
    expect(c.blame).toBe("controller");
    expect(c.error).toBe("ERROR: HTTP 404");
  });

  test("expired → blame BRIDGE (nobody picked it up)", () => {
    const c = classifyProbe({ status: "expired" });
    expect(c.outcome).toBe("expired");
    expect(c.blame).toBe("bridge");
  });

  test("expired and failed are NOT collapsed — the S2 distinction survives", () => {
    // Collapsing them destroys the only fleet-visible way to tell "customer's
    // bridge is down" from "customer's controller is down".
    expect(classifyProbe({ status: "expired" }).blame).not.toBe(
      classifyProbe({ status: "failed" }).blame
    );
  });

  test("timeout → blame APP; it is the app's 45s watchdog, not a probe verdict", () => {
    const c = classifyProbe({ status: "timeout" });
    expect(c.outcome).toBe("timeout");
    expect(c.blame).toBe("app");
  });

  test("pending/executing → not a failure", () => {
    expect(classifyProbe({ status: "pending" }).outcome).toBe("pending");
    expect(classifyProbe({ status: "executing" }).outcome).toBe("pending");
    expect(classifyProbe({ status: "executing" }).success).toBe(false);
  });

  test("MISSING document is its own outcome, never a failure", () => {
    // A skipped probe (one-in-flight guard) or a retention-deleted doc must not
    // manufacture a failure. Inventing one is how a monitor starts lying.
    for (const v of [null, undefined]) {
      const c = classifyProbe(v);
      expect(c.outcome).toBe("missing");
      expect(c.success).toBe(false);
      expect(c.blame).toBe("unknown");
    }
  });

  test("negative latency reports null rather than a nonsense number", () => {
    const c = classifyProbe({
      status: "completed",
      createdAt: ts(T0 + 500),
      completedAt: ts(T0),
    });
    expect(c.latencyMs).toBeNull();
  });

  test("missing completedAt yields null latency, not a throw", () => {
    expect(classifyProbe({ status: "completed", createdAt: ts(T0) }).latencyMs).toBeNull();
  });

  test("unbounded error strings are truncated", () => {
    const c = classifyProbe({ status: "failed", error: "x".repeat(5000) });
    expect(c.error).toHaveLength(300);
  });

  test("truncate ignores non-strings", () => {
    expect(truncate(undefined)).toBe("");
    expect(truncate(42)).toBe("");
  });
});

// ---------------------------------------------------------------------------
// parseWledInfo
// ---------------------------------------------------------------------------

describe("parseWledInfo", () => {
  // The EXACT body The Iron Reserve's controller returned at 21:15:58Z on
  // 2026-08-05, the probe that demonstrated this mechanism before it was built.
  const IRON_RESERVE = JSON.stringify({
    ver: "0.15.1",
    vid: 2507300,
    cn: "Kōsen",
    release: "ESP32_Ethernet",
    leds: { count: 300, rgbw: true },
  });

  test("parses the real production payload", () => {
    const i = parseWledInfo(IRON_RESERVE);
    expect(i.wledVersion).toBe("0.15.1");
    expect(i.wledVid).toBe(2507300);
    expect(i.ledCount).toBe(300);
    expect(i.rgbw).toBe(true);
    expect(i.release).toBe("ESP32_Ethernet");
  });

  test("DOES NOT record cn — it is a flash-image default, not a site id", () => {
    // Iron Reserve's controller reports "Kōsen", byte-identical to the bench
    // controller's name. Treating it as an identifier would merge two sites.
    const i = parseWledInfo(IRON_RESERVE);
    expect(Object.keys(i)).not.toContain("cn");
    expect(JSON.stringify(i)).not.toContain("Kōsen");
  });

  test("malformed JSON yields all-nulls and never throws", () => {
    for (const bad of ["not json", "{", "", null, undefined, 42, "[1,2,3]", '"str"']) {
      expect(() => parseWledInfo(bad)).not.toThrow();
      expect(parseWledInfo(bad).wledVersion).toBeNull();
    }
  });

  test("absent leds block does not throw", () => {
    const i = parseWledInfo(JSON.stringify({ ver: "0.15.1" }));
    expect(i.wledVersion).toBe("0.15.1");
    expect(i.ledCount).toBeNull();
    expect(i.rgbw).toBeNull();
  });

  test("wrongly-typed fields are rejected, not coerced", () => {
    const i = parseWledInfo(
      JSON.stringify({ ver: 15, vid: "2507300", leds: { count: "300", rgbw: "yes" } })
    );
    expect(i.wledVersion).toBeNull();
    expect(i.wledVid).toBeNull();
    expect(i.ledCount).toBeNull();
    expect(i.rgbw).toBeNull();
  });
});

// ---------------------------------------------------------------------------
// foldProbeIntoHealth
// ---------------------------------------------------------------------------

describe("foldProbeIntoHealth", () => {
  const bridge = {
    deviceId: "582ABD77687C",
    lastSeenMs: T0,
    firmwareVersion: "1.2",
    status: "paired",
  };
  const info = parseWledInfo(
    JSON.stringify({ ver: "0.15.1", vid: 2507300, leds: { count: 300, rgbw: true } })
  );
  const fold = (previous, classification, i = info) =>
    foldProbeIntoHealth({
      controllerId: "c1",
      previous,
      classification,
      info: i,
      probedAtMs: T0,
      bridge,
      targeting: "server_resolved_ip",
      bridgePresence: "live",
    });

  test("success resets consecutiveFailures and stamps lastSuccessAt", () => {
    const r = fold({ consecutiveFailures: 7 }, classifyProbe({ status: "completed" }));
    expect(r.consecutiveFailures).toBe(0);
    expect(r.lastSuccessAt).toBe(T0);
    expect(r.wledVersion).toBe("0.15.1");
  });

  test("failed increments consecutiveFailures", () => {
    expect(fold({ consecutiveFailures: 2 }, classifyProbe({ status: "failed" })).consecutiveFailures).toBe(3);
  });

  test("expired increments too", () => {
    expect(fold({ consecutiveFailures: 0 }, classifyProbe({ status: "expired" })).consecutiveFailures).toBe(1);
  });

  test("MISSING leaves the counter untouched", () => {
    expect(fold({ consecutiveFailures: 3 }, classifyProbe(null)).consecutiveFailures).toBe(3);
  });

  test("PENDING leaves the counter untouched", () => {
    expect(fold({ consecutiveFailures: 3 }, classifyProbe({ status: "pending" })).consecutiveFailures).toBe(3);
  });

  test("version fields are STICKY across a failure", () => {
    // A failed probe carries no /json/info body. Blanking the last-known version
    // on every failure would destroy the fleet-build signal this exists to collect.
    const previous = {
      consecutiveFailures: 0,
      wledVersion: "0.15.1",
      wledVid: 2507300,
      ledCount: 300,
      rgbw: true,
      wledRelease: "ESP32_Ethernet",
      lastSuccessAt: T0 - DAY,
    };
    const r = fold(previous, classifyProbe({ status: "expired" }), parseWledInfo(null));
    expect(r.wledVersion).toBe("0.15.1");
    expect(r.wledVid).toBe(2507300);
    expect(r.lastSuccessAt).toBe(T0 - DAY); // preserved, and now visibly stale
    expect(r.lastProbeOutcome).toBe("expired");
  });

  test("a first-ever probe with no previous record does not throw", () => {
    const r = fold(null, classifyProbe({ status: "completed" }));
    expect(r.consecutiveFailures).toBe(0);
    expect(r.bridgeDeviceId).toBe("582ABD77687C");
  });
});

// ---------------------------------------------------------------------------
// Q3 — dark-controller backoff (Tyler, 2026-08-07)
// ---------------------------------------------------------------------------

describe("shouldProbeToday — weekly backoff", () => {
  test("no previous record → probe", () => {
    expect(shouldProbeToday(null, T0).probe).toBe(true);
  });

  test("healthy → daily", () => {
    expect(shouldProbeToday({ consecutiveFailures: 0 }, T0)).toEqual({
      probe: true,
      reason: "daily",
    });
  });

  test("stays daily right up to the threshold", () => {
    for (let f = 0; f < BACKOFF_AFTER_CONSECUTIVE_FAILURES; f++) {
      expect(shouldProbeToday({ consecutiveFailures: f, lastProbeAt: T0 }, T0).probe).toBe(true);
    }
  });

  test("at the threshold, a same-day re-probe is refused", () => {
    const r = shouldProbeToday(
      { consecutiveFailures: BACKOFF_AFTER_CONSECUTIVE_FAILURES, lastProbeAt: T0 },
      T0 + DAY
    );
    expect(r).toEqual({ probe: false, reason: "backoff_weekly" });
  });

  test("weekly retry fires at exactly 7 days, not before", () => {
    const prev = { consecutiveFailures: 9, lastProbeAt: T0 };
    expect(shouldProbeToday(prev, T0 + BACKOFF_RETRY_INTERVAL_MS - 1).probe).toBe(false);
    expect(shouldProbeToday(prev, T0 + BACKOFF_RETRY_INTERVAL_MS).probe).toBe(true);
    expect(shouldProbeToday(prev, T0 + BACKOFF_RETRY_INTERVAL_MS).reason).toBe("weekly_retry");
  });

  test("backed off with NO recorded probe → probe rather than stall forever", () => {
    expect(
      shouldProbeToday({ consecutiveFailures: 9, lastProbeAt: null }, T0).probe
    ).toBe(true);
  });

  test("SUCCESS RETURNS TO DAILY on the very next run", () => {
    // The recovery path. A success sets consecutiveFailures to 0, and the
    // cadence is read off that counter — there is no separate state to reset.
    const bridge = { deviceId: "D", lastSeenMs: T0, firmwareVersion: "1.2", status: "paired" };
    const recovered = foldProbeIntoHealth({
      controllerId: "c1",
      previous: { consecutiveFailures: 40, lastProbeAt: T0 - 7 * DAY, firstFailureAt: T0 - 60 * DAY },
      classification: classifyProbe({ status: "completed" }),
      info: parseWledInfo(null),
      probedAtMs: T0,
      bridge,
      targeting: "server_resolved_ip",
      bridgePresence: "live",
    });
    expect(recovered.consecutiveFailures).toBe(0);
    expect(recovered.probeCadence).toBe("daily");
    expect(recovered.firstFailureAt).toBeNull();
    expect(shouldProbeToday(recovered, T0 + DAY)).toEqual({ probe: true, reason: "daily" });
  });

  test("a MISSING collect does NOT advance lastProbeAt — the backoff clock survives", () => {
    // THE BUG THIS PREVENTS: if lastProbeAt were bumped on every collect, the
    // "7 days since last probe" clock would reset daily and the weekly retry
    // would never fire — a dark controller would never be re-checked.
    const bridge = { deviceId: "D", lastSeenMs: null, firmwareVersion: null, status: null };
    const skipped = foldProbeIntoHealth({
      controllerId: "c1",
      previous: { consecutiveFailures: 5, lastProbeAt: T0, lastProbeOutcome: "expired", lastProbeBlame: "bridge" },
      classification: classifyProbe(null), // missing — the probe was skipped
      info: parseWledInfo(null),
      probedAtMs: T0 + DAY,
      bridge,
      targeting: "server_resolved_ip",
      bridgePresence: "silent",
    });
    expect(skipped.lastProbeAt).toBe(T0);               // NOT advanced
    expect(skipped.lastProbeOutcome).toBe("expired");   // last real observation preserved
    expect(skipped.lastCollectedAt).toBe(T0 + DAY);     // but we know the collector ran
    expect(shouldProbeToday(skipped, T0 + DAY).probe).toBe(false);
    expect(shouldProbeToday(skipped, T0 + 7 * DAY).probe).toBe(true);
  });
});

describe("darkForMs — duration independent of sampling rate", () => {
  test("THE 60-DAY CASE: 11 failures at weekly cadence still reads as 60 days", () => {
    // Tyler's exact objection. consecutiveFailures counts PROBES, so under
    // weekly backoff a 60-day outage is ~11. Duration must come from a
    // timestamp, never from the counter.
    const rec = { lastSuccessAt: T0 - 60 * DAY, consecutiveFailures: 11 };
    expect(Math.round(darkForMs(rec, T0) / DAY)).toBe(60);
  });

  test("falls back to firstFailureAt when it never succeeded", () => {
    expect(Math.round(darkForMs({ lastSuccessAt: null, firstFailureAt: T0 - 40 * DAY }, T0) / DAY))
      .toBe(40);
  });

  test("prefers lastSuccessAt over firstFailureAt", () => {
    const rec = { lastSuccessAt: T0 - 5 * DAY, firstFailureAt: T0 - 40 * DAY };
    expect(Math.round(darkForMs(rec, T0) / DAY)).toBe(5);
  });

  test("null when neither is known", () => {
    expect(darkForMs({}, T0)).toBeNull();
  });

  test("never negative on clock skew", () => {
    expect(darkForMs({ lastSuccessAt: T0 + DAY }, T0)).toBe(0);
  });

  test("firstFailureAt stamps the 0→1 transition and does not move after", () => {
    const bridge = { deviceId: "D", lastSeenMs: null, firmwareVersion: null, status: null };
    const fold = (previous, atMs) =>
      foldProbeIntoHealth({
        controllerId: "c1",
        previous,
        classification: classifyProbe({ status: "expired" }),
        info: parseWledInfo(null),
        probedAtMs: atMs,
        bridge,
        targeting: "server_resolved_ip",
        bridgePresence: "silent",
      });
    const first = fold({ consecutiveFailures: 0 }, T0);
    expect(first.firstFailureAt).toBe(T0);
    const second = fold(first, T0 + DAY);
    expect(second.firstFailureAt).toBe(T0); // unmoved
    expect(second.consecutiveFailures).toBe(2);
  });
});

// ---------------------------------------------------------------------------
// Q1 — no-bridge suppression and the roster
// ---------------------------------------------------------------------------

describe("Q1 — no-bridge accounts", () => {
  const row = (uid, email, presence, failures) => ({
    uid,
    email,
    displayName: null,
    record: {
      controllerId: "c1",
      consecutiveFailures: failures,
      lastSuccessAt: null,
      firstFailureAt: T0 - 30 * DAY,
      lastProbeOutcome: "expired",
      lastProbeBlame: "bridge",
      probeCadence: "weekly",
      bridgePresence: presence,
      bridgeDeviceId: presence === "never" ? null : "DEV1",
      bridgeLastSeen: presence === "never" ? null : T0 - 20 * DAY,
    },
  });

  test("`never` accounts are SUPPRESSED from alerts", () => {
    const a = evaluateHealthAlerts({
      health: [row("noBridge", "nb@x.com", "never", 30)],
      registry: [],
      knownUids: new Set(["noBridge"]),
      nowMs: T0,
    });
    expect(a).toHaveLength(0);
  });

  test("`silent` accounts still alert — that is Ellie, and must not be suppressed", () => {
    const a = evaluateHealthAlerts({
      health: [row("ellie", "e@x.com", "silent", 5)],
      registry: [],
      knownUids: new Set(["ellie"]),
      nowMs: T0,
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("controller_unreachable");
  });

  test("alert detail leads with DURATION, not the probe count", () => {
    const a = evaluateHealthAlerts({
      health: [row("ellie", "e@x.com", "silent", 11)],
      registry: [],
      knownUids: new Set(["ellie"]),
      nowMs: T0,
    });
    expect(a[0].ageDays).toBe(30);
    expect(a[0].detail).toContain("dark 30d");
    expect(a[0].detail).toContain("11 failed probe(s) at weekly cadence");
  });

  test("roster SPLITS never-had from had-one-now-silent", () => {
    // "those are different conversations" — one is a sales/records question,
    // the other is a support call.
    const r = buildRoster(
      [
        row("noBridge", "nb@x.com", "never", 30),
        row("ellie", "e@x.com", "silent", 5),
        row("healthy", "h@x.com", "live", 0),
      ],
      T0
    );
    expect(r.never.map((e) => e.who)).toEqual(["nb@x.com"]);
    expect(r.silent.map((e) => e.who)).toEqual(["e@x.com"]);
    expect(r.never[0].silentDays).toBeNull();
    expect(r.silent[0].silentDays).toBe(20);
  });

  test("live controllers never appear in the roster", () => {
    const r = buildRoster([row("healthy", "h@x.com", "live", 0)], T0);
    expect(r.never).toHaveLength(0);
    expect(r.silent).toHaveLength(0);
  });

  test("silent roster is ordered worst-first", () => {
    const a = row("a", "a@x.com", "silent", 5);
    const b = row("b", "b@x.com", "silent", 5);
    b.record.bridgeLastSeen = T0 - 40 * DAY;
    expect(buildRoster([a, b], T0).silent.map((e) => e.who)).toEqual(["b@x.com", "a@x.com"]);
  });
});

// ---------------------------------------------------------------------------
// resolveProbeTarget
// ---------------------------------------------------------------------------

describe("resolveProbeTarget", () => {
  // REGRESSION LOCK. The bench proved on 2026-08-06 that omitting controllerIp
  // sends the command to the bridge's paired-IP fallback, which was STALE:
  // `ERROR: HTTP -1` while 282 commands naming the same controller completed.
  // These tests exist so the "omit is strictly best" advice — which is written
  // down in SCHEDULING_ARCHITECTURE_V2 §8 and reads persuasively — cannot be
  // re-applied without a red suite.

  test("single controller STILL names the ip — never omits", () => {
    const t = resolveProbeTarget({
      controllerId: "c1",
      controllerIp: "10.1.10.240",
      totalControllersForUser: 1,
    });
    expect(t.controllerIp).toBe("10.1.10.240");
    expect(t.targeting).toBe("server_resolved_ip");
  });

  test("multi controller names the server-resolved ip", () => {
    const t = resolveProbeTarget({
      controllerId: "c2",
      controllerIp: "10.1.10.241",
      totalControllersForUser: 3,
    });
    expect(t.controllerIp).toBe("10.1.10.241");
    expect(t.targeting).toBe("server_resolved_ip");
  });

  test("no ip on the controller doc → refuse, never fall back", () => {
    // Falling back to the bridge's paired IP is exactly what produced a false
    // failure on the bench. A skipped probe is honest; a probe to a stale
    // address manufactures a "controller unreachable" alert for a healthy site.
    for (const n of [0, 1, 2, 5]) {
      const t = resolveProbeTarget({
        controllerId: "c",
        controllerIp: null,
        totalControllersForUser: n,
      });
      expect(t.targeting).toBeNull();
      expect(t.controllerIp).toBeNull();
    }
  });

  test("empty-string ip is treated as absent, not as a valid target", () => {
    const t = resolveProbeTarget({
      controllerId: "c",
      controllerIp: "",
      totalControllersForUser: 1,
    });
    expect(t.targeting).toBeNull();
  });

  test("the bridge_paired_fallback targeting value is no longer produced", () => {
    for (const n of [0, 1, 2]) {
      expect(
        resolveProbeTarget({ controllerId: "c", controllerIp: "1.2.3.4", totalControllersForUser: n })
          .targeting
      ).not.toBe("bridge_paired_fallback");
    }
  });
});

// ---------------------------------------------------------------------------
// hasInFlightCommand
// ---------------------------------------------------------------------------

describe("hasInFlightCommand", () => {
  test("blocks on a pending command for the same controller", () => {
    expect(hasInFlightCommand([{ status: "pending", controllerId: "c1" }], "c1")).toBe(true);
  });

  test("blocks on an EXECUTING command too", () => {
    expect(hasInFlightCommand([{ status: "executing", controllerId: "c1" }], "c1")).toBe(true);
  });

  test("blocks on a command with NO controllerId (bridge_health_service shape)", () => {
    // Writes no controllerId at all and targets the paired controller.
    expect(hasInFlightCommand([{ status: "pending" }], "c1")).toBe(true);
  });

  test("blocks on controllerId:'' (bridge_setup_screen shape)", () => {
    expect(hasInFlightCommand([{ status: "pending", controllerId: "" }], "c1")).toBe(true);
  });

  test("does NOT block on a different controller", () => {
    expect(hasInFlightCommand([{ status: "pending", controllerId: "c2" }], "c1")).toBe(false);
  });

  test("terminal statuses never block", () => {
    const terminal = ["completed", "failed", "expired", "timeout"].map((status) => ({
      status,
      controllerId: "c1",
    }));
    expect(hasInFlightCommand(terminal, "c1")).toBe(false);
  });

  test("empty queue never blocks", () => {
    expect(hasInFlightCommand([], "c1")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// evaluateHealthAlerts — anchored to the 2026-08-05 fleet
// ---------------------------------------------------------------------------

describe("evaluateHealthAlerts", () => {
  const NOW = T0;
  const base = { knownUids: new Set(["ellie", "brooke", "tyler"]), nowMs: NOW };
  const healthRow = (uid, email, consecutiveFailures, lastSuccessAt, blame, extra = {}) => ({
    uid,
    email,
    displayName: null,
    record: {
      controllerId: "c1",
      consecutiveFailures,
      lastSuccessAt,
      firstFailureAt: null,
      probeCadence: "daily",
      bridgePresence: "silent",
      lastProbeOutcome: blame === "bridge" ? "expired" : "failed",
      lastProbeBlame: blame,
      bridgeDeviceId: "DEV1",
      ...extra,
    },
  });

  test("ELLIE SHAPE — bridge dark: warn at 1 failure, alert at 2", () => {
    const one = evaluateHealthAlerts({
      ...base,
      health: [healthRow("ellie", "ecochran08@yahoo.com", 1, NOW - DAY, "bridge")],
      registry: [],
    });
    expect(one).toHaveLength(1);
    expect(one[0].kind).toBe("controller_unreachable");
    expect(one[0].severity).toBe("warn");
    expect(one[0].email).toBe("ecochran08@yahoo.com");
    expect(one[0].detail).toContain("bridge unreachable");

    const two = evaluateHealthAlerts({
      ...base,
      health: [healthRow("ellie", "ecochran08@yahoo.com", 2, NOW - 2 * DAY, "bridge")],
      registry: [],
    });
    expect(two[0].severity).toBe("alert");
    expect(two[0].ageDays).toBe(2);
  });

  test("zero failures produces no alert", () => {
    expect(
      evaluateHealthAlerts({
        ...base,
        health: [healthRow("tyler", "t@x.com", 0, NOW, "none")],
        registry: [],
      })
    ).toHaveLength(0);
  });

  test("controller-blamed failure names the CONTROLLER layer, not the bridge", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [healthRow("tyler", "t@x.com", 2, NOW - DAY, "controller")],
      registry: [],
    });
    expect(a[0].detail).toContain("controller unreachable behind a live bridge");
  });

  test("never-probed controller reports the duration AND says so", () => {
    // Post-Q3: a controller that never succeeded still gets a real duration,
    // measured from firstFailureAt, so it is not stuck at "unknown".
    const a = evaluateHealthAlerts({
      ...base,
      health: [
        healthRow("tyler", "t@x.com", 2, null, "bridge", { firstFailureAt: NOW - 9 * DAY }),
      ],
      registry: [],
    });
    expect(a[0].ageDays).toBe(9);
    expect(a[0].detail).toContain("dark 9d (never successfully probed)");
  });

  test("no success AND no first-failure stamp → duration unknown, not a fake zero", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [healthRow("tyler", "t@x.com", 2, null, "bridge")],
      registry: [],
    });
    expect(a[0].ageDays).toBeNull();
    expect(a[0].detail).toContain("duration unknown");
  });

  test("PAIRED BUT SILENT — the bucket-B registry shape", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "D4E9F4FA9D40",
          status: "paired",
          pairedUid: "ellie",
          pendingUid: "",
          lastSeenMs: NOW - 15 * DAY,
          email: "ecochran08@yahoo.com",
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_paired_but_silent");
    expect(a[0].severity).toBe("alert");
    expect(a[0].ageDays).toBe(15);
  });

  test("a paired bridge seen minutes ago is NOT flagged", () => {
    expect(
      evaluateHealthAlerts({
        ...base,
        health: [],
        registry: [
          {
            deviceId: "OK",
            status: "paired",
            pairedUid: "tyler",
            pendingUid: "",
            lastSeenMs: NOW - 60_000,
            email: null,
            displayName: null,
          },
        ],
      })
    ).toHaveLength(0);
  });

  test("IRON RESERVE SHAPE — unpaired but heartbeating right now", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "582ABD77687C",
          status: "unpaired",
          pairedUid: "",
          pendingUid: "",
          lastSeenMs: NOW - 30_000,
          email: null,
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_unpaired_but_heartbeating");
    expect(a[0].severity).toBe("alert");
  });

  test("SUPERSEDED ORPHAN — silent row beside a LIVE sibling is a warn, not an alert", () => {
    // The 2026-08-05 Brooke Rozenberg shape. Without this discriminator the
    // digest puts a healthy customer at the top of the call list.
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "0070077E8F60", // superseded
          status: "paired",
          pairedUid: "brooke",
          pendingUid: "",
          lastSeenMs: NOW - 22 * DAY,
          email: "b@x.com",
          displayName: null,
        },
        {
          deviceId: "D4E9F4FA54B8", // live replacement, same account
          status: "paired",
          pairedUid: "brooke",
          pendingUid: "",
          lastSeenMs: NOW - 30_000,
          email: "b@x.com",
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_superseded_orphan");
    expect(a[0].severity).toBe("warn");
    expect(a[0].deviceId).toBe("0070077E8F60");
    expect(a[0].detail).toContain("NOT a customer outage");
  });

  test("the SAME silent row with no live sibling IS a real outage alert", () => {
    // Same device, same age — only the sibling differs. This is the pair that
    // proves the discriminator is doing the work, not the staleness threshold.
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "0070077E8F60",
          status: "paired",
          pairedUid: "brooke",
          pendingUid: "",
          lastSeenMs: NOW - 22 * DAY,
          email: "b@x.com",
          displayName: null,
        },
      ],
    });
    expect(a[0].kind).toBe("bridge_paired_but_silent");
    expect(a[0].severity).toBe("alert");
  });

  test("a live sibling belonging to a DIFFERENT account does not suppress", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "DARK",
          status: "paired",
          pairedUid: "ellie",
          pendingUid: "",
          lastSeenMs: NOW - 15 * DAY,
          email: "e@x.com",
          displayName: null,
        },
        {
          deviceId: "LIVE",
          status: "paired",
          pairedUid: "brooke", // different uid
          pendingUid: "",
          lastSeenMs: NOW - 30_000,
          email: "b@x.com",
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_paired_but_silent");
    expect(a[0].severity).toBe("alert");
  });

  test("an unpaired bridge silent for weeks is NOT the Iron Reserve shape", () => {
    // 007007745388 — dead and unclaimed for 57 days. Real, but not actionable
    // as a pairing failure, and flagging it daily would be pure noise.
    expect(
      evaluateHealthAlerts({
        ...base,
        health: [],
        registry: [
          {
            deviceId: "007007745388",
            status: "unpaired",
            pairedUid: "",
            pendingUid: "",
            lastSeenMs: NOW - 57 * DAY,
            email: null,
            displayName: null,
          },
        ],
      })
    ).toHaveLength(0);
  });

  test("F-5b SHAPE — registry row claiming a uid with no user document", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "441D64C935AC",
          status: "paired",
          pairedUid: "deleted-account-uid",
          pendingUid: "",
          lastSeenMs: NOW - 60_000,
          email: null,
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_claims_unknown_uid");
    expect(a[0].detail).toContain("F-5b");
  });

  test("the stranded check wins over paired-but-silent (one alert, not two)", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [],
      registry: [
        {
          deviceId: "X",
          status: "paired",
          pairedUid: "gone",
          pendingUid: "",
          lastSeenMs: NOW - 30 * DAY,
          email: null,
          displayName: null,
        },
      ],
    });
    expect(a).toHaveLength(1);
    expect(a[0].kind).toBe("bridge_claims_unknown_uid");
  });

  test("alerts sort before warnings, oldest first — the call-list order", () => {
    const a = evaluateHealthAlerts({
      ...base,
      health: [
        healthRow("ellie", "e@x.com", 1, NOW - DAY, "bridge"), // warn
        healthRow("brooke", "b@x.com", 5, NOW - 20 * DAY, "bridge"), // alert, oldest
        healthRow("tyler", "t@x.com", 2, NOW - 3 * DAY, "bridge"), // alert
      ],
      registry: [],
    });
    expect(a.map((x) => x.severity)).toEqual(["alert", "alert", "warn"]);
    expect(a[0].email).toBe("b@x.com");
  });
});

// ---------------------------------------------------------------------------
// shouldSendDigest
// ---------------------------------------------------------------------------

describe("shouldSendDigest", () => {
  test("any alert sends, on any day", () => {
    for (let d = 0; d < 7; d++) expect(shouldSendDigest(1, d)).toBe(true);
  });

  test("silence on a non-Monday", () => {
    for (const d of [0, 2, 3, 4, 5, 6]) expect(shouldSendDigest(0, d)).toBe(false);
  });

  test("MONDAY ALL-CLEAR sends even with nothing to report", () => {
    // Without this, a silent inbox cannot be distinguished from a monitor that
    // has been throwing for three weeks — the scheduledDataCleanup failure mode.
    expect(shouldSendDigest(0, 1)).toBe(true);
  });
});
