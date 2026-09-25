// Team LED colours on the server fire path.
//
// users/{uid}/game_day_autopilot/{slug} stores the team's BRAND colour
// (`primary_color` / `secondary_color`, ARGB ints written once at addTeam). A
// brand hex lit at LED intensity reads wrong — Green Bay's #203731 has B ≈ G
// and shows teal — so buildGameDayPayload sends the calibrated LED colour.
// The table is a mirror of lib/data/team_led_colors.dart; the Dart test
// test/data/team_led_colors_test.dart fails if the two drift.

const { teamLedRgb, TEAM_LED_RGB } = require("../../lib/teamLedColors");
const { buildGameDayPayload } = require("../../lib/planGameDayFires");

const PACKERS = {
  primary_color: 0xff203731, // brand green
  secondary_color: 0xffffb612, // brand gold
  effect_id: 52,
  speed: 160,
  intensity: 128,
  brightness: 200,
};

describe("teamLedRgb", () => {
  test("Packers green: more green, much less blue, full value", () => {
    expect(teamLedRgb(0xff203731)).toEqual([0, 255, 31]);
  });

  test("alpha is ignored — the stored ARGB int resolves like its RGB", () => {
    expect(teamLedRgb(0xff203731)).toEqual(teamLedRgb(0x203731));
  });

  test("a colour that is not a team colour passes through unchanged", () => {
    expect(TEAM_LED_RGB.has(0x123457)).toBe(false);
    expect(teamLedRgb(0xff123457)).toEqual([0x12, 0x34, 0x57]);
  });

  test("every entry is full value except black (off)", () => {
    for (const [brand, led] of TEAM_LED_RGB) {
      if (led[0] === 0 && led[1] === 0 && led[2] === 0) continue;
      expect([brand, Math.max(...led)]).toEqual([brand, 255]);
    }
  });
});

describe("buildGameDayPayload sends LED colours, not the brand hex", () => {
  test("partitioned fire: participating seg carries the LED colours", () => {
    const out = buildGameDayPayload({
      config: PACKERS,
      participatingChannels: [0],
      deviceChannelIds: [0, 1],
    });
    const seg = JSON.parse(out.payload).seg;
    expect(seg[0].col).toEqual([
      [0, 255, 31, 0],
      [255, 180, 13, 0],
    ]);
    expect(seg[1]).toEqual({ id: 1, on: false });
  });

  test("unpartitioned fallback: same LED colours", () => {
    const out = buildGameDayPayload({ config: PACKERS, participatingChannels: [0] });
    const seg = JSON.parse(out.payload).seg;
    expect(seg[0].col[0]).toEqual([0, 255, 31, 0]);
    expect(seg[0].col[0]).not.toEqual([32, 55, 49, 0]);
  });

  test("a user's custom colour ships as picked", () => {
    const out = buildGameDayPayload({
      config: { ...PACKERS, primary_color: 0xff123457 },
      participatingChannels: [0],
    });
    expect(JSON.parse(out.payload).seg[0].col[0]).toEqual([0x12, 0x34, 0x57, 0]);
  });

  test("a saved design is forwarded verbatim (its colours were chosen on a preview)", () => {
    const saved = '{"seg":[{"id":0,"fx":0,"col":[[32,55,49,0]]}]}';
    const out = buildGameDayPayload({
      config: { design_mode: "saved", saved_design_payload: saved },
      participatingChannels: [0],
    });
    expect(out.payload).toBe(saved);
  });
});
