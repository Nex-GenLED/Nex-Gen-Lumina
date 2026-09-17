# Lumina How-To's — 2026.09 Refresh

**Rev 2026.09 · Edition date 2026-09-17 · Describes Lumina app 2.5.10+98 and Lumina Bridge firmware v1.2.**

Seven ready-to-replace drafts for the "Lumina How-To's" set. These are drafts for review, not
published files — nothing here overwrites the live guides in `docs/`.

| File | Audience | Replaces |
|---|---|---|
| [`01-feature-overview.md`](01-feature-overview.md) | Prospects, marketing | *(new — no prior one-pager)* |
| [`02-homeowner-guide.md`](02-homeowner-guide.md) | Homeowners | `docs/Lumina_Homeowner_Guide.md` |
| [`03-commercial-guide.md`](03-commercial-guide.md) | Commercial operators | `docs/User_Guide_Commercial.md` |
| [`04-installer-guide.md`](04-installer-guide.md) | Installer crews | `docs/Dealer_Installer_Setup_Guide.md` (§7–11) |
| [`05-dealer-guide.md`](05-dealer-guide.md) | Dealer principals | `docs/Dealer_Dashboard_Guide.md` |
| [`06-admin-guide.md`](06-admin-guide.md) | Nex-Gen staff | `docs/Admin_Operations_Guide.md` |
| [`07-bridge-setup-guide.md`](07-bridge-setup-guide.md) | Customers, installers | `docs/ESP32_Bridge_Setup_Guide.md` |

Shared stylesheet: [`_shared.css`](_shared.css).

---

## Grounding

Every capability described was verified against **shipping code on `main`** (`699a498`, version
`2.5.10+97`, bumped to `+98` for this release), not against the previous generation of docs. Where a
prior guide and the code
disagreed, the code won.

Two grounding decisions worth knowing:

1. **Production flag values, not code defaults.** Four Firestore flags gate scheduling and sync
   features. Their *code* defaults are all `false` — that is the fail-safe fallback, not the live
   value. The guides describe the **deployed** values.
2. **Reachability, not existence.** A screen that exists but that nothing navigates to is not a
   feature. Several large surfaces are built, complete, and unreachable; they are excluded.

---

## Brand rules applied

- Visible brand-name text renders as **Nex-GenLED.com** — hyphen, capital LED.
- Contact is **email only**. No phone numbers anywhere in the set.
- Mantras — *"Beyond the Light."* and *"The System Is the Difference."* — used sparingly, at
  section breaks and closes, never stacked.
- Dealer-facing drafts carry **no margin, cost, price, or profit figures**.
- Palette and type follow `marketing/sell-sheets-2026/SOURCE_OF_TRUTH.md` §4: VOID `#07091A`,
  LUMINA `#00D4FF`, PULSE `#6E2FFF`, CARBON `#111527`, FROST `#DCF0FF`; Exo 2 headings, DM Sans body.

### Internal codenames

`SOURCE_OF_TRUTH.md` §1.F bans the internal codenames from **sell sheets**. That ban is applied to
`01-feature-overview.md`, which is external marketing collateral. The six how-to guides use the
**real in-app names** — "Game Day", "Neighborhood Sync", "Autopilot" — because a how-to guide has to
name the button the reader is looking for.

---

## What changed, and why

### Corrected in this pass

| Change | Reason |
|---|---|
| **No bridge web dashboard.** All "open `http://<bridge-ip>/` and tap Factory Reset" instructions removed. | Firmware serves six `/api/*` endpoints and 404s everything else. It has never served a web page. |
| **Commercial guide rebuilt around the standard app.** | The commercial shell is orphaned — see below. |
| **Schedule limits restated.** Up to 20 saved schedules; 8 controller timer slots. | Two different limits, both real; older docs named only one. |
| **Solar schedules documented as live**, with the coordinate caveat. | Flag is `enabled:true` in production and bench-verified. |
| **Sports Alerts removed as a destination.** | Screen retired; settings moved onto the Game Day team card. |
| **Warranty stated as 5-year product / 1-year labor minimum / 50,000-hour rated life.** | Code-anchored. "Lifetime warranty" is banned phrasing. |
| **Install path is an installer invitation**, not an app-store search. | Not publicly listed yet. |
| **"AR" never used.** Called live preview on your house photo. | There is no AR — no camera path, no AR SDK. |

### Deliberately excluded

Not described anywhere in the set, because a reader cannot use them today:

- **Audio Mode** — `if (kDebugMode && audioSupported)`; absent from every release build.
- **The commercial shell** — `/commercial` and its Dashboard/Fleet/Brand/Events/Profile tabs. The
  route-guard fork that sent commercial customers there was removed; nothing navigates to it now.
- **Commercial onboarding wizard** — eight complete screens, zero callers.
- **Estimate Wizard** (5 steps) and the **material checkout/check-in lifecycle** (4 screens) —
  orphaned, which is why estimates fall back to manually-typed zone prices.
- **Dealer inventory and ordering screens** — four screens, no route, no import.
- **Brand Library admin** — buttons are reachable, but the permission check behind them cannot pass
  for any PIN session the app can create.
- **A Scenes screen, a Favorites screen, an analytics screen** — none exist.

---

## Open items for Tyler

Flagged, not invented. Each needs a decision before publication.

1. **Support mailbox.** The drafts use `support@Nex-GenLED.com`. The repo currently carries
   `support@nexgenled.com`, `support@nex-gen.io`, and `info@Nex-GenLED.com`. Confirm the canonical one.
2. **Bridge factory reset has no working path.** Firmware serves `POST /api/reset`; the app's client
   method targets `/api/bridge/reset` — a path the firmware does not serve — and nothing calls it.
   The bridge guide documents the manual request and marks it installer-level. This is worth fixing
   in code rather than in prose.
3. **Certifications and environmental specs.** No IP rating, UL/ETL/FCC/CE, RoHS, or operating
   temperature claim appears in these drafts, because none is anchored anywhere in the repo.
4. **Neighborhood Sync fanout is off in production.** The guides describe crews as coordinated
   moments among members with the app open. They do not promise unattended control of a neighbor's
   house. If the flag is flipped, that section needs a rewrite.
5. **Screenshots.** None embedded. Capture points are marked `> **Screenshot:**` inline.

---

*Beyond the Light.*
