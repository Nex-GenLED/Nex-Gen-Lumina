// #67 — a fire asserts the FULL PARTITION; exclusion means dark, not unchanged.
//
// TYLER'S DECISIONS, 2026-08-13, quoted because they are product choices:
//
//   "fires assert the full partition; non-participating segments get
//    {id: N, on: false} ONLY — look/effect preserved (exclusion = dark for this
//    event; the base restore asserts full state after, so nothing else needs
//    clearing)."
//
//   "Principle, third appearance: unstated segment state is inherited state,
//    and inherited state is a bug."
//
// THE REGRESSION SCENARIO — the bench Twins fire, 2026-08-12 17:10:00Z.
// Participation resolved [0]. The plan row said channels:[0]. The dispatched
// payload carried exactly one segment:
//   {"on":true,"bri":200,"seg":[{"id":0,"on":true,"fx":52,...}]}
// BOTH CHANNELS LIT. Planner and dispatcher were correct end to end; root
// on:true powers the master, which lights every segment whose own `on` is
// already true, so naming a subset stopped channel 1 CHANGING, not LIGHTING.
//
// The bench is a TWO-BUS rig: device channels [0, 1].

const {
  buildFullPartitionSegArray,
  buildParticipatingSegArray,
} = require("../../lib/gameDayPlanning");
const { buildGameDayPayload } = require("../../lib/planGameDayFires");
const { partitionBroadcastPayload } = require("../../lib/applySyncPattern");

const LOOK = {
  effectId: 52,
  speed: 160,
  intensity: 128,
  colorSlots: [
    [0, 43, 92, 0],
    [211, 17, 69, 0],
  ],
};

const DEVICE = [0, 1]; // the bench's two buses

describe("#67 — buildFullPartitionSegArray on the bench's two-bus shape", () => {
  test("THE TWINS REGRESSION: participation [0] darkens channel 1", () => {
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: DEVICE,
      participatingChannelIds: [0],
      ...LOOK,
    });

    expect(seg).toHaveLength(2);
    expect(seg[0]).toEqual({
      id: 0,
      on: true,
      fx: 52,
      sx: 160,
      ix: 128,
      col: LOOK.colorSlots,
    });
    // {id, on:false} and NOTHING else — the whole point of the decision.
    expect(seg[1]).toEqual({ id: 1, on: false });
  });

  test("the excluded entry carries NO look fields — exclusion is not erasure", () => {
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: DEVICE,
      participatingChannelIds: [0],
      ...LOOK,
    });
    const excluded = seg[1];
    expect(Object.keys(excluded).sort()).toEqual(["id", "on"]);
    for (const k of ["fx", "sx", "ix", "col", "bri", "pal"]) {
      expect(excluded[k]).toBeUndefined();
    }
  });

  test("participation [0,1] designs both channels", () => {
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: DEVICE,
      participatingChannelIds: [0, 1],
      ...LOOK,
    });
    expect(seg).toHaveLength(2);
    expect(seg.every((x) => x.on === true && x.fx === 52)).toBe(true);
    expect(seg.map((x) => x.id)).toEqual([0, 1]);
  });

  // REGRESSION SAFETY FOR THE WHOLE LIVE FLEET. #65 means no account can
  // currently produce a non-participating channel, so today every real fire has
  // participation == all channels. The partition MUST be byte-equivalent to the
  // old builder in that case or this change is a fleet-wide behaviour change
  // dressed up as a bug fix.
  test("participation == ALL channels is effect-equivalent to the old builder", () => {
    for (const device of [[0], [0, 1], [0, 1, 2, 3]]) {
      const partitioned = buildFullPartitionSegArray({
        deviceChannelIds: device,
        participatingChannelIds: device,
        ...LOOK,
      });
      const legacy = buildParticipatingSegArray({
        participatingChannelIds: device,
        ...LOOK,
      });
      expect(partitioned).toEqual(legacy);
    }
  });

  test("device order is preserved, not sorted", () => {
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: [2, 0, 1],
      participatingChannelIds: [0],
      ...LOOK,
    });
    expect(seg.map((x) => x.id)).toEqual([2, 0, 1]);
    expect(seg.map((x) => x.on)).toEqual([false, true, false]);
  });

  test("a participating id the DEVICE does not have is dropped, never invented", () => {
    // Addressing hardware that is not there is its own failure mode.
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: [0, 1],
      participatingChannelIds: [0, 7],
      ...LOOK,
    });
    expect(seg.map((x) => x.id)).toEqual([0, 1]);
    expect(seg.find((x) => x.id === 7)).toBeUndefined();
  });

  test("every device channel appears exactly once", () => {
    const seg = buildFullPartitionSegArray({
      deviceChannelIds: [0, 1, 2],
      participatingChannelIds: [1],
      ...LOOK,
    });
    expect(seg.map((x) => x.id)).toEqual([0, 1, 2]);
    expect(new Set(seg.map((x) => x.id)).size).toBe(3);
  });
});

