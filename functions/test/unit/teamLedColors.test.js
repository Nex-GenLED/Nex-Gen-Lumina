// Team LED colour table — the server MIRROR (src/teamLedColors.ts).
//
// The mirror is generated from lib/data/team_led_colors.dart by
// scripts/gen_team_led_mirror.dart and checked entry for entry by the Dart test
// test/data/team_led_colors_test.dart ("server mirror"). These tests pin the
// lookup contract of the TypeScript file itself.
//
// Build 124: NOT imported by any deployed function. Wiring the planner to it
// (b9eac14, buildGameDayPayload) is a separate gated functions deploy, so the
// payload tests that came with that commit are not here.

const { teamLedRgb, TEAM_LED_RGB } = require("../../lib/teamLedColors");

describe("teamLedRgb", () => {
  test("Packers green: more green, much less blue, full value", () => {
    expect(teamLedRgb(0xff203731)).toEqual([0, 255, 31]);
  });

  test("Chiefs: the owner's bench values (2026-11-10)", () => {
    expect(teamLedRgb(0xffe31837)).toEqual([255, 0, 34]); // red
    expect(teamLedRgb(0xffffb81c)).toEqual([255, 168, 0]); // gold
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
