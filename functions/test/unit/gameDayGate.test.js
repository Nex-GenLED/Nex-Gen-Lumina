// GATE REBUILD — per-account readiness, enforced server-side.
//
// WHAT IT REPLACES. `base_layer_gate.dart` says of itself: "⚠️ NOT A GUARD. If
// anything here fails — no context, dialog throws, provider unavailable — the
// enable PROCEEDS." It fired only on the enable toggle and was
// session-dismissible. All nine live Game Day accounts predate it, so it has
// gated nobody; the 2026-08-13 census found SEVEN of the nine with no everyday
// schedule at all.
//
// TYLER'S DECISIONS, 2026-08-13:
//   - R1 (floor) and R3 (participation facts) ENFORCED → log-only on failure,
//     reusing the allowlist's per-account log-only shape, never a second
//     mechanism.
//   - R2 (base ladder) TRI-STATE: true passes, false fails CLOSED,
//     absent is unknown-and-ALLOWED (logged advisory). The fact does not exist
//     yet, so failing closed on absence would log-only the entire fleet.
//   - Graduation is automatic on the next evaluation, and logged.

const {
  evaluateAccountReadiness,
  graduationEvents,
  gateSummary,
  GATE_ADVISORY_LADDER_UNKNOWN,
} = require("../../lib/gameDayGate");

/** A ready account: floor present, facts present, ladder unknown (today's best). */
const ready = (over) =>
  Object.assign(
    {
      hasScheduleArray: true,
      hasScheduleSubcollection: false,
      hasParticipationFacts: true,
      ladderAssertsSegments: null,
    },
    over || {}
  );

describe("R1 floor — the #TD-1 dual state, either counts", () => {
  test("array only -> armed", () => {
    const v = evaluateAccountReadiness(
      ready({ hasScheduleArray: true, hasScheduleSubcollection: false })
    );
    expect(v.armed).toBe(true);
    expect(v.blocking).toEqual([]);
  });

  test("subcollection only -> armed", () => {
    const v = evaluateAccountReadiness(
      ready({ hasScheduleArray: false, hasScheduleSubcollection: true })
    );
    expect(v.armed).toBe(true);
  });

  test("both -> armed", () => {
    const v = evaluateAccountReadiness(
      ready({ hasScheduleArray: true, hasScheduleSubcollection: true })
    );
    expect(v.armed).toBe(true);
  });

  test("NEITHER -> log-only, gated_no_floor", () => {
    const v = evaluateAccountReadiness(
      ready({ hasScheduleArray: false, hasScheduleSubcollection: false })
    );
    expect(v.armed).toBe(false);
    expect(v.blocking).toEqual(["gated_no_floor"]);
  });

  // The distinction the check exists to make. base_boundaries are device timers
  // the healer published; an account can have them and no schedule — Ellie
  // does. Nothing about boundaries may satisfy the floor, so there is no input
  // for them here AT ALL, and this test pins that absence.
  test("the floor has no base_boundaries input to be fooled by", () => {
    const v = evaluateAccountReadiness({
      hasScheduleArray: false,
      hasScheduleSubcollection: false,
      hasParticipationFacts: true,
      base_boundaries: [1, 2, 3], // ignored — not part of the contract
    });
    expect(v.armed).toBe(false);
    expect(v.blocking).toContain("gated_no_floor");
  });
});

describe("R3 participation facts", () => {
  test("absent -> log-only, gated_no_facts", () => {
    const v = evaluateAccountReadiness(ready({ hasParticipationFacts: false }));
    expect(v.armed).toBe(false);
    expect(v.blocking).toEqual(["gated_no_facts"]);
  });
});

describe("R2 base ladder — tri-state, and the asymmetry is the point", () => {
  test("true -> armed, and NO advisory", () => {
    const v = evaluateAccountReadiness(ready({ ladderAssertsSegments: true }));
    expect(v.armed).toBe(true);
    expect(v.advisory).toEqual([]);
  });

  test("false -> log-only (known-bad fails CLOSED)", () => {
    const v = evaluateAccountReadiness(ready({ ladderAssertsSegments: false }));
    expect(v.armed).toBe(false);
    expect(v.blocking).toEqual(["gated_ladder_bad"]);
  });

  test("absent -> ALLOWED, but recorded as advisory", () => {
    for (const unknown of [null, undefined]) {
      const v = evaluateAccountReadiness(
        ready({ ladderAssertsSegments: unknown })
      );
      expect(v.armed).toBe(true);
      expect(v.advisory).toEqual([GATE_ADVISORY_LADDER_UNKNOWN]);
      expect(v.blocking).toEqual([]);
    }
  });

  // THE COERCION TRAP. `!ladderAssertsSegments` is true for false AND for
  // null/undefined. Writing the check that way would collapse unknown into bad
  // and put every account in the fleet into log-only, because the fact does not
  // exist yet. This is the single most consequential line in the gate.
  test("unknown is NOT bad — the fleet is unknown today", () => {
    const unknown = evaluateAccountReadiness(ready({ ladderAssertsSegments: null }));
    const bad = evaluateAccountReadiness(ready({ ladderAssertsSegments: false }));
    expect(unknown.armed).toBe(true);
    expect(bad.armed).toBe(false);
  });
});

