/**
 * Pure-logic unit tests for the schedule migration helpers.
 *
 * Runs against the tsc-compiled output in ../../lib (run `npm run build`
 * first). No emulator / firebase-admin needed — these cover the tricky,
 * IO-free logic: the id mapping (Dart-parity), trim planning, and backfill
 * diff / idempotency.
 */

const {
  MAX_SCHEDULES,
  scheduleSubDocId,
  getScheduleId,
  scheduleIdOrReason,
  planScheduleTrim,
  planBackfill,
} = require("../../lib/scheduleMigrationShared");

const mk = (id, extra = {}) => ({
  id,
  timeLabel: "7:00 PM",
  repeatDays: ["Mon"],
  actionLabel: "Pattern: Warm White",
  enabled: true,
  ...extra,
});

describe("MAX_SCHEDULES", () => {
  test("is 50, matching the client cap (schedule_providers.dart:461)", () => {
    expect(MAX_SCHEDULES).toBe(50);
  });
});

describe("scheduleSubDocId — parity with Dart schedule_store_sync.dart", () => {
  // FIXTURES: expected outputs are the Dart scheduleSubDocId contract —
  //   slash-free id => unchanged; every '/' => '_'.
  // If the Dart mapping ever changes, THIS fixture must change in lockstep.
  const cases = [
    ["abc123", "abc123"],
    ["a/b/c", "a_b_c"],
    ["x/y", "x_y"],
    ["/leading", "_leading"],
    ["trailing/", "trailing_"],
    ["a//b", "a__b"],
    ["no-slashes-uuid-4f3a", "no-slashes-uuid-4f3a"],
  ];
  for (const [input, expected] of cases) {
    test(`"${input}" -> "${expected}"`, () => {
      expect(scheduleSubDocId(input)).toBe(expected);
    });
  }

  test("the two mappings agree on a '/'-containing id (parity assertion)", () => {
    // The Dart contract: id.contains('/') ? id.replaceAll('/', '_') : id.
    const dartContract = (id) => (id.includes("/") ? id.replace(/\//g, "_") : id);
    for (const id of ["a/b/c", "plain", "//", "p/q"]) {
      expect(scheduleSubDocId(id)).toBe(dartContract(id));
    }
  });
});

describe("getScheduleId", () => {
  test("extracts a valid string id", () => {
    expect(getScheduleId(mk("s1"))).toBe("s1");
  });
  test("returns null for malformed items", () => {
    expect(getScheduleId(null)).toBeNull();
    expect(getScheduleId({})).toBeNull();
    expect(getScheduleId({ id: 42 })).toBeNull();
    expect(getScheduleId({ id: "" })).toBeNull();
    expect(getScheduleId("not-an-object")).toBeNull();
  });
});

describe("scheduleIdOrReason — id or the exact malformed reason", () => {
  test("valid id", () => {
    expect(scheduleIdOrReason(mk("s1"))).toEqual({ id: "s1" });
  });
  test("not-a-map for null / non-object", () => {
    expect(scheduleIdOrReason(null)).toEqual({ skipReason: "not-a-map" });
    expect(scheduleIdOrReason("x")).toEqual({ skipReason: "not-a-map" });
    expect(scheduleIdOrReason(5)).toEqual({ skipReason: "not-a-map" });
  });
  test("missing-id-field", () => {
    expect(scheduleIdOrReason({ timeLabel: "7pm" })).toEqual({
      skipReason: "missing-id-field",
    });
  });
  test("non-string-id names the offending type", () => {
    expect(scheduleIdOrReason({ id: 42 })).toEqual({
      skipReason: "non-string-id (number)",
    });
  });
  test("empty-id", () => {
    expect(scheduleIdOrReason({ id: "" })).toEqual({ skipReason: "empty-id" });
  });
});

describe("planScheduleTrim", () => {
  test("no trim when within cap", () => {
    const items = [mk("a"), mk("b")];
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(false);
    expect(plan.removedIds).toEqual([]);
    expect(plan.kept).toEqual(items);
  });

  test("no trim / empty for non-array", () => {
    const plan = planScheduleTrim(undefined, 50);
    expect(plan.trimmed).toBe(false);
    expect(plan.kept).toEqual([]);
    expect(plan.removedIds).toEqual([]);
  });

  test("keeps the most recent `max`, removes the oldest prefix ids", () => {
    const items = Array.from({ length: 53 }, (_, i) => mk(`s${i}`));
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(true);
    expect(plan.kept).toHaveLength(50);
    // Removed = the first 3 (oldest).
    expect(plan.removedIds).toEqual(["s0", "s1", "s2"]);
    // Kept = last 50, so s2 gone, s3..s52 present.
    expect(getScheduleId(plan.kept[0])).toBe("s3");
    expect(getScheduleId(plan.kept[49])).toBe("s52");
  });

  test("idempotent: re-planning the kept set does not trim", () => {
    const items = Array.from({ length: 60 }, (_, i) => mk(`s${i}`));
    const first = planScheduleTrim(items, 50);
    const second = planScheduleTrim(first.kept, 50);
    expect(second.trimmed).toBe(false);
    expect(second.removedIds).toEqual([]);
  });

  test("removedIds skips malformed items but still trims", () => {
    const items = [
      { id: 123 }, // malformed — no string id
      ...Array.from({ length: 51 }, (_, i) => mk(`s${i}`)),
    ];
    const plan = planScheduleTrim(items, 50);
    expect(plan.trimmed).toBe(true);
    expect(plan.kept).toHaveLength(50);
    // 2 removed (52 - 50): the malformed one (skipped) + s0.
    expect(plan.removedIds).toEqual(["s0"]);
  });
});

describe("planBackfill", () => {
  // existing subcollection docs are now passed as a Map<docId, {sortKey?}>.
  const noneExisting = () => new Map();
  const existingWith = (entries) => new Map(entries); // [[docId, {sortKey}], ...]

  test("fresh backfill: all docs new, sortKey stamped = array index", () => {
    const items = [mk("a"), mk("b/c"), mk("d")];
    const plan = planBackfill(items, noneExisting());
    expect(plan.arrayCount).toBe(3);
    expect(plan.existingCount).toBe(0);
    expect(plan.upserts.map((u) => u.docId)).toEqual(["a", "b_c", "d"]);
    expect(plan.newDocIds).toEqual(["a", "b_c", "d"]);
    expect(plan.skippedMalformed).toBe(0);
    // sortKey = array index, stamped onto both the upsert and the item body.
    expect(plan.upserts.map((u) => u.sortKey)).toEqual([0, 1, 2]);
    expect(plan.upserts.map((u) => u.item.sortKey)).toEqual([0, 1, 2]);
    expect(plan.sortKeyAssignments).toEqual([
      { docId: "a", sortKey: 0 },
      { docId: "b_c", sortKey: 1 },
      { docId: "d", sortKey: 2 },
    ]);
  });

  test("slash id maps to sanitized docId, raw item + wledPayload preserved", () => {
    const item = mk("a/b/c", { wledPayload: '{"on":true,"seg":[{"col":[[255,0,0,0]]}]}' });
    const plan = planBackfill([item], noneExisting());
    expect(plan.upserts[0].docId).toBe("a_b_c");
    // Raw id kept verbatim in the body; wledPayload String untouched.
    expect(plan.upserts[0].item.id).toBe("a/b/c");
    expect(plan.upserts[0].item.wledPayload).toBe(item.wledPayload);
    expect(plan.upserts[0].item.sortKey).toBe(0);
  });

  test("idempotency: converged state yields zero new docs AND does not renumber", () => {
    const items = [mk("a"), mk("b/c"), mk("d")];
    const first = planBackfill(items, noneExisting());
    // Simulate the docs now existing with the keys the first pass assigned.
    const existing = existingWith(
      first.upserts.map((u) => [u.docId, { sortKey: u.sortKey }]),
    );
    const second = planBackfill(items, existing);
    expect(second.newDocIds).toEqual([]);
    expect(second.upserts).toHaveLength(3);
    // Preserved, not renumbered.
    expect(second.upserts.map((u) => u.sortKey)).toEqual([0, 1, 2]);
  });

  test("preserves an existing sortKey even when it differs from the index", () => {
    // Doc "d" already carries sortKey 99 (e.g. client-assigned post-migration);
    // rerun must keep 99, not renumber to its array index 2.
    const items = [mk("a"), mk("b/c"), mk("d")];
    const existing = existingWith([["d", { sortKey: 99 }]]);
    const plan = planBackfill(items, existing);
    expect(plan.upserts.map((u) => ({ id: u.docId, k: u.sortKey }))).toEqual([
      { id: "a", k: 0 }, // absent → index 0
      { id: "b_c", k: 1 }, // absent → index 1
      { id: "d", k: 99 }, // present → preserved
    ]);
  });

  test("malformed items are skipped but still consume their index slot", () => {
    // index:      0        1(bad)    2(bad)  3
    const plan = planBackfill([mk("a"), { id: 7 }, null, mk("b")], noneExisting());
    expect(plan.skippedMalformed).toBe(2);
    expect(plan.upserts.map((u) => u.docId)).toEqual(["a", "b"]);
    // "b" keeps its TRUE array index 3 (gap at 1,2 is harmless — order holds).
    expect(plan.upserts.map((u) => u.sortKey)).toEqual([0, 3]);
    // skippedDetails names each bad index + why (drives the dry-run report).
    expect(plan.skippedDetails).toEqual([
      { index: 1, reason: "non-string-id (number)" },
      { index: 2, reason: "not-a-map" },
    ]);
  });

  test("non-array input yields an empty plan", () => {
    const plan = planBackfill(undefined, noneExisting());
    expect(plan.arrayCount).toBe(0);
    expect(plan.upserts).toEqual([]);
    expect(plan.newDocIds).toEqual([]);
    expect(plan.sortKeyAssignments).toEqual([]);
    expect(plan.skippedDetails).toEqual([]);
  });
});
