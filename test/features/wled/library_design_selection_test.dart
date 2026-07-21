import 'package:flutter_test/flutter_test.dart';
import 'package:nexgen_command/features/wled/colorway_effect_selector.dart'
    show LibraryDesignSelection;

// The return contract of the library's SELECTION mode (the schedule "choose a
// pattern" flow). ColorwayEffectSelectorPage / LibraryBrowserScreen hand back a
// LibraryDesignSelection instead of applying-on-tap; the schedule editor maps
// its fields straight into a PatternSelection → ScheduleItem.wledPayload.
//
// NOTE: the selection-vs-apply widget behavior and the drill-down/z-order
// navigation are provider-heavy + navigation-based and are NOT unit-tested here
// — they need a device/bench run. What IS covered: this return shape, the
// unchanged default apply+save path (game_day_saved_design_firestore_test), and
// the store→ScheduleItem round-trip (schedule_edit_compose_test).
void main() {
  test('carries the raw payload + display fields the editor stores', () {
    const payload = {'on': true, 'bri': 255, 'seg': [<String, dynamic>{}]};
    const sel = LibraryDesignSelection(
      id: 'ocean_breeze',
      name: 'Ocean Breeze - Sparkle',
      wledPayload: payload,
    );
    expect(sel.id, 'ocean_breeze');
    expect(sel.name, 'Ocean Breeze - Sparkle');
    expect(sel.imageUrl, '', reason: 'defaults empty, matching PatternSelection');
    expect(sel.wledPayload, payload,
        reason: 'the raw design payload round-trips into the ScheduleItem');
    expect(sel.wledPayload['on'], true, reason: 'on:true so the timer wakes');
  });
}
