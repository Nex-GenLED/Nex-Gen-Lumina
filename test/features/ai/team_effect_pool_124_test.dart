// Build 124, fix d2 — the team effect pool and the palette a team look sends.
//
// The pool [12, 41, 65, 0] was commented "Theater Chase, Running" on its
// siblings; on WLED 0.15.x those ids are Fade, Lighthouse and Palette, and the
// owner's bench (spare controller, 2026-11-10, step 6) saw each misbehave:
// Fade animated half the run, Lighthouse's background read pale yellow,
// Palette showed one still colour. The pool is now the two moving looks the
// owner approved (step 7): Chase 2 (37) and Chase (28), then Solid (0). Both
// read the team's col[] only under pal 0, so the team look states it.

import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/data/team_color_database.dart';
import 'package:nexgen_command/features/ai/cloud_ai_processor.dart';
import 'package:nexgen_command/features/ai/lumina_brain.dart';

void main() {
  test('every team suggests Chase 2, Chase, Solid', () {
    expect(kTeamSuggestedEffects, [37, 28, 0]);
    final chiefs = TeamColorDatabase.allTeams.firstWhere((t) => t.id == 'chiefs');
    expect(chiefs.suggestedEffects, [37, 28, 0]);
    expect(
        TeamColorDatabase.allTeams.every(
            (t) => !t.suggestedEffects.any((fx) => const {12, 41, 65}.contains(fx))),
        isTrue,
        reason: 'no team keeps Fade, Lighthouse or Palette');
  });

  test("Lumina's team look leads with Chase 2 and states pal 0", () {
    final r = LuminaBrain.composeTeamResponse('chiefs design')!;
    final result = CloudAIProcessor.parseAiResponseForTest(r, 'chiefs design');
    final seg = (result.wledPayload!['seg'] as List).first as Map;
    expect(seg['fx'], 37);
    expect(seg['pal'], 0,
        reason: 'without it the chokepoint fills pal 5, under which Chase 2 '
            'takes its colours by position along the run');
    expect(seg['col'], [
      [255, 0, 34, 0],
      [255, 168, 0, 0],
    ], reason: 'the Chiefs LED colours');
  });
}