describe("#67 — buildGameDayPayload wiring and the fallback", () => {
  const config = {
    effect_id: 52,
    speed: 160,
    intensity: 128,
    brightness: 200,
    primary_color: 0xff002b5c,
    secondary_color: 0xffd31145,
  };

  test("with device facts: partitioned true, channel 1 dark", () => {
    const out = buildGameDayPayload({
      config,
      participatingChannels: [0],
      deviceChannelIds: DEVICE,
    });
    expect(out.partitioned).toBe(true);
    const seg = JSON.parse(out.payload).seg;
    expect(seg).toHaveLength(2);
    expect(seg[1]).toEqual({ id: 1, on: false });
  });

  // Never guess a partial. Without the device set we cannot know what to
  // exclude, and a fabricated set would darken a channel the customer has.
  test("facts MISSING: falls back to pre-#67 behaviour and says so", () => {
    for (const missing of [undefined, null, []]) {
      const out = buildGameDayPayload({
        config,
        participatingChannels: [0],
        deviceChannelIds: missing,
      });
      expect(out.partitioned).toBe(false);
      const seg = JSON.parse(out.payload).seg;
      expect(seg).toHaveLength(1);
      expect(seg[0].id).toBe(0);
    }
  });

  test("a saved design is passed through and reported unpartitioned", () => {
    const out = buildGameDayPayload({
      config: {
        design_mode: "saved",
        saved_design_payload: '{"seg":[{"id":0,"fx":9},{"id":1,"fx":9}]}',
      },
      participatingChannels: [0],
      deviceChannelIds: DEVICE,
    });
    expect(out.partitioned).toBe(false);
    expect(JSON.parse(out.payload).seg).toHaveLength(2);
  });
});

describe("#67 — partitionBroadcastPayload (Sync)", () => {
  const broadcast = JSON.stringify({
    seg: [{ fx: 88, pal: 5, col: [[255, 0, 0], [0, 0, 255]] }],
  });

  test("the canonical broadcast shape partitions per member", () => {
    const out = partitionBroadcastPayload({
      payloadString: broadcast,
      deviceChannelIds: DEVICE,
      participatingChannelIds: [0],
    });
    expect(out.partitioned).toBe(true);
    const seg = JSON.parse(out.payloadString).seg;
    expect(seg[0]).toMatchObject({ id: 0, on: true, fx: 88, pal: 5 });
    expect(seg[1]).toEqual({ id: 1, on: false });
  });

  test("top-level keys outside seg are preserved", () => {
    const out = partitionBroadcastPayload({
      payloadString: JSON.stringify({ on: true, bri: 200, seg: [{ fx: 88 }] }),
      deviceChannelIds: DEVICE,
      participatingChannelIds: [0],
    });
    const obj = JSON.parse(out.payloadString);
    expect(obj.on).toBe(true);
    expect(obj.bri).toBe(200);
  });

  test("participation == all channels leaves every segment designed", () => {
    const out = partitionBroadcastPayload({
      payloadString: broadcast,
      deviceChannelIds: DEVICE,
      participatingChannelIds: DEVICE,
    });
    const seg = JSON.parse(out.payloadString).seg;
    expect(seg.every((x) => x.on === true && x.fx === 88)).toBe(true);
  });

  // CONSERVATIVE BY CONSTRUCTION — each of these passes through untouched, and
  // each says why. A caller that already addressed its segments is not guessing.
  test("declines, with a reason, on every non-canonical shape", () => {
    const cases = [
      ["partition_unavailable", { deviceChannelIds: null }],
      ["partition_unavailable", { deviceChannelIds: [] }],
      ["participation_unknown", { participatingChannelIds: null }],
      ["not_single_segment", { payloadString: JSON.stringify({ seg: [] }) }],
      [
        "not_single_segment",
        { payloadString: JSON.stringify({ seg: [{ fx: 1 }, { fx: 2 }] }) },
      ],
      ["not_single_segment", { payloadString: JSON.stringify({ on: true }) }],
      [
        "segment_already_addressed",
        { payloadString: JSON.stringify({ seg: [{ id: 0, fx: 1 }] }) },
      ],
      ["unparseable_payload", { payloadString: "not json" }],
    ];
    for (const [reason, over] of cases) {
      const args = Object.assign(
        {
          payloadString: broadcast,
          deviceChannelIds: DEVICE,
          participatingChannelIds: [0],
        },
        over
      );
      const out = partitionBroadcastPayload(args);
      expect(out.partitioned).toBe(false);
      expect(out.reason).toBe(reason);
      expect(out.payloadString).toBe(args.payloadString); // untouched
    }
  });
});