describe("multiple failures are all named, not just the first", () => {
  test("no floor AND no facts -> both reasons", () => {
    const v = evaluateAccountReadiness({
      hasScheduleArray: false,
      hasScheduleSubcollection: false,
      hasParticipationFacts: false,
      ladderAssertsSegments: false,
    });
    expect(v.armed).toBe(false);
    expect(v.blocking).toEqual([
      "gated_no_floor",
      "gated_no_facts",
      "gated_ladder_bad",
    ]);
  });
});

describe("graduation — automatic, and legible", () => {
  test("a check turning green emits graduated_<reason>", () => {
    expect(graduationEvents(["gated_no_floor"], [])).toEqual([
      "graduated_gated_no_floor",
    ]);
  });

  test("only the checks that turned green graduate", () => {
    expect(
      graduationEvents(["gated_no_floor", "gated_no_facts"], ["gated_no_facts"])
    ).toEqual(["graduated_gated_no_floor"]);
  });

  test("no change -> no event (a still-gated account is not news every tick)", () => {
    expect(graduationEvents(["gated_no_floor"], ["gated_no_floor"])).toEqual([]);
  });

  // A first evaluation that passes was never gated. Reporting it as a
  // graduation would invent a history the account does not have.
  test("never-evaluated -> not a graduation", () => {
    expect(graduationEvents(null, [])).toEqual([]);
    expect(graduationEvents(undefined, [])).toEqual([]);
    expect(graduationEvents([], [])).toEqual([]);
  });

  test("REGRESSION direction emits nothing — graduation is one-way", () => {
    expect(graduationEvents([], ["gated_no_floor"])).toEqual([]);
  });
});

describe("gateSummary names what is missing, not that something is", () => {
  test("armed", () => {
    expect(gateSummary({ armed: true, blocking: [], advisory: [] })).toBe("armed");
  });

  test("armed but unverified says so", () => {
    expect(
      gateSummary({
        armed: true,
        blocking: [],
        advisory: [GATE_ADVISORY_LADDER_UNKNOWN],
      })
    ).toContain("unverified");
  });

  test("a gated account is told the actionable thing", () => {
    const s = gateSummary(
      evaluateAccountReadiness(
        ready({ hasScheduleArray: false, hasScheduleSubcollection: false })
      )
    );
    expect(s).toContain("log-only");
    expect(s).toContain("no everyday schedule");
  });
});

// The 2026-08-13 census, as fixtures. This is the global-arm worksheet in
// executable form: when these verdicts change, the worksheet has moved.
describe("census fixtures — the nine live accounts as of 2026-08-13", () => {
  const census = [
    ["5oHhaEaf ecochran08",   false, true,  false],
    ["Ayf0rqwN textim6",      false, false, false],
    ["EHRfYGyf cpaschall10",  false, false, false],
    ["NmDukd5r jjdyer1",      false, false, false],
    ["Pqptfawp dnicholas0131", false, true, false],
    ["YcSGiwes stegall.s",    true,  false, false],
    ["cndlN3nm chris_cipollone", true, true, true],
    ["j8eXTfcs marc (#53)",   false, true,  false],
    ["reviewer",              false, false, false],
  ];

  test.each(census)("%s", (_label, floor, facts, expectArmed) => {
    const v = evaluateAccountReadiness({
      hasScheduleArray: floor,
      hasScheduleSubcollection: false,
      hasParticipationFacts: facts,
      ladderAssertsSegments: null, // unknown fleet-wide today
    });
    expect(v.armed).toBe(expectArmed);
  });

  test("exactly ONE of the nine arms today", () => {
    const armed = census.filter(([, floor, facts]) =>
      evaluateAccountReadiness({
        hasScheduleArray: floor,
        hasScheduleSubcollection: false,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      }).armed
    );
    expect(armed).toHaveLength(1);
    expect(armed[0][0]).toContain("cndlN3nm");
  });

  test("every one of the nine is advisory-unknown on R2", () => {
    for (const [, floor, facts] of census) {
      const v = evaluateAccountReadiness({
        hasScheduleArray: floor,
        hasScheduleSubcollection: false,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      });
      expect(v.advisory).toEqual([GATE_ADVISORY_LADDER_UNKNOWN]);
    }
  });
});

