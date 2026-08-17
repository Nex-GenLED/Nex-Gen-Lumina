// #88 — `grp`/`spc` are DESIGN fields. Tyler's decision of record, 2026-08-17.
//
// Pure Dart (no flutter / dart:ui) so every design-payload builder can assert
// the defaults without dragging the provider layer in — the same reason
// channel_power_payload.dart was extracted. wled_payload_utils.dart re-exports
// these, so importers of that file are unaffected.
//
// THE HISTORY, because the sign flipped once and will read as a revert:
//
//   #76 (2026-08-14) stripped grp/spc from seven design-payload builders as
//   INSTALLATION GEOMETRY, alongside rev/mi/of/start/stop. #88 then found four
//   more emitters that were never in that sweep — one of them the interactive
//   colourway picker — so the codebase applied two different rules to the same
//   two fields depending on which screen the user came from. Bench `.150`,
//   capture 20260817T014938Z:
//
//       seg0 [0,128)   len=128  grp=1 spc=2  fx=0   rev=False
//       seg1 [128,290) len=162  grp=1 spc=0  fx=83  rev=True
//
//   `spc=2` with `grp=1` renders every third pixel — ~43 of 128 lit on
//   channel 1, with the two segments disagreeing in a geometry-family field.
//   THE SPLIT WAS THE DEFECT, not either half. It is resolved toward DESIGN: a
//   candy-cane look legitimately owns its spacing, and grouping is how a
//   colourway distributes its colours. `rev`/`mi`/`of`/`start`/`stop` remain
//   geometry and remain unwritable by a design path.
//
// AND THE CONSEQUENCE THAT MATTERS: once they are design, omission stops being
// neutral. Under #67 — *unstated design state is inherited design state, and
// inherited state is a bug* — a plain design applied over a segment carrying
// the stale `spc=2` above would keep rendering every third pixel forever. So a
// design with no opinion ASSERTS the defaults rather than staying silent.

/// One LED per colour band — "no grouping".
const int kDesignDefaultGrp = 1;

/// No dark pixels between bands — "no spacing".
const int kDesignDefaultSpc = 0;

/// Spread into a design seg that has no grouping/spacing of its own:
/// `{...kDesignSpacingDefaults, 'fx': …}`. Place it FIRST so a builder that
/// does own its spacing overrides the default rather than fighting it.
const Map<String, dynamic> kDesignSpacingDefaults = <String, dynamic>{
  'grp': kDesignDefaultGrp,
  'spc': kDesignDefaultSpc,
};
