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
//
// R1 WAS REMOVED 2026-08-26 — product decision, and it reverses the R1 half of
// the 2026-08-13 call above. Game Day must work with ZERO recurring schedules:
// single-day use and Game-Day-only accounts (no recurring schedule, ever) are
// both legitimate and common, and R1 treated them as broken. The census cited
// above is the evidence for the removal, not against it — SEVEN of nine live
// accounts had no everyday schedule, so R1 was gating the majority of real
// users rather than a broken minority. R2 and R3 are UNCHANGED.
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

/** A ready account: facts present, ladder unknown (today's best). */
const ready = (over) =>
  Object.assign(
    {
      hasParticipationFacts: true,
      ladderAssertsSegments: null,
    },
    over || {}
  );

describe("R1 floor — REMOVED; a schedule is no longer a precondition", () => {
  // THE POINT OF THE WHOLE CHANGE. This is the shape that used to be blocked.
  test("no schedule of ANY kind -> ARMED", () => {
    const v = evaluateAccountReadiness({
      hasParticipationFacts: true,
      ladderAssertsSegments: true,
    });
    expect(v.armed).toBe(true);
    expect(v.blocking).toEqual([]);
  });

  // A Game-Day-only account: never had a recurring schedule, never will.
  test("gated_no_floor is never produced, whatever the input", () => {
    const inputs = [
      { hasParticipationFacts: true, ladderAssertsSegments: true },
      { hasParticipationFacts: true, ladderAssertsSegments: null },
      { hasParticipationFacts: false, ladderAssertsSegments: false },
      // Legacy callers may still pass the retired fields; they must be inert,
      // not silently revive the check.
      {
        hasScheduleArray: false,
        hasScheduleSubcollection: false,
        hasParticipationFacts: true,
        ladderAssertsSegments: true,
      },
    ];
    for (const i of inputs) {
      const v = evaluateAccountReadiness(i);
      expect(v.blocking).not.toContain("gated_no_floor");
    }
  });

  test("passing the retired inputs does not change the verdict", () => {
    const withOut = evaluateAccountReadiness(ready({}));
    const withIn = evaluateAccountReadiness(
      ready({ hasScheduleArray: false, hasScheduleSubcollection: false })
    );
    expect(withIn).toEqual(withOut);
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
  test("no facts AND bad ladder -> both reasons", () => {
    const v = evaluateAccountReadiness({
      hasParticipationFacts: false,
      ladderAssertsSegments: false,
    });
    expect(v.armed).toBe(false);
    // Two reasons, not three: gated_no_floor is no longer among them.
    expect(v.blocking).toEqual(["gated_no_facts", "gated_ladder_bad"]);
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
      evaluateAccountReadiness(ready({ hasParticipationFacts: false }))
    );
    expect(s).toContain("log-only");
    expect(s).toContain("controller has not reported its channels");
  });

  // An account with no schedule is not gated at all, so it has no summary to
  // be told anything by. This is the sentence that no longer exists.
  test("no account is ever told to set an everyday schedule", () => {
    const s = gateSummary(evaluateAccountReadiness(ready({})));
    expect(s).not.toContain("no everyday schedule");
    expect(s).toContain("armed");
  });
});

// The 2026-08-13 census, as fixtures. This is the global-arm worksheet in
// executable form: when these verdicts change, the worksheet has moved.
describe("census fixtures — the nine live accounts as of 2026-08-13", () => {
  // Columns: label, hadEverydaySchedule (RETIRED — kept as the record of what
  // R1 was reading), hasParticipationFacts, expectArmed AFTER the R1 removal.
  //
  // The `expectArmed` column is now exactly the `facts` column, and that IS the
  // change: with R1 gone the only thing standing between these accounts and an
  // unattended fire is whether their controller has reported its channels.
  const census = [
    ["5oHhaEaf ecochran08",   false, true,  true],
    ["Ayf0rqwN textim6",      false, false, false],
    ["EHRfYGyf cpaschall10",  false, false, false],
    ["NmDukd5r jjdyer1",      false, false, false],
    ["Pqptfawp dnicholas0131", false, true, true],
    ["YcSGiwes stegall.s",    true,  false, false],
    ["cndlN3nm chris_cipollone", true, true, true],
    ["j8eXTfcs marc (#53)",   false, true,  true],
    ["reviewer",              false, false, false],
  ];

  test.each(census)("%s", (_label, _floor, facts, expectArmed) => {
    const v = evaluateAccountReadiness({
      hasParticipationFacts: facts,
      ladderAssertsSegments: null, // unknown fleet-wide today
    });
    expect(v.armed).toBe(expectArmed);
  });

  // WAS ONE. The census is the evidence FOR the removal, not against it: seven
  // of these nine had no everyday schedule, so R1 was gating the majority of
  // real customers rather than a broken minority.
  test("FOUR of the nine arm now — R1 was holding three of them back", () => {
    const armed = census
      .filter(([, , facts]) =>
        evaluateAccountReadiness({
          hasParticipationFacts: facts,
          ladderAssertsSegments: null,
        }).armed
      )
      .map(([label]) => label);
    expect(armed).toEqual([
      "5oHhaEaf ecochran08",
      "Pqptfawp dnicholas0131",
      "cndlN3nm chris_cipollone",
      "j8eXTfcs marc (#53)",
    ]);
  });

  // The removal, stated as a property over real accounts rather than a fixture.
  test("the retired floor column no longer changes any verdict", () => {
    for (const [, floor, facts] of census) {
      const withFloorAsRecorded = evaluateAccountReadiness({
        hasScheduleArray: floor,
        hasScheduleSubcollection: false,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      });
      const withFloorFlipped = evaluateAccountReadiness({
        hasScheduleArray: !floor,
        hasScheduleSubcollection: !floor,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      });
      expect(withFloorFlipped).toEqual(withFloorAsRecorded);
    }
  });

  test("every one of the nine is advisory-unknown on R2", () => {
    for (const [, , facts] of census) {
      const v = evaluateAccountReadiness({
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      });
      expect(v.advisory).toEqual([GATE_ADVISORY_LADDER_UNKNOWN]);
    }
  });
});

const { summarizeGate, formatGateSummary } = require("../../lib/gameDayGate");

describe("summary counter — INVARIANTS (permanent; these must never drift)", () => {
  // Property-style, deliberately not tied to any account. These hold for every
  // fleet in every state, so they stay true as the worksheet moves.
  const fleets = [
    [],
    [[true, true]],
    [[false, false]],
    [[true, false], [false, true], [true, true], [false, false]],
    Array.from({ length: 25 }, (_, i) => [i % 2 === 0, i % 3 === 0]),
  ].map((rows) =>
    rows.map(([floor, facts]) =>
      evaluateAccountReadiness({
        hasScheduleArray: floor,
        hasScheduleSubcollection: false,
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      })
    )
  );

  test("gated + armed === evaluated, always", () => {
    for (const vs of fleets) {
      const c = summarizeGate(vs);
      expect(c.gated + c.armed).toBe(c.evaluated);
      expect(c.evaluated).toBe(vs.length);
    }
  });

  // THE MISREADING THE LINE EXISTS TO PREVENT. Advisory accounts are ARMED.
  // Folding them into `gated` would send an operator after blocks that do not
  // exist — and today every account carries the R2 advisory, so the overstate
  // would be total.
  test("advisory is never folded into gated", () => {
    for (const vs of fleets) {
      const c = summarizeGate(vs);
      const adv = Object.values(c.advisory).reduce((a, b) => a + b, 0);
      expect(c.gated).toBe(vs.filter((v) => !v.armed).length);
      // Every account here is R2-unknown, so advisory === evaluated and is
      // wholly independent of how many are gated.
      expect(adv).toBe(c.evaluated);
    }
  });

  // Counts are FOLDED from the same verdicts the detail rows are built from.
  // Recomputing from the inputs a second time is how a summary and its own
  // rows come to disagree; this rebuilds them a different way and requires
  // agreement.
  test("counts are derived from the same verdicts as the detail rows", () => {
    for (const vs of fleets) {
      const c = summarizeGate(vs);
      for (const [reason, n] of Object.entries(c.blocking)) {
        expect(n).toBe(vs.filter((v) => v.blocking.includes(reason)).length);
      }
      for (const [reason, n] of Object.entries(c.advisory)) {
        expect(n).toBe(vs.filter((v) => v.advisory.includes(reason)).length);
      }
    }
  });

  test("a gated count is the UNION of reasons, never their sum", () => {
    // Two accounts, each failing BOTH remaining checks: no_facts:2 +
    // ladder_bad:2 but only 2 accounts gated. Summing reasons would say 4.
    // This is the arithmetic that made the approved example line read 7 when
    // the answer was 8. (Pre-R1-removal this used no_floor + no_facts; the
    // property is about the fold, not about which two reasons.)
    const vs = [0, 1].map(() =>
      evaluateAccountReadiness({
        hasParticipationFacts: false,
        ladderAssertsSegments: false,
      })
    );
    const c = summarizeGate(vs);
    expect(c.blocking).toEqual({ gated_no_facts: 2, gated_ladder_bad: 2 });
    expect(c.gated).toBe(2);
  });

  test("the separator is ASCII — this line is read through tooling", () => {
    const line = formatGateSummary(summarizeGate(fleets[3]));
    expect(line).toContain(" | ");
    // Every code unit below 128. Written without a control-character
    // literal on purpose: embedding a raw NUL in a source file to test for
    // ASCII-ness is its own small joke at the reader's expense.
    for (const ch of line) {
      expect(ch.codePointAt(0)).toBeLessThan(128);
    }
  });

  test("all-clear drops the advisory clause; empty fleet does not throw", () => {
    expect(
      formatGateSummary(
        summarizeGate([
          evaluateAccountReadiness({
            hasScheduleArray: true,
            hasScheduleSubcollection: false,
            hasParticipationFacts: true,
            ladderAssertsSegments: true,
          }),
        ])
      )
    ).toBe("gate: 0 accounts gated {} | 1 armed");
    expect(summarizeGate([])).toEqual({
      evaluated: 0, gated: 0, armed: 0, blocking: {}, advisory: {},
    });
  });
});

// ── WORKSHEET SNAPSHOT — a DRIFT DETECTOR, not a gate on the build ──────────
//
// This records the fleet as of a moment. It must never hard-fail: the fleet
// moving is the POINT, and a red build for a customer setting a schedule would
// teach everyone to stop reading it. On divergence it reports the delta and
// passes; updating the snapshot is a deliberate ledger act recording worksheet
// progress.
describe("worksheet snapshot 2026-08-13T15:55Z — drift detector", () => {
  // [label, hasFloor, hasFacts]
  const SNAPSHOT = [
    ["5oHhaEaf ecochran08", false, true],
    ["Ayf0rqwN textim6", false, true], // graduated no_facts 15:55:14Z
    ["EHRfYGyf cpaschall10", false, false],
    ["NmDukd5r jjdyer1", false, false],
    ["Pqptfawp dnicholas0131", false, true],
    ["YcSGiwes stegall.s", true, false],
    ["cndlN3nm chris_cipollone", true, true], // ARMED
    ["j8eXTfcs marc (#53)", false, true],
    ["reviewer", false, false],
    ["wrQRUUKy bench", true, true], // ARMED
  ];

  // The line production emitted at 2026-08-13T15:55:07Z, recorded verbatim
  // except for the separator, which became ASCII in the same commit:
  //
  //   "gate: 8 accounts gated {no_facts:4, no_floor:7} | " +
  //   "10 advisory {no_ladder_unknown:10} | 2 armed"
  //
  // That line is HISTORY and is kept above rather than edited, because it is
  // what production actually said. The baseline below is what the SAME fleet
  // produces once R1 is removed — no account changed, only the rule did. The
  // no_floor:7 term is gone entirely and six accounts arm instead of two.
  const RECORDED =
    "gate: 4 accounts gated {no_facts:4} | " +
    "10 advisory {no_ladder_unknown:10} | 6 armed";

  const current = () =>
    formatGateSummary(
      summarizeGate(
        SNAPSHOT.map(([, , facts]) =>
          evaluateAccountReadiness({
            hasParticipationFacts: facts,
            ladderAssertsSegments: null,
          })
        )
      )
    );

  test("reports drift from the recorded worksheet, and never fails on it", () => {
    const now = current();
    if (now !== RECORDED) {
      // Deliberately not an assertion. The delta is the deliverable.
      console.warn(
        [
          "WORKSHEET DRIFT - the fleet has moved since 2026-08-13T15:55Z.",
          "  recorded: " + RECORDED,
          "  current:  " + now,
          "  Update SNAPSHOT and record the movement in docs/BUILD_LEDGER.md.",
        ].join(String.fromCharCode(10))
      );
    }
    expect(true).toBe(true);
  });

  // What the snapshot is FOR: the two accounts that can fire unattended today.
  test("records which accounts arm — the worksheet's actual question", () => {
    const armed = SNAPSHOT.filter(([, , facts]) =>
      evaluateAccountReadiness({
        hasParticipationFacts: facts,
        ladderAssertsSegments: null,
      }).armed
    ).map(([label]) => label);
    // WAS TWO (cndlN3nm, wrQRUUKy). The R1 removal moves four more accounts
    // from log-only to armed without any of them changing anything.
    expect(armed).toEqual([
      "5oHhaEaf ecochran08",
      "Ayf0rqwN textim6",
      "Pqptfawp dnicholas0131",
      "cndlN3nm chris_cipollone",
      "j8eXTfcs marc (#53)",
      "wrQRUUKy bench",
    ]);
  });
});