const { summarizeGate, formatGateSummary } = require("../../lib/gameDayGate");

describe("summary counter — one aggregate line, derived from the same verdicts", () => {
  // The nine live accounts plus the bench, as the planner sees them today.
  const fleet = () =>
    [
      [false, true],  // 5oHhaEaf
      [false, false], // Ayf0rqwN
      [false, false], // EHRfYGyf
      [false, false], // NmDukd5r
      [false, true],  // Pqptfawp
      [true, false],  // YcSGiwes
      [true, true],   // cndlN3nm  -> armed
      [false, true],  // j8eXTfcs (marc)
      [false, false], // reviewer
      [true, true],   // bench     -> armed
    ].map(([floor, facts]) =>
      evaluateAccountReadiness({
        hasScheduleArray: floor,
        hasScheduleSubcollection: false,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      })
    );

  // EIGHT, not seven. The approved example line read "7 accounts gated
  // {no_floor:7, no_facts:5}" — but those two sets OVERLAP by four, and
  // YcSGiwes fails ONLY R3, so it is gated without appearing in no_floor:7.
  // Distinct gated accounts is the union: 8. This test is why the number is
  // right in the log instead of plausible.
  test("reproduces the 2026-08-13 live tick exactly", () => {
    const c = summarizeGate(fleet());
    expect(c.evaluated).toBe(10);
    expect(c.gated).toBe(8);
    expect(c.armed).toBe(2);
    expect(c.blocking).toEqual({ gated_no_floor: 7, gated_no_facts: 5 });
    expect(c.advisory).toEqual({ gated_no_ladder_unknown: 10 });
  });

  // THE MISREADING THIS EXISTS TO PREVENT. Every account carries the advisory,
  // so a merged figure would say "10 gated" when 7 are gated and 3... 2 are
  // armed. An operator would go looking for three blocks that do not exist.
  test("advisory is NEVER folded into the gated count", () => {
    const c = summarizeGate(fleet());
    const advisoryTotal = Object.values(c.advisory).reduce((a, b) => a + b, 0);
    expect(advisoryTotal).toBe(10);
    expect(c.gated).toBe(8);
    expect(c.gated + c.armed).toBe(c.evaluated);
    expect(c.gated).toBeLessThan(advisoryTotal);
  });

  // Counts are FOLDED from the verdicts the rows are built from, never
  // recomputed from the inputs. This asserts the invariant directly: rebuild
  // the counts from the verdicts a second way and they must agree.
  test("counts are consistent with the verdicts they came from", () => {
    const vs = fleet();
    const c = summarizeGate(vs);
    expect(c.gated).toBe(vs.filter((v) => !v.armed).length);
    expect(c.armed).toBe(vs.filter((v) => v.armed).length);
    for (const [reason, n] of Object.entries(c.blocking)) {
      expect(n).toBe(vs.filter((v) => v.blocking.includes(reason)).length);
    }
    for (const [reason, n] of Object.entries(c.advisory)) {
      expect(n).toBe(vs.filter((v) => v.advisory.includes(reason)).length);
    }
  });

  test("the line reads the way an operator needs it to", () => {
    const line = formatGateSummary(summarizeGate(fleet()));
    expect(line).toBe(
      "gate: 8 accounts gated {no_facts:5, no_floor:7} · " +
        "10 advisory {no_ladder_unknown:10} · 2 armed"
    );
  });

  test("an all-clear fleet says so without an advisory clause", () => {
    const vs = [
      evaluateAccountReadiness({
        hasScheduleArray: true,
        hasScheduleSubcollection: false,
        hasParticipationFacts: true,
        ladderAssertsSegments: true,
      }),
    ];
    expect(formatGateSummary(summarizeGate(vs))).toBe(
      "gate: 0 accounts gated {} · 1 armed"
    );
  });

  test("no accounts evaluated -> zeroes, not a crash", () => {
    const c = summarizeGate([]);
    expect(c).toEqual({ evaluated: 0, gated: 0, armed: 0, blocking: {}, advisory: {} });
  });
});
