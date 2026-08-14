# The Sync geometry layer — spec stub

> ⚠️ **IP NOTICE — DO NOT DISCLOSE PUBLICLY BEFORE COUNSEL.**
> Item 3 below (feet-based multi-home display composition, server-side) is
> assessed as **novel against all known competitors**. Per the IP timeline doc,
> flag to patent counsel **before** any public disclosure — that includes app
> store copy, marketing pages, demo videos, dealer decks, and anything said in
> front of a customer who has not signed an NDA. This document is internal.

**Status:** SPEC STUB. Scoped as its own design session — this is the Sync
architecture's next major, not a fix to be squeezed into a build. Written now so
the three field findings of 2026-08-12 point somewhere instead of accreting
workarounds.

---

## The root the field findings share

**The system has no model of the physical house.** #76 (design payloads clobber
installation geometry), #77 (two channels render as two independent runs), and
#78 (join fabricates 300 px / 49.2 ft) are three symptoms of one absence. Each
is individually fixable and each fix is a patch over the same hole.

Sync currently composes in **pixels**, and pixels are a property of the
installation, not of the display. Two houses with the same frontage and
different densities are, to the current engine, two different-sized canvases.

---

## 1. Per-channel Sync participation

Upgrade the per-member `isParticipating` boolean to a **per-channel set**: each
member chooses which channels/segments take part in Sync.

**Same shape as Game Day's `participating_channels`** — one participation
concept, two consumers. Not a parallel model: the denormalizer, the tri-state
publish discipline, and the "absent means unknown" semantics already exist and
are proven (`participation_denormalizer.dart`, `participationForFire.ts`).

Note the existing `isParticipating` field is documented as a not-yet-wired
STOP-path gate and currently disagrees with `participationStatus` on live member
docs — resolve that inconsistency as part of this, rather than layering on it.

## 2. Join reads real geometry

The joining member's pixel count is **computed from the selected channels' actual
bus data** — the healer's published facts, which already carry the device's bus
list per controller. No fabricated defaults.

Where a home has not yet published (never opened the app on its LAN), the value
is **unknown** and says so. #78's defaults are what makes today's data
untrustworthy: nothing can distinguish a real 300 from a placeholder 300.

## 3. Street-facing width in FEET as the cross-home coordinate

The load-bearing idea. **Displays are composed in linear feet and mapped to each
house's pixels via that house's own density.**

Set per home by the installer or user: the street-facing width in feet. A
two-storey home with 400 px across 200 ft of frontage and a bungalow with 200 px
across 200 ft receive the *same* display, rendered at their own densities.

- **This is the structural fix for #77.** A house's channels stop being
  independent canvases and become segments of one continuous frontage, so a
  design crosses a channel boundary because the boundary is a position in feet,
  not a device edge.
- It is the coordinate system block-wide effects need: a wave travelling down a
  street is only meaningful in feet.
- It is the reason the composition can live server-side: feet are portable
  between homes in a way pixels never are.

---

## Design-session inputs

- The existing roofline/boundary model (`base_boundaries`, the relational
  boundary map proven in Part B slice 5 — moving one boundary adjusted each
  impacted segment, so the map is relational, not a list of ranges).
- `participating_channels` and its publish discipline.
- **#76's rule** — geometry belongs to provisioning, never to design payloads.
  The geometry layer is the owner this rule implies; today there is no owner,
  which is why design paths drifted into writing it.
- Bench fact (2026-08-14): **geometry lives inside presets** — a preset load
  reverts `rev`. Any geometry layer has to decide whether presets or the server
  hold the authority, because today the preset silently wins.

## Open questions for the session

1. Who owns street-facing width — installer during provisioning, or user in
   settings? It determines whether it can be trusted for cross-home composition.
2. Feet as the wire format, or feet-derived normalised 0..1 positions?
3. What a home with unknown geometry does in a crew — excluded, or rendered at
   an assumed density and flagged?
4. Does the geometry layer write to the device (owning `rev`/`start`/`stop`), or
   only describe it? The preset finding above makes this a real fork.
