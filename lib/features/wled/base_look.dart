// lib/features/wled/base_look.dart
//
// THE BASE LOOK — what the NGL ON ladder (presets 1/3/4/5) shows when it fires.
//
// WHY A FIXED LOOK. Until +114 the ladder psaved `{on, bri, ib, seg:[{id, on}]}`
// and nothing else. A `psave` merges its inline state over the controller's
// CURRENT live state, so every field the payload did not name — colour, effect,
// palette — was captured from whatever the house happened to be showing at the
// moment of the save. A ladder saved during a black-coloured scene stores a
// black base layer: master on, every segment on, nothing lit. That is the same
// ambient-capture defect `audit/BASE_LADDER.md` closed for `on`, one field over.
// Naming the look removes the capture entirely: what the ladder fires is a
// constant, not an accident of timing.
//
// WHAT IT IS. Lumina Blue, RGB 0,212,255, white channel 0, effect 0 (Solid),
// second and third colour slots black. The same RGB as `NexGenPalette.cyan`
// (`app_colors.dart`), which a test pins, so the house and the app agree on
// what "Lumina Blue" means.
//
// ONE DEFINITION. Every ladder ON writer builds its segments through
// [baseLookSegmentFields] — schedule sync's ladder psaves, and the on-connect
// ladder repair. The restore-lit check reads the same constants to recognise a
// lit preset. A second spelling of the look anywhere is a bug.
//
// PURE DART. No Flutter imports, so the healer, schedule sync and tests share it
// without a binding.

/// The base look's red, green, blue and white channel values.
const int kBaseLookRed = 0;
const int kBaseLookGreen = 212;
const int kBaseLookBlue = 255;
const int kBaseLookWhite = 0;

/// WLED effect 0 is Solid: the whole segment shows colour slot 1.
const int kBaseLookEffectId = 0;

/// What the customer is told the base look is called.
const String kBaseLookName = 'Lumina Blue';

/// The segment keys the base look WRITES.
///
/// `ScheduleSyncService.presetSatisfies` deliberately does NOT compare these.
/// Every ladder preset on the installed fleet was saved before the look existed
/// and holds whatever colour it captured; asserting the look would mark all of
/// them unsatisfied and re-save the ladder on every controller at the next sync
/// — a fleet-wide flash-write pass with a visible light change per house,
/// started by an unrelated schedule edit. Replacing a DARK ladder is the
/// on-connect repair's job, under its own guards (`base_ladder_repair.dart`),
/// not the satisfaction predicate's.
const Set<String> kBaseLookSegmentKeys = <String>{'fx', 'col'};

/// The three WLED colour slots of the base look, as fresh lists (a caller that
/// mutates its payload must not mutate the next caller's).
List<List<int>> baseLookColSlots() => <List<int>>[
      <int>[kBaseLookRed, kBaseLookGreen, kBaseLookBlue, kBaseLookWhite],
      <int>[0, 0, 0, 0],
      <int>[0, 0, 0, 0],
    ];

/// The fields every lit ladder segment carries, merged into a seg entry beside
/// its `id` and `on`.
Map<String, dynamic> baseLookSegmentFields() => <String, dynamic>{
      'fx': kBaseLookEffectId,
      'col': baseLookColSlots(),
    };
